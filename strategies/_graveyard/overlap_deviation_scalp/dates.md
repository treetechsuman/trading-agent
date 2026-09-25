# overlap_deviation_scalp — date ranges

- **In-sample (optimization):** 2021.01.01 – 2023.12.31
- **Out-of-sample (validation):** 2024.01.01 – 2025.12.31

Same split as `overlap_momentum_scalp` (now graveyarded), kept for
comparability across scalping attempts.

## Symbols under test
Testing multiple pairs to check whether a better gross-edge-to-fixed-
commission ratio exists somewhere other than EURUSD.r — the constraint
diagnosed in the retired `overlap_momentum_scalp` line. Candidates:
GBPUSD.r, USDJPY, GBPJPY.r (all confirmed to have clean tick history on
this broker from ~2017.07-08 onward, per `gotobi`'s and
`wm_fix_reversal`'s own probing this session).

## Session
Same London/New York overlap as the retired line: 13:00-16:00 London =
15:00-18:00 this broker's server time.
