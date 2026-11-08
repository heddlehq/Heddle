// Takes the screenshots and records the videos of the documentation, from a real Heddle.
//
//     MIX_ENV=test mix ecto.reset && MIX_ENV=test PHX_SERVER=true PORT=4010 mix phx.server
//     node docs/media/capture.mjs [http://localhost:4010]
//
// It signs in as the seeded admin, imports the example flows of docs/examples, and
// writes each shot in the light and the dark theme, as WebP, and each video as WebM,
// here in docs/media. Pages show them with `<!-- shot:name | caption -->` and
// `<!-- video:name | caption -->`. Run it again when the editor changes.
import { chromium } from 'playwright';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BASE = process.argv[2] ?? 'http://localhost:4010';
const OUT = dirname(fileURLToPath(import.meta.url));
const EXAMPLES = join(OUT, '..', 'examples');
const VIEWPORT = { width: 1280, height: 780 };
const only = process.env.ONLY?.split(',');

// ---------------------------------------------------------------- helpers

const wait = (page, ms) => page.waitForTimeout(ms);

async function connected(page) {
  await page.waitForFunction(() => window.liveSocket?.isConnected(), null, { timeout: 15000 });
}

async function saved(page) {
  await page.locator('#save-state[data-state="saved"]').waitFor({ state: 'attached', timeout: 10000 });
}

async function login(page) {
  await page.goto(`${BASE}/users/log-in`);
  await connected(page);
  await page.getByRole('textbox', { name: 'Username' }).fill('admin');
  await page.getByRole('textbox', { name: 'Password' }).fill('admin');
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.waitForURL((url) => !url.pathname.includes('log-in'), { timeout: 15000 });
}

async function newFlow(page) {
  await page.goto(`${BASE}/flows`);
  await connected(page);
  await page.getByRole('button', { name: 'New Flow' }).first().click();
  await page.waitForURL(/\/flows\/\d+$/, { timeout: 15000 });
  await connected(page);
  await saved(page);
}

async function rename(page, name) {
  await page.locator('h1', { hasText: /Untitled|Flow/ }).first().hover();
  await page.locator('[phx-click="edit_flow_name"]').first().click();
  await page.locator('#flow-name-input').fill(name);
  await page.locator('#flow-name-input').press('Enter');
  await wait(page, 300);
}

async function importExample(page, name) {
  const flow = await import(join(EXAMPLES, `${name}.json`), { with: { type: 'json' } });
  const chooser = page.waitForEvent('filechooser');
  await page.locator('#flow-menu-button').click();
  await page.locator('#import-flow').click();
  await (await chooser).setFiles({
    name: `${name}.json`,
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(flow.default)),
  });
  await page.locator('custom-node').first().waitFor({ timeout: 10000 });
  await saved(page);
  await rename(page, flow.default.name);
  // Loading fits the flow on the canvas.
  await page.reload();
  await connected(page);
  await page.locator('custom-node').first().waitFor();
  await wait(page, 600);
}

async function node(page, label) {
  return page.locator('custom-node').filter({ hasText: label }).first();
}

async function openDrawer(page, label) {
  const target = await node(page, label);
  await target.hover();
  await target.locator('.node-action-btn.config').click();
  await page.locator('#node-config-form').waitFor();
  await wait(page, 300);
}

async function dismissFlash(page) {
  const close = page.locator('#flash-group button[aria-label], #flash-group [phx-click]').first();
  if (await close.isVisible().catch(() => false)) await close.click();
  await page.locator('#flash-group [role="alert"]').first().waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
  await wait(page, 300);
}

async function expandInspector(page, glideTo = false) {
  if (await page.locator('#run-timeline').isVisible()) return;
  const toggle = page.locator('#run-inspector-toggle');
  if (glideTo) await glide(page, toggle);
  await toggle.click();
  await page.locator('#run-timeline').waitFor();
  await wait(page, 400);
}

// A pointer the videos show, since a headless browser draws none.
const POINTER = () => {
  const install = () => {
    if (document.getElementById('docs-pointer')) return;
    const dot = document.createElement('div');
    dot.id = 'docs-pointer';
    dot.innerHTML =
      '<svg width="22" height="22" viewBox="0 0 24 24"><path d="M4 2l15 9-7 1.6L8.5 20z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
    Object.assign(dot.style, {
      position: 'fixed', left: '0', top: '0', zIndex: '2147483647', pointerEvents: 'none',
      transition: 'transform 0.05s linear', transform: 'translate(-100px,-100px)',
    });
    document.documentElement.appendChild(dot);
    addEventListener('mousemove', (e) => { dot.style.transform = `translate(${e.clientX - 3}px,${e.clientY - 2}px)`; }, true);
    addEventListener('mousedown', () => { dot.firstChild.style.transform = 'scale(0.85)'; }, true);
    addEventListener('mouseup', () => { dot.firstChild.style.transform = ''; }, true);
  };
  if (document.readyState === 'loading') addEventListener('DOMContentLoaded', install);
  else install();
};

