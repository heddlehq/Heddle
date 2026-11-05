// Runs one round of the comparison. See README.md for what it measures and why.
import { exec as execCb, execSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const exec = promisify(execCb);
const here = dirname(fileURLToPath(import.meta.url));

const SEQUENTIAL = Number(process.env.SEQUENTIAL ?? 100);
const WARMUP = Number(process.env.WARMUP ?? 20);
const BURST = Number(process.env.BURST ?? 20000);
const CONCURRENCY = Number(process.env.CONCURRENCY ?? 50);
const DRAIN_LIMIT_MS = Number(process.env.DRAIN_LIMIT_MS ?? 300_000);
const SETTLE_MS = Number(process.env.SETTLE_MS ?? 20_000);
const BOOT_LIMIT_MS = 300_000;
const SINK_PORT = 9099;
const ROUND = process.env.ROUND ?? '0';
const TOOLS = (process.env.TOOLS ?? 'heddle,n8n,n8n-queue,node-red,windmill,activepieces,kestra').split(',');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const sh = (command, options = {}) =>
  execSync(command, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 26, ...options });

// The judge. Work counts when it arrives here, outside the tool under test.
const sink = { hits: 0, first: 0, last: 0, waiter: null };

http
  .createServer((request, response) => {
    request.resume();
    request.on('end', () => {
      sink.hits += 1;
      sink.last = performance.now();
      if (!sink.first) sink.first = sink.last;
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end('{}');
      sink.waiter?.();
    });
  })
  .listen(SINK_PORT, '0.0.0.0');

const resetSink = () => Object.assign(sink, { hits: 0, first: 0, last: 0 });

const agent = new http.Agent({ keepAlive: true, maxSockets: CONCURRENCY });

const post = (url) =>
  new Promise((resolve) => {
    const started = performance.now();
    const request = http.request(
      url,
      { method: 'POST', agent, headers: { 'content-type': 'application/json' }, timeout: 30_000 },
      (response) => {
        response.resume();
        response.on('end', () =>
          resolve({ ok: response.statusCode < 300, status: response.statusCode, ms: performance.now() - started }),
        );
      },
    );
    request.on('timeout', () => request.destroy(new Error('timeout')));
    request.on('error', () => resolve({ ok: false, status: 0, ms: performance.now() - started }));
    request.end('{"bench":true}');
  });

const percentile = (values, p) => {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return Math.round(sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))] * 10) / 10;
};

const nextHit = (seen, limit) =>
  new Promise((resolve) => {
    if (sink.hits > seen) return resolve(true);
    const timer = setTimeout(() => {
      sink.waiter = null;
      resolve(false);
    }, limit);
    sink.waiter = () => {
      if (sink.hits > seen) {
        clearTimeout(timer);
        sink.waiter = null;
        resolve(true);
      }
    };
  });

// One request at a time: how long until the work is really done.
const sequential = async (url, count) => {
  const times = [];
  let failed = 0;

  for (let i = 0; i < count; i += 1) {
    const seen = sink.hits;
    const started = performance.now();
    const response = await post(url);
    const arrived = response.ok && (await nextHit(seen, 20_000));
    if (arrived) times.push(performance.now() - started);
    else failed += 1;
  }

  return { times, failed };
};

const memoryOf = async (project) => {
  const { stdout } = await exec(`docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}'`);
  const units = { B: 1, KiB: 1024, MiB: 1024 ** 2, GiB: 1024 ** 3 };

  return stdout
    .trim()
    .split('\n')
    .filter((line) => line.startsWith(project))
    .reduce((total, line) => {
      const [, value, unit] = line.split('|')[1].match(/^([\d.]+)(\w+)/) ?? [];
      return total + Number(value) * (units[unit] ?? 0);
    }, 0);
};

const burst = async (url, project) => {
  resetSink();

  let peak = 0;
  let sampling = true;
  const sampler = (async () => {
    while (sampling) {
      peak = Math.max(peak, await memoryOf(project));
      await sleep(1000);
    }
  })();

  const acks = [];
  let rejected = 0;
  let sent = 0;
  const started = performance.now();

  await Promise.all(
    Array.from({ length: CONCURRENCY }, async () => {
      while (sent < BURST) {
        sent += 1;
        const response = await post(url);
        acks.push(response.ms);
        if (!response.ok) rejected += 1;
      }
    }),
  );

  const accepted = performance.now();
  const expected = BURST - rejected;

  // Wait for the queue to drain, or for the tool to stop making progress.
  let seen = -1;
  let quietSince = performance.now();
  while (sink.hits < expected && performance.now() - started < DRAIN_LIMIT_MS) {
    if (sink.hits !== seen) {
      seen = sink.hits;
      quietSince = performance.now();
    }
    if (performance.now() - quietSince > 60_000) break;
    await sleep(100);
  }

  sampling = false;
  await sampler;

  const seconds = ((sink.last || accepted) - started) / 1000;

  return {
    sent: BURST,
    rejected,
    completed: sink.hits,
    ackP50: percentile(acks, 50),
    ackP95: percentile(acks, 95),
    ackP99: percentile(acks, 99),
    acceptedPerSecond: Math.round(BURST / ((accepted - started) / 1000)),
    completedPerSecond: Math.round((sink.hits / seconds) * 10) / 10,
    seconds: Math.round(seconds * 10) / 10,
    peakMemoryMb: Math.round(peak / 1024 ** 2),
  };
};

