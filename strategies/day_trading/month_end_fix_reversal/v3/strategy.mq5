//+------------------------------------------------------------------+
//| month_end_fix_reversal v3 - fade the WM/Reuters 4pm London FX fix  |
//| spike, restricted to the final trading days of the month, day      |
//| trading only.                                                       |
//|                                                                      |
//| Direct descendant of wm_fix_reversal v2's mechanism (identical      |
//| fix-window measurement, volatility-adaptive threshold, fade logic)  |
//| but built on a different, more specific hypothesis: wm_fix_reversal |
//| faded EVERY day's fix spike regardless of cause (routine noise vs.  |
//| genuine flow both counted equally, direction unknown until          |
//| measured) and found only a thin edge (PF ~1.04-1.06 out-of-sample). |
//|                                                                      |
//| This version targets a specific, named institutional mechanism      |
//| documented in FX-flow research: large asset managers, pension       |
//| funds, and corporates rebalance currency hedges at MONTH-END based  |
//| on that month's realized equity performance, with flow               |
//| concentrating in the final 2-3 trading days and peaking on the      |
//| last day, specifically around the London 4pm fix. The hypothesis    |
//| is that month-end fix spikes are more often genuine flow-driven     |
//| (and thus more reliably reversion-prone once the flow clears) than  |
//| an average day's fix spike, which could be pure noise.              |
//|                                                                      |
//| Same volatility-adaptive threshold technique used throughout this   |
//| project (rolling average of the fix window's own recent history),  |
//| now gated additionally by a "is today near month-end" calendar      |
//| filter.                                                              |
//|                                                                      |
//| v2 (2026-09-23) was a SAFETY-ONLY patch on top of v1: added         |
//| InpAllowLiveAccount + the matching OnInit() refusal check, mirroring|
//| gotobi/v1's exact pattern. Zero entry/exit/sizing/threshold logic   |
//| changed from v1.                                                    |
//|                                                                      |
//| v3 (2026-09-23) BACKFILLS the rest of the standard safety ledger    |
//| that v2 was still missing (consecutive-loss halt, daily-loss halt,  |
//| drawdown kill-switch/balancePeak tracking -- CLAUDE.md's kill-switch|
//| section implies these are standard across strategy EAs, and sibling |
//| gotobi/v1 already has all of them), copied line-for-line from       |
//| gotobi/v1/strategy.mq5's pattern: consecutiveLosses +                |
//| InpMaxConsecutiveLosses, an OnTradeTransaction() handler that        |
//| increments/resets it on deal close, monthlyHaltActive +              |
//| haltSetYear/haltSetMonth + CheckMonthlyHaltResume(), dailyStartBalance|
//| + dailyHaltActive + InpDailyLossStopPercent + UpdateDailyLossHalt(), |
//| balancePeak + drawdownHaltActive + InpMaxDrawdownStopPercent +       |
//| UpdateDrawdownHalt(), and InpResetLedgerNow/InpResetDrawdownStop      |
//| manual-reset inputs. These are wired in so they can only SUPPRESS a  |
//| trade v2 would have taken (checked immediately before order          |
//| placement) -- they never add a trade v2 would not have taken.        |
//|                                                                      |
//| v3 also adds the on-chart status panel (Comment()-based, 1s OnTimer  |
//| refresh) required by .claude/agents/ea-coder.md's "Chart status      |
//| panel" convention before a version can be flagged live_candidate.    |
//|                                                                      |
//| IMPORTANT: because the safety ledger can suppress trades that v2's   |
//| backtest took (any trade opened while a halt would now be active),   |
//| v2's review.md/VERDICT.md numbers do NOT automatically carry over to |
//| v3 -- this version needs a fresh backtest before any live/demo       |
//| decision is made on it. Entry/exit trigger logic, spike-threshold    |
//| math, sizing, and timing are otherwise byte-for-byte unchanged from  |
//| v2.                                                                  |
//+------------------------------------------------------------------+
#property copyright "month_end_fix_reversal"
#property version   "3.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Fix window timing (broker/server clock) -----------------------------
input int    FixHourServer     = 18;   // 16:00 London == 18:00 server, year-round
input int    FixMinuteServer   = 0;
input int    PreFixMinutes     = 5;
input int    PostFixMinutes    = 2;
input int    HoldMinutes       = 30;

// -- Month-end calendar filter ----------------------------------------------
input int    TradeLastNDaysOfMonth = 3;  // only trade if today is within this many calendar days of month-end

