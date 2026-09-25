# month_end_fix_reversal — date ranges

- **In-sample (optimization):** 2018.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Same split as `gotobi`/`wm_fix_reversal`/`london_range_fade`, for
cross-strategy comparability.

## Origin
Built 2026-09-23 per the user's "hunt for another [specific-event
strategy]" instruction. Direct descendant of `wm_fix_reversal` v2's
mechanism (identical fix-window measurement/fade logic), narrowed to a
more specific hypothesis backed by FX-flow research: large asset
managers, pension funds, and corporates rebalance currency hedges at
month-end based on that month's realized equity performance, with flow
concentrating in the final 2-3 trading days and peaking on the last day,
specifically around the London 4pm fix. `wm_fix_reversal` faded every
day's fix spike regardless of cause and found only a thin edge (PF
~1.04-1.06 out-of-sample) — this tests whether restricting to the days
research says the flow actually concentrates produces a cleaner signal
than the "every day" version.

## Session
Same fix-window mechanism as `wm_fix_reversal`: measure the fix-window
move at 16:00 London (18:00 server), fade it if it clears an adaptive
volatility threshold — now gated to only fire within
`TradeLastNDaysOfMonth` (3, default) calendar days of month-end.

## Symbol
EURUSD.r first, matching `wm_fix_reversal`'s primary pair.
