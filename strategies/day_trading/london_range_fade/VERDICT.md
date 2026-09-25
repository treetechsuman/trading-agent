# london_range_fade — live-readiness verdict

**Status update (2026-09-17): marked TRADEABLE by user, held here pending
their review.** The assessment below is my own analysis at the time of
the out-of-sample validation — it has not been superseded, just paused for
the user to look at the evidence themselves before the next step is
decided. See `STRATEGY.md` in this folder for a single-file description
of the whole strategy.

**Version validated:** v2 (bar-close breakout confirmation, minimum range
filter, rolling-average volatility filter). EURUSD.r, M15.

## Evidence summary

- **In-sample (2018–2022):** Profit Factor 1.08, win rate 53.5%, max
  drawdown 9.58%, 202 trades.
- **Yearly breakdown (in-sample):** 3 of 5 years profitable with
  substantial trade counts (2020: +$253/44 trades, 2021: +$369/15 trades,
  2022: +$535/89 trades); 2018 a confirmed loser on a full sample
  (-$359/52 trades) that a targeted volatility filter did not fix; 2019
  negligible (2 trades).
- **Out-of-sample (2023–2025, used once, unmodified):** Profit Factor
  1.10, win rate 54.9%, max drawdown 6.06%, 71 trades — closely matches
  in-sample, no degradation.
- Reached after retiring a prior strategy (`london_orb`, in `_graveyard/`)
  whose continuation thesis failed identically across three different
  entry filters — this fade thesis is a genuinely different, validated
  idea, not a variant of a failed one.

## Verdict: Not ready for live, but a genuinely borderline case

**This is not a curve-fit strategy** — out-of-sample performance matched
in-sample closely on every metric that matters (profit factor, win rate,
drawdown), which is real evidence against overfitting. That's worth
weighing seriously; a lot of strategies fail specifically by looking great
in-sample and collapsing out-of-sample, and this one didn't.

**But I wouldn't put real capital on it yet, for three reasons:**

1. **The edge is thin everywhere it's been measured.** Profit factor has
   stayed in a narrow 1.05–1.14 band across every honest test (in-sample,
   out-of-sample, and every reasonable parameter variation) — never
   comfortably above 1. A thin edge is fragile: live slippage, occasional
   requotes, wider spreads during news, or a slightly different execution
   model than the backtest assumed could plausibly erase it.
2. **2018 is a confirmed, unexplained failure mode.** A targeted fix
   (volatility filter) solved 2020's COVID-crash problem but left 2018
   untouched — meaning there's a regime this strategy loses money in that
   isn't yet understood, only patched around for one specific case.
3. **Absolute returns are modest.** Roughly $1,100 combined profit on a
   $10,000 account across the full 8 years tested (2018–2025) — call it
   1-2%/year. Even taking the edge at face value, it's a small return for
   the effort and residual risk.

**What would change my mind:** understanding *why* 2018 lost (the way we
diagnosed 2020's COVID-crash pattern) and confirming a fix doesn't just
curve-fit that year in hindsight; and/or a demo-account forward test
period to see if the thin edge survives real execution conditions before
committing capital. Given how close this one is, a demo/paper-trading
period is a reasonable middle path here specifically — not because it's
the default answer, but because the evidence is genuinely borderline
rather than clearly negative.
