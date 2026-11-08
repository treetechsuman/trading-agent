# LINUX_SERVER.md — live MT5 server on Vultr Ubuntu (Wine)

Runbook for the **live/deploy server** (see CLAUDE.md "Two-machine split"),
moving it from a Vultr Windows server (~US$30.80/mo) to a Vultr Ubuntu
server (~US$10/mo) running MT5 under Wine. Written 2026-11-08. Every step
here is meant to be repeatable to rebuild the server from nothing.

Config files used below live in `server/linux/`.

## Quick reference: connecting and managing it (read this first)

**Who manages it:** the dev PC's Claude sessions, over SSH (user's decision,
2026-11-08). There is no separate Claude running on the server; Claude Code
is installed there (`~/.local/bin/claude`) only as a spare and is not signed in.
Any new session on the dev PC can connect; nothing depends on one session.

| What | Value |
|---|---|
| Server | Vultr `mt5-linux`, Sydney, Ubuntu 24.04, 1 vCPU / 2 GB, $10/mo |
| IP / user | `45.77.236.85` / `trader` (root and password login are off) |
| SSH key (dev PC) | `C:\Users\Suman\.ssh\vultr_mt5` (passphrase-protected), loaded in the Windows **ssh-agent** service (startup type Automatic), so no passphrase prompt is needed |
| SSH client | **Windows OpenSSH** `C:\Windows\System32\OpenSSH\ssh.exe` / `scp.exe`. Git Bash's own `ssh` does NOT see the Windows agent. |
| sudo | `trader`'s sudo needs a password the user holds; **never ask for it in chat**. Passwordless (`sudo -n`): `systemctl start/stop/restart mt5`, `systemctl start/stop/restart tigervncserver@:1`, `/usr/sbin/reboot` |
| MT5 install | `~/.mt5/drive_c/Program Files/FP Markets MetaTrader 5/` (portable: `logs/`, `Config/`, `MQL5/`) |
| Account | FPMarkets-Live, Raw account (`.r` symbols), hedging; login in `scripts/local_settings.py` (gitignored) |
| Repo on server | `~/trading-agent` (`scripts/common.py` skip-worktree, portable paths) |

From the dev PC (Bash tool, Git Bash syntax):
```bash
SSH=/c/Windows/System32/OpenSSH/ssh.exe
$SSH trader@45.77.236.85 'systemctl is-active mt5'          # is MT5 running?
$SSH trader@45.77.236.85 '~/mt5log.sh 40'                   # last 40 lines of today's MT5 log
$SSH trader@45.77.236.85 "python3 - --days 7" < server/linux/trading_report.py   # full report (= /trading-report)
$SSH trader@45.77.236.85 '~/stop-mt5.sh'                    # stop MT5 CLEANLY (waits for it to save)
$SSH trader@45.77.236.85 'sudo -n systemctl start mt5'      # start MT5
```
If SSH fails with "Permission denied (publickey)": check that the key is in the agent with
`C:\Windows\System32\OpenSSH\ssh-add.exe -l`. If it's missing, the user runs
`ssh-add C:\Users\Suman\.ssh\vultr_mt5` in PowerShell and types the passphrase there, never in chat.

