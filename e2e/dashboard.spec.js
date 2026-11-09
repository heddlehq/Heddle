import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation } from './helpers.js';

test.describe('Dashboard', () => {
  test('displays dashboard heading and stats cards', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
    await expect(page.locator('#stat-runs')).toBeVisible();
    await expect(page.locator('#stat-success-rate')).toBeVisible();
    await expect(page.locator('#stat-failures')).toBeVisible();
    await expect(page.locator('#stat-duration')).toBeVisible();
    await expect(page.locator('#dashboard-activity')).toBeVisible();
  });

  test('shows recent runs, failing flows and flows', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    await expect(page.locator('#dashboard-recent-runs')).toBeVisible();
    await expect(page.locator('#dashboard-attention')).toBeVisible();
    await expect(page.locator('#dashboard-flows')).toBeVisible();
  });

  test('navigates to flows page via Manage Flows button', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    await clickAndWaitForNavigation(
      page,
      page.getByRole('link', { name: 'Manage Flows' }),
      /\/flows/,
    );
    await expect(page.getByRole('heading', { name: 'Flows', exact: true })).toBeVisible();
  });

  test('sidebar has navigation links', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    await expect(page.getByRole('link', { name: 'Dashboard' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Flows', exact: true })).toBeVisible();
  });
});
