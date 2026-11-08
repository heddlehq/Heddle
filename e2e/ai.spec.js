import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation } from './helpers.js';

test.describe('AI', () => {
  test('is reached from the sidebar', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    await clickAndWaitForNavigation(page, page.locator('#nav-ai'), /\/ai$/);

    await expect(page.getByRole('heading', { name: 'AI', exact: true })).toBeVisible();
    await expect(page.locator('#llm-status')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('#mcp-command')).toContainText('claude mcp add');
  });
});

async function createApiKey(page) {
  await page.goto('/api-keys');
  await waitForLiveView(page);

  await page.locator('#api_key_name').fill(`e2e ${Date.now()}`);
  await page.locator("input[name='api_key[scopes][]'][value='workflows:write']").check();
  await page.getByRole('button', { name: 'Generate API key' }).click();

  const token = page.locator('#api-key-token');
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

test.describe('Flow changed outside the editor', () => {
  test.describe.configure({ timeout: 60000 });

  test('appears on the open canvas', async ({ page, request }) => {
    const token = await createApiKey(page);
    const flowId = await openNewFlow(page);

    await expect(page.locator('custom-node')).toHaveCount(0);

    const response = await request.put(`/api/v1/workflows/${flowId}`, {
      headers: { Authorization: `Bearer ${token}` },
      data: {
        workflow: {
          nodes: [
            {
              id: 'external',
              type: 'Logger',
              label: 'Added elsewhere',
              controls: {},
              position: { x: 120, y: 120 },
            },
          ],
          connections: [],
        },
      },
    });
    expect(response.status(), await response.text()).toBe(200);

    await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });
  });
});

// Needs the server started with HEDDLE_CLAUDE_BIN pointing to a stand-in for claude
// and any HEDDLE_CLAUDE_API_KEY. The setting is global, so these run in order.
test.describe('Claude Agent', () => {
  test.describe.configure({ mode: 'serial', timeout: 60000 });

  const setAgent = async (page, enabled) => {
    await page.goto('/ai');
    await waitForLiveView(page);

    const toggle = page.locator('#claude-agent-toggle');
    if ((await toggle.getAttribute('aria-checked')) !== String(enabled)) {
      await toggle.click();
    }
    await expect(toggle).toHaveAttribute('aria-checked', String(enabled), { timeout: 5000 });
  };

  test('answers in the editor chat once turned on', async ({ page }) => {
    await page.goto('/ai');
    await waitForLiveView(page);
    test.skip(
      await page.locator('#claude-agent-toggle').isDisabled(),
      'The server has no HEDDLE_CLAUDE_BIN',
    );

    await setAgent(page, true);
    await openNewFlow(page);

    await page.getByTitle('AI Chat').click();
    const input = page.locator('#chat-input-field');
    await input.fill('hello');
    await input.press('Enter');

    await expect(page.getByText('Agent reply from the fake binary.')).toBeVisible({
      timeout: 10000,
    });

    await setAgent(page, false);
  });
});
