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
#property version   "2.56"
#property indicator_chart_window
#property indicator_plots 0   // هیچ پلاتی ندارد؛ فقط آبجکت رسم می‌کند

#include "ABHunterCore.mqh"

//---- گوشه ای که جدول در آن قرار می‌گیرد
enum PanelCornerMode
{
   PANEL_TOP_LEFT,   // بالا چپ
   PANEL_TOP_RIGHT   // بالا راست
};

//---- کدام وضعیت ها به حساب بیایند.
// اسکنر باید ستاپ را «قبل از» فعال شدنش نشان دهد تا فرصت رفتن به تایم پایین تر
// باشد. الگویی که B اش هانت شده دیگر موقعیت ورود نمی‌دهد و فقط شلوغی است.
enum PanelFilterMode
{
   FILTER_PRE_HUNT,   // AB و ABC که B هنوز هانت نشده
   FILTER_COK_ONLY,   // فقط ABC کامل (اصلاح معتبر، منتظر شکست)
   FILTER_ALL         // همه، شامل هانت شده ها
};

//---- دامنه اسکن
input string ScanSymbols       = "XAUUSD,DJIUSD,BRNUSD,SPXUSD,NDXUSD,NZDJPY,USDCAD,USDCHF,USDJPY,GBPCHF,GBPJPY,GBPNZD,GBPUSD,EURJPY,EURNZD,EURUSD,GBPAUD,GBPCAD,CHFJPY,EURAUD,EURCAD,EURCHF,EURGBP,AUDCAD,AUDJPY,AUDUSD,CADCHF,CADJPY"; // نمادها با کاما؛ خالی یعنی همه Market Watch
input bool   ScanAllMarketWatch = false; // اگر ScanSymbols خالی بود، همه Market Watch اسکن شود
input string ScanTimeframes    = "H8,H4,H3,H2,H1,M30,M20,M15"; // تایم فریم ها با کاما
input bool   SyncTFWithChart   = false;// به جای فهرست بالا، سه تایم فریم دکمه های چارت خوانده شود
input int    RefreshSeconds    = 60;   // فاصله هر اسکن کامل (ثانیه)؛ شمارش معکوس در سربرگ دیده می‌شود

//---- نوتیفیکیشن
input bool   EnablePush        = true; // نوتیفیکیشن موبایل برای هر AB جدید قطعی شده
input PanelFilterMode NotifyFilter = FILTER_PRE_HUNT; // برای کدام وضعیت ها اطلاع بدهد

//---- جدول
input PanelFilterMode PanelFilter = FILTER_PRE_HUNT; // کدام وضعیت ها در جدول بیایند
input PanelCornerMode PanelCorner = PANEL_TOP_RIGHT; // جدول در کدام گوشه باشد
input int    PanelX            = 70;   // فاصله جدول از لبه انتخاب شده
input int    PanelY            = 20;   // فاصله جدول از بالا
input int    PanelWidth        = 470;  // عرض جدول
input int    NewMarkMinutes    = 45;   // تا چند دقیقه سن الگو در ستون AGE نوشته شود
input bool   PersistAge        = true; // سن الگوها بین تعویض پروفایل و ری استارت حفظ شود
input int    ExpiredKeepSeconds = 0;   // 0 = یک کندل همان تایم فریم، >0 = ثانیه ثابت، منفی = خاموش
input int    PanelFontSize     = 9;
input color  PanelTitleColor   = clrWhite;
input color  PanelTextColor    = clrGainsboro;
input color  PanelBullColor    = clrDeepSkyBlue;
input color  PanelBearColor    = clrOrange;
input color  PanelExpiredColor = clrGray;   // رنگ ردیف های در حال حذف
input color  PanelBackColor    = clrBlack;
input color  PanelBorderColor  = clrDimGray; // رنگ قاب جدول
input int    PanelMaxRows      = 100;  // سقف ردیف؛ به هر حال از ارتفاع چارت بیشتر نمی‌شود

