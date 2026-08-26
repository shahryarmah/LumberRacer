//+------------------------------------------------------------------+
//|                                            GOD_OF_HUNT_BT.mq5   v1.18   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.18"
#property indicator_chart_window
#property indicator_plots 0   // هیچ پلاتی ندارد؛ فقط آبجکت رسم می‌کند

// نسخه بک تست.
//
// دقیقا همان اندیکاتور اصلی است، با سه تفاوت:
//   ۱. فقط الگوهایی رسم می‌شوند که در بازه تاریخی انتخاب شده باشند
//   ۲. الگوی مرده خاکستری نمی‌شود؛ همه با رنگ دسته تایم فریم خودشان
//   ۳. تاریخچه عمیق تر گشته می‌شود تا الگوهای قدیمی هم پیدا شوند
//
// همه آبجکت ها پیشوند GBT دارند (نه GOH)، پس می‌شود این را همزمان با
// نسخه زنده روی یک چارت داشت بدون اینکه به هم بریزند. اسکنر هم این را
// نمی‌بیند و انتخاب الگوهایش با نسخه زنده همگام نمی‌شود.
//
// قواعد تشخیص و چرخه عمر مشترک با اسکنر
#include "GOD_OF_HUNT_Core.mqh"

// این اندیکاتور فقط با آبجکت‌های گرافیکی کار می‌کند و هیچ بافری ندارد.

//---- تایم فریم های قابل تغییر با دکمه
ENUM_TIMEFRAMES StructureTF;
ENUM_TIMEFRAMES TriggerTF;
ENUM_TIMEFRAMES EntryTF;

ENUM_TIMEFRAMES prevStructureTF = 0;
ENUM_TIMEFRAMES prevTriggerTF   = 0;
ENUM_TIMEFRAMES prevEntryTF     = 0;

// ورودی ها با input group دسته بندی شده اند تا معلوم باشد هر پارامتر مال
// کدام الگوست. ترتیب نمایش در پنجره تنظیمات = ترتیب اعلان، و چون
// GOD_OF_HUNT_Core.mqh بالاتر include شده، اول دسته های «تشخیص» آن می‌آیند
// و بعد دسته های «رسم» همین فایل.

//==================== بازه بک تست ====================
input group "=== بازه بک تست ==="
// فقط الگوهایی رسم می‌شوند که *کندل شروعشان* در این بازه باشد:
//   AB HUNT      -> کندل A
//   INSIDE BAR   -> کندل فرزند
//   TICK FRACTAL -> کندل سیگنال
// این همان زمانی است که در فایل patterns_H4.csv / patterns_H1.csv ستون
// timeA نوشته شده، پس می‌توانید مستقیم از روی آن فهرست بازه بگذارید.
//
// BtTo برابر صفر یعنی «تا آخرین کندل».
input datetime BtFrom = D'2026.01.01 00:00';  // شروع بازه
input datetime BtTo   = 0;                    // پایان بازه (0 = تا انتها)

//==================== عمومی — مشترک بین هر سه الگو ====================
input group "=== عمومی (هر سه الگو) ==="
// رنگ بر اساس دسته تایم فریم است نه بر اساس الگو، تا وقتی سطوح چند تایم
// فریم روی هم می‌افتند معلوم باشد هر خط مال کدام تایم فریم است.
input color  StructureColor       = clrDeepSkyBlue;  // رنگ تایم فریم ساختار
input color  TriggerColor         = clrOrange;       // رنگ تایم فریم تریگر
input color  EntryColor           = clrViolet;       // رنگ تایم فریم ورود
input bool   EnableAlerts         = false;           // هشدار در لحظات کلیدی (هر سه الگو)
// در نسخه بک تست الگوی مرده خاکستری نمی‌شود و همیشه رسم می‌شود، پس
// ShowDeadPatterns و DeadPatternColor اینجا وجود ندارند.

//==================== AB HUNT — رسم ====================
input group "=== AB HUNT — رسم ==="
input color  LabelColor           = clrBlack; // رنگ لیبل های A و B و C
input int    LineBLength          = 10;   // طول خط ادامه از B (بر حسب کندل)
input int    LineMidLength        = 15;   // طول خط میانی (بر حسب کندل)
input int    LabelShiftCandles    = 1;    // تعداد کندل شیفت لیبل ها
input bool   Show20PercentLine    = true;  // رسم خط حداقل اصلاح (20 درصد)
input bool   ShowMaxRetraceLine   = true;  // رسم خط حداکثر اصلاح (60 درصد)
input bool   ShowStateLabel       = true;  // نمایش وضعیت الگو کنار خط B
input bool   ExtendBLineToNow     = true;  // ادامه خط B تا کندل جاری تا وقتی الگو فعال است
input bool   ShowEntrySignal      = true;  // نمایش فلش سیگنال ورود
input int    FVGExtendCandles     = 10;    // طول کادر FVG (بر حسب کندل)
input bool   ShowFVG              = true;  // رسم کادر FVG داخل AB
// این سه فقط وقتی EnableABCD خاموش است اثر دارند
input int    MaxLookbackStructure = 7;     // کندل ساختار (فقط وقتی ABCD خاموش)
input int    MaxLookbackTrigger   = 15;    // کندل تریگر (فقط وقتی ABCD خاموش)
input int    MaxLookbackEntry     = 30;    // کندل ورود (فقط وقتی ABCD خاموش)
input bool   ShowPreviousABs      = false; // نمایش AB های قبلی (فقط وقتی ABCD خاموش)

//==================== INSIDE BAR — رسم ====================
input group "=== INSIDE BAR — رسم ==="
// تشخیص در GOD_OF_HUNT_Core است (IBMaxAgeCandles)؛ اینها فقط رسم اند.
input int    IBLineCandles        = 5;    // طول خط ها بعد از کندل فرزند (بر حسب کندل)
input bool   IBShowChildLines     = true; // خطوط های و لوی کندل فرزند هم رسم شود

//==================== TICK FRACTAL — رسم و لاگ ====================
input group "=== TICK FRACTAL — رسم و لاگ ==="
// تشخیص در GOD_OF_HUNT_Core است (Tick*)؛ اینها فقط رسم و عیب یابی اند.
// رنگ خط تیک هم مثل AB و INSIDE BAR رنگ دسته تایم فریم است، پس ورودی رنگ
// جدا ندارد: رنگ می‌گوید کدام تایم فریم، شکل می‌گوید کدام الگو.
input int    TickLineWidth        = 2;          // ضخامت خط تیک
// لاگ: برای هر Inside Bar در محدوده اسکن می‌نویسد که چرا تیک نشد (یا شد)،
// در تب Experts. برای وقتی که الگویی با چشم دیده می‌شود ولی رد شده است.
input bool   TickDebugLog         = false; // نوشتن علت رد شدن کاندیدها در Experts
input int    TickDebugBars        = 200;   // فقط این تعداد کندل آخر لاگ شود

//==================== نمایشگرهای چارت ====================
input group "=== نمایشگرهای چارت (بی ربط به الگوها) ==="
input bool   ShowCandleTimer      = true;      // نمایش زمان باقی مانده تا بسته شدن کندل
input color  CandleTimerColor     = clrGray;   // رنگ تایمر
// تایم فریم فراکتال زیر تایمر: بعد از هانت شدن B روی این تایم فریم، برای
// کندل شکست و کندل سیگنال باید به این تایم فریم پایین تر رفت.
input bool   ShowFractalTF        = true;         // نمایش تایم فریم فراکتال زیر تایمر
input color  FractalTFColor       = clrSteelBlue; // رنگ تایم فریم فراکتال
// سشن: کدام سشن ها باز اند و چقدر تا تغییر بعدی مانده. مبنا ساعت GMT است نه
// ساعت سرور بروکر، چون ساعت سرور از بروکری به بروکر دیگر فرق می‌کند ولی
// جدول سشن ها همه جا با GMT نوشته می‌شود.
input bool   ShowSession          = true;          // نمایش سشن معاملاتی زیر تایمر
input color  SessionColor         = clrDarkOrange; // رنگ سشن

input group "=== ساعت سشن ها به وقت GMT ==="
// اگر تقویم تابستانی جابجایشان کرد، همین جا یک ساعت عقب/جلو ببرید.
input int    SydneyOpenGMT        = 21;
input int    SydneyCloseGMT       = 6;
input int    TokyoOpenGMT         = 0;
input int    TokyoCloseGMT        = 9;
input int    LondonOpenGMT        = 7;
input int    LondonCloseGMT       = 16;
input int    NewYorkOpenGMT       = 12;
input int    NewYorkCloseGMT      = 21;

//==================== سطوح دیلی و سشن ====================
input group "=== سطوح افقی (دیلی و سشن) ==="
// این ها «الگو» نیستند، «سطح» اند: یک قیمت ثابت که در مرز روز یا مرز سشن
// یک بار حساب می‌شود و تا پایان روز جاری سر جایش می‌ماند. برای همین هم
// بازحسابشان به تغییر روز/سشن گره خورده، نه به هر تیک.
input color  DailyLevelColor    = clrCrimson;      // های و لوی کندل دیروز
input color  SydneyLevelColor   = clrDarkGreen;
input color  TokyoLevelColor    = clrSaddleBrown;
input color  LondonLevelColor   = clrNavy;
input color  NewYorkLevelColor  = clrDarkMagenta;
input color  PatternBtnColor    = clrDarkSlateBlue; // رنگ دکمهٔ PATTERNS، جدا از دکمه های تایم فریم
input int    LevelLineWidth     = 1;
input bool   ShowLevelLabels    = true;            // برچسب کوتاه انتهای خط
input ENUM_TIMEFRAMES SessionLevelsMaxTF = PERIOD_H4; // سطح سشن فقط تا این تایم فریم
input ENUM_TIMEFRAMES SessionDataTF      = PERIOD_H1; // منبع های/لوی داخل سشن

// الگوی مرده/منقضی بی سروصدا حذف نمی‌شود؛ تا انتهای همان روز خاکستری روی
// چارت می‌ماند و علت ابطالش نوشته می‌شود، تا بشود بررسی کرد که اندیکاتور
// درست حذفش کرده یا نه. ورودی هایش در دسته «عمومی» بالا هستند.

//+------------------------------------------------------------------+
enum TFCategory { STRUCTURE, TRIGGER, ENTRY, NONE };

// اندیس فعلی در لیست ها
int idxStructure = 3;   // H4
int idxTrigger   = 2;   // M20
int idxEntry     = 8;   // M1

