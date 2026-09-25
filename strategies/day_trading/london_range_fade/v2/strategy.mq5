//+------------------------------------------------------------------+
//| london_range_fade v2 - fade the pre-London range break, day       |
//| trading only.                                                      |
//|                                                                    |
//| v1's yearly breakdown (2018-2022, EURUSD.r) showed 2018 and 2020   |
//| losing while 2021-2022 carried the whole aggregate result. 2020's  |
//| losses cluster almost entirely in the COVID crash window (Feb28-   |
//| Apr7 2020) -- a volatility shock where the range gets blown        |
//| through rather than reverted, breaking the mean-reversion premise. |
//| 2018's losses look diffuse, not event-driven, so this filter is    |
//| expected to help 2020 more than 2018.                              |
//|                                                                    |
//| Adds: skip the day if the pre-London range is abnormally wide      |
//| relative to its own recent history, on top of v1's minimum         |
//| range-size floor and bar-close breakout confirmation.              |
//|                                                                     |
//| (First attempt compared the range to daily ATR(14) -- a 2-hour      |
//| session range is naturally a small fraction of a full day's ATR,   |
//| so that filter never fired at any sane multiplier. Fixed to        |
//| compare the range to a rolling average of its own recent history   |
//| instead, an apples-to-apples comparison.)                          |
//+------------------------------------------------------------------+
#property copyright "london_range_fade"
#property version   "2.00"

#include <Trade/Trade.mqh>
CTrade trade;

input int    RangeStartHour        = 6;    // range window start, server time
input int    RangeEndHour          = 8;    // range window end / fade window opens
input int    EndOfDayHour          = 20;   // force-flat time, server time
input double BreakoutBufferPips    = 10;   // buffer beyond range extreme to confirm the break
input double MinRangeSizePips      = 15;   // skip the day if the range is narrower than this
input double MaxRangeVsAvgMultiplier = 2.0; // skip the day if range > this x the recent average range
input int    RangeHistoryWindow    = 20;   // how many past days' ranges to average over
input double SLMultiplier          = 1.0;  // stop distance beyond the breakout = range size * this
input double TPMultiplier          = 1.0;  // target distance back across the range = range size * this
input double RiskPercent           = 1.0;  // % of equity risked per trade
input int    MagicNumber           = 20260011;

double rangeHigh, rangeLow;
bool   rangeFinalized;
bool   rangeValid;
bool   tradeTakenToday;
int    currentDayOfYear = -1;
datetime lastBarTime = 0;
double pipSize;

double rangeHistory[];
int    rangeHistoryCount = 0;
int    rangeHistoryNext = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   ArrayResize(rangeHistory, RangeHistoryWindow);
   ResetDayState();
   return(INIT_SUCCEEDED);
}

double AverageRangeHistory()
{
   double sum = 0;
   for(int i = 0; i < rangeHistoryCount; i++)
      sum += rangeHistory[i];
   return sum / rangeHistoryCount;
}

void PushRangeHistory(double value)
{
   rangeHistory[rangeHistoryNext] = value;
   rangeHistoryNext = (rangeHistoryNext + 1) % RangeHistoryWindow;
   if(rangeHistoryCount < RangeHistoryWindow)
      rangeHistoryCount++;
}

void ResetDayState()
{
   rangeHigh = -DBL_MAX;
   rangeLow  = DBL_MAX;
   rangeFinalized = false;
   rangeValid = false;
   tradeTakenToday = false;
}

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
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
}

void OnTick()
{
   datetime now = TimeCurrent();
   int dayId = DayOfYearOf(now);
   if(dayId != currentDayOfYear)
   {
      currentDayOfYear = dayId;
      ResetDayState();
   }

   int hour = HourOf(now);

   // EOD flat -- day trading only, never hold overnight
   if(hour >= EndOfDayHour && PositionsTotal() > 0)
   {
      if(PositionSelect(_Symbol))
         trade.PositionClose(_Symbol);
      return;
   }

   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool newBar = (barTime != lastBarTime);
   if(newBar)
      lastBarTime = barTime;

   if(newBar && !rangeFinalized)
   {
      int prevHour = HourOf(iTime(_Symbol, PERIOD_CURRENT, 1));
      if(prevHour >= RangeStartHour && prevHour < RangeEndHour)
      {
         rangeHigh = MathMax(rangeHigh, iHigh(_Symbol, PERIOD_CURRENT, 1));
         rangeLow  = MathMin(rangeLow, iLow(_Symbol, PERIOD_CURRENT, 1));
      }
      if(hour >= RangeEndHour && rangeHigh > -DBL_MAX && rangeLow < DBL_MAX)
      {
         rangeFinalized = true;
         double rangeSize = rangeHigh - rangeLow;

         bool notTooNarrow = rangeSize >= MinRangeSizePips * pipSize;
         bool notTooWide = (rangeHistoryCount < 5) ||
                            (rangeSize <= MaxRangeVsAvgMultiplier * AverageRangeHistory());
         rangeValid = notTooNarrow && notTooWide;

         // Feed the rolling average regardless of pass/fail, so the "normal"
         // baseline isn't itself distorted by excluding the events it exists
         // to detect.
         PushRangeHistory(rangeSize);
      }
   }

   if(!rangeFinalized || !rangeValid || tradeTakenToday || PositionsTotal() > 0 || hour >= EndOfDayHour)
      return;

   // Only evaluate the break once per completed bar (close-confirmed, not a tick touch)
   if(!newBar)
      return;

   double buffer = BreakoutBufferPips * pipSize;
   double rangeSize = rangeHigh - rangeLow;
   double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);

   if(lastClose > rangeHigh + buffer)
   {
      // Fade: sell, betting on reversion back down into the range
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = bid + SLMultiplier * rangeSize;
      double tp = bid - TPMultiplier * rangeSize;
      double lots = CalculateLotSize(sl - bid);
      if(lots > 0)
      {
         trade.Sell(lots, _Symbol, bid, sl, tp);
         tradeTakenToday = true;
      }
   }
   else if(lastClose < rangeLow - buffer)
   {
      // Fade: buy, betting on reversion back up into the range
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - SLMultiplier * rangeSize;
      double tp = ask + TPMultiplier * rangeSize;
      double lots = CalculateLotSize(ask - sl);
      if(lots > 0)
      {
         trade.Buy(lots, _Symbol, ask, sl, tp);
         tradeTakenToday = true;
      }
   }
}
