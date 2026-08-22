//+------------------------------------------------------------------+
//|                                     GOD_OF_HUNT_Scanner.mq5   v1.16   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| اسکنر چند نمادی GOD_OF_HUNT.                                         |
//| روی یک چارت اختصاصی نصب می‌شود و همه نمادهای انتخابی را در فهرست   |
//| تایم فریم های دلخواه اسکن می‌کند، جدول الگوهای فعال را نشان می‌دهد |
//| و برای هر AB جدیدی که قطعی شود نوتیفیکیشن موبایل می‌فرستد.         |
//|                                                                  |
//| اسکنر الگو را «رسم» نمی‌کند؛ فقط می‌گوید کجا نگاه کنید. برای دیدن  |
//| خط AB و نقاط A و C و ناحیه اصلاح، چارت همان نماد و تایم فریم را با |
//| اندیکاتور GOD_OF_HUNT.mq5 باز کنید.                                  |
//|                                                                  |
//| قواعد تشخیص از GOD_OF_HUNT_Core.mqh می‌آید — همان فایلی که اندیکاتور   |
//| چارت هم استفاده می‌کند، تا دو نسخه از منطق وجود نداشته باشد.       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.16"
#property indicator_chart_window
#property indicator_plots 0   // هیچ پلاتی ندارد؛ فقط آبجکت رسم می‌کند

#include "GOD_OF_HUNT_Core.mqh"

//---- گوشه ای که جدول در آن قرار می‌گیرد
enum PanelCornerMode
{
   PANEL_TOP_LEFT,   // بالا چپ
   PANEL_TOP_RIGHT   // بالا راست
};

//---- کدام وضعیت ها به حساب بیایند.
//
// روش فراکتالی است: بعد از هانت شدن B در تایم اصلی، سراغ فراکتال پایین تر
// (حدود یک شانزدهم) می‌رویم و آنجا منتظر کندل شکست و کندل سیگنال می‌مانیم.
// پس HUNT و BREAK «شلوغی» نیستند — دقیقا لحظه ای اند که کار شروع می‌شود، و
// باید تا زنده بودن الگو در جدول بمانند. تشکیل C هم لحظه مهم دیگری است.
//
// پیش فرض FILTER_ALL است. دو حالت دیگر برای وقتی است که عمدا بخواهید فقط
// بخشی از چرخه را ببینید.
enum PanelFilterMode
{
   FILTER_PRE_HUNT,   // AB و ABC که B هنوز هانت نشده
   FILTER_COK_ONLY,   // فقط ABC کامل (اصلاح معتبر، منتظر شکست)
   FILTER_ALL         // همه، شامل هانت شده ها
};

// ورودی های خود اسکنر؛ هیچ کدام مخصوص یک الگو نیستند. تنظیمات تشخیص هر
// الگو در GOD_OF_HUNT_Core.mqh است و بالای همین پنجره دیده می‌شود.
input group "=== اسکنر — دامنه اسکن ==="
input string ScanSymbols       = "XAUUSD,DJIUSD,BRNUSD,SPXUSD,NDXUSD,NZDJPY,USDCAD,USDCHF,USDJPY,GBPCHF,GBPJPY,GBPNZD,GBPUSD,EURJPY,EURNZD,EURUSD,GBPAUD,GBPCAD,CHFJPY,EURAUD,EURCAD,EURCHF,EURGBP,AUDCAD,AUDJPY,AUDUSD,CADCHF,CADJPY"; // نمادها با کاما؛ خالی یعنی همه Market Watch
input bool   ScanAllMarketWatch = false; // اگر ScanSymbols خالی بود، همه Market Watch اسکن شود
input string ScanTimeframes    = "H8,H4,H3,H2,H1,M30,M20,M15"; // تایم فریم ها با کاما
input bool   SyncTFWithChart   = false;// به جای فهرست بالا، سه تایم فریم دکمه های چارت خوانده شود
input int    RefreshSeconds    = 60;   // فاصله هر اسکن کامل (ثانیه)؛ شمارش معکوس در سربرگ دیده می‌شود

input group "=== اسکنر — نوتیفیکیشن ==="
input bool   EnablePush        = true; // نوتیفیکیشن موبایل برای هر AB جدید قطعی شده
input PanelFilterMode NotifyFilter = FILTER_ALL;       // برای کدام وضعیت ها اطلاع بدهد

// مقصد کلیک روی ردیف جدول
enum ClickTargetMode
{
   CLICK_OFF,            // کلیک ردیف کاری نکند
   CLICK_HUNTER_CHART,   // چارتی که GOD_OF_HUNT رویش نصب است (اگر نبود، همین چارت)
   CLICK_THIS_CHART,     // همین چارتی که اسکنر رویش است
   CLICK_NEW_CHART       // یک چارت تازه باز شود
};

input group "=== اسکنر — جدول ==="
// الگوی باطل/منقضی (خاکستری) در جدول بیاید یا نه.
//
// روی چارت خاکستری ماندن مفید است — می‌شود بررسی کرد که درست کنار گذاشته
// شده — ولی در جدول فقط شلوغی می‌سازد، چون IB و TICK خیلی متراکم تر از AB
// هستند و تا آخر روز جمع می‌شوند. این ورودی فقط جدول را کنترل می‌کند؛
// نمایش خاکستری روی چارت با ShowDeadPatterns در خود اندیکاتور است.
input bool   ShowDeadInPanel   = false; // ردیف خاکستری (باطل/منقضی) در جدول
input PanelFilterMode PanelFilter = FILTER_ALL;       // کدام وضعیت ها در جدول بیایند
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
input bool   GroupBySymbol     = true; // نمادی که در چند تایم فریم الگو دارد یک ردیف کشویی شود

input group "=== اسکنر — کلیک روی ردیف و همگام سازی ==="
// کلیک روی یک ردیف عادی، چارت را به همان نماد و تایم فریم می‌برد.
// کلیک روی سربرگ گروه (ردیفی که با + یا - شروع می‌شود) کار قبلی اش را
// می‌کند و فقط تایم فریم های آن نماد را باز و بسته می‌کند؛ برای رفتن به
// چارت باید گروه را باز کنید و روی خود تایم فریم کلیک کنید.
input ClickTargetMode ClickTarget = CLICK_HUNTER_CHART; // کلیک روی ردیف چه چارتی را عوض کند
input bool   ClickSetsHunterTF   = true;  // دکمه تایم فریم اندیکاتور هم روی همان تایم فریم تنظیم شود

