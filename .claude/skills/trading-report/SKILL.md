---
name: trading-report
description: Report from the live Linux MT5 server (Vultr, 45.77.236.85) - trades taken per EA and their P&L, balance/equity, open positions, whether MT5 is running, Algo Trading on/off, MT5 restarts and crashes, broker connection, EA errors and server health. Read-only. Use when Suman types /trading-report or asks how the live server / EAs / trades are doing.
---

# /trading-report

Read-only. This skill never starts, stops or changes anything on the server.
If the report shows a problem, say what it is and ask before doing anything
(numbered options, question at the end — Suman reads this on his phone).

## 1. Run the report

Optional argument: number of days to cover (default 7), e.g. `/trading-report 30`.
Run from the repo root with the Bash tool:

```bash
/c/Windows/System32/OpenSSH/ssh.exe -o ConnectTimeout=15 trader@45.77.236.85 "python3 - --days 7" < server/linux/trading_report.py
```

The script is piped in from the repo, so the server always runs the current version.

If SSH fails:
- Use the **Windows OpenSSH** path above. Git Bash's own `ssh` can't see the key.
- If you get `Permission denied (publickey)`, run `C:\Windows\System32\OpenSSH\ssh-add.exe -l`. If the key `suman-pc-vultr-mt5` is missing, ask Suman to run `ssh-add C:\Users\Suman\.ssh\vultr_mt5` in PowerShell himself. Never ask for the passphrase or any password in chat.
- If it times out, the server may be rebooting (weekend reboot is Sat 06:00 UTC) or down. Try once more after a minute, then tell him and suggest checking the Vultr console.

More connection details are in `LINUX_SERVER.md` → "Quick reference".

## 2. Tell Suman (short, phone-friendly)

Start with one line: **All good** or **Needs attention: <what>**. Then cover these, in this order, a few lines each:

1. **Warnings** from the report's WARNINGS block, explained in plain words. Skip any that are expected (see the notes below).
2. **Trades**:
   - closed trades in the period per EA: count, wins/losses, net P&L in AUD
   - any open positions
   - any failed or rejected orders
3. **Account**: balance, equity, and the distance from the 15% safety stop.
4. **MT5**:
   - running or not, and the Algo Trading button ON/OFF
   - whether the 4 EAs are loaded
   - MT5 starts, crash restarts and server reboots
   - broker connection and ping
5. **Server**: memory, disk and clock, one line, and only if something is off.

Offer the full raw report if he wants it. Don't paste it unasked.

## Notes for reading the report

- **Trade history is account-wide**, from the broker. It includes trades the old Windows server took and Suman's old manual trades (shown as "manual", magic 0). For EA performance, look at the per-EA lines.
  - gotobi = magic 20260030
  - month_end_fix_reversal = magic 20260090
- **Expected trading days**:
  - gotobi trades only on gotobi days (the 5th/10th/15th/20th/25th/month-end, or the business day before), entry about 00:45 UTC.
  - month_end trades only on the last trading day of the month, around the 16:00 London fix.
  - A week with no trades is normal.
- **Algo Trading OFF** is a real warning: the Linux server has been the live one since 2026-11-08 10:11 UTC. If another IP shows up logging in, check that the old Windows server's Algo Trading is still off. Both on at once doubles every trade.
- **MT5 starts on 2026-11-08** were the setup work. After that, starts that don't match a reboot or a planned change are worth a mention. A crash restart (systemd auto-restart) is always worth a mention.
- **Connection drops**: the report already ignores drops caused by an MT5 restart. A few a week are normal internet blips. Many in one day are worth a mention.
- **No status file / status file old**: the account_reporter EA on chart04 has stopped. Balance and trades can't be read until it's fixed. The fix is to restart MT5 cleanly with `~/stop-mt5.sh`, then `sudo -n systemctl start mt5`, and only after asking Suman.
- **"Same account also logged in from other IPs"**: the old Windows server or Suman's PC/phone logged in. Fine, except after the switch-over, when it may mean the old server is still running. If so, ask whether its Algo Trading is off.