Remote desktop (to see MT5's screen): start the tunnel with
`C:\Windows\System32\OpenSSH\ssh.exe -N -L 5901:localhost:5901 trader@45.77.236.85`, then open
`C:\Program Files\TightVNC\tvnviewer.exe localhost::5901`. It asks for the VNC password the user set.

**Rules:**
- Never have Algo Trading ON on this server and on the old Windows server at the same time, or trades double.
- Stop MT5 only with `~/stop-mt5.sh`. A bare `systemctl stop` right after `taskkill` killed MT5 mid-save on 2026-11-08 and left `chart01.chr` 0 bytes.
- Chart and EA changes: stop MT5, run `server/linux/setup_charts.py` (§8b), start MT5, then check the log says 4 EAs `loaded successfully`.
- Compile `.mq5` files on the dev PC (§8) and copy the `.ex5` over.

**`/trading-report`** (skill in `.claude/skills/trading-report/`) runs
`server/linux/trading_report.py` on the server over SSH. The report is read-only and covers:
- MT5 service state, the Algo Trading button, and broker connection and ping
- MT5 starts, crash auto-restarts and server reboots
- balance, equity and open positions
- closed trades per EA (from the account's full deal history), and failed or rejected trade requests
- EA log messages, MT5 errors, and server memory, disk, updates and clock

Balance and trade data come from the read-only **account_reporter** EA on chart04
(`server/linux/account_reporter/v1/`). It writes `MQL5/Files/EAFactory_status.json`
every 60 s and never trades.

## 0. Decisions and why

| Decision | Choice | Why |
|---|---|---|
| Plan | Vultr **Cloud Compute → Shared CPU → Regular Performance, 1 vCPU / 2 GB / 55 GB SSD, $10/mo** | MT5 under Wine ≈ 400–600 MB, XFCE + VNC ≈ 300 MB, Claude Code ≈ 300–500 MB while a session runs. Fits with a 2 GB swap file as headroom. If it ever swaps hard, resize in place to 4 GB ($20) — no rebuild. |
| Region | **Sydney** | User's choice (2026-11-08), kept after measuring. MT5 connects to an FP Markets access point in Sydney (AWS `ap-southeast-2`, <1 ms away) which relays to the real trade server; MT5's ping is **~286 ms** (dev PC: 302 ms), consistent with the trade server being in **London**. The old Windows server had the same latency, and the live strategies (gotobi, month-end fix) hold for hours, so it's acceptable. For a latency-sensitive strategy, rebuild in **London** (same runbook, only the location click changes; expect ~1–5 ms). |
| OS | Ubuntu 24.04 LTS x64 | MetaQuotes' Linux script supports it; LTS = security updates to 2029. |
| MT5 install | MetaQuotes' official `mt5linux.sh` | The method MetaQuotes documents for Linux; installs WineHQ + MT5. |
| Remote desktop | TigerVNC + XFCE, **listening on localhost only**, reached through an SSH tunnel | Only port 22 is open to the internet. VNC also has its own password as a second lock. |
| Firewall | `ufw`: SSH only, + `fail2ban` | Remote desktop rides inside SSH, so nothing else needs opening. |
| Updates | `unattended-upgrades` (security only), reboot only Saturday 06:00 UTC if needed | Forex is closed Fri ~21:00 → Sun ~21:00 UTC, so a reboot never lands mid-trade. |
| Auto-start | systemd: `tigervncserver@:1` (desktop) → `mt5.service` (`Restart=always`) | MT5 comes up after reboot and is restarted 20 s after any crash. |
| Python | **Native Linux Python**, not Windows Python under Wine | Nothing in this repo uses the `MetaTrader5` Python package, DLLs, or sockets. The only MT5 contact is calling `MetaEditor64.exe`/`terminal64.exe`, which works as `wine <exe>`. |

Monthly cost: **$10.00** server (+ optional ~$0.50/mo for one snapshot).
Vultr bills hourly, so running both servers during the overlap costs
about $0.33/day extra.

## 1. Make the SSH key (on the dev PC)

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\vultr_mt5 -C "suman-pc vultr-mt5"
```
Type a passphrase when asked (in the terminal, never in chat). Then let
Windows remember it for the session (one-time, admin PowerShell):
```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\vultr_mt5
```
The **public** key to paste into Vultr is `~\.ssh\vultr_mt5.pub` (one
line starting `ssh-ed25519`). The private key never leaves the PC.

## 2. Vultr account / card

Vultr bills per **account**, not per server. Make sure the account you
deploy in is paid by the personal card:
1. **Account** (top right) → **Billing** → **Payment Methods** — check which card is default.
2. If the Windows server's account uses the PonteWise card: either create a
   separate personal Vultr account, or change that account's card (which
   moves the old server's bill too).

## 3. Deploy the server (Vultr clicks)

1. **Deploy +** → **Deploy New Server**.
2. Type: **Cloud Compute** → **Shared CPU**.
3. Location: **Sydney**.
4. Image: **Ubuntu** → **24.04 LTS x64**.
5. Plan: **Regular Performance** → the **1 vCPU / 2 GB / 55 GB SSD — $10/mo** box.
6. Additional features: turn **Auto Backups** off (confirm the warning), leave **IPv6** on.
7. **SSH Keys** → **Add New** → name `suman-pc`, paste the public key → select it.
8. Hostname / Label: `mt5-linux`.
9. **Deploy Now**. Wait until status is **Running**, copy the **IP Address**.

## 4. First login + base setup (run from the dev PC)

Notes from the 2026-11-08 build (server `mt5-linux`, Sydney):
- On Windows use the built-in OpenSSH (`C:\Windows\System32\OpenSSH\ssh.exe`
  / `scp.exe`), not Git Bash's, so it uses the Windows ssh-agent from step 1.
- Vultr's Ubuntu image already has a ~5 GB swap partition; `setup-root.sh`
  only adds a swap file when there is none.
- Copied files may arrive with Windows line endings: run
  `sed -i 's/\r$//'` on them before use.
- A kernel update during setup needed one reboot; do it right away
  (nothing is trading yet).
- Vultr's new deploy page: Quick Deploy → **Instances** → Shared CPU →
  plan row `vc2-1c-2gb` → Sydney → **Configure** → image version
  **Ubuntu 24.04 LTS x64** (default was 26.10) → SSH key (add it first under
  **Orchestration → SSH Keys**, then reload the deploy page) → Automatic
  Backups toggle off (tick "I understand") → **Deploy**.

```bash
scp -i ~/.ssh/vultr_mt5 server/linux/* root@SERVER_IP:/root/
ssh -i ~/.ssh/vultr_mt5 root@SERVER_IP 'bash /root/setup-root.sh'
```
`setup-root.sh` creates user `trader` (same SSH key), firewall (SSH only),
fail2ban, automatic security updates, 2 GB swap, XFCE + TigerVNC + git +
Python. Then the **user sets trader's sudo password themself** in a
terminal (never in chat):
```bash
ssh -t -i ~/.ssh/vultr_mt5 root@SERVER_IP passwd trader
```
Weekend reboot timer:
```bash
ssh -i ~/.ssh/vultr_mt5 root@SERVER_IP 'cp /root/weekend-reboot.* /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now weekend-reboot.timer'
```

## 5. Lock down SSH (only after trader works)

1. Prove it: `ssh -i ~/.ssh/vultr_mt5 trader@SERVER_IP 'sudo -v && echo OK'` (type trader's password in the terminal).
2. Then:
```bash
ssh -t -i ~/.ssh/vultr_mt5 trader@SERVER_IP 'sudo cp /root/10-hardening.conf /etc/ssh/sshd_config.d/ && sudo sshd -t && sudo systemctl restart ssh'
```
3. Check root is refused: `ssh -i ~/.ssh/vultr_mt5 root@SERVER_IP` → `Permission denied`.
   Keep the first session open until a fresh `trader` login works.

Recovery if locked out: Vultr → server → **View Console** (browser
console, uses trader's password).

## 6. Remote desktop (VNC, localhost only)

As trader:
```bash
mkdir -p ~/.vnc && cp /root/tigervnc.conf ~/.vnc/   # (sudo cp + chown if needed)
vncpasswd          # the user types a strong VNC password, answer n to view-only
echo ":1=trader" | sudo tee -a /etc/tigervnc/vncserver.users
sudo systemctl enable --now tigervncserver@:1
```
Connect from the PC:
```bash
ssh -i ~/.ssh/vultr_mt5 -L 5901:localhost:5901 -N trader@SERVER_IP
```
then a VNC viewer (TigerVNC or RealVNC Viewer) → `localhost:5901`.

From the phone: an app that does SSH tunnelling itself — **bVNC**
(Android free / iOS) — with connection type "VNC over SSH", host
`SERVER_IP`, user `trader`, the phone's **own** SSH key (generate it in
the app, add its public key to `/home/trader/.ssh/authorized_keys`), VNC
host `localhost`, port `5901`.

## 7. Install MT5 (inside the VNC desktop)

Open the VNC desktop → **Applications → Terminal Emulator**, run
MetaQuotes' official command (not with sudo; it asks for trader's password):
```bash
wget https://download.terminal.free/cdn/web/metaquotes.software.corp/mt5/mt5linux.sh ; chmod +x mt5linux.sh ; ./mt5linux.sh
```
Say yes to Wine Mono/Gecko. MT5 lands in
`~/.mt5/drive_c/Program Files/MetaTrader 5/`.

In MT5: **File → Open an Account** → search `FP Markets` → pick
**FPMarkets-Live** → **Connect with an existing trade account** → login +
password (typed by the user in VNC), tick **Save password**. Check the
ping in the bottom-right status bar (expect low single-digit ms).

Note the data folder (**File → Open Data Folder**, usually
`~/.mt5/drive_c/users/trader/AppData/Roaming/MetaQuotes/Terminal/<hash>/`
or the program folder itself).

Close MT5 (**File → Exit**), then install the auto-start service:
```bash
which wine        # if not /usr/bin/wine, edit start-mt5.sh
# copy mt5.service, start-mt5.sh, sudoers-trader-mt5, install-autostart.sh to ~trader, then:
sh ~/install-autostart.sh     # asks trader's sudo password once
```

### What actually happened on the 2026-11-08 build (read before redoing)
- **Use FP Markets' own installer, freshly downloaded** (Client Portal →
  Platforms → MetaTrader 5 for Desktop → **Download Windows**). Run
  `mt5linux.sh` first only to get Wine, and **Cancel** its generic MT5
  installer. Then copy the FP installer to the server and run it on the VNC
  desktop: `DISPLAY=:1 WINEPREFIX=~/.mt5 wine fpmarkets5setup.exe`.
  A Jan-2025 copy of the same installer installed fine but **every login
  failed with "Invalid account"**; the fresh download logged in first time.
- MT5 under Wine is installed **portable-style**: data, `Config/`, `logs/`,
  `MQL5/` all live under
  `~/.mt5/drive_c/Program Files/FP Markets MetaTrader 5/` (no AppData
  folder). `~/mt5log.sh [lines] [regex]` prints today's terminal log.
- The FP Markets **Client Portal → Account Password** page can change the
  **Investor** (read-only) password. Logging in with that gives
  `trading has been disabled - investor mode`. The EAs need the **Master**.
- MT5 build 6308 starts an embedded Edge WebView for news (~1.3 GB RAM).
  Turning news off (`NewsEnable=0` in `Config/common.ini`, edit while MT5 is
  closed; the file is UTF-16LE) brought total RAM use to ~0.7–1.1 GB.
- `start-mt5.sh` holds the Windows path so systemd needs no backslash escaping.
- `sudoers-trader-mt5` lets trader (and Claude Code) start/stop/restart only
  `mt5` and `tigervncserver@:1`, and `reboot`, without a password.
- Tests passed: `kill -9` of terminal64.exe → back and logged in after 27 s;
  `sudo reboot` → MT5 logged in ~60 s after the reboot.
- From Windows, connect with **TightVNC Viewer** to `localhost::5901` (the
  new RealVNC Viewer demands an account). A reboot drops the SSH tunnel;
  restart it.

## 8. Repo, Python, compiling under Wine

```bash
git clone https://github.com/treetechsuman/trading-agent.git ~/trading-agent
cd ~/trading-agent
python3 -m venv .venv && .venv/bin/pip install beautifulsoup4==4.15.0 lxml==6.1.3
cp scripts/local_settings.example.py scripts/local_settings.py   # user sets ACCOUNT_LOGIN
```
Set `scripts/common.py`'s paths for this server, then
`git update-index --skip-worktree scripts/common.py` (same per-machine
rule as the other two machines). On this server all three point into the
portable install: `~/.mt5/drive_c/Program Files/FP Markets MetaTrader 5`
(+ `/terminal64.exe`, `/MetaEditor64.exe`; `MT5_DATA_DIR` is the folder itself).

`scripts/wine_compat.py` makes `compile_ea.py` run `wine MetaEditor64.exe`
with `winepath -w` paths on Linux (no change on Windows).

**Known gap (2026-11-08): MetaEditor's command-line compile does not work
under Wine yet.** `wine MetaEditor64.exe /compile:... /log:...` exits in
under a second with no `.ex5` and no log, with MT5 running or stopped, with
or without `/portable`, short paths or `start /wait`. Once, a compile did
happen ~1 minute later (both EAs, 0 errors), but it could not be repeated.
Until this is solved: **compile on the Windows dev PC** (`compile_ea.py`
there) and copy `strategy.ex5` into
`MQL5/Experts/EAFactory/<name>/<version>/` on the server, after checking the
dev copy's `strategy.mq5` matches the repo. MT5 build 6308 runs `.ex5` files
compiled by build 5830 fine. Opening the `.mq5` in MetaEditor on the VNC
desktop and pressing **F7** is the manual alternative.

## 8b. Live charts (set 2026-11-08; Algo Trading switched ON 2026-11-08 10:11 UTC)

**Switch-over:** Suman confirmed the old Windows server's Algo Trading was off. Then, at 10:11 UTC:
- `[Experts]` was set to `Enabled=1`, `Account=1`, `Profile=1`, matching the old server, plus `[Charts] MaxBars=10000`.
- MT5 was stopped with `~/stop-mt5.sh` and restarted. All 4 EAs loaded, and the status file shows the Algo Trading button ON and EA trading allowed.
- First real trade expected: gotobi on Tue 10 Nov, entry about 00:45 UTC.

From here on, this server is the live one. The old Windows server must keep Algo Trading OFF until it is deleted (§12).
Note: `setup_charts.py` (full run) forces Algo Trading **OFF** again, so turn it back on afterwards on purpose.

`server/linux/setup_charts.py` (run with MT5 stopped) writes the Default
profile and forces Algo Trading off (`[Experts] Enabled=0`):

| Chart | EA | Inputs changed from repo defaults |
|---|---|---|
| USDJPY.r M15 | gotobi v2 | InpRiskPercent=2.0, MagicNumber=20260030, InpAllowLiveAccount=true, InpValidatedSymbols=USDJPY,USDJPY.r,EURJPY.r,GBPJPY.r |
| EURUSD.r M15 | month_end_fix_reversal v5 | RiskPercent=1.0, MagicNumber=20260090, InpAllowLiveAccount=true (InpMaxMarginUsePercent=90 default) |
| GBPUSD.r M15 | month_end_fix_reversal v5 | same as EURUSD.r |
| EURUSD.r M15 (chart04) | account_reporter v1 (read-only, never trades) | none; writes `MQL5/Files/EAFactory_status.json` for `/trading-report` (added 2026-11-08) |

month_end v5 (margin fit) was deployed on the Windows server on 2026-10-31 but
never pushed. On 2026-11-08 the repo got the EXACT live file (commit `b56f2e8`,
rebuilt from a diff the Windows server produced; LF SHA-256 `bf40ea61...`),
compiled on the dev PC (0 errors) and swapped in here.

To stop MT5 cleanly, run **`~/stop-mt5.sh`** (from `server/linux/stop-mt5.sh`). MT5 rewrites the profile when it exits.
1. The script runs `wine taskkill /im terminal64.exe`.
2. It waits until the process has really gone, up to 90 s.
3. Only then does it run `sudo -n systemctl stop mt5`, before systemd's 20 s auto-restart.

Start again with `sudo -n systemctl start mt5`.

The old way was `systemctl stop` straight after `taskkill`. On 2026-11-08 it killed MT5 mid-save and left `chart01.chr` at 0 bytes, so gotobi did not load until the charts were rebuilt. `setup_charts.py` now takes its template from the first intact chart file, so a 0-byte file can't break it. When checking whether MT5 is running, use `pgrep -f 'terminal6[4]\.exe'`: the `[4]` stops pgrep from matching its own SSH command line.

`setup_charts.py --reporter-only` adds or refreshes only chart04 (account_reporter). It leaves charts 01–03 and Algo Trading untouched.

## 9. Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
cd ~/trading-agent && claude      # the user signs in (opens a URL + code)
```

## 10. Soak test (before moving any EA)

During this period **no EA trades on the new server** — the same EA on
two terminals on one account would double every trade. MT5 is logged in,
charts open, Algo Trading off.

- [ ] `sudo reboot` → MT5 is back and connected within ~2 min, no login prompt.
- [ ] `pkill -f terminal64.exe` → MT5 back within ~30 s.
- [ ] `free -h` while MT5 + a Claude session run: swap use small.
- [ ] VNC works from PC and phone.
- [ ] Root/password SSH refused; `sudo ufw status` shows only 22.
- [ ] `compile_ea.py` works under Wine.
- [ ] Runs 3+ days with no disconnects in MT5's Journal tab.

## 11. Cutover (a weekend, markets closed)

1. Old server: note every chart + EA + inputs (and anything else running).
   Remove the EAs from charts, **File → Exit**.
2. Copy over: `MQL5/Experts/EAFactory/` (or recompile), `MQL5/Profiles/Charts/Default/`,
   `MQL5/Files/` (any EA files), and `scripts/local_settings.py`. The repo
   itself comes from git; push anything uncommitted on the old server first.
3. New server: attach the EAs (GUI, or the profile method in
   `live-manager/lessons.md`), Algo Trading on, confirm "loaded
   successfully" in the Experts tab. Note: the EAs' safety ledger is
   in-memory, so a restart resets a loss-streak pause / drawdown stop.
4. Leave the old server switched on but not trading for a few days as a
   fallback.

## 12. Delete the old Windows server

1. (Optional) **Products** → old server → **Snapshots** → **Take Snapshot** (costs per GB/month; delete it later).
2. **Products** → old server → **Server Destroy** (trash icon) → tick confirm → **Destroy Server**.
3. Billing stops from that hour.