//---- همگام سازی انتخاب الگوها با چارت اندیکاتور
// خاموش کردن یک الگو روی هر کدام (چارت یا اسکنر) روی دیگری هم اثر می‌کند.
// مرجع، آبجکت وضعیت چارت اندیکاتور است؛ اسکنر هر ثانیه آن را می‌خواند و
// دکمه های خودش هم همانجا می‌نویسند. اگر اسکنر روی پروفایل جدا باشد چارت
// اندیکاتور دیده نمی‌شود (محدودیت ChartFirst/ChartNext) و دکمه های خود
// اسکنر تنها مرجع می‌مانند.
input bool   SyncPatternsWithChart = true;

//+------------------------------------------------------------------+
// یک ردیف جدول
struct ScanRow
{
   string          symbol;
   int             symIndex;   // جای نماد در ScanSymbols، برای گروه بندی
   ENUM_TIMEFRAMES tf;
   int             tfIndex;
   int             pattern;    // PatternId: کدام الگو این ردیف را ساخته
   bool            isBull;
   ABState         state;
   bool            hasBreak;
   int             rank;       // هر چه کمتر، مهم تر
   int             groupRank;  // بهترین رتبه همین نماد
   string          newMark;    // سن الگو به دقیقه، اگر تازه باشد
   string          key;        // شناسه یکتای الگو
   ABDeadReason    dead;       // AB_ALIVE یعنی زنده
   datetime        goneAt;     // 0 یعنی زنده؛ وگرنه لحظه ای که از لیست افتاد
};

string   scanSymbolList[];
int      scanSymbolCount = 0;

ENUM_TIMEFRAMES scanTFList[];
int      scanTFCount = 0;
string   tfSource = "";

// اگر روی چارتی اندیکاتور GOD_OF_HUNT با تنظیمات تشخیص متفاوتی نصب باشد، آن
// چارت الگوهای دیگری می‌بیند و جدول با چارت نمی‌خواند. اینجا فقط علامت
// می‌زنیم؛ سربرگ جدول هشدار می‌دهد.
bool     cfgMismatch = false;

// هر الگو یک بار ثبت می‌شود: هم برای اینکه دوبار نوتیفیکیشن نرود، هم برای
// اینکه بدانیم چه زمانی اولین بار دیده شده.
// زمان با TimeLocal گرفته می‌شود نه TimeCurrent: دومی زمان آخرین تیک سرور است
// و با بازار بسته اصلا جلو نمی‌رود، پس سن همه الگوها صفر می‌ماند و همه برای
// همیشه «تازه» می‌مانند. مقدار 0 یعنی الگو از قبل وجود داشته (اسکن اول).
string   seenKeys[];
datetime seenFirst[];
int      seenRank[];   // آخرین رتبه ای که برایش خبر داده شده
int      seenCount = 0;
bool     firstScanDone = false;   // اولین اسکن فقط ثبت می‌کند و اطلاع نمی‌دهد

// پیشوند متغیرهای سراسری ترمینال. عمدا شناسه چارت در آن نیست: باید بین
// پروفایل ها مشترک باشد تا با عوض کردن پروفایل سن الگوها صفر نشود.
#define GOH_GV_PREFIX "GOHscan_"

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
string   liveGroup[];   // اگر سربرگ گروه باشد، نام نماد؛ وگرنه خالی
string   liveNavSym[]; // نماد واقعی ردیف، برای کلیک (برخلاف liveSymbol هیچ وقت خالی نیست)
ENUM_TIMEFRAMES liveNavTF[];
int      liveCount   = 0;

// نمادهایی که کاربر بازشان کرده است
string   expandedSym[];
int      expandedCount = 0;
int      timerTicks  = 0;
int      panelLeft = 0;   // مختصات چپ جدول، هر بار دوباره حساب می‌شود

// تیک هر الگو: روشن یعنی اسکن بشود. با دکمه های بالا چپ چارت اسکنر عوض
// می‌شود و در یک آبجکت مخفی می‌ماند تا با نصب دوباره یا تغییر تایم فریم
// چارت میزبان از بین نرود.
bool patScan[PATTERN_COUNT];

// --- اسکن سریع تا وقتی داده کامل شود.
//
// متاتریدر تاریخچه هر نماد و تایم فریم را در پس زمینه دانلود می‌کند، پس
// اولین اسکن بعد از نصب معمولا برای بیشتر نمادها داده ندارد و جدول خالی
// می‌ماند. با فاصله عادی اسکن (RefreshSeconds) یعنی یک دقیقه نگاه کردن به
// لیست خالی. تا وقتی داده ناقص است اسکن هر ScanRetrySeconds ثانیه تکرار
// می‌شود، و به محض کامل شدن به فاصله عادی برمی‌گردد.
#define SCAN_RETRY_SECONDS 3
#define SCAN_RETRY_MAX     40   // سقف تلاش سریع، تا نمادِ واقعا بی داده حلقه نسازد

bool scanDataIncomplete = false;   // در آخرین اسکن، جایی داده آماده نبود
int  scanRetriesLeft    = SCAN_RETRY_MAX;
int  scanPeriodNow      = 60;      // فاصله موثر همین چرخه (برای شمارش معکوس سربرگ)

string ScanPatStateObjName()
{
   return "GOHScanPat_" + IntegerToString(ChartID());
}