// تیک هر الگو: روشن یعنی رسم بشود. با دکمه عوض می‌شود و مثل اندیس دکمه های
// تایم فریم در آبجکت مخفی وضعیت ذخیره می‌شود، چون OnInit با هر تغییر تایم
// فریم دوباره اجرا می‌شود و متغیر سراسری صفر می‌شود.
bool patternOn[PATTERN_COUNT];

#define LEVEL_PREFIX "gohlv_"

// وضعیت کش شده. تا وقتی این ها عوض نشده اند هیچ آبجکتی دست نمی‌خورد.
datetime lvlDayStart   = 0;                  // کندل D1 جاری که سطوح با آن رسم شد
datetime lvlSessDrawn[SESSION_COUNT];        // زمان بستهٔ سشنی که رسم شده
bool     lvlOnDrawn[PATTERN_COUNT];          // تیک هر سطح در زمان رسم

//+------------------------------------------------------------------+
int SessionOpenGMT(int idx)
{
   if(idx == 0) return SydneyOpenGMT;
   if(idx == 1) return TokyoOpenGMT;
   if(idx == 2) return LondonOpenGMT;
   return NewYorkOpenGMT;
}

int SessionCloseGMT(int idx)
{
   if(idx == 0) return SydneyCloseGMT;
   if(idx == 1) return TokyoCloseGMT;
   if(idx == 2) return LondonCloseGMT;
   return NewYorkCloseGMT;
}

color SessionLevelColor(int idx)
{
   if(idx == 0) return SydneyLevelColor;
   if(idx == 1) return TokyoLevelColor;
   if(idx == 2) return LondonLevelColor;
   return NewYorkLevelColor;
}

//+------------------------------------------------------------------+
// یک خط افقی سطح، به علاوهٔ برچسب کوتاهش.
void DrawLevelLine(string id, datetime from, datetime to, double price,
                   color clr, string tag)
{
   string ln = LEVEL_PREFIX + id;
   if(ObjectFind(0, ln) >= 0) ObjectDelete(0, ln);
   ObjectCreate(0, ln, OBJ_TREND, 0, from, price, to, price);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, ln, OBJPROP_WIDTH, LevelLineWidth);
   ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);

   string tx = ln + "_T";
   if(ObjectFind(0, tx) >= 0) ObjectDelete(0, tx);
   if(!ShowLevelLabels) return;

   ObjectCreate(0, tx, OBJ_TEXT, 0, to, price);
   ObjectSetInteger(0, tx, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, tx, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, tx, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, tx, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, tx, OBJPROP_TEXT, tag + " ");
}

void DeleteLevelGroup(string id)
{
   string ln = LEVEL_PREFIX + id;
   ObjectDelete(0, ln);
   ObjectDelete(0, ln + "_T");
}

//+------------------------------------------------------------------+
// پنجرهٔ سشن برای روزی که کندل روزانه اش از dayStart شروع می‌شود، به وقت سرور.
//
// ساعت سشن ها GMT است ولی کندل روزانه و محور زمان چارت به وقت سرور کارگزار
// هستند. اگر مبنا را نیمه شب GMT بگیریم، روی کارگزاری که مثلا GMT+3 است
// پنجره تا یک روز جابه‌جا می‌شود و خط سشن روی روز بعد می‌افتد. پس ساعت GMT
// اول به «ثانیهٔ روز به وقت سرور» تبدیل می‌شود و از همان dayStart که خط
// رویش کشیده می‌شود شمرده می‌شود.
//
// سشنی که از روز قبل شروع شده و در این روز بسته می‌شود (مثل سیدنی) درست
// درمی‌آید، چون مبنا لحظهٔ بسته شدن است و fromSrv می‌تواند عقب تر برود.
bool SessionWindowOfDay(int idx, datetime dayStart, datetime &fromSrv, datetime &toSrv)
{
   datetime gmtNow = TimeGMT();
   if(gmtNow == 0) return false;

   long shift = (long)gmtNow - (long)TimeCurrent();   // سرور + shift = GMT

   int openH  = SessionOpenGMT(idx);
   int closeH = SessionCloseGMT(idx);
   int durH   = (closeH - openH + 24) % 24;
   if(durH == 0) durH = 24;

   // لنگر روی *بسته شدن* سشن: سشن مال روزی است که در آن بسته می‌شود.
   // این همان چیزی است که موقع معامله لازم است — های/لوی سشنی که همین
   // امروز تمام شده. fromSrv می‌تواند به روز قبل برود (سیدنی) و مشکلی نیست.
   //
   // اگر بسته شدن دقیقا روی نیمه شب سرور بیفتد (نیویورک روی کارگزار GMT+3)
   // باقیمانده صفر می‌شود؛ آن را انتهای همین روز می‌گیریم نه ابتدایش، وگرنه
   // آن سشن یک روز عقب می‌افتاد.
   long closeOfDay = ((long)closeH * 3600 - shift) % 86400;
   if(closeOfDay <= 0) closeOfDay += 86400;

   toSrv   = (datetime)((long)dayStart + closeOfDay);
   fromSrv = (datetime)((long)toSrv - (long)durH * 3600);
   return true;
}

// بیشترین های و کمترین لوی بازهٔ داده شده، از SessionDataTF.
// ساعت باز/بستهٔ سشن ها عدد صحیح اند، پس H1 دقیقا روی مرز می‌افتد و
// های/لوی واقعی سشن را می‌دهد.
bool RangeHighLow(datetime fromSrv, datetime toSrv, double &hi, double &lo)
{
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, SessionDataTF, fromSrv, toSrv - 1, r);
   if(n <= 0) return false;                           // داده آماده نیست

   hi = r[0].high;
   lo = r[0].low;
   for(int i = 1; i < n; i++)
   {
      if(r[i].high > hi) hi = r[i].high;
      if(r[i].low  < lo) lo = r[i].low;
   }
   return true;
}


//+------------------------------------------------------------------+
// نسخهٔ بک‌تست: به جای فقط روز جاری، برای *هر روز* داخل بازهٔ انتخابی رسم
// می‌شود. بازه از ورودی می‌آید و بدون بارگذاری دوباره عوض نمی‌شود، پس یک
// بار حساب می‌شود و تا وقتی بازه و تیک ها ثابت اند هیچ آبجکتی دست نمی‌خورد.
string lvlRangeSig = "";

void DeleteAllLevels()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, LEVEL_PREFIX) == 0) ObjectDelete(0, nm);
   }
}

void UpdateLevels()
{
   string sig = IntegerToString((long)BtFrom) + "/" + IntegerToString((long)BtTo) +
                "/" + IntegerToString(Period());
   for(int p = PATTERN_DAILY_HL; p < PATTERN_COUNT; p++)
      sig += patternOn[p] ? "1" : "0";
   if(sig == lvlRangeSig) return;

   DeleteAllLevels();
   lvlRangeSig = sig;

   datetime fromT = 0, toT = 0;
   BtDataRange(PERIOD_D1, fromT, toT);

   MqlRates d1[];
   ArraySetAsSeries(d1, false);
   int nd = CopyRates(_Symbol, PERIOD_D1, fromT, toT, d1);
   if(nd < 2) { lvlRangeSig = ""; return; }   // داده آماده نیست، دوباره تلاش شود

   bool dailyOn     = patternOn[PATTERN_DAILY_HL];
   bool sessAllowed = (Period() <= (int)SessionLevelsMaxTF);

   // d1[k] روز جاری، d1[k-1] روز قبلش
   for(int k = 1; k < nd; k++)
   {
      datetime dayStart = d1[k].time;
      datetime dayEnd   = dayStart + PeriodSeconds(PERIOD_D1);
      if(!InBtRange(dayStart)) continue;

      string sfx = IntegerToString((long)dayStart);

      if(dailyOn)
      {
         DrawLevelLine("DH" + sfx, dayStart, dayEnd, d1[k-1].high, DailyLevelColor, "PDH");
         DrawLevelLine("DL" + sfx, dayStart, dayEnd, d1[k-1].low,  DailyLevelColor, "PDL");
      }

      if(!sessAllowed) continue;

      for(int i = 0; i < SESSION_COUNT; i++)
      {
         int p = PATTERN_SESS_FIRST + i;
         if(!patternOn[p]) continue;

         // همان پنجره ای که نسخهٔ زنده استفاده می‌کند، گره خورده به روز کارگزار
         datetime a = 0, b = 0;
         if(!SessionWindowOfDay(i, dayStart, a, b)) continue;

         double hi = 0.0, lo = 0.0;
         if(!RangeHighLow(a, b, hi, lo)) continue;

         string tag = SessionShort(i);
         color  clr = SessionLevelColor(i);
         DrawLevelLine("S" + IntegerToString(i) + "H" + sfx, dayStart, dayEnd, hi, clr, tag + " H");
         DrawLevelLine("S" + IntegerToString(i) + "L" + sfx, dayStart, dayEnd, lo, clr, tag + " L");
      }
   }
}


//--- آبجکت ذخیره سازی محلی مخصوص این چارت
string stateObjName;

//+------------------------------------------------------------------+
// متغیرهای مدیریت وضعیت لیست ها
bool isStructureListOpen = false;
bool isTriggerListOpen   = false;
bool isEntryListOpen     = false;

// وضعیت آخرین بارگذاری، برای برچسب اطلاعات روی چارت
datetime btLoadFrom = 0, btLoadTo = 0;
int      btLoadBars = 0;
int      btDrawn    = 0;

// کنترل بازترسیم
datetime lastBarTime       = 0;
bool     forceRedraw       = true;
string   lastConfirmedSig  = "";

// همان کاهش رفت و برگشت نسخهٔ اصلی. اینجا حتی مهم تر است، چون نسخهٔ بک‌تست
// یک بازهٔ تاریخی کامل رسم می‌کند و آبجکت هایش بیشتر است.
string   staleLayoutSig    = "";
bool     hadLiveObjects    = false;

string StaleLayoutSignature()
{
   return IntegerToString(Period())         + "/" +
          IntegerToString((int)StructureTF) + "/" +
          IntegerToString((int)TriggerTF)   + "/" +
          IntegerToString((int)EntryTF);
}

//+------------------------------------------------------------------+
TFCategory GetCategory()
{
   int tf = Period();
   if(tf == StructureTF) return STRUCTURE;
   if(tf == TriggerTF)   return TRIGGER;
   if(tf == EntryTF)     return ENTRY;
   return NONE;
}

color GetCategoryColor(TFCategory cat)
{
   if(cat == STRUCTURE) return StructureColor;
   if(cat == TRIGGER)   return TriggerColor;
   if(cat == ENTRY)     return EntryColor;
   return clrGray;
}

