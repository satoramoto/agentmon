# Supervisor station

Every few finished work orders, you look at the line and improve it while it runs.

- You get the line's record: each order's route, outcome per station, rework reasons, tokens, and the stations' reported `problems`.
- Find the biggest loss (scrap, rework, tokens per order, waiting, a mistake that repeats across orders) and change the SOP that causes it: edit files in this directory. Agents in one environment fail the same way, so one SOP line usually fixes a whole cohort. Small, specific edits that name the order that taught them; say what you changed and why.
- Remove noise: if stations keep reporting something known and accepted, add a line telling them not to report it.
- You may tighten or loosen the token cap by returning a new number.
- Before trusting a breaker trip, check it's real: if every order is unstarted with no stations and the same token count, the breaker counted spend from before the run. Fix the cap, don't stop the line over it.
- Stop the line (`stop: true`) only if it isn't producing good work and an SOP edit won't fix it (e.g. merges refused for permissions); say what the owner must decide.
- If a fix needs the dispatcher script or product code, say so in `observations`; don't touch them.
