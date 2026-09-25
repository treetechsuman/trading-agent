# gotobi — live-readiness verdict

**Version validated:** v1 (fixed-rule EA, no tunable parameters swept —
entry/exit clock times, 20-pip stop, 0.5% risk and 3-pip spread cap all
taken directly from the strategy spec, not fit to data). USDJPY, EURJPY.r,
GBPJPY.r, backtested both independently (three single-symbol runs) and as
a true combined-account portfolio (`v1_portfolio/`, one EA instance
trading all three symbols against one shared account — see that folder's
`strategy.mq5` header for why this needed a separate harness).

**Update 2026-09-22 — combined-account gap closed.** An earlier version of
this verdict flagged the true 3-pair concurrent-account exposure as
untested. It's now been tested directly (`v1_portfolio/`, see below) after
finding and fixing a real bug in the harness (a shared `CTrade` object was
leaving the wrong magic number set when closing non-last-entered symbols,
causing occasional stuck positions — full root cause and fix documented in
`v1_portfolio/strategy.mq5`'s `ManageOpenPosition()` comment). This was a
test-harness bug, not a flaw in the underlying per-pair strategy logic.

## Evidence summary

- **In-sample (2017–2022):** all three pairs profitable in **every single
  year** — 18/18 pair-years with profit factor above 1.0, no losing year
  anywhere. Profit factor 1.42–1.48 aggregate, win rate 57–60%, max
  drawdown 1.6–2.6%, ~270–300 trades/pair. USDJPY 2022 is a standout year
  (PF 2.00 vs. 1.07–1.48 elsewhere) but doesn't mask any losing period.
- **Out-of-sample (2023–2025, used once, unmodified):** no degradation on
  any pair, on any metric — profit factor actually **improved** to
  1.48–1.86, drawdown stayed small (2.1–2.7%). See
  [v1/comparison.md](v1/comparison.md) for the full side-by-side.
- **But 2025 alone carries roughly 65–85% of the 3-year out-of-sample
  profit on every pair** — GBPJPY's 2024 was essentially flat (-$13 on
  $10k). This matches a caution the strategy spec itself raised: "one year
  gave most of that... a normal year is more like 4 to 9%." A representative
  year, excluding 2025's apparent outlier, looks more like 1-3%/yr per pair.
- **Safety systems fired for real, not just in theory** — the 6-consecutive-
  loss pause triggered during backtesting (USDJPY twice, EURJPY.r and
  GBPJPY.r once) and correctly auto-resumed the following month with no
  manual intervention needed.
- **No curve-fitting signature**, and less risk of it than usual: there
  were no free parameters to overfit to begin with, so in-sample/
  out-of-sample agreement here mainly confirms the event-driven premise
  (Tokyo gotobi dollar demand) held up on unseen data, not that a tuned
  config generalized.
- **Combined 3-pair account exposure, tested directly:** in-sample
  (2017-2022) combined-account profit factor 1.36, 898 trades, max
  drawdown 4.85-6.36%. Out-of-sample (2023-2025) profit factor **improved**
  to 1.72, 459 trades (exactly 153×3, matching the per-pair OOS counts),
  max drawdown 6.80-8.05%. Both comfortably below the 15% kill-switch, and
  the same no-degradation OOS pattern seen per-pair holds at the portfolio
  level too. This was the one piece of evidence missing from the original
  verdict — it no longer is.

## Verdict: Ready for live, but start at reduced size — a genuinely thin-edge case

**The consistency evidence is about as clean as this kind of backtest can
produce**: no losing year for any pair across 6 in-sample + 3 out-of-sample
years, drawdowns that never got close to the 15% hard stop at either the
per-pair level (worst 2.9%) or the true combined-account level (worst
8.05%), and safety mechanisms that were actually exercised and worked. I
don't see signs this is a fluke or an artifact of the test setup.

**One specific, unresolved risk keeps this from an unqualified "go":**

**The edge is small enough that live execution costs are the real test,
and backtesting can't fully settle that question.** Expectancy is
$4-11/trade per pair on a $10,000 account — a few pips. The spec itself
states plainly that ~3 pips of added cost (wider spread, slippage) erases
the edge. This is a well-known, calendar-published event (Japanese gotobi
dollar demand) that other market participants also trade — the exact
45-minute window this EA targets is precisely when liquidity and spread
behavior are least likely to match a historical tick replay. Tick-based
backtesting with the account's real recorded spread (`Model=4`) is the
best available proxy, but it cannot capture whether *this specific,
anticipated* price move fills the same way live as it did historically.
(The combined-account exposure risk flagged in an earlier version of this
verdict has since been tested directly and closed — see above.)

**Recommendation:** go live, but not at full three-pair 0.5%-each sizing on
day one. Start with a reduced size (e.g. half risk, or one pair first —
USDJPY has the longest and most consistent track record here) for the
first month or two of live gotobi days, specifically to confirm real fills
at the 00:45 UTC entry match backtest assumptions closely enough that the
thin edge survives contact with live spread/slippage. Scale to full
three-pair sizing once that's confirmed, rather than before. This isn't a
reflexive "always demo first" — it's specific to this strategy's unusually
thin per-trade margin and the one remaining risk (live execution quality on
a crowded, anticipated event) that no amount of backtesting resolves.