// آیا این دسته چرخه عمر ABCD را دنبال می‌کند؟
// هر سه دسته دنبال می‌کنند، چون کار به صورت فراکتالی است و تشخیص کندل شکست و
// سیگنال ورود دقیقا در تایم پایین لازم است. تفاوت تایم ورود در این است که
// فقط آخرین AB را نگه می‌دارد (در ProcessIndicator اعمال می‌شود).
bool UsesLifecycle(TFCategory cat)
{
   return EnableABCD;
}

// پیشوند نام آبجکت ها: <cat>_<tf>_
string GetTFPrefix(TFCategory cat, ENUM_TIMEFRAMES tf)
{
   string catStr = (cat == STRUCTURE) ? "gbtst_" : (cat == TRIGGER) ? "gbttr_" : (cat == ENTRY) ? "gbten_" : "gbtxx_";
   return catStr + IntegerToString((int)tf) + "_";
}

// نام پایه یک سویینگ.
// سویینگ زنده نام ثابت "L" می‌گیرد تا هر بار جایگزین قبلی شود.
// سویینگ قطعی شده با زمان کندل A نام می‌گیرد؛ زمان برخلاف ایندکس آرایه پایدار است.
string SwingBaseName(TFCategory cat, ENUM_TIMEFRAMES tf, SwingAB &s)
{
   if(s.live) return GetTFPrefix(cat, tf) + "L";
   return GetTFPrefix(cat, tf) + "C" + IntegerToString((long)s.timeA);
}

void DeleteByPrefix(string prefix)
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DeleteObjectsOfTF(TFCategory cat, ENUM_TIMEFRAMES tf)
{
   DeleteByPrefix(GetTFPrefix(cat, tf));
}

void DeleteLiveObjectsOfTF(TFCategory cat, ENUM_TIMEFRAMES tf)
{
   DeleteByPrefix(GetTFPrefix(cat, tf) + "L_");
}

// آیا این آبجکت مال این الگوست؟
//
// قالب نام: <cat>_<tf>_<mark>...  و نشانه الگو بعد از دومین آندرلاین است:
//   AB HUNT      -> "L" (سویینگ زنده) یا "C" (قطعی شده)
//   INSIDE BAR   -> "IB"
//   TICK FRACTAL -> "TK"
bool ObjectBelongsToPattern(string name, int p)
{
   if(StringFind(name, LEVEL_PREFIX) == 0)
   {
      string rest = StringSubstr(name, StringLen(LEVEL_PREFIX));
      if(p == PATTERN_DAILY_HL) return (StringSubstr(rest, 0, 1) == "D");
      if(IsSessionLevel(p))
         return (StringSubstr(rest, 0, 2) == "S" +
                 IntegerToString(p - PATTERN_SESS_FIRST));
      return false;
   }

   if(StringFind(name, "gbtst_") != 0 &&
      StringFind(name, "gbttr_") != 0 &&
      StringFind(name, "gbten_") != 0) return false;

   int p1 = StringFind(name, "_");
   int p2 = (p1 >= 0) ? StringFind(name, "_", p1 + 1) : -1;
   if(p2 < 0) return false;

   string mark2 = StringSubstr(name, p2 + 1, 2);
   string mark1 = StringSubstr(name, p2 + 1, 1);

   if(p == PATTERN_INSIDE_BAR)   return (mark2 == "IB");
   if(p == PATTERN_TICK_FRACTAL) return (mark2 == "TK");
   if(p == PATTERN_AB_HUNT)      return (mark1 == "L" || mark1 == "C");
   return false;
}

// آبجکت های هر الگوی خاموش را در همه دسته ها و تایم فریم ها پاک می‌کند.
//
// پاک کردن دسته و تایم فریم جاری (کاری که ProcessIndicator می‌کند) کافی
// نیست: آبجکت تایم فریم های بالاتر عمدا روی چارت می‌ماند تا کار فراکتالی
// ممکن باشد، پس با خاموش کردن یک الگو باید صریح سراغشان رفت. وگرنه
// خطوطی که در تایم فریم دیگری رسم شده اند تا ابد روی چارت می‌مانند.
//
// فقط موقع تغییر انتخاب صدا زده می‌شود، نه در هر تیک تایمر.
void DeleteOffPatternObjects()
{
   int total = ObjectsTotal(0);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      for(int p = 0; p < PATTERN_COUNT; p++)
      {
         if(patternOn[p]) continue;
         if(!ObjectBelongsToPattern(name, p)) continue;

         ObjectDelete(0, name);
         break;
      }
   }
}

void CheckTFChangeAndDelete()
{
   if(prevStructureTF != StructureTF)
   {
      if(prevStructureTF != 0) DeleteObjectsOfTF(STRUCTURE, prevStructureTF);
      prevStructureTF = StructureTF;
      forceRedraw = true;
   }

   if(prevTriggerTF != TriggerTF)
   {
      if(prevTriggerTF != 0) DeleteObjectsOfTF(TRIGGER, prevTriggerTF);
      prevTriggerTF = TriggerTF;
      forceRedraw = true;
   }

   if(prevEntryTF != EntryTF)
   {
      if(prevEntryTF != 0) DeleteObjectsOfTF(ENTRY, prevEntryTF);
      prevEntryTF = EntryTF;
      forceRedraw = true;
   }
}

//+------------------------------------------------------------------+
// هایلایت کردن تایم فریم انتخاب شده در لیست
void HighlightSelectedTF(TFCategory cat, int selectedIdx)
{
   string prefix;
   int count = 0;

   if(cat == STRUCTURE)   { prefix = "GBT_ListSt_"; count = ArraySize(StructureTFList); }
   else if(cat == TRIGGER){ prefix = "GBT_ListTr_"; count = ArraySize(TriggerTFList);   }
   else if(cat == ENTRY)  { prefix = "GBT_ListEn_"; count = ArraySize(EntryTFList);     }
   else return;

   for(int i = 0; i < count; i++)
   {
      string btnName = prefix + IntegerToString(i);
      if(ObjectFind(0, btnName) >= 0)
      {
         ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrDarkSlateGray);
         ObjectSetInteger(0, btnName, OBJPROP_COLOR, clrWhite);
      }
   }

   string selBtn = prefix + IntegerToString(selectedIdx);
   if(ObjectFind(0, selBtn) >= 0)
   {
      ObjectSetInteger(0, selBtn, OBJPROP_BGCOLOR, clrGold);
      ObjectSetInteger(0, selBtn, OBJPROP_COLOR, clrBlack);
   }
}

string ListPrefix(TFCategory cat)
{
   return (cat == STRUCTURE) ? "GBT_ListSt_" : (cat == TRIGGER) ? "GBT_ListTr_" : "GBT_ListEn_";
}

void ShowTFList(TFCategory cat, int x, int y)
{
   string prefix;
   ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
   int count = 0;
   int selectedIdx = 0;

   if(cat == STRUCTURE)    { prefix = "GBT_ListSt_"; count = ArraySize(StructureTFList); selectedIdx = idxStructure; }
   else if(cat == TRIGGER) { prefix = "GBT_ListTr_"; count = ArraySize(TriggerTFList);   selectedIdx = idxTrigger;   }
   else if(cat == ENTRY)   { prefix = "GBT_ListEn_"; count = ArraySize(EntryTFList);     selectedIdx = idxEntry;     }
   else return;

   for(int i = 0; i < count; i++)
   {
      if(cat == STRUCTURE)    tf = StructureTFList[i];
      else if(cat == TRIGGER) tf = TriggerTFList[i];
      else if(cat == ENTRY)   tf = EntryTFList[i];

      string btnName = prefix + IntegerToString(i);
      if(ObjectFind(0, btnName) < 0)
      {
         if(!ObjectCreate(0, btnName, OBJ_BUTTON, 0, 0, 0)) continue;
      }

      ObjectSetInteger(0, btnName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, y + UiPx(UI_LIST_ROW) * i);
      ObjectSetInteger(0, btnName, OBJPROP_XSIZE, UiPx(UI_BTN_W));
      ObjectSetInteger(0, btnName, OBJPROP_YSIZE, UiPx(UI_BTN_H));
      ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE, UI_FONT_BTN);
      ObjectSetInteger(0, btnName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrDodgerBlue);
      ObjectSetInteger(0, btnName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, btnName, OBJPROP_STATE, false);
      ObjectSetString(0, btnName, OBJPROP_TEXT, TFToStr(tf));
   }

   HighlightSelectedTF(cat, selectedIdx);
   ChartRedraw();
}

void HideTFList(TFCategory cat)
{
   if(cat == NONE) return;
   DeleteByPrefix(ListPrefix(cat));
   ChartRedraw();
}
//+------------------------------------------------------------------+

void SaveState()
{
   if(StringLen(stateObjName) == 0) return;

   string txt = IntegerToString(idxStructure) + "|" +
                IntegerToString(idxTrigger)   + "|" +
                IntegerToString(idxEntry);

   // تیک الگوها بعد از سه اندیس تایم فریم. آبجکت قدیمی که این فیلدها را
   // ندارد هم باید خوانده شود، پس موقع خواندن پیش فرض «همه روشن» است.
   for(int p = 0; p < PATTERN_COUNT; p++)
   {
      txt += "|";
      txt += patternOn[p] ? "1" : "0";
   }

   if(ObjectFind(0, stateObjName) < 0)
   {
      if(ObjectCreate(0, stateObjName, OBJ_LABEL, 0, 0, 0))
      {
         ObjectSetInteger(0, stateObjName, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, stateObjName, OBJPROP_SELECTABLE, false);
      }
   }
   ObjectSetString(0, stateObjName, OBJPROP_TEXT, txt);

   // اثر انگشت تنظیمات تشخیص، تا اسکنر بتواند بفهمد با همان قواعد کار می‌کند
   // یا نه. ورودی های GOD_OF_HUNTCore برای هر نصب جدا ذخیره می‌شوند، پس این دو
   // می‌توانند بی سروصدا از هم فاصله بگیرند.
   string cfgName = "GBT_Cfg_" + IntegerToString(ChartID());
   if(ObjectFind(0, cfgName) < 0)
   {
      if(ObjectCreate(0, cfgName, OBJ_LABEL, 0, 0, 0))
      {
         ObjectSetInteger(0, cfgName, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, cfgName, OBJPROP_SELECTABLE, false);
      }
   }
   ObjectSetString(0, cfgName, OBJPROP_TEXT, CoreConfigSignature());
}

//+------------------------------------------------------------------+
void CreateTFButton(string name, int x, int y, string text)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, UiPx(UI_BTN_W));
   ObjectSetInteger(0, name, OBJPROP_YSIZE, UiPx(UI_BTN_H));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_BTN);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrDodgerBlue);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