void SaveScanPatState()
{
   string name = ScanPatStateObjName();

   if(ObjectFind(0, name) < 0)
   {
      if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      {
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
   }

   string txt = "";
   for(int p = 0; p < PATTERN_SCAN_COUNT; p++)
   {
      if(p > 0) txt += "|";
      txt += patScan[p] ? "1" : "0";
   }
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
}

void LoadScanPatState()
{
   for(int p = 0; p < PATTERN_SCAN_COUNT; p++) patScan[p] = true;

   string name = ScanPatStateObjName();
   if(ObjectFind(0, name) < 0) return;

   string parts[];
   int n = StringSplit(ObjectGetString(0, name, OBJPROP_TEXT), '|', parts);
   for(int p = 0; p < PATTERN_SCAN_COUNT && p < n; p++)
      patScan[p] = (StringToInteger(parts[p]) != 0);
}

// دکمه تیک الگو، بالا چپ چارت اسکنر (جدول به طور پیش فرض بالا راست است).
string ScanPatButtonName(int p)
{
   return objPrefix + "PB" + IntegerToString(p);
}

void DrawScanPatternButton(int p)
{
   string name = ScanPatButtonName(p);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   // هندسه بیرون از بلوک ساخت است تا با عوض شدن مانیتور یا UIScalePercent،
   // دکمه ای که از قبل روی چارت مانده هم جابه‌جا و هم‌اندازه شود.
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UiPanelX());
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiBtnY(p));
   ObjectSetInteger(0, name, OBJPROP_XSIZE, UiPx(UI_BTN_W));
   ObjectSetInteger(0, name, OBJPROP_YSIZE, UiPx(UI_BTN_H));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_BTN);

   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, patScan[p] ? clrSeaGreen : clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_COLOR, patScan[p] ? clrWhite : clrSilver);
   ObjectSetString(0, name, OBJPROP_TEXT,
                   (patScan[p] ? "[x] " : "[  ] ") + PatternName(p));
}

void DrawScanPatternButtons()
{
   // سطوح دیلی و سشن فقط رسم اند و اسکن نمی‌شوند، پس دکمه ای هم ندارند
   for(int p = 0; p < PATTERN_SCAN_COUNT; p++)
      DrawScanPatternButton(p);
}

// خواندن انتخاب الگوها از آبجکت وضعیت اولین چارت اندیکاتور. برگشتی یعنی
// چیزی با patScan فرق داشت و اعمال شد (جدول باید از نو ساخته شود).
bool SyncPatternsFromHunterChart()
{
   long id = ChartFirst();

   while(id >= 0)
   {
      string obj = StateObjectName(id);

      if(ObjectFind(id, obj) >= 0)
      {
         string parts[];
         int nParts = StringSplit(ObjectGetString(id, obj, OBJPROP_TEXT), '|', parts);
         if(nParts < 3 + PATTERN_COUNT) return false;   // اندیکاتور نسخه قدیمی

         bool changed = false;
         for(int p = 0; p < PATTERN_SCAN_COUNT; p++)
         {
            bool v = (StringToInteger(parts[3 + p]) != 0);
            if(v != patScan[p]) { patScan[p] = v; changed = true; }
         }

         if(changed)
         {
            SaveScanPatState();
            DrawScanPatternButtons();
         }
         return changed;
      }

      id = ChartNext(id);
   }

   return false;
}

// نوشتن انتخاب الگوهای اسکنر روی آبجکت وضعیت همه چارت های اندیکاتور، تا
// دکمه های آن سمت هم (از OnTimer خودشان) همراه شوند. سه فیلد اول — اندیس
// تایم فریم های هر چارت — دست نمی‌خورند.
void WritePatternsToHunterCharts()
{
   long id = ChartFirst();

   while(id >= 0)
   {
      string obj = StateObjectName(id);

      if(ObjectFind(id, obj) >= 0)
      {
         string parts[];
         int nParts = StringSplit(ObjectGetString(id, obj, OBJPROP_TEXT), '|', parts);

         if(nParts >= 3)
         {
            string txt = parts[0] + "|" + parts[1] + "|" + parts[2];

            // اسکنر فقط صاحب سه تیک اول است. تیک سطوح دیلی و سشن مال
            // اندیکاتور چارت است و اگر اینجا بازنویسی شود، انتخاب کاربر
            // بی سروصدا برمی‌گردد به حالت روشن.
            for(int p = 0; p < PATTERN_SCAN_COUNT; p++)
            {
               txt += "|";
               txt += patScan[p] ? "1" : "0";
            }
            for(int i = 3 + PATTERN_SCAN_COUNT; i < nParts; i++)
               txt += "|" + parts[i];

            ObjectSetString(id, obj, OBJPROP_TEXT, txt);
         }
      }

      id = ChartNext(id);
   }
}

//+------------------------------------------------------------------+
// برای گوشه راست از CORNER_RIGHT_UPPER استفاده نمی‌کنیم، چون آن حالت جهت
// انکر متن ها را برعکس می‌کند و ستون های هم عرض به هم می‌ریزند. به جایش
// مختصات چپ را از عرض چارت حساب می‌کنیم و همه چیز از گوشه بالا چپ می‌ماند.
// ارتفاع یک ردیف جدول. فونت با DPI مانیتور بزرگ می‌شود ولی مختصات پیکسلی
// نه، پس فاصله ردیف ها هم باید با همان ضریب بزرگ شود وگرنه روی هم می‌افتند.
int PanelRowH()
{
   int h = UiPx(PanelFontSize + 7);
   if(h <= 0) h = UiPx(16);
   return h;
}

int PanelLeftX()
{
   if(PanelCorner == PANEL_TOP_LEFT) return UiPx(PanelX);

   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int x = chartW - UiPx(PanelWidth) - UiPx(PanelX);
   if(x < 0) x = 0;
   return x;
}

// چند ردیف در ارتفاع فعلی چارت جا می‌شود
int MaxRowsThatFit()
{
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int rowH   = PanelRowH();

   int fits = (chartH - UiPx(PanelY) - UiPx(24)) / rowH;
   if(fits < 5) fits = 5;
   return fits;
}

//+------------------------------------------------------------------+
// هر چه رتبه کمتر، الگو به معامله نزدیک تر.
int StateRank(SwingAB &s)
{
   if(s.state == AB_INVALID || s.state == AB_DONE) return 5;   // مرده، ته جدول
   if(s.state == AB_BROKEN)       return s.hasValidBreak ? 0 : 1;
   if(s.state == AB_RETRACED)     return 2;
   if(s.state == AB_WAIT_RETRACE) return 3;
   return 4;
}

