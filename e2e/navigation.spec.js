import { test, expect } from '@playwright/test';
import { waitForLiveView } from './helpers.js';

const PAGES = [
  { link: 'Flows', url: /\/flows$/ },
  { link: 'Dashboard', url: /\/$/ },
  { link: 'Executions', url: /\/executions$/ },
  { link: 'Dashboard', url: /\/$/ },
  { link: 'API keys', url: /\/api-keys$/ },
  { link: 'Users', url: /\/users$/ },
  { link: 'Members', url: /\/workspace$/ },
  { link: 'Workspaces', url: /\/workspaces$/ },
  { link: 'Dashboard', url: /\/$/ },
];

test.describe('Sidebar navigation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);
  });

  test('moves between pages without a full page reload', async ({ page }) => {
    // A full reload throws this flag away along with the old document.
    await page.evaluate(() => {
      window.__sameDocument = true;
    });

    for (const { link, url } of PAGES) {
      await page.locator('aside nav').getByRole('link', { name: link, exact: true }).click();
      await expect(page).toHaveURL(url, { timeout: 5000 });
      await waitForLiveView(page);

      expect(await page.evaluate(() => window.__sameDocument)).toBe(true);
    }
  });

  test('marks the current page', async ({ page }) => {
    const nav = page.locator('aside nav');
    const current = nav.locator('[aria-current="page"]');

    await expect(current).toHaveCount(1);
    await expect(current).toHaveText('Dashboard');

    await nav.getByRole('link', { name: 'Flows', exact: true }).click();
    await expect(page).toHaveURL(/\/flows$/, { timeout: 5000 });

    await expect(current).toHaveCount(1);
    await expect(current).toHaveText('Flows');
  });
});
