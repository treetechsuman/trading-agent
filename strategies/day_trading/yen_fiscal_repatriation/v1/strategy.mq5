//+------------------------------------------------------------------+
//| yen_fiscal_repatriation v1 - sell JPY crosses during the final     |
//| FiscalWindowDays calendar days of Japan's fiscal year-end (March)  |
//| and fiscal half-year-end (September), on the documented thesis     |
//| that Japanese institutional investors (life insurers, pension      |
//| funds, megabanks) reduce net FX exposure / add hedges / repatriate |
//| realized gains ahead of these balance-sheet dates. One SELL per    |
//| qualifying weekday, closed by the clock (fixed 09:00 UTC), not a   |
//| price target.                                                      |
//|                                                                     |
//| Intended to run as one copy per pair (USDJPY, EURJPY.r, GBPJPY.r)  |
//| on its own chart -- each instance tracks its own position, risk    |
//| sizing and safety ledger independently, same pattern as gotobi/v1. |
//|                                                                     |
//| Entry/exit are fixed BROKER-SERVER clock times, hardcoded per       |
//| calendar month rather than derived from TimeGMT() -- TimeGMT() is  |
//| not simulated inside the Strategy Tester (reflects the real host    |
//| clock, not simulated time). The UTC target times (00:15 entry /     |
//| 09:00 exit) were pre-converted to this broker's server clock using  |
//| the same table already validated for gotobi/v1: server leads UTC   |
//| by 3h Mar-Oct, 2h Nov-Feb (whole-month simplification, not an        |
//| exact DST-transition-date calculation -- inherited unchanged from   |
//| gotobi/v1 per spec instruction to mirror it rather than re-derive). |
//+------------------------------------------------------------------+
#property copyright "yen_fiscal_repatriation"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- Fiscal window definition --------------------------------------------
input int    InpFiscalWindowDays  = 15;   // trade every weekday in the final N calendar days of March AND September

// -- Trade timing (broker/server clock) -----------------------------------
input int    InpEntryHourSummer   = 3;    // Mar-Oct server hour for the 00:15 UTC entry
input int    InpEntryMinuteSummer = 15;
input int    InpEntryHourWinter   = 2;    // Nov-Feb server hour for the 00:15 UTC entry
input int    InpEntryMinuteWinter = 15;
input int    InpLateEntryMinutes  = 10;   // still enter up to this many minutes late, then skip the day
input int    InpExitHourSummer    = 12;   // Mar-Oct server hour for the 09:00 UTC clock exit
input int    InpExitMinuteSummer  = 0;
input int    InpExitHourWinter    = 11;   // Nov-Feb server hour for the 09:00 UTC clock exit
input int    InpExitMinuteWinter  = 0;

// -- Trade parameters ----------------------------------------------------
input double InpStopLossPips      = 40.0; // protective stop, set once at entry, never moved
input double InpRiskPercent       = 0.5;  // % of account balance risked if the stop is hit
input double InpMaxSpreadPips     = 3.0;  // skip entry if spread is wider than this
input int    MagicNumber          = 20260041;

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
bool     isFiscalWindowDay = false;
bool     enteredToday = false;
datetime entryWindowStart = 0;
datetime entryWindowEnd   = 0;
datetime scheduledExitTime = 0;

int      consecutiveLosses  = 0;
bool     windowHaltActive   = false;   // consecutive-loss pause; resumes on the first day of the NEXT qualifying window
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

// Calendar-day window (not a trading-day count): final InpFiscalWindowDays
// calendar days of March, and final InpFiscalWindowDays calendar days of
// September, weekdays only, no make-up day for weekends -- same convention
// as gotobi.
bool IsFiscalWindowDate(const MqlDateTime &s)
{
   if(s.day_of_week == 0 || s.day_of_week == 6) // Sunday/Saturday -- skip, no make-up day
      return false;
   if(s.mon == 3 || s.mon == 9)
   {
      int lastDay = DaysInMonth(s.mon, s.year);
      return (s.day > lastDay - InpFiscalWindowDays);
   }
   return false;
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
   isFiscalWindowDay = IsFiscalWindowDate(s);
   enteredToday = false;

   bool summer = IsSummerBroker(s.mon);
   int entryHour   = summer ? InpEntryHourSummer   : InpEntryHourWinter;
   int entryMinute = summer ? InpEntryMinuteSummer : InpEntryMinuteWinter;
   int exitHour    = summer ? InpExitHourSummer    : InpExitHourWinter;
   int exitMinute  = summer ? InpExitMinuteSummer  : InpExitMinuteWinter;

   MqlDateTime w = s;
   w.hour = entryHour;
   w.min  = entryMinute;
   w.sec  = 0;
   entryWindowStart  = StructToTime(w);
   entryWindowEnd    = entryWindowStart + InpLateEntryMinutes * 60;

   // Exit is a fixed clock time (09:00 UTC, converted), not an offset from
   // the entry fill -- "market close at 09:00 UTC regardless of P&L".
   MqlDateTime e = s;
   e.hour = exitHour;
   e.min  = exitMinute;
   e.sec  = 0;
   scheduledExitTime = StructToTime(e);

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;
}

// Resume: "first day of next qualifying window" -- lift the halt the first
// time a NEW qualifying window (a different year/month than the one the
// halt was set in) is encountered, not simply next calendar month.
void CheckWindowHaltResume(const MqlDateTime &s)
{
   if(!windowHaltActive)
      return;
   if(!isFiscalWindowDay)
      return;
   if((s.year * 12 + s.mon) > (haltSetYear * 12 + haltSetMonth))
   {
      windowHaltActive = false;
      consecutiveLosses = 0;
      Print("yen_fiscal_repatriation ", _Symbol, ": new qualifying window -- consecutive-loss pause lifted.");
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
         Alert("yen_fiscal_repatriation ", _Symbol, ": drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
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
      Print("yen_fiscal_repatriation ", _Symbol, ": closing stale position left open from a previous day at EA startup.");
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
      Print("yen_fiscal_repatriation ", _Symbol, ": skip, computed lot ", DoubleToString(lots, 2),
            " below broker minimum ", DoubleToString(minLot, 2));
      return;
   }

   double marginRequired;
   if(!OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, lots, bid, marginRequired))
      return;
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      Print("yen_fiscal_repatriation ", _Symbol, ": skip, insufficient free margin");
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
      Alert("yen_fiscal_repatriation ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("yen_fiscal_repatriation ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }

   consecutiveLosses = 0;
   windowHaltActive = false;
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
      if(consecutiveLosses >= InpMaxConsecutiveLosses && !windowHaltActive)
      {
         windowHaltActive = true;
         MqlDateTime s;
         TimeToStruct(TimeCurrent(), s);
         haltSetYear = s.year;
         haltSetMonth = s.mon;
         Print("yen_fiscal_repatriation ", _Symbol, ": ", InpMaxConsecutiveLosses,
               " consecutive losses -- pausing until the first day of the next qualifying window.");
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
      CheckWindowHaltResume(s);
   }

   if(InpResetLedgerNow)
   {
      windowHaltActive = false;
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

   if(!isFiscalWindowDay || enteredToday)
      return;
   if(windowHaltActive || dailyHaltActive || drawdownHaltActive)
      return;
   if(PositionSelect(_Symbol)) // never add to an open position / never more than one per pair per day
      return;
   if(now < entryWindowStart || now > entryWindowEnd)
      return;

   TryEnter();
}
