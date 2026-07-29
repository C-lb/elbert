// Reference schedule from ts-fsrs, the implementation the web app already trusts.
//
// The numbers this prints are pasted into ios/Elbert/Tests/ElbertTests/SchedulerTests.swift,
// where the Swift scheduler is asserted against them. Regenerate by running it from the repo
// root, where the web app's node_modules lives:
//
//     node ios/Tools/fsrs-parity.mjs
//
// If the output changes, ts-fsrs moved. That is a decision to make, not a test to update blindly.
import { fsrs, generatorParameters } from 'ts-fsrs'

const RETENTION = 0.9
const params = generatorParameters({ request_retention: RETENTION })
const engine = fsrs(params)

const blank = {
  due: new Date(0), stability: 0, difficulty: 0, elapsed_days: 0, scheduled_days: 0,
  learning_steps: 0, reps: 0, lapses: 0, state: 0, last_review: undefined,
}

function row(card, now) {
  const rec = engine.repeat(card, now)
  return Object.fromEntries([1, 2, 3, 4].map(g => {
    const c = rec[g].card
    return [g, {
      seconds: Math.round((c.due.getTime() - now.getTime()) / 1000),
      stability: c.stability,
      difficulty: c.difficulty,
      state: c.state,
      reps: c.reps,
      lapses: c.lapses,
      learning_steps: c.learning_steps,
    }]
  }))
}

// A brand-new card, and one that has already graduated so the review and lapse branches are
// covered too. Fixed instants, because a parity check that drifts with the clock is not one.
const NEW_AT = new Date('2026-01-01T00:00:00.000Z')
const MATURE_AT = new Date('2026-01-20T00:00:00.000Z')

const mature = {
  ...blank,
  due: MATURE_AT, stability: 15.2, difficulty: 6.4, state: 2, reps: 6, lapses: 1,
  last_review: new Date('2026-01-05T00:00:00.000Z'),
}

console.log(JSON.stringify({
  weightCount: params.w.length,
  decay: params.w[params.w.length - 1],
  enableFuzz: params.enable_fuzz,
  enableShortTerm: params.enable_short_term,
  newCard: row({ ...blank, due: NEW_AT }, NEW_AT),
  matureCard: row(mature, MATURE_AT),
}, null, 2))
