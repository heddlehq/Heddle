# Comparing Heddle with other workflow tools

We wrote this test, and Heddle is in it, so don't take our word for it. Everything here is meant to be checked and rerun. Raw numbers are in [`results/`](results/).

## What it measures

Every tool runs the same job: a webhook triggers a flow with one step, an HTTP POST to a small server outside the tool.

Most of these tools answer a webhook before doing the work, so requests per second only shows who says "got it" fastest. **A run counts when its call reaches that outside server.** That judge is the same for every tool.

| Measurement | How |
|---|---|
| Runs per second | 20,000 webhook calls from 50 connections. Runs that reached the server, divided by the time until the last one arrived. |
| One run | 100 calls, one at a time, each waiting for the previous run to arrive. Median. |
| Idle memory | Sum of all the tool's containers, Postgres included, 20 seconds after setup. |
| Peak memory | The same sum, sampled every second during the 20,000 calls. |
| Disk | Size of the images, each counted once. |
| Boot | From `docker compose up` to the first healthy answer, on an empty database. |
| Runs per second, slow target | A second pass with a target that takes 100 ms to answer, 3,000 calls. Results are in [`results/slow/`](results/slow/). |

## How it runs

- GitHub's `ubuntu-24.04` runners: 4 vCPUs and 16 GB. No tool runs at the same time as another.
- Three rounds on three machines, in random order. The figures we publish are medians.
- Every tool keeps its defaults, Heddle included. The `compose.yml` in each folder under `tools/` is the whole configuration.
- A tool gets 5 minutes. Anything still queued then is not counted, and is not treated as lost either.

To run it, start the `Benchmark` workflow, or run `node benchmark/compare/run.mjs` on a machine that has Docker. `node benchmark/compare/summarize.mjs` prints the medians.

An instant target hides how many runs a tool keeps going at once, because no run ever waits. A real API takes a while, and a tool that runs five at a time then does five per round trip. That's why the slow target is there: `TARGET_DELAY_MS=100 BURST=3000 RESULTS_DIR=slow node benchmark/compare/run.mjs`, and `node benchmark/compare/summarize.mjs slow` for its medians.

`crash.mjs` is a separate test: it kills each tool in the middle of a load, restarts it and checks, call by call, whether the work it had accepted was lost or repeated, and whether any run stayed unfinished. The target takes 100 ms to answer, so that work piles up. Heddle runs with `OBAN_RESCUE_AFTER_MINUTES=1` here instead of its default of 60, because the test can't wait an hour.

## What it does not tell you

- **The flow is trivial.** Two steps and a tiny body. It says nothing about long flows, big payloads, code steps, or runs that fail.
- **These tools don't do the same things.** Heddle has eight kinds of step and no ready-made connectors. n8n has more than 500 integrations and years in production. A tool that does more per run may pay for it here.
- **Node-RED wins, and it is doing less.** It keeps no run history and holds work in memory, so a crash loses what was in flight.
- **Defaults aren't limits.** Any of these can be tuned. We added no workers beyond each tool's default, which is one for Heddle and n8n in queue mode and several for Windmill, so the numbers say nothing about how each tool scales.
- **Shared machines are noisy.** Results change between rounds, and the machines weren't identical. Small differences mean nothing.
- **Zapier and Make are missing,** because a hosted service can't run on the same machine.

## What we changed after the first run

The first version ran 3,000 calls, and Heddle's lead over n8n looked too good. Heddle finished in 11 seconds, and we had compared n8n's single process with Heddle's split UI and worker. So, before publishing, we:

- raised the load to 20,000 calls, so a short peak couldn't pass for sustained speed;
- added n8n's queue mode, the closest match to how Heddle runs;
- fixed a bug that counted an image once per service in the disk size.

The first version's raw results are in [`results/first-version/`](results/first-version/).

## Details worth knowing

- Activepieces and n8n in queue mode hit the 5-minute limit in all three rounds, so their runs per second reflect that window.
- In one round, n8n's server received 19,996 of the 20,000 calls.
- Windmill runs a TypeScript script on its native worker, its fast path for this kind of job, instead of a visual flow.
- Heddle's HTTP step sets `headers` the way the editor saves it. Leaving it out made the run fail with nothing in the worker's log, which is a Heddle bug we found here.
- The ratios on the site come from `heddleTimes` in `summarize.mjs`, compared inside each round. Rounds can land on different hardware, so dividing medians from different rounds overstates or understates the gap.
