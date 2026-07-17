import { test, expect } from '@playwright/test'

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
    const doneOrCard = page.locator('.study-done, .study-card-tap').first()
    await expect(doneOrCard).toBeVisible()
    if (await page.locator('.study-done').count()) break
    await page.getByRole('button', { name: 'Show answer' }).click()
    await expect(page.locator('.rating-bar')).toBeVisible()
    await page.locator('.rating-good').click()
  }

  await expect(page.locator('.study-done')).toBeVisible()
  await page.getByRole('link', { name: 'Back home' }).click()

  await expect(page.getByRole('heading', { name: 'Elbert' })).toBeVisible()
  await expect(page.locator('.due-number')).toHaveText('0')
})