//+------------------------------------------------------------------+
// یک ردیف جدول
struct ScanRow
{
   string          symbol;
   int             symIndex;   // جای نماد در ScanSymbols، برای گروه بندی
   ENUM_TIMEFRAMES tf;
   int             tfIndex;
   bool            isBull;
   ABState         state;
   bool            hasBreak;
   int             rank;       // هر چه کمتر، مهم تر
   int             groupRank;  // بهترین رتبه همین نماد
   string          newMark;    // سن الگو به دقیقه، اگر تازه باشد
   string          key;        // شناسه یکتای الگو
   datetime        goneAt;     // 0 یعنی زنده؛ وگرنه لحظه ای که از لیست افتاد
};

string   scanSymbolList[];
int      scanSymbolCount = 0;

ENUM_TIMEFRAMES scanTFList[];
int      scanTFCount = 0;
string   tfSource = "";

// هر الگو یک بار ثبت می‌شود: هم برای اینکه دوبار نوتیفیکیشن نرود، هم برای
// اینکه بدانیم چه زمانی اولین بار دیده شده.
// زمان با TimeLocal گرفته می‌شود نه TimeCurrent: دومی زمان آخرین تیک سرور است
// و با بازار بسته اصلا جلو نمی‌رود، پس سن همه الگوها صفر می‌ماند و همه برای
// همیشه «تازه» می‌مانند. مقدار 0 یعنی الگو از قبل وجود داشته (اسکن اول).
string   seenKeys[];
datetime seenFirst[];
int      seenCount = 0;
bool     firstScanDone = false;   // اولین اسکن فقط ثبت می‌کند و اطلاع نمی‌دهد

// پیشوند متغیرهای سراسری ترمینال. عمدا شناسه چارت در آن نیست: باید بین
// پروفایل ها مشترک باشد تا با عوض کردن پروفایل سن الگوها صفر نشود.
#define ABH_GV_PREFIX "ABHscan_"

string   objPrefix;
int      drawnRows = 0;

// آخرین وضعیت جدول، تا رسم دوباره (تغییر اندازه چارت، انقضای ردیف خاکستری)
// بدون اجرای اسکن سنگین ممکن باشد
ScanRow  panelRows[];
int      panelRowCount = 0;
ScanRow  lastLive[];
int      lastLiveCount = 0;
ScanRow  goneRows[];
int      goneCount = 0;

// آنچه در آخرین رسم روی صفحه رفت، تا بشود فقط ستون سود را تازه کرد
string   liveSymbol[];
string   livePrefix[];
color    liveColor[];
int      liveRow[];
int      liveCount   = 0;
int      timerTicks  = 0;
int      panelLeft = 0;   // مختصات چپ جدول، هر بار دوباره حساب می‌شود

//+------------------------------------------------------------------+
// برای گوشه راست از CORNER_RIGHT_UPPER استفاده نمی‌کنیم، چون آن حالت جهت
// انکر متن ها را برعکس می‌کند و ستون های هم عرض به هم می‌ریزند. به جایش
// مختصات چپ را از عرض چارت حساب می‌کنیم و همه چیز از گوشه بالا چپ می‌ماند.
int PanelLeftX()
{
   if(PanelCorner == PANEL_TOP_LEFT) return PanelX;

   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int x = chartW - PanelWidth - PanelX;
   if(x < 0) x = 0;
   return x;
}

// چند ردیف در ارتفاع فعلی چارت جا می‌شود
int MaxRowsThatFit()
{
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int rowH   = PanelFontSize + 7;
   if(rowH <= 0) rowH = 16;

   int fits = (chartH - PanelY - 24) / rowH;
   if(fits < 5) fits = 5;
   return fits;
}

//+------------------------------------------------------------------+
// هر چه رتبه کمتر، الگو به معامله نزدیک تر.
int StateRank(SwingAB &s)
{
   if(s.state == AB_BROKEN)       return s.hasValidBreak ? 0 : 1;
   if(s.state == AB_RETRACED)     return 2;
   if(s.state == AB_WAIT_RETRACE) return 3;
   return 4;
}

