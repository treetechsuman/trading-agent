//+------------------------------------------------------------------+
//| london_breakout_retest v1 -- London-session breakout of the Asian |
//| session's range, entered NOT on the initial breakout impulse but  |
//| on a pullback retest of the broken boundary with a rejection-     |
//| candle confirmation (pin bar or engulfing), gated by an H1        |
//| directional-context filter. Delayed, confirmation-gated           |
//| CONTINUATION entry -- day trading only, EOD flat, no overnight.   |
//|                                                                     |
//| Runs on the M15 chart, one instance per pair (EURUSD.r, GBPUSD.r, |
//| USDJPY), each on its own chart -- MT5's standard Strategy Tester   |
//| only trades the chart's own symbol, so each pair is backtested     |
//| independently (single-symbol-per-chart, same pattern as gotobi     |
//| v1/yen_fiscal_repatriation v1, not the portfolio-harness variant). |
//|                                                                     |
//| Asian range and session windows are UTC times given by the spec,   |
//| pre-converted to this broker's server clock by hand (hardcoded per |
//| calendar month) rather than derived from TimeGMT() -- TimeGMT() is |
//| not simulated inside the Strategy Tester (reflects the real host   |
//| clock, not simulated time). Same DST-table convention as gotobi.   |
//|                                                                     |
//| Asian range window : 00:00-06:00 UTC = 02:00-08:00 server (Nov-Feb) |
//|                                       = 03:00-09:00 server (Mar-Oct)|
//| Session window      : 07:00-11:00 UTC = 09:00-13:00 server (Nov-Feb)|
//|                                       = 10:00-14:00 server (Mar-Oct)|
//| EOD flat            : 18:00 server, single fixed hour (not          |
//|                       seasonally adjusted -- sits well after the    |
//|                       trading window regardless of season, same     |
//|                       simplification london_range_fade uses).       |
//+------------------------------------------------------------------+
#property copyright "london_breakout_retest"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Asian range window (broker/server clock, DST table) -----------------
input int    InpAsianStartHourSummer   = 3;  // Mar-Oct server hour for 00:00 UTC
input int    InpAsianStartHourWinter   = 2;  // Nov-Feb server hour for 00:00 UTC
input int    InpAsianEndHourSummer     = 9;  // Mar-Oct server hour for 06:00 UTC
input int    InpAsianEndHourWinter     = 8;  // Nov-Feb server hour for 06:00 UTC

// -- Session (breakout/retest) window (broker/server clock, DST table) ---
input int    InpSessionStartHourSummer = 10; // Mar-Oct server hour for 07:00 UTC
input int    InpSessionStartHourWinter = 9;  // Nov-Feb server hour for 07:00 UTC
input int    InpSessionEndHourSummer   = 14; // Mar-Oct server hour for 11:00 UTC
input int    InpSessionEndHourWinter   = 13; // Nov-Feb server hour for 11:00 UTC

// -- EOD flat --------------------------------------------------------------
input int    InpEodFlatHour            = 18; // server hour, single fixed hour, no DST split

// -- Rejection candle thresholds (Researcher's numeric formalization) ----
input double InpPinBarWickRatio        = 2.0;  // opposite-direction wick >= this * body
input double InpPinBarMaxBodyPct       = 35.0; // body <= this % of the candle's total range

// -- Trade parameters ------------------------------------------------------
input double InpSLBufferPips           = 3.0;  // buffer beyond the rejection candle's wick extreme
input double InpTPMultiplier           = 2.0;  // TP = this * SL distance (R-multiple)
input double InpRiskPercent            = 0.5;  // % of account balance risked per trade
input double InpMaxSpreadPips          = 3.0;  // skip entry if spread is wider than this
input int    MagicNumber               = 20260050;

// -- Safety rules (always on) -----------------------------------------------
input int    InpMaxConsecutiveLosses   = 6;    // pause after this many losses in a row
input double InpDailyLossStopPercent   = 5.0;  // no more trades today after losing this % of balance today
input double InpMaxDrawdownStopPercent = 15.0; // hard stop after this % drawdown from the balance peak
input bool   InpResetLedgerNow         = false;// manually clear the consecutive-loss pause
input bool   InpResetDrawdownStop      = false;// manually clear the drawdown hard-stop

