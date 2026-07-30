//+------------------------------------------------------------------+
//|                                              ShinMim V1.09.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.09"
#property indicator_chart_window

// این اندیکاتور فقط با آبجکت‌های گرافیکی کار می‌کند و هیچ بافری ندارد،
// بنابراین indicator_buffers / indicator_plots تعریف نمی‌شود.

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

//---- تنظیمات نمایش AB
input bool   ShowPreviousABs      = false; // نمایش AB های قبلی (وقتی ABCD خاموش است)
input int    SwingLookAhead       = 3;     // جستجوی B تا چند کندل بعد از پنجره

//---- چرخه عمر الگو ABCD
input bool   EnableABCD           = true;  // ردیابی چرخه عمر و اعتبارسنجی الگو
input int    ABCDHistoryBars      = 300;   // تعداد کندل تاریخچه برای ردیابی الگو
input double RetraceMinPercent    = 20.0;  // حداقل درصد اصلاح از AB
input double RetraceMaxPercent    = 60.0;  // حداکثر درصد اصلاح (با بادی)
input int    MinRetraceCandles    = 3;     // حداقل کندل اصلاح، از کندل بعد از B
input bool   Show20PercentLine    = true;  // رسم خط حداقل اصلاح (20 درصد)
input bool   ShowMaxRetraceLine   = true;  // رسم خط حداکثر اصلاح (60 درصد)
input bool   ShowStateLabel       = true;  // نمایش وضعیت الگو کنار خط B
input bool   ExtendBLineToNow     = true;  // ادامه خط B تا کندل جاری تا وقتی الگو فعال است

//---- کندل شکست
input double BreakMinBodyPercent  = 90.0;  // حداقل درصد بادی کندل شکست
input double BreakMaxWickPercent  = 5.0;   // حداکثر درصد سایه هر طرف
input double BreakMinSizeRatio    = 1.0;   // حداقل اندازه کندل شکست نسبت به میانگین رنج
input double BreakMinDistancePct  = 10.0;  // حداقل فاصله اوپن و کلوز از سطح B (درصد از AB)
input int    BreakMaxCandles      = 3;     // ترکیب حداکثر چند کندل به عنوان یک کندل شکست

//---- سیگنال و هشدار
input bool   ShowEntrySignal      = true;  // نمایش فلش سیگنال ورود
input bool   EnableAlerts         = false; // هشدار در لحظات کلیدی

//+------------------------------------------------------------------+
enum TFCategory { STRUCTURE, TRIGGER, ENTRY, NONE };

// وضعیت الگو در چرخه عمر
enum ABState
{
   AB_FORMING,        // هنوز در حال تشکیل (B روی کندل جاری)
   AB_WAIT_RETRACE,   // AB قطعی شد، منتظر اصلاح معتبر
   AB_RETRACED,       // اصلاح معتبر ثبت شد (C)، منتظر شکست B
   AB_BROKEN,         // B شکسته شد، نقدینگی هانت شد
   AB_DONE,           // قیمت به A رسید، کار الگو تمام
   AB_INVALID         // باطل
};

// یک سویینگ AB به همراه وضعیت چرخه عمر
struct SwingAB
{
   int      idxA;
   int      idxB;
   datetime timeA;
   datetime timeB;
   double   priceA;
   double   priceB;
   bool     isBull;
   double   size;       // |priceB - priceA|
   bool     live;       // B روی کندل جاری بسته نشده است

   ABState  state;

   int      idxC;       // عمیق ترین نقطه اصلاح
   datetime timeC;
   double   priceC;

   int      idxBreakFrom;  // اولین کندل شکست (برای کندل مرکب)
   int      idxBreakTo;    // آخرین کندل شکست
   datetime timeBreak;
   double   breakHigh;
   double   breakLow;

   double   priceD;     // بیشترین نفوذ بعد از شکست

   int      idxSignal;  // کندلی که سیگنال ورود داد
   datetime timeSignal;
   double   priceSignal;
};

// کندل مرکب از چند کندل متوالی
struct Composite
{
   double open, high, low, close;
};

