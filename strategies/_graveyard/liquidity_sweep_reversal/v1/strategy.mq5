//+------------------------------------------------------------------+
//| liquidity_sweep_reversal v1 - fade a wick that sweeps through a    |
//| recent swing high/low and closes back inside the prior range,      |
//| London session, scalping only.                                     |
//|                                                                      |
//| Genuinely different signal from everything else tried in this       |
//| project's scalping work so far (overlap_momentum_scalp,             |
//| overlap_deviation_scalp -- 17 combinations total, all statistical   |
//| rolling-average thresholds on price action). This is based on       |
//| concrete recent price STRUCTURE instead: a documented retail/       |
//| institutional pattern where price briefly runs through a resting    |
//| liquidity level (a recent swing high/low, where stop-losses/orders  |
//| cluster) before reversing -- the wick sweeps the level, the bar's   |
//| CLOSE rejects back inside the prior range, signalling the move was  |
//| a liquidity grab rather than a genuine breakout.                    |
//|                                                                      |
//| Session: full London session through the NY overlap (10:00-18:00    |
//| server = 08:00-16:00 London), the window that performed best in     |
//| overlap_deviation_scalp's own testing.                              |
//+------------------------------------------------------------------+
#property copyright "liquidity_sweep_reversal"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Session window (broker/server clock) ---------------------------------
input int    SessionStartHour     = 10;   // 08:00 London == 10:00 server, year-round
input int    SessionEndHour       = 18;   // 16:00 London == 18:00 server

// -- Sweep detection (M5 bars, price structure, not a statistical threshold)
input int    SwingLookback      = 12;   // M5 bars (60 min) of prior structure to define the swing level
input double MinSweepPips       = 2.0;  // minimum distance the wick must clear the level by to count
input double StopBufferPips     = 2.0;  // extra buffer beyond the sweep wick for the stop

// -- Trade parameters -------------------------------------------------------
input double TPMultiplier      = 1.5;  // target = stop distance * this
input int    MaxHoldMinutes    = 30;
input int    MaxTradesPerDay   = 5;
input double RiskPercent       = 0.3;
input double MaxSpreadPips     = 2.5;
input int    MagicNumber       = 20260070;

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
      Print("liquidity_sweep_reversal: new month -- consecutive-loss pause lifted.");
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
         Alert("liquidity_sweep_reversal: drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
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

double SwingHigh()
{
   double hh = -DBL_MAX;
   for(int i = 2; i <= SwingLookback + 1; i++)
      hh = MathMax(hh, iHigh(_Symbol, PERIOD_M5, i));
   return hh;
}

double SwingLow()
{
   double ll = DBL_MAX;
   for(int i = 2; i <= SwingLookback + 1; i++)
      ll = MathMin(ll, iLow(_Symbol, PERIOD_M5, i));
   return ll;
}

void ProcessClosedBar(datetime now)
{
   if(PositionSelect(_Symbol))
      return;
   if(tradesToday >= MaxTradesPerDay)
      return;
   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
      return;

   double barHigh  = iHigh(_Symbol, PERIOD_M5, 1);
   double barLow   = iLow(_Symbol, PERIOD_M5, 1);
   double barClose = iClose(_Symbol, PERIOD_M5, 1);

   double swingHigh = SwingHigh();
   double swingLow  = SwingLow();
   double sweepBuf  = MinSweepPips * pipSize;
   double stopBuf   = StopBufferPips * pipSize;

   bool bearishSweep = (barHigh > swingHigh + sweepBuf) && (barClose < swingHigh);
   bool bullishSweep = (barLow  < swingLow  - sweepBuf) && (barClose > swingLow);

   // A bar that sweeps both sides in the same period is ambiguous -- skip it
   // rather than guess.
   if(bearishSweep && bullishSweep)
      return;
   if(!bearishSweep && !bullishSweep)
      return;

   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
   if(spreadPips > MaxSpreadPips)
      return;

   bool success = false;
   if(bearishSweep)
   {
      // Swept above a resting high, rejected back below it -- fade: sell
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = barHigh + stopBuf;
      double slDistance = sl - bid;
      double tp = bid - slDistance * TPMultiplier;
      double lots = CalculateLotSize(slDistance);
      if(lots > 0)
         success = trade.Sell(lots, _Symbol, bid, sl, tp);
   }
   else
   {
      // Swept below a resting low, rejected back above it -- fade: buy
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = barLow - stopBuf;
      double slDistance = ask - sl;
      double tp = ask + slDistance * TPMultiplier;
      double lots = CalculateLotSize(slDistance);
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

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("liquidity_sweep_reversal: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("liquidity_sweep_reversal: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
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
         Print("liquidity_sweep_reversal: ", InpMaxConsecutiveLosses,
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

   datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
   if(barTime != lastBarTime)
   {
      lastBarTime = barTime;
      ProcessClosedBar(now);
   }
}
