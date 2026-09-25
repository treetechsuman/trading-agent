//+------------------------------------------------------------------+
//| gotobi v1 - sell into the Tokyo pre-fixing dollar-buying spike on |
//| Japanese "gotobi" payment days, day trading only. One ~35-minute   |
//| SELL per gotobi day, closed by the clock rather than a target.     |
//|                                                                     |
//| Intended to run as one copy per pair (USDJPY, EURJPY, GBPJPY) on   |
//| its own chart -- each instance tracks its own position, risk       |
//| sizing and safety ledger independently, which is also how it is    |
//| backtested here (MT5's standard tester only trades the chart's     |
//| own symbol, so each pair gets its own single-symbol run).          |
//|                                                                     |
//| Entry/exit are fixed BROKER-SERVER clock times, hardcoded per       |
//| calendar month rather than derived from TimeGMT() -- TimeGMT() is  |
//| not simulated inside the Strategy Tester (it reflects the real     |
//| host clock, not simulated time), so the UTC target times (00:45    |
//| entry / 01:20 exit) were pre-converted to this broker's server      |
//| clock by hand: server leads UTC by 3h Mar-Oct, 2h Nov-Feb.          |
//+------------------------------------------------------------------+
#property copyright "gotobi"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Trade timing (broker/server clock) --------------------------------
input int    InpEntryHourSummer   = 3;    // Mar-Oct server hour for the 00:45 UTC entry
input int    InpEntryMinuteSummer = 45;
input int    InpEntryHourWinter   = 2;    // Nov-Feb server hour for the 00:45 UTC entry
input int    InpEntryMinuteWinter = 45;
input int    InpLateEntryMinutes  = 10;   // still enter up to this many minutes late, then skip the day
input int    InpHoldMinutes       = 35;   // exit this many minutes after the nominal (on-time) entry clock time

// -- Trade parameters ----------------------------------------------------
input double InpStopLossPips      = 20.0; // protective stop, set once at entry, never moved
input double InpRiskPercent       = 0.5;  // % of account balance risked if the stop is hit
input double InpMaxSpreadPips     = 3.0;  // skip entry if spread is wider than this
input int    MagicNumber          = 20260030;

// -- Safety rules (always on) --------------------------------------------
input int    InpMaxConsecutiveLosses   = 6;   // pause after this many losses in a row
input double InpDailyLossStopPercent   = 5.0; // no more trades today after losing this % of balance today
input double InpMaxDrawdownStopPercent = 15.0;// hard stop after this % drawdown from the balance peak
input bool   InpResetLedgerNow         = false; // manually clear the consecutive-loss pause
input bool   InpResetDrawdownStop      = false; // manually clear the drawdown hard-stop

// -- Live safety -----------------------------------------------------------
input bool   InpAllowLiveAccount  = false; // must be explicitly set true to run on a REAL account

double pipSize;

int      currentDay = -1;           // year*1000 + day_of_year, drives daily state resets
bool     isGotobiDay = false;
bool     enteredToday = false;
datetime entryWindowStart = 0;
datetime entryWindowEnd   = 0;
datetime scheduledExitTime = 0;

int      consecutiveLosses  = 0;
bool     monthlyHaltActive  = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;

double   balancePeak       = 0;
bool     drawdownHaltActive = false;

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

bool IsGotobiDate(const MqlDateTime &s)
{
   if(s.day_of_week == 0 || s.day_of_week == 6) // Sunday/Saturday -- skip, no make-up day
      return false;
   if(s.mon == 2)
   {
      int lastDay = DaysInMonth(2, s.year);
      return (s.day == 5 || s.day == 10 || s.day == 15 || s.day == 20 || s.day == 25 || s.day == lastDay);
   }
   return (s.day == 5 || s.day == 10 || s.day == 15 || s.day == 20 || s.day == 25 || s.day == 30);
}

