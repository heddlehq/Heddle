import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation } from '../helpers.js';

// Groups only arrange the flows page. Each test makes its own group and flow, so the
// shared admin's other flows don't matter.
test.describe('Flow groups', () => {
  test.describe.configure({ timeout: 60000 });

  async function newFlow(page) {
    await page.goto('/flows');
    await waitForLiveView(page);
    await clickAndWaitForNavigation(
      page,
      page.getByRole('button', { name: 'New Flow' }),
      /\/flows\/.+/,
    );
    return page.url().split('/').pop();
  }

  async function newGroup(page, name) {
    await page.goto('/flows');
    await waitForLiveView(page);
    await page.locator('#new-group').click();
    await page.locator('#new-group-form input[name="group[name]"]').fill(name);
    await page.getByRole('button', { name: 'Create group' }).click();
    const group = page
      .locator('section[data-group]')
      .filter({ has: page.locator('header', { hasText: name }) });
    await expect(group).toBeVisible({ timeout: 5000 });
    return group;
  }

  test('moves a flow into a group from its menu, and back out', async ({ page }) => {
    const flowId = await newFlow(page);
    const name = `Sales ${Date.now()}`;
    const group = await newGroup(page, name);
    const groupId = await group.getAttribute('data-group');

    await page.locator(`#flow-${flowId}-move`).click();
    await page.locator(`#flow-${flowId}-move-${groupId}`).click();
    await expect(group.locator(`#flow-${flowId}`)).toBeVisible({ timeout: 5000 });

    // It stays there after a reload.
    await page.reload();
    await waitForLiveView(page);
    await expect(page.locator(`#flow-group-${groupId} #flow-${flowId}`)).toBeVisible();

    await page.locator(`#flow-${flowId}-move`).click();
    await page.locator(`#flow-${flowId}-move-none`).click();
    await expect(page.locator(`#flow-group-none #flow-${flowId}`)).toBeVisible({ timeout: 5000 });
  });

  test('moves a flow dragged onto a group', async ({ page }) => {
    const flowId = await newFlow(page);
    // Two groups whose names sort together, so both are on screen while dragging.
    const stamp = Date.now();
    const from = await newGroup(page, `Drag ${stamp} A`);
    const to = await newGroup(page, `Drag ${stamp} B`);
    const fromId = await from.getAttribute('data-group');

    await page.locator(`#flow-${flowId}-move`).click();
    await page.locator(`#flow-${flowId}-move-${fromId}`).click();
    await expect(from.locator(`#flow-${flowId}`)).toBeVisible({ timeout: 5000 });

    await page.locator(`#flow-${flowId}`).dragTo(to.locator('header'));
    await expect(to.locator(`#flow-${flowId}`)).toBeVisible({ timeout: 5000 });
  });

  test('folds a group, and deleting it keeps its flows', async ({ page }) => {
    const flowId = await newFlow(page);
    const name = `Leads ${Date.now()}`;
    const group = await newGroup(page, name);
    const groupId = await group.getAttribute('data-group');

    await page.locator(`#flow-${flowId}-move`).click();
    await page.locator(`#flow-${flowId}-move-${groupId}`).click();
    await expect(group.locator(`#flow-${flowId}`)).toBeVisible({ timeout: 5000 });

    await page.locator(`#flow-group-${groupId}-toggle`).click();
    await expect(group.locator(`#flow-${flowId}`)).toBeHidden();
    await page.locator(`#flow-group-${groupId}-toggle`).click();
    await expect(group.locator(`#flow-${flowId}`)).toBeVisible();

    page.once('dialog', (dialog) => dialog.accept());
    await group.locator('header').hover();
    await page.locator(`#flow-group-${groupId}-delete`).click();

    await expect(page.locator(`#flow-group-${groupId}`)).toHaveCount(0, { timeout: 5000 });
    await expect(page.locator(`#flow-${flowId}`)).toBeVisible();
  });
});
