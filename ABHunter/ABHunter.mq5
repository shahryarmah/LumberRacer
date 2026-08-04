//+------------------------------------------------------------------+
//|                                              ABHunter V2.10.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.60"
#property indicator_chart_window
#property indicator_plots 0   // هیچ پلاتی ندارد؛ فقط آبجکت رسم می‌کند

// قواعد تشخیص و چرخه عمر مشترک با اسکنر
#include "ABHunterCore.mqh"

// این اندیکاتور فقط با آبجکت‌های گرافیکی کار می‌کند و هیچ بافری ندارد.

//---- تایم فریم های قابل تغییر با دکمه
ENUM_TIMEFRAMES StructureTF;
ENUM_TIMEFRAMES TriggerTF;
ENUM_TIMEFRAMES EntryTF;

ENUM_TIMEFRAMES prevStructureTF = 0;
ENUM_TIMEFRAMES prevTriggerTF   = 0;
ENUM_TIMEFRAMES prevEntryTF     = 0;

//---- رنگ ها با قابل تغییر توسط کاربر
input color  StructureColor = clrDeepSkyBlue;  // رنگ ساختار
input color  TriggerColor   = clrOrange;       // رنگ تریگر
input color  EntryColor     = clrViolet;       // رنگ ورود
input color  LabelColor     = clrBlack;        // رنگ لیبل ها

//---- تنظیمات اصلی
input int    MaxLookbackStructure = 7;    // تعداد کندل برای ساختار (وقتی ABCD خاموش است)
input int    MaxLookbackTrigger   = 15;   // تعداد کندل برای تریگر (وقتی ABCD خاموش است)
input int    MaxLookbackEntry     = 30;   // تعداد کندل برای ورود
input int    LineBLength          = 10;   // طول خط ادامه از B (بر حسب کندل)
input int    LineMidLength        = 15;   // طول خط میانی (بر حسب کندل)
input int    FVGExtendCandles     = 10;
input bool   ShowFVG              = true;
input int    LabelShiftCandles    = 1;    // تعداد کندل شیفت لیبل ها

//---- تنظیمات نمایش AB
input bool   ShowPreviousABs      = false; // نمایش AB های قبلی (وقتی ABCD خاموش است)

//---- نمایش الگو روی چارت
input bool   Show20PercentLine    = true;  // رسم خط حداقل اصلاح (20 درصد)
input bool   ShowMaxRetraceLine   = true;  // رسم خط حداکثر اصلاح (60 درصد)
input bool   ShowStateLabel       = true;  // نمایش وضعیت الگو کنار خط B
input bool   ExtendBLineToNow     = true;  // ادامه خط B تا کندل جاری تا وقتی الگو فعال است

//---- سیگنال و هشدار
input bool   ShowEntrySignal      = true;  // نمایش فلش سیگنال ورود
input bool   EnableAlerts         = false; // هشدار در لحظات کلیدی

//---- تایمر کندل
input bool   ShowCandleTimer      = true;      // نمایش زمان باقی مانده تا بسته شدن کندل
input color  CandleTimerColor     = clrGray;   // رنگ تایمر

//+------------------------------------------------------------------+
enum TFCategory { STRUCTURE, TRIGGER, ENTRY, NONE };

// اندیس فعلی در لیست ها
int idxStructure = 3;   // H4
int idxTrigger   = 2;   // M20
int idxEntry     = 8;   // M1

//--- آبجکت ذخیره سازی محلی مخصوص این چارت
string stateObjName;

//+------------------------------------------------------------------+
// متغیرهای مدیریت وضعیت لیست ها
bool isStructureListOpen = false;
bool isTriggerListOpen   = false;
bool isEntryListOpen     = false;

// کنترل بازترسیم
datetime lastBarTime       = 0;
bool     forceRedraw       = true;
string   lastConfirmedSig  = "";

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
   string catStr = (cat == STRUCTURE) ? "abhst_" : (cat == TRIGGER) ? "abhtr_" : (cat == ENTRY) ? "abhen_" : "abhxx_";
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

   if(cat == STRUCTURE)   { prefix = "ABH_ListSt_"; count = ArraySize(StructureTFList); }
   else if(cat == TRIGGER){ prefix = "ABH_ListTr_"; count = ArraySize(TriggerTFList);   }
   else if(cat == ENTRY)  { prefix = "ABH_ListEn_"; count = ArraySize(EntryTFList);     }
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
   return (cat == STRUCTURE) ? "ABH_ListSt_" : (cat == TRIGGER) ? "ABH_ListTr_" : "ABH_ListEn_";
}

