//+------------------------------------------------------------------+
//|                                             ABHunterScanner.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| اسکنر چند نمادی ABHunter.                                          |
//| روی یک چارت نصب می‌شود و همه نمادهای انتخابی را در سه تایم فریم    |
//| اسکن می‌کند، جدول الگوهای فعال را نشان می‌دهد و برای هر AB جدیدی   |
//| که قطعی شود نوتیفیکیشن موبایل می‌فرستد.                            |
//|                                                                  |
//| قواعد تشخیص از ABHunterCore.mqh می‌آید — همان فایلی که اندیکاتور    |
//| چارت هم استفاده می‌کند، تا دو نسخه از منطق وجود نداشته باشد.       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.10"
#property indicator_chart_window

#include "ABHunterCore.mqh"

//---- دامنه اسکن
input string ScanSymbols       = "";        // نمادها با کاما؛ خالی یعنی همه Market Watch
input bool   SyncTFWithChart   = true;      // خواندن تایم فریم ها از چارتی که اندیکاتور رویش نصب است
input ENUM_TIMEFRAMES ScanTF1  = PERIOD_H4; // تایم فریم ساختار (وقتی هماهنگی خاموش یا ناموفق است)
input ENUM_TIMEFRAMES ScanTF2  = PERIOD_M20;// تایم فریم تریگر
input ENUM_TIMEFRAMES ScanTF3  = PERIOD_M1; // تایم فریم ورود
input int    RefreshSeconds    = 30;        // فاصله هر اسکن (ثانیه)

//---- نوتیفیکیشن
input bool   EnablePush        = true;      // نوتیفیکیشن موبایل برای هر AB جدید قطعی شده
input bool   NotifyTF1         = true;      // اطلاع رسانی برای تایم فریم ساختار
input bool   NotifyTF2         = true;      // اطلاع رسانی برای تایم فریم تریگر
input bool   NotifyTF3         = false;     // اطلاع رسانی برای تایم فریم ورود

//---- جدول
input int    PanelX            = 10;        // فاصله جدول از چپ
input int    PanelY            = 20;        // فاصله جدول از بالا
input int    PanelFontSize     = 9;
input color  PanelTitleColor   = clrWhite;
input color  PanelTextColor    = clrGainsboro;
input color  PanelBullColor    = clrDeepSkyBlue;
input color  PanelBearColor    = clrOrange;
input color  PanelBackColor    = clrBlack;
input int    PanelMaxRows      = 25;        // حداکثر ردیف نمایش داده شده

//+------------------------------------------------------------------+
string   scanSymbolList[];      // نمادهایی که اسکن می‌شوند
int      scanSymbolCount = 0;

string   notifiedKeys[];        // کلید الگوهایی که برایشان اطلاع فرستاده شده
int      notifiedCount = 0;
bool     firstScanDone = false; // اولین اسکن فقط ثبت می‌کند و اطلاع نمی‌دهد

string   objPrefix;             // پیشوند آبجکت های این چارت
int      drawnRows = 0;

ENUM_TIMEFRAMES activeTF[3];    // تایم فریم های همین اسکن
string   tfSource = "";         // از کجا آمده اند، برای سربرگ جدول

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ScanTF(int slot)
{
   return activeTF[slot];
}

//+------------------------------------------------------------------+
// خواندن تایم فریم ها از چارتی که اندیکاتور ABHunter رویش نصب است.
// اندیکاتور انتخاب سه دکمه را در آبجکت ABH_State_<chartID> نگه می‌دارد، پس
// کافیست چارت های باز را بگردیم و اولین چارتی که چنین آبجکتی دارد را بخوانیم.
// اینطوری هر بار با دکمه ها تایم فریم را عوض کنید، اسکن بعدی همان را می‌گیرد.
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

            activeTF[0] = StructureTFList[i1];
            activeTF[1] = TriggerTFList[i2];
            activeTF[2] = EntryTFList[i3];
            tfSource    = ChartSymbol(id);
            return true;
         }
      }

      id = ChartNext(id);
   }

   return false;
}

// تایم فریم های این اسکن را تعیین می‌کند: اول از چارت، وگرنه از ورودی ها
void ResolveTFs()
{
   if(SyncTFWithChart && ReadTFsFromChart()) return;

   activeTF[0] = ScanTF1;
   activeTF[1] = ScanTF2;
   activeTF[2] = ScanTF3;
   tfSource    = SyncTFWithChart ? "inputs (no chart)" : "inputs";
}

