//+------------------------------------------------------------------+
//|                                            ABHunterScanner.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| اسکنر چند نمادی ABHunter.                                         |
//| روی یک چارت اختصاصی نصب می‌شود و همه نمادهای انتخابی را در فهرست   |
//| تایم فریم های دلخواه اسکن می‌کند، جدول الگوهای فعال را نشان می‌دهد |
//| و برای هر AB جدیدی که قطعی شود نوتیفیکیشن موبایل می‌فرستد.         |
//|                                                                  |
//| اسکنر الگو را «رسم» نمی‌کند؛ فقط می‌گوید کجا نگاه کنید. برای دیدن  |
//| خط AB و نقاط A و C و ناحیه اصلاح، چارت همان نماد و تایم فریم را با |
//| اندیکاتور ABHunter.mq5 باز کنید.                                  |
//|                                                                  |
//| قواعد تشخیص از ABHunterCore.mqh می‌آید — همان فایلی که اندیکاتور   |
//| چارت هم استفاده می‌کند، تا دو نسخه از منطق وجود نداشته باشد.       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.21"
#property indicator_chart_window

#include "ABHunterCore.mqh"

//---- کدام وضعیت ها به حساب بیایند
enum PanelFilterMode
{
   SHOW_ALL,        // همه
   SHOW_FROM_COK,   // فقط از «اصلاح معتبر» به بعد
   SHOW_FROM_HUNT   // فقط آنهایی که B شکسته شده
};

//---- دامنه اسکن
input string ScanSymbols       = "XAUUSD,DJIUSD,BRNUSD,SPXUSD,NDXUSD,NZDJPY,USDCAD,USDCHF,USDJPY,GBPCHF,GBPJPY,GBPNZD,GBPUSD,EURJPY,EURNZD,EURUSD,GBPAUD,GBPCAD,CHFJPY,EURAUD,EURCAD,EURCHF,EURGBP,AUDCAD,AUDJPY,AUDUSD,CADCHF,CADJPY"; // نمادها با کاما؛ خالی یعنی همه Market Watch
input string ScanTimeframes    = "H4,H3,H2,H1,M30,M20,M15"; // تایم فریم ها با کاما
input bool   SyncTFWithChart   = false;// به جای فهرست بالا، سه تایم فریم دکمه های چارت خوانده شود
input int    RefreshSeconds    = 60;   // فاصله هر اسکن (ثانیه)

//---- نوتیفیکیشن
input bool   EnablePush        = true; // نوتیفیکیشن موبایل برای هر AB جدید قطعی شده
input PanelFilterMode NotifyFilter = SHOW_FROM_COK; // برای کدام وضعیت ها اطلاع بدهد

//---- جدول
input PanelFilterMode PanelFilter = SHOW_ALL; // کدام وضعیت ها در جدول بیایند
input int    PanelX            = 150;  // فاصله جدول از چپ
input int    PanelY            = 20;   // فاصله جدول از بالا
input int    PanelFontSize     = 9;
input color  PanelTitleColor   = clrWhite;
input color  PanelTextColor    = clrGainsboro;
input color  PanelBullColor    = clrDeepSkyBlue;
input color  PanelBearColor    = clrOrange;
input color  PanelBackColor    = clrBlack;
input int    PanelMaxRows      = 30;   // حداکثر ردیف نمایش داده شده

//+------------------------------------------------------------------+
// یک ردیف جدول
struct ScanRow
{
   string          symbol;
   ENUM_TIMEFRAMES tf;
   bool            isBull;
   ABState         state;
   bool            hasBreak;
   int             rank;    // هر چه کمتر، مهم تر
};

string   scanSymbolList[];
int      scanSymbolCount = 0;

ENUM_TIMEFRAMES scanTFList[];
int      scanTFCount = 0;
string   tfSource = "";

string   notifiedKeys[];
int      notifiedCount = 0;
bool     firstScanDone = false;   // اولین اسکن فقط ثبت می‌کند و اطلاع نمی‌دهد

string   objPrefix;
int      drawnRows = 0;

//+------------------------------------------------------------------+
// هر چه رتبه کمتر، الگو به معامله نزدیک تر. جدول با همین مرتب می‌شود تا
// وقتی ردیف ها از سقف نمایش بیشتر شدند، مهم ترین ها بالا بمانند.
int StateRank(SwingAB &s)
{
   if(s.state == AB_BROKEN)       return s.hasValidBreak ? 0 : 1;
   if(s.state == AB_RETRACED)     return 2;
   if(s.state == AB_WAIT_RETRACE) return 3;
   return 4;
}

bool PassesFilter(int rank, PanelFilterMode mode)
{
   if(mode == SHOW_FROM_HUNT) return (rank <= 1);
   if(mode == SHOW_FROM_COK)  return (rank <= 2);
   return true;
}

