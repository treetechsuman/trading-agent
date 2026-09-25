//+------------------------------------------------------------------+
//| gotobi v2 - sell into the Tokyo pre-fixing dollar-buying spike on |
//| Japanese "gotobi" payment days, day trading only. One ~35-minute   |
//| SELL per gotobi day, closed by the clock rather than a target.     |
//|                                                                     |
//| Intended to run as one copy per pair (USDJPY, EURJPY, GBPJPY) on   |
//| its own chart -- each instance tracks its own position, risk       |
//| sizing and safety ledger independently, which is also how it is    |
//| backtested here (MT5's standard tester only trades the chart's     |
//| own symbol, so each pair gets its own single-symbol run).          |
//|                                                                     |
//| Entry/exit are fixed BROKER-SERVER clock times, hardcoded per       |
//| calendar month rather than derived from TimeGMT() -- TimeGMT() is  |
//| not simulated inside the Strategy Tester (it reflects the real     |
//| host clock, not simulated time), so the UTC target times (00:45    |
//| entry / 01:20 exit) were pre-converted to this broker's server      |
//| clock by hand: server leads UTC by 3h Mar-Oct, 2h Nov-Feb.          |
//|                                                                     |
//| v2 (2026-09-23) is a DISPLAY-ONLY patch on top of v1: adds the      |
//| on-chart Comment() status panel now required (before               |
//| live_candidate/live_candidate_final) by .claude/agents/ea-coder.md |
//| "Chart status panel" convention -- identity/DEMO-LIVE line,         |
//| Validated-symbols line, risk/drawdown line, Status line (with the   |
//| unvalidated-symbol WARNING case), Safety line, Position line, Last  |
//| line, and a gotobi-specific block showing today's gotobi-day        |
//| eligibility plus the next entry window/countdown. Wired via         |
//| OnTimer() (1s refresh, for the long idle stretches between gotobi   |
//| days) in addition to OnTick(), rendered before the INIT_FAILED      |
//| return on the live-account guard, and cleared with Comment("") in   |
//| OnDeinit(). NO entry/exit/sizing/timing/safety logic changed from   |
//| v1 at all -- every existing safety-ledger variable                  |
//| (consecutiveLosses, dailyHaltActive, drawdownHaltActive,            |
//| balancePeak, InpAllowLiveAccount) and every trading rule is byte-   |
//| for-byte identical to v1; this version only adds display code and  |
//| the new InpValidatedSymbols input the panel reads from. v1's        |
//| review.md/VERDICT.md findings (and the resulting approved_live      |
//| status) apply unchanged to v2, since nothing that affects trading   |
//| behavior was touched.                                                |
//+------------------------------------------------------------------+
#property copyright "gotobi"
#property version   "2.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Trade timing (broker/server clock) --------------------------------
input int    InpEntryHourSummer   = 3;    // Mar-Oct server hour for the 00:45 UTC entry
input int    InpEntryMinuteSummer = 45;
input int    InpEntryHourWinter   = 2;    // Nov-Feb server hour for the 00:45 UTC entry
input int    InpEntryMinuteWinter = 45;
input int    InpLateEntryMinutes  = 10;   // still enter up to this many minutes late, then skip the day
input int    InpHoldMinutes       = 35;   // exit this many minutes after the nominal (on-time) entry clock time

// -- Trade parameters ----------------------------------------------------
input double InpStopLossPips      = 20.0; // protective stop, set once at entry, never moved
input double InpRiskPercent       = 0.5;  // % of account balance risked if the stop is hit
input double InpMaxSpreadPips     = 3.0;  // skip entry if spread is wider than this
input int    MagicNumber          = 20260030;

// -- Safety rules (always on) --------------------------------------------
input int    InpMaxConsecutiveLosses   = 6;   // pause after this many losses in a row
input double InpDailyLossStopPercent   = 5.0; // no more trades today after losing this % of balance today
input double InpMaxDrawdownStopPercent = 15.0;// hard stop after this % drawdown from the balance peak
input bool   InpResetLedgerNow         = false; // manually clear the consecutive-loss pause
input bool   InpResetDrawdownStop      = false; // manually clear the drawdown hard-stop

