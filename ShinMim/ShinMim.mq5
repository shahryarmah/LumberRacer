//+------------------------------------------------------------------+
//|                                              ShinMim V1.05.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.05"
#property indicator_chart_window

// این اندیکاتور فقط با آبجکت‌های گرافیکی کار می‌کند و هیچ بافری ندارد،
// بنابراین indicator_buffers / indicator_plots تعریف نمی‌شود.

//+------------------------------------------------------------------+
// سازگاری با نسخه‌هایی که CHARTEVENT_OBJECT_RCLICK را تعریف نکرده‌اند
#ifndef CHARTEVENT_OBJECT_RCLICK
   #define CHARTEVENT_OBJECT_RCLICK 203
#endif
//+------------------------------------------------------------------+

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
input int    MaxLookbackStructure = 7;    // تعداد کندل برای ساختار
input int    MaxLookbackTrigger   = 15;   // تعداد کندل برای تریگر
input int    MaxLookbackEntry     = 30;   // تعداد کندل برای ورود
input int    MinCandles           = 3;
input int    MaxCandles           = 10;
input int    MaxOppositeCandles   = 1;
input double MinBodyPercent       = 0.1;
input int    MaxNonStandard       = 1;
input int    LineBLength          = 10;   // طول خط ادامه از B (بر حسب کندل)
input int    LineMidLength        = 15;   // طول خط میانی (بر حسب کندل)
input int    FVGExtendCandles     = 10;
input double MinABRatio           = 1.0;
input double MaxABRatio           = 8.0;
input bool   ShowFVG              = true;
input int    LabelShiftCandles    = 1;    // تعداد کندل شیفت لیبل ها

//+------------------------------------------------------------------+
enum TFCategory { STRUCTURE, TRIGGER, ENTRY, NONE };

// لیست تایم فریم های برای هر دکمه
ENUM_TIMEFRAMES StructureTFList[9] = {PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H6, PERIOD_H4, PERIOD_H3, PERIOD_H2, PERIOD_H1, PERIOD_M30};
ENUM_TIMEFRAMES TriggerTFList[8]   = {PERIOD_H1, PERIOD_M30, PERIOD_M20, PERIOD_M15, PERIOD_M12, PERIOD_M10, PERIOD_M6, PERIOD_M5};
ENUM_TIMEFRAMES EntryTFList[9]     = {PERIOD_M15, PERIOD_M12, PERIOD_M10, PERIOD_M6, PERIOD_M5, PERIOD_M4, PERIOD_M3, PERIOD_M2, PERIOD_M1};

// اندیس فعلی در لیست ها
int idxStructure = 3;   // H4
int idxTrigger   = 2;   // M15
int idxEntry     = 8;   // M2

//--- آبجکت ذخیره سازی محلی مخصوص این چارت
string stateObjName;

//+------------------------------------------------------------------+
// متغیرهای جدید برای مدیریت وضعیت لیست ها
bool isStructureListOpen = false;
bool isTriggerListOpen   = false;
bool isEntryListOpen     = false;

// کنترل بازترسیم: فقط وقتی کندل جدید بسته شود یا تنظیمات عوض شود، دوباره رسم می‌کنیم
datetime lastBarTime  = 0;
bool     forceRedraw  = true;

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

// پیشوند نام آبجکت ها: cat_tf_i_len
// تایم فریم بلافاصله بعد از نوع می‌آید تا حذف بر اساس تایم فریم دقیق و بدون
// تداخل باشد (در نسخه قبل جستجوی "_TF1" با "_TF15" و "_TF16388" هم مطابقت می‌کرد)
string GetTFPrefix(TFCategory cat, ENUM_TIMEFRAMES tf)
{
   string catStr = (cat == STRUCTURE) ? "st_" : (cat == TRIGGER) ? "tr_" : (cat == ENTRY) ? "en_" : "xx_";
   return catStr + IntegerToString((int)tf) + "_";
}

