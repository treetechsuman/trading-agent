//+------------------------------------------------------------------+
//| nfp_fade v2 - fade the initial spike around the US Non-Farm       |
//| Payrolls (NFP) release, day trading only. Same "measure a spike,   |
//| then fade it" structural pattern as wm_fix_reversal /              |
//| month_end_fix_reversal, every numeric parameter unchanged from v1  |
//| -- see spec.json / dates.md for the full reasoning behind each.    |
//|                                                                      |
//| SINGLE CHANGE FROM v1 (per v2/spec.json / v1/review.md): the        |
//| "first Friday of month, days 1-7" calendar-trigger APPROXIMATION    |
//| is replaced with a HARDCODED TABLE of actual historical BLS         |
//| Employment Situation (NFP) release dates, 2017-01 through 2025-12   |
//| (108 entries, one per calendar month). v1's day-of-month rule was   |
//| confirmed to fire zero wrong-day trades across all 59 in-sample     |
//| trades, but was separately confirmed to silently SKIP real events   |
//| that fall outside days 1-7 (Jan 2020's real release was 2020.01.10, |
//| not the computed 2020.01.03; Jan 2021's real release was            |
//| 2021.01.08, not the computed 2021.01.01, itself a market holiday).  |
//| This is purely a completeness fix -- nothing else changes.          |
//| NOTE: the table is NOT restricted to Fridays -- one entry           |
//| (2025.07.03, a Thursday) reflects BLS moving that specific release  |
//| one day earlier because the normally-computed Friday fell on July 4 |
//| (Independence Day); isNfpDay is now driven purely by table          |
//| membership (exact calendar date match), not day-of-week.            |
//|                                                                      |
//| Intended to run as one copy per pair (EURUSD.r, GBPUSD.r, USDJPY)  |
//| on its own chart -- each instance tracks its own position, risk     |
//| sizing and safety ledger independently (same convention as          |
//| gotobi/v1, month_end_fix_reversal/v1).                              |
//|                                                                      |
//| ENTRY TIMING -- unchanged from v1, the highest-risk part of this    |
//| EA to get right: 8:30am US Eastern must be converted to this        |
//| broker's server clock by combining TWO SEPARATE, independently-     |
//| changing DST calendars:                                             |
//|   1. US federal DST (EDT UTC-4 / EST UTC-5), switching on the       |
//|      2nd Sunday of March / 1st Sunday of November each year.        |
//|   2. Broker server DST (EEST UTC+3 / EET UTC+2, EU/Cyprus-based,    |
//|      same convention already used by gotobi/yen_fiscal_repatriation |
//|      elsewhere in this project), switching on the LAST Sunday of    |
//|      March / LAST Sunday of October each year.                      |
//| This EA computes both DST boundaries exactly, per calendar year,    |
//| from first principles (Nth-weekday-of-month arithmetic on           |
//| TimeCurrent(), never TimeGMT()/TimeLocal() -- those are NOT         |
//| simulated inside the Strategy Tester) rather than using any         |
//| hardcoded month-based table -- this part is REUSED UNCHANGED from   |
//| v1 (already spot-checked against real broker tick timestamps by     |
//| Backtester and confirmed correct to the minute). Only the           |
//| day-SELECTION mechanism (which calendar date is NFP day) changed.   |
//+------------------------------------------------------------------+
#property copyright "nfp_fade"
#property version   "2.00"

#include <Trade/Trade.mqh>
CTrade trade;

// -- NFP release time, fixed real-world calendar fact (not a sweep target) --
const int NfpReleaseHourET   = 8;   // 8:30am US Eastern, BLS standard scheduled release time
const int NfpReleaseMinuteET = 30;

// -- Measurement window & hold timing (server clock, entry computed per-year) --
input int    InpMeasureWindowMinutes = 10;   // T+0 (release) to T+10 measurement window
input int    InpHoldMinutes          = 60;   // backstop hold after measurement window closes (T+70 from release)

// -- Volatility-adaptive spike filter (event-count based, ~1yr of NFP history) --
input double InpMinSpikeSizePipsFloor    = 15.0;
input double InpMinSpikeVsAvgMultiplier  = 1.2;
input int    InpSpikeHistoryWindowEvents = 12;
input int    InpMinHistoryToAdapt        = 6;

