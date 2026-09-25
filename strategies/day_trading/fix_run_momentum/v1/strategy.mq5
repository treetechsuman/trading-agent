//+------------------------------------------------------------------+
//| fix_run_momentum v1 - go WITH the pre-fix directional run into the |
//| WM/Reuters 4pm London FX fix (dealer pre-positioning / "banging     |
//| the close" flow), day trading only.                                 |
//|                                                                      |
//| Structural cousin of wm_fix_reversal/month_end_fix_reversal (same    |
//| fix-window timing family, same volatility-adaptive threshold design |
//| -- compare each day's measured move to a rolling average of its OWN |
//| recent history, not a fixed pip bar) but with THREE deliberate       |
//| differences from those two:                                         |
//|   1. The measurement window is entirely BEFORE the fix snapshot     |
//|      (17:56:00-17:59:00 server, i.e. fix-4min to fix-1min), not      |
//|      straddling it like wm_fix_reversal's Pre/PostFixMinutes window. |
//|   2. Direction is MOMENTUM (buy if price rose into the window close, |
//|      sell if it fell) -- the opposite convention from wm_fix_reversal|
//|      /month_end_fix_reversal's fade.                                 |
//|   3. Entry fires immediately at measurement-window close (17:59:00   |
//|      server) and the hold is a deliberately tight 2 minutes, exiting |
//|      at 18:01:00 server (1 min after the fix print) -- to capture    |
//|      the pre-fix run and the fix print itself, then get out BEFORE   |
//|      the post-fix giveback/reversion that wm_fix_reversal's own       |
//|      (separate) thesis targets has time to dominate.                 |
//|                                                                       |
//| Built WITH the full safety ledger from its very first version per    |
//| this project's own standing lesson (see ea-coder/lessons.md's        |
//| month_end_fix_reversal/v2 entry: "every strategy coded from now on   |
//| must include this from its very first version") -- InpAllowLiveAccount|
//| live-account guard, consecutive-loss halt, daily-loss halt, and      |
//| drawdown kill-switch (balancePeak tracking), all copied line-for-line|
//| from gotobi/v1/strategy.mq5's pattern. No chart status panel yet --   |
//| per this project's convention that panel is only required once a     |
//| version is being flagged live_candidate, not at initial coding.      |
//|                                                                       |
//| JUDGMENT CALL flagged for Researcher (not a strategy-logic decision, |
//| a literal-text ambiguity in spec.json): spec.json's                  |
//| entry.entry_time field reads "18:59:00 -> immediately at             |
//| measurement-window close, 17:59:00 server time (15:59:00 London)" --  |
//| the leading "18:59:00" contradicts the rest of the same sentence, the |
//| measurement_window field (which ends at 17:59:00), and the exit rule  |
//| ("exactly 2 minutes after entry, 1 minute after the fix snapshot",    |
//| i.e. 18:01:00 -- only consistent with an entry at 17:59:00, since an  |
//| entry at 18:59:00 would be 59 minutes AFTER the fix and after the     |
//| stated exit time, contradicting the entire pre-fix-momentum thesis).  |
//| Coded against 17:59:00 (measurement-window close) as the only value   |
//| internally consistent with the rest of the spec; treated "18:59:00"   |
//| as a typo, not a distinct instruction to silently follow instead.     |
//+------------------------------------------------------------------+
#property copyright "fix_run_momentum"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Fix window timing (broker/server clock) -------------------------------
// The WM/Reuters fix is defined in London local time (16:00:00) for all three
// symbols traded here (EURUSD.r/GBPUSD.r/USDJPY) -- a London-session event,
// not a per-pair Tokyo-session one like gotobi -- so there is no per-pair or
// per-month DST branch needed: this broker's server clock (EET/EEST) shifts
// DST on the same calendar dates as UK/EU clocks and is always exactly 2
// hours ahead of London time year-round (per spec.json's
// broker_clock_conversion, reusing wm_fix_reversal's already-verified
// assumption unmodified).
input int    FixHourServer                      = 18;  // 16:00 London == 18:00 server, year-round
input int    FixMinuteServer                    = 0;
input int    MeasureWindowStartMinutesBeforeFix = 4;   // window opens fix-4min = 17:56:00 server
input int    MeasureWindowEndMinutesBeforeFix   = 1;   // window closes / entry fires fix-1min = 17:59:00 server
input int    ExitDelayMinutesAfterFix           = 1;   // scheduled exit fix+1min = 18:01:00 server (exactly 2 min after entry)

