export const meta = {
  name: 'job-shop',
  description: 'Software factory job shop: typed work orders routed through spec/build/inspect stations with token and quality circuit breakers, a WIP limit, an integration station and a live supervisor',
  phases: [
    { title: 'Spec', model: 'sonnet' },
    { title: 'Build' },
    { title: 'Inspect', model: 'sonnet' },
    { title: 'Integrate', model: 'sonnet' },
    { title: 'Supervise' },
  ],
}

// Copy into the repo (factory/job-shop.js) and run with Workflow({scriptPath, args}); see SKILL.md for args.
const cfg = args.config
const orders = args.orders
const REPO = cfg.repo                 // main checkout (stations never run git here)
const WT = cfg.worktrees              // dir holding one worktree per order
const SOP = cfg.sop_dir               // station SOPs, re-read by every station call
const GH = cfg.gh_repo
const BASE = cfg.base || 'main'
const SLOTS = 8                       // ~ min(16, CPUs - 2): the workflow's concurrent agent cap

// ---- line state --------------------------------------------------------
// budget.spent() is the whole session's output tokens; measure the run from launch.
const BASELINE = budget.spent()
const spent = () => budget.spent() - BASELINE
const record = []
let stopped = null
let runCap = cfg.run_output_tokens
let finishedSinceSupervise = 0
const done = {}
const resolvers = {}
for (const o of orders) done[o.id] = new Promise(r => { resolvers[o.id] = r })

function breakerCheck() {
  if (stopped) return stopped
  if (spent() > runCap) { stopped = `token breaker: ${spent()} output tokens > run cap ${runCap}`; log(stopped) }
  const finished = record.filter(r => r.type !== 'integration')
  const last = finished.slice(-3)
  if (last.length === 3 && last.every(r => !['merged', 'ready-to-merge'].includes(r.outcome))) { stopped = 'quality breaker: 3 orders in a row not ready'; log(stopped) }
  const last5 = finished.slice(-5)
  if (last5.length === 5 && last5.filter(r => r.firstPass).length / 5 < 0.4) { stopped = 'quality breaker: first-pass yield < 40% over last 5'; log(stopped) }
  return stopped
}

const sop = name => `Read your standard work first: "${SOP}/${name}.md" (and "${SOP}/README.md" for context). Repo ${GH}, main checkout "${REPO}" (never run git there); AGENTS.md has the project rules and test commands.`

const PROBLEMS = { type: 'array', items: { type: 'string' }, description: 'problems with the process, SOPs, tools or work order (not the product), one line each' }
const BUILD = { type: 'object', properties: {
  branch: { type: 'string' }, worktree: { type: 'string' }, pr_number: { type: 'integer' },
  result: { type: 'string', enum: ['ok', 'blocked'] }, ran: { type: 'string' }, notes: { type: 'string' }, problems: PROBLEMS },
  required: ['branch', 'result', 'ran', 'notes', 'problems'] }
const SPEC = { type: 'object', properties: {
  branch: { type: 'string' }, checks: { type: 'array', items: { type: 'string' } }, failing_summary: { type: 'string' }, problems: PROBLEMS },
  required: ['branch', 'checks', 'failing_summary', 'problems'] }
const INSPECT = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['pass', 'rework'] }, findings: { type: 'array', items: { type: 'string' } },
  follow_ups: { type: 'array', items: { type: 'string' } }, problems: PROBLEMS },
  required: ['verdict', 'findings', 'follow_ups', 'problems'] }
const MERGE = { type: 'object', properties: {
  result: { type: 'string', enum: ['merged', 'rework', 'blocked'] }, reason: { type: 'string' }, problems: PROBLEMS },
  required: ['result', 'reason', 'problems'] }
const SUPERVISE = { type: 'object', properties: {
  sop_changes: { type: 'array', items: { type: 'string' } }, stop: { type: 'boolean' }, stop_reason: { type: 'string' },
  run_output_tokens: { type: 'integer' }, observations: { type: 'array', items: { type: 'string' } } },
  required: ['sop_changes', 'stop', 'observations'] }
const INTEGRATION = { type: 'object', properties: {
  passed: { type: 'boolean' }, ran: { type: 'string' },
  culprits: { type: 'array', items: { type: 'object', properties: { order_id: { type: 'string' }, problem: { type: 'string' } }, required: ['order_id', 'problem'] } },
  unattributed: { type: 'array', items: { type: 'string' } }, problems: PROBLEMS },
  required: ['passed', 'ran', 'culprits', 'unattributed', 'problems'] }

