//+------------------------------------------------------------------+
//| intraday_momentum_carry v1 - trade the sign of the London          |
//| session's first half-hour return into the last half-hour,          |
//| day trading only.                                                  |
//|                                                                      |
//| Thesis, from the academic literature (not an internally-invented    |
//| pattern like every prior technical-pattern strategy in this         |
//| project): Gao, Han, Li & Zhou (2018, Journal of Financial           |
//| Economics) documented that a market's first half-hour return        |
//| predicts its last half-hour return in the SAME direction,           |
//| statistically and economically significant, attributed to          |
//| daytrader/informed-trader behavior. Baltussen et al. (2021)          |
//| extended this to 60+ futures across equities, bonds, commodities,   |
//| AND CURRENCIES over 40+ years, and both papers report the effect    |
//| survives realistic transaction costs -- a categorically stronger    |
//| evidence base than every prior strategy tried in this project,      |
//| which were internally-invented technical patterns.                  |
//|                                                                      |
//| v1 replicates the literature's construction as directly as          |
//| possible, deliberately WITHOUT adding filters the research didn't   |
//| call for: measure the London session's first 30-minute return       |
//| (sign only, no magnitude threshold), then take a position in that   |
//| same direction at the start of the session's last 30 minutes,       |
//| held to session close. A fixed pip stop (day-trading scale,         |
//| matching gotobi's convention) is the only risk-management addition  |
//| -- the paper studies return predictability, not a specific stop-    |
//| loss discipline, so this is this project's own choice, not a claim  |
//| from the research.                                                  |
//+------------------------------------------------------------------+
#property copyright "intraday_momentum_carry"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Session window (broker/server clock) ---------------------------------
input int    SessionStartHour     = 10;   // 08:00 London == 10:00 server, year-round
input int    SessionEndHour       = 18;   // 16:00 London == 18:00 server
input int    FirstWindowMinutes   = 30;   // length of the "first half-hour" measurement window
input int    LastWindowMinutes    = 30;   // length of the "last half-hour" trading window

// -- Entry filter (off by default -- v1 stays faithful to the literature's
//    sign-only construction; set > 0 to require a minimum first-window move) --
input double MinFirstMovePips     = 0.0;

// -- Trade parameters -------------------------------------------------------
input double StopLossPips      = 20.0; // fixed, day-trading scale (matches gotobi's convention)
input double RiskPercent       = 0.75; // % of account balance risked per trade
input double MaxSpreadPips     = 2.0;
input int    MagicNumber       = 20260080;

// -- Safety rules (always on, same pattern as gotobi) ----------------------
input int    InpMaxConsecutiveLosses   = 6;
input double InpDailyLossStopPercent   = 5.0;
input double InpMaxDrawdownStopPercent = 15.0;
input bool   InpResetLedgerNow         = false;
input bool   InpResetDrawdownStop      = false;
input bool   InpAllowLiveAccount       = false;

double pipSize;

int      currentDay = -1;
datetime firstWindowStart = 0;
datetime firstWindowEnd   = 0;
datetime lastWindowStart  = 0;
datetime sessionEndTime   = 0;

double   priceAtFirstStart = 0;
bool     haveFirstStartPrice = false;
double   firstMovePips = 0;
bool     firstWindowEvaluated = false;
bool     tradeTakenToday = false;

int      consecutiveLosses = 0;
bool     monthlyHaltActive = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;
double   balancePeak       = 0;
bool     drawdownHaltActive = false;

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
   MqlDateTime s;
   TimeToStruct(now, s);

   MqlDateTime f = s;
   f.hour = SessionStartHour;
   f.min  = 0;
   f.sec  = 0;
   datetime sessionStart = StructToTime(f);

   MqlDateTime e = s;
   e.hour = SessionEndHour;
   e.min  = 0;
   e.sec  = 0;
   sessionEndTime = StructToTime(e);

   firstWindowStart = sessionStart;
   firstWindowEnd   = sessionStart + FirstWindowMinutes * 60;
   lastWindowStart  = sessionEndTime - LastWindowMinutes * 60;

   haveFirstStartPrice = false;
   firstWindowEvaluated = false;
   tradeTakenToday = false;
   priceAtFirstStart = 0;
   firstMovePips = 0;

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
      Print("intraday_momentum_carry: new month -- consecutive-loss pause lifted.");
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
         Alert("intraday_momentum_carry: drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
               "% from peak balance) -- halted until manually reset (InpResetDrawdownStop).");
      drawdownHaltActive = true;
   }
}

double CalculateLotSize(double slDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
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
   if(now >= sessionEndTime)
      trade.PositionClose(_Symbol);
}

void OnInit_CloseStalePosition()
{
   if(!PositionSelect(_Symbol))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return;
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
   MqlDateTime a, b;
   TimeToStruct(openTime, a);
   TimeToStruct(TimeCurrent(), b);
   bool sameDay = (a.year == b.year && a.day_of_year == b.day_of_year);
   if(!sameDay)
   {
      Print("intraday_momentum_carry: closing stale position left open from a previous day at EA startup.");
      trade.PositionClose(_Symbol);
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("intraday_momentum_carry: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("intraday_momentum_carry: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }

   consecutiveLosses = 0;
   monthlyHaltActive = false;
   drawdownHaltActive = false;
   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);

   OnInit_CloseStalePosition();

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
         Print("intraday_momentum_carry: ", InpMaxConsecutiveLosses,
               " consecutive losses -- pausing until the first day of next month.");
      }
   }
   else
   {
      consecutiveLosses = 0;
   }
}

void TryEnter(datetime now)
{
   if(tradeTakenToday)
      return;
   if(PositionSelect(_Symbol))
      return;
   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
      return;
   if(!firstWindowEvaluated)
      return;
   if(MathAbs(firstMovePips) < MinFirstMovePips)
      return;

   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
   if(spreadPips > MaxSpreadPips)
      return;

   double slDistance = StopLossPips * pipSize;
   bool success = false;

   if(firstMovePips > 0)
   {
      // First half-hour was up -- literature predicts the last half-hour
      // continues up too: buy
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - slDistance;
      double lots = CalculateLotSize(ask - sl);
      if(lots > 0)
         success = trade.Buy(lots, _Symbol, ask, sl, 0.0);
   }
   else
   {
      // First half-hour was down -- literature predicts continuation down: sell
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = bid + slDistance;
      double lots = CalculateLotSize(sl - bid);
      if(lots > 0)
         success = trade.Sell(lots, _Symbol, bid, sl, 0.0);
   }

   if(success)
      tradeTakenToday = true;
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

   if(now < firstWindowStart || now >= sessionEndTime)
      return;

   // Capture the price at the start of the first window
   if(!haveFirstStartPrice && now >= firstWindowStart && now < firstWindowEnd)
   {
      priceAtFirstStart = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      haveFirstStartPrice = true;
      return;
   }

   // At the first window's close, lock in its return
   if(!firstWindowEvaluated && haveFirstStartPrice && now >= firstWindowEnd)
   {
      double priceNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      firstMovePips = (priceNow - priceAtFirstStart) / pipSize;
      firstWindowEvaluated = true;
   }

   // Enter once the last window opens
   if(now >= lastWindowStart)
      TryEnter(now);
}
