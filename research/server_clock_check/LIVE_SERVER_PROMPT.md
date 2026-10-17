Deploy month_end_fix_reversal **v4** to replace the v3 that's running live, before **2026-10-29**. The user approves this upgrade: same scope as v3 (EURUSD.r and GBPUSD.r only, USDJPY held back) and the same live inputs (InpAllowLiveAccount=true, RiskPercent=0.5).

1. `git pull` on main. Then read `strategies/day_trading/month_end_fix_reversal/v4/spec.json`, `v4/v3_vs_v4.md` and `research/server_clock_check/README.md`.
2. What v4 fixes (no strategy-logic change):
   - The broker server clock follows US DST (NY close + 7). On US/EU DST-mismatch days, which are this year's Oct 25–31, the London 4pm fix is at 19:00 server, not 18:00. v3 traded an hour early on those days. v4 shifts the fix window automatically.
   - v3's 22:00-server end-of-day close used `PositionSelect(_Symbol)` with no magic check, so it could close **other EAs' or manual positions** on EURUSD.r/GBPUSD.r. v4 only touches its own position (symbol + magic 20260090, closed by ticket).
3. Check that the v3 instances are flat. Don't swap while either has an open position; wait for it to close. Then compile v4 with `scripts/compile_ea.py`. Remove v3 from both charts and attach v4 with the same inputs as v3, plus `InpDstMismatchShift=true`. Same magic number, so the ledger behaviour is unchanged.
4. Verify:
   - Both charts' panels say "month_end_fix_reversal v4".
   - The Experts journal shows no INIT_FAILED.
   - The panel's fix-window line shows 17:55–18:02 today. From Oct 25 to 31 it should show "DST mismatch day: YES (fix +1h)" with an 18:55–19:02 window.
5. In the registry, under `day_trading/month_end_fix_reversal`:
   - Set `current_version` to v4 and remove `pending_version`.
   - Keep status `live` and add a history row noting the v3→v4 swap.
   - Log the deployment in `live-manager/lessons.md`.
   - Commit and push.
6. Separately, as a report only (don't change gotobi): gotobi v2's month-based server-time rule mistimes entry between Mar 1 and the 2nd Sunday of March, and between Nov 1 and the 1st Sunday of November. The next affected day is 2027-03-05. A fix will come through the dev machine later.
