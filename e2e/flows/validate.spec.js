import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation, waitSaved } from '../helpers.js';

async function addNode(page, nodeName, position) {
  const before = await page.locator('custom-node').count();
  await page.locator('#flow-canvas').click({ button: 'right', position });
  const menu = page.locator('.fixed.z-\\[200\\]');
  await expect(menu).toBeVisible({ timeout: 3000 });
  await menu.getByText('Create Node').click();
  await page.locator(`[phx-click=create_node_from_modal][phx-value-name="${nodeName}"]`).click();
  await expect(page.locator('custom-node')).toHaveCount(before + 1, { timeout: 5000 });
}

async function openDrawer(page, label) {
  const node = page.locator('custom-node').filter({ hasText: label }).first();
  await node.hover();
  await node.locator('.node-action-btn.config').click();
  await expect(page.locator('#node-config-form')).toBeVisible({ timeout: 5000 });
}

test.describe('Validate', () => {
  test.describe.configure({ timeout: 90000 });

  test.beforeEach(async ({ page }) => {
    await page.goto('/flows');
    await waitForLiveView(page);
    await clickAndWaitForNavigation(page, page.getByRole('button', { name: 'New Flow' }), /\/flows\/.+/);
    await waitForLiveView(page);
  });

  test('edits the rules as fields, with a message in each language, and keeps them', async ({ page }) => {
    await addNode(page, 'Validate', { x: 300, y: 250 });
    await openDrawer(page, 'Validate');

    await expect(page.locator('#validate-rule-key-0')).toHaveValue('name');
    await page.locator('#validate-rule-min-0').fill('3');
    await page.locator('#validate-rule-message-0-pt_BR').fill('Seu nome é curto demais');
    await page.locator('#validate-rule-add').click();
    await expect(page.locator('#validate-rule-key-2')).toHaveValue('field_3');

    await page.locator('#close-node-config').click();
    await waitSaved(page);
    await page.reload();
    await waitForLiveView(page);
    await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });

    await openDrawer(page, 'Validate');
    await expect(page.locator('#validate-rule-min-0')).toHaveValue('3');
    await expect(page.locator('#validate-rule-message-0-pt_BR')).toHaveValue('Seu nome é curto demais');
    await expect(page.locator('#validate-rule-key-2')).toHaveValue('field_3');
  });

  test('starts from the fields of the form', async ({ page }) => {
    await addNode(page, 'Form Trigger', { x: 200, y: 200 });
    await waitSaved(page);
    await addNode(page, 'Validate', { x: 500, y: 350 });
    await openDrawer(page, 'Validate');

    page.once('dialog', (dialog) => dialog.accept());
    await page.locator('#validate-use-form').click();

    // The fields a new Form Trigger comes with.
    await expect(page.locator('#validate-rule-type-1')).toHaveValue('email', { timeout: 5000 });
    await expect(page.locator('#node-field-validation_data')).toHaveValue('{{form}}');
  });
});