// -- Trade parameters ------------------------------------------------------
input double InpSLMultiplier    = 1.0;  // stop = measured spike size * this
input double InpTPMultiplier    = 1.3;  // target = measured spike size * this
input double InpRiskPercent     = 0.5;  // % of account EQUITY risked if the stop is hit
input double InpMaxSpreadPips   = 4.0;  // skip entry if spread is wider than this at T+10
input int    InpEndOfDayHour    = 22;   // force-flat backstop, server hour
input int    MagicNumber        = 20260092;

// -- Safety rules (always on) -----------------------------------------------
input int    InpMaxConsecutiveLosses   = 6;   // pause after this many losses in a row
input double InpDailyLossStopPercent   = 5.0; // no more trades today after losing this % of balance today
input double InpMaxDrawdownStopPercent = 15.0;// hard stop after this % drawdown from the balance peak
input bool   InpResetLedgerNow         = false; // manually clear the consecutive-loss pause
input bool   InpResetDrawdownStop      = false; // manually clear the drawdown hard-stop

// -- Live safety -------------------------------------------------------------
input bool   InpAllowLiveAccount = false; // must be explicitly set true to run on a REAL account

double pipSize;

int      currentDay = -1;            // year*1000 + day_of_year, drives daily state resets
bool     isNfpDay = false;
datetime releaseTime = 0;            // T+0, computed server time of the 8:30am ET release
datetime windowEnd   = 0;            // T+10 -- also the entry evaluation/entry moment
datetime scheduledExitTime = 0;      // T+70 -- windowEnd + InpHoldMinutes
double   priceAtRelease = 0;
bool     haveReleasePrice = false;
bool     windowEvaluated = false;
bool     tradeTakenToday = false;

double   spikeHistory[];
int      spikeHistoryCount = 0;
int      spikeHistoryNext = 0;

int      consecutiveLosses  = 0;
bool     monthlyHaltActive  = false;
int      haltSetYear = 0, haltSetMonth = 0;

double   dailyStartBalance = 0;
bool     dailyHaltActive   = false;

double   balancePeak       = 0;
bool     drawdownHaltActive = false;

//+------------------------------------------------------------------+
//| Hardcoded historical BLS Employment Situation (NFP) release-date   |
//| table, 2017-01 through 2025-12 (108 entries, one per calendar      |
//| month). Sourced from BLS's published release-schedule pattern:     |
//| release = the Friday 3 calendar weeks after the Saturday closing   |
//| the reference week (the week containing the 12th of the reported   |
//| month) -- BLS's own documented scheduling rule, cross-validated    |
//| against 10+ independently-known real release dates before being   |
//| applied here (see EA Coder's handoff notes / ea-coder/lessons.md   |
//| for the full derivation and confidence discussion). Two            |
//| confirmed manual exceptions applied: 2020.01.10 (not the           |
//| rule's 2020.01.03) and 2021.01.08 (not the rule's 2021.01.01,      |
//| itself New Year's Day) -- both already flagged in v1/review.md.    |
//| A third, same-pattern January exception (2025.01.10, not the       |
//| rule's 2025.01.03) and one Independence-Day exception               |
//| (2025.07.03, a Thursday, not the rule's 2025.07.04) are also        |
//| applied. See dates.md / EA Coder's handoff for confidence caveats. |
//+------------------------------------------------------------------+
struct NfpDate { int year; int mon; int day; };

