import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation } from '../helpers.js';

async function createApiKey(page) {
  await page.goto('/api-keys');
  await waitForLiveView(page);

  await page.locator('#api_key_name').fill(`e2e ${Date.now()}`);
  await page.locator("input[name='api_key[scopes][]'][value='workflows:read']").check();
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

const node = (id, type, label) => ({ id, type, label, controls: {} });

// A flash sits over the header until it is closed, so its buttons are clicked
// directly.
const press = (page, selector) => page.locator(selector).dispatchEvent('click');

test.describe('Flow versions', () => {
  test.describe.configure({ timeout: 60000 });

  test('publishes the draft, and previews what a version changed', async ({ page, request }) => {
    const token = await createApiKey(page);
    const flowId = await openNewFlow(page);
    const headers = { Authorization: `Bearer ${token}` };

    await expect(page.locator('#flow-publish-status')).toHaveAttribute('data-status', 'unpublished');

    const write = async (nodes) => {
      const response = await request.put(`/api/v1/workflows/${flowId}`, {
        headers,
        data: { workflow: { nodes, connections: [] } },
      });
      expect(response.status(), await response.text()).toBe(200);
    };

    await write([node('start', 'Start', 'Begin')]);
    await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });

    // Publishing takes what the canvas has.
    await page.locator('#publish-flow').click();
    await page.locator('#publish_note').fill('First version');
    await page.locator('#publish-submit').click();
    await expect(page.locator('#flow-publish-status')).toHaveAttribute('data-status', 'published', { timeout: 5000 });

    // A change made elsewhere is only the draft.
    await write([node('start', 'Start', 'Begin'), node('end', 'Output', 'Finish')]);
    await expect(page.locator('custom-node')).toHaveCount(2, { timeout: 5000 });
    await expect(page.locator('#flow-publish-status')).toHaveAttribute('data-status', 'changed');

    await press(page, '#publish-flow');
    await page.locator('#publish-submit').click();
    await expect(page.locator('#flow-publish-status')).toHaveAttribute('data-status', 'published', { timeout: 5000 });

    await press(page, '#open-versions');
    const history = page.locator('#version-history');
    await expect(history).toBeVisible();
    await expect(history.getByText('First version')).toBeVisible();

    // The newest version added the Output node: the preview marks it.
    await history.locator("[id^='version-preview-']").first().click();
    const preview = page.locator("[id^='version-preview-canvas-']");
    await expect(preview.locator('custom-node')).toHaveCount(2, { timeout: 5000 });
    await expect(preview.locator('.circular-node.diff-added')).toHaveCount(1);

    // The draft under it is untouched.
    await page.locator('#version-preview-close').click();
    await expect(page.locator('#version-preview-layer')).toHaveCount(0);
    await expect(page.locator('#flow-canvas custom-node')).toHaveCount(2);
  });
});
