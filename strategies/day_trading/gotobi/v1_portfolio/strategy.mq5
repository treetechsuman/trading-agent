//+------------------------------------------------------------------+
//| gotobi v1 - PORTFOLIO TEST HARNESS.                                 |
//|                                                                      |
//| Not a new strategy version -- identical per-pair rules to v1's       |
//| strategy.mq5 (same entry/exit clock times, 20-pip stop, 0.5% risk,   |
//| 3-pip spread cap, safety ledger), just restructured to run all       |
//| three pairs (USDJPY, EURJPY.r, GBPJPY.r) from ONE EA instance         |
//| against ONE simulated account, so the true combined-account          |
//| exposure/drawdown (up to 1.5% risked across all three pairs on the   |
//| same gotobi day) can actually be measured. v1's normal per-pair      |
//| backtests are three independent single-symbol runs and cannot show   |
//| this -- MT5's standard tester only trades the chart's own symbol,    |
//| which is why this harness exists as a separate artifact.             |
//|                                                                      |
//| Attach to any one chart as the tick-driving source (used: USDJPY,    |
//| longest tick history of the three) -- trades are placed on all       |
//| three symbols by name regardless of which chart the EA is on.        |
//| Consecutive-loss pauses stay per-pair (matches how three independent |
//| live EA instances would behave); daily-loss and drawdown stops are   |
//| evaluated once against the shared account balance, since that's a   |
//| single real account either way.                                      |
//+------------------------------------------------------------------+
#property copyright "gotobi"
#property version   "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

#define NPAIRS 3
string PairSymbols[NPAIRS] = {"USDJPY", "EURJPY.r", "GBPJPY.r"};

// -- Trade timing (broker/server clock) --------------------------------
input int    InpEntryHourSummer   = 3;    // Mar-Oct server hour for the 00:45 UTC entry
input int    InpEntryMinuteSummer = 45;
input int    InpEntryHourWinter   = 2;    // Nov-Feb server hour for the 00:45 UTC entry
input int    InpEntryMinuteWinter = 45;
input int    InpLateEntryMinutes  = 10;
input int    InpHoldMinutes       = 35;

// -- Trade parameters ----------------------------------------------------
input double InpStopLossPips      = 20.0;
input double InpRiskPercent       = 0.5;  // % of account balance risked, PER PAIR, if its stop is hit
input double InpMaxSpreadPips     = 3.0;
input int    MagicNumberBase      = 20260030; // pair i gets MagicNumberBase + i

// -- Safety rules ----------------------------------------------------------
input int    InpMaxConsecutiveLosses   = 6;   // per pair
input double InpDailyLossStopPercent   = 5.0; // against the shared account balance
input double InpMaxDrawdownStopPercent = 15.0;// against the shared account balance
input bool   InpResetLedgerNow         = false;
input bool   InpResetDrawdownStop      = false;

// -- Live safety -----------------------------------------------------------
input bool   InpAllowLiveAccount  = false;

double pipSize[NPAIRS];
bool   enteredToday[NPAIRS];
int    consecutiveLosses[NPAIRS];
bool   monthlyHaltActive[NPAIRS];
int    haltSetYear[NPAIRS];
int    haltSetMonth[NPAIRS];

int      currentDay = -1;
bool     isGotobiDay = false;
datetime entryWindowStart = 0;
datetime entryWindowEnd   = 0;
datetime scheduledExitTime = 0;

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
   if(s.day_of_week == 0 || s.day_of_week == 6)
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

double CalculateLotSize(string sym, int i, double slDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPriceUnit = tickValue / tickSize;
   double lots = riskAmount / (slDistance * valuePerPriceUnit);

   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   lots = MathMin(maxLot, lots);
   return lots;
}

void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);
   isGotobiDay = IsGotobiDate(s);
   for(int i = 0; i < NPAIRS; i++)
      enteredToday[i] = false;

   int entryHour   = IsSummerBroker(s.mon) ? InpEntryHourSummer   : InpEntryHourWinter;
   int entryMinute = IsSummerBroker(s.mon) ? InpEntryMinuteSummer : InpEntryMinuteWinter;

   MqlDateTime w = s;
   w.hour = entryHour;
   w.min  = entryMinute;
   w.sec  = 0;
   entryWindowStart  = StructToTime(w);
   entryWindowEnd    = entryWindowStart + InpLateEntryMinutes * 60;
   scheduledExitTime = entryWindowStart + InpHoldMinutes * 60;

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyHaltActive = false;
}

void CheckMonthlyHaltResume(const MqlDateTime &s)
{
   for(int i = 0; i < NPAIRS; i++)
   {
      if(!monthlyHaltActive[i])
         continue;
      if(s.year > haltSetYear[i] || (s.year == haltSetYear[i] && s.mon > haltSetMonth[i]))
      {
         monthlyHaltActive[i] = false;
         consecutiveLosses[i] = 0;
         Print("gotobi portfolio ", PairSymbols[i], ": new month -- consecutive-loss pause lifted.");
      }
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
         Alert("gotobi portfolio: drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
               "% from peak balance) -- halted until manually reset (InpResetDrawdownStop).");
      drawdownHaltActive = true;
   }
}