// -- Live safety -----------------------------------------------------------
input bool   InpAllowLiveAccount  = false; // must be explicitly set true to run on a REAL account

// -- Chart status panel ----------------------------------------------------
input string InpValidatedSymbols  = "USDJPY,EURJPY.r,GBPJPY.r"; // comma-separated symbols this version was backtested/validated on (spec.json "symbols")

double pipSize;

int      currentDay = -1;           // year*1000 + day_of_year, drives daily state resets
bool     isGotobiDay = false;
bool     enteredToday = false;
datetime entryWindowStart = 0;
datetime entryWindowEnd   = 0;
datetime scheduledExitTime = 0;

int      consecutiveLosses  = 0;
bool     monthlyHaltActive  = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;

double   balancePeak       = 0;
bool     drawdownHaltActive = false;

// -- Chart status panel state ------------------------------------------
string   g_status       = "";
string   g_lastAction   = "EA starting...";
string   g_initFailReason = ""; // set only when OnInit refuses to start; empty otherwise

bool IsLeapYear(int y)
{
   return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
}

int DaysInMonth(int mon, int year)
{
   switch(mon)
   {
      case 1: case 3: case 5: case 7: case 8: case 10: case 12: return 31;
      case 4: case 6: case 9: case 11: return 30;
      case 2: return IsLeapYear(year) ? 29 : 28;
   }
   return 30;
}

bool IsGotobiDate(const MqlDateTime &s)
{
   if(s.day_of_week == 0 || s.day_of_week == 6) // Sunday/Saturday -- skip, no make-up day
      return false;
   if(s.mon == 2)
   {
      int lastDay = DaysInMonth(2, s.year);
      return (s.day == 5 || s.day == 10 || s.day == 15 || s.day == 20 || s.day == 25 || s.day == lastDay);
   }
   return (s.day == 5 || s.day == 10 || s.day == 15 || s.day == 20 || s.day == 25 || s.day == 30);
}

bool IsSummerBroker(int mon)
{
   return (mon >= 3 && mon <= 10);
}

double CalculateLotSize(double slDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPriceUnit = tickValue / tickSize;
   double lots = riskAmount / (slDistance * valuePerPriceUnit);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   lots = MathMin(maxLot, lots);
   return lots; // deliberately NOT floored up to the broker minimum -- see TryEnter()
}

void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);
   isGotobiDay = IsGotobiDate(s);
   enteredToday = false;

   int entryHour   = IsSummerBroker(s.mon) ? InpEntryHourSummer   : InpEntryHourWinter;
   int entryMinute = IsSummerBroker(s.mon) ? InpEntryMinuteSummer : InpEntryMinuteWinter;

   MqlDateTime w = s;
   w.hour = entryHour;
   w.min  = entryMinute;
   w.sec  = 0;
   entryWindowStart  = StructToTime(w);
   entryWindowEnd    = entryWindowStart + InpLateEntryMinutes * 60;
   // Exit is a fixed clock time off the nominal (on-time) entry, not off the
   // actual (possibly late) fill -- "closed by the clock, not a target".
   scheduledExitTime = entryWindowStart + InpHoldMinutes * 60;

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;

   SetLastAction(isGotobiDay ? "new day -- gotobi day, entry window computed" : "new day -- not a gotobi day");
}

void CheckMonthlyHaltResume(const MqlDateTime &s)
{
   if(!monthlyHaltActive)
      return;
   if(s.year > haltSetYear || (s.year == haltSetYear && s.mon > haltSetMonth))
   {
      monthlyHaltActive = false;
      consecutiveLosses = 0;
      Print("gotobi ", _Symbol, ": new month -- consecutive-loss pause lifted.");
   }
}