bool NotifyForSlot(int slot)
{
   if(slot == 0) return NotifyTF1;
   if(slot == 1) return NotifyTF2;
   return NotifyTF3;
}

color SlotColor(int slot, bool isBull)
{
   return isBull ? PanelBullColor : PanelBearColor;
}

//+------------------------------------------------------------------+
// ساخت فهرست نمادها: اگر ScanSymbols خالی باشد از Market Watch، وگرنه از
// همان لیست. نمادهایی که در ترمینال وجود ندارند کنار گذاشته می‌شوند.
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
bool AlreadyNotified(string key)
{
   for(int i = 0; i < notifiedCount; i++)
      if(notifiedKeys[i] == key) return true;
   return false;
}

void RememberNotified(string key)
{
   // فهرست بی نهایت رشد نکند: نصف قدیمی ها دور ریخته می‌شود
   if(notifiedCount >= 4000)
   {
      int keep = notifiedCount / 2;
      for(int i = 0; i < keep; i++)
         notifiedKeys[i] = notifiedKeys[notifiedCount - keep + i];
      notifiedCount = keep;
   }

   if(notifiedCount >= ArraySize(notifiedKeys))
      ArrayResize(notifiedKeys, notifiedCount + 256);

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
   int height = 22 + rows * (PanelFontSize + 7) + 8;
   int width  = 330;

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

// ردیف های اضافه از اسکن قبلی پاک می‌شوند
void ClearRowsFrom(int firstRow)
{
   for(int r = firstRow; r < drawnRows; r++)
   {
      string name = objPrefix + "R" + IntegerToString(r);
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
// یک ردیف با عرض ثابت تا ستون ها زیر هم بمانند
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

   ResolveTFs();

   int row = 0;
   PanelRow(row, "TF: " + TFToStr(activeTF[0]) + " / " + TFToStr(activeTF[1]) +
                 " / " + TFToStr(activeTF[2]) + "   <- " + tfSource, PanelTitleColor);
   row++;
   PanelRow(row, PadRight("SYMBOL", 12) + PadRight("TF", 5) + PadRight("DIR", 5) + "STATE", PanelTitleColor);
   row++;

   int found = 0;

   for(int si = 0; si < scanSymbolCount; si++)
   {
      string sym = scanSymbolList[si];

      for(int slot = 0; slot < 3; slot++)
      {
         ENUM_TIMEFRAMES tf = ScanTF(slot);

         MqlRates rates[];
         int rates_total = 0;
         SwingAB active[];

         // تایم ورود مثل اندیکاتور فقط آخرین AB را نگه می‌دارد
         bool keepOnlyLast = (slot == 2);

         int n = AnalyzeSymbol(sym, tf, ABCDHistoryBars, 30, keepOnlyLast, false,
                               rates, rates_total, active);

         // داده هنوز آماده نیست؛ متاتریدر آن را در پس زمینه دانلود می‌کند
         // و اسکن بعدی دوباره امتحان می‌کند
         if(n < 0) continue;

         for(int k = 0; k < n; k++)
         {
            if(active[k].live) continue;   // هنوز قطعی نشده

            found++;

            // --- نوتیفیکیشن برای هر AB جدیدی که قطعی شده
            string key = sym + "|" + IntegerToString((int)tf) + "|" +
                         IntegerToString((long)active[k].timeA);

            if(!AlreadyNotified(key))
            {
               RememberNotified(key);

               // اولین اسکن فقط ثبت می‌کند، وگرنه با انبوه اطلاع رسانی
               // از الگوهای قدیمی روبرو می‌شوید
               if(firstScanDone && EnablePush && NotifyForSlot(slot))
               {
                  SendNotification("ABHunter " + sym + " " + TFToStr(tf) + " " +
                                   (active[k].isBull ? "BULL" : "BEAR") +
                                   " AB " + StateText(active[k]));
               }
            }

            // --- ردیف جدول
            if(row - 2 < PanelMaxRows)
            {
               string line = PadRight(sym, 12) +
                             PadRight(TFToStr(tf), 5) +
                             PadRight(active[k].isBull ? "BULL" : "BEAR", 5) +
                             StateText(active[k]);
               PanelRow(row, line, SlotColor(slot, active[k].isBull));
               row++;
            }
         }
      }
   }

   if(found == 0)
   {
      PanelRow(row, "(الگوی فعالی پیدا نشد)", PanelTextColor);
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

   ArrayResize(notifiedKeys, 256);
   notifiedCount = 0;
   firstScanDone = false;
   drawnRows     = 0;

   BuildSymbolList();
   ResolveTFs();

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