//+------------------------------------------------------------------+
// فهرست نمادها: خالی یعنی همه Market Watch، وگرنه همان لیست با کاما
void BuildSymbolList()
{
   ArrayResize(scanSymbolList, 0);
   scanSymbolCount = 0;

   string trimmed = ScanSymbols;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);

   if(StringLen(trimmed) == 0)
   {
      int total = SymbolsTotal(true);          // فقط Market Watch
      ArrayResize(scanSymbolList, total);
      for(int i = 0; i < total; i++)
      {
         scanSymbolList[scanSymbolCount] = SymbolName(i, true);
         scanSymbolCount++;
      }
      return;
   }

   string parts[];
   int n = StringSplit(trimmed, ',', parts);
   ArrayResize(scanSymbolList, n);

   for(int i = 0; i < n; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;

      // نماد باید در Market Watch باشد تا داده اش در دسترس باشد
      if(!SymbolSelect(sym, true)) continue;

      scanSymbolList[scanSymbolCount] = sym;
      scanSymbolCount++;
   }

   ArrayResize(scanSymbolList, scanSymbolCount);
}

//+------------------------------------------------------------------+
// خواندن سه تایم فریم از چارتی که اندیکاتور ABHunter رویش نصب است.
// اندیکاتور انتخاب دکمه ها را در آبجکت ABH_State_<chartID> نگه می‌دارد.
bool ReadTFsFromChart()
{
   long id = ChartFirst();

   while(id >= 0)
   {
      string obj = StateObjectName(id);

      if(ObjectFind(id, obj) >= 0)
      {
         string txt = ObjectGetString(id, obj, OBJPROP_TEXT);
         int p1 = StringFind(txt, "|");
         int p2 = (p1 >= 0) ? StringFind(txt, "|", p1 + 1) : -1;

         if(p1 >= 0 && p2 > p1)
         {
            int i1 = ClampIdx((int)StringToInteger(StringSubstr(txt, 0, p1)), ArraySize(StructureTFList));
            int i2 = ClampIdx((int)StringToInteger(StringSubstr(txt, p1 + 1, p2 - (p1 + 1))), ArraySize(TriggerTFList));
            int i3 = ClampIdx((int)StringToInteger(StringSubstr(txt, p2 + 1)), ArraySize(EntryTFList));

            ArrayResize(scanTFList, 3);
            scanTFList[0] = StructureTFList[i1];
            scanTFList[1] = TriggerTFList[i2];
            scanTFList[2] = EntryTFList[i3];
            scanTFCount   = 3;
            tfSource      = "chart " + ChartSymbol(id);
            return true;
         }
      }

      id = ChartNext(id);
   }

   return false;
}

// فهرست تایم فریم های این اسکن
void BuildTFList()
{
   if(SyncTFWithChart && ReadTFsFromChart()) return;

   ArrayResize(scanTFList, 0);
   scanTFCount = 0;

   string parts[];
   int n = StringSplit(ScanTimeframes, ',', parts);
   ArrayResize(scanTFList, n);

   for(int i = 0; i < n; i++)
   {
      ENUM_TIMEFRAMES tf = StrToTF(parts[i]);
      if(tf == 0) continue;                      // رشته نامعتبر رد می‌شود
      scanTFList[scanTFCount] = tf;
      scanTFCount++;
   }

   ArrayResize(scanTFList, scanTFCount);
   tfSource = "inputs";
}

//+------------------------------------------------------------------+
bool AlreadyNotified(string key)
{
   for(int i = 0; i < notifiedCount; i++)
      if(notifiedKeys[i] == key) return true;
   return false;
}

void RememberNotified(string key)
{
   // فهرست بی نهایت رشد نکند: نصف قدیمی ها دور ریخته می‌شود
   if(notifiedCount >= 6000)
   {
      int keep = notifiedCount / 2;
      for(int i = 0; i < keep; i++)
         notifiedKeys[i] = notifiedKeys[notifiedCount - keep + i];
      notifiedCount = keep;
   }

   if(notifiedCount >= ArraySize(notifiedKeys))
      ArrayResize(notifiedKeys, notifiedCount + 512);

   notifiedKeys[notifiedCount] = key;
   notifiedCount++;
}

//+------------------------------------------------------------------+
void DeletePanel()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, objPrefix) == 0)
         ObjectDelete(0, name);
   }
}

void PanelBackground(int rows)
{
   string name = objPrefix + "BG";
   int height = rows * (PanelFontSize + 7) + 14;
   int width  = 320;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelX - 6);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelY - 6);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, PanelBackColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, PanelBackColor);
}

void PanelRow(int row, string text, color clr)
{
   string name = objPrefix + "R" + IntegerToString(row);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelY + row * (PanelFontSize + 7));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PanelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void ClearRowsFrom(int firstRow)
{
   for(int r = firstRow; r < drawnRows; r++)
   {
      string name = objPrefix + "R" + IntegerToString(r);
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   }
}

string PadRight(string s, int width)
{
   string r = s;
   while(StringLen(r) < width) r = r + " ";
   return r;
}

