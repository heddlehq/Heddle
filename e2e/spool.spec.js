import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation } from './helpers.js';

test.describe('Spool', () => {
  test.describe.configure({ timeout: 60000 });

  test('creates a table, gives it columns and adds a row', async ({ page }) => {
    const name = `leads ${Date.now()}`;

    await page.goto('/spool');
    await waitForLiveView(page);
    await expect(page.locator('#nav-spool')).toHaveAttribute('aria-current', 'page');

    await page.locator('#spool-table-form input[name="table[name]"]').fill(name);
    await clickAndWaitForNavigation(page, page.locator('#spool-table-create'), /\/spool\/\d+\?tab=columns/);
    await waitForLiveView(page);

    await page.locator('#spool-add-column').click();
    await page.locator('#spool-column-name-0').fill('email');
    await page.locator('#spool-add-column').click();
    await page.locator('#spool-column-name-1').fill('score');
    await page.locator('#spool-column-type-1').selectOption('number');
    await page.locator('#spool-columns-save').click();
    await expect(page.getByText('Table saved.')).toBeVisible({ timeout: 5000 });

    await page.locator('#spool-tab-rows').click();
    await page.locator('#spool-new-row').click();
    await page.locator('#spool-row-form input[type=text]').first().fill('ana@example.com');
    await page.locator('#spool-row-form input[type=number]').fill('7');
    await page.locator('#spool-row-save').click();

    await expect(page.locator('#spool-rows')).toContainText('ana@example.com', { timeout: 5000 });
    await expect(page.locator('#spool-rows')).toContainText('7');
  });

  test('moves language and theme to the preferences', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);
    await expect(page.locator('#locale-select')).toHaveCount(0);

    await page.locator('#user-menu-button').click();
    await clickAndWaitForNavigation(page, page.locator('#user-menu-preferences'), /\/users\/preferences/);
    await waitForLiveView(page);

    await page.locator('#theme-light').click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
    await page.locator('#theme-dark').click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  });
});
