// Prints the median of each measurement across the rounds in results/.
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = join(dirname(fileURLToPath(import.meta.url)), 'results');
const rounds = readdirSync(dir)
  .filter((file) => file.endsWith('.json'))
  .map((file) => JSON.parse(readFileSync(join(dir, file), 'utf8')));

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
};

const tools = [...new Set(rounds.flatMap((round) => round.results.map((result) => result.tool)))];

const rows = tools.map((tool) => {
  const runs = rounds.map((round) => round.results.find((result) => result.tool === tool));
  const pick = (read) => median(runs.map(read));
  const perSecond = runs.map((run) => run.burst.completedPerSecond);

  return {
    tool: runs[0].name,
    version: runs[0].version,
    completedPerSecond: Math.round(pick((run) => run.burst.completedPerSecond)),
    range: [Math.min(...perSecond), Math.max(...perSecond)],
    finished: runs.every((run) => run.burst.completed >= run.burst.sent - run.burst.rejected),
    completed: runs.map((run) => run.burst.completed),
    acceptedPerSecond: pick((run) => run.burst.acceptedPerSecond),
    oneRunMs: pick((run) => run.sequential.p50),
    oneRunP95Ms: pick((run) => run.sequential.p95),
    idleMemoryMb: pick((run) => run.idleMemoryMb),
    peakMemoryMb: pick((run) => run.burst.peakMemoryMb),
    diskMb: pick((run) => run.diskMb),
    bootSeconds: pick((run) => run.bootSeconds),
  };
});

rows.sort((a, b) => b.completedPerSecond - a.completedPerSecond);
console.log(JSON.stringify(rows, null, 2));