string GetPrefix(TFCategory cat, ENUM_TIMEFRAMES tf, int i, int len)
{
   return GetTFPrefix(cat, tf) + IntegerToString(i) + "_" + IntegerToString(len);
}

void DeleteObjectsOfTF(TFCategory cat, ENUM_TIMEFRAMES tf)
{
   string prefix = GetTFPrefix(cat, tf);

   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

// حذف تمام آبجکت های رسم شده توسط اندیکاتور (برای پاکسازی کامل)
void DeleteAllDrawObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, "st_") == 0 || StringFind(name, "tr_") == 0 || StringFind(name, "en_") == 0)
         ObjectDelete(0, name);
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

   if(cat == STRUCTURE)
   {
      prefix = "ListSt_";
      count = ArraySize(StructureTFList);
   }
   else if(cat == TRIGGER)
   {
      prefix = "ListTr_";
      count = ArraySize(TriggerTFList);
   }
   else if(cat == ENTRY)
   {
      prefix = "ListEn_";
      count = ArraySize(EntryTFList);
   }
   else
      return;   // دسته نامعتبر

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
   return (cat == STRUCTURE) ? "ListSt_" : (cat == TRIGGER) ? "ListTr_" : "ListEn_";
}

void ShowTFList(TFCategory cat, int x, int y)
{
   string prefix;
   ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
   int count = 0;
   int selectedIdx = 0;

   if(cat == STRUCTURE)    { prefix = "ListSt_"; count = ArraySize(StructureTFList); selectedIdx = idxStructure; }
   else if(cat == TRIGGER) { prefix = "ListTr_"; count = ArraySize(TriggerTFList);   selectedIdx = idxTrigger;   }
   else if(cat == ENTRY)   { prefix = "ListEn_"; count = ArraySize(EntryTFList);     selectedIdx = idxEntry;     }
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
      ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, x);        // قبلا این مقدار ثابت 10 بود و لیست روی دکمه ها می‌افتاد
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
   string prefix = ListPrefix(cat);

   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
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

// محدود کردن اندیس خوانده شده از وضعیت ذخیره شده تا از خطای
// «array out of range» جلوگیری شود (مثلا اگر طول لیست ها عوض شده باشد)
int ClampIdx(int idx, int size)
{
   if(idx < 0) return 0;
   if(idx >= size) return size - 1;
   return idx;
}

//+------------------------------------------------------------------+
// ساخت / بروزرسانی دکمه اصلی
void CreateTFButton(string name, int x, int y, string text)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   // مقادیر همیشه ست می‌شوند تا اگر دکمه از قبل مانده باشد، متن آن قدیمی نماند
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

static ulong lastClickTime = 0;
//+------------------------------------------------------------------+