const NfpDate NfpReleaseTable[] =
{
   {2017,  1,  6}, {2017,  2,  3}, {2017,  3, 10}, {2017,  4,  7},
   {2017,  5,  5}, {2017,  6,  2}, {2017,  7,  7}, {2017,  8,  4},
   {2017,  9,  1}, {2017, 10,  6}, {2017, 11,  3}, {2017, 12,  8},
   {2018,  1,  5}, {2018,  2,  2}, {2018,  3,  9}, {2018,  4,  6},
   {2018,  5,  4}, {2018,  6,  1}, {2018,  7,  6}, {2018,  8,  3},
   {2018,  9,  7}, {2018, 10,  5}, {2018, 11,  2}, {2018, 12,  7},
   {2019,  1,  4}, {2019,  2,  1}, {2019,  3,  8}, {2019,  4,  5},
   {2019,  5,  3}, {2019,  6,  7}, {2019,  7,  5}, {2019,  8,  2},
   {2019,  9,  6}, {2019, 10,  4}, {2019, 11,  1}, {2019, 12,  6},
   {2020,  1, 10}, {2020,  2,  7}, {2020,  3,  6}, {2020,  4,  3},
   {2020,  5,  8}, {2020,  6,  5}, {2020,  7,  3}, {2020,  8,  7},
   {2020,  9,  4}, {2020, 10,  2}, {2020, 11,  6}, {2020, 12,  4},
   {2021,  1,  8}, {2021,  2,  5}, {2021,  3,  5}, {2021,  4,  2},
   {2021,  5,  7}, {2021,  6,  4}, {2021,  7,  2}, {2021,  8,  6},
   {2021,  9,  3}, {2021, 10,  8}, {2021, 11,  5}, {2021, 12,  3},
   {2022,  1,  7}, {2022,  2,  4}, {2022,  3,  4}, {2022,  4,  1},
   {2022,  5,  6}, {2022,  6,  3}, {2022,  7,  8}, {2022,  8,  5},
   {2022,  9,  2}, {2022, 10,  7}, {2022, 11,  4}, {2022, 12,  2},
   {2023,  1,  6}, {2023,  2,  3}, {2023,  3, 10}, {2023,  4,  7},
   {2023,  5,  5}, {2023,  6,  2}, {2023,  7,  7}, {2023,  8,  4},
   {2023,  9,  1}, {2023, 10,  6}, {2023, 11,  3}, {2023, 12,  8},
   {2024,  1,  5}, {2024,  2,  2}, {2024,  3,  8}, {2024,  4,  5},
   {2024,  5,  3}, {2024,  6,  7}, {2024,  7,  5}, {2024,  8,  2},
   {2024,  9,  6}, {2024, 10,  4}, {2024, 11,  1}, {2024, 12,  6},
   {2025,  1, 10}, {2025,  2,  7}, {2025,  3,  7}, {2025,  4,  4},
   {2025,  5,  2}, {2025,  6,  6}, {2025,  7,  3}, {2025,  8,  1},
   {2025,  9,  5}, {2025, 10,  3}, {2025, 11,  7}, {2025, 12,  5}
};

// Exact calendar-date lookup against the hardcoded BLS table above --
// this is now the SOLE source of truth for "is today NFP day", replacing
// v1's "first Friday, days 1-7" computed approximation. Table membership
// only -- deliberately NOT gated on day_of_week, since one table entry
// (2025.07.03) is a Thursday (see table header comment).
bool IsNfpReleaseDate(int year, int mon, int day)
{
   int n = ArraySize(NfpReleaseTable);
   for(int i = 0; i < n; i++)
   {
      if(NfpReleaseTable[i].year == year && NfpReleaseTable[i].mon == mon && NfpReleaseTable[i].day == day)
         return true;
   }
   return false; // month/date genuinely missing from the table -- per spec, skip silently (no fallback to the old rule)
}

//+------------------------------------------------------------------+
//| Calendar helpers (unchanged from v1 -- still needed for the DST    |
//| conversion below, which is independent of the NFP day-selection    |
//| change above)                                                       |
//+------------------------------------------------------------------+
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

datetime DateOnly(int year, int mon, int day)
{
   MqlDateTime d;
   d.year = year; d.mon = mon; d.day = day;
   d.hour = 0; d.min = 0; d.sec = 0;
   return StructToTime(d);
}

// 0=Sunday .. 6=Saturday, matching MqlDateTime.day_of_week
int WeekdayOf(int year, int mon, int day)
{
   datetime t = DateOnly(year, mon, day);
   MqlDateTime r;
   TimeToStruct(t, r);
   return r.day_of_week;
}

// First day-of-month (1-7) whose weekday matches targetDow
int FirstWeekdayDay(int year, int mon, int targetDow)
{
   for(int day = 1; day <= 7; day++)
      if(WeekdayOf(year, mon, day) == targetDow)
         return day;
   return 1; // unreachable -- every weekday occurs exactly once in days 1-7
}

int NthSundayDay(int year, int mon, int n)
{
   return FirstWeekdayDay(year, mon, 0) + (n - 1) * 7;
}

int LastSundayDay(int year, int mon)
{
   int last = DaysInMonth(mon, year);
   for(int day = last; day > last - 7; day--)
      if(WeekdayOf(year, mon, day) == 0)
         return day;
   return last; // unreachable -- every weekday occurs exactly once in the last 7 days
}

