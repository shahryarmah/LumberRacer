int CollectSwingsOld(MqlRates rates[], int rates_total, int scanFrom, SwingAB out[])
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

         // سویینگ باید حداقل MinCandles کندل «هم جهت» داشته باشد، نه اینکه فقط
         // پنجره ای به طول MinCandles با چند کندل مخالف باشد. بدون شرط دوم،
         // پنجره 3 کندلی با 1 کندل مخالف عملا فقط 2 کندل هم جهت دارد.
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

         // B تا «اولین اصلاح معنادار» جلو می‌رود، نه فقط چند کندل ثابت.
         // با جستجوی ثابت، سقفی که کمی دیرتر ساخته می‌شد از دست می‌رفت.
         // اصلاح با بادی سنجیده می‌شود، نه با سایه.
         idxB   = idxA;
         priceB = isBullish ? rates[idxA].high : rates[idxA].low;

         for(int m = idxA + 1; m < rates_total; m++)
         {
            if(isBullish)
            {
               if(rates[m].high > priceB) { priceB = rates[m].high; idxB = m; continue; }
               double swing = priceB - priceA;
               if(swing > 0.0)
               {
                  double bodyLow = MathMin(rates[m].open, rates[m].close);
                  if((priceB - bodyLow) >= swing * RetraceMinPercent / 100.0) break;
               }
            }
            else
            {
               if(rates[m].low < priceB) { priceB = rates[m].low; idxB = m; continue; }
               double swing = priceA - priceB;
               if(swing > 0.0)
               {
                  double bodyHigh = MathMax(rates[m].open, rates[m].close);
                  if((bodyHigh - priceB) >= swing * RetraceMinPercent / 100.0) break;
               }
            }
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

         // --- مومنتم 1: حرکت باید پله ای باشد، یعنی هر کندل سقف بالاتری از
         //     کندل قبل بسازد (برای نزولی: کف پایین تر). این شرط حرکت درهم را رد می‌کند.
         int nonProgressive = 0;
         for(int m = idxA + 1; m <= idxB; m++)
         {
            bool progressed = isBullish ? (rates[m].high > rates[m-1].high)
                                        : (rates[m].low  < rates[m-1].low);
            if(!progressed) nonProgressive++;
         }
         if(nonProgressive > MaxNonProgressive) continue;

         // --- مومنتم 2: گستره بدنه ها باید بخش عمده طول AB را بپوشاند.
         //     این شرط ABی را رد می‌کند که طولش از یک سایه بلند ساخته شده باشد.
         double bodyLo = MathMin(rates[idxA].open, rates[idxA].close);
         double bodyHi = MathMax(rates[idxA].open, rates[idxA].close);
         for(int m = idxA; m <= idxB; m++)
         {
            double lo = MathMin(rates[m].open, rates[m].close);
            double hi = MathMax(rates[m].open, rates[m].close);
            if(lo < bodyLo) bodyLo = lo;
            if(hi > bodyHi) bodyHi = hi;
         }
         if((bodyHi - bodyLo) < abLength * MomentumMinPercent / 100.0) continue;

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
         out[cnt].hasValidBreak = false;
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