// -- Volatility-adaptive run-size filter ------------------------------------
// Reused unmodified from wm_fix_reversal v2's proven design: compare today's
// measured |net move| to a rolling average of the SAME window's own recent
// history, not a fixed absolute pip bar (a fixed bar was shown there to
// collapse out-of-sample trade frequency when ambient volatility fell).
// Values below are spec.json's stated v1 defaults (its own text describes
// these as wm_fix_reversal v2's validated calibration; note MinHistoryToAdapt
// here is 20, not wm_fix_reversal v2's actual coded default of 5 -- coded
// exactly as spec.json states, flagging the discrepancy for Researcher rather
// than silently reconciling it either way).
input double MinRunVsAvgMultiplier = 2.0;  // trade only if today's run >= this x the recent average run size
input double MinRunSizePipsFloor   = 5.0;  // absolute floor regardless of how quiet the recent average is
input int    RunHistoryWindow      = 20;   // how many past trading days' runs to average over
input int    MinHistoryToAdapt     = 20;   // fall back to the floor alone until this many days of history exist

// -- Trade parameters --------------------------------------------------------
input double SLMultiplier      = 1.0;  // stop = run size * this, placed against the entry direction
input double TPMultiplier      = 1.0;  // target = run size * this, placed in the entry (continuation) direction
input double RiskPercent       = 0.5;  // % of account EQUITY risked per trade
input double MaxSpreadPips     = 3.0;
input int    EndOfDayHour      = 22;   // force-flat time, server time -- day trading only, never hold overnight
input int    MagicNumber       = 20260130;

// -- Safety rules (always on) -- gotobi/v1's pattern, included from v1 -----
input int    InpMaxConsecutiveLosses   = 6;   // pause after this many losses in a row
input double InpDailyLossStopPercent   = 5.0; // no more trades today after losing this % of balance today
input double InpMaxDrawdownStopPercent = 15.0;// hard stop after this % drawdown from the balance peak
input bool   InpResetLedgerNow         = false; // manually clear the consecutive-loss pause
input bool   InpResetDrawdownStop      = false; // manually clear the drawdown hard-stop

// -- Live safety -------------------------------------------------------------
input bool   InpAllowLiveAccount  = false; // must be explicitly set true to run on a REAL account

double pipSize;

int      currentDay = -1;           // year*1000 + day_of_year, drives daily state resets
datetime windowStart = 0;
datetime windowEnd   = 0;
datetime scheduledExitTime = 0;
double   priceAtWindowStart = 0;
bool     haveWindowStartPrice = false;
bool     windowEvaluated = false;
bool     tradeTakenToday = false;

double   runHistory[];
int      runHistoryCount = 0;
int      runHistoryNext = 0;

// -- Safety ledger state (gotobi/v1's pattern) -------------------------------
int      consecutiveLosses  = 0;
bool     monthlyHaltActive  = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;

double   balancePeak       = 0;
bool     drawdownHaltActive = false;

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

double AverageRunHistory()
{
   double sum = 0;
   for(int i = 0; i < runHistoryCount; i++)
      sum += runHistory[i];
   return sum / runHistoryCount;
}

void PushRunHistory(double runPips)
{
   runHistory[runHistoryNext] = runPips;
   runHistoryNext = (runHistoryNext + 1) % RunHistoryWindow;
   if(runHistoryCount < RunHistoryWindow)
      runHistoryCount++;
}

void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);

   MqlDateTime f = s;
   f.hour = FixHourServer;
   f.min  = FixMinuteServer;
   f.sec  = 0;
   datetime fixTime = StructToTime(f);

   windowStart       = fixTime - MeasureWindowStartMinutesBeforeFix * 60;
   windowEnd         = fixTime - MeasureWindowEndMinutesBeforeFix * 60;
   scheduledExitTime = fixTime + ExitDelayMinutesAfterFix * 60;

   haveWindowStartPrice = false;
   windowEvaluated = false;
   tradeTakenToday = false;
   priceAtWindowStart = 0;

   // gotobi/v1's pattern: daily-loss halt baseline captured once per day,
   // folded into the same day-change reset (no separate day-change detection
   // needed).
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;
}