// دکمه تیک هر الگو، زیر سه دکمه تایم فریم. سبز یعنی روشن (رسم می‌شود)،
// خاکستری یعنی خاموش. متن هم تیک دارد تا به رنگ تنها تکیه نشود.
string PatternButtonName(int p)
{
   return "GBT_BtnPat" + IntegerToString(p) + "_" + IntegerToString(ChartID());
}

// هشت الگو/سطح داریم و هشت دکمه چارت را می‌پوشاند. پس مثل دکمه های تایم
// فریم، یک دکمهٔ «PATTERNS» داریم که لیستی باز می‌کند.
//
// تفاوت با لیست تایم فریم: آنجا یکی انتخاب می‌شود و لیست بسته می‌شود،
// اینجا چند تیک مستقل اند پس لیست باز می‌ماند تا دوباره روی PATTERNS
// کلیک شود.
bool isPatternListOpen = false;

string PatternHeadButtonName()
{
   return "GBT_BtnPatHead_" + IntegerToString(ChartID());
}

void DrawPatternHeadButton()
{
   string name = PatternHeadButtonName();

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UiPanelX());
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiBtnY(3));
   ObjectSetInteger(0, name, OBJPROP_XSIZE, UiPx(UI_BTN_W));
   ObjectSetInteger(0, name, OBJPROP_YSIZE, UiPx(UI_BTN_H));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_BTN);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, PatternBtnColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);

   int on = 0;
   for(int p = 0; p < PATTERN_COUNT; p++) if(patternOn[p]) on++;
   ObjectSetString(0, name, OBJPROP_TEXT,
                   "PATTERNS (" + IntegerToString(on) + "/" +
                   IntegerToString(PATTERN_COUNT) + ")");
}

// یک ردیف لیست الگوها. فقط وقتی لیست باز است ساخته می‌شود.
void DrawPatternButton(int p)
{
   if(!isPatternListOpen) return;

   string name = PatternButtonName(p);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UiListX());
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiBtnY(0) + UiPx(UI_LIST_ROW) * p);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, UiPx(UI_BTN_W));
   ObjectSetInteger(0, name, OBJPROP_YSIZE, UiPx(UI_BTN_H));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_BTN);

   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, patternOn[p] ? clrSeaGreen : clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_COLOR, patternOn[p] ? clrWhite : clrSilver);
   ObjectSetString(0, name, OBJPROP_TEXT,
                   (patternOn[p] ? "[x] " : "[  ] ") + PatternName(p));
}

void DrawPatternButtons()
{
   DrawPatternHeadButton();
   for(int p = 0; p < PATTERN_COUNT; p++)
      DrawPatternButton(p);
}

void HidePatternList()
{
   isPatternListOpen = false;
   for(int p = 0; p < PATTERN_COUNT; p++)
      ObjectDelete(0, PatternButtonName(p));
   DrawPatternHeadButton();
}

// آبجکت وضعیت مرجع مشترک انتخاب الگوهاست: اسکنر هم می‌تواند در آن بنویسد
// (دکمه های خودش)، پس هر ثانیه خوانده می‌شود و اگر با حافظه فرق داشت اعمال
// می‌شود. برگشتی یعنی چیزی عوض شد و بازترسیم لازم است.
bool ApplyPatternStateFromObject()
{
   if(ObjectFind(0, stateObjName) < 0) return false;

   string parts[];
   int nParts = StringSplit(ObjectGetString(0, stateObjName, OBJPROP_TEXT), '|', parts);

   bool changed = false;
   for(int p = 0; p < PATTERN_COUNT && 3 + p < nParts; p++)
   {
      bool v = (StringToInteger(parts[3 + p]) != 0);
      if(v != patternOn[p]) { patternOn[p] = v; changed = true; }
   }

   if(changed)
   {
      DrawPatternButtons();
      DeleteOffPatternObjects();   // انتخاب از سمت اسکنر آمده، ولی پاکسازی یکی است
   }
   return changed;
}

static ulong lastClickTime       = 0;   // ضد لرزش کلیک روی آبجکت های ما
static ulong lastObjectClickTime = 0;   // زمان آخرین کلیک پردازش شده روی آبجکت های ما

//+------------------------------------------------------------------+
// زمان باقی مانده تا بسته شدن کندل جاری، زیر دکمه ها.
// هر ثانیه از OnTimer بروز می‌شود، پس روی هر تایم فریمی کار می‌کند.
void UpdateCandleTimer()
{
   string name = "GBT_Timer_" + IntegerToString(ChartID());

   if(!ShowCandleTimer)
   {
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      return;
   }

   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == 0) return;

   long remain = (long)(barTime + PeriodSeconds(_Period)) - (long)TimeCurrent();
   if(remain < 0) remain = 0;

   int hh = (int)(remain / 3600);
   int mm = (int)((remain % 3600) / 60);
   int ss = (int)(remain % 60);

   string txt = (hh > 0) ? StringFormat("%02d:%02d:%02d", hh, mm, ss)
                         : StringFormat("%02d:%02d", mm, ss);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   // ردیف ۰ از ردیف های متنی، درست زیر شش دکمه
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UiPanelX());
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiTextY(0));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_BIG);
   ObjectSetInteger(0, name, OBJPROP_COLOR, CandleTimerColor);
   ObjectSetString(0, name, OBJPROP_TEXT, TFToStr((ENUM_TIMEFRAMES)Period()) + "  " + txt);
}

//+------------------------------------------------------------------+
// تایم فریم فراکتال تایم فریم جاری، درست زیر تایمر کندل.
// اگر تایم فریم جاری در نردبان نباشد، چیزی نوشته نمی‌شود.
void UpdateFractalTFLabel()
{
   string name = "GBT_Fract_" + IntegerToString(ChartID());

   string frac = ShowFractalTF ? FractalTFText((ENUM_TIMEFRAMES)Period()) : "";

   if(StringLen(frac) == 0)
   {
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      return;
   }

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   // یک ردیف زیر تایمر کندل
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UiPanelX());
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiTextY(1));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_TXT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, FractalTFColor);
   ObjectSetString(0, name, OBJPROP_TEXT, "F: " + frac);
}

//+------------------------------------------------------------------+
// آیا ساعت GMT داده شده داخل پنجره سشن است؟
// پنجره ای که از نیمه شب رد می‌شود (مثل سیدنی 21 تا 6) هم پشتیبانی می‌شود.
bool InSessionWindow(int hour, int openH, int closeH)
{
   if(openH == closeH) return false;
   if(openH <  closeH) return (hour >= openH && hour < closeH);
   return (hour >= openH || hour < closeH);
}

// سشن های باز در یک ساعت مشخص GMT، به صورت "LDN+NY"
string SessionsAtHour(int hour)
{
   string s = "";
   if(InSessionWindow(hour, SydneyOpenGMT,  SydneyCloseGMT))
      s = s + (StringLen(s) > 0 ? "+" : "") + "SYD";
   if(InSessionWindow(hour, TokyoOpenGMT,   TokyoCloseGMT))
      s = s + (StringLen(s) > 0 ? "+" : "") + "TOK";
   if(InSessionWindow(hour, LondonOpenGMT,  LondonCloseGMT))
      s = s + (StringLen(s) > 0 ? "+" : "") + "LDN";
   if(InSessionWindow(hour, NewYorkOpenGMT, NewYorkCloseGMT))
      s = s + (StringLen(s) > 0 ? "+" : "") + "NY";
   return s;
}

// تعطیلی آخر هفته فارکس: از بسته شدن نیویورک جمعه تا باز شدن سیدنی یکشنبه
bool ForexClosedNow(MqlDateTime &g)
{
   if(g.day_of_week == 6) return true;
   if(g.day_of_week == 5 && g.hour >= NewYorkCloseGMT) return true;
   if(g.day_of_week == 0 && g.hour <  SydneyOpenGMT)   return true;
   return false;
}

//+------------------------------------------------------------------+
// سشن معاملاتی، زیر تایم فریم فراکتال.
// قالب: "S: LDN+NY > NY 01:23" یعنی الان لندن و نیویورک باز اند و ۱ ساعت و
// ۲۳ دقیقه دیگر لندن بسته می‌شود و فقط نیویورک می‌ماند.
void UpdateSessionLabel()
{
   string name = "GBT_Sess_" + IntegerToString(ChartID());

   if(!ShowSession)
   {
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      return;
   }

   MqlDateTime g;
   TimeToStruct(TimeGMT(), g);

   string txt;

   if(ForexClosedNow(g))
   {
      txt = "S: weekend";
   }
   else
   {
      string nowSet = SessionsAtHour(g.hour);
      string shown  = (StringLen(nowSet) > 0) ? nowSet : "-";

      // همه مرزهای سشن سر ساعت اند، پس کافی است ۲۴ ساعت بعدی نگاه شود.
      int    aheadH  = 0;
      string nextSet = "";

      for(int h = 1; h <= 24; h++)
      {
         string s = SessionsAtHour((g.hour + h) % 24);
         if(s == nowSet) continue;
         aheadH  = h;
         nextSet = (StringLen(s) > 0) ? s : "-";
         break;
      }

      txt = "S: " + shown;

      if(aheadH > 0)
      {
         long rem = (long)aheadH * 3600 - (long)g.min * 60 - (long)g.sec;
         txt = txt + " > " + nextSet +
               StringFormat(" %02d:%02d", (int)(rem / 3600), (int)((rem % 3600) / 60));
      }
   }

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   // دو ردیف زیر تایمر کندل
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UiPanelX());
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiTextY(2));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_TXT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, SessionColor);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
}
//+------------------------------------------------------------------+