void UpdateDailyLossHalt()
{
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dailyStartBalance > 0 && (dailyStartBalance - balanceNow) >= dailyStartBalance * InpDailyLossStopPercent / 100.0)
      dailyHaltActive = true;
}

void UpdateDrawdownHalt()
{
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balanceNow > balancePeak)
      balancePeak = balanceNow;
   if(balancePeak > 0 && (balancePeak - balanceNow) >= balancePeak * InpMaxDrawdownStopPercent / 100.0)
   {
      if(!drawdownHaltActive)
         Alert("gotobi ", _Symbol, ": drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
               "% from peak balance) -- halted until manually reset (InpResetDrawdownStop).");
      drawdownHaltActive = true;
   }
}

void CloseStalePosition()
{
   if(!PositionSelect(_Symbol))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return;

   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
   MqlDateTime a, b;
   TimeToStruct(openTime, a);
   TimeToStruct(TimeCurrent(), b);
   bool sameDay = (a.year == b.year && a.day_of_year == b.day_of_year);
   if(!sameDay)
   {
      Print("gotobi ", _Symbol, ": closing stale position left open from a previous day at EA startup.");
      SetLastAction("closed stale position left open from a previous day at startup");
      trade.PositionClose(_Symbol);
   }
}

void ManageOpenPosition(datetime now)
{
   if(!PositionSelect(_Symbol))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return;
   if(now >= scheduledExitTime)
   {
      SetLastAction("closed position at scheduled exit time (nominal entry + hold minutes)");
      trade.PositionClose(_Symbol);
   }
}

void TryEnter()
{
   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
   if(spreadPips > InpMaxSpreadPips)
   {
      SetLastAction(StringFormat("skip entry -- spread %.1fp above max %.1fp", spreadPips, InpMaxSpreadPips));
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = bid + InpStopLossPips * pipSize;
   double slDistance = sl - bid;

   double lots = CalculateLotSize(slDistance);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lots < minLot)
   {
      Print("gotobi ", _Symbol, ": skip, computed lot ", DoubleToString(lots, 2),
            " below broker minimum ", DoubleToString(minLot, 2));
      SetLastAction(StringFormat("skip entry -- computed lot %.2f below broker minimum %.2f", lots, minLot));
      return;
   }

   double marginRequired;
   if(!OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, lots, bid, marginRequired))
   {
      SetLastAction("skip entry -- OrderCalcMargin failed");
      return;
   }
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      Print("gotobi ", _Symbol, ": skip, insufficient free margin");
      SetLastAction("skip entry -- insufficient free margin");
      return;
   }

   if(trade.Sell(lots, _Symbol, bid, sl, 0.0)) // no take-profit -- closed by the clock
   {
      enteredToday = true;
      SetLastAction(StringFormat("SELL %.2f lots @ %s, SL %s", lots, DoubleToString(bid, _Digits), DoubleToString(sl, _Digits)));
   }
   else
   {
      SetLastAction(StringFormat("entry order failed, retcode %d", trade.ResultRetcode()));
   }
}

// ---------------------------------------------------------------------
// Chart status panel (display-only, added v2 -- see .claude/agents/
// ea-coder.md "Chart status panel" for the locked format/wiring rules).
// ---------------------------------------------------------------------

void SetLastAction(string msg)
{
   g_lastAction = TimeToString(TimeCurrent(), TIME_MINUTES) + " " + msg;
}

bool IsSymbolValidated()
{
   string list = InpValidatedSymbols;
   StringReplace(list, " ", "");
   list += ",";
   string sym = _Symbol + ",";
   return (StringFind(list, sym) >= 0);
}

string HaltReason()
{
   string parts = "";
   if(monthlyHaltActive)
      parts += "consecutive losses";
   if(dailyHaltActive)
      parts += (parts == "" ? "" : ", ") + "daily loss";
   if(drawdownHaltActive)
      parts += (parts == "" ? "" : ", ") + "drawdown";
   return parts;
}

