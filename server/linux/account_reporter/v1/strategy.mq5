//+------------------------------------------------------------------+
//| account_reporter v1 - READ-ONLY status writer for /trading-report |
//|                                                                    |
//| Never trades: no CTrade, no OrderSend. Every 60 s (and on every    |
//| trade event) it writes MQL5/Files/EAFactory_status.json with the   |
//| account state, open positions and the account's deal history, so  |
//| server/linux/trading_report.py can report balance, trades and P&L |
//| without Windows Python. Attach to any one chart (chart04 on the   |
//| Linux server). Works with Algo Trading ON or OFF.                 |
//+------------------------------------------------------------------+
#property copyright "EAFactory"
#property version   "1.00"

input int InpWriteSeconds = 60;   // how often to rewrite the status file
input int InpMaxDeals     = 2000; // newest N deals kept in the file

const string FILE_TMP = "EAFactory_status.tmp";
const string FILE_OUT = "EAFactory_status.json";

string Esc(string s)
{
   StringReplace(s, "\\", "/");
   StringReplace(s, "\"", "'");
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   return s;
}

string Q(string s) { return "\"" + Esc(s) + "\""; }
string D(double v, int digits = 2) { return DoubleToString(v, digits); }
string B(bool v) { return v ? "true" : "false"; }

string DealTypeName(long t)
{
   switch((int)t)
   {
      case DEAL_TYPE_BUY:     return "buy";
      case DEAL_TYPE_SELL:    return "sell";
      case DEAL_TYPE_BALANCE: return "balance";
      case DEAL_TYPE_CREDIT:  return "credit";
      case DEAL_TYPE_COMMISSION: return "commission";
      default: return "other_" + IntegerToString(t);
   }
}

string DealEntryName(long e)
{
   switch((int)e)
   {
      case DEAL_ENTRY_IN:    return "in";
      case DEAL_ENTRY_OUT:   return "out";
      case DEAL_ENTRY_INOUT: return "inout";
      case DEAL_ENTRY_OUT_BY: return "out_by";
      default: return "other";
   }
}