int OnInit()
{
   string chartIDStr = IntegerToString(ChartID());
   stateObjName = "GBT_State_" + IntegerToString(ChartID());

   // پیش فرض: همه الگوها روشن. اگر وضعیت ذخیره شده داشت، از همان خوانده می‌شود.
   for(int p = 0; p < PATTERN_COUNT; p++) patternOn[p] = true;

   if(ObjectFind(0, stateObjName) >= 0)
   {
      string txt = ObjectGetString(0, stateObjName, OBJPROP_TEXT);
      string parts[];
      int nParts = StringSplit(txt, '|', parts);

      if(nParts >= 3)
      {
         idxStructure = (int)StringToInteger(parts[0]);
         idxTrigger   = (int)StringToInteger(parts[1]);
         idxEntry     = (int)StringToInteger(parts[2]);
      }

      // فیلدهای الگو از نسخه 1.01؛ آبجکت قدیمی آنها را ندارد
      for(int p = 0; p < PATTERN_COUNT && 3 + p < nParts; p++)
         patternOn[p] = (StringToInteger(parts[3 + p]) != 0);
   }

   idxStructure = ClampIdx(idxStructure, ArraySize(StructureTFList));
   idxTrigger   = ClampIdx(idxTrigger,   ArraySize(TriggerTFList));
   idxEntry     = ClampIdx(idxEntry,     ArraySize(EntryTFList));
   SaveState();

   StructureTF = StructureTFList[idxStructure];
   TriggerTF   = TriggerTFList[idxTrigger];
   EntryTF     = EntryTFList[idxEntry];

   prevStructureTF = StructureTF;
   prevTriggerTF   = TriggerTF;
   prevEntryTF     = EntryTF;


   CreateTFButton("GBT_BtnStructure_" + chartIDStr, UiPanelX(), UiBtnY(0), "STRUCT: " + TFToStr(StructureTF));
   CreateTFButton("GBT_BtnTrigger_"   + chartIDStr, UiPanelX(), UiBtnY(1), "TRIG: "   + TFToStr(TriggerTF));
   CreateTFButton("GBT_BtnEntry_"     + chartIDStr, UiPanelX(), UiBtnY(2), "ENTRY: "  + TFToStr(EntryTF));
   DrawPatternButtons();

   lastBarTime      = 0;
   forceRedraw      = true;
   lastConfirmedSig = "";
   staleLayoutSig   = "";
   hadLiveObjects   = false;
   lvlRangeSig      = "";   // سطوح یک بار دوباره حساب شوند

   EventSetTimer(1);

   // آبجکت الگوی خاموش ممکن است از نصب قبلی روی چارت مانده باشد
   DeleteOffPatternObjects();

   // همین لحظه رسم شود، نه با اولین تیک بازار.
   // بدون این، وقتی بازار تیک ندارد (آخر هفته یا نماد کم معامله) چارت تا
   // اولین اجرای تایمر خالی می‌ماند.
   ProcessIndicator();

   UpdateCandleTimer();
   UpdateFractalTFLabel();
   UpdateSessionLabel();
   ChartRedraw();
   return(INIT_SUCCEEDED);
}

void UpdateButton(string btnName, string text)
{
   ObjectSetString(0, btnName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, btnName, OBJPROP_STATE, false);
}

void ChangeTF(string type, int idx)
{
   string chartIDStr = IntegerToString(ChartID());

   if(type == "STRUCT")
   {
      idxStructure = ClampIdx(idx, ArraySize(StructureTFList));
      StructureTF = StructureTFList[idxStructure];
      UpdateButton("GBT_BtnStructure_" + chartIDStr, "STRUCT: " + TFToStr(StructureTF));
   }
   else if(type == "TRIG")
   {
      idxTrigger = ClampIdx(idx, ArraySize(TriggerTFList));
      TriggerTF = TriggerTFList[idxTrigger];
      UpdateButton("GBT_BtnTrigger_" + chartIDStr, "TRIG: " + TFToStr(TriggerTF));
   }
   else if(type == "ENTRY")
   {
      idxEntry = ClampIdx(idx, ArraySize(EntryTFList));
      EntryTF = EntryTFList[idxEntry];
      UpdateButton("GBT_BtnEntry_" + chartIDStr, "ENTRY: " + TFToStr(EntryTF));
   }

   forceRedraw = true;
   SaveState();
   ProcessIndicator();
   ChartRedraw();
}

//+------------------------------------------------------------------+

static TFCategory currentListCategory = NONE;
//+------------------------------------------------------------------+

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   string chartIDStr    = IntegerToString(ChartID());
   string btnStructName = "GBT_BtnStructure_" + chartIDStr;
   string btnTrigName   = "GBT_BtnTrigger_"   + chartIDStr;
   string btnEntryName  = "GBT_BtnEntry_"     + chartIDStr;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      bool isOurObject = (sparam == btnStructName || sparam == btnTrigName || sparam == btnEntryName ||
                          sparam == PatternHeadButtonName() ||
                          StringFind(sparam, "GBT_BtnPat")  == 0 ||
                          StringFind(sparam, "GBT_ListSt_") == 0 ||
                          StringFind(sparam, "GBT_ListTr_") == 0 ||
                          StringFind(sparam, "GBT_ListEn_") == 0);
      if(!isOurObject) return;

      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

      ulong now = GetMicrosecondCount();
      if(now - lastClickTime < 100000)   // 0.1 ثانیه
      {
         ChartRedraw();
         return;
      }
      lastClickTime       = now;
      lastObjectClickTime = now;

      if(sparam == PatternHeadButtonName())
      {
         if(isPatternListOpen)
            HidePatternList();
         else
         {
            HideTFList(currentListCategory);
            isStructureListOpen = false;
            isTriggerListOpen   = false;
            isEntryListOpen     = false;
            currentListCategory = NONE;

            isPatternListOpen = true;
            DrawPatternButtons();
         }
         ChartRedraw();
         return;
      }

      if(StringFind(sparam, "GBT_BtnPat") == 0)
      {
         // نام: GBT_BtnPat<p>_<chartID>
         int p = (int)StringToInteger(StringSubstr(sparam, StringLen("GBT_BtnPat")));
         if(p >= 0 && p < PATTERN_COUNT)
         {
            patternOn[p] = !patternOn[p];
            DrawPatternButton(p);
            DrawPatternHeadButton();
            SaveState();

            // آبجکت های الگوی خاموش شده در همه تایم فریم ها پاک می‌شوند،
            // نه فقط تایم فریم جاری که ProcessIndicator می‌بیند.
            DeleteOffPatternObjects();

            forceRedraw = true;
            ProcessIndicator();
         }
         ChartRedraw();
         return;
      }

      if(sparam == btnStructName)
      {
         if(currentListCategory != STRUCTURE) HideTFList(currentListCategory);
         if(isPatternListOpen) HidePatternList();
         if(!isStructureListOpen) ShowTFList(STRUCTURE, UiListX(), UiBtnY(0));
         isStructureListOpen = true;
         isTriggerListOpen   = false;
         isEntryListOpen     = false;
         currentListCategory = STRUCTURE;
      }
      else if(sparam == btnTrigName)
      {
         if(currentListCategory != TRIGGER) HideTFList(currentListCategory);
         if(isPatternListOpen) HidePatternList();
         if(!isTriggerListOpen) ShowTFList(TRIGGER, UiListX(), UiBtnY(0));
         isTriggerListOpen   = true;
         isStructureListOpen = false;
         isEntryListOpen     = false;
         currentListCategory = TRIGGER;
      }
      else if(sparam == btnEntryName)
      {
         if(currentListCategory != ENTRY) HideTFList(currentListCategory);
         if(isPatternListOpen) HidePatternList();
         if(!isEntryListOpen) ShowTFList(ENTRY, UiListX(), UiBtnY(0));
         isEntryListOpen     = true;
         isStructureListOpen = false;
         isTriggerListOpen   = false;
         currentListCategory = ENTRY;
      }
      else if(StringFind(sparam, "GBT_ListSt_") == 0)
      {
         ChangeTF("STRUCT", (int)StringToInteger(StringSubstr(sparam, StringLen("GBT_ListSt_"))));
         HideTFList(STRUCTURE);
         isStructureListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "GBT_ListTr_") == 0)
      {
         ChangeTF("TRIG", (int)StringToInteger(StringSubstr(sparam, StringLen("GBT_ListTr_"))));
         HideTFList(TRIGGER);
         isTriggerListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "GBT_ListEn_") == 0)
      {
         ChangeTF("ENTRY", (int)StringToInteger(StringSubstr(sparam, StringLen("GBT_ListEn_"))));
         HideTFList(ENTRY);
         isEntryListOpen = false;
         currentListCategory = NONE;
      }

      ChartRedraw();
   }

   if(id == CHARTEVENT_CLICK)
   {
      // کلیک روی دکمه های خود اندیکاتور علاوه بر CHARTEVENT_OBJECT_CLICK یک
      // CHARTEVENT_CLICK هم تولید می‌کند. بدون این محافظ، لیستی که همین الان
      // با کلیک روی دکمه باز شده، بلافاصله با رویداد دوم بسته می‌شود.
      if(GetMicrosecondCount() - lastObjectClickTime < 300000)   // 0.3 ثانیه
         return;

      if(isPatternListOpen)
      {
         HidePatternList();
         ChartRedraw();
      }

      if(currentListCategory != NONE)
      {
         HideTFList(currentListCategory);
         isStructureListOpen = false;
         isTriggerListOpen   = false;
         isEntryListOpen     = false;
         currentListCategory = NONE;
         ChartRedraw();
      }
   }
}
//+------------------------------------------------------------------+

// آیا این تایم فریم هنوز روی یکی از سه دکمه نشسته است؟
bool IsSelectedTF(int tf)
{
   return (tf == (int)StructureTF || tf == (int)TriggerTF || tf == (int)EntryTF);
}

