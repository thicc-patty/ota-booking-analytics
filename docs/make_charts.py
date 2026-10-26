"""Draws the four charts used in the README from the CSV files in data/powerbi/.

Run from the repository root:
    python docs/make_charts.py

Needs pandas and matplotlib. The charts are written to docs/charts/.
All numbers come from the synthetic data in this repository.
"""
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "powerbi"
OUT = ROOT / "docs" / "charts"
OUT.mkdir(parents=True, exist_ok=True)

BLUE = "#2a78d6"
ORANGE = "#eb6834"
GREY = "#b9b8b2"
INK = "#0b0b0b"
INK_SOFT = "#52514e"
GRID = "#e7e6e1"

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 10,
    "axes.edgecolor": GREY,
    "axes.labelcolor": INK_SOFT,
    "xtick.color": INK_SOFT,
    "ytick.color": INK_SOFT,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
})


def finish(fig, name):
    fig.savefig(OUT / name, dpi=160, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def style_axes(ax, grid_axis="y"):
    ax.grid(axis=grid_axis, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


bookings = pd.read_csv(DATA / "bookings.csv", parse_dates=["month_start"])
payments = pd.read_csv(DATA / "payments.csv")
refunds = pd.read_csv(DATA / "refunds.csv")
funnel = pd.read_csv(DATA / "funnel.csv")

# 1. Gross booking value by month (bookings that are not cancelled)
live = bookings[bookings["status"] != "cancelled"]
gbv = live.groupby("month_start")["gross_amount"].sum() / 1e6
peak = gbv.sort_values(ascending=False).index[:3]
fig, ax = plt.subplots(figsize=(8, 3.8))
colors = [BLUE if m in peak else GREY for m in gbv.index]
bars = ax.bar(gbv.index.strftime("%b"), gbv.values, color=colors, width=0.62)
for b, v in zip(bars, gbv.values):
    ax.text(b.get_x() + b.get_width() / 2, v + 0.2, f"{v:.1f}", ha="center", va="bottom", fontsize=9, color=INK)
ax.set_ylabel("Million BDT")
ax.set_title("Gross booking value by month (2026)", loc="left", fontsize=12, color=INK, pad=12)
style_axes(ax)
finish(fig, "01_gbv_by_month.png")

# 2. Funnel: sessions reaching each stage
stages = funnel.groupby(["stage_order", "stage"])["sessions_reaching_stage"].sum().reset_index()
stages["pct"] = 100 * stages["sessions_reaching_stage"] / stages["sessions_reaching_stage"].iloc[0]
fig, ax = plt.subplots(figsize=(8, 3.4))
y = range(len(stages))[::-1]
ax.barh(list(y), stages["sessions_reaching_stage"] / 1e3, color=BLUE, height=0.62)
for yi, (_, r) in zip(y, stages.iterrows()):
    ax.text(r["sessions_reaching_stage"] / 1e3 + 5, yi,
            f"{r['sessions_reaching_stage'] / 1e3:,.0f}k  ({r['pct']:.1f}%)", va="center", fontsize=9, color=INK)
ax.set_yticks(list(y))
ax.set_yticklabels(stages["stage"].str.capitalize())
ax.set_xlim(0, stages["sessions_reaching_stage"].max() / 1e3 * 1.28)
ax.set_xlabel("Sessions (thousands)")
ax.set_title("Booking funnel: sessions reaching each stage", loc="left", fontsize=12, color=INK, pad=12)
style_axes(ax, "x")
finish(fig, "02_funnel.png")

# 3. Payment method: failure rate and refund time (two panels, each with its own scale)
attempts = payments.groupby("payment_method")["payment_status"].agg(
    attempts="count", failed=lambda s: (s == "failed").sum())
attempts["rate"] = 100 * attempts["failed"] / attempts["attempts"]
attempts = attempts.sort_values("rate", ascending=True)

done = refunds[(refunds["is_pending"] == "No") & (refunds["is_timestamp_valid"] == "Yes")]
days = done.groupby("payment_method")["days_to_complete"].mean().sort_values(ascending=True)

fig, (a1, a2) = plt.subplots(1, 2, figsize=(10, 3.6))
for ax, series, title, fmt in (
    (a1, attempts["rate"], "Failed payment attempts (%)", "{:.1f}%"),
    (a2, days, "Average days to complete a refund", "{:.1f}"),
):
    cols = [BLUE if name == "Internet banking" else GREY for name in series.index]
    ax.barh(series.index, series.values, color=cols, height=0.62)
    for yi, v in enumerate(series.values):
        ax.text(v + series.max() * 0.015, yi, fmt.format(v), va="center", fontsize=9, color=INK)
    ax.set_xlim(0, series.max() * 1.18)
    ax.set_title(title, loc="left", fontsize=11, color=INK, pad=10)
    style_axes(ax, "x")
fig.suptitle("Internet banking is the weak payment method", x=0.01, ha="left", fontsize=12, color=INK, y=1.02)
fig.tight_layout()
finish(fig, "03_payment_methods.png")

# 4. Net revenue per booking, promo against no promo, by product type
live = live.assign(has_promo=live["promo_code"] != "No promo")
net = live.groupby(["product_type", "has_promo"])["net_revenue"].mean().unstack()
net = net.rename(columns={False: "No promo", True: "With promo"})
order = net["No promo"].sort_values(ascending=False).index
net = net.loc[order]
labels = [p.replace("_", " ").capitalize() for p in net.index]
fig, ax = plt.subplots(figsize=(8, 3.8))
x = range(len(net))
w = 0.36
b1 = ax.bar([i - w / 2 for i in x], net["No promo"], width=w, color=GREY, label="No promo")
b2 = ax.bar([i + w / 2 for i in x], net["With promo"], width=w, color=ORANGE, label="With promo")
for bars in (b1, b2):
    for b in bars:
        v = b.get_height()
        ax.text(b.get_x() + b.get_width() / 2, v + (25 if v >= 0 else -25), f"{v:,.0f}",
                ha="center", va="bottom" if v >= 0 else "top", fontsize=9, color=INK)
ax.axhline(0, color=INK_SOFT, linewidth=0.8)
ax.set_ylim(net.min().min() - 160, net.max().max() + 200)
ax.set_xticks(list(x))
ax.set_xticklabels(labels)
ax.set_ylabel("BDT per booking")
ax.set_title("Net revenue per booking: promo against no promo", loc="left", fontsize=12, color=INK, pad=12)
ax.legend(frameon=False, loc="upper right")
style_axes(ax)
finish(fig, "04_promo_effect.png")

print("Charts written to", OUT)
