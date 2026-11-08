import { test, expect } from '@playwright/test';
import { waitForLiveView, loginViaUI } from './helpers.js';

test.describe.configure({ timeout: 60000 });

async function register(browser, inviteUrl) {
  const context = await browser.newContext({ storageState: { cookies: [], origins: [] } });
  const page = await context.newPage();
  const stamp = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
  const username = `ws${stamp}`;

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

async function switchTo(page, name) {
  await page.locator('#workspace-switcher-button').click();
  await page.getByRole('menuitem', { name: new RegExp(name) }).click();
  await expect(page.locator('#workspace-switcher-button')).toContainText(name, { timeout: 10000 });
}

test.describe('Workspaces', () => {
  test('a system admin creates a workspace and switches between them', async ({ page }) => {
    const name = `Team ${Date.now()}`;

    await page.goto('/workspaces');
    await waitForLiveView(page);
    await page.getByLabel('Name').fill(name);
    await page.getByRole('button', { name: 'Create' }).click();

    await expect(page).toHaveURL(/\/workspace$/, { timeout: 10000 });
    await expect(page.locator('#workspace-name')).toHaveText(name);
    await expect(page.locator('#workspace-switcher-button')).toContainText(name);

    await page.goto('/flows');
    await waitForLiveView(page);
    await expect(page.getByText('No flows created yet')).toBeVisible();

    await switchTo(page, 'Default');
    await expect(page).toHaveURL(/\/flows$/);
  });

  test('an invited viewer sees a flow without being able to change or run it', async ({ page, browser }) => {
    await page.goto('/flows');
    await waitForLiveView(page);
    await switchTo(page, 'Default');
    await page.getByRole('button', { name: 'New Flow' }).first().click();
    await expect(page).toHaveURL(/\/flows\/\d+$/, { timeout: 15000 });
    const flowUrl = new URL(page.url()).pathname;

    await page.goto('/workspace');
    await waitForLiveView(page);
    await page.locator('#invite-form select').selectOption('viewer');
    await page.getByRole('button', { name: 'Get invite link' }).click();
    await expect(page.locator('input#invite-url')).toBeVisible({ timeout: 5000 });
    await expect(page.getByText('as Viewer')).toBeVisible();
    const inviteUrl = await page.locator('input#invite-url').inputValue();

    const viewer = await register(browser, inviteUrl);
    await viewer.page.goto(flowUrl);
    await waitForLiveView(viewer.page);

    await expect(viewer.page.locator('#flow-read-only')).toBeVisible({ timeout: 10000 });
    await expect(viewer.page.getByRole('button', { name: 'Run Flow' })).toHaveCount(0);
    await expect(viewer.page.locator('#canvas-tools')).toHaveCount(0);
    await expect(viewer.page.locator('#flow-canvas')).toHaveAttribute('data-read-only', 'true');

    await viewer.page.goto('/workspace');
    await waitForLiveView(viewer.page);
    await expect(viewer.page.locator('#add-member-form')).toHaveCount(0);
    await expect(viewer.page.locator('#workspace-members')).toContainText(viewer.username);
    await viewer.context.close();

    await page.goto('/workspace');
    await waitForLiveView(page);
    await expect(page.locator('#workspace-members')).toContainText(viewer.username);
  });

  test('a person outside every workspace is told to ask for one', async ({ browser }) => {
    const admin = await browser.newContext({ storageState: 'e2e/.auth/user.json' });
    const adminPage = await admin.newPage();
    const name = `Leaving ${Date.now()}`;

    await adminPage.goto('/workspaces');
    await waitForLiveView(adminPage);
    await adminPage.getByLabel('Name').fill(name);
    await adminPage.getByRole('button', { name: 'Create' }).click();
    await expect(adminPage).toHaveURL(/\/workspace$/, { timeout: 10000 });
    await adminPage.locator('#invite-form select').selectOption('editor');
    await adminPage.getByRole('button', { name: 'Get invite link' }).click();
    const inviteUrl = await adminPage.locator('input#invite-url').inputValue();

    const person = await register(browser, inviteUrl);
    await person.page.goto('/workspace');
    await waitForLiveView(person.page);
    person.page.once('dialog', (dialog) => dialog.accept());
    await person.page.getByTitle('Leave').click();

    await expect(person.page).toHaveURL(/\/$/, { timeout: 10000 });
    await expect(person.page.getByText('Ask an admin to add you')).toBeVisible();
    await expect(person.page.locator('#nav-flows')).toHaveCount(0);

    await person.context.close();
    await admin.close();
  });
});
