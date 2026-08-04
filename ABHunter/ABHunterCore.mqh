//+------------------------------------------------------------------+
//|                                        ABHunterCore.mqh   v2.71   |
//|                                                                  |
//| منطق مشترک تشخیص سویینگ و چرخه عمر الگوی ABCD.                   |
//| هم ABHunter.mq5 (اندیکاتور چارت) و هم ABHunterScanner.mq5           |
//| (اسکنر چند نمادی) این فایل را include می‌کنند تا قواعد تشخیص      |
//| یک منبع واحد داشته باشند و بین دو فایل واگرا نشوند.               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//---- تنظیمات تشخیص سویینگ
input int    MinCandles           = 3;
input int    MaxCandles           = 10;   // طول پنجره تشخیص، نه طول خود سویینگ
input int    MaxABSpan            = 30;   // حداکثر طول سویینگ AB بر حسب کندل
input int    MaxOppositeCandles   = 1;
input double MinBodyPercent       = 50.0;  // حداقل درصد بادی کندل (0 تا 100)
input int    MaxNonStandard       = 1;
input double MinABRatio           = 1.0;
input double MaxABRatio           = 8.0;

//---- تحمل کندل مخالف در محدوده AB
// عدد ثابت MaxOppositeCandles برای پنجره کوتاه تشخیص خوب است، ولی محدوده
// [idxA, idxB] می‌تواند خیلی بلندتر باشد و آنجا عدد ثابت هر ایمپالس چند کندلی
// که یکی دو پولبک کوچک دارد را رد می‌کند. پس سهم مجاز نسبی است.
input double AbOppositePercent    = 30.0;  // درصد مجاز کندل مخالف در محدوده AB

//---- مومنتم سویینگ
input double MomentumMinPercent   = 60.0;  // حداقل درصد AB که باید با بدنه پوشیده شود
input int    MaxNonProgressive    = 1;     // چند کندل مجاز است سقف بالاتر از کندل قبل نسازد

//---- چرخه عمر الگو ABCD
input bool   EnableABCD           = true;  // ردیابی چرخه عمر و اعتبارسنجی الگو
input int    ABCDHistoryBars      = 300;   // تعداد کندل تاریخچه برای ردیابی الگو
input double RetraceMinPercent    = 20.0;  // حداقل درصد اصلاح از AB
input double RetraceMaxPercent    = 60.0;  // حداکثر درصد اصلاح (با بادی)
input int    BConfirmBars        = 3;     // کندل صفر تا چند کندل بعد، B را تثبیت می‌کند
input int    MinRetraceCandles    = 3;     // حداقل کندل اصلاح، از کندل بعد از تثبیت B
input int    MaxRetraceBars       = 24;    // حداکثر کندل از B تا حالا (0 = بی نهایت)
input int    MaxPatternDays       = 0;     // سقف روز تقویمی (0 = خاموش؛ روی تایم بالا نگذارید)
input bool   HideCounterABInRetrace = true; // پنهان کردن AB خلاف جهت که خودش اصلاح الگوی بزرگتر است

//---- کندل شکست
input double BreakMinBodyPercent  = 90.0;  // حداقل درصد بادی کندل شکست
input double BreakMaxWickPercent  = 5.0;   // حداکثر درصد سایه هر طرف
input double BreakMinSizeRatio    = 1.0;   // حداقل اندازه کندل شکست نسبت به میانگین رنج
input double BreakMinDistancePct  = 10.0;  // حداقل فاصله اوپن و کلوز از سطح B (درصد از AB)
input int    BreakMaxCandles      = 3;     // ترکیب حداکثر چند کندل به عنوان یک کندل شکست

//+------------------------------------------------------------------+
// لیست تایم فریم های هر دکمه. اینجا هستند تا اسکنر بتواند اندیس ذخیره شده
// روی چارت را دقیقا مثل خود اندیکاتور به تایم فریم تبدیل کند.
ENUM_TIMEFRAMES StructureTFList[9] = {PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H6, PERIOD_H4, PERIOD_H3, PERIOD_H2, PERIOD_H1, PERIOD_M30};
ENUM_TIMEFRAMES TriggerTFList[8]   = {PERIOD_H1, PERIOD_M30, PERIOD_M20, PERIOD_M15, PERIOD_M12, PERIOD_M10, PERIOD_M6, PERIOD_M5};
ENUM_TIMEFRAMES EntryTFList[9]     = {PERIOD_M15, PERIOD_M12, PERIOD_M10, PERIOD_M6, PERIOD_M5, PERIOD_M4, PERIOD_M3, PERIOD_M2, PERIOD_M1};

// نام آبجکت مخفی که اندیکاتور انتخاب سه دکمه را در آن ذخیره می‌کند.
// اسکنر همین نام را روی چارت های باز می‌گردد تا تایم فریم ها را بخواند.
string StateObjectName(long chartId)
{
   return "ABH_State_" + IntegerToString(chartId);
}

// نام آبجکتی که اندیکاتور چارت اثر انگشت تنظیمات تشخیصش را در آن می‌گذارد.
string ConfigObjectName(long chartId)
{
   return "ABH_Cfg_" + IntegerToString(chartId);
}