int OnInit()
{
   string chartIDStr = IntegerToString(ChartID());
   stateObjName = "ShinMim_State_" + chartIDStr;

   // اگر وضعیت قبلا ذخیره شده بود بارگذاری شود
   if(ObjectFind(0, stateObjName) >= 0)
   {
      string txt = ObjectGetString(0, stateObjName, OBJPROP_TEXT);
      if(StringLen(txt) > 0)
      {
         int p1end = StringFind(txt, "|");
         int p2end = (p1end >= 0) ? StringFind(txt, "|", p1end + 1) : -1;
         if(p1end >= 0 && p2end > p1end)
         {
            string part1 = StringSubstr(txt, 0, p1end);
            string part2 = StringSubstr(txt, p1end + 1, p2end - (p1end + 1));
            string part3 = StringSubstr(txt, p2end + 1);
            idxStructure = (int)StringToInteger(part1);
            idxTrigger   = (int)StringToInteger(part2);
            idxEntry     = (int)StringToInteger(part3);
         }
      }
   }

   // اندیس ها همیشه محدود می‌شوند، چه از وضعیت خوانده شده باشند چه پیش فرض
   idxStructure = ClampIdx(idxStructure, ArraySize(StructureTFList));
   idxTrigger   = ClampIdx(idxTrigger,   ArraySize(TriggerTFList));
   idxEntry     = ClampIdx(idxEntry,     ArraySize(EntryTFList));
   SaveState();

   // مقداردهی تایم فریم ها از روی اندیس ها
   StructureTF = StructureTFList[idxStructure];
   TriggerTF   = TriggerTFList[idxTrigger];
   EntryTF     = EntryTFList[idxEntry];

   prevStructureTF = StructureTF;
   prevTriggerTF   = TriggerTF;
   prevEntryTF     = EntryTF;

   // پاکسازی آبجکت های باقی مانده از اجرای قبلی (از جمله نسخه های قدیمی تر)
   DeleteAllDrawObjects();

   // ساخت دکمه ها با نام یکتا
   CreateTFButton("BtnStructure_" + chartIDStr, 10, 10, "STRUCT: " + TFToStr(StructureTF));
   CreateTFButton("BtnTrigger_"   + chartIDStr, 10, 40, "TRIG: "   + TFToStr(TriggerTF));
   CreateTFButton("BtnEntry_"     + chartIDStr, 10, 70, "ENTRY: "  + TFToStr(EntryTF));

   lastBarTime = 0;
   forceRedraw = true;

   // === تنظیم تایمر هر 1 ثانیه ===
   EventSetTimer(1);   // هر 1 ثانیه OnTimer اجرا می شود

   ChartRedraw();
   return(INIT_SUCCEEDED);
}

void UpdateButton(string btnName, string text)
{
   ObjectSetString(0, btnName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, btnName, OBJPROP_STATE, false);
}

string TFToStr(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M2:   return "M2";
      case PERIOD_M3:   return "M3";
      case PERIOD_M4:   return "M4";
      case PERIOD_M5:   return "M5";
      case PERIOD_M6:   return "M6";
      case PERIOD_M10:  return "M10";
      case PERIOD_M12:  return "M12";
      case PERIOD_M15:  return "M15";
      case PERIOD_M20:  return "M20";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H2:   return "H2";
      case PERIOD_H3:   return "H3";
      case PERIOD_H4:   return "H4";
      case PERIOD_H6:   return "H6";
      case PERIOD_H8:   return "H8";
      case PERIOD_H12:  return "H12";
      case PERIOD_D1:   return "D1";
   }
   return "?";
}