//+------------------------------------------------------------------+
//| DST-aware 8:30am US Eastern -> broker server time conversion.     |
//| Unchanged from v1 -- computed per calendar year from first         |
//| principles (two independent DST rules), NOT a hardcoded            |
//| month-based table -- see file header and dates.md for why that     |
//| shortcut is unsafe specifically for NFP. This logic does NOT       |
//| depend on how the trigger date was selected, only on what date it  |
//| is, so it is reused verbatim against the new table's dates.        |
//+------------------------------------------------------------------+
void ComputeNfpServerReleaseTime(int year, int mon, int day, int &outHour, int &outMinute)
{
   datetime triggerDate = DateOnly(year, mon, day);

   // US side: EDT (UTC-4) from 2nd Sunday of March through 1st Sunday of
   // November (that year); EST (UTC-5) otherwise.
   int secondSundayMarchDay = NthSundayDay(year, 3, 2);
   int firstSundayNovDay    = NthSundayDay(year, 11, 1);
   datetime usDstStart = DateOnly(year, 3, secondSundayMarchDay);
   datetime usDstEnd   = DateOnly(year, 11, firstSundayNovDay);
   bool usSummer = (triggerDate >= usDstStart && triggerDate < usDstEnd);
   int usOffsetHours = usSummer ? -4 : -5; // ET offset from UTC

   // Broker side: EEST (UTC+3) from last Sunday of March through last
   // Sunday of October (that year); EET (UTC+2) otherwise.
   int lastSundayMarchDay = LastSundayDay(year, 3);
   int lastSundayOctDay   = LastSundayDay(year, 10);
   datetime brokerDstStart = DateOnly(year, 3, lastSundayMarchDay);
   datetime brokerDstEnd   = DateOnly(year, 10, lastSundayOctDay);
   bool brokerSummer = (triggerDate >= brokerDstStart && triggerDate < brokerDstEnd);
   int brokerOffsetHours = brokerSummer ? 3 : 2; // server offset from UTC

   // server = ET - usOffsetHours (-> UTC) + brokerOffsetHours (-> server).
   // Both offsets are whole hours, so the release minute (:30) is unaffected.
   outHour   = NfpReleaseHourET + (brokerOffsetHours - usOffsetHours);
   outMinute = NfpReleaseMinuteET;
}

//+------------------------------------------------------------------+
//| Spike history (rolling average of this pair's own NFP-window      |
//| moves, event-count based)                                          |
//+------------------------------------------------------------------+
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
   spikeHistoryNext = (spikeHistoryNext + 1) % InpSpikeHistoryWindowEvents;
   if(spikeHistoryCount < InpSpikeHistoryWindowEvents)
      spikeHistoryCount++;
}

//+------------------------------------------------------------------+
//| Day state                                                          |
//+------------------------------------------------------------------+
void ResetDayState(datetime now)
{
   MqlDateTime s;
   TimeToStruct(now, s);

   // Hardcoded historical BLS release-date table lookup (v2 change --
   // see NfpReleaseTable / IsNfpReleaseDate above). Replaces v1's
   // "first Friday of the month, days 1-7" computed approximation.
   isNfpDay = IsNfpReleaseDate(s.year, s.mon, s.day);

   int relHour, relMinute;
   ComputeNfpServerReleaseTime(s.year, s.mon, s.day, relHour, relMinute);

   MqlDateTime r = s;
   r.hour = relHour;
   r.min  = relMinute;
   r.sec  = 0;
   releaseTime       = StructToTime(r);
   windowEnd         = releaseTime + InpMeasureWindowMinutes * 60;
   scheduledExitTime = windowEnd + InpHoldMinutes * 60;

   haveReleasePrice = false;
   windowEvaluated  = false;
   tradeTakenToday  = false;
   priceAtRelease   = 0;

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
      Print("nfp_fade ", _Symbol, ": new month -- consecutive-loss pause lifted.");
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
         Alert("nfp_fade ", _Symbol, ": drawdown stop hit (", DoubleToString(InpMaxDrawdownStopPercent, 1),
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
      Print("nfp_fade ", _Symbol, ": closing stale position left open from a previous day at EA startup.");
      trade.SetExpertMagicNumber(MagicNumber);
      trade.PositionClose(_Symbol);
   }
}