// Merging needs a formal approval (a review bot account). Without one, routes end at inspect
// and the plant manager merges the ready PRs.
const tail = cfg.merge === 'station' ? ['inspect', 'merge'] : ['inspect']
const ROUTES = { fix: ['build', ...tail], 'story-lite': ['build', ...tail], doc: ['build', ...tail],
  story: ['spec', 'build', ...tail], pr: [...tail] }

async function supervise() {
  const r = await agent(`${sop('supervisor')}

The line's record so far (JSON):
${JSON.stringify({ finished: record, output_tokens_spent: spent(), run_cap: runCap, orders_total: orders.length }, null, 1)}

Edit SOP files in "${SOP}" if it will improve the rest of this run. Return your changes, observations, whether to stop, and optionally a new run_output_tokens cap.`,
    { label: `supervise@${record.length}`, phase: 'Supervise', schema: SUPERVISE })
  if (!r) return
  r.sop_changes.forEach(c => log(`supervisor: ${c}`))
  if (r.run_output_tokens) { runCap = r.run_output_tokens; log(`supervisor: run cap now ${runCap}`) }
  if (r.stop) { stopped = `supervisor stopped the line: ${r.stop_reason}`; log(stopped) }
  return r
}

// ---- WIP limit ---------------------------------------------------------
// ~ the agent slot cap: lower starves the line, none lets it start everything and finish nothing.
let inFlight = 0
const waiting = []
async function admit() {
  while (inFlight >= (cfg.wip || SLOTS)) await new Promise(r => waiting.push(r))
  inFlight++
}
function leave() { inFlight--; const next = waiting.shift(); if (next) next() }

// ---- integration station -----------------------------------------------
const ready = []
let integratedUpTo = 0
let integrating = null
async function integrate(final) {
  if (integrating) await integrating
  if (ready.length === integratedUpTo && !final) return
  integratedUpTo = ready.length
  const batch = ready.map(r => `${r.id} → ${r.branch}`).join('\n')
  integrating = agent(`${sop('integration')}\n\nIntegration worktree: "${WT}/integration" (create it with \`git -C "${REPO}" worktree add --detach "${WT}/integration" origin/${BASE}\` if missing). Ready orders and branches, merge in this order:\n${batch}`,
    { label: `integration@${ready.length}`, phase: 'Integrate', schema: INTEGRATION, model: 'sonnet' })
  const r = await integrating
  integrating = null
  if (!r) return
  log(`integration of ${ready.length} branches: ${r.passed ? 'green' : `${r.culprits.length} culprits`}`)
  record.push({ id: `integration@${ready.length}`, type: 'integration', outcome: r.passed ? 'green' : 'red', culprits: r.culprits, unattributed: r.unattributed, problems: r.problems })
  for (const c of r.culprits) {
    const item = ready.find(x => x.id === c.order_id)
    if (!item) continue
    item.entry.firstPass = false
    const b = await agent(`${sop('build')}\n\nWork order ${item.id}: ${item.o.input}\n\nBranch \`${item.branch}\`, worktree "${WT}/${item.id}". Existing PR: #${item.entry.pr}.\n\nREWORK from the integration station (your branch breaks when assembled with the other ready orders) — fix only this:\n${c.problem}`,
      { label: `build:${item.id}:integration-rework`, phase: 'Build', schema: BUILD })
    item.entry.stations.push({ st: 'build', ok: b?.result === 'ok' })
    if (b?.result !== 'ok') item.entry.outcome = 'blocked'
  }
}

// ---- orders ------------------------------------------------------------
async function runOrder(o) {
  for (const dep of o.after || []) await done[dep]
  await admit()
  try { return await runOrderAdmitted(o) } finally { leave() }
}