// rank: 0 = BREAK، 1 = HUNT، 2 = C ok، 3 = WAIT
bool PassesFilter(int rank, PanelFilterMode mode)
{
   if(mode == FILTER_ALL)      return true;
   if(mode == FILTER_COK_ONLY) return (rank == 2);
   return (rank >= 2);   // FILTER_PRE_HUNT: فقط C ok و WAIT
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
      // بدون تایید صریح، لیست خالی به معنی «همه Market Watch» نیست. اینطور
      // اگر مقدار ورودی جا نیفتاده باشد، جدول بی سروصدا پر از نمادهای ناخواسته
      // نمی‌شود؛ به جایش سربرگ می‌گوید چه شده.
      if(!ScanAllMarketWatch) return;

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

//+------------------------------------------------------------------+
// تبدیل رشته به تایم فریم، برای ورودی ScanTimeframes.
// عمدا اینجاست و نه در ABHunterCore.mqh: تنها مصرف کننده اش همین فایل است و
// اینطور به روز کردن اسکنر به به روز کردن فایل مشترک وابسته نیست.
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

   return (ENUM_TIMEFRAMES)0;   // نامعتبر
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
// --- ماندگاری سن الگو
//
// متغیرهای سراسری ترمینال روی دیسک ذخیره می‌شوند و با عوض کردن پروفایل یا
// بستن ترمینال از بین نمی‌روند. آرایه های داخل اندیکاتور اما با هر بار
// نصب دوباره صفر می‌شوند، پس ستون AGE بدون این کار هر بار از نو شروع می‌کرد.
//
// علامت مقدار معنا دارد: مثبت یعنی الگو موقع دیده شدن «تازه» بود و همان عدد
// زمان اولین رویت است؛ منفی یعنی موقع اولین اسکن از قبل روی چارت بوده و
// نباید تازه حساب شود. قدر مطلق در هر دو حالت زمان نوشتن است، که برای
// پاکسازی به کار می‌آید.
string GVName(string sym, ENUM_TIMEFRAMES tf, datetime timeA)
{
   string s = sym;
   if(StringLen(s) > 24) s = StringSubstr(s, 0, 24);   // سقف نام ۶۳ کاراکتر است

   return ABH_GV_PREFIX + s + "_" + IntegerToString((int)tf) + "_" +
          IntegerToString((long)timeA);
}

// ورودی های کهنه دور ریخته می‌شوند تا فهرست متغیرهای سراسری بی نهایت رشد
// نکند. الگو حداکثر یک روز معتبر است، پس دو روز حاشیه امن کافی است.
void PruneOldGlobals()
{
   if(!PersistAge) return;

   double now = (double)TimeLocal();
   int total = GlobalVariablesTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, ABH_GV_PREFIX) != 0) continue;

      double v = MathAbs(GlobalVariableGet(name));
      if(v <= 0.0 || (now - v) > 2.0 * 86400.0)
         GlobalVariableDel(name);
   }
}

//+------------------------------------------------------------------+
int SeenIndex(string key)
{
   for(int i = 0; i < seenCount; i++)
      if(seenKeys[i] == key) return i;
   return -1;
}