// -- Live safety -------------------------------------------------------------
input bool   InpAllowLiveAccount       = false;// must be explicitly set true to run on a REAL account

double pipSize;

int      currentDay = -1;              // year*1000 + day_of_year, drives daily state resets

// -- Daily session windows (computed each day in ResetDayState) --------------
datetime asianWindowStart = 0, asianWindowEnd = 0;
datetime sessionWindowStart = 0, sessionWindowEnd = 0;
datetime eodFlatTime = 0;

// -- Asian range state ---------------------------------------------------------
bool     asianRangeReady = false;
double   asianHigh = -DBL_MAX, asianLow = DBL_MAX;

// -- Breakout/retest/rejection state machine (per day) --------------------------
bool     breakoutSet   = false;
int      breakoutDir   = 0;      // +1 bullish, -1 bearish
double   breakoutLevel = 0;
bool     dayResolved   = false;  // true once the day's setup is decided either way (traded, invalidated, filtered out, or skipped)
bool     tradedToday   = false;
datetime lastProcessedBarTime = 0;

// -- Safety ledger --------------------------------------------------------------
int      consecutiveLosses  = 0;
bool     monthlyHaltActive  = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;

double   balancePeak       = 0;
bool     drawdownHaltActive = false;

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
   return lots; // deliberately NOT floored up to the broker minimum -- see EnterTrade()
}

void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);
   bool summer = IsSummerBroker(s.mon);

   int asianStartHour = summer ? InpAsianStartHourSummer : InpAsianStartHourWinter;
   int asianEndHour   = summer ? InpAsianEndHourSummer   : InpAsianEndHourWinter;
   int sessStartHour  = summer ? InpSessionStartHourSummer : InpSessionStartHourWinter;
   int sessEndHour    = summer ? InpSessionEndHourSummer   : InpSessionEndHourWinter;

   MqlDateTime t = s;
   t.min = 0; t.sec = 0;

   t.hour = asianStartHour;   asianWindowStart   = StructToTime(t);
   t.hour = asianEndHour;     asianWindowEnd     = StructToTime(t);
   t.hour = sessStartHour;    sessionWindowStart = StructToTime(t);
   t.hour = sessEndHour;      sessionWindowEnd   = StructToTime(t);
   t.hour = InpEodFlatHour;   eodFlatTime        = StructToTime(t);

   asianRangeReady = false;
   asianHigh = -DBL_MAX;
   asianLow  = DBL_MAX;

   breakoutSet   = false;
   breakoutDir   = 0;
   breakoutLevel = 0;
   dayResolved   = false;
   tradedToday   = false;
   lastProcessedBarTime = 0;

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;
}