//+------------------------------------------------------------------+
//| Position sizing -- round down only, never up past the spec's       |
//| intended risk; skip the trade entirely below broker minimum lot.   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPriceUnit = tickValue / tickSize;
   double lots = riskAmount / (slDistance * valuePerPriceUnit);

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   lots = MathMin(maxLot, lots);
   return lots; // deliberately NOT floored up to the broker minimum -- caller checks
}

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("nfp_fade ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("nfp_fade ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }

   ArrayResize(spikeHistory, InpSpikeHistoryWindowEvents);
   spikeHistoryCount = 0;
   spikeHistoryNext  = 0;

   consecutiveLosses  = 0;
   monthlyHaltActive  = false;
   drawdownHaltActive = false;
   balancePeak = AccountInfoDouble(ACCOUNT_BALANCE);

   CloseStalePosition();

   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   currentDay = s.year * 1000 + s.day_of_year;
   ResetDayState(TimeCurrent());

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
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
         Print("nfp_fade ", _Symbol, ": ", InpMaxConsecutiveLosses,
               " consecutive losses -- pausing until the first day of next month.");
      }
   }
   else
   {
      consecutiveLosses = 0;
   }
}

//+------------------------------------------------------------------+
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

   // End-of-day flat backstop -- same-session day trade only, never overnight.
   if(s.hour >= InpEndOfDayHour && PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      trade.SetExpertMagicNumber(MagicNumber);
      trade.PositionClose(_Symbol);
      return;
   }

   // Scheduled T+70 exit backstop (SL/TP themselves are evaluated by the
   // broker/tester engine directly, not polled here).
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      if(now >= scheduledExitTime)
      {
         trade.SetExpertMagicNumber(MagicNumber);
         trade.PositionClose(_Symbol);
      }
      return;
   }

   if(!isNfpDay)
      return;

   // At T+10 (measurement window close): feed the spike-history baseline
   // every NFP day regardless of whether a trade is ultimately taken, so
   // the rolling average reflects genuine event-to-event volatility (same
   // convention as month_end_fix_reversal/wm_fix_reversal).
   if(!windowEvaluated && haveReleasePrice && now >= windowEnd)
   {
      windowEvaluated = true;
      double priceNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double spike = priceNow - priceAtRelease;
      double spikePips = MathAbs(spike) / pipSize;
      PushSpikeHistory(spikePips);

      if(tradeTakenToday)
         return;
      if(monthlyHaltActive || dailyHaltActive || drawdownHaltActive)
         return;
      if(spike == 0)
         return; // no directional move to fade

      double threshold;
      if(spikeHistoryCount < InpMinHistoryToAdapt)
         threshold = InpMinSpikeSizePipsFloor;
      else
         threshold = MathMax(InpMinSpikeSizePipsFloor, InpMinSpikeVsAvgMultiplier * AverageSpikeHistory());

      if(spikePips < threshold)
         return;

      double spreadPips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pipSize;
      if(spreadPips > InpMaxSpreadPips)
         return;

      if(PositionSelect(_Symbol)) // never more than one position per pair per event
         return;

      double slDistance = spikePips * pipSize * InpSLMultiplier;
      double tpDistance  = spikePips * pipSize * InpTPMultiplier;
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

      trade.SetExpertMagicNumber(MagicNumber);

      if(spike > 0) // price rose into the window -- fade with a sell
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = bid + slDistance;
         double tp = bid - tpDistance;
         double lots = CalculateLotSize(sl - bid);
         if(lots < minLot)
         {
            Print("nfp_fade ", _Symbol, ": skip, computed lot ", DoubleToString(lots, 2),
                  " below broker minimum ", DoubleToString(minLot, 2));
            return;
         }
         double marginRequired;
         if(!OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, lots, bid, marginRequired))
            return;
         if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         {
            Print("nfp_fade ", _Symbol, ": skip, insufficient free margin");
            return;
         }
         if(trade.Sell(lots, _Symbol, bid, sl, tp))
            tradeTakenToday = true;
      }
      else // price fell into the window -- fade with a buy
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = ask - slDistance;
         double tp = ask + tpDistance;
         double lots = CalculateLotSize(ask - sl);
         if(lots < minLot)
         {
            Print("nfp_fade ", _Symbol, ": skip, computed lot ", DoubleToString(lots, 2),
                  " below broker minimum ", DoubleToString(minLot, 2));
            return;
         }
         double marginRequired;
         if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, ask, marginRequired))
            return;
         if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         {
            Print("nfp_fade ", _Symbol, ": skip, insufficient free margin");
            return;
         }
         if(trade.Buy(lots, _Symbol, ask, sl, tp))
            tradeTakenToday = true;
      }
      return;
   }

   if(tradeTakenToday)
      return;

   // Capture the T+0 (release-moment) reference price once, at the first
   // tick inside [releaseTime, windowEnd).
   if(!haveReleasePrice && now >= releaseTime && now < windowEnd)
   {
      priceAtRelease = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      haveReleasePrice = true;
   }
}