void ShowTFList(TFCategory cat, int x, int y)
{
   string prefix;
   ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
   int count = 0;
   int selectedIdx = 0;

   if(cat == STRUCTURE)    { prefix = "ABH_ListSt_"; count = ArraySize(StructureTFList); selectedIdx = idxStructure; }
   else if(cat == TRIGGER) { prefix = "ABH_ListTr_"; count = ArraySize(TriggerTFList);   selectedIdx = idxTrigger;   }
   else if(cat == ENTRY)   { prefix = "ABH_ListEn_"; count = ArraySize(EntryTFList);     selectedIdx = idxEntry;     }
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
      ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, y + 25 * i);
      ObjectSetInteger(0, btnName, OBJPROP_XSIZE, 120);
      ObjectSetInteger(0, btnName, OBJPROP_YSIZE, 20);
      ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE, 9);
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

   if(ObjectFind(0, stateObjName) < 0)
   {
      if(ObjectCreate(0, stateObjName, OBJ_LABEL, 0, 0, 0))
      {
         ObjectSetInteger(0, stateObjName, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, stateObjName, OBJPROP_SELECTABLE, false);
      }
   }
   ObjectSetString(0, stateObjName, OBJPROP_TEXT, txt);
}

//+------------------------------------------------------------------+
void CreateTFButton(string name, int x, int y, string text)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 120);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrDodgerBlue);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

static ulong lastClickTime       = 0;   // ضد لرزش کلیک روی آبجکت های ما
static ulong lastObjectClickTime = 0;   // زمان آخرین کلیک پردازش شده روی آبجکت های ما

//+------------------------------------------------------------------+
// زمان باقی مانده تا بسته شدن کندل جاری، زیر دکمه ها.
// هر ثانیه از OnTimer بروز می‌شود، پس روی هر تایم فریمی کار می‌کند.
void UpdateCandleTimer()
{
   string name = "ABH_Timer_" + IntegerToString(ChartID());

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
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 100);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 11);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, CandleTimerColor);
   ObjectSetString(0, name, OBJPROP_TEXT, TFToStr((ENUM_TIMEFRAMES)Period()) + "  " + txt);
}
//+------------------------------------------------------------------+

