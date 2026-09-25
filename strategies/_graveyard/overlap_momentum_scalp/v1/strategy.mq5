//+------------------------------------------------------------------+
//| overlap_momentum_scalp v1 - scalp momentum continuation during     |
//| the London/New York overlap, scalping only.                        |
//|                                                                      |
//| Thesis: 13:00-16:00 London time (15:00-18:00 this broker's server   |
//| time, a flat +2h offset that holds year-round -- see gotobi's/      |
//| wm_fix_reversal's dates.md for why) is the highest-liquidity window |
//| in FX, when both major sessions are simultaneously active. Fast,    |
//| high-conviction M1 momentum bursts in this window reflect          |
//| concentrated institutional order flow and tend to see brief         |
//| continuation over the following few minutes before fading -- a      |
//| documented short-horizon order-flow-persistence effect -- distinct  |
//| from london_orb's failed thesis (a multi-hour SESSION RANGE         |
//| predicting the day's direction, which didn't hold up). This trades  |
//| single-BAR bursts on a much shorter continuation horizon instead.   |
//|                                                                      |
//| "Burst" is defined adaptively: a completed M1 bar's body size       |
//| relative to a rolling average of recent session bars' own body      |
//| sizes (same technique already proven in london_range_fade v2 and    |
//| wm_fix_reversal v2 -- apples-to-apples, not a fixed pip count),      |
//| plus a body/range ratio filter so a big wick doesn't count as       |
//| conviction.                                                         |
//|                                                                      |
//| Scalping-specific care: very tight spread filter and a small        |
//| absolute stop floor, since round-turn costs matter proportionally   |
//| far more at this size of target than in this project's other,       |
//| slower strategies.                                                  |
//+------------------------------------------------------------------+
#property copyright "overlap_momentum_scalp"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Session window (broker/server clock) ---------------------------------
input int    SessionStartHour     = 15;   // 13:00 London == 15:00 server, year-round
input int    SessionEndHour       = 18;   // 16:00 London == 18:00 server

// -- Burst detection (volatility-adaptive) ---------------------------------
input double BurstVsAvgMultiplier = 2.0;  // burst bar's body must be >= this x the rolling average body size
input double MinBurstPipsFloor    = 3.0;  // absolute floor regardless of how quiet the recent average is
input double MinBodyToRangeRatio  = 0.6;  // body must be at least this fraction of the bar's total range
input int    BurstHistoryWindow   = 30;   // how many past session M1 bars' body sizes to average over
input int    MinHistoryToAdapt    = 10;   // fall back to the floor alone until this many session bars seen

// -- Trade parameters -------------------------------------------------------
input double SLMultiplier      = 1.0;  // stop = burst size (pips) * this
input double TPMultiplier      = 1.0;  // target = burst size (pips) * this
input double MinStopPips       = 4.0;  // stop floor so it isn't unrealistically tight
input int    MaxHoldMinutes    = 10;   // force-close if neither SL/TP hit -- scalps resolve fast or not at all
input int    MaxTradesPerDay   = 5;
input double RiskPercent       = 0.3;  // % of equity risked per trade -- small, trades often
input double MaxSpreadPips     = 1.5;  // tight -- critical at scalping target sizes
input int    MagicNumber       = 20260050;

// -- Safety rules (always on, same pattern as gotobi) ----------------------
input int    InpMaxConsecutiveLosses   = 8;   // higher than gotobi's 6 -- far more trades/day here
input double InpDailyLossStopPercent   = 5.0;
input double InpMaxDrawdownStopPercent = 15.0;
input bool   InpResetLedgerNow         = false;
input bool   InpResetDrawdownStop      = false;
input bool   InpAllowLiveAccount       = false;

double pipSize;

int      currentDay = -1;
datetime lastBarTime = 0;
int      tradesToday = 0;

double   bodyHistory[];
int      bodyHistoryCount = 0;
int      bodyHistoryNext  = 0;

int      consecutiveLosses = 0;
bool     monthlyHaltActive = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;
double   balancePeak       = 0;
bool     drawdownHaltActive = false;

datetime scheduledExitTime = 0;

int HourOf(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour;
}

int DayOfYearOf(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day_of_year + s.year * 1000;
}

double AverageBodyHistory()
{
   double sum = 0;
   for(int i = 0; i < bodyHistoryCount; i++)
      sum += bodyHistory[i];
   return sum / bodyHistoryCount;
}

