import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation, waitSaved } from '../helpers.js';

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

test.describe('Validate', () => {
  test.describe.configure({ timeout: 90000 });

  test('comes with a schema to start from, and keeps the one written', async ({ page }) => {
    await page.goto('/flows');
    await waitForLiveView(page);
    await clickAndWaitForNavigation(page, page.getByRole('button', { name: 'New Flow' }), /\/flows\/.+/);
    await waitForLiveView(page);
    await addNodeViaContextMenu(page, 'Validate');

    await openDrawer(page);
    const schema = page.locator('#node-field-validation_schema');
    await expect(schema).toHaveValue(/"email": "email"/);

    await schema.fill('{"email": "email", "tags": ["string"]}');
    await page.locator('#close-node-config').click();
    await waitSaved(page);
    await page.reload();
    await waitForLiveView(page);
    await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });

    await openDrawer(page);
    await expect(page.locator('#node-field-validation_schema')).toHaveValue('{"email": "email", "tags": ["string"]}');
  });
});
