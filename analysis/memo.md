# Decision memo: does late delivery cause worse reviews?

**Data:** 95,824 delivered Olist orders with a review, 2016–2018. **Method:** regression
discontinuity at the promised delivery date, standard errors clustered by seller. All numbers are
from `analysis/rd_late_delivery.py`, stored in the table `analysis.rd_results`.

## Answer

**Lateness hurts reviews, but through *how late* the order is, not the act of crossing the promised date.**

| Question | Estimate | 95% CI |
|---|---|---|
| Does crossing the promise by itself drop the average score? | −0.03 stars | −0.18 to +0.12 (not significant) |
| …the share of 5-star reviews? | −7.9 pp | −12.5 to −3.2 |
| How much more does **each extra day late** cost, compared with the trend before the promise? | **−0.62 stars per day** | −0.73 to −0.52 |
| Raw comparison: delivered on the promised day vs 1 day late | −0.30 stars (4.03 → 3.73) | −0.42 to −0.19 |

Before the promised date, scores are almost flat (4.1–4.3 whether the order is 10 days early or
just on time). After it, they fall about half a star per day, to roughly 1.7 by day 6, then level
off. The one-day comparison (−0.30) is mostly the first step down that slope, not a penalty for
crossing the line.

## Why not just compare late vs on-time orders?

Late orders average 2.27 stars against 4.29 for on-time ones. That gap mixes in everything else
that differs between them: sellers, distance, product. RD compares only orders that landed right
around the promised date, which should otherwise be similar.

## How much to trust this

| Check | Result | Verdict |
|---|---|---|
| Covariate balance (price, items, distance) | No jump | ✅ |
| Covariate balance (freight) | +R$1.9, p = 0.08 | ⚠️ borderline |
| Placebo cutoff at −5 days | No jump (p = 0.62) | ✅ |
| Placebo cutoff at +5 days | Jump of −0.35 (p = 0.02) | ⚠️ the curve flattens around day 6 and a straight line can't follow that bend |
| Bandwidth sensitivity | Level jump stays near zero and not significant (−0.05 to +0.12) | ✅ for the "no level jump" conclusion |
| **Bunching** | **36% fewer orders just after the promise than the trend predicts (p = 0.001)** | ❌ main threat |

**Bunching** means deliveries are pushed to land on or before the promised date. Orders that just
made it may differ from ones that just missed (more carrier effort, easier routes), so the
on-time/late split right at 0 is not purely random. This weakens the level-jump estimate most. The
slope finding rests on many days on each side and is much harder to explain away.

**Other limitations:**
- Days are whole numbers, so the narrowest feasible bandwidth is 2.6 days. Half the optimal
  bandwidth could not be estimated.
- Olist seems to send the review survey around the promised date. 70% of reviews at +3 days were
  written **before** the package arrived. These are kept, because dropping them removes mostly late
  orders. Dropping them gives +0.26, CI −0.00 to +0.53, which is not significant.
- This is the effect near the promised date. It doesn't say what a 20-day delay does.

## Recommendation

1. **Prioritize cutting how late orders are, over the on-time rate itself.** Turning a 3-day-late
   order into a 1-day-late one is worth about +1 star. Turning a 1-day-late order into an on-time
   one is worth far less (+0.30 stars in the raw comparison, about zero once the trend is accounted for).
2. **Test a more conservative promised date** (experiment design in
   `analysis/experiment_design.md`, a stretch goal). If reviews depend on lateness *relative to the
   promise*, adding a few days to the promise moves orders onto the flat part of the curve. The
   guardrail is checkout conversion, since a later promise may put buyers off. Primary metric: 5-star
   rate, which does respond at the threshold.

*A quasi-experimental estimate on historical data, not a randomized test.*
