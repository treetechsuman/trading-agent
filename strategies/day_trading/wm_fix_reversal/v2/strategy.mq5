//+------------------------------------------------------------------+
//| wm_fix_reversal v2 - fade the WM/Reuters 4pm London FX fix spike, |
//| now with a VOLATILITY-ADAPTIVE threshold instead of v1's fixed    |
//| pip count, day trading only.                                       |
//|                                                                     |
//| v1's yearly breakdown showed a fixed MinSpikeSizePips threshold     |
//| (12 pips) worked well in the unusually volatile 2020-2022 window    |
//| but its out-of-sample trade frequency collapsed ~85-90% in the      |
//| calmer 2023-2025 window (EURUSD had zero qualifying trades in all   |
//| of 2023) -- the strategy simply went dormant rather than failing,   |
//| because a fixed absolute pip bar doesn't adapt to a lower ambient   |
//| volatility regime.                                                  |
//|                                                                     |
//| v2 fixes this the same way london_range_fade v2 fixed its own       |
//| volatility-filter problem: compare each day's fix-window spike to  |
//| a ROLLING AVERAGE OF ITS OWN RECENT HISTORY (the last               |
//| SpikeHistoryWindow trading days' fix-window moves), an apples-to-   |
//| apples comparison, rather than to a fixed absolute number. (A first |
//| attempt at fixing london_range_fade's filter compared a session      |
//| range to daily ATR -- mismatched timeframes, never fired at any     |
//| sane multiplier. Learned from that mistake here: comparing this     |
//| 7-minute window's move to ITS OWN rolling history, not to an        |
//| unrelated indicator, is what actually worked there.)                |
//|                                                                     |
//| A small absolute floor (MinSpikeSizePipsFloor) still applies so an  |
//| extremely quiet regime doesn't degrade into trading noise-sized     |
//| moves that can't clear round-turn transaction costs.                |
//+------------------------------------------------------------------+
#property copyright "wm_fix_reversal"
#property version   "2.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Fix window timing (broker/server clock) -----------------------------
input int    FixHourServer     = 18;   // 16:00 London == 18:00 server, year-round
input int    FixMinuteServer   = 0;
input int    PreFixMinutes     = 5;    // start measuring the spike this many minutes before the fix
input int    PostFixMinutes    = 2;    // keep measuring this many minutes after the fix before entering
input int    HoldMinutes       = 30;   // force-close this many minutes after entry if SL/TP not hit

// -- Volatility-adaptive spike filter --------------------------------------
input double MinSpikeVsAvgMultiplier = 2.0;  // trade only if today's spike >= this x the recent average spike size (locked 2026-09-22 after in-sample sweep: 1.0-1.5 diluted to breakeven PF~1.0, 2.0 is the best-defensible balance of edge strength vs. trade count -- see sweep/sweep_results.csv)
input double MinSpikeSizePipsFloor   = 5.0;  // absolute floor regardless of how quiet the recent average is
input int    SpikeHistoryWindow      = 20;   // how many past trading days' spikes to average over
input int    MinHistoryToAdapt       = 5;    // fall back to the floor alone until this many days of history exist

// -- Trade parameters ------------------------------------------------------
input double SLMultiplier      = 1.0;  // stop = spike size * this, beyond entry in the spike's own direction
input double TPMultiplier      = 1.0;  // target = spike size * this, back toward the pre-fix level
input double RiskPercent       = 1.0;  // % of account equity risked per trade
input double MaxSpreadPips     = 3.0;
input int    EndOfDayHour      = 22;   // force-flat time, server time -- day trading only, never hold overnight
input int    MagicNumber       = 20260041;

double pipSize;

int      currentDay = -1;
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

   // At window close, measure the spike, update the rolling history, and
   // decide whether today's spike is large enough RELATIVE TO RECENT
   // VOLATILITY to trade.
   if(!windowEvaluated && haveWindowStartPrice && now >= windowEnd)
   {
      windowEvaluated = true;

      double priceNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double spike = priceNow - priceAtWindowStart;
      double spikePips = MathAbs(spike) / pipSize;

      // Feed the rolling average regardless of pass/fail, so the "normal"
      // baseline isn't itself distorted by excluding the events it exists
      // to detect (same principle as london_range_fade v2's range filter).
      PushSpikeHistory(spikePips);

      double threshold;
      if(spikeHistoryCount < MinHistoryToAdapt)
         threshold = MinSpikeSizePipsFloor; // not enough history yet -- fall back to the floor
      else
         threshold = MathMax(MinSpikeSizePipsFloor, MinSpikeVsAvgMultiplier * AverageSpikeHistory());

      if(spikePips < threshold)
         return; // not large enough relative to recent volatility -- skip

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