int OnInit()
{
   string chartIDStr = IntegerToString(ChartID());
   stateObjName = StateObjectName(ChartID());

   if(ObjectFind(0, stateObjName) >= 0)
   {
      string txt = ObjectGetString(0, stateObjName, OBJPROP_TEXT);
      if(StringLen(txt) > 0)
      {
         int p1end = StringFind(txt, "|");
         int p2end = (p1end >= 0) ? StringFind(txt, "|", p1end + 1) : -1;
         if(p1end >= 0 && p2end > p1end)
         {
            idxStructure = (int)StringToInteger(StringSubstr(txt, 0, p1end));
            idxTrigger   = (int)StringToInteger(StringSubstr(txt, p1end + 1, p2end - (p1end + 1)));
            idxEntry     = (int)StringToInteger(StringSubstr(txt, p2end + 1));
         }
      }
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


   CreateTFButton("ABH_BtnStructure_" + chartIDStr, 10, 10, "STRUCT: " + TFToStr(StructureTF));
   CreateTFButton("ABH_BtnTrigger_"   + chartIDStr, 10, 40, "TRIG: "   + TFToStr(TriggerTF));
   CreateTFButton("ABH_BtnEntry_"     + chartIDStr, 10, 70, "ENTRY: "  + TFToStr(EntryTF));

   lastBarTime      = 0;
   forceRedraw      = true;
   lastConfirmedSig = "";

   EventSetTimer(1);

   UpdateCandleTimer();
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
      UpdateButton("ABH_BtnStructure_" + chartIDStr, "STRUCT: " + TFToStr(StructureTF));
   }
   else if(type == "TRIG")
   {
      idxTrigger = ClampIdx(idx, ArraySize(TriggerTFList));
      TriggerTF = TriggerTFList[idxTrigger];
      UpdateButton("ABH_BtnTrigger_" + chartIDStr, "TRIG: " + TFToStr(TriggerTF));
   }
   else if(type == "ENTRY")
   {
      idxEntry = ClampIdx(idx, ArraySize(EntryTFList));
      EntryTF = EntryTFList[idxEntry];
      UpdateButton("ABH_BtnEntry_" + chartIDStr, "ENTRY: " + TFToStr(EntryTF));
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
   string btnStructName = "ABH_BtnStructure_" + chartIDStr;
   string btnTrigName   = "ABH_BtnTrigger_"   + chartIDStr;
   string btnEntryName  = "ABH_BtnEntry_"     + chartIDStr;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      bool isOurObject = (sparam == btnStructName || sparam == btnTrigName || sparam == btnEntryName ||
                          StringFind(sparam, "ABH_ListSt_") == 0 ||
                          StringFind(sparam, "ABH_ListTr_") == 0 ||
                          StringFind(sparam, "ABH_ListEn_") == 0);
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

      if(sparam == btnStructName)
      {
         if(currentListCategory != STRUCTURE) HideTFList(currentListCategory);
         if(!isStructureListOpen) ShowTFList(STRUCTURE, 140, 10);
         isStructureListOpen = true;
         isTriggerListOpen   = false;
         isEntryListOpen     = false;
         currentListCategory = STRUCTURE;
      }
      else if(sparam == btnTrigName)
      {
         if(currentListCategory != TRIGGER) HideTFList(currentListCategory);
         if(!isTriggerListOpen) ShowTFList(TRIGGER, 140, 10);
         isTriggerListOpen   = true;
         isStructureListOpen = false;
         isEntryListOpen     = false;
         currentListCategory = TRIGGER;
      }
      else if(sparam == btnEntryName)
      {
         if(currentListCategory != ENTRY) HideTFList(currentListCategory);
         if(!isEntryListOpen) ShowTFList(ENTRY, 140, 10);
         isEntryListOpen     = true;
         isStructureListOpen = false;
         isTriggerListOpen   = false;
         currentListCategory = ENTRY;
      }
      else if(StringFind(sparam, "ABH_ListSt_") == 0)
      {
         ChangeTF("STRUCT", (int)StringToInteger(StringSubstr(sparam, StringLen("ABH_ListSt_"))));
         HideTFList(STRUCTURE);
         isStructureListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "ABH_ListTr_") == 0)
      {
         ChangeTF("TRIG", (int)StringToInteger(StringSubstr(sparam, StringLen("ABH_ListTr_"))));
         HideTFList(TRIGGER);
         isTriggerListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "ABH_ListEn_") == 0)
      {
         ChangeTF("ENTRY", (int)StringToInteger(StringSubstr(sparam, StringLen("ABH_ListEn_"))));
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

void DeleteLowerTFObjects()
{
   int total = ObjectsTotal(0);
   int currentTF = Period();

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      if(StringFind(name, "abhst_") == 0 || StringFind(name, "abhtr_") == 0 || StringFind(name, "abhen_") == 0)
      {
         // فرمت نام: <cat>_<tf>_...  →  تایم فریم بین اولین و دومین آندرلاین است
         int p1 = StringFind(name, "_");
         int p2 = (p1 >= 0) ? StringFind(name, "_", p1 + 1) : -1;
         if(p1 < 0 || p2 <= p1 + 1) continue;

         int objTF = (int)StringToInteger(StringSubstr(name, p1 + 1, p2 - p1 - 1));

         // مقادیر ENUM_TIMEFRAMES با مدت زمان کندل هم‌ترتیب هستند
         if(objTF < currentTF)
            ObjectDelete(0, name);
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
   ObjectCreate(0, lineName, OBJ_TREND, 0, s.timeA, s.priceA, s.timeB, s.priceB);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, drawColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, s.live ? STYLE_DASH : STYLE_SOLID);

   // --- لیبل های A و B
   if(ObjectFind(0, labelA) >= 0) ObjectDelete(0, labelA);
   ObjectCreate(0, labelA, OBJ_TEXT, 0, s.timeA + tfSecs * LabelShiftCandles, s.priceA);
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
      ObjectSetString(0, stName, OBJPROP_TEXT, "  " + StateText(s));
   }
}

