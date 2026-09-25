//+------------------------------------------------------------------+
//| london_range_fade v1 - fade the pre-London range break, day       |
//| trading only.                                                      |
//|                                                                    |
//| Motivated by london_orb (see _graveyard): three different filters  |
//| on "breakout predicts continuation" all landed at ~32% win rate,   |
//| every version losing money specifically by trading WITH the        |
//| breakout direction. This strategy tests the opposite thesis: a     |
//| break beyond the pre-London range (06:00-08:00 server time) is a   |
//| fade opportunity, betting on reversion back toward the range       |
//| rather than continuation. Reuses london_orb's bar-close            |
//| confirmation + minimum range-size filter, since those reduced      |
//| noise without hurting win rate there.                              |
//|                                                                    |
//| Sell when a bar closes above rangeHigh+buffer (fade back down).    |
//| Buy when a bar closes below rangeLow-buffer (fade back up).        |
//| Stop sits beyond the breakout extreme (room for it to extend       |
//| before invalidating); target is back across the range.             |
//+------------------------------------------------------------------+
#property copyright "london_range_fade"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

input int    RangeStartHour     = 6;    // range window start, server time
input int    RangeEndHour       = 8;    // range window end / fade window opens
input int    EndOfDayHour       = 20;   // force-flat time, server time
input double BreakoutBufferPips = 3;    // buffer beyond range extreme to confirm the break
input double MinRangeSizePips   = 15;   // skip the day if the range is narrower than this
input double SLMultiplier       = 1.0;  // stop distance beyond the breakout = range size * this
input double TPMultiplier       = 1.0;  // target distance back across the range = range size * this
input double RiskPercent        = 1.0;  // % of equity risked per trade
input int    MagicNumber        = 20260010;

double rangeHigh, rangeLow;
bool   rangeFinalized;
bool   rangeValid;
bool   tradeTakenToday;
int    currentDayOfYear = -1;
datetime lastBarTime = 0;
double pipSize;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   ResetDayState();
   return(INIT_SUCCEEDED);
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
         rangeValid = (rangeHigh - rangeLow) >= MinRangeSizePips * pipSize;
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