// اثر انگشت همه ورودی هایی که روی تشخیص اثر دارند.
//
// این ورودی ها در ABHunterCore.mqh تعریف شده اند ولی متاتریدر برای هر .mq5
// یک کپی جدا از مقادیرشان نگه می‌دارد. یعنی اسکنر و اندیکاتور چارت می‌توانند
// بی سروصدا با قواعد متفاوت کار کنند و همین باعث می‌شود جدول الگویی را بگوید
// که روی چارت نیست. اسکنر این اثر انگشت را با مال خودش مقایسه می‌کند و اگر
// فرق داشت در سربرگ هشدار می‌دهد.
string CoreConfigSignature()
{
   long h = 0;

   h = h * 31 + MinCandles;
   h = h * 31 + MaxCandles;
   h = h * 31 + MaxABSpan;
   h = h * 31 + MaxOppositeCandles;
   h = h * 31 + (long)(MinBodyPercent * 10);
   h = h * 31 + MaxNonStandard;
   h = h * 31 + (long)(MinABRatio * 10);
   h = h * 31 + (long)(MaxABRatio * 10);
   h = h * 31 + (long)(AbOppositePercent * 10);
   h = h * 31 + (long)(MomentumMinPercent * 10);
   h = h * 31 + MaxNonProgressive;
   h = h * 31 + (EnableABCD ? 1 : 0);
   h = h * 31 + ABCDHistoryBars;
   h = h * 31 + (long)(RetraceMinPercent * 10);
   h = h * 31 + (long)(RetraceMaxPercent * 10);
   h = h * 31 + BConfirmBars;
   h = h * 31 + MinRetraceCandles;
   h = h * 31 + MaxRetraceBars;
   h = h * 31 + MaxPatternDays;
   h = h * 31 + (HideCounterABInRetrace ? 1 : 0);
   h = h * 31 + (long)(BreakMinBodyPercent * 10);
   h = h * 31 + (long)(BreakMaxWickPercent * 10);
   h = h * 31 + (long)(BreakMinSizeRatio * 10);
   h = h * 31 + (long)(BreakMinDistancePct * 10);
   h = h * 31 + BreakMaxCandles;

   if(h < 0) h = -h;
   return IntegerToString(h % 1000000);
}

int ClampIdx(int idx, int size)
{
   if(idx < 0) return 0;
   if(idx >= size) return size - 1;
   return idx;
}

//+------------------------------------------------------------------+
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

// چرا الگو باطل شد. روی چارت و در جدول اسکنر نوشته می‌شود تا معلوم باشد
// اندیکاتور به چه دلیلی الگو را کنار گذاشته و بشود درستی اش را بررسی کرد.
enum ABDeadReason
{
   AB_ALIVE = 0,
   AB_DEAD_RETRACE,    // بادی اصلاح از RetraceMaxPercent رد شد
   AB_DEAD_BEARLY,     // B قبل از ثبت یک C معتبر برداشته شد
   AB_DEAD_CD,         // طول CD (با بادی) از AB بیشتر شد
   AB_DEAD_EXPIRED,    // از سقف کندل های فاز اصلاح گذشت
   AB_DEAD_HITA        // قیمت به A رسید — پایان طبیعی، نه خطا
};

// کد کوتاه برای ستون جدول. عرض جدول نباید زیاد شود، پس حداکثر ۷ کاراکتر.
string DeadReasonText(ABDeadReason r)
{
   switch(r)
   {
      case AB_DEAD_RETRACE: return "X >60%";
      case AB_DEAD_BEARLY:  return "X earlyB";
      case AB_DEAD_CD:      return "X CD>AB";
      case AB_DEAD_EXPIRED: return "X old";
      case AB_DEAD_HITA:    return "DONE";
   }
   return "";
}

// یک سویینگ AB به همراه وضعیت چرخه عمر
struct SwingAB
{
   int      idxA;
   int      idxB;      // کندلی که سطح B روی آن است (ممکن است شدو باشد)
   int      idxZero;   // «کندل صفر»: آخرین کندل خود لگ
   datetime timeA;
   datetime timeB;
   double   priceA;
   double   priceB;
   bool     isBull;
   double   size;       // |priceB - priceA|
   bool     live;       // B روی کندل جاری بسته نشده است

   ABState  state;

   int      idxC;       // عمیق ترین نقطه اصلاح (با سایه، برای رسم)
   datetime timeC;
   double   priceC;
   double   priceCBody; // همان نقطه ولی با بدنه، برای سنجش CD

   bool     hasValidBreak; // کندل شکست معتبر تایید شده است
   int      idxBreakFrom;  // اولین کندل شکست (برای کندل مرکب)
   int      idxBreakTo;    // آخرین کندل شکست
   datetime timeBreak;
   double   breakHigh;
   double   breakLow;

   int      idxHunt;    // کندلی که B در آن برداشته شد (-1 یعنی هنوز نشده)
   datetime timeHunt;
   double   priceD;     // بیشترین نفوذ بعد از شکست

   int      idxSignal;  // کندلی که سیگنال ورود داد
   datetime timeSignal;
   double   priceSignal;

   ABDeadReason deadReason;  // اگر باطل شده، چرا
   datetime     deadTime;    // زمان کندلی که در آن باطل شد
};

// کندل مرکب از چند کندل متوالی
struct Composite
{
   double open, high, low, close;
};

//+------------------------------------------------------------------+
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

string StateText(SwingAB &s)
{
   switch(s.state)
   {
      case AB_FORMING:      return "...";
      case AB_WAIT_RETRACE: return "WAIT";
      case AB_RETRACED:     return "C ok";
      // HUNT یعنی قیمت از B رد شد؛ BREAK یعنی کندل شکست هم معتبر بود
      case AB_BROKEN:       return s.hasValidBreak ? "BREAK" : "HUNT";
      case AB_DONE:         return "DONE";
      case AB_INVALID:      return "X";
   }
   return "";
}