// -- Volatility-adaptive spike filter --------------------------------------
input double MinSpikeVsAvgMultiplier = 2.0;  // starting from wm_fix_reversal v2's locked value
input double MinSpikeSizePipsFloor   = 5.0;
input int    SpikeHistoryWindow      = 20;
input int    MinHistoryToAdapt       = 5;

// -- Trade parameters ------------------------------------------------------
input double SLMultiplier      = 1.0;
input double TPMultiplier      = 1.0;
input double RiskPercent       = 1.0;
input double MaxSpreadPips     = 3.0;
input int    EndOfDayHour      = 22;
input int    MagicNumber       = 20260090;

// -- Safety rules (always on) -- backfilled in v3, copied from gotobi/v1 --
input int    InpMaxConsecutiveLosses   = 6;   // pause after this many losses in a row
input double InpDailyLossStopPercent   = 5.0; // no more trades today after losing this % of balance today
input double InpMaxDrawdownStopPercent = 15.0;// hard stop after this % drawdown from the balance peak
input bool   InpResetLedgerNow         = false; // manually clear the consecutive-loss pause
input bool   InpResetDrawdownStop      = false; // manually clear the drawdown hard-stop

// -- Live safety -----------------------------------------------------------
input bool   InpAllowLiveAccount  = false; // must be explicitly set true to run on a REAL account

// -- Chart panel -------------------------------------------------------------
input string InpValidatedSymbols  = "EURUSD.r,GBPUSD.r,USDJPY"; // comma-separated -- per VERDICT.md, backtested independently AND as a 3-pair portfolio (v1_portfolio/), not just this version's own single-symbol spec.json

double pipSize;

int      currentDay = -1;
bool     isMonthEndWindow = false;
datetime windowStart = 0;
datetime windowEnd   = 0;
datetime scheduledExitTime = 0;
double   priceAtWindowStart = 0;
bool     haveWindowStartPrice = false;
bool     windowEvaluated = false;
bool     tradeTakenToday = false;

double   spikeHistory[];
int      spikeHistoryCount = 0;
int      spikeHistoryNext = 0;

// -- Safety ledger state (backfilled in v3) --------------------------------
int      consecutiveLosses  = 0;
bool     monthlyHaltActive  = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;

double   balancePeak       = 0;
bool     drawdownHaltActive = false;

// -- Chart panel state --------------------------------------------------------
string   g_status = "INIT";
string   g_lastAction = "";

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("month_end_fix_reversal ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("month_end_fix_reversal ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      g_status = "INIT FAILED: refusing to start on a REAL account (InpAllowLiveAccount=false)";
      RenderPanel();
      return INIT_FAILED;
   }

   consecutiveLosses = 0;
   monthlyHaltActive = false;
   drawdownHaltActive = false;
   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);

   ArrayResize(spikeHistory, SpikeHistoryWindow);
   ResetDayState(TimeCurrent());

   EventSetTimer(1);
   g_status = "RUNNING";
   RenderPanel();
   return(INIT_SUCCEEDED);
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

int DayOfYearOf(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day_of_year + s.year * 1000;
}

int HourOf(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour;
}

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

double AverageSpikeHistory()
{
   double sum = 0;
   for(int i = 0; i < spikeHistoryCount; i++)
      sum += spikeHistory[i];
   return sum / spikeHistoryCount;
}

void PushSpikeHistory(double spikePips)
{
   spikeHistory[spikeHistoryNext] = spikePips;
   spikeHistoryNext = (spikeHistoryNext + 1) % SpikeHistoryWindow;
   if(spikeHistoryCount < SpikeHistoryWindow)
      spikeHistoryCount++;
}

double CurrentAdaptiveThreshold()
{
   if(spikeHistoryCount < MinHistoryToAdapt)
      return MinSpikeSizePipsFloor;
   return MathMax(MinSpikeSizePipsFloor, MinSpikeVsAvgMultiplier * AverageSpikeHistory());
}

void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);

   int lastDay = DaysInMonth(s.mon, s.year);
   isMonthEndWindow = (s.day > lastDay - TradeLastNDaysOfMonth);

   MqlDateTime f = s;
   f.hour = FixHourServer;
   f.min  = FixMinuteServer;
   f.sec  = 0;
   datetime fixTime = StructToTime(f);

   windowStart = fixTime - PreFixMinutes * 60;
   windowEnd   = fixTime + PostFixMinutes * 60;
   scheduledExitTime = windowEnd + HoldMinutes * 60;

   haveWindowStartPrice = false;
   windowEvaluated = false;
   tradeTakenToday = false;
   priceAtWindowStart = 0;

   // Backfilled in v3, mirrors gotobi/v1's ResetDayState.
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;
}