void CloseStalePosition(string sym, ulong magic)
{
   if(!PositionSelect(sym))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != magic)
      return;

   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
   MqlDateTime a, b;
   TimeToStruct(openTime, a);
   TimeToStruct(TimeCurrent(), b);
   bool sameDay = (a.year == b.year && a.day_of_year == b.day_of_year);
   if(!sameDay)
   {
      Print("gotobi portfolio ", sym, ": closing stale position left open from a previous day at EA startup.");
      trade.SetExpertMagicNumber(magic);
      trade.PositionClose(sym);
   }
}

void ManageOpenPosition(string sym, ulong magic, datetime now)
{
   if(!PositionSelect(sym))
      return;
   if(PositionGetInteger(POSITION_MAGIC) != magic)
      return;
   if(now >= scheduledExitTime)
   {
      // Must re-set the trade object's magic to THIS symbol's before closing --
      // CTrade tags/validates the closing request against its own currently
      // configured magic, not the position's actual magic, and a single CTrade
      // instance here is shared across all three symbols (last set by whichever
      // symbol entered most recently in TryEnter()). Without this, closes for
      // any symbol other than the last one entered are silently rejected
      // (retcode 10006) forever -- found by instrumenting a debug run: a stuck
      // USDJPY position sat open for 4+ years before its own stop-loss finally
      // caught it, producing a ~78% drawdown that was a bug artifact, not a
      // real result.
      trade.SetExpertMagicNumber(magic);
      trade.PositionClose(sym);
   }
}

void TryEnter(int i)
{
   string sym = PairSymbols[i];
   double spreadPips = (SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / pipSize[i];
   if(spreadPips > InpMaxSpreadPips)
      return;

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double sl  = bid + InpStopLossPips * pipSize[i];
   double slDistance = sl - bid;

   double lots = CalculateLotSize(sym, i, slDistance);
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(lots < minLot)
   {
      Print("gotobi portfolio ", sym, ": skip, computed lot ", DoubleToString(lots, 2),
            " below broker minimum ", DoubleToString(minLot, 2));
      return;
   }

   double marginRequired;
   if(!OrderCalcMargin(ORDER_TYPE_SELL, sym, lots, bid, marginRequired))
      return;
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      Print("gotobi portfolio ", sym, ": skip, insufficient free margin");
      return;
   }

   trade.SetExpertMagicNumber((ulong)(MagicNumberBase + i));
   if(trade.Sell(lots, sym, bid, sl, 0.0))
      enteredToday[i] = true;
}

int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("gotobi portfolio: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("gotobi portfolio: refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }

   for(int i = 0; i < NPAIRS; i++)
   {
      SymbolSelect(PairSymbols[i], true);
      int d = (int)SymbolInfoInteger(PairSymbols[i], SYMBOL_DIGITS);
      double point = SymbolInfoDouble(PairSymbols[i], SYMBOL_POINT);
      pipSize[i] = (d == 3 || d == 5) ? point * 10 : point;
      enteredToday[i] = false;
      consecutiveLosses[i] = 0;
      monthlyHaltActive[i] = false;
      CloseStalePosition(PairSymbols[i], (ulong)(MagicNumberBase + i));
   }

   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);
   drawdownHaltActive = false;

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

   ulong magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   int i = -1;
   for(int k = 0; k < NPAIRS; k++)
   {
      if(magic == (ulong)(MagicNumberBase + k))
      {
         i = k;
         break;
      }
   }
   if(i < 0)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != PairSymbols[i])
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(profit < 0)
   {
      consecutiveLosses[i]++;
      if(consecutiveLosses[i] >= InpMaxConsecutiveLosses && !monthlyHaltActive[i])
      {
         monthlyHaltActive[i] = true;
         MqlDateTime s;
         TimeToStruct(TimeCurrent(), s);
         haltSetYear[i] = s.year;
         haltSetMonth[i] = s.mon;
         Print("gotobi portfolio ", PairSymbols[i], ": ", InpMaxConsecutiveLosses,
               " consecutive losses -- pausing until the first day of next month.");
      }
   }
   else
   {
      consecutiveLosses[i] = 0;
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
      for(int i = 0; i < NPAIRS; i++)
      {
         monthlyHaltActive[i] = false;
         consecutiveLosses[i] = 0;
      }
   }
   if(InpResetDrawdownStop)
   {
      drawdownHaltActive = false;
      balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   UpdateDrawdownHalt();
   UpdateDailyLossHalt();

   for(int i = 0; i < NPAIRS; i++)
      ManageOpenPosition(PairSymbols[i], (ulong)(MagicNumberBase + i), now);

   if(!isGotobiDay)
      return;
   if(dailyHaltActive || drawdownHaltActive)
      return;
   if(now < entryWindowStart || now > entryWindowEnd)
      return;

   for(int i = 0; i < NPAIRS; i++)
   {
      if(enteredToday[i] || monthlyHaltActive[i])
         continue;
      if(PositionSelect(PairSymbols[i]))
         continue;
      TryEnter(i);
   }
}
