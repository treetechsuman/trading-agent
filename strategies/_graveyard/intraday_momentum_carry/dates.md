# intraday_momentum_carry — date ranges

- **In-sample (optimization):** 2018.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Same split as `gotobi`, `london_range_fade`, and `wm_fix_reversal` — the
standard day-trading date range used throughout this project, for
cross-strategy comparability. (Scalping attempts used a shorter,
more-recent 2021-2023/2024-2025 split instead, on the theory that
scalping-scale microstructure edges decay faster than calendar-event
edges — that reasoning doesn't apply here, since this strategy trades a
well-established, decades-old academic anomaly, not a fragile
microstructure pattern.)

## Origin
Built 2026-09-23 per the user's "go for day trading" instruction after
all three scalping attempts (25+ configurations) were graveyarded,
combined with "think out of the box, research deeply." Unlike every
prior strategy in this project (internally-invented technical patterns,
even when session-anchored to a real event like `gotobi`/
`wm_fix_reversal`), this one trades a specific, published, peer-reviewed
academic finding: Gao, Han, Li & Zhou (2018, *Journal of Financial
Economics*) documented that a market's first half-hour return predicts
its last half-hour return in the same direction — statistically and
economically significant, robust to transaction costs, attributed to
daytrader/informed-trader behavior. Baltussen, van Vliet & Ye (2021)
extended this to 60+ futures across equities, bonds, commodities, and
**currencies** over 40+ years.

## Session
London session: 08:00-16:00 London = 10:00-18:00 this broker's server
time (constant year-round). First half-hour: 08:00-08:30 London
(10:00-10:30 server). Last half-hour: 15:30-16:00 London (17:30-18:00
server).

## Symbol
EURUSD.r first (most liquid, most directly analogous to the equity-index
context the original research studied); GBPUSD.r as a second pair if v1
shows promise, matching this project's established pattern.
