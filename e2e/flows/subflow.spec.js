import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation, waitSaved } from '../helpers.js';

async function newFlow(page) {
  await page.goto('/flows');
  await waitForLiveView(page);
  await clickAndWaitForNavigation(page, page.getByRole('button', { name: 'New Flow' }), /\/flows\/.+/);
  await waitForLiveView(page);
  return page.url().split('/').pop();
}

async function addNodeViaContextMenu(page, nodeName) {
  await page.locator('#flow-canvas').click({ button: 'right' });
  const menu = page.locator('.fixed.z-\\[200\\]');
  await expect(menu).toBeVisible({ timeout: 3000 });
  await menu.getByText('Create Node').click();
  await page.locator(`[phx-click=create_node_from_modal][phx-value-name="${nodeName}"]`).click();
  await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });
}

async function openDrawer(page) {
  const node = page.locator('custom-node').first();
  await node.hover();
  await node.locator('.node-action-btn.config').click();
  await expect(page.locator('#node-config-form')).toBeVisible({ timeout: 5000 });
}

test.describe('Subflow', () => {
  test.describe.configure({ timeout: 90000 });

  test('picks the flow to run in the drawer, and keeps it', async ({ page }) => {
    const calleeId = await newFlow(page);
    const callerId = await newFlow(page);
    expect(callerId).not.toBe(calleeId);

    await addNodeViaContextMenu(page, 'Subflow');
    await openDrawer(page);

    const picker = page.locator('#node-flow-subflow_id');
    // The flow open in the editor can't call itself.
    await expect(picker.locator(`option[value="${callerId}"]`)).toHaveCount(0);
    await picker.selectOption(calleeId);
    await expect(page.locator('#node-flow-open-subflow_id')).toHaveAttribute('href', `/flows/${calleeId}`);

    await page.locator('#close-node-config').click();
    await waitSaved(page);
    await page.reload();
    await waitForLiveView(page);
    await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });

    await openDrawer(page);
    await expect(page.locator('#node-flow-subflow_id')).toHaveValue(calleeId);
  });
});