// پاک کردن آبجکت هایی که دیگر به کار نمی‌آیند.
//
// دو قاعده جدا:
//
//   ۱. تایم فریم پایین تر از چارت جاری: کار فراکتالی از بالا به پایین
//      می‌آید، پس آنچه در تایم پایین تر رسم شده وقتی به تایم بالا برمی‌گردید
//      فقط شلوغی است.
//
//   ۲. تایم فریم بالاتر از چارت جاری فقط تا وقتی می‌ماند که هنوز روی یکی از
//      سه دکمه باشد. همین بند قبلا نبود و باگ می‌ساخت: با رفتن دکمه ساختار
//      از H8 به H4، آبجکت های H8 نه پایین تر از چارت بودند که قاعده یک
//      پاکشان کند، نه دیگر «فراکتال بالاتر» بودند — فقط ته مانده انتخاب
//      قبلی. برعکسش (H4 به H8) مشکلی نداشت چون آنجا آبجکت کهنه پایین تر از
//      چارت می‌افتاد و قاعده یک می‌گرفتش. همین باعث می‌شد ایراد فقط در یک
//      جهت دیده شود.
void DeleteStaleTFObjects()
{
   int total = ObjectsTotal(0);
   int currentTF = Period();

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      if(StringFind(name, "gbtst_") == 0 || StringFind(name, "gbttr_") == 0 || StringFind(name, "gbten_") == 0)
      {
         // فرمت نام: <cat>_<tf>_...  →  تایم فریم بین اولین و دومین آندرلاین است
         int p1 = StringFind(name, "_");
         int p2 = (p1 >= 0) ? StringFind(name, "_", p1 + 1) : -1;
         if(p1 < 0 || p2 <= p1 + 1) continue;

         int objTF = (int)StringToInteger(StringSubstr(name, p1 + 1, p2 - p1 - 1));

         // مقادیر ENUM_TIMEFRAMES با مدت زمان کندل هم‌ترتیب هستند
         if(objTF < currentTF)   { ObjectDelete(0, name); continue; }

         if(!IsSelectedTF(objTF)) ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
void DrawSwing(SwingAB &s, TFCategory cat, ENUM_TIMEFRAMES tf, color drawColor, int tfSecs,
               MqlRates &rates[], int rates_total)
{
   string base = SwingBaseName(cat, tf, s);

   string lineName = base + "_AB";
   string labelA   = base + "_A";
   string labelB   = base + "_B";
   string extLine  = base + "_BL";
   string midLine  = base + "_MID";

   bool active = (s.state == AB_WAIT_RETRACE || s.state == AB_RETRACED || s.state == AB_BROKEN);

   // الگوی مرده کاملا خاکستری رسم می‌شود تا با الگوهای زنده اشتباه نشود
   // بک تست: الگوی مرده هم با رنگ دسته تایم فریم خودش رسم می‌شود.
   // متن علت ابطال کنار خط B می‌ماند، چون همان چیزی است که موقع بررسی
   // لازم است بدانید.
   bool dead = (s.state == AB_INVALID || s.state == AB_DONE);

   // --- FVG داخل سویینگ بین idxA و idxB
   if(ShowFVG && (cat == STRUCTURE || cat == TRIGGER))
   {
      for(int m = s.idxA + 2; m <= s.idxB; m++)
      {
         if(m >= rates_total) break;

         string fvgName = base + "_FVG" + IntegerToString((long)rates[m].time);
         datetime fvgEnd = rates[m].time + tfSecs * FVGExtendCandles;

         if(s.isBull && rates[m].low > rates[m-2].high)
         {
            if(ObjectFind(0, fvgName) >= 0) ObjectDelete(0, fvgName);
            ObjectCreate(0, fvgName, OBJ_RECTANGLE, 0, rates[m-2].time, rates[m].low, fvgEnd, rates[m-2].high);
            ObjectSetInteger(0, fvgName, OBJPROP_COLOR, drawColor);
            ObjectSetInteger(0, fvgName, OBJPROP_BACK, true);
         }
         else if(!s.isBull && rates[m].high < rates[m-2].low)
         {
            if(ObjectFind(0, fvgName) >= 0) ObjectDelete(0, fvgName);
            ObjectCreate(0, fvgName, OBJ_RECTANGLE, 0, rates[m-2].time, rates[m].high, fvgEnd, rates[m-2].low);
            ObjectSetInteger(0, fvgName, OBJPROP_COLOR, drawColor);
            ObjectSetInteger(0, fvgName, OBJPROP_BACK, true);
         }
      }
   }

   // --- خط AB: در حال تشکیل خط‌چین، بعد از قطعی شدن ممتد
   if(ObjectFind(0, lineName) >= 0) ObjectDelete(0, lineName);
   // خط AB و برچسب A از نقطه رسم استفاده می‌کنند، نه از priceA محاسباتی.
   // بقیه رسم ها (خط میانی، خطوط ۲۰ و ۶۰ درصد) روی priceA می‌مانند تا با
   // چیزی که چرخه عمر واقعا می‌سنجد یکی باشند.
   ObjectCreate(0, lineName, OBJ_TREND, 0, s.timeADraw, s.priceADraw, s.timeB, s.priceB);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, s.live ? STYLE_DASH : STYLE_SOLID);

   // --- لیبل های A و B
   if(ObjectFind(0, labelA) >= 0) ObjectDelete(0, labelA);
   ObjectCreate(0, labelA, OBJ_TEXT, 0, s.timeADraw + tfSecs * LabelShiftCandles, s.priceADraw);
   ObjectSetInteger(0, labelA, OBJPROP_COLOR, LabelColor);
   ObjectSetString(0, labelA, OBJPROP_TEXT, "A");

   if(ObjectFind(0, labelB) >= 0) ObjectDelete(0, labelB);
   ObjectCreate(0, labelB, OBJ_TEXT, 0, s.timeB - tfSecs * LabelShiftCandles, s.priceB);
   ObjectSetInteger(0, labelB, OBJPROP_COLOR, LabelColor);
   ObjectSetString(0, labelB, OBJPROP_TEXT, "B");

   // --- خط B (محدوده نقدینگی). تا وقتی الگو فعال است تا کندل جاری ادامه پیدا می‌کند.
   datetime bEnd = s.timeB + tfSecs * LineBLength;
   if(ExtendBLineToNow && active && rates_total > 0)
   {
      datetime nowBar = rates[rates_total - 1].time + tfSecs * 2;
      if(nowBar > bEnd) bEnd = nowBar;
   }

   if(ObjectFind(0, extLine) >= 0) ObjectDelete(0, extLine);
   ObjectCreate(0, extLine, OBJ_TREND, 0, s.timeB, s.priceB, bEnd, s.priceB);
   ObjectSetInteger(0, extLine, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, extLine, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, extLine, OBJPROP_RAY_RIGHT, false);

   // --- خط میانی (سطح 50 درصد اصلاح)
   double midPrice = (s.priceA + s.priceB) / 2.0;
   if(ObjectFind(0, midLine) >= 0) ObjectDelete(0, midLine);
   ObjectCreate(0, midLine, OBJ_TREND, 0, s.timeB, midPrice, s.timeB + tfSecs * LineMidLength, midPrice);
   ObjectSetInteger(0, midLine, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, midLine, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, midLine, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, midLine, OBJPROP_RAY_RIGHT, false);

   if(!UsesLifecycle(cat)) return;

   // --- مرزهای ناحیه اصلاح مجاز: حداقل و حداکثر درصد
   double dir = s.isBull ? -1.0 : 1.0;

   if(Show20PercentLine)
   {
      double levelMin = s.priceB + dir * s.size * RetraceMinPercent / 100.0;
      string lineMin  = base + "_L20";

      if(ObjectFind(0, lineMin) >= 0) ObjectDelete(0, lineMin);
      ObjectCreate(0, lineMin, OBJ_TREND, 0, s.timeB, levelMin, s.timeB + tfSecs * LineMidLength, levelMin);
      ObjectSetInteger(0, lineMin, OBJPROP_COLOR, drawColor);
      ObjectSetInteger(0, lineMin, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, lineMin, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, lineMin, OBJPROP_RAY_RIGHT, false);
   }

   if(ShowMaxRetraceLine)
   {
      double levelMax = s.priceB + dir * s.size * RetraceMaxPercent / 100.0;
      string lineMax  = base + "_LMX";

      if(ObjectFind(0, lineMax) >= 0) ObjectDelete(0, lineMax);
      ObjectCreate(0, lineMax, OBJ_TREND, 0, s.timeB, levelMax, s.timeB + tfSecs * LineMidLength, levelMax);
      ObjectSetInteger(0, lineMax, OBJPROP_COLOR, drawColor);
      ObjectSetInteger(0, lineMax, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, lineMax, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, lineMax, OBJPROP_RAY_RIGHT, false);
   }

   // --- لیبل C
   // C در AB صعودی کف اصلاح است و در AB نزولی سقف آن. لیبل بیرون کندل قرار
   // می‌گیرد تا رویش نیفتد: صعودی زیر کف کندل، نزولی بالای سقف کندل.
   // priceC عمیق ترین بدنه است، ولی برای جای لیبل از سایه استفاده می‌شود تا
   // متن کل کندل را رد کند.
   if(s.idxC >= 0 && s.idxC < rates_total && (s.state == AB_RETRACED || s.state == AB_BROKEN))
   {
      string labelC = base + "_C";
      double anchorPrice = s.isBull ? rates[s.idxC].low : rates[s.idxC].high;

      if(ObjectFind(0, labelC) >= 0) ObjectDelete(0, labelC);
      ObjectCreate(0, labelC, OBJ_TEXT, 0, s.timeC, anchorPrice);
      ObjectSetInteger(0, labelC, OBJPROP_COLOR, LabelColor);
      ObjectSetInteger(0, labelC, OBJPROP_ANCHOR, s.isBull ? ANCHOR_UPPER : ANCHOR_LOWER);
      ObjectSetString(0, labelC, OBJPROP_TEXT, "C");
   }

   // --- علامت کندل شکست
   if(s.hasValidBreak && s.idxBreakTo >= 0)
   {
      string brkName = base + "_BRK";
      if(ObjectFind(0, brkName) >= 0) ObjectDelete(0, brkName);
      ObjectCreate(0, brkName, OBJ_RECTANGLE, 0,
                   rates[s.idxBreakFrom].time, s.breakLow,
                   rates[s.idxBreakTo].time,   s.breakHigh);
      ObjectSetInteger(0, brkName, OBJPROP_COLOR, drawColor);
      ObjectSetInteger(0, brkName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, brkName, OBJPROP_BACK, true);
   }

   // --- فلش سیگنال ورود
   if(ShowEntrySignal && s.idxSignal >= 0)
   {
      string sigName = base + "_SIG";
      if(ObjectFind(0, sigName) >= 0) ObjectDelete(0, sigName);
      // AB صعودی: هانت بالای B و بازگشت به پایین → سیگنال فروش
      ObjectCreate(0, sigName, s.isBull ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, s.timeSignal, s.priceSignal);
      ObjectSetInteger(0, sigName, OBJPROP_COLOR, drawColor);
      ObjectSetInteger(0, sigName, OBJPROP_WIDTH, 2);
   }

   // --- برچسب وضعیت کنار خط B
   if(ShowStateLabel && !s.live)
   {
      string stName = base + "_ST";
      if(ObjectFind(0, stName) >= 0) ObjectDelete(0, stName);
      ObjectCreate(0, stName, OBJ_TEXT, 0, bEnd, s.priceB);
      ObjectSetInteger(0, stName, OBJPROP_COLOR, drawColor);
      ObjectSetInteger(0, stName, OBJPROP_FONTSIZE, 8);
      // برای الگوی مرده، به جای وضعیت، علت ابطال نوشته می‌شود
      ObjectSetString(0, stName, OBJPROP_TEXT,
                      "  " + (dead ? DeadReasonText(s.deadReason) : StateText(s)));
   }
}

//+------------------------------------------------------------------+
// رسم یک Inside Bar: خط افقی از های و لوی مادر و (در صورت انتخاب) فرزند،
// از خود کندل تا IBLineCandles کندل بعد از فرزند به سمت آینده بازار.
// نام آبجکت ها با پیشوند همان تایم فریم است تا پاکسازی تعویض تایم فریم و
// DeleteStaleTFObjects بدون تغییری شامل شان شود.
void DrawInsideBar(InsideBar &ib, TFCategory cat, ENUM_TIMEFRAMES tf, int tfSecs,
                   color drawColor)
{
   // الگوی منقضی شده مثل الگوی مرده AB خاکستری می‌ماند تا انتهای همان روز،
   // تا بشود بررسی کرد که درست کنار گذاشته شده یا نه.

   string base = GetTFPrefix(cat, tf) + "IB" + IntegerToString((long)ib.timeChild);
   datetime lineEnd = ib.timeChild + tfSecs * IBLineCandles;

   string names[4];
   double lvl[4];
   datetime from[4];
   int nLines = 2;

   names[0] = base + "_MH"; lvl[0] = ib.motherHigh; from[0] = ib.timeMother;
   names[1] = base + "_ML"; lvl[1] = ib.motherLow;  from[1] = ib.timeMother;

   if(IBShowChildLines)
   {
      names[2] = base + "_CH"; lvl[2] = ib.childHigh; from[2] = ib.timeChild;
      names[3] = base + "_CL"; lvl[3] = ib.childLow;  from[3] = ib.timeChild;
      nLines = 4;
   }

   for(int i = 0; i < nLines; i++)
   {
      if(ObjectFind(0, names[i]) >= 0) ObjectDelete(0, names[i]);
      ObjectCreate(0, names[i], OBJ_TREND, 0, from[i], lvl[i], lineEnd, lvl[i]);
      ObjectSetInteger(0, names[i], OBJPROP_COLOR, drawColor);
      // خطوط مادر ممتد و پهن، خطوط فرزند خط چین و نازک تا از هم جدا باشند
      ObjectSetInteger(0, names[i], OBJPROP_WIDTH, (i < 2) ? 2 : 1);
      ObjectSetInteger(0, names[i], OBJPROP_STYLE, (i < 2) ? STYLE_SOLID : STYLE_DASH);
      ObjectSetInteger(0, names[i], OBJPROP_RAY_RIGHT, false);
   }

   string lbl = base + "_LBL";
   if(ObjectFind(0, lbl) >= 0) ObjectDelete(0, lbl);
   ObjectCreate(0, lbl, OBJ_TEXT, 0, ib.timeMother, ib.motherHigh);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LOWER);
   ObjectSetString(0, lbl, OBJPROP_TEXT, "IB");
}