bool IsSummerBroker(int mon)
{
   return (mon >= 3 && mon <= 10);
}

double CalculateLotSize(double slDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPriceUnit = tickValue / tickSize;
   double lots = riskAmount / (slDistance * valuePerPriceUnit);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   lots = MathMin(maxLot, lots);
   return lots; // deliberately NOT floored up to the broker minimum -- see TryEnter()
}

void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);
   isGotobiDay = IsGotobiDate(s);
   enteredToday = false;

   int entryHour   = IsSummerBroker(s.mon) ? InpEntryHourSummer   : InpEntryHourWinter;
   int entryMinute = IsSummerBroker(s.mon) ? InpEntryMinuteSummer : InpEntryMinuteWinter;

   MqlDateTime w = s;
   w.hour = entryHour;
   w.min  = entryMinute;
   w.sec  = 0;
   entryWindowStart  = StructToTime(w);
   entryWindowEnd    = entryWindowStart + InpLateEntryMinutes * 60;
   // Exit is a fixed clock time off the nominal (on-time) entry, not off the
   // actual (possibly late) fill -- "closed by the clock, not a target".
   scheduledExitTime = entryWindowStart + InpHoldMinutes * 60;

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;
}

void CheckMonthlyHaltResume(const MqlDateTime &s)
{
   if(!monthlyHaltActive)
      return;
   if(s.year > haltSetYear || (s.year == haltSetYear && s.mon > haltSetMonth))
   {
      monthlyHaltActive = false;
      consecutiveLosses = 0;
      Print("gotobi ", _Symbol, ": new month -- consecutive-loss pause lifted.");
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
         Alert("gotobi ", _Symbol, ": drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
               "% from peak balance) -- halted until manually reset (InpResetDrawdownStop).");
      drawdownHaltActive = true;
   }
}

void CloseStalePosition()
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
      Print("gotobi ", _Symbol, ": closing stale position left open from a previous day at EA startup.");
      trade.PositionClose(_Symbol);
   }
}

void ManageOpenPosition(datetime now)
{
   if(!PositionSelect(_Symbol))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return;
   if(now >= scheduledExitTime)
      trade.PositionClose(_Symbol);
}

void TryEnter()
{
   double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
   if(spreadPips > InpMaxSpreadPips)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = bid + InpStopLossPips * pipSize;
   double slDistance = sl - bid;

   double lots = CalculateLotSize(slDistance);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lots < minLot)
   {
      Print("gotobi ", _Symbol, ": skip, computed lot ", DoubleToString(lots, 2),
            " below broker minimum ", DoubleToString(minLot, 2));
      return;
   }

   double marginRequired;
   if(!OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, lots, bid, marginRequired))
      return;
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      Print("gotobi ", _Symbol, ": skip, insufficient free margin");
      return;
   }

   if(trade.Sell(lots, _Symbol, bid, sl, 0.0)) // no take-profit -- closed by the clock
      enteredToday = true;
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("gotobi ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("gotobi ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }

   consecutiveLosses = 0;
   monthlyHaltActive = false;
   drawdownHaltActive = false;
   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);

   CloseStalePosition();

   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   currentDay = s.year * 1000 + s.day_of_year;
   ResetDayState(TimeCurrent());

   return INIT_SUCCEEDED;
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
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
         Print("gotobi ", _Symbol, ": ", InpMaxConsecutiveLosses,
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
   MqlDateTime s;
   TimeToStruct(now, s);
   int dayId = s.year * 1000 + s.day_of_year;
   if(dayId != currentDay)
   {
      currentDay = dayId;
      ResetDayState(now);
      CheckMonthlyHaltResume(s);
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

   if(!isGotobiDay || enteredToday)
      return;
   if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
      return;
   if(PositionSelect(_Symbol)) // never add to an open position / never more than one per pair per day
      return;
   if(now < entryWindowStart || now > entryWindowEnd)
      return;

   TryEnter();
}