// Moves the pointer the way a hand does, then clicks.
async function glide(page, locator, options = {}) {
  const box = await locator.boundingBox();
  const x = box.x + (options.x ?? box.width / 2);
  const y = box.y + (options.y ?? box.height / 2);
  await page.mouse.move(x, y, { steps: 18 });
  await wait(page, 120);
  return { x, y };
}

async function glideClick(page, locator, options = {}) {
  await glide(page, locator, options);
  await locator.click(options.click);
}

async function addNode(page, name, at) {
  const canvas = page.locator('#flow-canvas');
  await glide(page, canvas, at);
  await canvas.click({ button: 'right', position: at });
  await wait(page, 250);
  await glideClick(page, page.locator('.fixed.z-\\[200\\]').getByText('Create Node'));
  const search = page.locator('[phx-keyup="search_nodes"], input[placeholder*="Search"]').last();
  await search.waitFor();
  await search.pressSequentially(name, { delay: 45 });
  await wait(page, 300);
  await glideClick(page, page.locator(`[phx-click=create_node_from_modal][phx-value-name="${name}"]`));
  await page.locator('custom-node').filter({ hasText: name }).first().waitFor();
  await wait(page, 400);
}

async function connect(page, from, to) {
  const output = (await node(page, from)).locator('.socket-container.right .socket').first();
  const input = (await node(page, to)).locator('.socket-container.left .socket').first();
  const a = await glide(page, output);
  await page.mouse.down();
  const box = await input.boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 25 });
  await page.mouse.up();
  await wait(page, 350);
  return a;
}

// ---------------------------------------------------------------- media

const webp = (png, out) => {
  execFileSync('magick', [png, '-resize', '1600x', '-quality', '82', out]);
  rmSync(png);
};

const SHOTS = {
  // The editor with a whole flow, as it opens.
  async editor(page) {
    await newFlow(page);
    await importExample(page, 'support-triage');
  },

  // A node's drawer, with its fields and what it does when it fails.
  async drawer(page) {
    await newFlow(page);
    await importExample(page, 'support-triage');
    await openDrawer(page, 'What is it about?');
  },

  // A run, with the steps it took and what one of them returned.
  async inspector(page) {
    await newFlow(page);
    await importExample(page, 'first-flow');
    await page.getByRole('button', { name: 'Run Flow' }).click();
    await page.locator('#run-inspector').waitFor({ timeout: 15000 });
    await page.locator('#run-inspector-status', { hasText: /Succeeded|Failed/ }).waitFor({ timeout: 30000 });
    await expandInspector(page);
    await page.locator("#run-step-1").click();
    await wait(page, 600);
  },

  // The versions of a flow, after it was published.
  async versions(page) {
    await newFlow(page);
    await importExample(page, 'daily-report');
    // A flash can sit over the header's buttons.
    await page.locator('#publish-flow').dispatchEvent('click');
    const note = page.getByPlaceholder('e.g. Retry the payment call twice');
    await note.fill('First version, for the sales team');
    await page.locator('#publish-submit').click();
    await page.locator('#flow-publish-status[data-status="published"]').waitFor({ timeout: 10000 });
    await dismissFlash(page);
    await page.locator('#flow-menu-button').click();
    await page.locator('#open-versions').click();
    await page.locator('#version-history').waitFor();
    await wait(page, 500);
  },

  // Publishing, with a note on what changed.
  async publish(page) {
    await newFlow(page);
    await importExample(page, 'daily-report');
    await page.locator('#publish-flow').dispatchEvent('click');
    await page.getByPlaceholder('e.g. Retry the payment call twice').fill('First version, for the sales team');
    await wait(page, 300);
  },

  // Trying a flow that starts at a webhook.
  async webhook(page) {
    await newFlow(page);
    await importExample(page, 'webhook-to-slack');
    await page.getByRole('button', { name: 'Run Flow' }).click();
    await page.locator('#webhook-test-modal').waitFor();
    await wait(page, 400);
  },

  // The list of flows.
  async flows(page) {
    await page.goto(`${BASE}/flows`);
    await connected(page);
    await wait(page, 500);
  },
};

