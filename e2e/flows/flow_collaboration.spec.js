import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation, waitSaved } from '../helpers.js';

// Two people on the same flow: each sees what the other does, and undo takes back only
// one's own changes. See collab.js and HeddleCore.Flows.Session.

async function addNode(page, nodeName, at) {
  await page.locator('#flow-canvas').click({ button: 'right', position: at });

  const menu = page.locator('.fixed.z-\\[200\\]');
  await expect(menu).toBeVisible({ timeout: 3000 });
  await menu.getByText('Create Node').click();

  await expect(page.locator('[phx-click=close_create_node_modal]').first()).toBeVisible({ timeout: 5000 });
  await page.locator(`[phx-click=create_node_from_modal][phx-value-name="${nodeName}"]`).click();
  await waitSaved(page);
}

async function open(page, url) {
  await page.goto(url);
  await waitForLiveView(page);
  await expect(page.locator('#flow-canvas')).toBeVisible({ timeout: 5000 });
  await waitSaved(page);
}

const names = (page) => page.locator('#flow-canvas custom-node .node-name');

test.describe('Editing a flow together', () => {
  test.describe.configure({ timeout: 60000 });

  test('each sees what the other does, and undoes only their own', async ({ page, browser }) => {
    await page.goto('/flows');
    await waitForLiveView(page);
    await clickAndWaitForNavigation(page, page.getByRole('button', { name: 'New Flow' }), /\/flows\/.+/);
    await waitForLiveView(page);
    await waitSaved(page);
    const url = page.url();

    const other = await browser.newContext({ storageState: 'e2e/.auth/user.json' });
    const them = await other.newPage();
    await open(them, url);

    // What one adds appears for the other, with no save and no reload.
    await addNode(page, 'Logger', { x: 200, y: 200 });
    await expect(names(them)).toHaveCount(1, { timeout: 5000 });

    await addNode(them, 'Output', { x: 500, y: 300 });
    await expect(names(page)).toHaveCount(2, { timeout: 5000 });

    // Undo takes back the Logger this person added, not the Output the other did.
    await page.keyboard.press('Control+z');
    await waitSaved(page);

    await expect(names(page)).toHaveCount(1, { timeout: 5000 });
    await expect(names(them)).toHaveCount(1, { timeout: 5000 });
    await expect(names(them).first()).not.toHaveText(/Log/);

    // And redo brings it back for both.
    await page.keyboard.press('Control+y');
    await waitSaved(page);
    await expect(names(them)).toHaveCount(2, { timeout: 5000 });

    // What everyone did is saved.
    await page.reload();
    await waitForLiveView(page);
    await expect(names(page)).toHaveCount(2, { timeout: 5000 });

    await other.close();
  });
});