// preExisting یعنی این الگو در اولین اسکن این نصب دیده شده و نباید «تازه»
// شمرده شود. برگشتی: اندیس در seenKeys، و alreadyKnown می‌گوید که آیا این
// الگو از قبل (در نصب قبلی) هم شناخته شده بود یا واقعا اولین بار است.
int RememberSeen(string key, string gv, bool preExisting, bool &alreadyKnown)
{
   alreadyKnown = false;
   datetime first = preExisting ? 0 : TimeLocal();

   if(PersistAge && GlobalVariableCheck(gv))
   {
      double v = GlobalVariableGet(gv);
      alreadyKnown = true;
      first = (v > 0.0) ? (datetime)v : 0;
   }
   else if(PersistAge)
   {
      GlobalVariableSet(gv, preExisting ? -(double)TimeLocal() : (double)TimeLocal());
   }

   // فهرست بی نهایت رشد نکند: نصف قدیمی ها دور ریخته می‌شود
   if(seenCount >= 6000)
   {
      int keep = seenCount / 2;
      for(int i = 0; i < keep; i++)
      {
         seenKeys[i]  = seenKeys[seenCount - keep + i];
         seenFirst[i] = seenFirst[seenCount - keep + i];
      }
      seenCount = keep;
   }

   if(seenCount >= ArraySize(seenKeys))
   {
      ArrayResize(seenKeys,  seenCount + 512);
      ArrayResize(seenFirst, seenCount + 512);
   }

   seenKeys[seenCount]  = key;
   seenFirst[seenCount] = first;
   seenCount++;
   return seenCount - 1;
}

// وضعیت و سود شناور معامله های باز روی یک نماد، در یک بار پیمایش.
// سود شامل سواپ هم هست تا عدد همان چیزی باشد که در ترمینال می‌بینید.
// واحدش ارز حساب است، نه لزوما دلار.
void PositionInfo(string sym, string &mark, double &profit, bool &hasAny)
{
   bool hasBuy = false, hasSell = false;
   profit = 0.0;

   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      if(PositionGetSymbol(i) != sym) continue;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) hasBuy = true;
      else                                                       hasSell = true;

      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   hasAny = (hasBuy || hasSell);

   if(hasBuy && hasSell) mark = "B+S";
   else if(hasBuy)       mark = "BUY";
   else if(hasSell)      mark = "SELL";
   else                  mark = "";
}

string FormatProfit(double profit, bool hasAny)
{
   if(!hasAny) return "";
   return (profit >= 0.0 ? "+" : "") + DoubleToString(profit, 2);
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

// کادر جدول باید قبل از لیبل ها ساخته شود.
// در متاتریدر بین آبجکت هایی که BACK=false دارند، هر چه دیرتر ساخته شود
// رویی تر رسم می‌شود؛ اگر کادر بعد از لیبل ها ساخته شود رویشان می‌افتد و
// متن جدول دیده نمی‌شود.
void EnsurePanelBackground()
{
   string name = objPrefix + "BG";
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // جلوی چارت رسم می‌شود تا کندل ها رویش نیفتند و جدول خوانا بماند
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void SizePanelBackground(int rows)
{
   string name = objPrefix + "BG";
   int height = rows * (PanelFontSize + 7) + 14;
   int width  = PanelWidth;

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, panelLeft - 6);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelY - 6);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, PanelBackColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, PanelBorderColor);
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

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, panelLeft);
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

string TwoDigits(int v)
{
   return (v < 10 ? "0" : "") + IntegerToString(v);
}

//+------------------------------------------------------------------+
// سربرگ، شامل شمارش معکوس تا اسکن بعدی. هر ثانیه تازه می‌شود تا معلوم باشد
// عددهای جدول چقدر کهنه اند و سیکل به کجا رسیده.
string HeaderText()
{
   int period = RefreshSeconds;
   if(period < 5) period = 5;

   int left = period - timerTicks;
   if(left < 0) left = 0;

   // تعداد نماد و تایم فریم عمدا نوشته نمی‌شود؛ خود شما آن را تنظیم کرده اید.
   // منبع تایم فریم فقط وقتی می‌آید که از چارت خوانده شده باشد، چون آن یکی
   // ممکن است بدون اینکه بدانید عوض شود.
   string src = (tfSource == "inputs") ? "" : "  <- " + tfSource;

   return "ABHunter" + src +
          "   next " + TwoDigits(left / 60) + ":" + TwoDigits(left % 60);
}

string StateTextOf(ScanRow &r)
{
   if(r.state == AB_BROKEN)   return r.hasBreak ? "BREAK" : "HUNT";
   if(r.state == AB_RETRACED) return "C ok";
   return "WAIT";
}