const VIDEOS = {
  // Building a flow from nothing: nodes, wires, a field, a run and what it did.
  async 'first-flow'(page) {
    await newFlow(page);
    await wait(page, 600);
    await addNode(page, 'Start', { x: 220, y: 300 });
    await addNode(page, 'HTTP Request', { x: 520, y: 300 });
    await addNode(page, 'Output', { x: 820, y: 300 });
    await connect(page, 'Start', 'HTTP Request');
    await connect(page, 'HTTP Request', 'Output');
    await saved(page);

    const http = await node(page, 'HTTP Request');
    await glide(page, http);
    await http.hover();
    await glideClick(page, http.locator('.node-action-btn.config'));
    const url = page.locator('#node-config-form [name="url"]');
    await url.waitFor();
    await glideClick(page, url);
    await url.fill('');
    await url.pressSequentially('https://api.github.com/repos/heddlehq/Heddle', { delay: 35 });
    await wait(page, 500);
    await page.keyboard.press('Escape');
    await saved(page);
    await wait(page, 400);

    await glideClick(page, page.getByRole('button', { name: 'Run Flow' }));
    await page.locator('#run-inspector-status', { hasText: /Succeeded|Failed/ }).waitFor({ timeout: 30000 });
    await wait(page, 600);
    await expandInspector(page, true);
    await glideClick(page, page.locator("#run-step-1"));
    await wait(page, 2500);
  },
};

// ---------------------------------------------------------------- run

const browser = await chromium.launch();

for (const theme of ['light', 'dark']) {
  const prepare = async (context) => {
    await context.addInitScript((t) => {
      localStorage.setItem('phx:theme', t);
      localStorage.setItem('theme', t);
    }, theme);
  };

  for (const [name, take] of Object.entries(SHOTS)) {
    if (only && !only.includes(name)) continue;
    const context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 2, colorScheme: theme });
    await prepare(context);
    const page = await context.newPage();
    await login(page);
    try {
      await take(page);
    } catch (error) {
      await page.screenshot({ path: join(tmpdir(), `failed-${name}.png`) });
      throw error;
    }
    const png = join(tmpdir(), `${name}-${theme}.png`);
    await page.mouse.move(VIEWPORT.width - 40, VIEWPORT.height / 2);
    await wait(page, 200);
    await page.screenshot({ path: png });
    webp(png, join(OUT, `${name}-${theme}.webp`));
    console.log(`shot ${name} ${theme}`);
    await context.close();
  }

  for (const [name, record] of Object.entries(VIDEOS)) {
    if (only && !only.includes(name)) continue;
    // Signs in first, so the video starts on the editor.
    const setup = await browser.newContext({ viewport: VIEWPORT, colorScheme: theme });
    await prepare(setup);
    const first = await setup.newPage();
    await login(first);
    const state = await setup.storageState();
    await setup.close();

    const dir = mkdtempSync(join(tmpdir(), 'heddle-video-'));
    const context = await browser.newContext({
      viewport: VIEWPORT,
      colorScheme: theme,
      storageState: state,
      recordVideo: { dir, size: VIEWPORT },
    });
    await prepare(context);
    await context.addInitScript(POINTER);
    const page = await context.newPage();
    await record(page);
    await context.close();

    const [raw] = readdirSync(dir).filter((file) => file.endsWith('.webm'));
    const out = join(OUT, `${name}-${theme}.webm`);
    // The first second is the empty page loading.
    execFileSync('ffmpeg', [
      '-y', '-loglevel', 'error', '-ss', '1', '-i', join(dir, raw),
      '-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '38', '-row-mt', '1', '-an', out,
    ]);
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-ss', '3', '-i', out, '-frames:v', '1', join(dir, 'poster.png')]);
    webp(join(dir, 'poster.png'), join(OUT, `${name}-${theme}.webp`));
    rmSync(dir, { recursive: true, force: true });
    console.log(`video ${name} ${theme}`);
  }
}

await browser.close();
writeFileSync(join(OUT, 'README.md'), [
  '# Media of the documentation',
  '',
  'Screenshots and videos of Heddle, in the light and the dark theme. `capture.mjs` takes them',
  'from a running Heddle: see the comment at its top. Pages show them with',
  '`<!-- shot:name | caption -->` and `<!-- video:name | caption -->`.',
  '',
].join('\n'));
