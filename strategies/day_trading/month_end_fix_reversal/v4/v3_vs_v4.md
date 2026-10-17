# month_end_fix_reversal: v3 vs v4 (DST-aware fix hour) backtest diff

Run 2026-10-18 by Backtester. Settings match v3 on every leg: Model=4 (every
tick, real ticks), Login=YOUR_ACCOUNT_LOGIN, Deposit 10000 USD, Leverage 100, M1,
all other inputs at v3 values. The only input change is
`InpDstMismatchShift=true` on legs 1-4 and `false` on leg 5.

Mismatch-day rule (from spec.json `dst_fix.rule`): a server date is a mismatch day if it falls on or after
the 2nd Sunday of March and before the last Sunday of March, or on or after the last Sunday of
October and before the 1st Sunday of November.

## Verification

| Check | Result |
|---|---|
| (a) Leg 5 (EURUSD.r IS, `InpDstMismatchShift=false`) vs `v3/journal.csv` | **PASS.** 35 vs 35 trades, every column of every row identical, `summary.csv` identical |
| (b) Leg 1 EURUSD.r IS: mismatch to 19:02, others to 18:02 | **PASS.** 34 trades, 0 on mismatch dates, all 18:02 |
| (b) Leg 2 EURUSD.r OOS | **PASS.** 16 trades, 0 on mismatch dates, all 18:02 |
| (b) Leg 3 GBPUSD.r IS | **PASS.** 39 trades, 2 on mismatch dates (both 19:02), 37 at 18:02 |
| (b) Leg 4 GBPUSD.r OOS | **PASS.** 20 trades, 2 on mismatch dates (both 19:02), 18 at 18:02 |

No safety-ledger halt messages (consecutive-loss / daily / drawdown) appear in
any leg's tester log, so no knock-on effects came through the ledger.

## Headline metrics

| Leg | Trades v3 / v4 | Net P&L v3 / v4 | PF v3 / v4 | Bal DD max v3 / v4 | Eq DD max v3 / v4 |
|---|---|---|---|---|---|
| EURUSD.r IS 2018-2022 | 35 / 34 | 133.67 / 37.87 | 1.12 / 1.03 | 288.09 (2.88%) / 288.09 (2.88%) | 354.20 (3.53%) / 354.20 (3.53%) |
| EURUSD.r OOS 2023-2025 | 19 / 16 | 669.37 / 624.56 | 2.21 / 2.27 | 131.56 (1.26%) / 122.84 (1.16%) | 242.89 (2.31%) / 131.65 (1.30%) |
| GBPUSD.r IS 2018-2022 | 37 / 39 | 696.42 / 634.26 | 1.67 / 1.58 | 179.72 (1.80%) / 186.72 (1.85%) | 255.11 (2.51%) / 255.11 (2.52%) |
| GBPUSD.r OOS 2023-2025 | 21 / 20 | 603.46 / 867.64 | 2.05 / 3.05 | 148.73 (1.40%) / 126.58 (1.24%) | 215.73 (2.02%) / 188.10 (1.77%) |

## Trade-level differences (matched on open date; at most one trade per day)

### EURUSD.r in-sample
- Only in v3: 2021.03.31 18:02 sell 1.14, +93.10. **Not a mismatch date.** Most likely a knock-on
  through the 20-day spike history: 2021.03.14-26 were mismatch days, so v4 fed true-fix-window
  samples into the rolling average instead of 15:00-London samples. That most likely raised the adaptive
  threshold above this day's 8.7-pip spike. This is inferred: the EA does not log its threshold.
- Only in v4: none.
- Common dates: side, entry, exit and close time are identical on all of them. 13 differ only in lot
  size, which follows from equity-based sizing after the missing +93.10.

### EURUSD.r out-of-sample
- Only in v3 (all mismatch dates): 2024.03.29 buy -26.73; 2024.10.30 buy +94.74; 2024.10.31 buy -24.82.
- Only in v4: none. On those dates the real 19:00 fix spike did not clear the threshold.
- Common dates: prices and times identical; 3 differ in lots only (equity knock-on).

### GBPUSD.r in-sample
- Only in v3: none.
- Only in v4 (mismatch dates, 19:02): 2018.10.29 buy -22.37; 2018.10.31 buy -31.02.
- Common dates: prices and times identical; 7 differ in lots only.

### GBPUSD.r out-of-sample
- Only in v3 (all mismatch dates): 2024.10.30 buy +97.46; 2024.10.31 buy -106.99; 2025.10.29 sell -53.89.
- Only in v4 (mismatch dates, 19:02): 2023.10.31 sell +96.17; 2025.10.31 sell +100.94.
- Common dates: prices and times identical; 7 differ in lots only.

## Notes
- Across 8 years of EURUSD.r, v4 never takes a trade on a mismatch date. So the positive 19:02
  timing evidence comes only from the GBPUSD.r legs (4 trades). Both pairs run the same EA code and
  the same rule.
- Every difference on a non-mismatch date is either a lot-size change (equity compounding) or the
  single EURUSD 2021.03.31 spike-history knock-on. Nothing else changed.
- Every trade sample is small (16-39 trades per leg), well below the project's 200-trade bar.
