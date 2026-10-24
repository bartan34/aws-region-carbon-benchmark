#!/usr/bin/env python3
"""Sensitivity analysis and README figures from data/processed/sci-results.csv.

Run analysis/sci.py first. Outputs (relative to repo root):
  data/processed/sensitivity.csv          one-at-a-time sensitivity, one row per region x factor
  docs/figures/fig2-stacked-op-embodied.png
  docs/figures/fig3-tornado.png
  docs/figures/fig4-accounting-views.png
  docs/figures/fig5-cost-vs-carbon.png    (only if data/coefficients/pricing.csv exists)

Needs matplotlib (see requirements.txt); sci.py itself stays stdlib-only.
"""
from __future__ import annotations

import csv
import statistics
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sci import COEF, OUT, ROOT, interpolate, load_power_curve, read_csv  # noqa: E402

FIG = ROOT / "docs" / "figures"

# Sensitivity factors (one at a time, all others at baseline)
CCF_CURVE = "m5.large-ccf2026"  # alternative power curve in power.csv
PUE_DELTA = 0.1
EL_BASE_Y, EL_ALT_Y = 6, 4      # Boavizta default server lifetime vs a shorter refresh cycle

# Palette: reference categorical slots 1-3, text and grid tokens
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
SURFACE, TEXT, TEXT_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "font.family": "sans-serif", "font.size": 10,
    "text.color": TEXT, "axes.labelcolor": TEXT_2, "xtick.color": TEXT_2, "ytick.color": TEXT_2,
    "axes.edgecolor": GRID, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 1,
    "axes.spines.top": False, "axes.spines.right": False, "axes.axisbelow": True,
    "legend.frameon": False,
})


def load_results() -> list[dict]:
    rows = read_csv(OUT / "sci-results.csv")
    num = [k for k in rows[0] if k not in {"region", "instance_id", "instance_type", "cpu_model",
                                            "start_utc", "end_utc", "i_hourly_source"}]
    for r in rows:
        for k in num:
            r[k] = float(r[k]) if r[k] != "" else None
    return rows


def region_order(rows: list[dict]) -> list[str]:
    """Regions sorted by baseline SCI (annual LBM), cleanest first."""
    by = {}
    for r in rows:
        by.setdefault(r["region"], []).append(r["sci_lbm_annual_g_per_1e6ev"])
    return sorted(by, key=lambda k: statistics.fmean(by[k]))


def mean_by_region(rows: list[dict], key: str, region: str) -> float:
    return statistics.fmean(r[key] for r in rows if r["region"] == region)


# --- sensitivity ------------------------------------------------------------

def sensitivity(rows: list[dict]) -> list[dict]:
    ccf = load_power_curve(CCF_CURVE)
    alt_i = {g["region"]: float(g["alt_gco2e_kwh"]) for g in read_csv(COEF / "grid-intensity.csv")}

    def sci(r: dict, op_scale: float = 1.0, m_scale: float = 1.0) -> float:
        return (r["op_g_lbm_annual"] * op_scale + r["embodied_g"] * m_scale) / (r["total_events"] / 1e6)

    factors = {
        "P: Teads -> CCF": lambda r: [sci(r, op_scale=interpolate(ccf, r["run_cpu_pct"]) / r["watts_est"])],
        f"PUE +/- {PUE_DELTA}": lambda r: [sci(r, op_scale=(r["pue"] - PUE_DELTA) / r["pue"]),
                                           sci(r, op_scale=(r["pue"] + PUE_DELTA) / r["pue"])],
        "I: annual -> alt source": lambda r: [sci(r, op_scale=alt_i[r["region"]] / r["i_annual"])],
        f"EL: {EL_BASE_Y} -> {EL_ALT_Y} y": lambda r: [sci(r, m_scale=EL_BASE_Y / EL_ALT_Y)],
    }

    out = []
    for region in region_order(rows):
        rr = [r for r in rows if r["region"] == region]
        base = statistics.fmean(sci(r) for r in rr)
        for name, fn in factors.items():
            variants = list(zip(*(fn(r) for r in rr)))  # one tuple per variant across runs
            deltas = [statistics.fmean(v) - base for v in variants]
            out.append({
                "region": region, "factor": name, "baseline_sci": base,
                "delta_low": min(min(deltas), 0.0), "delta_high": max(max(deltas), 0.0),
                "detail": _detail(name, rr[0], alt_i),
            })
    return out


def _detail(name: str, r: dict, alt_i: dict) -> str:
    if name.startswith("PUE"):
        return f"PUE {r['pue']:.2f} +/- {PUE_DELTA}"
    if name.startswith("I:"):
        return f"I {r['i_annual']:g} -> {alt_i[r['region']]:g}"
    return name


# --- figures ----------------------------------------------------------------

def fig_stacked(rows: list[dict], regions: list[str]) -> None:
    op = [mean_by_region(rows, "op_g_lbm_annual", g) for g in regions]
    emb = [mean_by_region(rows, "embodied_g", g) for g in regions]
    fig, ax = plt.subplots(figsize=(8, 4.2))
    x = range(len(regions))
    ax.bar(x, op, width=0.5, color=BLUE, edgecolor=SURFACE, linewidth=2, label="Operational (location-based, annual)")
    ax.bar(x, emb, width=0.5, bottom=op, color=ORANGE, edgecolor=SURFACE, linewidth=2, label="Embodied (Boavizta)")
    for i, (o, e) in enumerate(zip(op, emb)):
        ax.text(i, o + e + 0.04, f"{e / (o + e) * 100:.0f}% embodied", ha="center", va="bottom",
                fontsize=9, color=TEXT_2)
    ax.set_xticks(list(x), regions)
    ax.grid(axis="x", visible=False)
    ax.set_ylabel("gCO₂e per 600 s run")
    ax.set_title("Operational vs embodied emissions per run, m5.large", loc="left", fontsize=12)
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(FIG / "fig2-stacked-op-embodied.png", dpi=200)
    plt.close(fig)