//+------------------------------------------------------------------+
// جمع آوری سویینگ ها بدون رسم. خروجی به ترتیب زمانی (قدیمی → جدید).
// همه شرط های اعتبار یک نامزد AB روی محدوده واقعی [idxA, idxB].
// جدا شده تا بشود دو نامزد را با یک منطق سنجید: اول A روی مبدا واقعی حرکت،
// و اگر لگ از آنجا تمیز نبود همان A کوتاه تر.
bool ValidateAB(MqlRates &rates[], int idxA, int idxB,
                double priceA, double priceB, bool isBullish)
{
   if(idxA >= idxB) return false;
   if(idxB - idxA + 1 < MinCandles) return false;

   // --- شمارش روی محدوده واقعی AB، نه روی پنجره تشخیص.
   // این دو یکی نیستند: A تا مبدا حرکت به عقب می‌رود و B تا اولین اصلاح به
   // جلو. بدون این بررسی، شرط «حداقل MinCandles کندل هم جهت» روی خود AB
   // تضمین نمی‌شود و مثلا 2 کندل صعودی با یک کندل مخالف قبول می‌شد.
   int abBull = 0, abBear = 0;
   int abTotal = idxB - idxA + 1;

   // علاوه بر تعداد، حجم بدنه هم شمرده می‌شود: یک کندل مخالف بزرگ حتی اگر
   // «فقط یکی» باشد ایمپالس را از بین می‌برد.
   double sameBody = 0.0, oppBody = 0.0;

   for(int m = idxA; m <= idxB; m++)
   {
      double abBody  = MathAbs(rates[m].close - rates[m].open);
      double abRange = rates[m].high - rates[m].low;
      double abPct   = (abRange == 0) ? 0 : (abBody / abRange) * 100.0;

      if(abPct < MinBodyPercent)
      {
         continue;               // کندل بی بدنه نه هم جهت است نه مخالف
      }

      bool up = (rates[m].close > rates[m].open);
      bool dn = (rates[m].close < rates[m].open);

      // کندلی که خود B را ساخته، کندل چرخش است. مخالف بودنش ذاتِ نقطه چرخش
      // است نه ضعف ایمپالس؛ پس نه در تعداد و نه در حجم بدنه جریمه نمی‌شود.
      // بدون این استثنا، یک لگ تمیز که با کندل برگشت تمام می‌شود دو بار
      // جریمه می‌شد و رد می‌گشت. اگر همان کندل هم جهت لگ باشد عادی شمرده
      // می‌شود؛ این استثنا فقط سمت مخالف را می‌بخشد.
      bool isOpposite = isBullish ? dn : up;
      if(isOpposite && m == idxB) continue;

      if(up) abBull++;
      if(dn) abBear++;

      if(isBullish) { if(up) sameBody += abBody; else if(dn) oppBody += abBody; }
      else          { if(dn) sameBody += abBody; else if(up) oppBody += abBody; }
   }

   if(sameBody <= 0.0) return false;
   if(oppBody > sameBody * AbOppositePercent / 100.0) return false;

   // سهم مجاز نسبی است، ولی هیچ وقت کمتر از عدد ثابت ورودی نمی‌شود.
   double abShare = abTotal * AbOppositePercent / 100.0;
   int maxOpp     = (int)MathMax((double)MaxOppositeCandles, abShare);

   // عمدا سقفی روی تعداد کندل های بی بدنه داخل [idxA, idxB] گذاشته نمی‌شود.
   // کندل با بدنه کمتر از MinBodyPercent در یک لگ واقعی کاملا عادی است، و
   // چون A به عقب و B به جلو بسط پیدا می‌کنند این محدوده می‌تواند بلند باشد.
   // سنجش ۳۹۹۵۲ رد شدن در شبیه ساز (پوشه tools) نشان داد همین شرط به تنهایی
   // بیشترین سویینگ درست را حذف می‌کرد.
   //
   // محافظت لازم از جای دیگر می‌آید و به طول محدوده حساس نیست:
   //   abBull/abBear >= MinCandles  →  حداقل سه کندل جهت دار واقعی
   //   مومنتم ۲                      →  بدنه ها باید بخش عمده طول AB را بپوشانند
   if(isBullish) { if(abBull < MinCandles || abBear > maxOpp) return false; }
   else          { if(abBear < MinCandles || abBull > maxOpp) return false; }

   // میانگین رنج روی خود محدوده AB حساب می‌شود، نه روی پنجره تشخیص —
   // حالا که هر دو سر سویینگ باز می‌شود این دو می‌توانند خیلی متفاوت باشند.
   double totalRange = 0.0;
   for(int k = idxA; k <= idxB; k++)
      totalRange += (rates[k].high - rates[k].low);
   double avgRange = totalRange / abTotal;
   if(avgRange <= 0.0) return false;

   double abLength = MathAbs(priceB - priceA);

   // سقف نسبت با طول سویینگ رشد می‌کند: یک ایمپالس ۲۰ کندلی طبیعتا چند برابر
   // یک ایمپالس ۵ کندلی است و نباید فقط به خاطر طولش رد شود.
   double spanScale = MathMax(1.0, (double)abTotal / (double)MaxCandles);
   if(abLength < MinABRatio * avgRange || abLength > MaxABRatio * avgRange * spanScale)
      return false;

   // --- مومنتم 1: حرکت باید پله ای باشد (سقف بالاتر از کندل قبل)
   int nonProgressive = 0;
   for(int m = idxA + 1; m <= idxB; m++)
   {
      bool progressed = isBullish ? (rates[m].high > rates[m-1].high)
                                  : (rates[m].low  < rates[m-1].low);
      if(!progressed) nonProgressive++;
   }
   if(nonProgressive > (int)MathMax((double)MaxNonProgressive, abShare)) return false;

   // --- مومنتم 2: گستره بدنه ها باید بخش عمده طول AB را بپوشاند
   double bodyLo = MathMin(rates[idxA].open, rates[idxA].close);
   double bodyHi = MathMax(rates[idxA].open, rates[idxA].close);

   for(int m = idxA; m <= idxB; m++)
   {
      double lo = MathMin(rates[m].open, rates[m].close);
      double hi = MathMax(rates[m].open, rates[m].close);
      if(lo < bodyLo) bodyLo = lo;
      if(hi > bodyHi) bodyHi = hi;
   }
   if((bodyHi - bodyLo) < abLength * MomentumMinPercent / 100.0) return false;

   return true;
}