// rank: 0 = BREAK، 1 = HUNT، 2 = C ok، 3 = WAIT
bool PassesFilter(int rank, PanelFilterMode mode)
{
   if(rank >= 5)               return true;   // مرده: فیلتر وضعیت شاملش نمی‌شود
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
// خواندن سه تایم فریم از چارتی که اندیکاتور GOD_OF_HUNT رویش نصب است.
// اندیکاتور انتخاب دکمه ها را در آبجکت GOH_State_<chartID> نگه می‌دارد.
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
// آیا اندیکاتور روی چارت های باز با همین تنظیمات تشخیص کار می‌کند؟
//
// ورودی های GOD_OF_HUNT_Core.mqh مشترک نوشته شده اند ولی متاتریدر برای هر .mq5
// یک کپی جدا از مقادیرشان نگه می‌دارد. نتیجه اش این است که جدول الگویی را
// گزارش می‌کند که روی چارت وجود ندارد — و هیچ نشانه ای هم دیده نمی‌شود.
void CheckConfigMatch()
{
   cfgMismatch = false;

   string mine = CoreConfigSignature();
   long id = ChartFirst();

   while(id >= 0)
   {
      string obj = ConfigObjectName(id);
      if(ObjectFind(id, obj) >= 0 && ObjectGetString(id, obj, OBJPROP_TEXT) != mine)
      {
         cfgMismatch = true;
         return;
      }
      id = ChartNext(id);
   }
}

//+------------------------------------------------------------------+
// تبدیل رشته به تایم فریم، برای ورودی ScanTimeframes.
// عمدا اینجاست و نه در GOD_OF_HUNT_Core.mqh: تنها مصرف کننده اش همین فایل است و
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

   return GOH_GV_PREFIX + s + "_" + IntegerToString((int)tf) + "_" +
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
      if(StringFind(name, GOH_GV_PREFIX) != 0) continue;

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
int RememberSeen(string key, string gv, bool preExisting, bool &alreadyKnown, int rank)
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
         seenRank[i]  = seenRank[seenCount - keep + i];
      }
      seenCount = keep;
   }

   if(seenCount >= ArraySize(seenKeys))
   {
      ArrayResize(seenKeys,  seenCount + 512);
      ArrayResize(seenFirst, seenCount + 512);
      ArrayResize(seenRank,  seenCount + 512);
   }

   seenKeys[seenCount]  = key;
   seenFirst[seenCount] = first;
   seenRank[seenCount]  = rank;
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
   int height = rows * PanelRowH() + UiPx(14);
   int width  = UiPx(PanelWidth);

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, panelLeft - UiPx(6));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiPx(PanelY) - UiPx(6));
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
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiPx(PanelY) + row * PanelRowH());
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
   int left = scanPeriodNow - timerTicks;
   if(left < 0) left = 0;

   // تعداد نماد و تایم فریم عمدا نوشته نمی‌شود؛ خود شما آن را تنظیم کرده اید.
   // منبع تایم فریم فقط وقتی می‌آید که از چارت خوانده شده باشد، چون آن یکی
   // ممکن است بدون اینکه بدانید عوض شود.
   string src = (tfSource == "inputs") ? "" : "  <- " + tfSource;

   return "GOD_OF_HUNT" + src +
          "   next " + TwoDigits(left / 60) + ":" + TwoDigits(left % 60) +
          (cfgMismatch ? "   !cfg differs from chart" : "");
}

string StateTextOf(ScanRow &r)
{
   // الگوی منقضی شده IB/TICK با AB_DEAD_EXPIRED علامت می‌خورد و مثل الگوی
   // مرده AB علتش نوشته می‌شود ("X old")
   if(r.pattern == PATTERN_INSIDE_BAR)
      return (r.dead != AB_ALIVE) ? DeadReasonText(r.dead) : "IB";
   if(r.pattern == PATTERN_TICK_FRACTAL)
      return (r.dead != AB_ALIVE) ? DeadReasonText(r.dead) : "TICK";
   if(r.dead != AB_ALIVE)     return DeadReasonText(r.dead);
   if(r.state == AB_BROKEN)   return r.hasBreak ? "BREAK" : "HUNT";
   if(r.state == AB_RETRACED) return "C ok";
   return "WAIT";
}

//+------------------------------------------------------------------+
// نمادهایی که کاربر بازشان کرده. حالت باز/بسته بین اسکن ها می‌ماند ولی
// عمدا روی دیسک ذخیره نمی‌شود؛ یک انتخاب لحظه ای است نه تنظیم.
int ExpandedIndex(string sym)
{
   for(int i = 0; i < expandedCount; i++)
      if(expandedSym[i] == sym) return i;
   return -1;
}

bool IsExpanded(string sym)
{
   return (ExpandedIndex(sym) >= 0);
}

void ToggleExpanded(string sym)
{
   int idx = ExpandedIndex(sym);

   if(idx >= 0)
   {
      for(int i = idx; i < expandedCount - 1; i++) expandedSym[i] = expandedSym[i + 1];
      expandedCount--;
      return;
   }

   if(expandedCount >= ArraySize(expandedSym))
      ArrayResize(expandedSym, expandedCount + 32);

   expandedSym[expandedCount] = sym;
   expandedCount++;
}

//+------------------------------------------------------------------+
// یک ردیف داده. بخش ثابت جدا نگه داشته می‌شود تا RefreshLive بتواند فقط دو
// ستون آخر را دوباره بسازد بدون اینکه کل اسکن تکرار شود.
// showPos خاموش یعنی ستون های POS و P/L خالی بمانند — برای زیرمجموعه های یک
// نماد که وضعیت معامله شان با سربرگ یکی است.
void DrawDataRow(ScanRow &r, int row, string symCell, string tfCell,
                 bool isGroup, bool showPos = true)
{
   // الگوی Inside Bar جهت ندارد؛ ستون DIR خنثی و رنگ ردیف رنگ متن جدول است
   string dirCell = (r.pattern == PATTERN_INSIDE_BAR) ? "-"
                                                      : (r.isBull ? "BULL" : "BEAR");

   string prefix = PadRight(symCell, 11) +
                   PadRight(tfCell, 5) +
                   PadRight(dirCell, 5) +
                   PadRight(StateTextOf(r), 7) +
                   PadRight(r.newMark, 5);

   color rowColor = (r.goneAt > 0 || r.dead != AB_ALIVE)
                       ? PanelExpiredColor
                       : (r.pattern == PATTERN_INSIDE_BAR)
                            ? PanelTextColor
                            : (r.isBull ? PanelBullColor : PanelBearColor);

   string posSym = showPos ? r.symbol : "";

   string posMark; double profit; bool hasAny;
   PositionInfo(posSym, posMark, profit, hasAny);

   PanelRow(row, prefix + PadRight(posMark, 6) + FormatProfit(profit, hasAny), rowColor);

   if(liveCount >= ArraySize(liveRow)) return;

   liveSymbol[liveCount] = posSym;
   livePrefix[liveCount] = prefix;
   liveColor[liveCount]  = rowColor;
   liveRow[liveCount]    = row;
   liveGroup[liveCount]  = isGroup ? r.symbol : "";
   liveNavSym[liveCount] = r.symbol;
   liveNavTF[liveCount]  = r.tf;
   liveCount++;
}

