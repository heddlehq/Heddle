import { test, expect } from '@playwright/test';
import { waitForLiveView, loginViaUI, waitSaved } from '../helpers.js';

// Who else is on a flow: their avatar, their cursor, what they select and drag, and
// following them. See presence.js and HeddleUI.FlowPresence.

// It registers someone and opens five pages, which takes a while on a busy machine.
test.describe.configure({ timeout: 150000 });

async function register(browser, inviteUrl) {
  const context = await browser.newContext({ storageState: { cookies: [], origins: [] } });
  const page = await context.newPage();
  const username = `co${Date.now()}${Math.floor(Math.random() * 1000)}`;

  await page.goto(inviteUrl);
  await waitForLiveView(page);
  await page.getByLabel('Username').fill(username);
  await page.getByLabel('Email').fill(`${username}@example.com`);
  await page.getByLabel('Password', { exact: true }).first().fill('password123');
  await page.getByLabel('Confirm password').fill('password123');
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page).toHaveURL(/\/users\/log-in/, { timeout: 10000 });
  await loginViaUI(page, username, 'password123');

  return { context, page, username };
}

test('people on a flow see each other, where they point and what they drag', async ({ page, browser, request }) => {
  await page.goto('/flows');
  await waitForLiveView(page);
  // The flow and the invite are in the workspace the admin works in. Switching it here
  // would move the other tests, which share the admin, to another one.
  await page.getByRole('button', { name: 'New Flow' }).first().click();
  await expect(page).toHaveURL(/\/flows\/\d+$/, { timeout: 15000 });
  const flowPath = new URL(page.url()).pathname;
  await waitForLiveView(page);
  await waitSaved(page);

  // A node to point at, added on the canvas.
  await page.locator('#flow-canvas').click({ button: 'right', position: { x: 400, y: 300 } });
  await page.locator('.fixed.z-\\[200\\]').getByText('Create Node').click();
  await expect(page.locator('[phx-click=close_create_node_modal]').first()).toBeVisible({ timeout: 5000 });
  await page.locator('[phx-click=create_node_from_modal][phx-value-name="Logger"]').click();
  await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });
  await page.waitForTimeout(300);
  await waitSaved(page);

  await page.goto('/workspace');
  await waitForLiveView(page);
  await page.locator('#invite-form select').selectOption('editor');
  await page.getByRole('button', { name: 'Get invite link' }).click();
  await expect(page.locator('input#invite-url')).toBeVisible({ timeout: 5000 });
  const inviteUrl = await page.locator('input#invite-url').inputValue();
  const other = await register(browser, inviteUrl);

  await page.goto(flowPath);
  await waitForLiveView(page);
  await waitSaved(page);
  await other.page.goto(flowPath);
  await waitForLiveView(other.page);
  await waitSaved(other.page);
  await expect(other.page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });

  // Each sees the other's avatar, not their own.
  await expect(page.locator('#presence-avatars .presence-avatar')).toHaveCount(1, { timeout: 10000 });
  await expect(other.page.locator('#presence-avatars .presence-avatar')).toHaveCount(1, { timeout: 10000 });

  // The other's cursor shows, with their name.
  const canvas = other.page.locator('#flow-canvas');
  const box = await canvas.boundingBox();
  await other.page.mouse.move(box.x + 200, box.y + 150);
  await other.page.mouse.move(box.x + 260, box.y + 180, { steps: 5 });
  const cursor = page.locator('.remote-cursor');
  await expect(cursor).toHaveCount(1, { timeout: 5000 });
  await expect(cursor).toContainText(other.username);

  // What they select is ringed in their color.
  await other.page.locator('custom-node .circular-node').click();
  await expect(page.locator('custom-node.remote-marked')).toHaveCount(1, { timeout: 5000 });

  // What they drag moves here as they drag it, and lands where they drop it.
  const node = other.page.locator('custom-node .circular-node');
  const nodeBox = await node.boundingBox();
  const where = () => page.locator('custom-node').evaluate((el) => { let e = el; while (e && !e.style?.transform) e = e.parentElement; return e ? e.style.transform : ''; });
  const before = await where();
  expect(before).toContain('translate');
  await other.page.mouse.move(nodeBox.x + nodeBox.width / 2, nodeBox.y + nodeBox.height / 2);
  await other.page.mouse.down();
  await other.page.mouse.move(nodeBox.x + 150, nodeBox.y + 90, { steps: 12 });
  await expect.poll(where, { timeout: 5000 }).not.toBe(before);
  await other.page.mouse.up();
  await waitSaved(other.page);

  // Following them keeps their cursor in view.
  await page.locator('#presence-avatars .presence-avatar').click();
  await expect(page.locator('#presence-avatars .presence-avatar.is-following')).toHaveCount(1);

  // Someone who leaves is gone.
  await other.context.close();
  await expect(page.locator('#presence-avatars .presence-avatar')).toHaveCount(0, { timeout: 10000 });
  await expect(page.locator('.remote-cursor')).toHaveCount(0);
});