//+------------------------------------------------------------------+
void RunScan()
{
   if(scanSymbolCount == 0) BuildSymbolList();
   BuildTFList();

   ScanRow rows[];
   int nRows = 0;
   ArrayResize(rows, 256);

   for(int si = 0; si < scanSymbolCount; si++)
   {
      string sym = scanSymbolList[si];

      for(int ti = 0; ti < scanTFCount; ti++)
      {
         ENUM_TIMEFRAMES tf = scanTFList[ti];

         MqlRates rates[];
         int rates_total = 0;
         SwingAB active[];

         int n = AnalyzeSymbol(sym, tf, ABCDHistoryBars, 30, false, false,
                               rates, rates_total, active);

         // داده هنوز آماده نیست؛ متاتریدر آن را در پس زمینه دانلود می‌کند
         // و اسکن بعدی دوباره امتحان می‌کند
         if(n < 0) continue;

         for(int k = 0; k < n; k++)
         {
            if(active[k].live) continue;   // هنوز قطعی نشده

            int rank = StateRank(active[k]);

            // --- نوتیفیکیشن برای هر AB جدیدی که قطعی شده
            string key = sym + "|" + IntegerToString((int)tf) + "|" +
                         IntegerToString((long)active[k].timeA);

            if(!AlreadyNotified(key))
            {
               RememberNotified(key);

               // اولین اسکن فقط ثبت می‌کند، وگرنه لحظه نصب با انبوه
               // اطلاع رسانی از الگوهای قدیمی روبرو می‌شوید
               if(firstScanDone && EnablePush && PassesFilter(rank, NotifyFilter))
               {
                  SendNotification("ABHunter " + sym + " " + TFToStr(tf) + " " +
                                   (active[k].isBull ? "BULL" : "BEAR") +
                                   " " + StateText(active[k]));
               }
            }

            if(!PassesFilter(rank, PanelFilter)) continue;

            if(nRows >= ArraySize(rows)) ArrayResize(rows, nRows + 256);

            rows[nRows].symbol   = sym;
            rows[nRows].tf       = tf;
            rows[nRows].isBull   = active[k].isBull;
            rows[nRows].state    = active[k].state;
            rows[nRows].hasBreak = active[k].hasValidBreak;
            rows[nRows].rank     = rank;
            nRows++;
         }
      }
   }

   // --- سربرگ
   int row = 0;
   PanelRow(row, "ABHunter  " + IntegerToString(scanSymbolCount) + " sym x " +
                 IntegerToString(scanTFCount) + " tf  <- " + tfSource, PanelTitleColor);
   row++;
   PanelRow(row, PadRight("SYMBOL", 12) + PadRight("TF", 5) + PadRight("DIR", 5) + "STATE",
            PanelTitleColor);
   row++;

   // --- ردیف ها به ترتیب اهمیت. مرتب سازی انتخابی ساده کافی است چون فقط
   //     به تعداد PanelMaxRows بار اجرا می‌شود.
   int shown = 0;
   bool used[];
   if(nRows > 0)
   {
      ArrayResize(used, nRows);
      for(int i = 0; i < nRows; i++) used[i] = false;
   }

   while(shown < PanelMaxRows)
   {
      int best = -1;
      for(int i = 0; i < nRows; i++)
      {
         if(used[i]) continue;
         if(best < 0 || rows[i].rank < rows[best].rank) best = i;
      }
      if(best < 0) break;

      used[best] = true;

      string dir = rows[best].isBull ? "BULL" : "BEAR";
      string st  = (rows[best].state == AB_BROKEN)
                      ? (rows[best].hasBreak ? "BREAK" : "HUNT")
                      : (rows[best].state == AB_RETRACED ? "C ok" : "WAIT");

      PanelRow(row, PadRight(rows[best].symbol, 12) +
                    PadRight(TFToStr(rows[best].tf), 5) +
                    PadRight(dir, 5) + st,
               rows[best].isBull ? PanelBullColor : PanelBearColor);
      row++;
      shown++;
   }

   if(nRows == 0)
   {
      PanelRow(row, "(no active pattern)", PanelTextColor);
      row++;
   }
   else if(nRows > shown)
   {
      PanelRow(row, "... +" + IntegerToString(nRows - shown) + " more", PanelTextColor);
      row++;
   }

   ClearRowsFrom(row);
   drawnRows = row;

   PanelBackground(row);
   ChartRedraw();

   firstScanDone = true;
}

//+------------------------------------------------------------------+
int OnInit()
{
   objPrefix = "ABHScan_" + IntegerToString(ChartID()) + "_";

   ArrayResize(notifiedKeys, 512);
   notifiedCount = 0;
   firstScanDone = false;
   drawnRows     = 0;

   BuildSymbolList();
   BuildTFList();

   int period = RefreshSeconds;
   if(period < 5) period = 5;
   EventSetTimer(period);

   RunScan();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   RunScan();
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // کار اصلی روی تایمر انجام می‌شود؛ تیک های چارت میزبان بی ربط اند
   return(rates_total);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeletePanel();
   ChartRedraw();
}
//+------------------------------------------------------------------+
