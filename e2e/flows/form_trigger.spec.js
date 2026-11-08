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

test.describe('Form Trigger', () => {
  test.describe.configure({ timeout: 90000 });

  test.beforeEach(async ({ page }) => {
    await page.goto('/flows');
    await waitForLiveView(page);
    await clickAndWaitForNavigation(page, page.getByRole('button', { name: 'New Flow' }), /\/flows\/.+/);
    await waitForLiveView(page);
    await addNodeViaContextMenu(page, 'Form Trigger');
  });

  test('builds the form in the drawer, and keeps the fields', async ({ page }) => {
    await openDrawer(page);

    await expect(page.locator('#form-link-url')).toHaveValue(/\/f\//);
    await expect(page.locator('#form-link-unpublished')).toBeVisible();
    await expect(page.locator('#form-field-label-0')).toHaveValue('Name');

    await page.locator('#form-field-add').click();
    await expect(page.locator('#form-field-label-3')).toBeVisible();
    await page.locator('#form-field-label-3').fill('Company size');
    await expect(page.locator('#form-field-key-3')).toHaveValue('company_size', { timeout: 5000 });

    await page.locator('#close-node-config').click();
    await waitSaved(page);
    await openDrawer(page);
    await expect(page.locator('#form-field-label-3')).toHaveValue('Company size');
  });

  test('once published, anyone with the link fills it in', async ({ page, browser }) => {
    await openDrawer(page);
    const url = await page.locator('#form-link-url').inputValue();
    await page.locator('#close-node-config').click();
    await waitSaved(page);

    await page.locator('#publish-flow').dispatchEvent('click');
    await page.locator('#publish-submit').click();
    await expect(page.locator('#flow-publish-status')).toHaveAttribute('data-status', 'published', { timeout: 5000 });

    // Someone who isn't signed in.
    const visitor = await browser.newContext({ storageState: { cookies: [], origins: [] } });
    const form = await visitor.newPage();
    await form.goto(new URL(url).pathname);

    await expect(form.locator('#form-title')).toHaveText('Contact us');
    await form.locator('#form_name').fill('Ana');
    await form.locator('#form_email').fill('not an email');
    await form.locator('#form_email').evaluate((el) => el.form.noValidate = true);
    await form.locator('#form-submit').click();
    await expect(form.getByText('Enter a valid email address.')).toBeVisible();

    await form.locator('#form_email').fill('ana@example.com');
    await form.locator('#form-submit').click();
    await expect(form.locator('#form-sent')).toBeVisible();
    await visitor.close();
  });
});