//+------------------------------------------------------------------+
// مرتب سازی: اول نمادی که به معامله نزدیک تر است، ولی همه ردیف های یک نماد
// کنار هم. اینطور لازم نیست یک نماد را دو جای جدول دنبال کنید، و در عین حال
// وقتی ردیف ها از ارتفاع چارت بیشتر شدند مهم ترین نمادها بالا می‌مانند.
void SortRows(ScanRow &r[], int n)
{
   // بهترین (کمترین) رتبه هر نماد
   for(int i = 0; i < n; i++)
   {
      int best = r[i].rank;
      for(int j = 0; j < n; j++)
         if(r[j].symIndex == r[i].symIndex && r[j].rank < best) best = r[j].rank;
      r[i].groupRank = best;
   }

   for(int i = 0; i < n - 1; i++)
   {
      int best = i;

      for(int j = i + 1; j < n; j++)
      {
         if(r[j].groupRank != r[best].groupRank)
         {
            if(r[j].groupRank < r[best].groupRank) best = j;
            continue;
         }
         if(r[j].symIndex != r[best].symIndex)
         {
            if(r[j].symIndex < r[best].symIndex) best = j;
            continue;
         }
         if(r[j].rank != r[best].rank)
         {
            if(r[j].rank < r[best].rank) best = j;
            continue;
         }
         if(r[j].tfIndex < r[best].tfIndex) best = j;
      }

      if(best != i)
      {
         ScanRow t;      // متاتریدر مقداردهی اولیه ساختار در خود اعلان را قبول ندارد
         t       = r[i];
         r[i]    = r[best];
         r[best] = t;
      }
   }
}

//+------------------------------------------------------------------+
// الگویی که از فهرست می‌افتد بلافاصله ناپدید نمی‌شود: مدتی خاکستری در انتهای
// جدول می‌ماند تا معلوم باشد چه چیزی اعتبارش تمام شده.
// چقدر خاکستری بماند. پیش فرض «یک کندل همان تایم فریم» است: روی H8 هشت
// ساعت، روی H1 یک ساعت. یک عدد ثابت برای همه تایم فریم ها معنی ندارد —
// شصت ثانیه روی H8 یعنی عملا ندیدنش.
int ExpirySeconds(ENUM_TIMEFRAMES tf)
{
   if(ExpiredKeepSeconds > 0) return ExpiredKeepSeconds;

   int p = PeriodSeconds(tf);
   return (p > 0) ? p : 60;
}

bool PruneGone()
{
   if(ExpiredKeepSeconds < 0)
   {
      bool had = (goneCount > 0);
      goneCount = 0;
      return had;
   }

   datetime now = TimeLocal();
   bool changed = false;

   for(int g = goneCount - 1; g >= 0; g--)
   {
      if((now - goneRows[g].goneAt) < ExpirySeconds(goneRows[g].tf)) continue;

      for(int k = g; k < goneCount - 1; k++) goneRows[k] = goneRows[k + 1];
      goneCount--;
      changed = true;
   }

   return changed;
}

