//+------------------------------------------------------------------+
//| wm_fix_reversal v2 - PORTFOLIO TEST HARNESS.                        |
//|                                                                      |
//| Not a new strategy version -- identical per-pair rules to v2's       |
//| strategy.mq5 (same fix-window measurement, volatility-adaptive       |
//| spike threshold, SL/TP, 30-min exit), just restructured to run       |
//| both pairs (EURUSD.r, GBPUSD.r) from ONE EA instance against ONE     |
//| simulated account, to test a specific hypothesis: each pair had      |
//| exactly one losing out-of-sample year (EURUSD 2025, GBPUSD 2024)     |
//| that didn't coincide -- suggesting a combined account might be       |
//| more consistently profitable than either pair traded alone. v2's     |
//| normal per-pair backtests are two independent single-symbol runs     |
//| and cannot show this -- MT5's standard tester only trades the        |
//| chart's own symbol.                                                  |
//|                                                                      |
//| Attach to any one chart as the tick-driving source (used: EURUSD.r)  |
//| -- trades are placed on both symbols by name regardless of which     |
//| chart the EA is on.                                                  |
//|                                                                      |
//| IMPORTANT (lesson from gotobi/v1_portfolio, applied here from the    |
//| start): a single CTrade object only tracks ONE "current" magic       |
//| number. trade.SetExpertMagicNumber(magic) must be called again       |
//| immediately before EVERY PositionClose() call, not just before the   |
//| opening Sell()/Buy() -- otherwise closes for whichever symbol wasn't |
//| entered last each day get silently rejected forever (retcode        |
//| 10006), leaving a position stuck open indefinitely.                  |
//+------------------------------------------------------------------+
#property copyright "wm_fix_reversal"
#property version   "2.00"

#include <Trade/Trade.mqh>
CTrade trade;

#define NPAIRS 2
string PairSymbols[NPAIRS] = {"EURUSD.r", "GBPUSD.r"};

// -- Fix window timing (broker/server clock) -----------------------------
input int    FixHourServer     = 18;   // 16:00 London == 18:00 server, year-round
input int    FixMinuteServer   = 0;
input int    PreFixMinutes     = 5;
input int    PostFixMinutes    = 2;
input int    HoldMinutes       = 30;

// -- Volatility-adaptive spike filter --------------------------------------
input double MinSpikeVsAvgMultiplier = 2.0;  // locked value from v2's own sweep
input double MinSpikeSizePipsFloor   = 5.0;
input int    SpikeHistoryWindow      = 20;
input int    MinHistoryToAdapt       = 5;

// -- Trade parameters ------------------------------------------------------
input double SLMultiplier      = 1.0;
input double TPMultiplier      = 1.0;
input double RiskPercent       = 1.0;  // % of account equity risked, PER PAIR
input double MaxSpreadPips     = 3.0;
input int    EndOfDayHour      = 22;
input int    MagicNumberBase   = 20260042; // pair i gets MagicNumberBase + i

double pipSize[NPAIRS];

int      currentDay = -1;
datetime windowStart = 0;
datetime windowEnd   = 0;
datetime scheduledExitTime = 0;

double   priceAtWindowStart[NPAIRS];
bool     haveWindowStartPrice[NPAIRS];
bool     windowEvaluated[NPAIRS];
bool     tradeTakenToday[NPAIRS];

// Two separate resizable 1D arrays (not a 2D array of fixed size) so each
// pair's history genuinely tracks the SpikeHistoryWindow input rather than
// a hardcoded slot count that could silently overflow if that input changes.
double   spikeHistoryEUR[];
double   spikeHistoryGBP[];
int      spikeHistoryCount[NPAIRS];
int      spikeHistoryNext[NPAIRS];

int OnInit()
{
   trade.SetExpertMagicNumber((ulong)MagicNumberBase);

   ArrayResize(spikeHistoryEUR, SpikeHistoryWindow);
   ArrayResize(spikeHistoryGBP, SpikeHistoryWindow);

   for(int i = 0; i < NPAIRS; i++)
   {
      SymbolSelect(PairSymbols[i], true);
      int d = (int)SymbolInfoInteger(PairSymbols[i], SYMBOL_DIGITS);
      double point = SymbolInfoDouble(PairSymbols[i], SYMBOL_POINT);
      pipSize[i] = (d == 3 || d == 5) ? point * 10 : point;
      spikeHistoryCount[i] = 0;
      spikeHistoryNext[i] = 0;
   }

   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   currentDay = s.year * 1000 + s.day_of_year;
   ResetDayState(TimeCurrent());

   return(INIT_SUCCEEDED);
}

