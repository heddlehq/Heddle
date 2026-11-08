import { test, expect } from '@playwright/test';
import { waitForLiveView, clickAndWaitForNavigation, waitSaved } from '../helpers.js';

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

  test('displays the canvas', async ({ page }) => {
    await expect(page.locator('#flow-canvas-container')).toBeVisible();
    await expect(page.locator('#flow-canvas')).toBeVisible();
  });

  test('navigates back to flows list', async ({ page }) => {
    await page.getByRole('link', { name: 'Flows' }).click();
    await expect(page).toHaveURL(/\/flows$/, { timeout: 10000 });
  });

  test.describe('Context Menu', () => {
    test('shows Undo, Redo and Create Node on empty canvas right-click', async ({ page }) => {
      const rete = page.locator('#flow-canvas');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await expect(menu.getByText('Undo')).toBeVisible();
      await expect(menu.getByText('Redo')).toBeVisible();
      await expect(menu.getByText('Create Node')).toBeVisible();
    });

    test('does not show Copy, Paste or Delete on empty canvas', async ({ page }) => {
      const rete = page.locator('#flow-canvas');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await expect(menu.getByText('Copy')).not.toBeVisible();
      await expect(menu.getByText('Paste')).not.toBeVisible();
      await expect(menu.getByText('Delete')).not.toBeVisible();
    });

    test('closes context menu on Escape', async ({ page }) => {
      const rete = page.locator('#flow-canvas');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await page.keyboard.press('Escape');
      await expect(menu).not.toBeVisible({ timeout: 3000 });
    });

    test('closes context menu on left-click outside', async ({ page }) => {
      const rete = page.locator('#flow-canvas');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await page.locator('header').click();
      await expect(menu).not.toBeVisible({ timeout: 3000 });
    });

    test('Create Node option triggers create node modal', async ({ page }) => {
      const rete = page.locator('#flow-canvas');
      await rete.click({ button: 'right' });

      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });

      await menu.getByText('Create Node').click();
      await expect(menu).not.toBeVisible({ timeout: 3000 });
    });

    test('second right-click replaces the context menu', async ({ page }) => {
      const rete = page.locator('#flow-canvas');

      await rete.click({ button: 'right', position: { x: 200, y: 150 } });
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

      const rete = page.locator('#flow-canvas');
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

      const rete = page.locator('#flow-canvas');
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

      const rete = page.locator('#flow-canvas');
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

      const rete = page.locator('#flow-canvas');
      await rete.click({ button: 'right', force: true });
      const menu = page.locator('.fixed.z-\\[200\\]');
      await expect(menu).toBeVisible({ timeout: 3000 });
      await menu.getByText('Delete').click();

      await expect(page.locator('custom-node')).toHaveCount(0, { timeout: 5000 });
    });
  });

  test.describe('Create node shortcut', () => {
    test('A opens the search, and Enter adds the first result', async ({ page }) => {
      await page.keyboard.press('a');

      const search = page.locator('#node-search');
      await expect(search).toBeFocused();
      await expect(search).toHaveValue('');

      await search.fill('Logger');
      await expect(page.locator('[phx-click="create_node_from_modal"]')).toHaveCount(1);
      await search.press('Enter');

      await expect(page.locator('custom-node')).toHaveCount(1);
      await expect(search).toHaveCount(0);
    });

    test('Escape closes the search', async ({ page }) => {
      await page.keyboard.press('a');
      await expect(page.locator('#node-search')).toBeFocused();

      await page.keyboard.press('Escape');

      await expect(page.locator('#node-search')).toHaveCount(0);
    });

    test('the context menu shows the shortcut', async ({ page }) => {
      await page.locator('#flow-canvas').click({ button: 'right', position: { x: 200, y: 150 } });

      const item = page.locator('.fixed.z-\\[200\\]').getByRole('button', { name: 'Create Node' });
      await expect(item).toContainText('A');
    });

    test('typing A in a field does not open it', async ({ page }) => {
      await page.locator('#node-sidebar-search').fill('');
      await page.locator('#node-sidebar-search').press('a');
      await page.locator('#add-comment-note').click();
      await page.keyboard.press('a');

      await expect(page.locator('#node-search')).toHaveCount(0);
      await expect(page.locator('custom-comment textarea')).toHaveValue('a');
    });
  });

  test.describe('Comments', () => {
    const note = (page) => page.locator('custom-comment');

    // Where the note is on the canvas, whatever the zoom of the screen.
    const placement = (page) =>
      note(page).evaluate((el) => ({
        position: el.parentElement.parentElement.style.transform,
        size: el.querySelector('.comment-note').getAttribute('style'),
      }));

    const addComment = async (page, text, kind = 'note') => {
      await page.locator(`#add-comment-${kind}`).click();
      const input = note(page).last().locator('textarea');
      await expect(input).toBeFocused();
      await input.fill(text);
      await page.locator('header').click();
      await expect(note(page).last().locator('textarea')).toHaveCount(0);
    };

    const save = (page) => waitSaved(page);

    const dragBy = async (page, locator, dx, dy) => {
      const box = await locator.boundingBox();
      const x = box.x + box.width / 2;
      const y = box.y + box.height / 2;
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.mouse.move(x + dx, y + dy, { steps: 5 });
      await page.mouse.up();
    };

    test('adds a title, a text, a note and a section from the canvas', async ({ page }) => {
      for (const kind of ['title', 'text', 'note', 'section']) {
        await addComment(page, `A ${kind}`, kind);
        await expect(page.locator(`.comment-note[data-kind="${kind}"]`)).toContainText(`A ${kind}`);
      }

      await save(page);
      await page.reload();
      await waitForLiveView(page);

      await expect(note(page)).toHaveCount(4);
      await expect(page.locator('.comment-note[data-kind="title"]')).toContainText('A title');
      await expect(page.locator('.comment-note[data-kind="section"]')).toContainText('A section');
    });

    test('changes the kind and color of a comment, and keeps them', async ({ page }) => {
      await addComment(page, 'Billing');

      await note(page).click();
      await note(page).getByRole('button', { name: 'Title' }).click();
      await note(page).getByRole('button', { name: 'Color green' }).click();
      await save(page);

      await page.reload();
      await waitForLiveView(page);

      await expect(page.locator('.comment-note[data-kind="title"][data-color="green"]')).toContainText('Billing');
    });

    test('grows to fit what is typed', async ({ page }) => {
      await page.locator('#add-comment-text').click();
      const input = note(page).locator('textarea');
      await expect(input).toBeFocused();
      const before = (await note(page).locator('.comment-note').boundingBox()).height;

      await page.keyboard.type('one\ntwo\nthree\nfour\nfive\nsix\nseven\neight');

      const after = (await note(page).locator('.comment-note').boundingBox()).height;
      expect(after).toBeGreaterThan(before);
      expect(await input.evaluate((el) => el.scrollHeight <= el.clientHeight)).toBe(true);
    });

    test('keeps a section below the other comments', async ({ page }) => {
      await addComment(page, 'Group', 'section');
      await addComment(page, 'Inside');

      const layer = (kind) =>
        page.locator(`custom-comment:has(.comment-note[data-kind="${kind}"])`)
          .evaluate((el) => el.parentElement.parentElement.style.zIndex);

      expect(await layer('section')).toBe('-2');
      expect(await layer('note')).toBe('-1');
    });

    test('selects what is inside a section with Shift and a box drawn on it', async ({ page }) => {
      await addComment(page, 'Group', 'section');
      await addComment(page, 'Inside');

      const section = page.locator('.comment-note[data-kind="section"]');
      const inside = page.locator('.comment-note[data-kind="note"]');
      const box = await section.boundingBox();

      await page.keyboard.down('Shift');
      await page.mouse.move(box.x + 10, box.y + box.height - 10);
      await page.mouse.down();
      await page.mouse.move(box.x + box.width - 20, box.y + 40, { steps: 5 });
      await page.mouse.up();
      await page.keyboard.up('Shift');

      await expect(inside).toHaveClass(/is-selected/);
      await expect(section).not.toHaveClass(/is-selected/);
    });

    test('still picks a section with a Shift click', async ({ page }) => {
      await addComment(page, 'Group', 'section');

      const section = page.locator('.comment-note[data-kind="section"]');
      const box = await section.boundingBox();
      await expect(section).not.toHaveClass(/is-selected/);
      await page.keyboard.down('Shift');
      await page.mouse.click(box.x + 10, box.y + box.height - 10);
      await page.keyboard.up('Shift');

      await expect(section).toHaveClass(/is-selected/);
    });

    // A Logger in the middle of the canvas, and a section moved over it.
    const sectionAroundNode = async (page) => {
      await addNodeViaContextMenu(page, 'Logger');
      await addComment(page, 'Billing', 'section');

      const section = page.locator('.comment-note[data-kind="section"]');
      const node = page.locator('custom-node').first();
      const s = await section.boundingBox();
      const n = await node.boundingBox();
      await dragBy(page, section, n.x + n.width / 2 - (s.x + s.width / 2), n.y + n.height / 2 - (s.y + s.height / 2));

      return { section, node };
    };

    test('moves what is inside a section along with it', async ({ page }) => {
      const { section, node } = await sectionAroundNode(page);
      const before = await node.boundingBox();

      await dragBy(page, section, 80, 40);

      const after = await node.boundingBox();
      expect(Math.abs(after.x - before.x - 80)).toBeLessThan(3);
      expect(Math.abs(after.y - before.y - 40)).toBeLessThan(3);
    });

    test('sets a section to run only by hand from its gear, and keeps it', async ({ page }) => {
      await addComment(page, 'Billing', 'section');
      const section = page.locator('.comment-note[data-kind="section"]');

      await page.getByRole('button', { name: 'Section settings' }).click();
      const toggle = page.getByRole('switch', { name: /Run with the flow/ });
      await expect(toggle).toBeChecked();
      await toggle.uncheck();

      await expect(section).toHaveAttribute('data-manual', 'true');
      await expect(section.locator('.section-badge')).toBeVisible();

      await page.locator('header').click();
      await expect(page.locator('.section-settings')).toHaveCount(0);

      await save(page);
      await page.reload();
      await waitForLiveView(page);

      await expect(page.locator('.comment-note[data-kind="section"]')).toHaveAttribute('data-manual', 'true');
    });

    test('cannot run a section with nothing in it', async ({ page }) => {
      await addComment(page, 'Empty', 'section');

      await expect(page.getByRole('button', { name: 'Put nodes in this section to run it' })).toBeDisabled();
    });

    test('runs a section from its play button', async ({ page }) => {
      await sectionAroundNode(page);
      await page.locator('.section-run').hover();

      const run = page.getByRole('button', { name: 'Run section' });
      await expect(run).toBeEnabled();
      await run.click();

      await expect(page.locator('#run-inspector')).toBeVisible({ timeout: 10000 });
    });

    test('adds a comment from the context menu where it was clicked', async ({ page }) => {
      const rete = page.locator('#flow-canvas');
      const canvas = await rete.boundingBox();
      await rete.click({ button: 'right', position: { x: 300, y: 200 } });
      await page.locator('.fixed.z-\\[200\\]').getByText('Add Note').click();

      await expect(note(page).locator('textarea')).toBeFocused();
      const box = await note(page).boundingBox();
      expect(Math.abs(box.x - canvas.x - 300)).toBeLessThan(5);
      expect(Math.abs(box.y - canvas.y - 200)).toBeLessThan(5);
    });

    test('keeps a comment after saving and reloading', async ({ page }) => {
      await addComment(page, 'Calls the billing API\nOnly on weekdays');
      await save(page);

      await page.reload();
      await waitForLiveView(page);

      await expect(note(page)).toContainText('Calls the billing API');
      await expect(note(page)).toContainText('Only on weekdays');
    });

    test('keeps where a comment was moved and its size', async ({ page }) => {
      await addComment(page, 'Moved');
      await save(page);

      await dragBy(page, note(page).locator('.comment-note'), 80, 40);

      await note(page).hover();
      await dragBy(page, note(page).locator('.comment-resize'), 60, 30);
      const before = await placement(page);
      expect(before.size).not.toContain('width: 240px');
      await save(page);

      await page.reload();
      await waitForLiveView(page);

      await expect(note(page)).toBeVisible();
      expect(await placement(page)).toEqual(before);
    });

    test('keeps where a node was moved, without a save button', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Logger');
      await expect(page.locator('custom-node')).toHaveCount(1);
      await save(page);

      await dragBy(page, page.locator('custom-node .circular-node'), 80, 40);
      const where = () => page.locator('custom-node').evaluate((el) => el.parentElement.style.transform);
      const before = await where();
      await page.waitForTimeout(600);
      await save(page);

      await page.reload();
      await waitForLiveView(page);
      await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });
      expect(await where()).toEqual(before);
    });

    test('clicking a comment changes nothing', async ({ page }) => {
      await addComment(page, 'Still');
      await page.waitForTimeout(600);
      await save(page);

      await note(page).click();
      await page.waitForTimeout(600);

      await expect(page.locator('#save-state')).toHaveAttribute('data-state', 'saved');
    });

    test('edits a comment with a double click', async ({ page }) => {
      await addComment(page, 'First');

      await note(page).dblclick();
      const input = note(page).locator('textarea');
      await expect(input).toBeFocused();
      await input.fill('Second');
      await input.press('Escape');

      await expect(note(page)).toContainText('Second');
    });

    test('shows the text as text, not as markup', async ({ page }) => {
      await addComment(page, '<img src=x onerror=alert(1)>');

      await expect(note(page)).toContainText('<img src=x');
      await expect(note(page).locator('img')).toHaveCount(0);
    });

    test('deletes a comment and brings it back with undo', async ({ page }) => {
      await addComment(page, 'Gone');
      await dragBy(page, note(page).locator('.comment-note'), 80, 40);
      await page.waitForTimeout(600);
      const before = await placement(page);

      await note(page).click();
      await note(page).getByRole('button', { name: 'Delete' }).click();
      await expect(note(page)).toHaveCount(0);

      await page.keyboard.press('Control+z');
      await expect(note(page)).toContainText('Gone');
      expect(await placement(page)).toEqual(before);
    });

    test('undoes a change to the text', async ({ page }) => {
      await addComment(page, 'First');

      await note(page).dblclick();
      await note(page).locator('textarea').fill('Second');
      await page.locator('header').click();
      await expect(note(page)).toContainText('Second');

      await page.keyboard.press('Control+z');
      await expect(note(page)).toContainText('First');
    });

    test('copies and pastes a comment with its text', async ({ page }) => {
      await addComment(page, 'Twice');

      await note(page).click();
      await page.keyboard.press('Control+c');
      await page.keyboard.press('Control+v');

      await expect(note(page)).toHaveCount(2);
      await expect(note(page).nth(1)).toContainText('Twice');
    });

    test('copy and paste inside a comment stay in the text', async ({ page }) => {
      await addComment(page, 'Text');

      await note(page).click();
      await page.keyboard.press('Control+c');
      await note(page).dblclick();
      await note(page).locator('textarea').press('Control+v');

      await expect(note(page)).toHaveCount(1);
    });

    test('keeps a comment behind the nodes', async ({ page }) => {
      await page.locator('#flow-canvas').click({ button: 'right', position: { x: 300, y: 200 } });
      await page.locator('.fixed.z-\\[200\\]').getByText('Add Note').click();
      await page.locator('header').click();

      const zIndex = await note(page).evaluate((el) => el.parentElement.parentElement.style.zIndex);
      expect(zIndex).toBe('-1');
    });

    test('does not count as a node of the flow', async ({ page }) => {
      await addComment(page, 'Not a step');
      await save(page);

      await expect(page.locator('custom-node')).toHaveCount(0);

      await page.getByRole('button', { name: 'Run Flow' }).click();
      await expect(page.locator('#run-inspector-status')).toHaveText(/Queued/i);
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

  test.describe('New nodes', () => {
    for (const name of ['Schedule', 'AI Agent', 'For Each', 'Respond to Webhook', 'Slack: Send Message', 'Email: Send Email', 'Email: List Emails', 'Google Sheets: Read Rows', 'Read CSV', 'Write CSV', 'S3: Upload File', 'FTP: Rename or Move', 'AI: Generate Image', 'AI: Edit Image', 'AI: Summarize', 'AI: Transcribe Audio', 'SQL: Run Query', 'SQL: Insert Rows', 'MongoDB: Find Documents', 'Redis: Set Value', 'Elasticsearch: Search', 'DynamoDB: Get Item', 'Cassandra: Run Query', 'Neo4j: Run Query']) {
      test(`adds ${name} from the context menu and saves it`, async ({ page }) => {
        await addNodeViaContextMenu(page, name);

        await expect(page.locator('custom-node')).toHaveCount(1, { timeout: 5000 });
        await waitSaved(page);
      });
    }

    test('groups the actions of a service in the sidebar, with its logo', async ({ page }) => {
      const group = page.locator('#node-category-slack');
      const action = group.locator('[data-node-name="Slack: Send Message"]');

      await expect(group).toBeVisible({ timeout: 5000 });
      await expect(action).toBeHidden();

      await group.getByRole('button', { name: 'Slack', exact: true }).click();

      await expect(action).toBeVisible({ timeout: 5000 });
      await expect(action.locator('.logo-slack')).toBeVisible();
      await expect(group.locator('[data-node-name="Slack: Add Reaction"]')).toBeVisible();
    });

    test('groups the databases in one category, by store', async ({ page }) => {
      const category = page.locator('#node-category-database');

      await category.getByRole('button', { name: 'Database', exact: true }).click();

      for (const store of ['SQL', 'MongoDB', 'Redis', 'Elasticsearch', 'DynamoDB', 'Cassandra', 'Neo4j']) {
        await expect(category.locator(`[id="node-group-${store}"]`)).toBeVisible({ timeout: 5000 });
      }

      await expect(category.locator('[data-node-name="MongoDB: Find Documents"] .logo-mongodb')).toBeVisible();
    });

    test('finds the SQL nodes by the name of a database', async ({ page }) => {
      await page.getByPlaceholder('Search nodes').fill('postgresql');

      await expect(page.locator('[data-node-name="SQL: Run Query"]')).toBeVisible({ timeout: 5000 });
    });

    test('writes a query in a box that takes several lines, and keeps it', async ({ page }) => {
      await addNodeViaContextMenu(page, 'SQL: Run Query');

      const node = page.locator('custom-node').first();
      await node.hover();
      await node.locator('.node-action-btn.config').click();

      const query = page.locator('textarea[name="sql"]');
      await expect(query).toBeVisible({ timeout: 5000 });
      await query.fill('SELECT *\nFROM items\nWHERE id = {{id}}');
      await page.locator('#node-config-form').getByRole('button', { name: 'Save' }).click();
      await expect(query).toBeHidden({ timeout: 5000 });

      await node.hover();
      await node.locator('.node-action-btn.config').click();
      await expect(page.locator('textarea[name="sql"]')).toHaveValue('SELECT *\nFROM items\nWHERE id = {{id}}', { timeout: 5000 });
    });

    test('clears the recent nodes', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Variable');

      const recent = page.locator('#recent-node-group');
      await expect(recent.locator('[data-node-name="Variable"]')).toBeVisible({ timeout: 5000 });

      await recent.getByRole('button', { name: 'Clear' }).click();

      await expect(recent).toBeHidden({ timeout: 5000 });
      await expect(page.locator('custom-node')).toHaveCount(1);
    });

    test('groups HTTP Request under HTTP', async ({ page }) => {
      const group = page.locator('#node-category-http');

      await expect(group.getByRole('button', { name: 'HTTP', exact: true })).toBeVisible({ timeout: 5000 });
      await expect(group.locator('[data-node-name="HTTP Request"]')).toBeVisible();
    });

    test('shows the logo of a service on the canvas', async ({ page }) => {
      await addNodeViaContextMenu(page, 'Google Sheets: Read Rows');

      await expect(page.locator('custom-node .logo-google-sheets')).toBeVisible({ timeout: 5000 });
    });

    test('shows only the fields of the action', async ({ page }) => {
      await addNodeViaContextMenu(page, 'FTP: Rename or Move');

      const node = page.locator('custom-node').first();
      await node.hover();
      await node.locator('.node-action-btn.config').click();

      await expect(page.getByText('New path')).toBeVisible({ timeout: 5000 });
      await expect(page.getByText('Operation')).toHaveCount(0);
      await expect(page.getByText('Content')).toHaveCount(0);
    });

    test('finds the image nodes by the name of the model', async ({ page }) => {
      await page.getByPlaceholder('Search nodes').fill('nano banana');

      await expect(page.locator('[data-node-name="AI: Generate Image"]')).toBeVisible({ timeout: 5000 });
      await expect(page.locator('[data-node-name="AI: Edit Image"]')).toBeVisible();
      await expect(page.locator('[data-node-name="AI: Summarize"]')).toHaveCount(0);
    });

    test('offers only the models of the credential, and says the default', async ({ page }) => {
      const name = `gemini-${Date.now()}`;
      const editor = page.url();

      await page.goto('/credentials');
      await waitForLiveView(page);
      await page.getByLabel('Name').fill(name);
      await page.getByLabel('Service').selectOption('ai');
      await page.locator('#credential-value-provider').selectOption('google');
      await page.locator('#credential-value-api_key').fill('e2e-key');
      await page.locator('#credential-save').click();
      await expect(page.locator('#credentials').getByText(name)).toBeVisible({ timeout: 5000 });

      await page.goto(editor);
      await waitForLiveView(page);
      await addNodeViaContextMenu(page, 'AI: Generate Image');

      const node = page.locator('custom-node').first();
      await node.hover();
      await node.locator('.node-action-btn.config').click();

      const credential = page.locator('#node-credential-credential');
      const model = page.locator('#node-model-model');

      await credential.selectOption(name);

      await expect(model.locator('option').first()).toHaveText('Default: Nano Banana 2.1', { timeout: 5000 });
      await expect(model.locator('option', { hasText: 'Nano Banana Pro' })).toHaveCount(1);
      await expect(model.locator('option', { hasText: 'Gemini 3.8 Flash' })).toHaveCount(0);
      await expect(model).toHaveJSProperty('tagName', 'SELECT');
    });

    test('offers the stored credentials on a node', async ({ page }) => {
      const name = `slack-${Date.now()}`;
      const editor = page.url();

      await page.goto('/credentials');
      await waitForLiveView(page);
      await page.getByLabel('Name').fill(name);
      await page.getByLabel('Bot token').fill('xoxb-e2e');
      await page.locator('#credential-save').click();
      await expect(page.locator('#credentials').getByText(name)).toBeVisible({ timeout: 5000 });

      await page.goto(editor);
      await waitForLiveView(page);
      await addNodeViaContextMenu(page, 'Slack: Send Message');

      const node = page.locator('custom-node').first();
      await node.hover();
      await node.locator('.node-action-btn.config').click();

      const select = page.locator('#node-credential-credential');
      await expect(select.locator('option', { hasText: name })).toHaveCount(1, { timeout: 5000 });
      await select.selectOption(name);
      await expect(select).toHaveValue(name);
    });

    test('shows the outputs of For Each', async ({ page }) => {
      await addNodeViaContextMenu(page, 'For Each');

      const node = page.locator('custom-node').first();
      await expect(node.locator('custom-socket')).toHaveCount(3, { timeout: 5000 });
    });
  });

  test.describe('Import', () => {
    const flow = {
      nodes: [
        { id: 'hook', type: 'Webhook', label: 'New lead', controls: { method: 'POST', path: '/leads' }, position: { x: 0, y: 0 } },
        { id: 'log', type: 'Logger', label: 'Log it', controls: { level: 'info', message: 'A lead' }, position: { x: 220, y: 0 } },
      ],
      connections: [{ source: 'hook', sourceOutput: 'exec', target: 'log', targetInput: 'exec' }],
      comments: [],
    };

    const importFile = async (page, name, content) => {
      const chooser = page.waitForEvent('filechooser');
      await page.locator('#import-flow').click();
      await (await chooser).setFiles({ name, mimeType: 'application/json', buffer: Buffer.from(content) });
    };

    test('puts a flow from a file on the canvas, and keeps it', async ({ page }) => {
      await importFile(page, 'leads.json', JSON.stringify(flow));

      await expect(page.locator('custom-node')).toHaveCount(2, { timeout: 5000 });
      await expect(page.getByText('Flow imported')).toBeVisible({ timeout: 5000 });
      await waitSaved(page);

      await page.reload();
      await waitForLiveView(page);
      await expect(page.locator('custom-node')).toHaveCount(2, { timeout: 5000 });
    });

    test('says why a file is not a flow, and leaves the canvas alone', async ({ page }) => {
      await importFile(page, 'notes.json', '{"name": "Not a flow"}');

      await expect(page.getByText("That file isn't a Heddle flow.")).toBeVisible({ timeout: 5000 });
      await expect(page.locator('custom-node')).toHaveCount(0);
    });
  });
});

async function addNodeViaContextMenu(page, nodeName) {
  const rete = page.locator('#flow-canvas');
  await rete.click({ button: 'right' });

  const menu = page.locator('.fixed.z-\\[200\\]');
  await expect(menu).toBeVisible({ timeout: 3000 });
  await menu.getByText('Create Node').click();

  const modal = page.locator('[phx-click=close_create_node_modal]').first();
  await expect(modal).toBeVisible({ timeout: 5000 });

  await page.locator(`[phx-click=create_node_from_modal][phx-value-name="${nodeName}"]`).click();
  await page.waitForTimeout(1000);
}