// cur = ردیف هایی که از فیلتر جدول رد شده اند.
// all = همه الگوهای این اسکن، حتی آنهایی که فیلتر نشدند. لازم است چون الگویی
//       که هانت می‌شود از جدول می‌افتد ولی هنوز وجود دارد، و ردیف خاکستری
//       باید وضعیت تازه اش (HUNT) را بنویسد نه وضعیت کهنه ای که آخرین بار
//       در جدول دیده شده بود.
void UpdateGoneList(ScanRow &cur[], int nCur, ScanRow &all[], int nAll)
{
   datetime now = TimeLocal();

   // هر چه دوباره زنده شده از فهرست خاکستری ها بیرون می‌آید
   for(int g = goneCount - 1; g >= 0; g--)
   {
      bool aliveAgain = false;
      for(int i = 0; i < nCur; i++)
         if(cur[i].key == goneRows[g].key) { aliveAgain = true; break; }

      if(!aliveAgain) continue;

      for(int k = g; k < goneCount - 1; k++) goneRows[k] = goneRows[k + 1];
      goneCount--;
   }

   PruneGone();

   if(ExpiredKeepSeconds < 0) return;

   // هر چه در اسکن قبل بود و حالا نیست، مهلت خاکستری می‌گیرد
   for(int i = 0; i < lastLiveCount; i++)
   {
      bool stillHere = false;
      for(int j = 0; j < nCur; j++)
         if(cur[j].key == lastLive[i].key) { stillHere = true; break; }
      if(stillHere) continue;

      bool already = false;
      for(int g = 0; g < goneCount; g++)
         if(goneRows[g].key == lastLive[i].key) { already = true; break; }
      if(already) continue;

      if(goneCount >= ArraySize(goneRows)) ArrayResize(goneRows, goneCount + 64);

      // اگر الگو هنوز وجود دارد و فقط از فیلتر افتاده، وضعیت تازه اش نوشته
      // می‌شود؛ اگر کلا باطل شده، آخرین وضعیت شناخته شده می‌ماند.
      int a = -1;
      for(int j = 0; j < nAll; j++)
         if(all[j].key == lastLive[i].key) { a = j; break; }

      if(a >= 0) goneRows[goneCount] = all[a];
      else       goneRows[goneCount] = lastLive[i];

      goneRows[goneCount].goneAt  = now;
      goneRows[goneCount].newMark = "";
      goneCount++;
   }
}

// ردیف های زنده و بعد خاکستری ها، همان چیزی که رسم می‌شود
void BuildPanelRows()
{
   ArrayResize(panelRows, lastLiveCount + goneCount + 1);
   panelRowCount = 0;

   for(int i = 0; i < lastLiveCount; i++)
   {
      panelRows[panelRowCount] = lastLive[i];
      panelRowCount++;
   }

   for(int g = 0; g < goneCount; g++)
   {
      panelRows[panelRowCount] = goneRows[g];
      panelRowCount++;
   }
}

