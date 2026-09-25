//+------------------------------------------------------------------+
//| nfp_fade v1 - fade the initial spike around the US Non-Farm       |
//| Payrolls (NFP) release, first Friday of every month, day trading   |
//| only. Same "measure a spike, then fade it" structural pattern as   |
//| wm_fix_reversal / month_end_fix_reversal, but every numeric        |
//| parameter (measurement window, adaptive-threshold floor/multiplier,|
//| SL/TP multiples, hold time, risk%) is independently re-derived for |
//| NFP's distinct character -- see spec.json / dates.md for the full  |
//| reasoning behind each value.                                       |
//|                                                                      |
//| Intended to run as one copy per pair (EURUSD.r, GBPUSD.r, USDJPY)  |
//| on its own chart -- each instance tracks its own position, risk     |
//| sizing and safety ledger independently (same convention as          |
//| gotobi/v1, month_end_fix_reversal/v1).                              |
//|                                                                      |
//| ENTRY TIMING -- the highest-risk part of this EA to get wrong:      |
//| 8:30am US Eastern must be converted to this broker's server clock   |
//| by combining TWO SEPARATE, independently-changing DST calendars:    |
//|   1. US federal DST (EDT UTC-4 / EST UTC-5), switching on the       |
//|      2nd Sunday of March / 1st Sunday of November each year.        |
//|   2. Broker server DST (EEST UTC+3 / EET UTC+2, EU/Cyprus-based,    |
//|      same convention already used by gotobi/yen_fiscal_repatriation |
//|      elsewhere in this project), switching on the LAST Sunday of    |
//|      March / LAST Sunday of October each year.                      |
//| Unlike gotobi's flat "Mar-Oct summer / Nov-Feb winter" whole-month   |
//| simplification (fine for gotobi's trading days, spread across the   |
//| whole month), NFP's trigger day is ALWAYS in days 1-7 of the month  |
//| -- always before the real EU March/October cutover (which falls    |
//| around day 25-31) and, in November, sometimes still before the US   |
//| cutover too (the "still EDT" case, computed per-year below, is the  |
//| MAJORITY outcome across this project's 2017-2025 test window, not a |
//| rare corner case -- see dates.md's 9-year hand cross-check). This   |
//| EA computes both DST boundaries exactly, per calendar year, from    |
//| first principles (Nth-weekday-of-month arithmetic on TimeCurrent(), |
//| never TimeGMT()/TimeLocal() -- those are NOT simulated inside the   |
//| Strategy Tester) rather than using any hardcoded month-based table. |
//+------------------------------------------------------------------+
#property copyright "nfp_fade"
#property version   "1.00"

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
//| Calendar helpers                                                   |
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
//| Computed per calendar year from first principles (two independent |
//| DST rules), NOT a hardcoded month-based table -- see file header   |
//| and dates.md for why that shortcut is unsafe specifically for NFP. |
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

   // First Friday of the month, computed by calendar rule (spec.json's
   // "code_friendly_definition"): the first Friday is always within days 1-7.
   isNfpDay = (s.day_of_week == 5 && s.day <= 7);

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