void PushBodyHistory(double bodyPips)
{
   bodyHistory[bodyHistoryNext] = bodyPips;
   bodyHistoryNext = (bodyHistoryNext + 1) % BurstHistoryWindow;
   if(bodyHistoryCount < BurstHistoryWindow)
      bodyHistoryCount++;
}

void ResetDayState(datetime now)
{
   tradesToday = 0;
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;
}

void CheckMonthlyHaltResume(datetime now)
{
   if(!monthlyHaltActive)
      return;
   MqlDateTime s;
   TimeToStruct(now, s);
   if(s.year > haltSetYear || (s.year == haltSetYear && s.mon > haltSetMonth))
   {
      monthlyHaltActive = false;
      consecutiveLosses = 0;
      Print("overlap_momentum_scalp: new month -- consecutive-loss pause lifted.");
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
         Alert("overlap_momentum_scalp: drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
               "% from peak balance) -- halted until manually reset (InpResetDrawdownStop).");
      drawdownHaltActive = true;
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

void ManageOpenPosition(datetime now)
{
   if(!PositionSelect(_Symbol))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return;

   bool sessionOver = (HourOf(now) >= SessionEndHour);
   if(sessionOver || now >= scheduledExitTime)
      trade.PositionClose(_Symbol);
}

void ProcessClosedBar(datetime now)
{
   double openPrice  = iOpen(_Symbol, PERIOD_M1, 1);
   double closePrice = iClose(_Symbol, PERIOD_M1, 1);
   double highPrice  = iHigh(_Symbol, PERIOD_M1, 1);
   double lowPrice   = iLow(_Symbol, PERIOD_M1, 1);

   double body = closePrice - openPrice;
   double bodyPips = MathAbs(body) / pipSize;
   double range = highPrice - lowPrice;

   // Feed the rolling average regardless of pass/fail, so the baseline
   // isn't distorted by excluding the events it exists to detect (same
   // principle as london_range_fade v2's / wm_fix_reversal v2's filters).
   PushBodyHistory(bodyPips);

   if(PositionSelect(_Symbol))
      return; // already in a trade -- don't stack
   if(tradesToday >= MaxTradesPerDay)
      return;
   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
      return;

   double threshold;
   if(bodyHistoryCount < MinHistoryToAdapt)
      threshold = MinBurstPipsFloor;
   else
      threshold = MathMax(MinBurstPipsFloor, BurstVsAvgMultiplier * AverageBodyHistory());

   if(bodyPips < threshold)
      return; // not a burst

   if(range <= 0 || (MathAbs(body) / range) < MinBodyToRangeRatio)
      return; // mostly wick, not real directional conviction

   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
   if(spreadPips > MaxSpreadPips)
      return;

   double slDistancePips = MathMax(MinStopPips, bodyPips * SLMultiplier);
   double tpDistancePips = bodyPips * TPMultiplier;
   double slDistance = slDistancePips * pipSize;
   double tpDistance = tpDistancePips * pipSize;

   bool success = false;
   if(body > 0)
   {
      // Bullish burst -- bet on continuation: buy
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - slDistance;
      double tp = ask + tpDistance;
      double lots = CalculateLotSize(ask - sl);
      if(lots > 0)
         success = trade.Buy(lots, _Symbol, ask, sl, tp);
   }
   else
   {
      // Bearish burst -- bet on continuation: sell
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = bid + slDistance;
      double tp = bid - tpDistance;
      double lots = CalculateLotSize(sl - bid);
      if(lots > 0)
         success = trade.Sell(lots, _Symbol, bid, sl, tp);
   }

   if(success)
   {
      tradesToday++;
      scheduledExitTime = now + MaxHoldMinutes * 60;
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   ArrayResize(bodyHistory, BurstHistoryWindow);

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("overlap_momentum_scalp: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("overlap_momentum_scalp: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }

   consecutiveLosses = 0;
   monthlyHaltActive = false;
   drawdownHaltActive = false;
   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);

   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   currentDay = s.year * 1000 + s.day_of_year;
   ResetDayState(TimeCurrent());

   return(INIT_SUCCEEDED);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
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
         Print("overlap_momentum_scalp: ", InpMaxConsecutiveLosses,
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
   int dayId = DayOfYearOf(now);
   if(dayId != currentDay)
   {
      currentDay = dayId;
      ResetDayState(now);
      CheckMonthlyHaltResume(now);
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

   int hour = HourOf(now);
   if(hour < SessionStartHour || hour >= SessionEndHour)
      return;

   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime != lastBarTime)
   {
      lastBarTime = barTime;
      ProcessClosedBar(now);
   }
}