//+------------------------------------------------------------------+
// رسم جدول از روی panelRows. اسکن نمی‌کند، پس می‌شود با تغییر اندازه چارت
// هم صدایش زد — قبلا برای جا شدن ردیف های جدید باید تا اسکن بعدی صبر می‌کردید.
void DrawPanel()
{
   panelLeft = PanelLeftX();
   EnsurePanelBackground();

   int row = 0;
   PanelRow(row, HeaderText(), PanelTitleColor);
   row++;
   PanelRow(row, PadRight("SYMBOL", 11) + PadRight("TF", 5) + PadRight("DIR", 5) +
                 PadRight("STATE", 7) + PadRight("AGE", 5) + PadRight("POS", 6) + "P/L",
            PanelTitleColor);
   row++;

   // سقف نمایش: کمترین مقدار بین ورودی کاربر و آنچه در ارتفاع چارت جا می‌شود.
   // سه ردیف برای سربرگ ها و خط «چند مورد دیگر» کنار گذاشته می‌شود.
   int rowLimit = MaxRowsThatFit() - 3;
   if(rowLimit > PanelMaxRows) rowLimit = PanelMaxRows;
   if(rowLimit < 1) rowLimit = 1;

   ArrayResize(liveSymbol, rowLimit + 4);
   ArrayResize(livePrefix, rowLimit + 4);
   ArrayResize(liveColor,  rowLimit + 4);
   ArrayResize(liveRow,    rowLimit + 4);
   liveCount = 0;

   int shown = 0;

   for(int i = 0; i < panelRowCount && shown < rowLimit; i++)
   {
      string dir = panelRows[i].isBull ? "BULL" : "BEAR";

      // بخش ثابت ردیف جدا نگه داشته می‌شود تا RefreshLive بتواند فقط دو
      // ستون آخر را دوباره بسازد، بدون اینکه کل اسکن تکرار شود.
      string prefix = PadRight(panelRows[i].symbol, 11) +
                      PadRight(TFToStr(panelRows[i].tf), 5) +
                      PadRight(dir, 5) +
                      PadRight(StateTextOf(panelRows[i]), 7) +
                      PadRight(panelRows[i].newMark, 5);

      color rowColor = (panelRows[i].goneAt > 0)
                          ? PanelExpiredColor
                          : (panelRows[i].isBull ? PanelBullColor : PanelBearColor);

      string posMark; double profit; bool hasAny;
      PositionInfo(panelRows[i].symbol, posMark, profit, hasAny);

      PanelRow(row, prefix + PadRight(posMark, 6) + FormatProfit(profit, hasAny), rowColor);

      liveSymbol[liveCount] = panelRows[i].symbol;
      livePrefix[liveCount] = prefix;
      liveColor[liveCount]  = rowColor;
      liveRow[liveCount]    = row;
      liveCount++;

      row++;
      shown++;
   }

   if(scanSymbolCount == 0)
   {
      PanelRow(row, "ScanSymbols is empty - set it, or enable ScanAllMarketWatch",
               PanelTextColor);
      row++;
   }
   else if(panelRowCount == 0)
   {
      PanelRow(row, "(no active pattern)", PanelTextColor);
      row++;
   }
   else if(panelRowCount > shown)
   {
      // فقط تعداد گفتن کمکی نمی‌کرد؛ خود موارد جا مانده هم نوشته می‌شوند تا
      // بدون بزرگ کردن پنجره چارت معلوم باشد چه چیزی بیرون از قاب مانده.
      string more = "";
      for(int i = shown; i < panelRowCount; i++)
      {
         if(StringLen(more) > 46) { more = more + " ..."; break; }
         if(StringLen(more) > 0) more = more + ", ";
         more = more + panelRows[i].symbol + " " + TFToStr(panelRows[i].tf);
      }

      PanelRow(row, "+" + IntegerToString(panelRowCount - shown) + ": " + more,
               PanelTextColor);
      row++;
   }

   ClearRowsFrom(row);
   drawnRows = row;

   SizePanelBackground(row);
   ChartRedraw();
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

            string key = sym + "|" + IntegerToString((int)tf) + "|" +
                         IntegerToString((long)active[k].timeA);

            int seenIdx = SeenIndex(key);

            if(seenIdx < 0)
            {
               // الگوهایی که موقع نصب از قبل روی چارت بودند «تازه» نیستند
               bool alreadyKnown = false;
               seenIdx = RememberSeen(key, GVName(sym, tf, active[k].timeA),
                                      !firstScanDone, alreadyKnown);

               // اولین اسکن فقط ثبت می‌کند، وگرنه لحظه نصب با انبوه
               // اطلاع رسانی از الگوهای قدیمی روبرو می‌شوید. الگویی هم که از
               // نصب قبلی شناخته شده بود دوباره اطلاع نمی‌دهد.
               if(firstScanDone && !alreadyKnown && EnablePush &&
                  PassesFilter(rank, NotifyFilter))
               {
                  SendNotification("ABHunter " + sym + " " + TFToStr(tf) + " " +
                                   (active[k].isBull ? "BULL" : "BEAR") +
                                   " " + StateText(active[k]));
               }
            }

            // اینجا فیلتر جدول اعمال نمی‌شود. همه الگوها نگه داشته می‌شوند تا
            // UpdateGoneList بتواند وضعیت تازه الگویی که از جدول افتاده
            // (مثلا تازه هانت شده) را بخواند.
            if(nRows >= ArraySize(rows)) ArrayResize(rows, nRows + 256);

            rows[nRows].symbol    = sym;
            rows[nRows].symIndex  = si;
            rows[nRows].tf        = tf;
            rows[nRows].tfIndex   = ti;
            rows[nRows].isBull    = active[k].isBull;
            rows[nRows].state     = active[k].state;
            rows[nRows].hasBreak  = active[k].hasValidBreak;
            rows[nRows].rank      = rank;
            rows[nRows].groupRank = rank;
            rows[nRows].key       = key;
            rows[nRows].goneAt    = 0;

            // به جای یک ستاره یکسان، سن الگو نوشته می‌شود تا با یک نگاه معلوم
            // باشد کدام تازه تر است
            rows[nRows].newMark = "";
            if(NewMarkMinutes > 0 && seenFirst[seenIdx] > 0)
            {
               int ageMin = (int)((TimeLocal() - seenFirst[seenIdx]) / 60);
               if(ageMin <= NewMarkMinutes)
                  rows[nRows].newMark = IntegerToString(ageMin) + "m";
            }

            nRows++;
         }
      }
   }

   // ردیف های جدول = آنهایی که از فیلتر رد می‌شوند
   ScanRow live[];
   ArrayResize(live, nRows + 1);
   int nLive = 0;

   for(int i = 0; i < nRows; i++)
   {
      if(!PassesFilter(rows[i].rank, PanelFilter)) continue;
      live[nLive] = rows[i];
      nLive++;
   }

   SortRows(live, nLive);

   // مقایسه با اسکن قبل باید قبل از جایگزینی lastLive انجام شود
   UpdateGoneList(live, nLive, rows, nRows);

   ArrayResize(lastLive, nLive + 1);
   for(int i = 0; i < nLive; i++) lastLive[i] = live[i];
   lastLiveCount = nLive;

   BuildPanelRows();
   DrawPanel();

   firstScanDone = true;
}