void CheckMonthlyHaltResume(const MqlDateTime &s)
{
   if(!monthlyHaltActive)
      return;
   if(s.year > haltSetYear || (s.year == haltSetYear && s.mon > haltSetMonth))
   {
      monthlyHaltActive = false;
      consecutiveLosses = 0;
      Print("london_breakout_retest ", _Symbol, ": new month -- consecutive-loss pause lifted.");
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
         Alert("london_breakout_retest ", _Symbol, ": drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
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
      Print("london_breakout_retest ", _Symbol, ": closing stale position left open from a previous day at EA startup.");
      trade.PositionClose(_Symbol);
   }
}

void ManageOpenPosition(datetime now)
{
   if(!PositionSelect(_Symbol))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return;
   if(now >= eodFlatTime)
      trade.PositionClose(_Symbol);
}

// Finalize the Asian range once the window has closed, by scanning completed
// M15 bars backward from the most recently closed one. Self-contained (does
// not rely on catching every tick during the window), so it also works
// correctly if the EA is (re)started mid-day after the window already closed.
void FinalizeAsianRange()
{
   asianHigh = -DBL_MAX;
   asianLow  = DBL_MAX;
   int shift = 1; // most recently completed bar; shift 0 may still be forming
   for(int i = 0; i < 200; i++)
   {
      datetime bt = iTime(_Symbol, PERIOD_M15, shift);
      if(bt == 0)
         break;
      if(bt < asianWindowStart)
         break;
      if(bt < asianWindowEnd)
      {
         double h = iHigh(_Symbol, PERIOD_M15, shift);
         double l = iLow(_Symbol, PERIOD_M15, shift);
         if(h > asianHigh) asianHigh = h;
         if(l < asianLow)  asianLow  = l;
      }
      shift++;
   }
}

// Pin bar / engulfing rejection candle in the breakout direction, per
// spec.json's numeric thresholds. (o,h,l,c) is the candle being tested,
// (po,pc) is the prior candle's open/close (needed for engulfing).
bool IsRejectionCandle(int dir, double o, double h, double l, double c, double po, double pc)
{
   double range = h - l;
   if(range <= 0)
      return false;
   double body = MathAbs(c - o);
   double lowerWick = MathMin(o, c) - l;
   double upperWick = h - MathMax(o, c);
   double priorBodyLow  = MathMin(po, pc);
   double priorBodyHigh = MathMax(po, pc);

   bool pinBar  = false;
   bool engulf  = false;

   if(dir == +1)
   {
      if(c > o) // closes in the breakout direction (bullish)
      {
         if(lowerWick >= InpPinBarWickRatio * body && body <= (InpPinBarMaxBodyPct / 100.0) * range)
            pinBar = true;
         if(o <= priorBodyLow && c >= priorBodyHigh)
            engulf = true;
      }
   }
   else if(dir == -1)
   {
      if(c < o) // closes in the breakout direction (bearish)
      {
         if(upperWick >= InpPinBarWickRatio * body && body <= (InpPinBarMaxBodyPct / 100.0) * range)
            pinBar = true;
         if(o >= priorBodyHigh && c <= priorBodyLow)
            engulf = true;
      }
   }
   return (pinBar || engulf);
}

void EnterTrade(int dir, double rejLow, double rejHigh)
{
   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
   if(spreadPips > InpMaxSpreadPips)
   {
      Print("london_breakout_retest ", _Symbol, ": skip, spread ", DoubleToString(spreadPips, 1), " pips");
      return;
   }

   double price = (dir == +1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (dir == +1) ? (rejLow - InpSLBufferPips * pipSize) : (rejHigh + InpSLBufferPips * pipSize);
   double slDistance = MathAbs(price - sl);
   if(slDistance <= 0)
      return;
   double tp = (dir == +1) ? (price + InpTPMultiplier * slDistance) : (price - InpTPMultiplier * slDistance);

   double lots = CalculateLotSize(slDistance);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lots < minLot)
   {
      Print("london_breakout_retest ", _Symbol, ": skip, computed lot ", DoubleToString(lots, 2),
            " below broker minimum ", DoubleToString(minLot, 2));
      return;
   }

   ENUM_ORDER_TYPE otype = (dir == +1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double marginRequired;
   if(!OrderCalcMargin(otype, _Symbol, lots, price, marginRequired))
      return;
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      Print("london_breakout_retest ", _Symbol, ": skip, insufficient free margin");
      return;
   }

   bool ok = (dir == +1) ? trade.Buy(lots, _Symbol, price, sl, tp) : trade.Sell(lots, _Symbol, price, sl, tp);
   if(ok)
      tradedToday = true;
}

// Evaluate the just-completed M15 bar at the given shift (1 = most recently
// closed bar) against the breakout / retest / rejection / invalidation state
// machine. Called at most once per completed bar (gated by lastProcessedBarTime
// in OnTick).
void ProcessClosedM15Bar(int shift)
{
   if(PositionSelect(_Symbol)) // never add to an open position / max one per pair per day
      return;

   double o = iOpen(_Symbol, PERIOD_M15, shift);
   double h = iHigh(_Symbol, PERIOD_M15, shift);
   double l = iLow(_Symbol, PERIOD_M15, shift);
   double c = iClose(_Symbol, PERIOD_M15, shift);

   if(!breakoutSet)
   {
      // Step 1: impulse -- completed bar closes fully outside the Asian range.
      // This bar itself is never traded.
      if(c > asianHigh)
      {
         breakoutSet   = true;
         breakoutDir   = +1;
         breakoutLevel = asianHigh;
         Print("london_breakout_retest ", _Symbol, ": bullish impulse breakout, level=", DoubleToString(breakoutLevel, _Digits));
      }
      else if(c < asianLow)
      {
         breakoutSet   = true;
         breakoutDir   = -1;
         breakoutLevel = asianLow;
         Print("london_breakout_retest ", _Symbol, ": bearish impulse breakout, level=", DoubleToString(breakoutLevel, _Digits));
      }
      return;
   }

   // Step 2: invalidation -- a completed bar closes back across the OPPOSITE
   // Asian boundary before a valid retest+rejection has entered.
   if(breakoutDir == +1 && c < asianLow)
   {
      dayResolved = true;
      Print("london_breakout_retest ", _Symbol, ": setup invalidated (closed back below Asian low).");
      return;
   }
   if(breakoutDir == -1 && c > asianHigh)
   {
      dayResolved = true;
      Print("london_breakout_retest ", _Symbol, ": setup invalidated (closed back above Asian high).");
      return;
   }

   // Step 3: retest -- intrabar wick touch of the broken boundary is sufficient here.
   bool touched = (breakoutDir == +1) ? (l <= breakoutLevel) : (h >= breakoutLevel);
   if(!touched)
      return; // keep waiting for a later bar to touch the level

   // Step 4: rejection trigger. If this touching bar doesn't qualify, we simply
   // keep waiting -- a later bar that also touches the level will be evaluated
   // the same way when it closes. (Judgment call: the spec's "a later bar still
   // touching it" is read as "the next bar that touches", not "every bar in
   // between must touch" -- see handoff notes.)
   double po = iOpen(_Symbol, PERIOD_M15, shift + 1);
   double pc = iClose(_Symbol, PERIOD_M15, shift + 1);
   if(!IsRejectionCandle(breakoutDir, o, h, l, c, po, pc))
      return;

   // H1 directional context filter, evaluated as of this M15 rejection trigger.
   double h1Open  = iOpen(_Symbol, PERIOD_H1, 1);
   double h1Close = iClose(_Symbol, PERIOD_H1, 1);
   bool h1Ok = (breakoutDir == +1) ? (h1Close > h1Open) : (h1Close < h1Open);
   if(!h1Ok)
   {
      dayResolved = true;
      Print("london_breakout_retest ", _Symbol, ": rejection candle confirmed but H1 filter disagrees -- no trade today.");
      return;
   }

   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
   {
      dayResolved = true;
      Print("london_breakout_retest ", _Symbol, ": valid setup but safety halt active -- no trade today.");
      return;
   }

   // Entry: market order on the tick following the rejection candle's close
   // (the earliest the EA can act on a bar-close-triggered signal -- consistent
   // with london_range_fade's bar-close entry convention).
   EnterTrade(breakoutDir, l, h);
   dayResolved = true;
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("london_breakout_retest ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("london_breakout_retest ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
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

   return INIT_SUCCEEDED;
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
         Print("london_breakout_retest ", _Symbol, ": ", InpMaxConsecutiveLosses,
               " consecutive losses -- pausing until the first day of next month.");
      }
   }
   else
   {
      consecutiveLosses = 0;
   }
}

void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime s;
   TimeToStruct(now, s);
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

   ManageOpenPosition(now); // EOD flat exit

   // Finalize the Asian range exactly once, as soon as its window has closed
   // (also handles EA (re)start mid-day, after the window already closed).
   if(!asianRangeReady && now >= asianWindowEnd)
   {
      FinalizeAsianRange();
      asianRangeReady = true;
      Print("london_breakout_retest ", _Symbol, ": Asian range finalized, high=",
            DoubleToString(asianHigh, _Digits), " low=", DoubleToString(asianLow, _Digits));
   }

   // Only look for the impulse breakout, retest, and rejection trigger within
   // the session window; process each newly completed M15 bar exactly once.
   if(asianRangeReady && !dayResolved && now >= sessionWindowStart && now <= sessionWindowEnd)
   {
      datetime closedBarTime = iTime(_Symbol, PERIOD_M15, 1);
      if(closedBarTime > 0 && closedBarTime != lastProcessedBarTime && closedBarTime >= sessionWindowStart)
      {
         lastProcessedBarTime = closedBarTime;
         ProcessClosedM15Bar(1);
      }
   }
}