//+------------------------------------------------------------------+
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

            // اینجا فقط «دانه» پیدا می‌شود، اعتبارسنجی نیست. پس کندل بدنه کوچک
            // هم جهتش شمرده می‌شود؛ سخت گیری واقعی در ValidateAB روی محدوده
            // واقعی [idxA, idxB] انجام می‌شود که آنجا کندل بی بدنه جای کندل
            // هم جهت را نمی‌گیرد.
            //
            // با شمردن نکردن جهت این کندل ها، پنجره تشخیص آنقدر سخت می‌شد که
            // خیلی از لگ های واقعی اصلا دانه ای برای شروع پیدا نمی‌کردند.
            if(bodyPercent < MinBodyPercent) nonStd++;

            if(rates[idx].close > rates[idx].open) bullCount++;
            if(rates[idx].close < rates[idx].open) bearCount++;
         }

         if(nonStd > MaxNonStandard) continue;

         // سویینگ باید حداقل MinCandles کندل «هم جهت» داشته باشد، نه اینکه فقط
         // پنجره ای به طول MinCandles با چند کندل مخالف باشد.
         bool isBullish = (bearCount <= MaxOppositeCandles && bullCount >= MinCandles);
         bool isBearish = (bullCount <= MaxOppositeCandles && bearCount >= MinCandles);
         if(!isBullish && !isBearish) continue;

         int startIdx = i - len + 1;
         int endIdx   = i;

         int    idxA = startIdx, idxB = startIdx;
         double priceA = 0.0, priceB = 0.0;

         // A باید «اولین کندل سویینگ» باشد، نه پایین ترین کف داخل پنجره.
         // کندل های مخالف جهت که ابتدای پنجره افتاده اند کنار گذاشته می‌شوند.
         if(isBullish)
         {
            while(idxA < endIdx && rates[idxA].close <= rates[idxA].open) idxA++;
            priceA = rates[idxA].low;
         }
         else
         {
            while(idxA < endIdx && rates[idxA].close >= rates[idxA].open) idxA++;
            priceA = rates[idxA].high;
         }

         // --- کندل صفر و سطح B.
         //
         // «کندل صفر» آخرین کندل لگ است که بعد از آن هیچ کندلی بالاتر از آن
         // (در لگ نزولی: پایین تر از آن) کلوز نداده باشد. تا وقتی کندلی با
         // کلوز از آن رد شود یعنی ایمپالس ادامه دارد و همان کندل، کندل صفر
         // جدید می‌شود.
         //
         // سطح B افراطی ترین نقطه بین کندل صفر و BConfirmBars کندل بعدش است —
         // یعنی شدویی که در این پنجره از کندل صفر رد شود B را جابجا می‌کند،
         // ولی بعد از این پنجره B قفل است.
         //
         // این جای منطق قبلی را می‌گیرد که B را تا «اولین اصلاح ۲۰ درصدی با
         // بادی» جلو می‌برد. آن اشتباه بود: درصد اصلاح مربوط به نقطه C و اعتبار
         // کل الگوست و هیچ ربطی به جای B ندارد.
         int idxZero = idxA;

         for(int m = idxA + 1; m < rates_total; m++)
         {
            bool closedBeyond = isBullish ? (rates[m].close > rates[idxZero].high)
                                          : (rates[m].close < rates[idxZero].low);
            if(closedBeyond) { idxZero = m; continue; }

            if(m - idxZero >= BConfirmBars) break;   // کندل صفر قطعی شد
         }

         if(idxA >= idxZero) continue;

         int bWindowEnd = idxZero + BConfirmBars;
         if(bWindowEnd > rates_total - 1) bWindowEnd = rates_total - 1;

         idxB   = idxZero;
         priceB = isBullish ? rates[idxZero].high : rates[idxZero].low;

         for(int m = idxZero + 1; m <= bWindowEnd; m++)
         {
            if(isBullish) { if(rates[m].high > priceB) { priceB = rates[m].high; idxB = m; } }
            else          { if(rates[m].low  < priceB) { priceB = rates[m].low;  idxB = m; } }
         }

         // جلوگیری از AB تو در تو.
         //
         // شرط عمدا «بزرگتر» است نه «بزرگتر یا مساوی»: کندل چرخش بین دو لگ
         // متوالی مشترک است — همان کندلی که B لگ قبلی است، A لگ بعدی هم هست.
         // با >= همین یک کندل مشترک «تو در تو» حساب می‌شد و چون اسکن از جدید
         // به قدیم می‌رود، لگ تازه (که اغلب هنوز در حال تشکیل است) لگ کامل و
         // معتبر قبلی را حذف می‌کرد. با بسط A به عقب این حالت تقریبا همیشه
         // پیش می‌آمد، چون A لگ بعدی دقیقا روی همان کندل چرخش می‌نشیند.
         if(idxB > lastAcceptedA) continue;

         // --- بسط A به عقب، آینه بسط B.
         //
         // پنجره تشخیص طول ثابتی دارد (MaxCandles) ولی خود سویینگ ندارد. اگر
         // A همانجا بماند که پنجره شروع شده، هر ایمپالسی بلندتر از پنجره،
         // A اش وسط حرکت می‌افتد؛ آنوقت طول AB کوتاه تر از واقعیت شمرده
         // می‌شود، آستانه های ۲۰ و ۶۰ درصد روی عدد کوچک حساب می‌شوند و یک
         // اصلاح جزئی الگو را بی جهت باطل می‌کند.
         //
         // در یک لگ صعودی هر چه به عقب برویم کف ها پایین تر است تا به مبدا
         // برسیم؛ بعد از آن وارد لگ نزولی قبلی می‌شویم و کف ها بالاتر می‌روند.
         // همان شرط ۲۰ درصد بادی که B را متوقف می‌کند، اینجا هم جلوی رفتن به
         // داخل حرکت قبلی را می‌گیرد.
         //
         // B عمدا با A جدید دوباره حساب نمی‌شود: A تازه پایین تر است، پس
         // سقف حرکت عوض نمی‌شود، ولی بسط دوباره B از یک کندل مخالفِ مبدا شروع
         // می‌شد و بلافاصله می‌شکست — همین در نسخه 2.50 تعداد تشخیص ها را به
         // شدت پایین آورد.
         int    idxABase   = idxA;
         double priceABase = priceA;

         int minA = idxB - MaxABSpan + 1;
         if(minA < 0) minA = 0;

         for(int m = idxA - 1; m >= minA; m--)
         {
            if(isBullish)
            {
               if(rates[m].low < priceA) { priceA = rates[m].low; idxA = m; continue; }
               double swingA = priceB - priceA;
               if(swingA > 0.0)
               {
                  double bodyHi = MathMax(rates[m].open, rates[m].close);
                  if((bodyHi - priceA) >= swingA * RetraceMinPercent / 100.0) break;
               }
            }
            else
            {
               if(rates[m].high > priceA) { priceA = rates[m].high; idxA = m; continue; }
               double swingA = priceA - priceB;
               if(swingA > 0.0)
               {
                  double bodyLo = MathMin(rates[m].open, rates[m].close);
                  if((priceA - bodyLo) >= swingA * RetraceMinPercent / 100.0) break;
               }
            }
         }

         // --- A روی «اولین کندل هم جهت» لگ.
         //
         // بسط بالا تا افراطی ترین نقطه به عقب می‌رود، ولی آن نقطه اغلب روی
         // کندلی می‌افتد که اصلا جزو لگ نیست — مثلا سقف یک کندل صعودی درست
         // قبل از یک لگ نزولی. A باید روی اولین کندل هم جهت خود لگ بنشیند.
         while(idxA < idxZero &&
               (isBullish ? (rates[idxA].close <= rates[idxA].open)
                          : (rates[idxA].close >= rates[idxA].open))) idxA++;

         priceA = isBullish ? rates[idxA].low : rates[idxA].high;

         // اعتبارسنجی روی [idxA, idxZero] است نه [idxA, idxB]: کندل هایی که
         // فقط با شدو B را جابجا کرده اند جزو خود لگ نیستند و نباید به عنوان
         // کندل مخالف شمرده شوند.
         //
         // نامزد اول: A روی مبدا واقعی. اگر لگ از آنجا تمیز نبود، همان A
         // کوتاه تر امتحان می‌شود تا هیچ سویینگی نسبت به قبل از دست نرود.
         if(!ValidateAB(rates, idxA, idxZero, priceA, priceB, isBullish))
         {
            if(idxA == idxABase) continue;
            if(!ValidateAB(rates, idxABase, idxZero, priceABase, priceB, isBullish)) continue;

            idxA   = idxABase;
            priceA = priceABase;
         }

         out[cnt].idxA          = idxA;
         out[cnt].idxB          = idxB;
         out[cnt].idxZero       = idxZero;
         out[cnt].timeA         = rates[idxA].time;
         out[cnt].timeB         = rates[idxB].time;
         out[cnt].priceA        = priceA;
         out[cnt].priceB        = priceB;
         out[cnt].isBull        = isBullish;
         out[cnt].size          = MathAbs(priceB - priceA);
         out[cnt].live          = ((rates_total - 1 - idxZero) < BConfirmBars);
         out[cnt].state         = AB_FORMING;
         out[cnt].idxC          = -1;
         out[cnt].timeC         = 0;
         out[cnt].priceC        = 0.0;
         out[cnt].priceCBody    = 0.0;
         out[cnt].hasValidBreak = false;
         out[cnt].idxBreakFrom  = -1;
         out[cnt].idxBreakTo    = -1;
         out[cnt].timeBreak     = 0;
         out[cnt].breakHigh     = 0.0;
         out[cnt].breakLow      = 0.0;
         out[cnt].idxHunt       = -1;
         out[cnt].timeHunt      = 0;
         out[cnt].priceD        = 0.0;
         out[cnt].idxSignal     = -1;
         out[cnt].timeSignal    = 0;
         out[cnt].priceSignal   = 0.0;
         out[cnt].deadReason    = AB_ALIVE;
         out[cnt].deadTime      = 0;
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

