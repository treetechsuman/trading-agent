//+------------------------------------------------------------------+
//| overlap_deviation_scalp v1 - deviation-from-moving-average mean    |
//| reversion scalp during the London/New York overlap, scalping only. |
//|                                                                      |
//| Direct continuation of the retired overlap_momentum_scalp line      |
//| (see strategies/_graveyard/overlap_momentum_scalp/REASON.md).       |
//| That project tested four mechanisms on EURUSD.r; the only one with  |
//| a genuine directional signal was fading price's deviation from a    |
//| short M1 moving average (55.86% win rate, consistently >50% both    |
//| directions) -- but it still lost (PF 0.82) because this account's   |
//| fixed per-lot commission (-$1,784.13 vs. a gross edge of only       |
//| +$729.60 over 725 trades) overwhelmed the small real edge at        |
//| EURUSD's typical scalp target size.                                 |
//|                                                                      |
//| This strategy reuses that exact validated mechanism unchanged, but  |
//| tests it across multiple pairs -- the hypothesis being that a more  |
//| volatile pair may have a better gross-edge-to-fixed-commission      |
//| ratio even at the same % risk per trade, since typical pip moves    |
//| (and therefore typical targets) are larger relative to the fixed    |
//| per-lot cost. Same volatility-adaptive threshold technique as       |
//| every other strategy in this project (rolling average of the        |
//| session's own recent deviations, not a fixed pip count).            |
//+------------------------------------------------------------------+
#property copyright "overlap_deviation_scalp"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Session window (broker/server clock) ---------------------------------
input int    SessionStartHour     = 15;   // 13:00 London == 15:00 server, year-round
input int    SessionEndHour       = 18;   // 16:00 London == 18:00 server

// -- Deviation-from-mean detection (volatility-adaptive) --------------------
input int    SMAPeriod                  = 20;  // M1 bars
input double MinDeviationVsAvgMultiplier = 4.0;  // locked 2026-09-23 after per-pair sweep: GBPUSD.r was the best of 4 pairs tested at defaults (EURUSD, GBPUSD, USDJPY, GBPJPY.r); a threshold sweep on GBPUSD showed a genuine peak at 4.0 (PF 1.02, 495 trades, 3.96% max DD) rather than monotonic improvement toward the most selective end -- see GBPUSD/sweep/sweep_results.csv. Primary tested symbol is now GBPUSD.r, not EURUSD.
input double MinDeviationPipsFloor      = 3.0;
input int    DeviationHistoryWindow     = 30;
input int    MinHistoryToAdapt          = 10;

// -- Trade parameters -------------------------------------------------------
input double SLMultiplier      = 1.0;
input double TPMultiplier      = 2.0;
input double MinStopPips       = 5.0;
input int    MaxHoldMinutes    = 30;  // locked 2026-09-23 -- diagnosed 68-73% of trades were hitting the old 15-min limit before reaching SL/TP, making the nominal R:R barely relevant to actual outcomes. A hold-time sweep showed a genuine peak at 30min (PF 1.09, $527 net vs 15min's PF 1.02/$105) -- see GBPUSD/sweep/sweep_hold_results.csv
input int    MaxTradesPerDay   = 5;
input double RiskPercent       = 0.3;
input double MaxSpreadPips     = 2.5;  // widened from 1.5 -- more volatile pairs run wider natural spreads
input int    MagicNumber       = 20260060;

// -- Safety rules (always on, same pattern as gotobi) ----------------------
input int    InpMaxConsecutiveLosses   = 8;
input double InpDailyLossStopPercent   = 5.0;
input double InpMaxDrawdownStopPercent = 15.0;
input bool   InpResetLedgerNow         = false;
input bool   InpResetDrawdownStop      = false;
input bool   InpAllowLiveAccount       = false;

double pipSize;

int      currentDay = -1;
datetime lastBarTime = 0;
int      tradesToday = 0;

double   deviationHistory[];
int      deviationHistoryCount = 0;
int      deviationHistoryNext  = 0;

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

double AverageDeviationHistory()
{
   double sum = 0;
   for(int i = 0; i < deviationHistoryCount; i++)
      sum += deviationHistory[i];
   return sum / deviationHistoryCount;
}

void PushDeviationHistory(double devPips)
{
   deviationHistory[deviationHistoryNext] = devPips;
   deviationHistoryNext = (deviationHistoryNext + 1) % DeviationHistoryWindow;
   if(deviationHistoryCount < DeviationHistoryWindow)
      deviationHistoryCount++;
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
      Print("overlap_deviation_scalp: new month -- consecutive-loss pause lifted.");
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
         Alert("overlap_deviation_scalp: drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
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

double ComputeSMA()
{
   double sum = 0;
   for(int i = 1; i <= SMAPeriod; i++)
      sum += iClose(_Symbol, PERIOD_M1, i);
   return sum / SMAPeriod;
}

void ProcessClosedBar(datetime now)
{
   double closePrice = iClose(_Symbol, PERIOD_M1, 1);
   double sma = ComputeSMA();
   double deviation = closePrice - sma;
   double devPips = MathAbs(deviation) / pipSize;

   PushDeviationHistory(devPips);

   if(PositionSelect(_Symbol))
      return;
   if(tradesToday >= MaxTradesPerDay)
      return;
   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
      return;

   double threshold;
   if(deviationHistoryCount < MinHistoryToAdapt)
      threshold = MinDeviationPipsFloor;
   else
      threshold = MathMax(MinDeviationPipsFloor, MinDeviationVsAvgMultiplier * AverageDeviationHistory());

   if(devPips < threshold)
      return;

   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
   if(spreadPips > MaxSpreadPips)
      return;

   double slDistancePips = MathMax(MinStopPips, devPips * SLMultiplier);
   double tpDistancePips = devPips * TPMultiplier;
   double slDistance = slDistancePips * pipSize;
   double tpDistance = tpDistancePips * pipSize;

   bool success = false;
   if(deviation > 0)
   {
      // Price above the mean -- fade it, bet on reversion down: sell
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = bid + slDistance;
      double tp = bid - tpDistance;
      double lots = CalculateLotSize(sl - bid);
      if(lots > 0)
         success = trade.Sell(lots, _Symbol, bid, sl, tp);
   }
   else
   {
      // Price below the mean -- fade it, bet on reversion up: buy
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - slDistance;
      double tp = ask + tpDistance;
      double lots = CalculateLotSize(ask - sl);
      if(lots > 0)
         success = trade.Buy(lots, _Symbol, ask, sl, tp);
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
   ArrayResize(deviationHistory, DeviationHistoryWindow);

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("overlap_deviation_scalp: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("overlap_deviation_scalp: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
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
         Print("overlap_deviation_scalp: ", InpMaxConsecutiveLosses,
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
