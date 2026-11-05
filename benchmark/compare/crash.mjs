// Kills each tool in the middle of a load and checks, call by call, what happened
// to the work it had already accepted. See README.md.
import { execSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ROUND = process.env.ROUND ?? '0';
const CALLS = Number(process.env.CALLS ?? 2000);
const KILL_AT = Number(process.env.KILL_AT ?? 1000);
const CONCURRENCY = Number(process.env.CONCURRENCY ?? 20);
const TARGET_DELAY_MS = Number(process.env.TARGET_DELAY_MS ?? 100);
const QUIET_LIMIT_MS = 60_000;
const RECOVERY_LIMIT_MS = 300_000;
const SINK_PORT = 9099;
const TOOLS = (process.env.TOOLS ?? 'heddle,n8n,n8n-queue,node-red,windmill,activepieces,kestra').split(',');
const MODES = (process.env.MODES ?? 'process,machine').split(',');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const env = { ...process.env, CRASH: '1', FLOWS: 'flows.crash.json' };
const sh = (command, options = {}) =>
  execSync(command, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 26, env, ...options });

// The target takes a moment to answer, like a real API, so work piles up inside
// each tool. Only work that is waiting can be lost.
const seen = new Map();
let lastHit = 0;

http
  .createServer((request, response) => {
    const id = new URL(request.url, 'http://sink').searchParams.get('id');
    request.resume();
    request.on('end', () => {
      seen.set(id, (seen.get(id) ?? 0) + 1);
      lastHit = performance.now();
      setTimeout(() => {
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end('{}');
      }, TARGET_DELAY_MS);
    });
  })
  .listen(SINK_PORT, '0.0.0.0');

const agent = new http.Agent({ keepAlive: true, maxSockets: CONCURRENCY });

const post = (url, id) =>
  new Promise((resolve) => {
    const request = http.request(
      url,
      { method: 'POST', agent, headers: { 'content-type': 'application/json' }, timeout: 10_000 },
      (response) => {
        response.resume();
        response.on('end', () => resolve(response.statusCode < 300));
        response.on('error', () => resolve(false));
      },
    );
    request.on('timeout', () => request.destroy(new Error('timeout')));
    request.on('error', () => resolve(false));
    request.end(JSON.stringify({ id }));
  });

const healthy = (url) =>
  new Promise((resolve) => {
    const request = http.get(url, { timeout: 2000 }, (response) => {
      response.resume();
      resolve(response.statusCode < 400);
    });
    request.on('timeout', () => request.destroy());
    request.on('error', () => resolve(false));
  });

const waitForHealth = async (url) => {
  for (let i = 0; i < 480; i += 1) {
    if (await healthy(url)) return;
    await sleep(250);
  }
  throw new Error(`no answer from ${url}`);
};

const crashTest = async (tool, mode) => {
  const dir = join(here, 'tools', tool);
  const meta = JSON.parse(readFileSync(join(dir, 'meta.json'), 'utf8'));
  const project = `crash-${tool}`;
  const compose = `docker compose -p ${project} -f ${join(dir, 'compose.yml')}`;
  const result = { tool, name: meta.name, version: meta.version, mode };

  try {
    console.log(`\n=== ${tool} / ${mode}: starting`);
    sh(`${compose} pull --quiet --ignore-pull-failures`);
    sh(`${compose} up -d`);
    await waitForHealth(meta.health);

    const url = sh('bash setup.sh', { cwd: dir, env: { ...env, COMPOSE: compose } }).trim().split('\n').pop();
    await sleep(5000);

    seen.clear();
    if (!(await post(url, 'warmup'))) throw new Error('warm up call was refused');
    for (let i = 0; i < 300 && !seen.has('warmup'); i += 1) await sleep(100);
    if (!seen.has('warmup')) {
      try {
        console.log(sh('bash debug.sh', { cwd: dir, env: { ...env, COMPOSE: compose } }));
      } catch {}
      throw new Error('warm up call never reached the target');
    }
    seen.clear();

    const accepted = new Set();
    let next = 0;
    let killed = false;

    const kill = () => {
      killed = true;
      const services = mode === 'process' ? meta.app.join(' ') : '';
      console.log(`=== ${tool} / ${mode}: kill -9 after ${accepted.size} accepted, ${seen.size} done`);
      result.acceptedAtKill = accepted.size;
      result.doneAtKill = seen.size;
      sh(`${compose} kill -s KILL ${services}`);
    };

    await Promise.all(
      Array.from({ length: CONCURRENCY }, async () => {
        while (next < CALLS && !killed) {
          const id = String((next += 1));
          if (await post(url, id)) accepted.add(id);
          if (!killed && accepted.size >= KILL_AT) kill();
        }
      }),
    );
    if (!killed) kill();

    await sleep(3000);
    const restarting = performance.now();
    sh(`${compose} start`);
    await waitForHealth(meta.health);
    result.restartSeconds = Math.round((performance.now() - restarting) / 100) / 10;

    // Give it time to finish what it promised, until nothing has moved for a while.
    lastHit = performance.now();
    const waiting = performance.now();
    const missing = () => [...accepted].filter((id) => !seen.has(id)).length;

    while (
      missing() > 0 &&
      performance.now() - lastHit < QUIET_LIMIT_MS &&
      performance.now() - waiting < RECOVERY_LIMIT_MS
    ) {
      await sleep(500);
    }
    await sleep(5000);

    result.accepted = accepted.size;
    result.lost = missing();
    result.lostPercent = Math.round((result.lost / accepted.size) * 1000) / 10;
    result.duplicated = [...seen.values()].filter((count) => count > 1).length;
    console.log(JSON.stringify(result));

    if (result.lost > 0) {
      try {
        console.log(sh('bash debug.sh', { cwd: dir, env: { ...env, COMPOSE: compose } }));
      } catch {}
    }
  } catch (error) {
    result.error = String(error.stderr || error.message).slice(0, 1200);
    console.log(`=== ${tool} / ${mode}: FAILED\n${result.error}`);
    try {
      console.log(sh(`${compose} logs --tail 25`).slice(-3000));
    } catch {}
  }

  try {
    sh(`${compose} down -v --remove-orphans`);
  } catch {}

  return result;
};

const order = TOOLS.map((tool) => [Math.random(), tool])
  .sort(([a], [b]) => a - b)
  .map(([, tool]) => tool);

const results = [];
for (const tool of order) {
  for (const mode of MODES) results.push(await crashTest(tool, mode));
}

mkdirSync(join(here, 'results', 'crash'), { recursive: true });
writeFileSync(
  join(here, 'results', 'crash', `round-${ROUND}.json`),
  JSON.stringify(
    { round: ROUND, finishedAt: new Date().toISOString(), order, settings: { CALLS, KILL_AT, CONCURRENCY, TARGET_DELAY_MS }, results },
    null,
    2,
  ),
);
process.exit(0);
