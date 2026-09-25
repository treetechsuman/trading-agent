//+------------------------------------------------------------------+
//| london_orb v3 - London opening-range breakout, day trading only  |
//|                                                                    |
//| v1 and v2 both landed at ~32% win rate / ~0.80 profit factor       |
//| trading breakouts in whichever direction they occurred, which is   |
//| the signature of a signal with no real directional edge. Last      |
//| structural attempt before retiring the concept: only take a        |
//| breakout when it agrees with the higher-timeframe trend (H4,       |
//| price vs a 50-period MA) -- the hypothesis being that counter-     |
//| trend breakouts are the ones failing and dragging the average      |
//| down. Keeps v2's bar-close confirmation + min range-size filter.   |
//+------------------------------------------------------------------+
#property copyright "london_orb"
#property version   "3.00"

#include <Trade/Trade.mqh>
CTrade trade;

input int    RangeStartHour     = 6;    // range window start, server time
input int    RangeEndHour       = 8;    // range window end / breakout window opens
input int    EndOfDayHour       = 20;   // force-flat time, server time
input double BreakoutBufferPips = 3;    // buffer beyond range extreme to confirm breakout
input double MinRangeSizePips   = 15;   // skip the day if the range is narrower than this
input double SLMultiplier       = 1.0;  // stop distance = range size * this
input double TPMultiplier       = 2.0;  // target distance = range size * this
input double RiskPercent        = 1.0;  // % of equity risked per trade
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H4;  // higher timeframe used for the trend filter
input int    TrendMAPeriod      = 50;   // MA period on TrendTimeframe
input int    MagicNumber        = 20260003;

double rangeHigh, rangeLow;
bool   rangeFinalized;
bool   rangeValid;
bool   tradeTakenToday;
int    currentDayOfYear = -1;
datetime lastBarTime = 0;
double pipSize;
int    trendMAHandle;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   trendMAHandle = iMA(_Symbol, TrendTimeframe, TrendMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(trendMAHandle == INVALID_HANDLE)
      return(INIT_FAILED);
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

// +1 uptrend, -1 downtrend, 0 undetermined (not enough history yet)
int TrendDirection()
{
   double ma[1];
   if(CopyBuffer(trendMAHandle, 0, 1, 1, ma) != 1)
      return 0;
   double price = iClose(_Symbol, TrendTimeframe, 1);
   if(price > ma[0]) return 1;
   if(price < ma[0]) return -1;
   return 0;
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

   // Only evaluate the breakout once per completed bar (close-confirmed, not a tick touch)
   if(!newBar)
      return;

   int trend = TrendDirection();
   if(trend == 0)
      return;

   double buffer = BreakoutBufferPips * pipSize;
   double rangeSize = rangeHigh - rangeLow;
   double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);

   if(trend > 0 && lastClose > rangeHigh + buffer)
   {
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
   else if(trend < 0 && lastClose < rangeLow - buffer)
   {
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
}
