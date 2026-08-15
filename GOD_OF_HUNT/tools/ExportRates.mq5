//+------------------------------------------------------------------+
//|                                          ExportRates.mq5   v1.00  |
//|                                                                  |
//| اسکریپت استخراج تاریخچه برای بک تست GOD_OF_HUNT.                  |
//|                                                                  |
//| این فایل در MQL5/Scripts گذاشته می‌شود، نه Indicators. با اجرا روی|
//| هر چارتی، برای همه نماد و تایم فریم های خواسته شده یک CSV در       |
//| MQL5/Files می‌سازد:                                               |
//|                                                                  |
//|     GOH_<نماد>_<تایم فریم>.csv                                    |
//|                                                                  |
//| قالب هر خط:  time,open,high,low,close                             |
//| زمان به وقت سرور بروکر نوشته می‌شود — همان مبنایی که کندل ها با آن|
//| ساخته شده اند، تا بک تست دقیقا همان کندل های چارت شما را ببیند.    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

// خالی یعنی فقط نماد همین چارت
input string ExportSymbols    = "XAUUSD,BRNUSD,SPXUSD,EURUSD";  // نمادها با کاما (خالی = نماد چارت)
input string ExportTimeframes = "H8,H4,H3,H2,H1,M30,M20,M15";   // تایم فریم ها با کاما
input int    ExportBars       = 20000;   // چند کندل آخر از هر ترکیب

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StrToTF(string txt)
{
   string u = txt;
   StringTrimLeft(u);
   StringTrimRight(u);
   StringToUpper(u);

   if(u == "M1")  return PERIOD_M1;
   if(u == "M2")  return PERIOD_M2;
   if(u == "M3")  return PERIOD_M3;
   if(u == "M4")  return PERIOD_M4;
   if(u == "M5")  return PERIOD_M5;
   if(u == "M6")  return PERIOD_M6;
   if(u == "M10") return PERIOD_M10;
   if(u == "M12") return PERIOD_M12;
   if(u == "M15") return PERIOD_M15;
   if(u == "M20") return PERIOD_M20;
   if(u == "M30") return PERIOD_M30;
   if(u == "H1")  return PERIOD_H1;
   if(u == "H2")  return PERIOD_H2;
   if(u == "H3")  return PERIOD_H3;
   if(u == "H4")  return PERIOD_H4;
   if(u == "H6")  return PERIOD_H6;
   if(u == "H8")  return PERIOD_H8;
   if(u == "H12") return PERIOD_H12;
   if(u == "D1")  return PERIOD_D1;

   return (ENUM_TIMEFRAMES)0;
}

string TFName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";    case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";    case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";    case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";   case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";   case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";   case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";    case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";    case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";    case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
   }
   return "?";
}

//+------------------------------------------------------------------+
// یک ترکیب نماد و تایم فریم. برگشتی تعداد کندل نوشته شده، یا -1 برای خطا.
int ExportOne(string sym, ENUM_TIMEFRAMES tf)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(digits <= 0) digits = 5;

   int available = Bars(sym, tf);
   if(available <= 0)
   {
      // متاتریدر تاریخچه را در پس زمینه دانلود می‌کند؛ یک بار درخواست
      // می‌دهیم و اگر نرسید کاربر دوباره اجرا کند.
      MqlRates probe[];
      CopyRates(sym, tf, 0, 10, probe);
      Print("no history yet: ", sym, " ", TFName(tf), "  (run again in a moment)");
      return -1;
   }

   int need = ExportBars;
   if(need > available) need = available;

   MqlRates rates[];
   ArraySetAsSeries(rates, false);          // ایندکس 0 = قدیمی ترین
   int n = CopyRates(sym, tf, 0, need, rates);
   if(n <= 0)
   {
      Print("CopyRates failed: ", sym, " ", TFName(tf), "  error ", GetLastError());
      return -1;
   }

   string fname = "GOH_" + sym + "_" + TFName(tf) + ".csv";

   int h = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
   {
      Print("FileOpen failed: ", fname, "  error ", GetLastError());
      return -1;
   }

   FileWrite(h, "time", "open", "high", "low", "close");

   for(int i = 0; i < n; i++)
   {
      FileWrite(h,
                TimeToString(rates[i].time, TIME_DATE | TIME_MINUTES),
                DoubleToString(rates[i].open,  digits),
                DoubleToString(rates[i].high,  digits),
                DoubleToString(rates[i].low,   digits),
                DoubleToString(rates[i].close, digits));
   }

   FileClose(h);
   Print("exported ", n, " bars -> MQL5/Files/", fname);
   return n;
}

//+------------------------------------------------------------------+
void OnStart()
{
   string symList = ExportSymbols;
   StringTrimLeft(symList);
   StringTrimRight(symList);
   if(StringLen(symList) == 0) symList = _Symbol;

   string syms[];
   int nSym = StringSplit(symList, ',', syms);

   string tfs[];
   int nTF = StringSplit(ExportTimeframes, ',', tfs);

   int files = 0, failed = 0;

   for(int s = 0; s < nSym; s++)
   {
      string sym = syms[s];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;

      // نماد باید در Market Watch باشد وگرنه داده اش در دسترس نیست
      if(!SymbolSelect(sym, true))
      {
         Print("unknown symbol, skipped: ", sym);
         failed++;
         continue;
      }

      for(int t = 0; t < nTF; t++)
      {
         ENUM_TIMEFRAMES tf = StrToTF(tfs[t]);
         if(tf == 0)
         {
            Print("bad timeframe, skipped: ", tfs[t]);
            continue;
         }

         if(ExportOne(sym, tf) > 0) files++;
         else                       failed++;
      }
   }

   Print("=== ExportRates done: ", files, " file(s) written, ", failed, " skipped.");
   Print("=== folder: MQL5/Files  (File > Open Data Folder)");
}
//+------------------------------------------------------------------+
