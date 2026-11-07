import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation } from '../helpers.js';

async function createApiKey(page) {
  await page.goto('/api-keys');
  await waitForLiveView(page);

  await page.locator('#api_key_name').fill(`e2e ${Date.now()}`);
  await page.locator("input[name='api_key[scopes][]'][value='workflows:read']").check();
  await page.locator("input[name='api_key[scopes][]'][value='workflows:write']").check();
  await page.getByRole('button', { name: 'Generate API key' }).click();

  const token = page.locator('input[readonly]').first();
  await expect(token).toBeVisible({ timeout: 5000 });
  return token.inputValue();
}

async function openNewFlow(page) {
  await page.goto('/flows');
  await waitForLiveView(page);

  await clickAndWaitForNavigation(
    page,
    page.getByRole('button', { name: 'New Flow' }),
    /\/flows\/.+/,
  );
  await waitForLiveView(page);
  await expect(page.locator('#flow-canvas')).toBeVisible({ timeout: 5000 });

  return page.url().split('/').pop();
}

async function dragNode(page, node) {
  const box = await node.boundingBox();
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;

  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + 60, y + 40, { steps: 5 });
  await page.mouse.up();
}

test.describe('Flow written outside the canvas', () => {
  test.describe.configure({ timeout: 60000 });

  let token;
  let flowId;
  let headers;

  test.beforeEach(async ({ page, request }) => {
    token = await createApiKey(page);
    flowId = await openNewFlow(page);
    headers = { Authorization: `Bearer ${token}` };

    // No positions and no target input: neither is needed to describe a flow.
    const response = await request.put(`/api/v1/workflows/${flowId}`, {
      headers,
      data: {
        workflow: {
          nodes: [
            { id: 'hook', type: 'Webhook', label: 'Receive Input', controls: {} },
            {
              id: 'log',
              type: 'Logger',
              label: 'Write Log',
              controls: { set_by_api: 'kept', retries: 0 },
            },
            { id: 'end', type: 'Output', label: 'Final Output', controls: {} },
          ],
          connections: [
            { source: 'hook', sourceOutput: 'exec', target: 'log' },
            { source: 'hook', sourceOutput: 'exec', target: 'end' },
          ],
        },
      },
    });
    expect(response.status(), await response.text()).toBe(200);

    await expect(page.locator('custom-node')).toHaveCount(3, { timeout: 5000 });
  });

  test('has nothing to save when it is just opened', async ({ page }) => {
    await page.reload();
    await waitForLiveView(page);
    await expect(page.locator('custom-node')).toHaveCount(3, { timeout: 5000 });

    await expect(page.getByText('You have unsaved changes')).toHaveCount(0);
  });

  test('has something to save once a node moves', async ({ page }) => {
    await page.reload();
    await waitForLiveView(page);
    await expect(page.locator('custom-node')).toHaveCount(3, { timeout: 5000 });

    await dragNode(page, page.locator('custom-node .circular-node').first());

    await expect(page.getByText('You have unsaved changes')).toBeVisible({ timeout: 3000 });
  });

  test('gets its nodes placed apart from each other', async ({ page }) => {
    const boxes = await Promise.all(
      (await page.locator('custom-node').all()).map((node) => node.boundingBox()),
    );
    const spots = boxes.map((box) => `${Math.round(box.x)}:${Math.round(box.y)}`);

    expect(new Set(spots).size).toBe(3);
  });

  test('shows the name of each node without hovering, and it cannot be selected', async ({
    page,
  }) => {
    const name = page.locator('custom-node .node-name').filter({ hasText: 'Receive Input' });

    await expect(name).toBeVisible();
    await expect(name).toHaveCSS('user-select', 'none');

    await dragNode(page, page.locator('custom-node .circular-node').first());

    expect(await page.evaluate(() => window.getSelection().toString())).toBe('');
  });

  test('keeps everything the canvas does not show when saved', async ({ page, request }) => {
    await dragNode(page, page.locator('custom-node .circular-node').first());
    await page.getByRole('button', { name: 'Save Changes' }).click();
    await expect(page.getByText('You have unsaved changes')).not.toBeVisible();

    const response = await request.get(`/api/v1/workflows/${flowId}`, { headers });
    const { data } = await response.json();
    const nodes = Object.fromEntries(data.nodes.map((node) => [node.id, node]));

    expect(nodes.log.controls.set_by_api).toBe('kept');
    expect(nodes.log.controls.retries).toBe(0);
    expect(nodes.hook.controls).not.toHaveProperty('code_elixir');
    expect(nodes.hook.position).toEqual({ x: expect.any(Number), y: expect.any(Number) });
    expect(data.connections.map((connection) => connection.target)).toEqual(['log', 'end']);
  });
});