// لیست تایم فریم های برای هر دکمه
ENUM_TIMEFRAMES StructureTFList[9] = {PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H6, PERIOD_H4, PERIOD_H3, PERIOD_H2, PERIOD_H1, PERIOD_M30};
ENUM_TIMEFRAMES TriggerTFList[8]   = {PERIOD_H1, PERIOD_M30, PERIOD_M20, PERIOD_M15, PERIOD_M12, PERIOD_M10, PERIOD_M6, PERIOD_M5};
ENUM_TIMEFRAMES EntryTFList[9]     = {PERIOD_M15, PERIOD_M12, PERIOD_M10, PERIOD_M6, PERIOD_M5, PERIOD_M4, PERIOD_M3, PERIOD_M2, PERIOD_M1};

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
   string catStr = (cat == STRUCTURE) ? "st_" : (cat == TRIGGER) ? "tr_" : (cat == ENTRY) ? "en_" : "xx_";
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

// پاکسازی آبجکت های نسخه های قدیمی تر.
// نام گذاری قبل از 1.06 شامل "_TF" بود و نام گذاری فعلی هرگز "_TF" تولید نمی‌کند.
// نکته مهم: اینجا نباید همه آبجکت ها پاک شوند. متاتریدر با هر تغییر تایم فریم
// چارت دوباره OnInit را صدا می‌زند و پاکسازی کامل، آبجکت های تایم فریم بالاتر را
// که باید روی تایم فریم پایین تر باقی بمانند از بین می‌برد.
void DeleteLegacyObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      bool isOurs = (StringFind(name, "st_") == 0 || StringFind(name, "tr_") == 0 || StringFind(name, "en_") == 0);
      if(isOurs && StringFind(name, "_TF") >= 0)
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

   if(cat == STRUCTURE)   { prefix = "ListSt_"; count = ArraySize(StructureTFList); }
   else if(cat == TRIGGER){ prefix = "ListTr_"; count = ArraySize(TriggerTFList);   }
   else if(cat == ENTRY)  { prefix = "ListEn_"; count = ArraySize(EntryTFList);     }
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