//+------------------------------------------------------------------+
// هشدار لحظات کلیدی. فقط برای رویدادی که روی آخرین کندل بسته شده رخ داده،
// بنابراین هر رویداد دقیقا یک بار هشدار می‌دهد.
// لاگ تشخیصی: برای هر Inside Bar در محدوده اسکن، علت رد شدن یا قبول شدنش
// به عنوان Tick Fractal نوشته می‌شود.
//
// عمدا از همان EvaluateTickCandidate هسته استفاده می‌کند که خود تشخیص هم
// از آن استفاده می‌کند — نه یک کپی موازی، وگرنه ممکن بود لاگ چیزی بگوید و
// تشخیص چیز دیگری بکند.
void LogTickCandidates(ENUM_TIMEFRAMES tf, MqlRates &rates[], int rates_total)
{
   int firstChild = 0, lastSignal = 0;
   TickScanRange(rates, rates_total, firstChild, lastSignal);

   // سقف کاربر: فقط کندل های اخیر، وگرنه روی تایم پایین لاگ پر می‌شود
   int limitFrom = rates_total - TickDebugBars;
   if(limitFrom > firstChild) firstChild = limitFrom;
   if(firstChild < 1) firstChild = 1;

   Print("--- GOD_OF_HUNT tick log  ", _Symbol, " ", TFToStr(tf),
         "  (body>=", DoubleToString(TickMotherBodyPercent, 1),
         "%  lookback=", TickSwingLookback,
         "  signal<=", TickSignalMaxCandles, " bars)");

   int shown = 0;

   for(int m = firstChild; m <= lastSignal - 1; m++)
   {
      TickCandidate c;
      TickReject r = EvaluateTickCandidate(rates, m, lastSignal, c);

      // کاندیدی که اصلا Inside Bar نیست ارزش نوشتن ندارد
      if(r == TICK_REJ_NOT_INSIDE) continue;

      shown++;

      string line = "IB child " + TimeToString(rates[m].time, TIME_DATE | TIME_MINUTES) +
                    "  mother " + TimeToString(rates[m-1].time, TIME_DATE | TIME_MINUTES) +
                    "  " + (c.isBull ? "BULL" : "BEAR") +
                    "  body " + DoubleToString(c.motherBodyPct, 1) + "%" +
                    "  -> " + TickRejectText(r);

      if(r == TICK_REJ_NOT_SWING_END && c.blockOffset > 0)
         line += "  (mother " + DoubleToString(c.motherExtreme, _Digits) +
                 ", blocked by " + DoubleToString(c.blockExtreme, _Digits) +
                 " at -" + IntegerToString(c.blockOffset) + " bars)";

      if(r == TICK_OK)
         line += "  signal " + TimeToString(rates[c.idxSignal].time, TIME_DATE | TIME_MINUTES);

      Print(line);
   }

   if(shown == 0)
      Print("(no inside bar in the scanned range)");
}

//+------------------------------------------------------------------+
void DrawTickFractal(TickFractal &tk, TFCategory cat, ENUM_TIMEFRAMES tf,
                     color catColor)
{
   // دو پاره خط مادر→فرزند→سیگنال. در سویینگ نزولی از لوها و در صعودی از
   // های ها — همان شکلی که اسم الگو از آن می‌آید.
   color drawColor = catColor;

   string base = GetTFPrefix(cat, tf) + "TK" + IntegerToString((long)tk.timeSignal);

   string seg1 = base + "_S1";
   if(ObjectFind(0, seg1) >= 0) ObjectDelete(0, seg1);
   ObjectCreate(0, seg1, OBJ_TREND, 0, tk.timeMother, tk.p1, tk.timeChild, tk.p2);
   ObjectSetInteger(0, seg1, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, seg1, OBJPROP_WIDTH, TickLineWidth);
   ObjectSetInteger(0, seg1, OBJPROP_RAY_RIGHT, false);

   string seg2 = base + "_S2";
   if(ObjectFind(0, seg2) >= 0) ObjectDelete(0, seg2);
   ObjectCreate(0, seg2, OBJ_TREND, 0, tk.timeChild, tk.p2, tk.timeSignal, tk.p3);
   ObjectSetInteger(0, seg2, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, seg2, OBJPROP_WIDTH, TickLineWidth);
   ObjectSetInteger(0, seg2, OBJPROP_RAY_RIGHT, false);

   // برچسب کنار نقطه سیگنال، بیرون از خود کندل
   string lbl = base + "_LBL";
   if(ObjectFind(0, lbl) >= 0) ObjectDelete(0, lbl);
   ObjectCreate(0, lbl, OBJ_TEXT, 0, tk.timeSignal, tk.p3);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, tk.isBull ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetString(0, lbl, OBJPROP_TEXT, "TICK");
}

//+------------------------------------------------------------------+
void MaybeAlert(SwingAB &s, TFCategory cat, ENUM_TIMEFRAMES tf, int rates_total)
{
   if(!EnableAlerts) return;
   if(s.state == AB_INVALID || s.state == AB_DONE) return;

   int lastClosed = rates_total - 2;
   if(lastClosed < 0) return;

   string tag = _Symbol + " " + TFToStr(tf) + " " + (s.isBull ? "BULL" : "BEAR");

   if(s.idxSignal == lastClosed)
      Alert("GOD_OF_HUNT ", tag, ": سیگنال ورود");
   else if(s.hasValidBreak && s.idxBreakTo == lastClosed)
      Alert("GOD_OF_HUNT ", tag, ": شکست سطح B - برو تایم پایین تر");
   else if(s.state == AB_RETRACED && s.idxC == lastClosed)
      Alert("GOD_OF_HUNT ", tag, ": اصلاح معتبر شد (C)");
}

//+------------------------------------------------------------------+
// برچسب وضعیت بک تست: چه بازه ای واقعا بار شد، چند کندل، و چند الگو رسم شد.
// بدون این، اگر متاتریدر تاریخچه آن بازه را نداشته باشد چارت بی سروصدا
// خالی می‌ماند و معلوم نیست ایراد از بازه است یا از تنظیمات.
void UpdateBtInfo()
{
   string name = "GBT_Info_" + IntegerToString(ChartID());

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   // سه ردیف زیر تایمر کندل
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UiPanelX());
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UiTextY(3));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, UI_FONT_BTN);

   string txt;
   if(btLoadBars <= 0)
      txt = "BT: تاریخچه این بازه در ترمینال نیست";
   else
      txt = "BT " + TimeToString(BtFrom, TIME_DATE) +
            " .. " + (BtTo > 0 ? TimeToString(BtTo, TIME_DATE) : "now") +
            "   بار شده " + IntegerToString(btLoadBars) + " کندل" +
            "   رسم " + IntegerToString(btDrawn) + " الگو";

   ObjectSetInteger(0, name, OBJPROP_COLOR, btLoadBars > 0 ? clrSilver : clrTomato);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
}

//+------------------------------------------------------------------+
// آیا کندل شروع الگو داخل بازه بک تست است؟
// BtTo == 0 یعنی بدون سقف.
bool InBtRange(datetime t)
{
   if(t < BtFrom) return false;
   if(BtTo > 0 && t > BtTo) return false;
   return true;
}

//+------------------------------------------------------------------+
// بازه ای که واقعا از تاریخچه خوانده می‌شود.
//
// فقط همین پنجره بار می‌شود، نه از BtFrom تا امروز — وگرنه انتخاب بازه ای
// از یک سال پیش یعنی خواندن یک سال کندل که چارت را سنگین می‌کند.
//
// دو حاشیه لازم است و هر دو از خود ورودی های تشخیص حساب می‌شوند:
//
//   گرم کردن (قبل از BtFrom): الگویی که A اش نزدیک ابتدای بازه است، برای
//     پیدا شدن به کندل های قبل از خودش نیاز دارد — به اندازه بلندترین
//     سویینگ ممکن (MaxABSpan) به علاوه پنجره تشخیص (MaxCandles).
//
//   دنباله (بعد از BtTo): الگویی که نزدیک انتهای بازه تشکیل شده باید
//     فرصت کند چرخه عمرش را طی کند (C، هانت، ابطال)، وگرنه ناتمام رسم
//     می‌شود. سقفش MaxRetraceBars است.
//
// ضریب ۲ برای جبران شکاف آخر هفته و تعطیلی است: تبدیل «تعداد کندل» به
// «زمان» روی بازار پنج روزه دقیق نیست و کمی دست و دلبازی ارزان تر از
// کم آوردن داده است.
void BtDataRange(ENUM_TIMEFRAMES tf, datetime &fromT, datetime &toT)
{
   long secs = (long)PeriodSeconds(tf);

   long warmBars = MaxABSpan + MaxCandles + 20;
   long tailBars = (MaxRetraceBars > 0 ? MaxRetraceBars : 100) + 50;

   fromT = (datetime)((long)BtFrom - warmBars * secs * 2);

   if(BtTo > 0) toT = (datetime)((long)BtTo + tailBars * secs * 2);
   else         toT = TimeCurrent();
}

