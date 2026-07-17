import { test, expect } from '@playwright/test'

// Delete the app's IndexedDB before its scripts run so repeated runs against
// a reused browser profile start from a clean slate. IndexedDB queues the
// subsequent Dexie open() behind the delete, so there is no race. The
// sessionStorage flag keeps later same-tab navigations from wiping mid-test.
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    if (!sessionStorage.getItem('e2e-db-cleared')) {
      sessionStorage.setItem('e2e-db-cleared', '1')
      indexedDB.deleteDatabase('elbert')
    }
  })
})

test('create deck, add a note, study it, and reach zero due', async ({ page }) => {
  await page.goto('/')

  const deckName = `Smoke deck ${Date.now()}`

  // Create a deck from the home screen.
  await page.getByPlaceholder('New deck name').fill(deckName)
  await page.getByRole('button', { name: 'Add' }).click()

  const deckRow = page.locator('.deck-row', { hasText: deckName })
  await expect(deckRow).toBeVisible()

  // Open the editor for that deck and add one note.
  await deckRow.getByRole('link', { name: `Edit ${deckName}` }).click()
  await expect(page.getByRole('heading', { name: 'Edit deck' })).toBeVisible()

  await page.getByPlaceholder('Term').first().fill('bonjour')
  await page.getByPlaceholder('Definition').first().fill('hello')
  await page.getByPlaceholder('Definition').first().blur()

  // A second (blank) row should appear once the note is persisted.
  await expect(page.getByPlaceholder('Term')).toHaveCount(2)

  // Back to home.
  await page.getByRole('button', { name: 'Back' }).click()
  await expect(page.getByRole('heading', { name: 'Elbert' })).toBeVisible()

  await expect(page.locator('.due-number')).not.toHaveText('0')
  await expect(page.locator('.due-number')).not.toHaveText('–')

  // Study the freshly created card. A brand-new card can pass through several intraday
  // learning steps before the session ends, so keep rating Good until the done screen shows.
  await page.getByRole('button', { name: 'Study now' }).click()

  for (let i = 0; i < 10; i++) {
    // After a rating the UI settles into exactly one of two states: another
    // card (front side, "Show answer" present) or the done screen. Waiting on
    // the union of those two settled states avoids racing React's re-render;
    // the old check keyed off .study-card-tap, which is still mounted for a
    // frame after the final rating, and then hung on a button that never came.
    const done = page.locator('.study-done')
    const showAnswer = page.getByRole('button', { name: 'Show answer' })
    await expect(done.or(showAnswer).first()).toBeVisible()
    if (await done.isVisible()) break
    await showAnswer.click()
    await expect(page.locator('.rating-bar')).toBeVisible()
    await page.locator('.rating-good').click()
  }

  await expect(page.locator('.study-done')).toBeVisible()
  await page.getByRole('link', { name: 'Back home' }).click()

  await expect(page.getByRole('heading', { name: 'Elbert' })).toBeVisible()
  await expect(page.locator('.due-number')).toHaveText('0')
})