// -- Safety ledger (backfilled in v3, copied from gotobi/v1/strategy.mq5) --

void CheckMonthlyHaltResume(const MqlDateTime &s)
{
   if(!monthlyHaltActive)
      return;
   if(s.year > haltSetYear || (s.year == haltSetYear && s.mon > haltSetMonth))
   {
      monthlyHaltActive = false;
      consecutiveLosses = 0;
      Print("month_end_fix_reversal ", _Symbol, ": new month -- consecutive-loss pause lifted.");
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
         Alert("month_end_fix_reversal ", _Symbol, ": drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
               "% from peak balance) -- halted until manually reset (InpResetDrawdownStop).");
      drawdownHaltActive = true;
   }
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
         Print("month_end_fix_reversal ", _Symbol, ": ", InpMaxConsecutiveLosses,
               " consecutive losses -- pausing until the first day of next month.");
      }
   }
   else
   {
      consecutiveLosses = 0;
   }
}

double CalculateLotSize(double slDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPriceUnit = tickValue / tickSize;
   double lots = riskAmount / (slDistance * valuePerPriceUnit);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathFloor(lots / step) * step;
   lots = MathMin(maxLot, lots);
   if(lots < minLot)
      return 0.0;
   return lots;
}

// -- Chart status panel (added in v3, per .claude/agents/ea-coder.md) --------

bool IsSymbolValidated(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(p == _Symbol)
         return true;
   }
   return false;
}

double CurrentDrawdownPercent()
{
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balancePeak <= 0)
      return 0.0;
   return (balancePeak - balanceNow) / balancePeak * 100.0;
}

void RenderPanel()
{
   string modeStr = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) ? "LIVE" : "DEMO";

   string statusLine;
   if(!IsSymbolValidated(InpValidatedSymbols))
      statusLine = "Status: WARNING: SYMBOL NOT VALIDATED FOR THIS EA";
   else
      statusLine = "Status: " + g_status;

   string positionLine = "Position: FLAT";
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      string side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double vol = PositionGetDouble(POSITION_VOLUME);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double slPrice = PositionGetDouble(POSITION_SL);
      double tpPrice = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double curPrice = (side == "BUY") ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double pipsPL = (side == "BUY") ? (curPrice - entryPrice) / pipSize : (entryPrice - curPrice) / pipSize;
      positionLine = StringFormat("Position: %s %s @ %s  SL %s TP %s  P/L $%s (%sp)",
                        side, DoubleToString(vol, 2), DoubleToString(entryPrice, _Digits),
                        DoubleToString(slPrice, _Digits), DoubleToString(tpPrice, _Digits),
                        DoubleToString(profit, 2), DoubleToString(pipsPL, 1));
   }

   MqlDateTime nowS;
   TimeToStruct(TimeCurrent(), nowS);
   int lastDay = DaysInMonth(nowS.mon, nowS.year);
   bool eligible = (nowS.day > lastDay - TradeLastNDaysOfMonth);

   string eaBlock = StringFormat(
      "Month-end window: day %d of %d -- %s (last %d days of month)\n"
      "Fix window: %s - %s | scheduled exit: %s\n"
      "Spike history: %d/%d samples | avg %s pips | adaptive threshold %s pips",
      nowS.day, lastDay, eligible ? "ELIGIBLE" : "not eligible", TradeLastNDaysOfMonth,
      TimeToString(windowStart, TIME_MINUTES), TimeToString(windowEnd, TIME_MINUTES),
      TimeToString(scheduledExitTime, TIME_MINUTES),
      spikeHistoryCount, SpikeHistoryWindow,
      spikeHistoryCount > 0 ? DoubleToString(AverageSpikeHistory(), 1) : "n/a",
      DoubleToString(CurrentAdaptiveThreshold(), 1));

   string panel = StringFormat(
      "month_end_fix_reversal v3 | %s | %s\n"
      "Validated: %s\n"
      "Risk/trade: %s%%  |  DD from peak: %s%% (limit %s%%)\n"
      "%s\n"
      "Safety: losses %d/%d\n"
      "%s\n"
      "Last: %s\n"
      "--------------------------------------------------\n"
      "%s",
      _Symbol, modeStr,
      InpValidatedSymbols,
      DoubleToString(RiskPercent, 2), DoubleToString(CurrentDrawdownPercent(), 2), DoubleToString(InpMaxDrawdownStopPercent, 1),
      statusLine,
      consecutiveLosses, InpMaxConsecutiveLosses,
      positionLine,
      g_lastAction,
      eaBlock);

   Comment(panel);
}