// کندل شکست معتبر
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
      if(c.close < bLevel + minDist) return false;
      if(c.open  > bLevel - minDist) return false;
   }
   else
   {
      if(c.close > bLevel - minDist) return false;
      if(c.open  < bLevel + minDist) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
// باطل کردن با ثبت علت. الگوی مرده بی سروصدا حذف نمی‌شود؛ خاکستری روی چارت
// و در جدول می‌ماند تا بشود بررسی کرد که درست حذف شده یا نه.
void KillSwing(SwingAB &s, ABDeadReason why, datetime when)
{
   s.state      = AB_INVALID;
   s.deadReason = why;
   s.deadTime   = when;
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

   double dir      = s.isBull ? -1.0 : 1.0;   // اصلاح AB صعودی، نزولی است
   double levelMin = s.priceB + dir * s.size * RetraceMinPercent / 100.0;
   double levelMax = s.priceB + dir * s.size * RetraceMaxPercent / 100.0;

   // دو عمق جدا نگه داشته می‌شود:
   //   deepestBody برای آستانه های 20 و 60 درصد، چون کاربر گفت اصلاح باید با
   //   بدنه سنجیده شود نه سایه.
   //   deepestWick برای جای خود نقطه C و محاسبه CD، چون C از نظر بصری همان
   //   کف/سقف واقعی اصلاح است نه انتهای بدنه.
   double deepestBody = s.priceB;
   double deepestWick = s.priceB;
   double bodyD       = s.priceB;   // انتهای بدنه در سمت نفوذ، برای سنجش CD

   // اصلاح BC از کندل بعد از پنجره تثبیت B شمرده می‌شود. کندل های ۱ تا ۳ خودشان
   // در تعیین سطح B نقش داشتند، پس نقطه C نباید روی آنها بنشیند.
   int bLocked = s.idxZero + BConfirmBars;

   // فقط کندل های بسته شده بررسی می‌شوند تا وضعیت وسط کندل repaint نشود.
   for(int m = bLocked + 1; m <= rates_total - 2; m++)
   {
      // ردیابی اصلاح تا لحظه شکست B ادامه دارد، نه فقط تا وقتی معتبر شود.
      if(s.state == AB_WAIT_RETRACE || s.state == AB_RETRACED)
      {
         // --- اعتبار زمانی، فقط روی فاز اصلاح.
         //
         // عمدا داخل حلقه است و نه اول تابع: بعد از هانت شدن B معامله شروع
         // شده و شمردن باید بس شود. وگرنه الگویی که در کندل بیستم بعد از B
         // هانت می‌شد، چهار کندل بعد وسط معامله از لیست حذف می‌شد.
         // بعد از هانت، عمر الگو را دو قاعده خودش تعیین می‌کند: CD > AB و
         // رسیدن قیمت به A.
         //
         // سقف بر حسب کندل است نه روز تقویمی. قاعده «فقط همان روز» روی تایم
         // های بالا خودش را می‌خورد: روی H8 فقط ۳ کندل در روز هست، و AB به
         // علاوه اصلاح از یک روز بیشتر طول می‌کشد — یعنی هیچ الگویی هرگز به
         // C نمی‌رسید. سقف کندلی خودبه‌خود با تایم فریم مقیاس می‌گیرد.
         if(MaxRetraceBars > 0 && (m - bLocked) > MaxRetraceBars)
         {
            KillSwing(s, AB_DEAD_EXPIRED, rates[m].time);
            return;
         }

         // قاعده روز تقویمی هنوز در دسترس است ولی پیش فرض خاموش است.
         if(MaxPatternDays > 0 &&
            ((long)rates[m].time / 86400 - (long)s.timeB / 86400) >= MaxPatternDays)
         {
            KillSwing(s, AB_DEAD_EXPIRED, rates[m].time);
            return;
         }

         double bodyExt = s.isBull ? MathMin(rates[m].open, rates[m].close)
                                   : MathMax(rates[m].open, rates[m].close);
         double wickExt = s.isBull ? rates[m].low : rates[m].high;

         if(s.isBull ? (bodyExt < deepestBody) : (bodyExt > deepestBody))
            deepestBody = bodyExt;

         if(s.isBull ? (wickExt < deepestWick) : (wickExt > deepestWick))
         {
            deepestWick   = wickExt;
            s.idxC        = m;
            s.timeC       = rates[m].time;
            s.priceC      = wickExt;
            s.priceCBody  = deepestBody;   // همان C ولی با بدنه، برای سنجش CD
         }

         bool bodyBeyondMax = s.isBull ? (bodyExt < levelMax) : (bodyExt > levelMax);
         if(bodyBeyondMax)
         {
            KillSwing(s, AB_DEAD_RETRACE, rates[m].time);
            return;
         }

         if(s.state == AB_WAIT_RETRACE)
         {
            bool retraceDeepEnough = s.isBull ? (deepestBody <= levelMin) : (deepestBody >= levelMin);

            // «حداقل MinRetraceCandles کندل استراحت» از خود کندل صفر شمرده
            // می‌شود، یعنی کندل های ۱، ۲ و ۳ هم جزو استراحت اند.
            //
            // طبق جزوه «مادامیکه قیمت بالای B کلوزی انجام نداده، هر کندلی
            // داریم جزء اصلاح BC محسوب می‌شود» — پس پنجره تثبیت B خودش بخشی
            // از اصلاح است. آن پنجره فقط تعیین می‌کند که نقطه C کجا می‌تواند
            // بنشیند (از کندل ۴ به بعد)، نه اینکه شمارش استراحت از آنجا شروع
            // شود.
            //
            // ملاک، تعداد کندل سپری شده است نه جای خود C: اگر اصلاح در همان
            // کندل اول به عمیق ترین نقطه اش برسد و بعد چند کندل بخوابد،
            // استراحت انجام شده.
            bool enoughCandles = (s.idxC >= 0 && (m - s.idxZero) >= MinRetraceCandles);

            // اصلاح معتبر یعنی هر دو با هم: عمق کافی و استراحت کافی
            bool retraceValid = (retraceDeepEnough && enoughCandles);

            bool touchedB = s.isBull ? (rates[m].high > s.priceB) : (rates[m].low < s.priceB);

            // باطل: B برداشته شود بدون اینکه C معتبری ثبت شده باشد
            if(touchedB && !retraceValid)
            {
               KillSwing(s, AB_DEAD_BEARLY, rates[m].time);
               return;
            }

            if(retraceValid)
               s.state = AB_RETRACED;
            else
               continue;
         }
      }

      if(s.state == AB_RETRACED)
      {
         // همینکه قیمت از سطح B رد شود یعنی نقدینگی برداشته شده — مستقل از
         // اینکه کندل شکست معتبر باشد یا نه.
         bool crossedB = s.isBull ? (rates[m].high > s.priceB) : (rates[m].low < s.priceB);
         if(!crossedB) continue;

         s.state    = AB_BROKEN;
         s.idxHunt  = m;
         s.timeHunt = rates[m].time;
         s.priceD   = s.isBull ? rates[m].high : rates[m].low;
         bodyD      = s.isBull ? MathMax(rates[m].open, rates[m].close)
                               : MathMin(rates[m].open, rates[m].close);
      }

      if(s.state == AB_BROKEN)
      {
         if(s.isBull) { if(rates[m].high > s.priceD) s.priceD = rates[m].high; }
         else         { if(rates[m].low  < s.priceD) s.priceD = rates[m].low;  }

         // انتهای بدنه در سمت نفوذ — مبنای سنجش طول CD
         double bodyEnd = s.isBull ? MathMax(rates[m].open, rates[m].close)
                                   : MathMin(rates[m].open, rates[m].close);
         if(s.isBull) { if(bodyEnd > bodyD) bodyD = bodyEnd; }
         else         { if(bodyEnd < bodyD) bodyD = bodyEnd; }

         // باطل: CD بزرگتر از AB شود.
         // هر دو سر با بدنه سنجیده می‌شوند، نه با سایه — یک شدوی بلند نباید
         // الگویی را بکشد که با بدنه اصلا به طول AB نرسیده.
         if(MathAbs(bodyD - s.priceCBody) > s.size)
         {
            KillSwing(s, AB_DEAD_CD, rates[m].time);
            return;
         }

         if(!s.hasValidBreak)
         {
            for(int n = 1; n <= BreakMaxCandles; n++)
            {
               int from = m - n + 1;
               if(from <= s.idxC) break;   // کندل مرکب نباید از C عقب تر برود

               Composite c;
               BuildComposite(rates, from, m, c);

               if(IsValidBreak(c, s.isBull, s.priceB, s.size, avgRange))
               {
                  s.hasValidBreak = true;
                  s.idxBreakFrom  = from;
                  s.idxBreakTo    = m;
                  s.timeBreak     = rates[m].time;
                  s.breakHigh     = c.high;
                  s.breakLow      = c.low;
                  break;
               }
            }
         }
         else if(s.idxSignal < 0)
         {
            // سیگنال ورود: کندلی که آن طرف کندل شکست بسته شود
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
            s.state      = AB_DONE;
            s.deadReason = AB_DEAD_HITA;
            s.deadTime   = rates[m].time;
            return;
         }
      }
   }

   // --- کندل جاری، که هنوز بسته نشده است.
   //
   // حلقه بالا عمدا فقط کندل های بسته شده را می‌بیند تا نقطه C و آستانه ۶۰
   // درصد وسط کندل جابجا نشوند. ولی «شکست B» را نمی‌شود تا بسته شدن کندل
   // معطل کرد: روی H8 یعنی تا ۸ ساعت تاخیر، و کل فایده این روش همین است که
   // به محض هانت شدن B سراغ تایم پایین تر بروید.
   //
   // این بررسی repaint نمی‌کند: سقف (و کف) یک کندل در حال تشکیل هیچ وقت
   // برنمی‌گردد، پس وقتی قیمت از B رد شد تا بسته شدن کندل رد شده می‌ماند و
   // نتیجه دقیقا همان چیزی است که بعد از بسته شدن هم به دست می‌آید.
   //
   // فقط سطح C اینجا به روز نمی‌شود؛ آن باید روی کندل بسته شده بماند.
   if(s.state == AB_WAIT_RETRACE || s.state == AB_RETRACED)
   {
      int last = rates_total - 1;

      if(last > s.idxB)
      {
         bool crossedB = s.isBull ? (rates[last].high > s.priceB)
                                  : (rates[last].low  < s.priceB);
         if(crossedB)
         {
            // همان قاعده حلقه بالا: فقط نرسیدن به عمق ۲۰ درصد الگو را باطل
            // می‌کند، نه کوتاه بودن اصلاح.
            bool deepEnough = (s.state == AB_RETRACED) ||
                              (s.isBull ? (deepestBody <= levelMin)
                                        : (deepestBody >= levelMin));
            if(deepEnough)
            {
               // نقدینگی برداشته شد — همان D
               s.state    = AB_BROKEN;
               s.idxHunt  = last;
               s.timeHunt = rates[last].time;
               s.priceD   = s.isBull ? rates[last].high : rates[last].low;
            }
            else
            {
               KillSwing(s, AB_DEAD_BEARLY, rates[last].time);
            }
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
// آیا این الگوی مرده هنوز باید نشان داده شود؟
// الگوی باطل بی سروصدا حذف نمی‌شود؛ تا انتهای همان روزی که مرده، خاکستری
// می‌ماند تا بشود بررسی کرد که درست حذف شده یا نه.
bool DeadStillVisible(SwingAB &s, MqlRates &rates[], int rates_total)
{
   if(s.deadTime == 0 || rates_total <= 0) return false;

   long dayDead = (long)s.deadTime / 86400;
   long dayNow  = (long)rates[rates_total - 1].time / 86400;
   return (dayNow == dayDead);
}

//+------------------------------------------------------------------+
// از سویینگ های خام، فهرست الگوهای «فعال» را می‌سازد:
// چرخه عمر را بازپخش می‌کند، لگ های اصلاحی خلاف جهت را کنار می‌گذارد، و
// الگوهای مرده امروز را برای بازرسی نگه می‌دارد.
int BuildActiveSwings(MqlRates &rates[], int rates_total, double avgRange,
                      SwingAB &raw[], int nRaw, SwingAB &out[],
                      bool keepOnlyLast, bool showPrevious)
{
   int nKept = 0;

   if(EnableABCD)
   {
      ArrayResize(out, nRaw);
      for(int k = 0; k < nRaw; k++)
      {
         EvaluateLifecycle(raw[k], rates, rates_total, avgRange);

         if(raw[k].state == AB_INVALID || raw[k].state == AB_DONE)
            if(!DeadStillVisible(raw[k], rates, rates_total)) continue;

         out[nKept] = raw[k];
         nKept++;
      }
      ArrayResize(out, nKept);

      // یک AB بزرگ که در حال اصلاح است، لگ اصلاحی اش خودش به عنوان یک AB
      // خلاف جهت تشخیص داده می‌شود. تا وقتی الگوی بزرگتر معتبر است این لگ
      // فقط اصلاح است نه الگوی مستقل، پس کنار گذاشته می‌شود.
      if(HideCounterABInRetrace && nKept > 1)
      {
         SwingAB kept2[];
         ArrayResize(kept2, nKept);
         int n2 = 0;

         for(int k = 0; k < nKept; k++)
         {
            bool isRetraceLeg = false;

            for(int j = 0; j < nKept; j++)
            {
               if(j == k) continue;
               if(out[j].isBull == out[k].isBull) continue;
               if(out[j].state != AB_WAIT_RETRACE && out[j].state != AB_RETRACED) continue;
               if(out[j].deadReason != AB_ALIVE) continue;

               if(out[k].idxA >= out[j].idxB)
               {
                  isRetraceLeg = true;
                  break;
               }
            }

            if(isRetraceLeg) continue;

            kept2[n2] = out[k];
            n2++;
         }

         ArrayResize(out, n2);
         for(int k = 0; k < n2; k++) out[k] = kept2[k];
         nKept = n2;
      }
   }
   else
   {
      nKept = ReduceSwings(raw, nRaw, out);
      for(int k = 0; k < nKept; k++)
         out[k].state = out[k].live ? AB_FORMING : AB_WAIT_RETRACE;

      if(!showPrevious && nKept > 2)
      {
         int firstIdx = nKept - 2;
         for(int k = 0; k < 2; k++)
            out[k] = out[firstIdx + k];
         nKept = 2;
         ArrayResize(out, nKept);
      }
   }

   if(keepOnlyLast && nKept > 1)
   {
      out[0] = out[nKept - 1];
      nKept = 1;
      ArrayResize(out, nKept);
   }

   return nKept;
}

//+------------------------------------------------------------------+
// تحلیل کامل یک نماد و تایم فریم: کپی داده، تشخیص، چرخه عمر و فیلترها.
// rates و out پر می‌شوند. مقدار برگشتی تعداد الگوهای فعال است،
// یا -1 اگر داده کافی در دسترس نباشد (مثلا هنوز دانلود نشده).
int AnalyzeSymbol(string symbol, ENUM_TIMEFRAMES tf, int historyBars, int maxLookback,
                  bool keepOnlyLast, bool showPrevious,
                  MqlRates &rates[], int &rates_total, SwingAB &out[])
{
   rates_total = 0;

   int available = Bars(symbol, tf);
   if(available <= MinCandles) return -1;

   int needed = EnableABCD ? historyBars : (maxLookback + MaxCandles + 10);
   if(needed > available) needed = available;

   ArraySetAsSeries(rates, false);   // ایندکس 0 = قدیمی ترین کندل
   rates_total = CopyRates(symbol, tf, 0, needed, rates);
   if(rates_total <= MinCandles) return -1;

   // میانگین رنج کندل ها برای سنجش «کندل شکست خیلی کوچک نباشد»
   double sumRange = 0.0;
   for(int m = 0; m < rates_total; m++)
      sumRange += (rates[m].high - rates[m].low);
   double avgRange = sumRange / rates_total;

   int scanFrom = EnableABCD ? MinCandles : (rates_total - maxLookback - MaxCandles);

   SwingAB raw[];
   int nRaw = CollectSwings(rates, rates_total, scanFrom, raw);

   return BuildActiveSwings(rates, rates_total, avgRange, raw, nRaw, out,
                            keepOnlyLast, showPrevious);
}
//+------------------------------------------------------------------+