void WriteStatus()
{
   int h = FileOpen(FILE_TMP, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("account_reporter: cannot open ", FILE_TMP, " error ", GetLastError());
      return;
   }

   string s = "{\n";
   s += "\"reporter\":\"account_reporter v1\",\n";
   s += "\"written_server_time\":" + IntegerToString((long)TimeCurrent()) + ",\n";
   s += "\"written_gmt\":" + IntegerToString((long)TimeGMT()) + ",\n";
   s += "\"server_gmt_offset_sec\":" + IntegerToString((long)(TimeTradeServer() - TimeGMT())) + ",\n";
   s += "\"terminal_build\":" + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)) + ",\n";
   s += "\"terminal_connected\":" + B(TerminalInfoInteger(TERMINAL_CONNECTED) != 0) + ",\n";
   s += "\"algo_trading_button\":" + B(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) + ",\n";
   s += "\"ping_ms\":" + D(TerminalInfoInteger(TERMINAL_PING_LAST) / 1000.0, 1) + ",\n";
   s += "\"account\":{";
   s += "\"login\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   s += ",\"server\":" + Q(AccountInfoString(ACCOUNT_SERVER));
   s += ",\"currency\":" + Q(AccountInfoString(ACCOUNT_CURRENCY));
   s += ",\"leverage\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE));
   s += ",\"balance\":" + D(AccountInfoDouble(ACCOUNT_BALANCE));
   s += ",\"equity\":" + D(AccountInfoDouble(ACCOUNT_EQUITY));
   s += ",\"margin\":" + D(AccountInfoDouble(ACCOUNT_MARGIN));
   s += ",\"free_margin\":" + D(AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   s += ",\"margin_level\":" + D(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL));
   s += ",\"trade_allowed\":" + B(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0);
   s += ",\"trade_expert\":" + B(AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0);
   s += "},\n";
   FileWriteString(h, s);

   // open positions
   FileWriteString(h, "\"positions\":[");
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      string p = (i > 0 ? ",\n" : "\n") + "{";
      p += "\"ticket\":" + IntegerToString((long)ticket);
      p += ",\"symbol\":" + Q(PositionGetString(POSITION_SYMBOL));
      p += ",\"type\":" + Q(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "buy" : "sell");
      p += ",\"volume\":" + D(PositionGetDouble(POSITION_VOLUME));
      p += ",\"open_price\":" + D(PositionGetDouble(POSITION_PRICE_OPEN), 5);
      p += ",\"sl\":" + D(PositionGetDouble(POSITION_SL), 5);
      p += ",\"tp\":" + D(PositionGetDouble(POSITION_TP), 5);
      p += ",\"profit\":" + D(PositionGetDouble(POSITION_PROFIT));
      p += ",\"swap\":" + D(PositionGetDouble(POSITION_SWAP));
      p += ",\"magic\":" + IntegerToString(PositionGetInteger(POSITION_MAGIC));
      p += ",\"time\":" + IntegerToString(PositionGetInteger(POSITION_TIME));
      p += "}";
      FileWriteString(h, p);
   }
   FileWriteString(h, "],\n");

   // deal history (whole account, newest InpMaxDeals)
   FileWriteString(h, "\"deals\":[");
   bool ok = HistorySelect(0, TimeCurrent() + 86400);
   int n = ok ? HistoryDealsTotal() : 0;
   int start = MathMax(0, n - InpMaxDeals);
   bool first = true;
   for(int i = start; i < n; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      string d = (first ? "\n" : ",\n") + "{";
      first = false;
      d += "\"ticket\":" + IntegerToString((long)t);
      d += ",\"time\":" + IntegerToString(HistoryDealGetInteger(t, DEAL_TIME));
      d += ",\"symbol\":" + Q(HistoryDealGetString(t, DEAL_SYMBOL));
      d += ",\"type\":" + Q(DealTypeName(HistoryDealGetInteger(t, DEAL_TYPE)));
      d += ",\"entry\":" + Q(DealEntryName(HistoryDealGetInteger(t, DEAL_ENTRY)));
      d += ",\"volume\":" + D(HistoryDealGetDouble(t, DEAL_VOLUME));
      d += ",\"price\":" + D(HistoryDealGetDouble(t, DEAL_PRICE), 5);
      d += ",\"profit\":" + D(HistoryDealGetDouble(t, DEAL_PROFIT));
      d += ",\"commission\":" + D(HistoryDealGetDouble(t, DEAL_COMMISSION));
      d += ",\"swap\":" + D(HistoryDealGetDouble(t, DEAL_SWAP));
      d += ",\"magic\":" + IntegerToString(HistoryDealGetInteger(t, DEAL_MAGIC));
      d += ",\"position\":" + IntegerToString(HistoryDealGetInteger(t, DEAL_POSITION_ID));
      d += ",\"comment\":" + Q(HistoryDealGetString(t, DEAL_COMMENT));
      d += "}";
      FileWriteString(h, d);
   }
   FileWriteString(h, "],\n\"history_ok\":" + B(ok) + "\n}\n");
   FileClose(h);

   if(!FileMove(FILE_TMP, 0, FILE_OUT, FILE_REWRITE))
      Print("account_reporter: cannot rename status file, error ", GetLastError());

   Comment("account_reporter v1 | read-only, never trades\n",
           "Status file written ", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), " (server time)\n",
           "Balance ", D(AccountInfoDouble(ACCOUNT_BALANCE)), "  Equity ", D(AccountInfoDouble(ACCOUNT_EQUITY)),
           "  Positions ", IntegerToString(PositionsTotal()));
}

int OnInit()
{
   EventSetTimer(MathMax(10, InpWriteSeconds));
   WriteStatus();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
}

void OnTimer() { WriteStatus(); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      WriteStatus();
}

void OnTick() {}