def fig_tornado(sens: list[dict], regions: list[str]) -> None:
    fig, axes = plt.subplots(1, len(regions), figsize=(3.1 * len(regions), 3.2))
    for ax, region in zip(axes, regions):
        rs = sorted((s for s in sens if s["region"] == region),
                    key=lambda s: s["delta_high"] - s["delta_low"])
        y = range(len(rs))
        ax.barh(y, [s["delta_low"] for s in rs], height=0.5, color=BLUE, edgecolor=SURFACE, linewidth=2)
        ax.barh(y, [s["delta_high"] for s in rs], height=0.5, color=ORANGE, edgecolor=SURFACE, linewidth=2)
        ax.set_yticks(list(y), [s["detail"].replace("->", "→") for s in rs], fontsize=8)
        ax.axvline(0, color=TEXT_2, linewidth=1)
        ax.grid(axis="y", visible=False)
        ax.set_title(f"{region}\nbaseline {rs[0]['baseline_sci']:.3f}", fontsize=10)
        ax.tick_params(axis="x", labelsize=8)
    axes[0].set_xlabel("Δ SCI (gCO₂e per 10⁶ events)")
    handles = [plt.Rectangle((0, 0), 1, 1, color=BLUE), plt.Rectangle((0, 0), 1, 1, color=ORANGE)]
    fig.legend(handles, ["Lowers SCI", "Raises SCI"], loc="lower right", ncol=2)
    fig.suptitle("Sensitivity: which coefficient moves the result (one at a time)", x=0.01, ha="left", fontsize=12)
    fig.tight_layout(rect=(0, 0.06, 1, 1))
    fig.savefig(FIG / "fig3-tornado.png", dpi=200)
    plt.close(fig)


def fig_accounting(rows: list[dict], regions: list[str]) -> None:
    views = [("sci_lbm_annual_g_per_1e6ev", "Location-based, annual grid average", BLUE),
             ("sci_lbm_hourly_g_per_1e6ev", "Location-based, hourly at run time", ORANGE),
             ("sci_mbm_g_per_1e6ev", "Market-based (renewable matching, Scope 2 = 0)", AQUA)]
    fig, ax = plt.subplots(figsize=(8, 4.2))
    w = 0.24
    for j, (key, label, color) in enumerate(views):
        vals = [mean_by_region(rows, key, g) for g in regions]
        xs = [i + (j - 1) * w for i in range(len(regions))]
        ax.bar(xs, vals, width=w, color=color, edgecolor=SURFACE, linewidth=2, label=label)
    ax.set_xticks(range(len(regions)), regions)
    ax.grid(axis="x", visible=False)
    ax.set_ylabel("SCI, gCO₂e per 10⁶ events")
    ax.set_title("Same runs, three accounting views", loc="left", fontsize=12)
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(FIG / "fig4-accounting-views.png", dpi=200)
    plt.close(fig)


def fig_cost(rows: list[dict], regions: list[str]) -> None:
    """Cost and carbon per unit of work, both axes from zero so the spreads compare honestly."""
    cents = [mean_by_region(rows, "cost_usd_per_1e6ev", g) * 100 for g in regions]
    sci = [mean_by_region(rows, "sci_lbm_annual_g_per_1e6ev", g) for g in regions]
    fig, ax = plt.subplots(figsize=(8, 4.2))
    ax.scatter(cents, sci, s=64, color=BLUE, edgecolors=SURFACE, linewidths=2, zorder=3)
    for c, v, g in zip(cents, sci, regions):
        ax.annotate(g, (c, v), xytext=(8, 0), textcoords="offset points", va="center", fontsize=9, color=TEXT_2)
    ax.set_xlim(0, max(cents) * 1.35)
    ax.set_ylim(0, max(sci) * 1.15)
    ax.set_xlabel("On-demand compute cost, US cents per 10⁶ events")
    ax.set_ylabel("SCI, gCO₂e per 10⁶ events")
    spread_c = max(cents) / min(cents)
    spread_s = max(sci) / min(sci)
    ax.set_title(f"Cost varies {(spread_c - 1) * 100:.0f}% across regions, carbon varies {spread_s:.0f}×",
                 loc="left", fontsize=12)
    fig.tight_layout()
    fig.savefig(FIG / "fig5-cost-vs-carbon.png", dpi=200)
    plt.close(fig)


def main() -> None:
    FIG.mkdir(parents=True, exist_ok=True)
    rows = load_results()
    regions = region_order(rows)
    sens = sensitivity(rows)
    with (OUT / "sensitivity.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(sens[0].keys()))
        w.writeheader(); w.writerows(sens)
    fig_stacked(rows, regions)
    fig_tornado(sens, regions)
    fig_accounting(rows, regions)
    if rows[0].get("cost_usd_per_1e6ev") is not None:
        fig_cost(rows, regions)
    print(f"wrote {OUT / 'sensitivity.csv'} and figures in {FIG}")


if __name__ == "__main__":
    main()