string ComputeStatusLine()
{
   if(g_initFailReason != "")
      return "INIT FAILED: " + g_initFailReason;
   if(!IsSymbolValidated())
      return "WARNING: SYMBOL NOT VALIDATED FOR THIS EA";
   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
      return "HALTED: " + HaltReason();
   return "RUNNING";
}

string FormatCountdown(long totalSeconds)
{
   if(totalSeconds < 0)
      totalSeconds = 0;
   long days  = totalSeconds / 86400;
   long hours = (totalSeconds % 86400) / 3600;
   long mins  = (totalSeconds % 3600) / 60;
   long secs  = totalSeconds % 60;
   if(days > 0)
      return StringFormat("%dd %dh %dm", days, hours, mins);
   if(hours > 0)
      return StringFormat("%dh %dm", hours, mins);
   return StringFormat("%dm %ds", mins, secs);
}

// Scans forward from 'from' (inclusive) up to 40 calendar days to find the
// next gotobi entry-window start time that has not yet begun. Pure display
// helper -- does not read or modify any trading state.
datetime NextGotobiEntryWindow(datetime from)
{
   MqlDateTime s;
   TimeToStruct(from, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   datetime dayStart = StructToTime(s);

   for(int i = 0; i <= 40; i++)
   {
      datetime d = dayStart + i * 86400;
      MqlDateTime ds;
      TimeToStruct(d, ds);
      if(!IsGotobiDate(ds))
         continue;

      int entryHour   = IsSummerBroker(ds.mon) ? InpEntryHourSummer   : InpEntryHourWinter;
      int entryMinute = IsSummerBroker(ds.mon) ? InpEntryMinuteSummer : InpEntryMinuteWinter;

      MqlDateTime w = ds;
      w.hour = entryHour;
      w.min  = entryMinute;
      w.sec  = 0;
      datetime entryStart = StructToTime(w);
      if(entryStart >= from)
         return entryStart;
   }
   return 0; // shouldn't happen -- gotobi days occur every calendar month
}

string BuildGotobiBlock()
{
   datetime now = TimeCurrent();

   string line1 = StringFormat("Gotobi day today: %s", isGotobiDay ? "YES" : "NO");

   string line2;
   if(isGotobiDay && !enteredToday && now >= entryWindowStart && now <= entryWindowEnd)
      line2 = StringFormat("Entry window: OPEN, closes in %s", FormatCountdown((long)(entryWindowEnd - now)));
   else if(isGotobiDay && enteredToday)
      line2 = "Entry window: CLOSED (already entered today)";
   else if(isGotobiDay && !enteredToday && now > entryWindowEnd)
      line2 = "Entry window: CLOSED (missed today's window)";
   else
      line2 = "Entry window: n/a (not a gotobi day)";

   datetime nextEntry = NextGotobiEntryWindow(now);
   string line3;
   if(nextEntry > 0)
      line3 = StringFormat("Next entry window: %s server (in %s)",
                            TimeToString(nextEntry, TIME_DATE | TIME_MINUTES),
                            FormatCountdown((long)MathMax(0, (double)(nextEntry - now))));
   else
      line3 = "Next entry window: unknown";

   return line1 + "\n" + line2 + "\n" + line3;
}

void RenderPanel()
{
   string acctType = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) ? "LIVE" : "DEMO";
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddPct = (balancePeak > 0) ? (balancePeak - balanceNow) / balancePeak * 100.0 : 0.0;

   string posLine = "FLAT";
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string side   = (ptype == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double lots   = PositionGetDouble(POSITION_VOLUME);
      double entryPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double slPx   = PositionGetDouble(POSITION_SL);
      double tpPx   = PositionGetDouble(POSITION_TP);
      double curPx  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double pl     = PositionGetDouble(POSITION_PROFIT);
      double pips   = (ptype == POSITION_TYPE_BUY) ? (curPx - entryPx) / pipSize : (entryPx - curPx) / pipSize;

      posLine = StringFormat("%s %s @ %s  SL %s TP %s  P/L $%s (%sp)",
                              side, DoubleToString(lots, 2), DoubleToString(entryPx, _Digits),
                              DoubleToString(slPx, _Digits),
                              (tpPx > 0 ? DoubleToString(tpPx, _Digits) : "none"),
                              DoubleToString(pl, 2), DoubleToString(pips, 1));
   }

   g_status = ComputeStatusLine();

   string panel = StringFormat(
      "gotobi v2 | %s | %s\n" +
      "Validated: %s\n" +
      "Risk/trade: %s%%  |  DD from peak: %s%% (limit %s%%)\n" +
      "Status: %s\n" +
      "Safety: losses %d/%d\n" +
      "Position: %s\n" +
      "Last: %s\n" +
      "--------------------------------------------------\n" +
      "%s",
      _Symbol, acctType,
      InpValidatedSymbols,
      DoubleToString(InpRiskPercent, 2), DoubleToString(ddPct, 2), DoubleToString(InpMaxDrawdownStopPercent, 1),
      g_status,
      consecutiveLosses, InpMaxConsecutiveLosses,
      posLine,
      g_lastAction,
      BuildGotobiBlock()
   );

   Comment(panel);
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("gotobi ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("gotobi ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      g_initFailReason = "refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm";
      RenderPanel();
      return INIT_FAILED;
   }

   consecutiveLosses = 0;
   monthlyHaltActive = false;
   drawdownHaltActive = false;
   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);

   CloseStalePosition();

   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   currentDay = s.year * 1000 + s.day_of_year;
   ResetDayState(TimeCurrent());

   EventSetTimer(1); // 1s refresh so the panel's countdowns don't freeze between ticks

   RenderPanel();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
}

