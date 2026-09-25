//+------------------------------------------------------------------+
//| month_end_fix_reversal v1 - fade the WM/Reuters 4pm London FX fix  |
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
//| on that month's realized equity performance, with flow              |
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
//+------------------------------------------------------------------+
#property copyright "month_end_fix_reversal"
#property version   "1.00"

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

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   ArrayResize(spikeHistory, SpikeHistoryWindow);
   ResetDayState(TimeCurrent());
   return(INIT_SUCCEEDED);
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

void OnTick()
{
   datetime now = TimeCurrent();
   int dayId = DayOfYearOf(now);
   if(dayId != currentDay)
   {
      currentDay = dayId;
      ResetDayState(now);
   }

   if(HourOf(now) >= EndOfDayHour && PositionSelect(_Symbol))
   {
      trade.PositionClose(_Symbol);
      return;
   }

   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      if(now >= scheduledExitTime)
         trade.PositionClose(_Symbol);
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
         return;

      double threshold;
      if(spikeHistoryCount < MinHistoryToAdapt)
         threshold = MinSpikeSizePipsFloor;
      else
         threshold = MathMax(MinSpikeSizePipsFloor, MinSpikeVsAvgMultiplier * AverageSpikeHistory());

      if(spikePips < threshold)
         return;

      double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
      if(spreadPips > MaxSpreadPips)
         return;

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
         }
      }
      return;
   }

   if(tradeTakenToday)
      return;

   if(!haveWindowStartPrice && now >= windowStart && now < windowEnd)
   {
      priceAtWindowStart = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      haveWindowStartPrice = true;
   }
}
