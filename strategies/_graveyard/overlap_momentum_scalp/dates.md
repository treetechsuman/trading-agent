# overlap_momentum_scalp — date ranges

- **In-sample (optimization):** 2021.01.01 – 2023.12.31
- **Out-of-sample (validation):** 2024.01.01 – 2025.12.31

Deliberately shorter and more recent than the 2018-2022/2023-2025 split
used for this project's other strategies (user's choice, 2026-09-22):
scalping edges depend on spread/liquidity microstructure, which can
shift faster than the slower calendar-event edges tested so far. A
strategy tuned on 2018 execution conditions might not reflect this
broker's current environment. Trade-off accepted: less data, thinner
out-of-sample, in exchange for relevance.

## Symbol
EURUSD.r — the account's tightest-spread major, important at scalping
target sizes where spread cost is a large fraction of the profit target.

## Session
London/New York overlap only: 13:00-16:00 London time = 15:00-18:00 this
broker's server time (constant year-round — see gotobi's/
wm_fix_reversal's dates.md for why the EET/EEST-to-London offset doesn't
shift with DST). Chosen over the full London session specifically for
its peak liquidity concentration, the property a momentum-continuation
scalp thesis most depends on.