void OnTimer()
{
   RenderPanel();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(profit < 0)
   {
      consecutiveLosses++;
      if(consecutiveLosses >= InpMaxConsecutiveLosses && !monthlyHaltActive)
      {
         monthlyHaltActive = true;
         MqlDateTime s;
         TimeToStruct(TimeCurrent(), s);
         haltSetYear = s.year;
         haltSetMonth = s.mon;
         Print("gotobi ", _Symbol, ": ", InpMaxConsecutiveLosses,
               " consecutive losses -- pausing until the first day of next month.");
      }
   }
   else
   {
      consecutiveLosses = 0;
   }
}

void ProcessTick(datetime now, const MqlDateTime &s)
{
   int dayId = s.year * 1000 + s.day_of_year;
   if(dayId != currentDay)
   {
      currentDay = dayId;
      ResetDayState(now);
      CheckMonthlyHaltResume(s);
   }

   if(InpResetLedgerNow)
   {
      monthlyHaltActive = false;
      consecutiveLosses = 0;
   }
   if(InpResetDrawdownStop)
   {
      drawdownHaltActive = false;
      balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   UpdateDrawdownHalt();
   UpdateDailyLossHalt();

   ManageOpenPosition(now);

   if(!isGotobiDay || enteredToday)
   {
      SetLastAction(!isGotobiDay ? "idle -- not a gotobi day" : "idle -- already entered today");
      return;
   }
   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
   {
      SetLastAction("halted: " + HaltReason());
      return;
   }
   if(PositionSelect(_Symbol)) // never add to an open position / never more than one per pair per day
   {
      SetLastAction("idle -- position already open, waiting for scheduled exit");
      return;
   }
   if(now < entryWindowStart || now > entryWindowEnd)
   {
      SetLastAction(now < entryWindowStart ? "idle -- waiting for entry window to open" : "idle -- missed entry window (late grace expired)");
      return;
   }

   TryEnter();
}

void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime s;
   TimeToStruct(now, s);

   ProcessTick(now, s);
   RenderPanel();
}
