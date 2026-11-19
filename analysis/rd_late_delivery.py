"""Does late delivery cause worse reviews? Regression discontinuity at the promised delivery date.

Running variable: days_vs_estimate (whole days; <= 0 on time, >= 1 late), so the cutoff sits at 0.5.
Unit: delivered orders with a review. Standard errors are clustered by seller.

Writes every estimate to the DuckDB table analysis.rd_results and prints a summary.
Run after `dbt build`:  .venv/Scripts/python analysis/rd_late_delivery.py
"""
import os
import warnings
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd
import statsmodels.api as sm
from rdrobust import rdrobust
from scipy import stats

warnings.filterwarnings("ignore")  # rdrobust prints "mass points detected" on every call; expected here.

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = os.environ.get("WAREHOUSE_PATH", str(ROOT / "data" / "warehouse.duckdb"))
CUTOFF = 0.5

ORDERS_SQL = """
with zip as (  -- one point per zip prefix; drop the few coordinates outside Brazil
    select zip_code_prefix, avg(lat) as lat, avg(lng) as lng
    from staging.stg_geolocation
    where lat between -34 and 6 and lng between -74 and -34
    group by 1
),
first_seller as (  -- multi-seller orders: use the seller of the first item
    select order_id, arg_min(seller_id, order_item_id) as seller_id
    from staging.stg_order_items
    group by 1
)
select
    o.days_vs_estimate                       as x,
    o.review_score                           as score,
    (o.review_score = 1)::int                as one_star,
    (o.review_score = 5)::int                as five_star,
    o.is_review_before_delivery              as review_before_delivery,
    o.items_value::double                    as items_value,
    o.freight_value::double                  as freight_value,
    o.item_count,
    fs.seller_id,
    2 * 6371 * asin(sqrt(
        pow(sin(radians(sz.lat - cz.lat) / 2), 2)
        + cos(radians(cz.lat)) * cos(radians(sz.lat)) * pow(sin(radians(sz.lng - cz.lng) / 2), 2)
    ))                                       as distance_km
from marts.fct_orders o
join staging.stg_customers c using (customer_id)
join first_seller fs using (order_id)
join staging.stg_sellers s using (seller_id)
left join zip cz on cz.zip_code_prefix = c.zip_code_prefix
left join zip sz on sz.zip_code_prefix = s.zip_code_prefix
where o.is_delivered and o.review_score is not null
"""


def rd(df, y, label, c=CUTOFF, h=None, deriv=0):
    """rdrobust local-polynomial estimate; robust bias-corrected CI and p-value (Calonico et al.)."""
    d = df.dropna(subset=[y])
    r = rdrobust(
        d[y], d.x, c=c, h=h, deriv=deriv, p=deriv + 1,
        cluster=pd.factorize(d.seller_id)[0], vce="hc1",
    )
    # estimate = bias-corrected point estimate, which is the centre of the robust CI.
    # The conventional estimate is kept for reference; it can sit outside the robust CI.
    return {
        "spec": label, "outcome": y, "method": "rdrobust" + (" kink" if deriv else ""),
        "cutoff": c, "estimate": r.coef.iloc[1, 0], "estimate_conventional": r.coef.iloc[0, 0],
        "ci_low": r.ci.iloc[2, 0], "ci_high": r.ci.iloc[2, 1], "p_value": r.pv.iloc[2, 0],
        "bandwidth": r.bws.iloc[0, 0], "n_left": int(r.N_h[0]), "n_right": int(r.N_h[1]),
    }


def adjacent_days(df, y, label):
    """Local randomization: compare orders delivered ON the promised day (0) vs 1 day late (+1)."""
    a, b = df.loc[df.x == 0, y], df.loc[df.x == 1, y]
    diff = b.mean() - a.mean()
    se = np.sqrt(a.var() / len(a) + b.var() / len(b))
    return {
        "spec": label, "outcome": y, "method": "diff in means (0 vs +1)", "cutoff": CUTOFF,
        "estimate": diff, "ci_low": diff - 1.96 * se, "ci_high": diff + 1.96 * se,
        "p_value": 2 * stats.norm.sf(abs(diff / se)), "bandwidth": 0.5,
        "n_left": len(a), "n_right": len(b),
    }


def density_jump(df, window=10):
    """Bunching check: Poisson regression of order counts per day, separate linear trend each side,
    plus a jump dummy at the cutoff. estimate = log ratio of counts just after vs just before."""
    counts = df.loc[df.x.abs() <= window].groupby("x").size().reset_index(name="n")
    late = (counts.x > CUTOFF).astype(int)
    X = sm.add_constant(pd.DataFrame({"late": late, "x": counts.x, "x_late": counts.x * late}))
    fit = sm.GLM(counts.n, X, family=sm.families.Poisson()).fit(cov_type="HC1")
    lo, hi = fit.conf_int().loc["late"]
    return {
        "spec": "bunching check", "outcome": "log(order count)", "method": "poisson counts",
        "cutoff": CUTOFF, "estimate": fit.params["late"], "ci_low": lo, "ci_high": hi,
        "p_value": fit.pvalues["late"], "bandwidth": window,
        "n_left": int(counts.n[late == 0].sum()), "n_right": int(counts.n[late == 1].sum()),
    }


def main():
    con = duckdb.connect(DB_PATH)
    df = con.sql(ORDERS_SQL).df()
    print(f"{len(df):,} delivered orders with a review\n")

    results = []
    # 1. Main estimates: level jump at the cutoff, for three outcomes.
    for y in ["score", "one_star", "five_star"]:
        results.append(rd(df, y, "main"))
    main = results[0]

    # 2. Slope change at the cutoff (does each extra day late cost more than each day early gains?).
    results.append(rd(df, "score", "kink (slope change)", deriv=1))

    # 3. Just-on-time vs 1-day-late, no extrapolation.
    for y in ["score", "one_star", "five_star"]:
        results.append(adjacent_days(df, y, "day 0 vs day +1"))

    # 4. Robustness of the main estimate.
    # Half the optimal bandwidth (~1.9 days) leaves one mass point per side, too few for a line.
    # 2.6 days is the narrowest feasible: days -1, 0 on the left and +1, +2 on the right.
    results.append(rd(df, "score", "bandwidth 2.6 (narrowest feasible)", h=2.6))
    results.append(rd(df, "score", "bandwidth x2", h=main["bandwidth"] * 2))
    results.append(rd(df[~df.review_before_delivery.fillna(False)], "score", "drop reviews before delivery"))
    # Placebo cutoffs: use only one side of the real cutoff so the real jump can't leak in.
    results.append(rd(df[df.x <= 0], "score", "placebo cutoff -5", c=-4.5))
    results.append(rd(df[df.x >= 1], "score", "placebo cutoff +5", c=5.5))

    # 5. Covariate balance: things lateness can't cause should not jump at the cutoff.
    for y in ["items_value", "freight_value", "item_count", "distance_km"]:
        results.append(rd(df, y, "covariate balance"))

    # 6. Bunching (manipulation of the running variable).
    results.append(density_jump(df))

    out = pd.DataFrame(results)
    con.execute("create schema if not exists analysis")
    con.execute("create or replace table analysis.rd_results as select * from out")
    con.close()

    pd.set_option("display.width", 200)
    print(out[["spec", "outcome", "method", "estimate", "ci_low", "ci_high", "p_value",
               "bandwidth", "n_left", "n_right"]].round(3).to_string(index=False))
    print("\nWrote analysis.rd_results")


if __name__ == "__main__":
    main()