void ChangeTF(string type, int idx)
{
   string chartIDStr = IntegerToString(ChartID());

   if(type == "STRUCT")
   {
      idxStructure = ClampIdx(idx, ArraySize(StructureTFList));
      StructureTF = StructureTFList[idxStructure];
      UpdateButton("BtnStructure_" + chartIDStr, "STRUCT: " + TFToStr(StructureTF));
   }
   else if(type == "TRIG")
   {
      idxTrigger = ClampIdx(idx, ArraySize(TriggerTFList));
      TriggerTF = TriggerTFList[idxTrigger];
      UpdateButton("BtnTrigger_" + chartIDStr, "TRIG: " + TFToStr(TriggerTF));
   }
   else if(type == "ENTRY")
   {
      idxEntry = ClampIdx(idx, ArraySize(EntryTFList));
      EntryTF = EntryTFList[idxEntry];
      UpdateButton("BtnEntry_" + chartIDStr, "ENTRY: " + TFToStr(EntryTF));
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
   string chartIDStr       = IntegerToString(ChartID());
   string btnStructName    = "BtnStructure_" + chartIDStr;
   string btnTrigName      = "BtnTrigger_"   + chartIDStr;
   string btnEntryName     = "BtnEntry_"     + chartIDStr;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      bool isOurObject = (sparam == btnStructName || sparam == btnTrigName || sparam == btnEntryName ||
                          StringFind(sparam, "ListSt_") == 0 ||
                          StringFind(sparam, "ListTr_") == 0 ||
                          StringFind(sparam, "ListEn_") == 0);
      if(!isOurObject) return;

      // دکمه ها بعد از کلیک در حالت فشرده می‌مانند؛ آزادشان می‌کنیم
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

      // ضد لرزش کلیک — فقط روی کلیک آبجکت های خودمان اعمال می‌شود،
      // نه روی همه رویدادهای چارت (اشکال نسخه قبل)
      ulong now = GetMicrosecondCount();
      if(now - lastClickTime < 100000)   // 0.1 ثانیه
      {
         ChartRedraw();
         return;
      }
      lastClickTime = now;

      if(sparam == btnStructName)
      {
         if(currentListCategory != STRUCTURE) HideTFList(currentListCategory);
         if(isStructureListOpen)
         {
            HideTFList(STRUCTURE);
            isStructureListOpen = false;
            currentListCategory = NONE;
         }
         else
         {
            ShowTFList(STRUCTURE, 140, 10);
            isStructureListOpen = true;
            isTriggerListOpen   = false;
            isEntryListOpen     = false;
            currentListCategory = STRUCTURE;
         }
      }
      else if(sparam == btnTrigName)
      {
         if(currentListCategory != TRIGGER) HideTFList(currentListCategory);
         if(isTriggerListOpen)
         {
            HideTFList(TRIGGER);
            isTriggerListOpen = false;
            currentListCategory = NONE;
         }
         else
         {
            ShowTFList(TRIGGER, 140, 10);
            isTriggerListOpen   = true;
            isStructureListOpen = false;
            isEntryListOpen     = false;
            currentListCategory = TRIGGER;
         }
      }
      else if(sparam == btnEntryName)
      {
         if(currentListCategory != ENTRY) HideTFList(currentListCategory);
         if(isEntryListOpen)
         {
            HideTFList(ENTRY);
            isEntryListOpen = false;
            currentListCategory = NONE;
         }
         else
         {
            ShowTFList(ENTRY, 140, 10);
            isEntryListOpen     = true;
            isStructureListOpen = false;
            isTriggerListOpen   = false;
            currentListCategory = ENTRY;
         }
      }
      else if(StringFind(sparam, "ListSt_") == 0)
      {
         int idx = (int)StringToInteger(StringSubstr(sparam, StringLen("ListSt_")));
         ChangeTF("STRUCT", idx);
         HideTFList(STRUCTURE);
         isStructureListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "ListTr_") == 0)
      {
         int idx = (int)StringToInteger(StringSubstr(sparam, StringLen("ListTr_")));
         ChangeTF("TRIG", idx);
         HideTFList(TRIGGER);
         isTriggerListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "ListEn_") == 0)
      {
         int idx = (int)StringToInteger(StringSubstr(sparam, StringLen("ListEn_")));
         ChangeTF("ENTRY", idx);
         HideTFList(ENTRY);
         isEntryListOpen = false;
         currentListCategory = NONE;
      }

      ChartRedraw();
   }

   if(id == CHARTEVENT_CLICK)
   {
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

      if(StringFind(name, "st_") == 0 || StringFind(name, "tr_") == 0 || StringFind(name, "en_") == 0)
      {
         // فرمت نام: cat_tf_i_len_suffix  →  تایم فریم بین اولین و دومین آندرلاین است
         int p1 = StringFind(name, "_");
         int p2 = (p1 >= 0) ? StringFind(name, "_", p1 + 1) : -1;
         if(p1 < 0 || p2 <= p1 + 1) continue;

         int objTF = (int)StringToInteger(StringSubstr(name, p1 + 1, p2 - p1 - 1));

         // مقادیر ENUM_TIMEFRAMES با مدت زمان کندل هم‌ترتیب هستند،
         // بنابراین مقایسه عددی مستقیم برای تشخیص تایم فریم پایین تر کافی است
         if(objTF < currentTF)
            ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
// آیا لازم است دوباره رسم کنیم؟ فقط با کندل جدید یا تغییر تنظیمات
bool NeedsRedraw()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0) return false;

   if(forceRedraw || t != lastBarTime)
   {
      lastBarTime = t;
      forceRedraw = false;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// تابع مشترک پردازش — این تابع منطق قبلی OnCalculate را اجرا می‌کند
void ProcessIndicator()
{
   // بروزرسانی TFها و حذف آبجکت‌های نامناسب
   CheckTFChangeAndDelete();
   DeleteLowerTFObjects();

   TFCategory cat = GetCategory();
   if(cat == NONE) return;

   int maxLookback = 0;
   if(cat == STRUCTURE)      maxLookback = MaxLookbackStructure;
   else if(cat == TRIGGER)   maxLookback = MaxLookbackTrigger;
   else if(cat == ENTRY)     maxLookback = MaxLookbackEntry;

   if(!NeedsRedraw()) return;

   ENUM_TIMEFRAMES tf = (cat == STRUCTURE) ? StructureTF : (cat == TRIGGER) ? TriggerTF : EntryTF;

   // فقط به تعداد کندل مورد نیاز کپی می‌کنیم — نسخه قبل تمام تاریخچه چارت را
   // هر ثانیه کپی و پردازش می‌کرد که باعث سنگین شدن چارت می‌شد
   int needed = maxLookback + MaxCandles + 10;
   int available = Bars(_Symbol, _Period);
   if(available <= 0) return;
   if(needed > available) needed = available;

   MqlRates rates[];
   ArraySetAsSeries(rates, false);   // ایندکس 0 = قدیمی ترین کندل
   int rates_total = CopyRates(_Symbol, _Period, 0, needed, rates);
   if(rates_total <= MinCandles) return;

   // آبجکت های قبلی همین دسته و همین تایم فریم پاک می‌شوند تا سویینگ ها و
   // FVG هایی که دیگر معتبر نیستند روی چارت باقی نمانند
   DeleteObjectsOfTF(cat, tf);

   color drawColor = GetCategoryColor(cat);
   int tfSecs = PeriodSeconds(tf);

   int start = (int)MathMax(MinCandles, rates_total - maxLookback - MaxCandles);
   int i = rates_total - 1;

   while(i >= start)
   {
      bool swingDetected = false;

      for(int len = MaxCandles; len >= MinCandles; len--)
      {
         if(i - len + 1 < 0) continue;

         int nonStd = 0;
         int bullCount = 0, bearCount = 0;

         for(int j = 0; j < len; j++)
         {
            int idx = i - j;
            double body = MathAbs(rates[idx].close - rates[idx].open);
            double candleSize = rates[idx].high - rates[idx].low;
            double bodyPercent = (candleSize == 0) ? 0 : (body / candleSize) * 100.0;

            if(bodyPercent < MinBodyPercent) nonStd++;

            if(rates[idx].close > rates[idx].open) bullCount++;
            if(rates[idx].close < rates[idx].open) bearCount++;
         }

         if(nonStd > MaxNonStandard) continue;

         bool isBullish = (bearCount <= MaxOppositeCandles);
         bool isBearish = (bullCount <= MaxOppositeCandles);

         if(!isBullish && !isBearish) continue;

         int startIdx = i - len + 1;
         int endIdx   = i;

         // ---------- تعیین A و B با بررسی سه کندل بعد ----------
         datetime timeA = rates[startIdx].time;
         datetime timeB = rates[endIdx].time;
         double priceA = 0.0;
         double priceB = 0.0;
         double midPrice = 0.0;

         int idxA = startIdx;
         int idxB = endIdx;

         if(isBullish)
         {
            double minLow = rates[startIdx].low;
            idxA = startIdx;
            for(int m = startIdx; m <= endIdx; m++)
            {
               if(rates[m].low < minLow)
               {
                  minLow = rates[m].low;
                  idxA = m;
               }
            }
            priceA = minLow;
            timeA  = rates[idxA].time;

            double maxHigh = rates[idxA].high;
            idxB = idxA;
            int maxCheck = (int)MathMin(rates_total - 1, endIdx + 3);
            for(int m = idxA; m <= maxCheck; m++)
            {
               if(rates[m].high > maxHigh)
               {
                  maxHigh = rates[m].high;
                  idxB = m;
               }
            }
            priceB = maxHigh;
            timeB  = rates[idxB].time;

            if(MathAbs(idxB - idxA) + 1 < MinCandles) continue;
            if(idxA == idxB) continue;
         }
         else if(isBearish)
         {
            double maxHighLocal = rates[startIdx].high;
            idxA = startIdx;
            for(int m = startIdx; m <= endIdx; m++)
            {
               if(rates[m].high > maxHighLocal)
               {
                  maxHighLocal = rates[m].high;
                  idxA = m;
               }
            }
            priceA = maxHighLocal;
            timeA  = rates[idxA].time;

            double minLowLocal = rates[idxA].low;
            idxB = idxA;
            int maxCheck = (int)MathMin(rates_total - 1, endIdx + 3);
            for(int m = idxA; m <= maxCheck; m++)
            {
               if(rates[m].low < minLowLocal)
               {
                  minLowLocal = rates[m].low;
                  idxB = m;
               }
            }
            priceB = minLowLocal;
            timeB  = rates[idxB].time;

            if(MathAbs(idxB - idxA) + 1 < MinCandles) continue;
            if(idxA == idxB) continue;
         }
         else
         {
            continue;
         }

         // AB length condition
         double totalRange = 0.0;
         for(int k = startIdx; k <= endIdx; k++)
            totalRange += (rates[k].high - rates[k].low);
         double avgRange = totalRange / len;
         if(avgRange <= 0.0) continue;

         double abLength = MathAbs(priceB - priceA);
         if(abLength < MinABRatio * avgRange || abLength > MaxABRatio * avgRange)
            continue;

         // تعیین نام آبجکت ها
         string prefix = GetPrefix(cat, tf, i, len);

         string lineName    = prefix + "_AB";
         string labelA      = prefix + "_A";
         string labelB      = prefix + "_B";
         string extLine     = prefix + "_BL";
         string midLine     = prefix + "_MID";
         string baseFVGName = prefix + "_FVG";

         // --- بررسی FVG داخل سویینگ بین idxA و idxB
         if(ShowFVG && (cat == STRUCTURE || cat == TRIGGER))
         {
            int startM = idxA + 2;
            if(startM <= idxB)
            {
               for(int m = startM; m <= idxB; m++)
               {
                  if(m >= rates_total) break;
                  string fvgNameLocal = baseFVGName + "_" + IntegerToString(m);   // نام یکتا
                  datetime fvgEndTimeLocal = rates[m].time + tfSecs * FVGExtendCandles;

                  if(isBullish && rates[m].low > rates[m-2].high)
                  {
                     if(ObjectFind(0, fvgNameLocal) >= 0) ObjectDelete(0, fvgNameLocal);
                     ObjectCreate(0, fvgNameLocal, OBJ_RECTANGLE, 0, rates[m-2].time, rates[m].low, fvgEndTimeLocal, rates[m-2].high);
                     ObjectSetInteger(0, fvgNameLocal, OBJPROP_COLOR, drawColor);
                     ObjectSetInteger(0, fvgNameLocal, OBJPROP_BACK, true);
                  }
                  else if(isBearish && rates[m].high < rates[m-2].low)
                  {
                     if(ObjectFind(0, fvgNameLocal) >= 0) ObjectDelete(0, fvgNameLocal);
                     ObjectCreate(0, fvgNameLocal, OBJ_RECTANGLE, 0, rates[m-2].time, rates[m].high, fvgEndTimeLocal, rates[m-2].low);
                     ObjectSetInteger(0, fvgNameLocal, OBJPROP_COLOR, drawColor);
                     ObjectSetInteger(0, fvgNameLocal, OBJPROP_BACK, true);
                  }
               }
            }
         }

         // ادامه‌ی رسم AB (خط، لیبل‌ها و ...)
         if(ObjectFind(0, lineName) >= 0) ObjectDelete(0, lineName);
         ObjectCreate(0, lineName, OBJ_TREND, 0, timeA, priceA, timeB, priceB);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, drawColor);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         if(idxB == rates_total - 1)
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);

         // Labels A & B
         if(ObjectFind(0, labelA) >= 0) ObjectDelete(0, labelA);
         ObjectCreate(0, labelA, OBJ_TEXT, 0, timeA + tfSecs * LabelShiftCandles, priceA);
         ObjectSetInteger(0, labelA, OBJPROP_COLOR, LabelColor);
         ObjectSetString(0, labelA, OBJPROP_TEXT, "A");

         if(ObjectFind(0, labelB) >= 0) ObjectDelete(0, labelB);
         ObjectCreate(0, labelB, OBJ_TEXT, 0, timeB - tfSecs * LabelShiftCandles, priceB);
         ObjectSetInteger(0, labelB, OBJPROP_COLOR, LabelColor);
         ObjectSetString(0, labelB, OBJPROP_TEXT, "B");

         // Line from B — طول آن از ورودی LineBLength خوانده می‌شود (قبلا عدد ثابت 20 بود)
         if(ObjectFind(0, extLine) >= 0) ObjectDelete(0, extLine);
         datetime timeB_ext = timeB + tfSecs * LineBLength;
         ObjectCreate(0, extLine, OBJ_TREND, 0, timeB, priceB, timeB_ext, priceB);
         ObjectSetInteger(0, extLine, OBJPROP_COLOR, drawColor);
         ObjectSetInteger(0, extLine, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, extLine, OBJPROP_RAY_RIGHT, false);

         // Midpoint line
         midPrice = (priceA + priceB) / 2.0;
         if(ObjectFind(0, midLine) >= 0) ObjectDelete(0, midLine);
         datetime timeMid_ext = timeB + tfSecs * LineMidLength;
         ObjectCreate(0, midLine, OBJ_TREND, 0, timeB, midPrice, timeMid_ext, midPrice);
         ObjectSetInteger(0, midLine, OBJPROP_COLOR, drawColor);
         ObjectSetInteger(0, midLine, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, midLine, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, midLine, OBJPROP_RAY_RIGHT, false);

         i = i - len;
         swingDetected = true;
         break;
      }

      if(!swingDetected)
         i--;
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
   // پردازش سنگین فقط در صورت نیاز داخل ProcessIndicator انجام می‌شود
   ProcessIndicator();

   return(rates_total);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   // هر 1 ثانیه اجرا می‌شود (EventSetTimer(1) در OnInit)
   // ProcessIndicator خودش تشخیص می‌دهد که آیا کاری برای انجام هست یا نه
   ProcessIndicator();
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // خاموش کردن تایمر
   EventKillTimer();

   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
   {
      int total = ObjectsTotal(0);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);

         if(StringFind(name, "st_") == 0 ||
            StringFind(name, "tr_") == 0 ||
            StringFind(name, "en_") == 0 ||
            StringFind(name, "ListSt_") == 0 ||
            StringFind(name, "ListTr_") == 0 ||
            StringFind(name, "ListEn_") == 0 ||
            StringFind(name, "BtnStructure_") == 0 ||
            StringFind(name, "BtnTrigger_") == 0 ||
            StringFind(name, "BtnEntry_") == 0 ||
            StringFind(name, "ShinMim_State_") == 0)
         {
            ObjectDelete(0, name);
         }
      }
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