//+------------------------------------------------------------------+
// هشدار لحظات کلیدی. فقط برای رویدادی که روی آخرین کندل بسته شده رخ داده،
// بنابراین هر رویداد دقیقا یک بار هشدار می‌دهد.
void MaybeAlert(SwingAB &s, TFCategory cat, ENUM_TIMEFRAMES tf, int rates_total)
{
   if(!EnableAlerts) return;

   int lastClosed = rates_total - 2;
   if(lastClosed < 0) return;

   string tag = _Symbol + " " + TFToStr(tf) + " " + (s.isBull ? "BULL" : "BEAR");

   if(s.idxSignal == lastClosed)
      Alert("ABHunter ", tag, ": سیگنال ورود");
   else if(s.hasValidBreak && s.idxBreakTo == lastClosed)
      Alert("ABHunter ", tag, ": شکست سطح B - برو تایم پایین تر");
   else if(s.state == AB_RETRACED && s.idxC == lastClosed)
      Alert("ABHunter ", tag, ": اصلاح معتبر شد (C)");
}

//+------------------------------------------------------------------+
void ProcessIndicator()
{
   CheckTFChangeAndDelete();
   DeleteLowerTFObjects();

   TFCategory cat = GetCategory();
   if(cat == NONE) return;

   int maxLookback = 0;
   if(cat == STRUCTURE)      maxLookback = MaxLookbackStructure;
   else if(cat == TRIGGER)   maxLookback = MaxLookbackTrigger;
   else if(cat == ENTRY)     maxLookback = MaxLookbackEntry;

   ENUM_TIMEFRAMES tf = (cat == STRUCTURE) ? StructureTF : (cat == TRIGGER) ? TriggerTF : EntryTF;

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == 0) return;

   // تشخیص، چرخه عمر و فیلترها همگی در ABHunterCore انجام می‌شوند تا اندیکاتور
   // و اسکنر دقیقا یک منطق داشته باشند. اینجا فقط رسم می‌ماند.
   MqlRates rates[];
   int rates_total = 0;
   SwingAB kept[];

   int nKept = AnalyzeSymbol(_Symbol, tf, ABCDHistoryBars, maxLookback,
                             (cat == ENTRY), ShowPreviousABs,
                             rates, rates_total, kept);
   if(nKept < 0) return;

   // امضای وضعیت الگوهای قطعی شده. اگر عوض شود باید کامل بازترسیم کنیم،
   // حتی اگر هنوز کندل جدیدی باز نشده باشد.
   string sig = "";
   for(int k = 0; k < nKept; k++)
      if(!kept[k].live)
         sig += IntegerToString((long)kept[k].timeA) + "/" +
                IntegerToString((int)kept[k].state)  + "/" +
                DoubleToString(kept[k].priceB, _Digits) + ";";

   bool fullRedraw = (forceRedraw || curBar != lastBarTime || sig != lastConfirmedSig);

   if(fullRedraw)
   {
      DeleteObjectsOfTF(cat, tf);
      lastBarTime      = curBar;
      forceRedraw      = false;
      lastConfirmedSig = sig;
   }
   else
   {
      DeleteLiveObjectsOfTF(cat, tf);
   }

   color drawColor = GetCategoryColor(cat);
   int   tfSecs    = PeriodSeconds(tf);

   for(int k = 0; k < nKept; k++)
   {
      if(fullRedraw || kept[k].live)
         DrawSwing(kept[k], cat, tf, drawColor, tfSecs, rates, rates_total);

      if(fullRedraw && EnableABCD)
         MaybeAlert(kept[k], cat, tf, rates_total);
   }

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
   // برای وقتی که بازار تیک ندارد ولی کندل بسته می‌شود یا کاربر تایم فریم را عوض کرده
   ProcessIndicator();
   UpdateCandleTimer();
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

         if(StringFind(name, "abhst_") == 0 ||
            StringFind(name, "abhtr_") == 0 ||
            StringFind(name, "abhen_") == 0 ||
            StringFind(name, "ABH_ListSt_") == 0 ||
            StringFind(name, "ABH_ListTr_") == 0 ||
            StringFind(name, "ABH_ListEn_") == 0 ||
            StringFind(name, "ABH_BtnStructure_") == 0 ||
            StringFind(name, "ABH_BtnTrigger_") == 0 ||
            StringFind(name, "ABH_BtnEntry_") == 0 ||
            StringFind(name, "ABH_State_") == 0 ||
            StringFind(name, "ABH_Timer_") == 0)
         {
            ObjectDelete(0, name);
         }
      }
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