int ClampIdx(int idx, int size)
{
   if(idx < 0) return 0;
   if(idx >= size) return size - 1;
   return idx;
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

int OnInit()
{
   string chartIDStr = IntegerToString(ChartID());
   stateObjName = "ShinMim_State_" + chartIDStr;

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

   // فقط باقیمانده نسخه های قدیمی تر پاک می‌شود، نه همه آبجکت ها
   DeleteLegacyObjects();

   CreateTFButton("BtnStructure_" + chartIDStr, 10, 10, "STRUCT: " + TFToStr(StructureTF));
   CreateTFButton("BtnTrigger_"   + chartIDStr, 10, 40, "TRIG: "   + TFToStr(TriggerTF));
   CreateTFButton("BtnEntry_"     + chartIDStr, 10, 70, "ENTRY: "  + TFToStr(EntryTF));

   lastBarTime      = 0;
   forceRedraw      = true;
   lastConfirmedSig = "";

   EventSetTimer(1);

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
   string chartIDStr    = IntegerToString(ChartID());
   string btnStructName = "BtnStructure_" + chartIDStr;
   string btnTrigName   = "BtnTrigger_"   + chartIDStr;
   string btnEntryName  = "BtnEntry_"     + chartIDStr;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      bool isOurObject = (sparam == btnStructName || sparam == btnTrigName || sparam == btnEntryName ||
                          StringFind(sparam, "ListSt_") == 0 ||
                          StringFind(sparam, "ListTr_") == 0 ||
                          StringFind(sparam, "ListEn_") == 0);
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
      else if(StringFind(sparam, "ListSt_") == 0)
      {
         ChangeTF("STRUCT", (int)StringToInteger(StringSubstr(sparam, StringLen("ListSt_"))));
         HideTFList(STRUCTURE);
         isStructureListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "ListTr_") == 0)
      {
         ChangeTF("TRIG", (int)StringToInteger(StringSubstr(sparam, StringLen("ListTr_"))));
         HideTFList(TRIGGER);
         isTriggerListOpen = false;
         currentListCategory = NONE;
      }
      else if(StringFind(sparam, "ListEn_") == 0)
      {
         ChangeTF("ENTRY", (int)StringToInteger(StringSubstr(sparam, StringLen("ListEn_"))));
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

      if(StringFind(name, "st_") == 0 || StringFind(name, "tr_") == 0 || StringFind(name, "en_") == 0)
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
// جمع آوری سویینگ ها بدون رسم. خروجی به ترتیب زمانی (قدیمی → جدید).
int CollectSwings(MqlRates &rates[], int rates_total, int scanFrom, SwingAB &out[])
{
   ArrayResize(out, rates_total);
   int cnt = 0;

   int start = (int)MathMax(MinCandles, scanFrom);
   int i = rates_total - 1;

   // کوچکترین idxA پذیرفته شده تا این لحظه. چون از جدید به قدیم می‌رویم،
   // هر کاندیدی که idxB آن به این مقدار برسد یعنی داخل سویینگ قبلی افتاده است.
   int lastAcceptedA = rates_total;

   while(i >= start)
   {
      bool found = false;

      for(int len = MaxCandles; len >= MinCandles; len--)
      {
         if(i - len + 1 < 0) continue;

         int nonStd = 0, bullCount = 0, bearCount = 0;

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
         int maxCheck = (int)MathMin(rates_total - 1, endIdx + SwingLookAhead);

         int    idxA = startIdx, idxB = startIdx;
         double priceA = 0.0, priceB = 0.0;

         if(isBullish)
         {
            double minLow = rates[startIdx].low;
            for(int m = startIdx; m <= endIdx; m++)
               if(rates[m].low < minLow) { minLow = rates[m].low; idxA = m; }
            priceA = minLow;

            double maxHigh = rates[idxA].high;
            idxB = idxA;
            for(int m = idxA; m <= maxCheck; m++)
               if(rates[m].high > maxHigh) { maxHigh = rates[m].high; idxB = m; }
            priceB = maxHigh;
         }
         else
         {
            double maxHighLocal = rates[startIdx].high;
            for(int m = startIdx; m <= endIdx; m++)
               if(rates[m].high > maxHighLocal) { maxHighLocal = rates[m].high; idxA = m; }
            priceA = maxHighLocal;

            double minLowLocal = rates[idxA].low;
            idxB = idxA;
            for(int m = idxA; m <= maxCheck; m++)
               if(rates[m].low < minLowLocal) { minLowLocal = rates[m].low; idxB = m; }
            priceB = minLowLocal;
         }

         if(idxA == idxB) continue;
         if(idxB - idxA + 1 < MinCandles) continue;

         // جلوگیری از AB تو در تو
         if(idxB >= lastAcceptedA) continue;

         double totalRange = 0.0;
         for(int k = startIdx; k <= endIdx; k++)
            totalRange += (rates[k].high - rates[k].low);
         double avgRange = totalRange / len;
         if(avgRange <= 0.0) continue;

         double abLength = MathAbs(priceB - priceA);
         if(abLength < MinABRatio * avgRange || abLength > MaxABRatio * avgRange)
            continue;

         out[cnt].idxA         = idxA;
         out[cnt].idxB         = idxB;
         out[cnt].timeA        = rates[idxA].time;
         out[cnt].timeB        = rates[idxB].time;
         out[cnt].priceA       = priceA;
         out[cnt].priceB       = priceB;
         out[cnt].isBull       = isBullish;
         out[cnt].size         = abLength;
         out[cnt].live         = (idxB == rates_total - 1);
         out[cnt].state        = AB_FORMING;
         out[cnt].idxC         = -1;
         out[cnt].timeC        = 0;
         out[cnt].priceC       = 0.0;
         out[cnt].idxBreakFrom = -1;
         out[cnt].idxBreakTo   = -1;
         out[cnt].timeBreak    = 0;
         out[cnt].breakHigh    = 0.0;
         out[cnt].breakLow     = 0.0;
         out[cnt].priceD       = 0.0;
         out[cnt].idxSignal    = -1;
         out[cnt].timeSignal   = 0;
         out[cnt].priceSignal  = 0.0;
         cnt++;

         lastAcceptedA = idxA;
         i = idxA - 1;      // پرش به قبل از A، نه فقط به اندازه طول پنجره
         found = true;
         break;
      }

      if(!found) i--;
   }

   // معکوس کردن به ترتیب زمانی
   SwingAB tmp;
   for(int a = 0, b = cnt - 1; a < b; a++, b--)
   {
      tmp    = out[a];
      out[a] = out[b];
      out[b] = tmp;
   }

   ArrayResize(out, cnt);
   return cnt;
}

//+------------------------------------------------------------------+
// ساخت کندل مرکب از چند کندل متوالی
void BuildComposite(MqlRates &rates[], int from, int to, Composite &c)
{
   c.open  = rates[from].open;
   c.close = rates[to].close;
   c.high  = rates[from].high;
   c.low   = rates[from].low;

   for(int m = from; m <= to; m++)
   {
      if(rates[m].high > c.high) c.high = rates[m].high;
      if(rates[m].low  < c.low)  c.low  = rates[m].low;
   }
}

// کندل شکست معتبر:
//   بادی حداقل BreakMinBodyPercent درصد کل کندل
//   هیچ طرف سایه بیش از BreakMaxWickPercent درصد نداشته باشد
//   کندل خیلی کوچک نباشد (نسبت به میانگین رنج)
//   اوپن و کلوز هر دو به اندازه کافی از سطح B فاصله داشته باشند
bool IsValidBreak(Composite &c, bool isBull, double bLevel, double abSize, double avgRange)
{
   double range = c.high - c.low;
   if(range <= 0.0) return false;

   double body = MathAbs(c.close - c.open);
   if(body / range * 100.0 < BreakMinBodyPercent) return false;

   double upperWick = c.high - MathMax(c.open, c.close);
   double lowerWick = MathMin(c.open, c.close) - c.low;
   if(upperWick / range * 100.0 > BreakMaxWickPercent) return false;
   if(lowerWick / range * 100.0 > BreakMaxWickPercent) return false;

   // کندل نباید خیلی کوچک باشد
   if(avgRange > 0.0 && range < BreakMinSizeRatio * avgRange) return false;

   // اوپن و کلوز نباید نزدیک سطح B باشند
   double minDist = abSize * BreakMinDistancePct / 100.0;

   if(isBull)
   {
      if(c.close < bLevel + minDist) return false;   // کلوز باید کافی بالاتر از B باشد
      if(c.open  > bLevel - minDist) return false;   // اوپن باید کافی پایین تر از B باشد
   }
   else
   {
      if(c.close > bLevel - minDist) return false;
      if(c.open  < bLevel + minDist) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
// بازپخش چرخه عمر یک AB از کندل بعد از B تا کندل جاری.
// وضعیت کاملا از روی قیمت بازسازی می‌شود، پس نیازی به ذخیره سازی حالت نیست.
void EvaluateLifecycle(SwingAB &s, MqlRates &rates[], int rates_total, double avgRange)
{
   if(s.live)
   {
      s.state = AB_FORMING;
      return;
   }

   s.state = AB_WAIT_RETRACE;

   // سطوح اصلاح نسبت به B، در جهت مخالف حرکت AB
   double dir      = s.isBull ? -1.0 : 1.0;   // اصلاح AB صعودی، نزولی است
   double levelMin = s.priceB + dir * s.size * RetraceMinPercent / 100.0;
   double levelMax = s.priceB + dir * s.size * RetraceMaxPercent / 100.0;

   double deepest = s.priceB;   // عمیق ترین نقطه اصلاح تا این لحظه

   // فقط کندل های بسته شده بررسی می‌شوند. کندل جاری هنوز می‌تواند تغییر کند و
   // اگر آن را حساب کنیم وضعیت الگو وسط کندل بالا و پایین می‌رود (repaint).
   for(int m = s.idxB + 1; m <= rates_total - 2; m++)
   {
      // ردیابی اصلاح تا لحظه شکست B ادامه دارد، نه فقط تا وقتی معتبر شود.
      // وگرنه اگر قیمت بعد از معتبر شدن اصلاح عمیق تر برود، نه C بروز می‌شود
      // و نه حد حداکثر اصلاح دیگر بررسی می‌شود.
      if(s.state == AB_WAIT_RETRACE || s.state == AB_RETRACED)
      {
         // بروزرسانی عمیق ترین نقطه اصلاح (C)
         double ext = s.isBull ? rates[m].low : rates[m].high;
         bool deeper = s.isBull ? (ext < deepest) : (ext > deepest);
         if(deeper)
         {
            deepest  = ext;
            s.idxC   = m;
            s.timeC  = rates[m].time;
            s.priceC = ext;
         }

         // باطل: بادی از حداکثر درصد مجاز اصلاح رد شود (سایه ایراد ندارد)
         double bodyExt = s.isBull ? MathMin(rates[m].open, rates[m].close)
                                   : MathMax(rates[m].open, rates[m].close);
         bool bodyBeyondMax = s.isBull ? (bodyExt < levelMax) : (bodyExt > levelMax);
         if(bodyBeyondMax)
         {
            s.state = AB_INVALID;
            return;
         }

         if(s.state == AB_WAIT_RETRACE)
         {
            bool retraceDeepEnough = s.isBull ? (deepest <= levelMin) : (deepest >= levelMin);
            bool enoughCandles     = ((m - s.idxB) >= MinRetraceCandles);

            // باطل: قیمت سطح B را بشکند بدون اینکه اصلاح کافی رخ داده باشد
            bool touchedB = s.isBull ? (rates[m].high > s.priceB) : (rates[m].low < s.priceB);
            if(touchedB && !(retraceDeepEnough && enoughCandles))
            {
               s.state = AB_INVALID;
               return;
            }

            // بدون continue، اگر اصلاح در همین کندل معتبر شد، شکست هم در همین
            // کندل بررسی می‌شود و یک کندل عقب نمی‌افتیم
            if(retraceDeepEnough && enoughCandles)
               s.state = AB_RETRACED;
            else
               continue;
         }
      }

      if(s.state == AB_RETRACED)
      {
         // دنبال کندل شکست معتبر (تکی یا مرکب از 2 تا BreakMaxCandles کندل)
         for(int n = 1; n <= BreakMaxCandles; n++)
         {
            int from = m - n + 1;
            if(from <= s.idxC) break;   // کندل مرکب نباید از C عقب تر برود

            Composite c;
            BuildComposite(rates, from, m, c);

            if(IsValidBreak(c, s.isBull, s.priceB, s.size, avgRange))
            {
               s.state        = AB_BROKEN;
               s.idxBreakFrom = from;
               s.idxBreakTo   = m;
               s.timeBreak    = rates[m].time;
               s.breakHigh    = c.high;
               s.breakLow     = c.low;
               s.priceD       = s.isBull ? c.high : c.low;
               break;
            }
         }
         continue;
      }

      if(s.state == AB_BROKEN)
      {
         // ردیابی D (بیشترین نفوذ)
         if(s.isBull) { if(rates[m].high > s.priceD) s.priceD = rates[m].high; }
         else         { if(rates[m].low  < s.priceD) s.priceD = rates[m].low;  }

         // باطل: CD بزرگتر از AB شود
         if(MathAbs(s.priceD - s.priceC) > s.size)
         {
            s.state = AB_INVALID;
            return;
         }

         // سیگنال ورود: کندلی که آن طرف کندل شکست بسته شود
         if(s.idxSignal < 0)
         {
            bool signalled = s.isBull ? (rates[m].close < s.breakLow)
                                      : (rates[m].close > s.breakHigh);
            if(signalled)
            {
               s.idxSignal   = m;
               s.timeSignal  = rates[m].time;
               s.priceSignal = rates[m].close;
            }
         }

         // پایان: قیمت به A رسید
         bool reachedA = s.isBull ? (rates[m].low <= s.priceA) : (rates[m].high >= s.priceA);
         if(reachedA)
         {
            s.state = AB_DONE;
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
// کاهش زنجیره AB ها (فقط وقتی چرخه عمر خاموش است):
//   خلاف جهت → هر دو؛ هم جهت + جدید بزرگتر → قبلی حذف؛ هم جهت + جدید کوچکتر → هر دو
int ReduceSwings(SwingAB &src[], int n, SwingAB &dst[])
{
   ArrayResize(dst, n);
   int m = 0;

   for(int k = 0; k < n; k++)
   {
      while(m > 0 && dst[m-1].isBull == src[k].isBull && src[k].size > dst[m-1].size)
         m--;

      dst[m] = src[k];
      m++;
   }

   return m;
}

//+------------------------------------------------------------------+
string StateText(ABState st)
{
   switch(st)
   {
      case AB_FORMING:      return "...";
      case AB_WAIT_RETRACE: return "WAIT";
      case AB_RETRACED:     return "C ok";
      case AB_BROKEN:       return "HUNT";
      case AB_DONE:         return "DONE";
      case AB_INVALID:      return "X";
   }
   return "";
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
   if(s.idxC >= 0 && (s.state == AB_RETRACED || s.state == AB_BROKEN))
   {
      string labelC = base + "_C";
      if(ObjectFind(0, labelC) >= 0) ObjectDelete(0, labelC);
      ObjectCreate(0, labelC, OBJ_TEXT, 0, s.timeC, s.priceC);
      ObjectSetInteger(0, labelC, OBJPROP_COLOR, LabelColor);
      ObjectSetString(0, labelC, OBJPROP_TEXT, "C");
   }

   // --- علامت کندل شکست
   if(s.state == AB_BROKEN && s.idxBreakTo >= 0)
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
      ObjectSetString(0, stName, OBJPROP_TEXT, "  " + StateText(s.state));
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
      Alert("ShinMim ", tag, ": سیگنال ورود");
   else if(s.state == AB_BROKEN && s.idxBreakTo == lastClosed)
      Alert("ShinMim ", tag, ": شکست سطح B - برو تایم پایین تر");
   else if(s.state == AB_RETRACED && s.idxC == lastClosed)
      Alert("ShinMim ", tag, ": اصلاح معتبر شد (C)");
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
   bool lifecycle = UsesLifecycle(cat);

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == 0) return;

   // با چرخه عمر، تاریخچه بلندتری لازم است تا الگویی که مدت‌ها پیش شکل گرفته
   // و هنوز معتبر است از پنجره اسکن بیرون نیفتد.
   int needed;
   if(lifecycle) needed = ABCDHistoryBars;
   else          needed = maxLookback + MaxCandles + SwingLookAhead + 10;

   int available = Bars(_Symbol, _Period);
   if(available <= 0) return;
   if(needed > available) needed = available;

   MqlRates rates[];
   ArraySetAsSeries(rates, false);   // ایندکس 0 = قدیمی ترین کندل
   int rates_total = CopyRates(_Symbol, _Period, 0, needed, rates);
   if(rates_total <= MinCandles) return;

   // میانگین رنج کندل ها برای سنجش «کندل خیلی کوچک نباشد»
   double sumRange = 0.0;
   for(int m = 0; m < rates_total; m++)
      sumRange += (rates[m].high - rates[m].low);
   double avgRange = sumRange / rates_total;

   // با چرخه عمر کل تاریخچه اسکن می‌شود، وگرنه فقط پنجره lookback
   int scanFrom = lifecycle ? MinCandles : (rates_total - maxLookback - MaxCandles);

   SwingAB raw[];
   int nRaw = CollectSwings(rates, rates_total, scanFrom, raw);

   SwingAB kept[];
   int nKept = 0;

   if(lifecycle)
   {
      // چرخه عمر هر AB بازپخش می‌شود و فقط الگوهای فعال نگه داشته می‌شوند
      ArrayResize(kept, nRaw);
      for(int k = 0; k < nRaw; k++)
      {
         EvaluateLifecycle(raw[k], rates, rates_total, avgRange);

         if(raw[k].state == AB_INVALID || raw[k].state == AB_DONE)
            continue;

         kept[nKept] = raw[k];
         nKept++;
      }
      ArrayResize(kept, nKept);
   }
   else
   {
      nKept = ReduceSwings(raw, nRaw, kept);
      for(int k = 0; k < nKept; k++)
         kept[k].state = kept[k].live ? AB_FORMING : AB_WAIT_RETRACE;

      // بدون چرخه عمر، پیش فرض فقط دو AB آخر
      if(!ShowPreviousABs && nKept > 2)
      {
         int firstIdx = nKept - 2;
         for(int k = 0; k < 2; k++)
            kept[k] = kept[firstIdx + k];
         nKept = 2;
         ArrayResize(kept, nKept);
      }
   }

   // تایم ورود فقط آخرین AB را نگه می‌دارد
   if(cat == ENTRY && nKept > 1)
   {
      kept[0] = kept[nKept - 1];
      nKept = 1;
      ArrayResize(kept, nKept);
   }

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

      if(fullRedraw && lifecycle)
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
