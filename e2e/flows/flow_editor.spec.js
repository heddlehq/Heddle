import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation } from '../helpers.js';

test.describe('Flow Editor', () => {
  test.describe.configure({ timeout: 60000 });

  test.beforeEach(async ({ page }) => {
    await page.goto('/flows');
    await waitForLiveView(page);

    await clickAndWaitForNavigation(
      page,
      page.getByRole('button', { name: 'New Flow' }),
      /\/flows\/.+/,
    );

    await waitForLiveView(page);
  });

  test('displays flow editor header with flow name', async ({ page }) => {
    await expect(page.locator('header')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Run Flow' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Flows' })).toBeVisible();
  });

  test('displays node sidebar with categories', async ({ page }) => {
    await expect(page.locator('aside')).toBeVisible();
    await expect(page.getByText('Nodes')).toBeVisible();
    await expect(page.getByText('Flow Control')).toBeVisible();
    await expect(page.getByText('Utility')).toBeVisible();
  });

  test('displays rete editor canvas', async ({ page }) => {
    await expect(page.locator('#rete-container')).toBeVisible();
    await expect(page.locator('#rete')).toBeVisible();
  });

  test('navigates back to flows list', async ({ page }) => {
    await page.getByRole('link', { name: 'Flows' }).click();
    await expect(page).toHaveURL(/\/flows$/, { timeout: 10000 });
  });

  test.describe('Context Menu', () => {
    test('shows Undo, Redo and Create Node on empty canvas right-click', async ({ page }) => {
      const rete = page.locator('#rete');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await expect(menu.getByText('Undo')).toBeVisible();
      await expect(menu.getByText('Redo')).toBeVisible();
      await expect(menu.getByText('Create Node')).toBeVisible();
    });

    test('does not show Copy, Paste or Delete on empty canvas', async ({ page }) => {
      const rete = page.locator('#rete');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await expect(menu.getByText('Copy')).not.toBeVisible();
      await expect(menu.getByText('Paste')).not.toBeVisible();
      await expect(menu.getByText('Delete')).not.toBeVisible();
    });

    test('closes context menu on Escape', async ({ page }) => {
      const rete = page.locator('#rete');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await page.keyboard.press('Escape');
      await expect(menu).not.toBeVisible({ timeout: 3000 });
    });

    test('closes context menu on left-click outside', async ({ page }) => {
      const rete = page.locator('#rete');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await page.locator('header').click();
      await expect(menu).not.toBeVisible({ timeout: 3000 });
    });

    test('Create Node option triggers create node modal', async ({ page }) => {
      const rete = page.locator('#rete');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await menu.getByText('Create Node').click();
      await expect(menu).not.toBeVisible({ timeout: 3000 });
    });

    test('second right-click replaces the context menu', async ({ page }) => {
      const rete = page.locator('#rete');

      await rete.click({ button: 'right', position: { x: 50, y: 50 } });
      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await rete.click({ button: 'right', position: { x: 300, y: 300 }, force: true });
      await expect(menu).toHaveCount(1);
      await expect(menu).toBeVisible();
    });

    test('shows Copy and Delete when a node is selected', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Logger');

      const node = page.locator('custom-node').first();
      await expect(node).toBeVisible({ timeout: 5000 });
      await node.click();

      const rete = page.locator('#rete');
      await rete.click({ button: 'right', force: true });
      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await expect(menu.getByText('Copy')).toBeVisible();
      await expect(menu.getByText('Delete')).toBeVisible();
    });

    test('copy and paste duplicates a node', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Logger');

      const node = page.locator('custom-node').first();
      await expect(node).toBeVisible({ timeout: 5000 });
      await node.click();

      const rete = page.locator('#rete');
      await rete.click({ button: 'right', force: true });
      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });
      await menu.getByText('Copy').click();

      await rete.click({ button: 'right', position: { x: 200, y: 200 }, force: true });
      await expect(menu).toBeVisible({ timeout: 3000 });
      await expect(menu.getByText('Paste')).toBeVisible();
      await menu.getByText('Paste').click();

      await expect(page.locator('custom-node')).toHaveCount(2, { timeout: 5000 });
    });

    test('copy with Ctrl+C and paste with Ctrl+V', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Logger');

      const node = page.locator('custom-node').first();
      await expect(node).toBeVisible({ timeout: 5000 });
      await node.click();

      await page.keyboard.press('Control+c');
      await page.keyboard.press('Control+v');

      await expect(page.locator('custom-node')).toHaveCount(2, { timeout: 5000 });
    });

    test('Paste is not shown when nothing has been copied', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Logger');

      const rete = page.locator('#rete');
      await rete.click({ button: 'right', force: true });
      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await expect(menu.getByText('Paste')).not.toBeVisible();
    });

    test('Delete removes selected node via context menu', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Logger');

      const node = page.locator('custom-node').first();
      await expect(node).toBeVisible({ timeout: 5000 });
      await node.click();

      const rete = page.locator('#rete');
      await rete.click({ button: 'right', force: true });
      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });
      await menu.getByText('Delete').click();

      await expect(page.locator('custom-node')).toHaveCount(0, { timeout: 5000 });
    });
  });

  test.describe('Code Editor', () => {
    const openCodeEditor = async (page) => {
      const node = page.locator('custom-node').first();
      await node.hover();
      await node.locator('.node-action-btn.config').click();
      await page.locator('#edit-code-code').click();
      await expect(page.locator('#code-editor-wrapper .monaco-editor')).toBeVisible({ timeout: 5000 });
    };

    const typeCode = async (page, code) => {
      await page.locator('#code-editor-wrapper .monaco-editor').click();
      await page.keyboard.type(code);
    };

    test('loads the editor from the app itself', async ({ page }) => {
      const external = [];
      page.on('request', (request) => {
        if (request.url().includes('monaco') && !request.url().startsWith('http://localhost')) {
          external.push(request.url());
        }
      });

      await addNodeViaContextMenu(page, 'Evaluate Code');
      await openCodeEditor(page);

      expect(external).toEqual([]);
    });

    test('keeps the code of each language when switching tabs', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Evaluate Code');
      await openCodeEditor(page);
      await typeCode(page, '3 + 3');

      await page.locator('button[phx-value-tab=python]').click();
      await expect(page.locator('#code-editor-wrapper')).toHaveAttribute('data-language', 'python');
      await typeCode(page, 'print(42)');

      await page.locator('button[phx-value-tab=elixir]').click();
      await expect(page.locator('#code-editor-wrapper')).toHaveAttribute('data-language', 'elixir');

      await expect(page.locator('#code_elixir_textarea')).toHaveValue('3 + 3');
      await expect(page.locator('#code_python_textarea')).toHaveValue('print(42)');
    });

    test('shows the saved code in the node drawer', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Evaluate Code');
      await openCodeEditor(page);
      await typeCode(page, '3 + 3');

      await page.locator('#code-editor-form').getByRole('button', { name: 'Save Changes' }).click();

      await expect(page.locator('#node-code-preview-code')).toContainText('3 + 3');
    });

    test('still shows the code when the editor cannot load', async ({ page }) => {
      await page.route('**/vendor/monaco/**', (route) => route.abort());
      await page.reload();
      await waitForLiveView(page);

      await addNodeViaContextMenu(page, 'Evaluate Code');
      const node = page.locator('custom-node').first();
      await node.hover();
      await node.locator('.node-action-btn.config').click();
      await page.locator('#edit-code-code').click();

      const field = page.locator('#code_elixir_textarea');
      await expect(field).toBeVisible({ timeout: 5000 });
      await field.fill('1 + 1');
      await page.locator('#code-editor-form').getByRole('button', { name: 'Save Changes' }).click();

      await expect(page.locator('#node-code-preview-code')).toContainText('1 + 1');
    });
  });
});

async function addNodeViaContextMenu(page, nodeName) {
  const rete = page.locator('#rete');
  await rete.click({ button: 'right' });

  const menu = page.locator('.fixed.z-\\[200\\]');
  await expect(menu).toBeVisible({ timeout: 3000 });
  await menu.getByText('Create Node').click();

  const modal = page.locator('[phx-click=close_create_node_modal]').first();
  await expect(modal).toBeVisible({ timeout: 5000 });

  await page.locator(`[phx-click=create_node_from_modal][phx-value-name="${nodeName}"]`).click();
  await page.waitForTimeout(1000);
}