//+------------------------------------------------------------------+
// مرتب سازی: اول نمادی که به معامله نزدیک تر است، ولی همه ردیف های یک نماد
// کنار هم. اینطور لازم نیست یک نماد را دو جای جدول دنبال کنید، و در عین حال
// وقتی ردیف ها از ارتفاع چارت بیشتر شدند مهم ترین نمادها بالا می‌مانند.
void SortRows(ScanRow &r[], int n)
{
   // بهترین (کمترین) رتبه هر نماد، جدا برای زنده ها و خاکستری ها
   for(int i = 0; i < n; i++)
   {
      int best = r[i].rank;
      for(int j = 0; j < n; j++)
         if(r[j].symIndex == r[i].symIndex &&
            (r[j].goneAt > 0) == (r[i].goneAt > 0) &&
            (r[j].dead != AB_ALIVE) == (r[i].dead != AB_ALIVE) &&
            r[j].rank < best) best = r[j].rank;
      r[i].groupRank = best;
   }

   for(int i = 0; i < n - 1; i++)
   {
      int best = i;

      for(int j = i + 1; j < n; j++)
      {
         // خاکستری ها همیشه پایین جدول
         bool fadeJ = (r[j].goneAt > 0 || r[j].dead != AB_ALIVE);
         bool fadeB = (r[best].goneAt > 0 || r[best].dead != AB_ALIVE);
         if(fadeJ != fadeB)
         {
            if(!fadeJ) best = j;
            continue;
         }

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
      // ردیفی که خودش با علت ابطال خاکستری شده، مهلت دوم نمی‌گیرد
      if(lastLive[i].goneAt > 0 || lastLive[i].dead != AB_ALIVE) continue;

      // الگویی که تیکش برداشته شده با انتخاب کاربر رفته، نه با ابطال؛
      // ردیف خاکستری «چه چیزی اعتبارش تمام شد» است و اینجا معنا ندارد.
      if(!patScan[lastLive[i].pattern]) continue;

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

   // ردیف های «از لیست افتاده» هم خاکستری اند، پس با همان ورودی کنترل
   // می‌شوند تا جدول یک رفتار یکدست داشته باشد.
   if(!ShowDeadInPanel) return;

   for(int g = 0; g < goneCount; g++)
   {
      // ردیف خاکستری الگویی که بعدا تیکش برداشته شده هم نمایش داده نمی‌شود
      if(!patScan[goneRows[g].pattern]) continue;

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

   ArrayResize(liveGroup,  rowLimit + 4);
   ArrayResize(liveNavSym, rowLimit + 4);
   ArrayResize(liveNavTF,  rowLimit + 4);
   liveCount = 0;

   int shown = 0;
   int i     = 0;   // بیرون از حلقه، چون خط «چند مورد دیگر» به آن نیاز دارد

   while(i < panelRowCount && shown < rowLimit)
   {
      // چند ردیف پشت سر هم برای همین نماد؟ فهرست از قبل بر اساس نماد گروه
      // شده، پس شمردن ردیف های متوالی کافی است. زنده و خاکستری با هم گروه
      // نمی‌شوند تا رنگ ردیف معنایش را از دست ندهد.
      int grp = 1;
      while(i + grp < panelRowCount &&
            panelRows[i + grp].symbol == panelRows[i].symbol &&
            (panelRows[i + grp].goneAt > 0) == (panelRows[i].goneAt > 0) &&
            (panelRows[i + grp].dead != AB_ALIVE) == (panelRows[i].dead != AB_ALIVE)) grp++;

      if(!GroupBySymbol || grp == 1)
      {
         DrawDataRow(panelRows[i], row, panelRows[i].symbol,
                     TFToStr(panelRows[i].tf), false);
         row++; shown++; i++;
         continue;
      }

      // --- سربرگ گروه. ردیف های هر نماد بر اساس رتبه مرتب اند، پس
      //     panelRows[i] همان نزدیک ترین به معامله است و وضعیتش نمایندگی
      //     می‌کند. ستون TF تعداد تایم فریم ها را می‌گوید.
      bool expanded = IsExpanded(panelRows[i].symbol);

      DrawDataRow(panelRows[i], row,
                  (expanded ? "-" : "+") + panelRows[i].symbol,
                  "x" + IntegerToString(grp), true);
      row++; shown++;

      if(expanded)
      {
         for(int k = 0; k < grp && shown < rowLimit; k++)
         {
            // ستون نماد خالی می‌ماند تا زیرمجموعه بودن دیده شود، و POS/PL
            // هم تکرار نمی‌شود چون برای کل نماد یکی است و در سربرگ آمده.
            DrawDataRow(panelRows[i + k], row, "", "  " + TFToStr(panelRows[i + k].tf),
                        false, false);
            row++; shown++;
         }
      }

      i += grp;
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
   else if(i < panelRowCount)
   {
      // فقط تعداد گفتن کمکی نمی‌کرد؛ خود موارد جا مانده هم نوشته می‌شوند تا
      // بدون بزرگ کردن پنجره چارت معلوم باشد چه چیزی بیرون از قاب مانده.
      string more = "";
      for(int k = i; k < panelRowCount; k++)
      {
         if(StringLen(more) > 46) { more = more + " ..."; break; }
         if(StringLen(more) > 0) more = more + ", ";
         more = more + panelRows[k].symbol + " " + TFToStr(panelRows[k].tf);
      }

      PanelRow(row, "+" + IntegerToString(panelRowCount - i) + ": " + more,
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
   CheckConfigMatch();

   scanDataIncomplete = false;   // در طول اسکن، هر داده ناقصی علامتش می‌زند

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
         int n = -1;

         if(patScan[PATTERN_AB_HUNT])
         {
            n = AnalyzeSymbol(sym, tf, ABCDHistoryBars, 30, false, false,
                              rates, rates_total, active);

            // داده هنوز آماده نیست؛ متاتریدر آن را در پس زمینه دانلود می‌کند
            // و اسکن بعدی دوباره امتحان می‌کند. الگوی IB پایین تر خودش داده
            // را جدا می‌گیرد و دوباره امتحان می‌کند.
            if(n < 0) scanDataIncomplete = true;
         }

         for(int k = 0; k < n; k++)
         {
            if(active[k].live) continue;   // هنوز قطعی نشده

            int rank = StateRank(active[k]);

            string key = sym + "|" + IntegerToString((int)tf) + "|" +
                         IntegerToString((long)active[k].timeA);

            int seenIdx = SeenIndex(key);

            // اطلاع رسانی روی «تغییر وضعیت» است، نه فقط اولین رویت.
            //
            // rank دقیقا در همان گذارهایی عوض می‌شود که برای شما مهم اند:
            // WAIT → C ok (الگو آماده شد) و C ok → HUNT → BREAK (وقت رفتن به
            // فراکتال پایین تر). قبلا فقط اولین رویت خبر می‌داد، پس الگویی که
            // به عنوان WAIT دیده شده بود و بعدا هانت می‌شد هیچ وقت خبر دومی
            // نمی‌داد — یعنی مهم ترین لحظه بی صدا می‌گذشت.
            bool notify = false;
            bool isDead = (active[k].state == AB_INVALID || active[k].state == AB_DONE);

            if(seenIdx < 0)
            {
               // الگوهایی که موقع نصب از قبل روی چارت بودند «تازه» نیستند
               bool alreadyKnown = false;
               seenIdx = RememberSeen(key, GVName(sym, tf, active[k].timeA),
                                      !firstScanDone, alreadyKnown, rank);

               // اولین اسکن فقط ثبت می‌کند، وگرنه لحظه نصب با انبوه
               // اطلاع رسانی از الگوهای قدیمی روبرو می‌شوید. الگویی هم که از
               // نصب قبلی شناخته شده بود دوباره اطلاع نمی‌دهد.
               notify = (!alreadyKnown);
            }
            else if(seenRank[seenIdx] != rank)
            {
               seenRank[seenIdx] = rank;
               notify = true;
            }

            // الگوی مرده فقط برای بازرسی در جدول می‌ماند؛ خبر نمی‌دهد
            if(notify && !isDead && firstScanDone && EnablePush &&
               PassesFilter(rank, NotifyFilter))
            {
               SendNotification("GOD_OF_HUNT " + sym + " " + TFToStr(tf) + " " +
                                (active[k].isBull ? "BULL" : "BEAR") +
                                " " + StateText(active[k]));
            }

            // اینجا فیلتر جدول اعمال نمی‌شود. همه الگوها نگه داشته می‌شوند تا
            // UpdateGoneList بتواند وضعیت تازه الگویی که از جدول افتاده
            // (مثلا تازه هانت شده) را بخواند.
            if(nRows >= ArraySize(rows)) ArrayResize(rows, nRows + 256);

            rows[nRows].symbol    = sym;
            rows[nRows].symIndex  = si;
            rows[nRows].tf        = tf;
            rows[nRows].tfIndex   = ti;
            rows[nRows].pattern   = PATTERN_AB_HUNT;
            rows[nRows].isBull    = active[k].isBull;
            rows[nRows].state     = active[k].state;
            rows[nRows].hasBreak  = active[k].hasValidBreak;
            rows[nRows].rank      = rank;
            rows[nRows].groupRank = rank;
            rows[nRows].key       = key;
            rows[nRows].dead      = active[k].deadReason;

            // خاکستری فقط برای الگویی است که واقعا مرده (باطل یا تمام شده) و
            // در UpdateGoneList ثبت می‌شود. الگوی هانت شده زنده است و ردیف
            // عادی می‌گیرد.
            rows[nRows].goneAt = 0;

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

         // --- الگوی INSIDE BAR روی همین نماد و تایم فریم.
         //
         // rank ثابت 4 دارد: پایین تر از همه وضعیت های AB زنده (BREAK=0 تا
         // WAIT=3) و بالاتر از مرده ها (5). یعنی در فیلتر COK_ONLY نمی‌آید و
         // در FILTER_ALL و PRE_HUNT می‌آید.
         if(patScan[PATTERN_INSIDE_BAR])
         {
            InsideBar ibs[];
            int nIB = (n >= 0) ? CollectInsideBars(rates, rates_total, ibs)
                               : AnalyzeInsideBars(sym, tf, ibs);
            if(nIB < 0) scanDataIncomplete = true;

            for(int k = 0; k < nIB; k++)
            {
               // منقضی شده ته جدول می‌رود، مثل الگوی مرده AB
               int rank = ibs[k].expired ? 5 : 4;

               string key = sym + "|" + IntegerToString((int)tf) + "|IB|" +
                            IntegerToString((long)ibs[k].timeChild);

               int seenIdx = SeenIndex(key);
               bool notify = false;

               if(seenIdx < 0)
               {
                  // پسوند I تا اسم متغیر سراسری با AB ای که timeA اش همین
                  // کندل است یکی نشود
                  bool alreadyKnown = false;
                  seenIdx = RememberSeen(key, GVName(sym, tf, ibs[k].timeChild) + "I",
                                         !firstScanDone, alreadyKnown, rank);
                  notify = (!alreadyKnown);
               }

               // IB چرخه عمر و گذار وضعیت ندارد؛ فقط اولین رویت خبر می‌دهد،
               // و الگوی منقضی شده اصلا خبر نمی‌دهد
               if(notify && !ibs[k].expired && firstScanDone && EnablePush &&
                  PassesFilter(rank, NotifyFilter))
               {
                  SendNotification("GOD_OF_HUNT " + sym + " " + TFToStr(tf) + " IB");
               }

               if(nRows >= ArraySize(rows)) ArrayResize(rows, nRows + 256);

               rows[nRows].symbol    = sym;
               rows[nRows].symIndex  = si;
               rows[nRows].tf        = tf;
               rows[nRows].tfIndex   = ti;
               rows[nRows].pattern   = PATTERN_INSIDE_BAR;
               rows[nRows].isBull    = false;   // IB جهت ندارد
               rows[nRows].state     = AB_FORMING;
               rows[nRows].hasBreak  = false;
               rows[nRows].rank      = rank;
               rows[nRows].groupRank = rank;
               rows[nRows].key       = key;
               rows[nRows].dead      = ibs[k].expired ? AB_DEAD_EXPIRED : AB_ALIVE;
               rows[nRows].goneAt    = 0;

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

         // --- الگوی TICK FRACTAL روی همین نماد و تایم فریم.
         //
         // مثل IB رتبه 4 دارد و چرخه عمر ندارد؛ ولی برخلاف IB جهت دارد
         // (جهت سویینگ و شکست) و ستون DIR را عادی پر می‌کند.
         if(patScan[PATTERN_TICK_FRACTAL])
         {
            TickFractal tks[];
            int nTK = (n >= 0) ? CollectTickFractals(rates, rates_total, tks)
                               : AnalyzeTickFractals(sym, tf, tks);
            if(nTK < 0) scanDataIncomplete = true;

            for(int k = 0; k < nTK; k++)
            {
               int rank = tks[k].expired ? 5 : 4;

               string key = sym + "|" + IntegerToString((int)tf) + "|TK|" +
                            IntegerToString((long)tks[k].timeSignal);

               int seenIdx = SeenIndex(key);
               bool notify = false;

               if(seenIdx < 0)
               {
                  bool alreadyKnown = false;
                  seenIdx = RememberSeen(key, GVName(sym, tf, tks[k].timeSignal) + "K",
                                         !firstScanDone, alreadyKnown, rank);
                  notify = (!alreadyKnown);
               }

               if(notify && !tks[k].expired && firstScanDone && EnablePush &&
                  PassesFilter(rank, NotifyFilter))
               {
                  SendNotification("GOD_OF_HUNT " + sym + " " + TFToStr(tf) +
                                   " TICK " + (tks[k].isBull ? "BULL" : "BEAR"));
               }

               if(nRows >= ArraySize(rows)) ArrayResize(rows, nRows + 256);

               rows[nRows].symbol    = sym;
               rows[nRows].symIndex  = si;
               rows[nRows].tf        = tf;
               rows[nRows].tfIndex   = ti;
               rows[nRows].pattern   = PATTERN_TICK_FRACTAL;
               rows[nRows].isBull    = tks[k].isBull;
               rows[nRows].state     = AB_FORMING;
               rows[nRows].hasBreak  = false;
               rows[nRows].rank      = rank;
               rows[nRows].groupRank = rank;
               rows[nRows].key       = key;
               rows[nRows].dead      = tks[k].expired ? AB_DEAD_EXPIRED : AB_ALIVE;
               rows[nRows].goneAt    = 0;

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
   }

   // ردیف های جدول = آنهایی که از فیلتر رد می‌شوند
   ScanRow live[];
   ArrayResize(live, nRows + 1);
   int nLive = 0;

   for(int i = 0; i < nRows; i++)
   {
      // الگوی باطل/منقضی: روی چارت خاکستری می‌ماند، ولی در جدول فقط اگر
      // ShowDeadInPanel روشن باشد
      if(!ShowDeadInPanel && rows[i].dead != AB_ALIVE) continue;

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

   // فاصله تا اسکن بعدی: تا وقتی داده ناقص است کوتاه، بعد عادی
   bool retrying = (scanDataIncomplete && scanRetriesLeft > 0);

   if(retrying)
   {
      scanRetriesLeft--;
      scanPeriodNow = SCAN_RETRY_SECONDS;
   }
   else
   {
      scanPeriodNow = (RefreshSeconds < 5) ? 5 : RefreshSeconds;
   }

   BuildPanelRows();
   DrawPanel();

   // اسکن «اول» یعنی اولین اسکنی که داده اش کامل بوده. اسکن های ناقص فقط
   // ثبت می‌کنند و خبر نمی‌دهند، وگرنه لحظه ای که تاریخچه دانلود می‌شود
   // انبوه نوتیفیکیشن از الگوهای قدیمی می‌آید.
   if(!retrying) firstScanDone = true;
}

//+------------------------------------------------------------------+
int OnInit()
{
   objPrefix = "GOHScan_" + IntegerToString(ChartID()) + "_";

   LoadScanPatState();
   SaveScanPatState();      // اگر آبجکت هنوز نبود، با پیش فرض ساخته شود
   if(SyncPatternsWithChart) SyncPatternsFromHunterChart();
   DrawScanPatternButtons();

   ArrayResize(seenKeys,  512);
   ArrayResize(seenFirst, 512);
   ArrayResize(seenRank,  512);
   ArrayResize(goneRows,  64);
   seenCount     = 0;
   goneCount     = 0;
   expandedCount = 0;
   lastLiveCount = 0;
   panelRowCount = 0;
   firstScanDone = false;
   drawnRows     = 0;

   PruneOldGlobals();

   BuildSymbolList();
   BuildTFList();

   timerTicks       = 0;
   liveCount        = 0;
   scanRetriesLeft  = SCAN_RETRY_MAX;
   scanPeriodNow    = (RefreshSeconds < 5) ? 5 : RefreshSeconds;
   EventSetTimer(1);   // هر ثانیه؛ اسکن کامل داخل OnTimer شمرده می‌شود

   // اسکن همین لحظه، نه بعد از یک دوره تایمر. اگر تاریخچه هنوز دانلود نشده
   // باشد RunScan خودش فاصله بعدی را کوتاه می‌کند تا جدول زود پر شود.
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

   // اگر انتخاب الگوها روی چارت اندیکاتور عوض شده، جدول همان لحظه با
   // انتخاب جدید ساخته می‌شود نه در اسکن بعدی.
   if(SyncPatternsWithChart && SyncPatternsFromHunterChart())
   {
      timerTicks = 0;
      RunScan();
      return;
   }

   if(timerTicks >= scanPeriodNow)
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
// جای یک تایم فریم در یکی از سه لیست دکمه های اندیکاتور. -1 یعنی نیست.
// تعداد عمدا جدا پاس داده می‌شود و از ArraySize روی پارامتر آرایه استفاده
// نمی‌کنیم، تا شیم ++C که برای بررسی نحوی داریم هم بتواند بخواندش.
int IndexInTFList(ENUM_TIMEFRAMES &list[], int count, ENUM_TIMEFRAMES tf)
{
   for(int i = 0; i < count; i++)
      if(list[i] == tf) return i;
   return -1;
}

// دکمه تایم فریم اندیکاتور روی چارت مقصد را روی tf می‌گذارد.
//
// بدون این کار، عوض کردن تایم فریم چارت اغلب به چارت خالی می‌رسد:
// GOD_OF_HUNT فقط وقتی رسم می‌کند که تایم فریم چارت با یکی از سه دکمه اش یکی
// باشد (GetCategory)، و لیست اسکن معمولا تایم فریم های بیشتری دارد.
//
// اندیکاتور این انتخاب را در آبجکت GOH_State_<chartID> نگه می‌دارد و در
// OnInit می‌خواندش. عوض کردن تایم فریم چارت خودش OnInit را دوباره صدا
// می‌زند، پس اگر آبجکت را *قبل* از تعویض بنویسیم، اندیکاتور همان را
// برمی‌دارد. OnDeinit هم فقط موقع حذف یا بسته شدن چارت پاکش می‌کند، نه
// موقع تعویض تایم فریم.
void PointHunterTF(long chartId, ENUM_TIMEFRAMES tf)
{
   string obj = StateObjectName(chartId);
   if(ObjectFind(chartId, obj) < 0) return;

   // فیلدهای بعد از سه اندیس (تیک الگوها از 1.01) باید دست نخورده برگردند،
   // وگرنه هر کلیک روی ردیف جدول انتخاب الگوهای کاربر را ریست می‌کند.
   string txt = ObjectGetString(chartId, obj, OBJPROP_TEXT);
   string parts[];
   int nParts = StringSplit(txt, '|', parts);
   if(nParts < 3) return;

   int i1 = (int)StringToInteger(parts[0]);
   int i2 = (int)StringToInteger(parts[1]);
   int i3 = (int)StringToInteger(parts[2]);

   // بعضی تایم فریم ها در دو لیست هستند (مثلا H1 هم ساختار هم تریگر).
   // اولویت با ساختار است، بعد تریگر، بعد ورود.
   int k = IndexInTFList(StructureTFList, ArraySize(StructureTFList), tf);
   if(k >= 0) i1 = k;
   else
   {
      k = IndexInTFList(TriggerTFList, ArraySize(TriggerTFList), tf);
      if(k >= 0) i2 = k;
      else
      {
         k = IndexInTFList(EntryTFList, ArraySize(EntryTFList), tf);
         if(k < 0) return;   // این تایم فریم روی هیچ دکمه ای نیست
         i3 = k;
      }
   }

   string outTxt = IntegerToString(i1) + "|" + IntegerToString(i2) + "|" +
                   IntegerToString(i3);
   for(int k = 3; k < nParts; k++)
   {
      outTxt += "|";
      outTxt += parts[k];
   }

   ObjectSetString(chartId, obj, OBJPROP_TEXT, outTxt);
}

// بردن چارت به نماد و تایم فریم یک ردیف
void NavigateTo(string sym, ENUM_TIMEFRAMES tf)
{
   if(ClickTarget == CLICK_OFF) return;

   if(ClickTarget == CLICK_NEW_CHART)
   {
      ChartOpen(sym, tf);
      return;   // روی چارت تازه اندیکاتوری نیست، پس تنظیم دکمه معنا ندارد
   }

   long target = 0;   // صفر یعنی همین چارتی که اسکنر رویش است

   if(ClickTarget == CLICK_HUNTER_CHART)
   {
      // اولین چارتی که GOD_OF_HUNT رویش نصب است و خودمان نیستیم.
      // ChartFirst/ChartNext فقط چارت های پروفایل جاری را می‌گردند، پس اگر
      // اسکنر روی پروفایل جدا باشد چیزی پیدا نمی‌شود و به همین چارت
      // برمی‌گردیم.
      long id = ChartFirst();
      while(id >= 0)
      {
         if(id != ChartID() && ObjectFind(id, StateObjectName(id)) >= 0)
         {
            target = id;
            break;
         }
         id = ChartNext(id);
      }
   }

   // مقصد که خود چارت اسکنر باشد، متاتریدر اندیکاتور را دوباره راه اندازی
   // می‌کند: جدول یک لحظه پاک می‌شود و با اسکن بعدی برمی‌گردد.
   if(ClickSetsHunterTF && target != 0) PointHunterTF(target, tf);

   ChartSetSymbolPeriod(target, sym, tf);
   if(target != 0) ChartRedraw(target);
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
{
   // با تغییر اندازه چارت، جدول همان لحظه دوباره چیده می‌شود. قبلا باید تا
   // اسکن بعدی صبر می‌کردید تا تعداد ردیف ها با ارتفاع جدید جور شود.
   if(id == CHARTEVENT_CHART_CHANGE) { DrawPanel(); return; }

   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // دکمه تیک الگو: تغییر انتخاب و اسکن دوباره همان لحظه، نه اسکن بعدی
   string patPrefix = objPrefix + "PB";
   if(StringFind(sparam, patPrefix) == 0)
   {
      int p = (int)StringToInteger(StringSubstr(sparam, StringLen(patPrefix)));
      if(p >= 0 && p < PATTERN_SCAN_COUNT)
      {
         patScan[p] = !patScan[p];
         SaveScanPatState();
         DrawScanPatternButton(p);

         // دکمه های چارت اندیکاتور هم همراه شوند
         if(SyncPatternsWithChart) WritePatternsToHunterCharts();

         timerTicks = 0;
         RunScan();
      }
      return;
   }

   string rowPrefix = objPrefix + "R";
   if(StringFind(sparam, rowPrefix) != 0) return;

   int clicked = (int)StringToInteger(StringSubstr(sparam, StringLen(rowPrefix)));

   for(int i = 0; i < liveCount; i++)
   {
      if(liveRow[i] != clicked) continue;

      // سربرگ گروه (ردیفی که با + یا - شروع می‌شود) فقط باز و بسته می‌کند.
      // عمدا چارت را عوض نمی‌کند تا با کلیک رفتن به چارت قاطی نشود؛ برای
      // نمادی که چند تایم فریم دارد، گروه را باز کنید و روی خود تایم فریم
      // کلیک کنید.
      if(StringLen(liveGroup[i]) > 0)
      {
         ToggleExpanded(liveGroup[i]);
         DrawPanel();
         return;
      }

      NavigateTo(liveNavSym[i], liveNavTF[i]);
      return;
   }
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