async function runOrderAdmitted(o) {
  const entry = { id: o.id, type: o.type, outcome: 'pending', firstPass: true, stations: [], problems: [], follow_ups: [] }
  const branch = `job/${o.id}`
  let pr = o.pr || null
  let notes = ''
  let reworks = 0
  const route = [...ROUTES[o.type]]
  try {
    for (let i = 0; i < route.length; i++) {
      if (breakerCheck()) { entry.outcome = 'halted'; break }
      const st = route[i]
      if (st === 'spec') {
        const r = await agent(`${sop('spec')}\n\nWork order ${o.id}: ${o.input}\n\nUse branch \`${branch}\` from origin/${BASE}, in a worktree at "${WT}/${o.id}".`,
          { label: `spec:${o.id}`, phase: 'Spec', schema: SPEC, model: 'sonnet' })
        entry.stations.push({ st, ok: !!r }); if (!r) throw new Error('spec died')
        entry.problems.push(...r.problems)
      } else if (st === 'build') {
        const r = await agent(`${sop('build')}\n\nWork order ${o.id} (${o.type}): ${o.input}\n\nBranch \`${pr ? "(the PR's existing branch)" : branch}\` based on origin/${BASE}, worktree "${WT}/${o.id}".${pr ? ` Existing PR: #${pr}.` : ''}${notes ? `\n\nREWORK — fix only this:\n${notes}` : ''}`,
          { label: `build:${o.id}${reworks ? ':rework' : ''}`, phase: 'Build', schema: BUILD })
        entry.stations.push({ st, ok: r?.result === 'ok' }); if (!r) throw new Error('build died')
        entry.problems.push(...r.problems)
        if (r.result !== 'ok') { entry.outcome = 'blocked'; entry.reason = r.notes; break }
        pr = r.pr_number || pr
      } else if (st === 'inspect') {
        const r = await agent(`${sop('inspect')}\n\nWork order ${o.id} (${o.type}): ${o.input}\n\nPR #${pr} in ${GH}.`,
          { label: `inspect:${o.id}`, phase: 'Inspect', schema: INSPECT, model: 'sonnet' })
        entry.stations.push({ st, ok: r?.verdict === 'pass' }); if (!r) throw new Error('inspect died')
        entry.problems.push(...r.problems); entry.follow_ups = r.follow_ups
        if (r.verdict === 'rework') {
          entry.firstPass = false
          if (++reworks > 1) { entry.outcome = 'scrapped'; entry.reason = 'second inspection rework'; break }
          notes = r.findings.join('\n'); route.splice(i + 1, 0, 'build', 'inspect'); continue
        }
      } else if (st === 'merge') {
        const r = await agent(`${sop('merge')}\n\nPR #${pr} in ${GH} (work order ${o.id}). Build worktree: "${WT}/${o.id}".`,
          { label: `merge:${o.id}`, phase: 'Integrate', schema: MERGE, model: 'sonnet' })
        entry.stations.push({ st, ok: r?.result === 'merged' }); if (!r) throw new Error('merge died')
        entry.problems.push(...r.problems)
        if (r.result === 'merged') { entry.outcome = 'merged'; break }
        if (r.result === 'blocked') { entry.outcome = 'blocked'; entry.reason = r.reason; break }   // permissions: to the owner, never to build
        entry.firstPass = false
        if (++reworks > 1) { entry.outcome = 'scrapped'; entry.reason = `merge: ${r.reason}`; break }
        notes = `Merge failed: ${r.reason}. Merge origin/${BASE} into the branch and fix.`; route.splice(i + 1, 0, 'build', 'merge')
      }
    }
  } catch (e) { entry.outcome = 'scrapped'; entry.reason = String(e) }
  if (entry.outcome === 'pending') entry.outcome = route[route.length - 1] === 'inspect' && entry.stations.at(-1)?.ok ? 'ready-to-merge' : 'unfinished'
  entry.pr = pr; entry.output_tokens_at_finish = spent()
  record.push(entry)
  log(`${o.id}: ${entry.outcome}${entry.firstPass ? ' (first pass)' : ''} — ${spent()} output tokens so far`)
  if (['ready-to-merge', 'merged'].includes(entry.outcome)) {
    ready.push({ id: o.id, branch: `job/${o.id}`, entry, o })
    if (ready.length - integratedUpTo >= (cfg.integrate_every || Infinity)) await integrate(false)
  }
  resolvers[o.id](entry.outcome)
  if (++finishedSinceSupervise >= cfg.supervise_every && record.length < orders.length && !stopped) {
    finishedSinceSupervise = 0
    await supervise()
  }
  return entry
}

await pipeline(orders, o => runOrder(o))
if (ready.length && cfg.integrate_every) await integrate(true)
const final = await supervise()
return {
  stopped, output_tokens: spent(), record,
  ready_prs: record.filter(r => r.outcome === 'ready-to-merge').map(r => r.pr),
  follow_ups: record.flatMap(r => (r.follow_ups || []).map(f => `${r.id}: ${f}`)),
  final_supervisor: final,
}