void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime s;
   TimeToStruct(now, s);
   int dayId = DayOfYearOf(now);
   if(dayId != currentDay)
   {
      currentDay = dayId;
      ResetDayState(now);
      CheckMonthlyHaltResume(s);
   }

   // -- Safety ledger housekeeping (backfilled in v3) -----------------------
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

   if(monthlyHaltActive)
      g_status = "HALTED: consecutive-loss pause (resumes next calendar month)";
   else if(dailyHaltActive)
      g_status = "HALTED: daily loss stop hit";
   else if(drawdownHaltActive)
      g_status = "HALTED: drawdown stop hit";
   else
      g_status = "RUNNING";

   if(HourOf(now) >= EndOfDayHour && PositionSelect(_Symbol))
   {
      trade.PositionClose(_Symbol);
      g_lastAction = TimeToString(now, TIME_MINUTES) + " end-of-day flat close";
      RenderPanel();
      return;
   }

   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      if(now >= scheduledExitTime)
      {
         trade.PositionClose(_Symbol);
         g_lastAction = TimeToString(now, TIME_MINUTES) + " scheduled hold-time exit";
      }
      RenderPanel();
      return;
   }

   // Feed the spike-history baseline every day regardless of the month-end
   // filter, so the rolling average reflects genuine ambient volatility,
   // not just month-end days (same principle as the "feed history on every
   // pass/fail" pattern used throughout this project).
   if(!windowEvaluated && haveWindowStartPrice && now >= windowEnd)
   {
      windowEvaluated = true;
      double priceNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double spike = priceNow - priceAtWindowStart;
      double spikePips = MathAbs(spike) / pipSize;
      PushSpikeHistory(spikePips);

      if(!isMonthEndWindow || tradeTakenToday)
      {
         g_lastAction = TimeToString(now, TIME_MINUTES) + " fix window measured (" + DoubleToString(spikePips, 1) + "p), not eligible to trade today";
         RenderPanel();
         return;
      }

      // Backfilled in v3: these can only SUPPRESS an entry v2 would have
      // taken, never add one -- checked immediately before any of v2's
      // original threshold/spread/sizing checks below.
      if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
      {
         g_lastAction = TimeToString(now, TIME_MINUTES) + " skip entry: safety halt active";
         RenderPanel();
         return;
      }

      double threshold;
      if(spikeHistoryCount < MinHistoryToAdapt)
         threshold = MinSpikeSizePipsFloor;
      else
         threshold = MathMax(MinSpikeSizePipsFloor, MinSpikeVsAvgMultiplier * AverageSpikeHistory());

      if(spikePips < threshold)
      {
         g_lastAction = TimeToString(now, TIME_MINUTES) + " skip entry: spike " + DoubleToString(spikePips, 1) + "p below threshold " + DoubleToString(threshold, 1) + "p";
         RenderPanel();
         return;
      }

      double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
      if(spreadPips > MaxSpreadPips)
      {
         g_lastAction = TimeToString(now, TIME_MINUTES) + " skip entry: spread " + DoubleToString(spreadPips, 1) + "p above max " + DoubleToString(MaxSpreadPips, 1) + "p";
         RenderPanel();
         return;
      }

      double slDistance = spikePips * pipSize * SLMultiplier;
      double tpDistance  = spikePips * pipSize * TPMultiplier;

      if(spike > 0)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = bid + slDistance;
         double tp = bid - tpDistance;
         double lots = CalculateLotSize(sl - bid);
         if(lots > 0)
         {
            trade.Sell(lots, _Symbol, bid, sl, tp);
            tradeTakenToday = true;
            g_lastAction = TimeToString(now, TIME_MINUTES) + " SELL entered (fade up-spike)";
         }
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = ask - slDistance;
         double tp = ask + tpDistance;
         double lots = CalculateLotSize(ask - sl);
         if(lots > 0)
         {
            trade.Buy(lots, _Symbol, ask, sl, tp);
            tradeTakenToday = true;
            g_lastAction = TimeToString(now, TIME_MINUTES) + " BUY entered (fade down-spike)";
         }
      }
      RenderPanel();
      return;
   }

   if(tradeTakenToday)
   {
      RenderPanel();
      return;
   }

   if(!haveWindowStartPrice && now >= windowStart && now < windowEnd)
   {
      priceAtWindowStart = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      haveWindowStartPrice = true;
      g_lastAction = TimeToString(now, TIME_MINUTES) + " captured fix-window start price";
   }

   RenderPanel();
}
