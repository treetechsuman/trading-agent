//+------------------------------------------------------------------+
//| wm_fix_reversal v1 - fade the WM/Reuters 4pm London FX fix spike, |
//| day trading only.                                                  |
//|                                                                     |
//| Thesis: the WM/Reuters 4pm London fix is the benchmark rate index  |
//| funds, custodians, and pension funds use to execute large currency |
//| rebalancing trades. The concentrated execution creates a           |
//| documented volatility spike in the minutes bracketing 16:00:00     |
//| London time, which commonly overshoots and partially reverts once  |
//| the concentrated flow clears. Unlike gotobi's fixed-direction      |
//| event, the fix's direction varies day to day with that month's     |
//| rebalancing flow, so this strategy measures the spike and fades    |
//| whichever way it went, rather than always selling.                |
//|                                                                     |
//| Broker-clock note: 16:00:00 London time = 18:00:00 this broker's   |
//| server time, CONSTANTLY year-round (EET/EEST currently shifts DST  |
//| on the same calendar dates as UK/EU clocks, so the 2h gap to       |
//| London never changes) -- see dates.md for the reasoning. This is   |
//| simpler than gotobi's month-branched conversion, which was needed  |
//| there because Tokyo doesn't observe DST at all.                    |
//+------------------------------------------------------------------+
#property copyright "wm_fix_reversal"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Fix window timing (broker/server clock) -----------------------------
input int    FixHourServer     = 18;   // 16:00 London == 18:00 server, year-round
input int    FixMinuteServer   = 0;
input int    PreFixMinutes     = 5;    // start measuring the spike this many minutes before the fix
input int    PostFixMinutes    = 2;    // keep measuring this many minutes after the fix before entering
input int    HoldMinutes       = 30;   // force-close this many minutes after entry if SL/TP not hit

// -- Trade parameters ------------------------------------------------------
input double MinSpikeSizePips  = 12.0; // skip the day if the fix-window move is smaller than this (locked 2026-09-22 after in-sample sweep: 6-10 pips showed almost no edge, PF ~1.04-1.10; 12 pips is the best-defensible balance of edge strength vs. sample size -- see sweep/sweep_results.csv)
input double SLMultiplier      = 1.0;  // stop = spike size * this, beyond entry in the spike's own direction
input double TPMultiplier      = 1.0;  // target = spike size * this, back toward the pre-fix level
input double RiskPercent       = 1.0;  // % of account equity risked per trade
input double MaxSpreadPips     = 3.0;
input int    EndOfDayHour       = 22;  // force-flat time, server time -- day trading only, never hold overnight
input int    MagicNumber       = 20260040;

double pipSize;

int      currentDay = -1;
datetime windowStart = 0;
datetime windowEnd   = 0;
datetime scheduledExitTime = 0;
double   priceAtWindowStart = 0;
bool     haveWindowStartPrice = false;
bool     windowEvaluated = false;
bool     tradeTakenToday = false;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
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

void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);

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
      return 0.0; // skip rather than force up to the minimum -- see project convention
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

   // EOD flat -- day trading only, never hold overnight
   if(HourOf(now) >= EndOfDayHour && PositionSelect(_Symbol))
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

   // Capture the price at the start of the measurement window
   if(!haveWindowStartPrice && now >= windowStart && now < windowEnd)
   {
      priceAtWindowStart = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      haveWindowStartPrice = true;
      return;
   }

   // At window close, measure the spike and fade it
   if(!windowEvaluated && haveWindowStartPrice && now >= windowEnd)
   {
      windowEvaluated = true;

      double priceNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double spike = priceNow - priceAtWindowStart;
      double spikePips = MathAbs(spike) / pipSize;

      if(spikePips < MinSpikeSizePips)
         return; // no real fix move today -- skip

      double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
      if(spreadPips > MaxSpreadPips)
         return;

      double slDistance = spikePips * pipSize * SLMultiplier;
      double tpDistance  = spikePips * pipSize * TPMultiplier;

      if(spike > 0)
      {
         // Price rose into the fix -- fade it: sell
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
         // Price fell into the fix -- fade it: buy
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
   }
}
