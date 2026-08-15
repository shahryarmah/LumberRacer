// سرشماری ستاپ ها روی داده واقعی، قبل از ساختن موتور معاملاتی.
//
// می‌شمارد در بازه مشترک دو تایم فریم فراکتال، چند بار مرحله های زنجیره
// اتفاق افتاده: AB قطعی -> C تایید شده -> FVG داخل AB -> رسیدن قیمت به FVG
// -> هانت شدن B تایم بالا. اگر عددها کوچک باشند، بک تست معاملاتی روی این
// حجم داده معنی آماری ندارد و باید اول تاریخچه بیشتری گرفت.
#include "bt_common.h"

struct Stage
{
   long cOk = 0;        // الگویی که به «C ok» رسید (هر الگو یک بار)
   long withFvg = 0;    // از آنها، چند تا داخل AB شان FVG داشت
   long fvgTouched = 0; // از آنها، در چند تا قیمت در فاز اصلاح به FVG رسید
   long hunted = 0;     // از آنها، چند تا بعدا B شان هانت شد
};

static void Census(const char *hiPath, int hiTF, const char *loPath, int loTF,
                   const char *title)
{
   std::vector<MqlRates> hi, lo;
   if(!LoadCsv(hiPath, hi) || !LoadCsv(loPath, lo)) return;

   long long overlapFrom = MathMax(hi.front().time, lo.front().time);
   long long overlapTo   = MathMin(hi.back().time,  lo.back().time);

   printf("\n================ %s ================\n", title);
   printf("بازه مشترک: %s تا %s\n", Stamp(overlapFrom).c_str(), Stamp(overlapTo).c_str());
   printf("روز: %.0f   |  کندل تایم بالا در بازه: ", (overlapTo - overlapFrom) / 86400.0);

   int firstHi = 0;
   while(firstHi < (int)hi.size() && hi[firstHi].time < overlapFrom) firstHi++;
   printf("%d  |  کندل تایم پایین: ", (int)hi.size() - firstHi);

   int firstLo = 0;
   while(firstLo < (int)lo.size() && lo[firstLo].time < overlapFrom) firstLo++;
   printf("%d\n", (int)lo.size() - firstLo);

   Stage st;

   // هر الگو با زمان کندل A شناخته می‌شود تا دوبار شمرده نشود
   std::vector<long long> seenCok, seenFvg, seenTouch, seenHunt;
   auto once = [](std::vector<long long> &v, long long key) {
      if(std::find(v.begin(), v.end(), key) != v.end()) return false;
      v.push_back(key); return true;
   };

   static SwingAB sw[512];

   for(int i = firstHi; i < (int)hi.size(); i++)
   {
      int n = SwingsAt(hi, i, hiTF, sw, 512);

      for(int k = 0; k < n; k++)
      {
         SwingAB &s = sw[k];
         if(s.live) continue;

         long long key = (long long)s.timeA;

         if(s.state == AB_RETRACED || s.state == AB_BROKEN)
         {
            if(once(seenCok, key)) st.cOk++;

            std::vector<Fvg> fv;
            if(FvgsInSwing(hi, s, fv) > 0)
            {
               if(once(seenFvg, key)) st.withFvg++;

               // آیا قیمت تا همین کندل به یکی از FVG ها رسیده؟
               bool touched = false;
               for(size_t g = 0; g < fv.size() && !touched; g++)
                  for(int m = s.idxB + 1; m <= i; m++)
                  {
                     if(s.isBull ? (hi[m].low <= fv[g].hi) : (hi[m].high >= fv[g].lo))
                     { touched = true; break; }
                  }

               if(touched && once(seenTouch, key)) st.fvgTouched++;
            }
         }

         if(s.state == AB_BROKEN && once(seenHunt, key)) st.hunted++;
      }
   }

   printf("\n  الگوی تایم بالا که به C ok رسید      : %ld\n", st.cOk);
   printf("  از آنها، داخل AB شان FVG داشت        : %ld\n", st.withFvg);
   printf("  از آنها، قیمت در اصلاح به FVG رسید   : %ld   <-- ورودی معامله اول\n", st.fvgTouched);
   printf("  الگویی که B اش هانت شد               : %ld   <-- ورودی معامله دوم\n", st.hunted);
}

int main()
{
   printf("سرشماری ستاپ ها روی داده واقعی XAUUSD\n");
   printf("(منطق تشخیص از GOD_OF_HUNT_Core.mqh می‌آید، بدون نگاه به آینده)\n");

   Census("data/GOH_XAUUSD_H4.csv", PERIOD_H4,
          "data/GOH_XAUUSD_M15.csv", PERIOD_M15, "H4  <->  M15");

   Census("data/GOH_XAUUSD_H1.csv", PERIOD_H1,
          "data/GOH_XAUUSD_M5.csv", PERIOD_M5,  "H1  <->  M5");

   return 0;
}
