//+------------------------------------------------------------------+
//| server_clock_check v1 - research probe, NOT a strategy.            |
//| Never trades. Run in the Strategy Tester with Model=4 (real ticks) |
//| and it aggregates every tick into per-minute rows (server clock):  |
//| tick count, min/max spread (points), bid high/low, plus a flag on  |
//| the first tick after any gap > 1h (weekend open). Output goes to   |
//| Common\Files\server_clock_<InpTag>.csv for offline analysis by     |
//| analyze.py in this folder.                                          |
//+------------------------------------------------------------------+
#property copyright "server_clock_check"
#property version   "1.00"

input string InpTag = "probe";

int      g_fh = INVALID_HANDLE;
datetime g_curMin = 0;
datetime g_lastTick = 0;
int      g_ticks = 0;
long     g_spMin = 0, g_spMax = 0;
double   g_hi = 0, g_lo = 0;
string   g_firstAfterGap = "";

void Flush()
{
   if(g_curMin == 0 || g_fh == INVALID_HANDLE)
      return;
   FileWrite(g_fh, TimeToString(g_curMin, TIME_DATE | TIME_MINUTES), g_ticks,
             g_spMin, g_spMax, DoubleToString(g_hi, _Digits), DoubleToString(g_lo, _Digits),
             g_firstAfterGap);
}

int OnInit()
{
   g_fh = FileOpen("server_clock_" + InpTag + ".csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(g_fh == INVALID_HANDLE)
      return INIT_FAILED;
   FileWrite(g_fh, "minute", "ticks", "spread_min", "spread_max", "bid_high", "bid_low", "gap_open");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return;
   datetime m = t.time - (t.time % 60);
   long sp = (long)MathRound((t.ask - t.bid) / _Point);
   if(m != g_curMin)
   {
      Flush();
      g_curMin = m;
      g_ticks = 0;
      g_spMin = sp; g_spMax = sp;
      g_hi = t.bid; g_lo = t.bid;
      g_firstAfterGap = "";
   }
   if(g_lastTick != 0 && t.time - g_lastTick > 3600 && g_firstAfterGap == "")
      g_firstAfterGap = TimeToString(t.time, TIME_DATE | TIME_SECONDS);
   g_lastTick = t.time;
   g_ticks++;
   if(sp < g_spMin) g_spMin = sp;
   if(sp > g_spMax) g_spMax = sp;
   if(t.bid > g_hi) g_hi = t.bid;
   if(t.bid < g_lo) g_lo = t.bid;
}

void OnDeinit(const int reason)
{
   Flush();
   if(g_fh != INVALID_HANDLE)
      FileClose(g_fh);
}