// -- Safety ledger (copied line-for-line from gotobi/v1/strategy.mq5) -------

void CheckMonthlyHaltResume(const MqlDateTime &s)
{
   if(!monthlyHaltActive)
      return;
   if(s.year > haltSetYear || (s.year == haltSetYear && s.mon > haltSetMonth))
   {
      monthlyHaltActive = false;
      consecutiveLosses = 0;
      Print("fix_run_momentum ", _Symbol, ": new month -- consecutive-loss pause lifted.");
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
         Alert("fix_run_momentum ", _Symbol, ": drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
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
         Print("fix_run_momentum ", _Symbol, ": ", InpMaxConsecutiveLosses,
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
      return 0.0; // skip rather than force up to the minimum -- see project convention
   return lots;
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("fix_run_momentum ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("fix_run_momentum ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }

   consecutiveLosses = 0;
   monthlyHaltActive = false;
   drawdownHaltActive = false;
   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);

   ArrayResize(runHistory, RunHistoryWindow);
   ResetDayState(TimeCurrent());

   return(INIT_SUCCEEDED);
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

   // -- Safety ledger housekeeping (gotobi/v1's pattern) --------------------
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

   // EOD flat -- day trading only, never hold overnight
   if(HourOf(now) >= EndOfDayHour && PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      trade.PositionClose(_Symbol);
      return;
   }

   // Manage an open position: fixed-time exit (SL/TP are broker-side orders,
   // handled automatically by the tester/broker if hit first)
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      if(now >= scheduledExitTime)
         trade.PositionClose(_Symbol);
      return;
   }

   if(tradeTakenToday)
      return;

   // Capture the price at the start of the pre-fix measurement window
   if(!haveWindowStartPrice && now >= windowStart && now < windowEnd)
   {
      priceAtWindowStart = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      haveWindowStartPrice = true;
      return;
   }

   // At window close (== the scheduled entry instant), measure the run,
   // update the rolling history, and decide whether today's run is large
   // enough RELATIVE TO RECENT VOLATILITY to trade -- then enter immediately
   // WITH the run's direction (momentum, not fade).
   if(!windowEvaluated && haveWindowStartPrice && now >= windowEnd)
   {
      windowEvaluated = true;

      double priceNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double run = priceNow - priceAtWindowStart;
      double runPips = MathAbs(run) / pipSize;

      // Feed the rolling average regardless of pass/fail, so the "normal"
      // baseline isn't itself distorted by excluding the events it exists to
      // detect (same principle used throughout this project's fix-window
      // strategies).
      PushRunHistory(runPips);

      // Safety halts can only SUPPRESS an entry, never add one -- checked
      // immediately before the threshold/spread/sizing checks below, same
      // relative position as gotobi/v1's and month_end_fix_reversal/v3's gate.
      if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
         return;

      double threshold;
      if(runHistoryCount < MinHistoryToAdapt)
         threshold = MinRunSizePipsFloor; // not enough history yet -- fall back to the floor
      else
         threshold = MathMax(MinRunSizePipsFloor, MinRunVsAvgMultiplier * AverageRunHistory());

      if(runPips < threshold)
         return; // not large enough relative to recent volatility -- skip

      double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
      if(spreadPips > MaxSpreadPips)
         return;

      double slDistance = runPips * pipSize * SLMultiplier;
      double tpDistance = runPips * pipSize * TPMultiplier;

      if(run > 0)
      {
         // Price rose into the fix -- go WITH it (momentum continuation): buy
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = ask - slDistance;
         double tp = ask + tpDistance;
         double lots = CalculateLotSize(ask - sl);
         if(lots > 0)
         {
            trade.Buy(lots, _Symbol, ask, sl, tp);
            tradeTakenToday = true;
         }
      }
      else if(run < 0)
      {
         // Price fell into the fix -- go WITH it (momentum continuation): sell
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = bid + slDistance;
         double tp = bid - tpDistance;
         double lots = CalculateLotSize(sl - bid);
         if(lots > 0)
         {
            trade.Sell(lots, _Symbol, bid, sl, tp);
            tradeTakenToday = true;
         }
      }
      return;
   }
}