//+------------------------------------------------------------------+
void ProcessIndicator()
{
   CheckTFChangeAndDelete();

   // تصمیم DeleteStaleTFObjects فقط به تایم فریم چارت و سه تایم فریم انتخابی
   // بستگی دارد؛ تا عوض نشده اند پیمایش کامل جدول آبجکت بی اثر است.
   string layoutSig = StaleLayoutSignature();
   if(forceRedraw || layoutSig != staleLayoutSig)
   {
      staleLayoutSig = layoutSig;
      DeleteStaleTFObjects();
   }

   TFCategory cat = GetCategory();

   // سطوح افقی سطح مطلق قیمت اند و به دستهٔ تایم فریم ربطی ندارند، پس روی
   // هر تایم فریمی رسم می‌شوند.
   UpdateLevels();

   if(cat == NONE) return;

   int maxLookback = 0;
   if(cat == STRUCTURE)      maxLookback = MaxLookbackStructure;
   else if(cat == TRIGGER)   maxLookback = MaxLookbackTrigger;
   else if(cat == ENTRY)     maxLookback = MaxLookbackEntry;

   ENUM_TIMEFRAMES tf = (cat == STRUCTURE) ? StructureTF : (cat == TRIGGER) ? TriggerTF : EntryTF;

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == 0) return;

   bool abOn = patternOn[PATTERN_AB_HUNT];
   bool ibOn = patternOn[PATTERN_INSIDE_BAR];
   bool tkOn = patternOn[PATTERN_TICK_FRACTAL];

   // حالت بک تست: الگوی مرده حذف نشود و تشخیص IB/TICK کل تاریخچه را بگردد
   KeepAllDeadPatterns = true;
   ScanAllHistory      = true;

   datetime btFrom = 0, btTo = 0;
   BtDataRange(tf, btFrom, btTo);
   btLoadFrom = btFrom;
   btLoadTo   = btTo;

   // تشخیص، چرخه عمر و فیلترها همگی در GOD_OF_HUNTCore انجام می‌شوند تا اندیکاتور
   // و اسکنر دقیقا یک منطق داشته باشند. اینجا فقط رسم می‌ماند.
   MqlRates rates[];
   int rates_total = 0;
   SwingAB kept[];
   int nKept = 0;

   if(abOn)
   {
      // keepOnlyLast عمدا false است.
      //
      // در نسخه زنده تایم ورود فقط آخرین AB را نگه می‌دارد تا چارت شلوغ
      // نشود، ولی در بک تست همان قاعده یعنی از کل بازه فقط یک الگو رسم
      // شود. اینجا هر سه دسته همه الگوهای بازه را نشان می‌دهند.
      nKept = AnalyzeSymbolRange(_Symbol, tf, btFrom, btTo, maxLookback,
                                 false, ShowPreviousABs,
                                 rates, rates_total, kept);
      btLoadBars = rates_total;
      if(nKept < 0) { btLoadBars = 0; UpdateBtInfo(); return; }
   }

   // اگر AB خاموش باشد داده کپی نشده؛ برای IB و TICK همان بازه اینجا
   // خوانده می‌شود (توابع Analyze* عمدا از دم تاریخچه می‌خوانند که برای
   // بک تست به کار نمی‌آید).
   if(!abOn && (ibOn || tkOn))
   {
      ArraySetAsSeries(rates, false);
      rates_total = CopyRates(_Symbol, tf, btFrom, btTo, rates);
      btLoadBars  = (rates_total > 0) ? rates_total : 0;
      if(rates_total < 3) { UpdateBtInfo(); return; }
   }

   InsideBar ibs[];
   int nIB = ibOn ? CollectInsideBars(rates, rates_total, ibs) : 0;

   TickFractal tks[];
   int nTK = tkOn ? CollectTickFractals(rates, rates_total, tks) : 0;

   // امضای وضعیت الگوهای قطعی شده. اگر عوض شود باید کامل بازترسیم کنیم،
   // حتی اگر هنوز کندل جدیدی باز نشده باشد.
   string sig = "";
   for(int k = 0; k < nKept; k++)
      if(!kept[k].live)
         sig += IntegerToString((long)kept[k].timeA) + "/" +
                IntegerToString((int)kept[k].state)  + "/" +
                DoubleToString(kept[k].priceB, _Digits) + ";";

   bool fullRedraw = (forceRedraw || curBar != lastBarTime || sig != lastConfirmedSig);

   bool liveNow = false;
   for(int k = 0; k < nKept; k++)
      if(kept[k].live) { liveNow = true; break; }

   if(fullRedraw)
   {
      DeleteObjectsOfTF(cat, tf);
      lastBarTime      = curBar;
      forceRedraw      = false;
      lastConfirmedSig = sig;
   }
   else if(liveNow || hadLiveObjects)
   {
      DeleteLiveObjectsOfTF(cat, tf);
   }

   hadLiveObjects = liveNow;

   color drawColor = GetCategoryColor(cat);
   int   tfSecs    = PeriodSeconds(tf);

   // شمارش الگوهای داخل بازه، مستقل از رسم.
   //
   // قبلا شمارش IB و TICK داخل بلوک fullRedraw بود، پس فقط در اولین اجرا
   // درست بود و از تیک بعدی تایمر — که بازترسیم کامل لازم ندارد — صفر
   // می‌شد، در حالی که الگوها روی چارت بودند.
   btDrawn = 0;
   for(int c = 0; c < nKept; c++) if(InBtRange(kept[c].timeA))      btDrawn++;
   for(int c = 0; c < nIB;   c++) if(InBtRange(ibs[c].timeChild))   btDrawn++;
   for(int c = 0; c < nTK;   c++) if(InBtRange(tks[c].timeSignal))  btDrawn++;

   for(int k = 0; k < nKept; k++)
   {
      if(!InBtRange(kept[k].timeA)) continue;

      bool isDead = (kept[k].state == AB_INVALID || kept[k].state == AB_DONE);

      if(fullRedraw || kept[k].live)
         DrawSwing(kept[k], cat, tf, drawColor, tfSecs, rates, rates_total);

      if(fullRedraw && EnableABCD)
         MaybeAlert(kept[k], cat, tf, rates_total);
   }

   // Inside Bar و Tick Fractal فقط از کندل های بسته شده ساخته می‌شوند، پس
   // فقط با کندل جدید عوض می‌شوند و رسمشان در بازترسیم کامل کافی است.
   if(fullRedraw)
   {
      for(int k = 0; k < nIB; k++)
      {
         if(!InBtRange(ibs[k].timeChild)) continue;

         DrawInsideBar(ibs[k], cat, tf, tfSecs, drawColor);

         // ageCandles == 1 یعنی فرزند همین کندل قبلی بسته شده است؛ الگو یک
         // بار، درست بعد از تشکیل، هشدار می‌دهد.
         if(EnableAlerts && ibs[k].ageCandles == 1)
            Alert("GOD_OF_HUNT ", _Symbol, " ", TFToStr(tf), ": Inside Bar");
      }

      for(int k = 0; k < nTK; k++)
      {
         if(!InBtRange(tks[k].timeSignal)) continue;

         DrawTickFractal(tks[k], cat, tf, drawColor);

         if(EnableAlerts && tks[k].ageCandles == 1)
            Alert("GOD_OF_HUNT ", _Symbol, " ", TFToStr(tf),
                  ": Tick Fractal ", tks[k].isBull ? "BULL" : "BEAR");
      }

      // لاگ تشخیصی، فقط در بازترسیم کامل تا هر ثانیه تکرار نشود.
      // وقتی AB خاموش است rates پر نشده، پس اینجا جدا کپی می‌شود.
      if(tkOn && TickDebugLog)
      {
         if(abOn) LogTickCandidates(tf, rates, rates_total);
         else
         {
            MqlRates dbg[];
            ArraySetAsSeries(dbg, false);
            int nDbg = CopyRates(_Symbol, tf, 0, ABCDHistoryBars, dbg);
            if(nDbg > 3) LogTickCandidates(tf, dbg, nDbg);
         }
      }
   }

   UpdateBtInfo();
   ChartRedraw();
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
   ProcessIndicator();
   return(rates_total);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   // انتخاب الگوها ممکن است از سمت اسکنر عوض شده باشد
   if(ApplyPatternStateFromObject())
      forceRedraw = true;

   // برای وقتی که بازار تیک ندارد ولی کندل بسته می‌شود یا کاربر تایم فریم را عوض کرده
   ProcessIndicator();
   UpdateCandleTimer();
   UpdateFractalTFLabel();
   UpdateSessionLabel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
   {
      int total = ObjectsTotal(0);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);

         if(StringFind(name, "gbtst_") == 0 ||
            StringFind(name, "gbttr_") == 0 ||
            StringFind(name, "gbten_") == 0 ||
            StringFind(name, "GBT_ListSt_") == 0 ||
            StringFind(name, "GBT_ListTr_") == 0 ||
            StringFind(name, "GBT_ListEn_") == 0 ||
            StringFind(name, "GBT_BtnStructure_") == 0 ||
            StringFind(name, "GBT_BtnTrigger_") == 0 ||
            StringFind(name, "GBT_BtnEntry_") == 0 ||
            StringFind(name, "GBT_BtnPat") == 0 ||
            StringFind(name, LEVEL_PREFIX) == 0 ||
            StringFind(name, "GBT_State_") == 0 ||
            StringFind(name, "GBT_Cfg_") == 0 ||
            StringFind(name, "GBT_Timer_") == 0 ||
            StringFind(name, "GBT_Fract_") == 0 ||
            StringFind(name, "GBT_Sess_") == 0 ||
            StringFind(name, "GBT_Info_") == 0)
         {
            ObjectDelete(0, name);
         }
      }
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