const waitForHealth = async (health) => {
  const started = performance.now();

  while (performance.now() - started < BOOT_LIMIT_MS) {
    const ready = await new Promise((resolve) => {
      const request = http.get(health, { timeout: 2000 }, (response) => {
        response.resume();
        resolve(response.statusCode < 400);
      });
      request.on('timeout', () => request.destroy());
      request.on('error', () => resolve(false));
    });
    if (ready) return performance.now() - started;
    await sleep(250);
  }

  throw new Error(`no answer from ${health}`);
};

const runTool = async (tool) => {
  const dir = join(here, 'tools', tool);
  const meta = JSON.parse(readFileSync(join(dir, 'meta.json'), 'utf8'));
  const project = `bench-${tool}`;
  const compose = `docker compose -p ${project} -f ${join(dir, 'compose.yml')}`;
  const result = { tool, ...meta };

  try {
    console.log(`\n=== ${tool}: pulling`);
    sh(`${compose} pull --quiet --ignore-pull-failures`);

    // A service can reuse another's image, and Docker stores it only once.
    const images = [...new Set(sh(`${compose} config --images`).trim().split('\n'))];
    result.images = images.map((image) => ({
      image,
      id: sh(`docker image inspect --format '{{.Id}}' ${image}`).trim().slice(7, 19),
    }));
    result.diskMb = Math.round(
      images.reduce((sum, image) => sum + Number(sh(`docker image inspect --format '{{.Size}}' ${image}`)), 0) / 1024 ** 2,
    );

    console.log(`=== ${tool}: booting`);
    const booting = performance.now();
    sh(`${compose} up -d`);
    await waitForHealth(meta.health);
    result.bootSeconds = Math.round((performance.now() - booting) / 100) / 10;

    console.log(`=== ${tool}: setting up, ready after ${result.bootSeconds}s`);
    const output = sh(`bash setup.sh`, { cwd: dir, env: { ...process.env, COMPOSE: compose } });
    const url = output.trim().split('\n').pop();
    console.log(`=== ${tool}: webhook ${url.replace(/token=.*/, 'token=...')}`);

    await sleep(SETTLE_MS);
    result.idleMemoryMb = Math.round((await memoryOf(project)) / 1024 ** 2);

    console.log(`=== ${tool}: warm up`);
    const warm = await sequential(url, WARMUP);
    if (warm.times.length === 0) {
      const debug = join(dir, 'debug.sh');
      if (existsSync(debug)) console.log(sh(`bash debug.sh`, { cwd: dir, env: { ...process.env, COMPOSE: compose } }));
      throw new Error('no warm up request reached the sink');
    }

    console.log(`=== ${tool}: one at a time`);
    const single = await sequential(url, SEQUENTIAL);
    result.sequential = {
      count: SEQUENTIAL,
      failed: single.failed,
      p50: percentile(single.times, 50),
      p95: percentile(single.times, 95),
      p99: percentile(single.times, 99),
    };

    console.log(`=== ${tool}: burst`);
    await sleep(2000);
    result.burst = await burst(url, project);
    console.log(JSON.stringify({ sequential: result.sequential, burst: result.burst }));
  } catch (error) {
    result.error = String(error.stderr || error.message).slice(0, 1500);
    console.log(`=== ${tool}: FAILED\n${result.error}`);
    try {
      console.log(sh(`${compose} logs --tail 40`).slice(-5000));
    } catch {}
  }

  try {
    sh(`${compose} down -v --remove-orphans`);
  } catch {}

  return result;
};

// Order changes every round, so no tool always gets the warmest machine.
const shuffled = TOOLS.map((tool) => [Math.random(), tool])
  .sort(([a], [b]) => a - b)
  .map(([, tool]) => tool);

const results = [];
for (const tool of shuffled) results.push(await runTool(tool));

mkdirSync(join(here, 'results'), { recursive: true });
writeFileSync(
  join(here, 'results', `round-${ROUND}.json`),
  JSON.stringify(
    {
      round: ROUND,
      finishedAt: new Date().toISOString(),
      order: shuffled,
      machine: { cpus: os.cpus().length, model: os.cpus()[0]?.model, memoryGb: Math.round(os.totalmem() / 1024 ** 3) },
      settings: { SEQUENTIAL, WARMUP, BURST, CONCURRENCY, DRAIN_LIMIT_MS },
      results,
    },
    null,
    2,
  ),
);
process.exit(0);