//+------------------------------------------------------------------+
int OnInit()
{
   objPrefix = "ABHScan_" + IntegerToString(ChartID()) + "_";

   ArrayResize(seenKeys,  512);
   ArrayResize(seenFirst, 512);
   ArrayResize(goneRows,  64);
   seenCount     = 0;
   goneCount     = 0;
   lastLiveCount = 0;
   panelRowCount = 0;
   firstScanDone = false;
   drawnRows     = 0;

   PruneOldGlobals();

   BuildSymbolList();
   BuildTFList();

   timerTicks = 0;
   liveCount  = 0;
   EventSetTimer(1);   // هر ثانیه؛ اسکن کامل داخل OnTimer شمرده می‌شود

   RunScan();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// فقط سربرگ و دو ستون آخر را تازه می‌کند. سبک است، پس هر ثانیه اجرا می‌شود.
void RefreshLive()
{
   panelLeft = PanelLeftX();
   PanelRow(0, HeaderText(), PanelTitleColor);

   for(int i = 0; i < liveCount; i++)
   {
      string posMark; double profit; bool hasAny;
      PositionInfo(liveSymbol[i], posMark, profit, hasAny);

      PanelRow(liveRow[i], livePrefix[i] + PadRight(posMark, 6) + FormatProfit(profit, hasAny),
               liveColor[i]);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
// تایمر هر ثانیه است ولی اسکن سنگین فقط هر RefreshSeconds ثانیه اجرا می‌شود.
// بین آن ها شمارش معکوس سربرگ و ستون سود و زیان تازه می‌شود.
void OnTimer()
{
   timerTicks++;

   int period = RefreshSeconds;
   if(period < 5) period = 5;

   if(timerTicks >= period)
   {
      timerTicks = 0;
      RunScan();
      return;
   }

   // مهلت ردیف های خاکستری ممکن است وسط دو اسکن تمام شود
   if(PruneGone())
   {
      BuildPanelRows();
      DrawPanel();
      return;
   }

   RefreshLive();
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
{
   // با تغییر اندازه چارت، جدول همان لحظه دوباره چیده می‌شود. قبلا باید تا
   // اسکن بعدی صبر می‌کردید تا تعداد ردیف ها با ارتفاع جدید جور شود.
   if(id == CHARTEVENT_CHART_CHANGE) DrawPanel();
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
