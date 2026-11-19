---
title: Findings
---

```sql results
select spec, outcome, method, estimate, ci_low, ci_high, p_value, bandwidth, n_left, n_right
from warehouse.rd_results
```

```sql level
select * from ${results} where spec = 'main' and outcome = 'score'
```

```sql five
select * from ${results} where spec = 'main' and outcome = 'five_star'
```

```sql kink
select * from ${results} where spec = 'kink (slope change)'
```

```sql adjacent
select * from ${results} where spec = 'day 0 vs day +1' and outcome = 'score'
```

```sql bunching
select *, 1 - exp(estimate) as share_missing from ${results} where spec = 'bunching check'
```

## Does late delivery cause worse reviews?

**Yes, but through _how late_ the order is, not through missing the promised date by itself.**

<BigValue data={kink} value=estimate title="Each extra day late (stars)" fmt=num2/>
<BigValue data={level} value=estimate title="Jump at the promised date (stars)" fmt=num2/>
<BigValue data={five} value=estimate title="Jump in 5-star share" fmt=pct1/>

- **Each extra day late:** <Value data={kink} column=estimate fmt=num2/> stars per day, compared with the trend before the promised date (95% CI <Value data={kink} column=ci_low fmt=num2/> to <Value data={kink} column=ci_high fmt=num2/>).
- **Just crossing the promised date:** <Value data={level} column=estimate fmt=num2/> stars (95% CI <Value data={level} column=ci_low fmt=num2/> to <Value data={level} column=ci_high fmt=num2/>), which is not significant. The share of 5-star reviews does dip: <Value data={five} column=estimate fmt=pct1/>.
- **Raw comparison, delivered on the promised day vs 1 day late:** <Value data={adjacent} column=estimate fmt=num2/> stars. Most of that is the first step down the slope, not a penalty for being late at all.

## Method: regression discontinuity

Comparing all late orders with all on-time ones (2.27 vs 4.29 stars) mixes lateness up with
everything else that differs between them: seller, distance, product. Regression discontinuity
looks only at orders delivered **just before vs just after** the promised date, which should be
otherwise similar, and measures the change at that line. Estimates use `rdrobust` (local linear,
data-driven bandwidth, robust bias-corrected CIs, errors clustered by seller), on 95,824 delivered
orders with a review.

## How much to trust it

| Check | Result |
|---|---|
| Covariates (price, items, distance) | ✅ no jump at the promised date |
| Covariate: freight | ⚠️ borderline (p = 0.08) |
| Placebo cutoff at −5 days | ✅ no jump |
| Placebo cutoff at +5 days | ⚠️ jump. The curve levels off near day 6 and a straight line can't follow the bend |
| Bandwidth sensitivity | ✅ the level jump stays near zero |
| Bunching | ❌ about 36% fewer orders just after the promised date than the trend predicts |

**Bunching is the main threat.** Deliveries seem to be pushed to land just in time, so orders
that barely made it may differ from those that barely missed. That weakens the level-jump
estimate most. The per-day slope rests on many days either side and is much more robust.

Other limitations: days are whole numbers, so the narrowest feasible bandwidth is 2.6 days. Olist
seems to send review surveys around the promised date, so many late reviews were written before
the package arrived. These are kept, because dropping them would remove mostly late orders. The
result also only describes orders near the promised date.

## Recommendation

1. **Prioritize cutting how late orders are, over the on-time rate itself.** Turning a 3-day-late
   order into a 1-day-late one is worth about +1 star.
2. **Test a more conservative promised date.** If reviews depend on lateness *relative to the
   promise*, adding a few days to the promise moves orders onto the flat part of the curve.
   Primary metric: 5-star rate. Guardrail: checkout conversion, since a later promise may put
   buyers off.

*This is a quasi-experimental estimate on historical data, not a randomized test.*

## All estimates

<DataTable data={results} rows=all>
    <Column id=spec title="Specification"/>
    <Column id=outcome/>
    <Column id=method/>
    <Column id=estimate fmt=num3/>
    <Column id=ci_low title="CI low" fmt=num3/>
    <Column id=ci_high title="CI high" fmt=num3/>
    <Column id=p_value title="p" fmt=num3/>
    <Column id=bandwidth fmt=num1/>
    <Column id=n_left title="N left" fmt=num0/>
    <Column id=n_right title="N right" fmt=num0/>
</DataTable>

---
<small>Data: <a href="https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce">Brazilian E-Commerce Public Dataset by Olist</a>, CC BY-NC-SA 4.0. Derived data shared under the same license.</small>