test.describe('Testing a webhook', () => {
  test.describe.configure({ timeout: 60000 });

  test.beforeEach(async ({ page, request }) => {
    const token = await createApiKey(page);
    const flowId = await openNewFlow(page);

    const response = await request.put(`/api/v1/workflows/${flowId}`, {
      headers: { Authorization: `Bearer ${token}` },
      data: {
        workflow: {
          nodes: [
            { id: 'hook', type: 'Webhook', label: 'Receive', controls: {} },
            {
              id: 'sum',
              type: 'Evaluate Code',
              label: 'Sum',
              controls: {
                language: 'elixir',
                code_elixir: 'variable(:body)["x"] + variable(:body)["y"]',
              },
            },
          ],
          connections: [{ source: 'hook', sourceOutput: 'exec', target: 'sum' }],
        },
      },
    });
    expect(response.status(), await response.text()).toBe(200);
    await expect(page.locator('custom-node')).toHaveCount(2, { timeout: 5000 });

    await page.getByRole('button', { name: 'Run Flow' }).click();
    await expect(page.locator('#webhook-test-form')).toBeVisible({ timeout: 5000 });
  });

  test('suggests the fields the flow reads and shows their type', async ({ page }) => {
    const rows = page.locator('#webhook-body-editor [data-row]');
    await expect(rows).toHaveCount(2);

    const value = rows.first().getByRole('textbox', { name: 'x' });
    await value.fill('10');
    await expect(rows.first().locator('[data-type]')).toHaveText('number');

    await value.fill('hello');
    await expect(rows.first().locator('[data-type]')).toHaveText('string');

    await value.fill('true');
    await expect(rows.first().locator('[data-type]')).toHaveText('boolean');
  });

  test('keeps the parameters and the JSON in sync', async ({ page }) => {
    const editor = page.locator('#webhook-body-editor');

    await editor.locator('[data-row]').first().getByRole('textbox', { name: 'x' }).fill('10');
    await editor.getByRole('button', { name: 'JSON' }).click();

    await expect(editor.locator('.monaco-editor')).toBeVisible({ timeout: 10000 });
    await expect(editor.locator('.view-lines')).toContainText('"x"');
    const colors = await editor.locator('.view-lines span span').evaluateAll((spans) =>
      new Set(spans.map((span) => getComputedStyle(span).color)).size,
    );
    expect(colors).toBeGreaterThan(1);

    await editor.getByRole('button', { name: 'Parameters' }).click();
    await expect(editor.locator('[data-row]').first().getByRole('textbox', { name: 'x' })).toHaveValue('10');
  });

  test('refuses to leave the JSON while it is broken', async ({ page }) => {
    const editor = page.locator('#webhook-body-editor');
    await editor.getByRole('button', { name: 'JSON' }).click();
    await expect(editor.locator('.monaco-editor')).toBeVisible({ timeout: 10000 });

    await editor.locator('.monaco-editor textarea').first().focus();
    await page.keyboard.press('Control+A');
    await page.keyboard.type('{nope');

    await editor.getByRole('button', { name: 'Parameters' }).click();

    await expect(editor.locator('[data-error]')).toBeVisible();
  });

  test('runs with what was filled in', async ({ page }) => {
    await page.locator('#webhook-body-editor [data-row]').first().getByRole('textbox', { name: 'x' }).fill('2');
    await page.locator('#webhook-test-run').click();

    await expect(page.locator('#webhook-test-form')).toHaveCount(0);
    await expect(page.getByText('Execution queued')).toBeVisible({ timeout: 5000 });
  });
});

// Only on a local install, with the claude program in the PATH of the server. The setting
// is global, so these run in order.
test.describe('Terminal', () => {
  test.describe.configure({ mode: 'serial', timeout: 60000 });

  const setTerminal = async (page, enabled) => {
    await page.goto('/ai');
    await waitForLiveView(page);

    const toggle = page.locator('#terminal-toggle');
    test.skip(await toggle.isDisabled(), 'This server has no terminal');

    if ((await toggle.getAttribute('aria-checked')) !== String(enabled)) await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', String(enabled), { timeout: 5000 });
  };

  test('only shows in the editor when turned on', async ({ page }) => {
    await setTerminal(page, false);
    await openNewFlow(page);

    await expect(page.locator('#terminal-open-button')).toHaveCount(0);
  });

  test('opens and keeps running while hidden', async ({ page }) => {
    await setTerminal(page, true);
    await openNewFlow(page);

    await page.locator('#terminal-open-button').click();
    await expect(page.locator('#terminal-screen .xterm')).toBeVisible({ timeout: 10000 });

    // It takes the place of the canvas, and leaves the sidebar alone.
    const panel = await page.locator('#terminal-panel').boundingBox();
    const sidebar = await page.locator('aside').first().boundingBox();
    const canvas = await page.locator('#flow-canvas-container').boundingBox();
    expect(panel.x).toBeGreaterThanOrEqual(sidebar.x + sidebar.width - 1);
    expect(canvas.y + canvas.height).toBeLessThanOrEqual(panel.y + 1);

    await page.getByTitle('Hide').click();
    await expect(page.locator('#terminal-panel')).toBeHidden();

    await page.locator('#terminal-open-button').click();
    await expect(page.locator('#terminal-screen .xterm')).toBeVisible();

    await setTerminal(page, false);
  });
});