int HourOf(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour;
}

double AverageSpikeHistory(int i)
{
   double sum = 0;
   if(i == 0)
   {
      for(int k = 0; k < spikeHistoryCount[i]; k++)
         sum += spikeHistoryEUR[k];
   }
   else
   {
      for(int k = 0; k < spikeHistoryCount[i]; k++)
         sum += spikeHistoryGBP[k];
   }
   return sum / spikeHistoryCount[i];
}

void PushSpikeHistory(int i, double spikePips)
{
   if(i == 0)
      spikeHistoryEUR[spikeHistoryNext[i]] = spikePips;
   else
      spikeHistoryGBP[spikeHistoryNext[i]] = spikePips;
   spikeHistoryNext[i] = (spikeHistoryNext[i] + 1) % SpikeHistoryWindow;
   if(spikeHistoryCount[i] < SpikeHistoryWindow)
      spikeHistoryCount[i]++;
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

   for(int i = 0; i < NPAIRS; i++)
   {
      haveWindowStartPrice[i] = false;
      windowEvaluated[i] = false;
      tradeTakenToday[i] = false;
      priceAtWindowStart[i] = 0;
   }
}

double CalculateLotSize(string sym, double slDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPriceUnit = tickValue / tickSize;
   double lots = riskAmount / (slDistance * valuePerPriceUnit);

   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

   lots = MathFloor(lots / step) * step;
   lots = MathMin(maxLot, lots);
   if(lots < minLot)
      return 0.0;
   return lots;
}

void ManageOpenPosition(int i, datetime now)
{
   string sym = PairSymbols[i];
   ulong magic = (ulong)(MagicNumberBase + i);

   if(!PositionSelect(sym))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != magic)
      return;

   bool eod = (HourOf(now) >= EndOfDayHour);
   if(eod || now >= scheduledExitTime)
   {
      trade.SetExpertMagicNumber(magic); // see header note -- must re-set before every close
      trade.PositionClose(sym);
   }
}

void EvaluateFixWindow(int i, datetime now)
{
   string sym = PairSymbols[i];

   if(tradeTakenToday[i])
      return;

   if(!haveWindowStartPrice[i] && now >= windowStart && now < windowEnd)
   {
      priceAtWindowStart[i] = SymbolInfoDouble(sym, SYMBOL_BID);
      haveWindowStartPrice[i] = true;
      return;
   }

   if(!windowEvaluated[i] && haveWindowStartPrice[i] && now >= windowEnd)
   {
      windowEvaluated[i] = true;

      double priceNow = SymbolInfoDouble(sym, SYMBOL_BID);
      double spike = priceNow - priceAtWindowStart[i];
      double spikePips = MathAbs(spike) / pipSize[i];

      PushSpikeHistory(i, spikePips);

      double threshold;
      if(spikeHistoryCount[i] < MinHistoryToAdapt)
         threshold = MinSpikeSizePipsFloor;
      else
         threshold = MathMax(MinSpikeSizePipsFloor, MinSpikeVsAvgMultiplier * AverageSpikeHistory(i));

      if(spikePips < threshold)
         return;

      double spreadPips = (SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / pipSize[i];
      if(spreadPips > MaxSpreadPips)
         return;

      double slDistance = spikePips * pipSize[i] * SLMultiplier;
      double tpDistance  = spikePips * pipSize[i] * TPMultiplier;
      ulong magic = (ulong)(MagicNumberBase + i);

      if(spike > 0)
      {
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double sl = bid + slDistance;
         double tp = bid - tpDistance;
         double lots = CalculateLotSize(sym, sl - bid);
         if(lots > 0)
         {
            trade.SetExpertMagicNumber(magic);
            if(trade.Sell(lots, sym, bid, sl, tp))
               tradeTakenToday[i] = true;
         }
      }
      else
      {
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         double sl = ask - slDistance;
         double tp = ask + tpDistance;
         double lots = CalculateLotSize(sym, ask - sl);
         if(lots > 0)
         {
            trade.SetExpertMagicNumber(magic);
            if(trade.Buy(lots, sym, ask, sl, tp))
               tradeTakenToday[i] = true;
         }
      }
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
   }

   for(int i = 0; i < NPAIRS; i++)
      ManageOpenPosition(i, now);

   for(int i = 0; i < NPAIRS; i++)
      EvaluateFixWindow(i, now);
}
