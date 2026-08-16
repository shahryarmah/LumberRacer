// فهرست همه الگوهای AB تایم بالا با تاریخ و ساعت، برای بررسی دستی روی چارت.
//
// برای هر الگو، لحظه هر مرحله جدا ثبت می‌شود: قطعی شدن AB، تایید C، رسیدن
// قیمت به FVG، هانت شدن B، و مرگ الگو با علتش. همه از هسته واقعی
// (GOD_OF_HUNT_Core.mqh) و بدون نگاه به آینده.
#include "bt_common.h"

struct Pat
{
   long long keyA = 0;
   bool   isBull = false;
   double pA = 0, pB = 0, pC = 0;
   long long tA = 0, tB = 0;
   long long tConfirm = 0;   // اولین لحظه ای که AB قطعی دیده شد
   long long tCok = 0;       // اصلاح معتبر شد (C ok)
   long long tFvg = 0;       // قیمت به FVG داخل AB رسید
   long long tHunt = 0;      // B هانت شد
   long long tDead = 0;      // الگو مرد
   int    deadWhy = 0;       // ABDeadReason
   int    nFvg = 0;          // چند FVG داخل AB بود
};

static const char *DeadWhy(int r)
{
   switch(r)
   {
      case AB_ALIVE:        return "زنده";
      case AB_DEAD_RETRACE: return "اصلاح>60%";
      case AB_DEAD_BEARLY:  return "B زودهنگام";
      case AB_DEAD_CD:      return "CD>AB";
      case AB_DEAD_EXPIRED:  return "کهنه";
      case AB_DEAD_HITA:    return "به A رسید";
   }
   return "?";
}

static string Or(long long t) { return t ? Stamp(t) : string("        —       "); }

static void ListPatterns(const char *path, int tf, const char *tfName,
                         long long from, long long btFrom, const char *csvOut)
{
   std::vector<MqlRates> bars;
   if(!LoadCsv(path, bars)) return;

   int first = 0;
   while(first < (int)bars.size() && bars[first].time < from) first++;

   std::vector<Pat> pats;
   static SwingAB sw[512];

   for(int i = first; i < (int)bars.size(); i++)
   {
      int n = SwingsAt(bars, i, tf, sw, 512);

      for(int k = 0; k < n; k++)
      {
         SwingAB &s = sw[k];
         if(s.live) continue;

         Pat *p = nullptr;
         for(size_t q = 0; q < pats.size(); q++)
            if(pats[q].keyA == (long long)s.timeA) { p = &pats[q]; break; }

         if(!p)
         {
            pats.push_back(Pat());
            p = &pats.back();
            p->keyA   = (long long)s.timeA;
            p->isBull = s.isBull;
            p->pA     = s.priceA;
            p->pB     = s.priceB;
            p->tA     = (long long)s.timeA;
            p->tB     = (long long)s.timeB;
            p->tConfirm = (long long)bars[i].time;

            std::vector<Fvg> fv;
            p->nFvg = FvgsInSwing(bars, s, fv);
         }

         if(s.priceC != 0.0) p->pC = s.priceC;

         if(p->tCok == 0 && (s.state == AB_RETRACED || s.state == AB_BROKEN))
            p->tCok = (long long)bars[i].time;

         if(p->tFvg == 0 && s.state == AB_RETRACED)
         {
            std::vector<Fvg> fv;
            if(FvgsInSwing(bars, s, fv) > 0)
               for(size_t g = 0; g < fv.size() && p->tFvg == 0; g++)
                  if(s.isBull ? (bars[i].low <= fv[g].hi) : (bars[i].high >= fv[g].lo))
                     p->tFvg = (long long)bars[i].time;
         }

         if(p->tHunt == 0 && s.state == AB_BROKEN)
            p->tHunt = (long long)bars[i].time;

         if(p->tDead == 0 && (s.state == AB_INVALID || s.state == AB_DONE))
         {
            p->tDead   = (long long)bars[i].time;
            p->deadWhy = (int)s.deadReason;
         }
      }
   }

   printf("\n================================================================\n");
   printf(" الگوهای %s   —  از %s   (%d الگو)\n", tfName, Stamp(from).c_str(),
          (int)pats.size());
   printf("================================================================\n");
   printf(" ستون بک‌تست: * یعنی این الگو در بازه بک‌تست بوده\n\n");
   printf(" %-3s %-2s %-4s %-16s %9s %-16s %9s %-16s %-16s %-16s %-10s %s\n",
          "#", "بت", "جهت", "کندل A", "قیمت A", "کندل B", "قیمت B",
          "C ok", "رسیدن به FVG", "هانت B", "مرگ", "علت");

   FILE *f = fopen(csvOut, "w");
   if(f) fprintf(f, "idx,in_backtest,dir,timeA,priceA,timeB,priceB,"
                    "t_confirm,t_Cok,t_fvg_touch,t_hunt,t_dead,dead_reason,n_fvg\n");

   for(size_t q = 0; q < pats.size(); q++)
   {
      const Pat &p = pats[q];
      bool inBt = (p.keyA >= btFrom);

      printf(" %-3d %-2s %-4s %-16s %9.2f %-16s %9.2f %-16s %-16s %-16s %-10s %s\n",
             (int)q + 1, inBt ? "*" : " ", p.isBull ? "BULL" : "BEAR",
             Stamp(p.tA).c_str(), p.pA, Stamp(p.tB).c_str(), p.pB,
             Or(p.tCok).c_str(), Or(p.tFvg).c_str(), Or(p.tHunt).c_str(),
             Or(p.tDead).c_str(), p.tDead ? DeadWhy(p.deadWhy) : "زنده");

      if(f)
         fprintf(f, "%d,%s,%s,%s,%.2f,%s,%.2f,%s,%s,%s,%s,%s,%s,%d\n",
                 (int)q + 1, inBt ? "yes" : "no", p.isBull ? "BULL" : "BEAR",
                 Stamp(p.tA).c_str(), p.pA, Stamp(p.tB).c_str(), p.pB,
                 Stamp(p.tConfirm).c_str(),
                 p.tCok  ? Stamp(p.tCok).c_str()  : "",
                 p.tFvg  ? Stamp(p.tFvg).c_str()  : "",
                 p.tHunt ? Stamp(p.tHunt).c_str() : "",
                 p.tDead ? Stamp(p.tDead).c_str() : "",
                 p.tDead ? DeadWhy(p.deadWhy) : "alive", p.nFvg);
   }

   if(f) { fclose(f); printf("\n CSV: %s\n", csvOut); }

   int cok = 0, fvg = 0, hunt = 0;
   for(size_t q = 0; q < pats.size(); q++)
   {
      if(pats[q].tCok)  cok++;
      if(pats[q].tFvg)  fvg++;
      if(pats[q].tHunt) hunt++;
   }
   printf(" جمع: %d الگو | به C ok رسید %d | قیمت به FVG رسید %d | B هانت شد %d\n",
          (int)pats.size(), cok, fvg, hunt);
}

int main()
{
   // 2026.01.01 — بازه ای که هم برای بررسی دستی معقول است و هم بازه بک‌تست
   // را کامل در بر می‌گیرد
   long long from = 1767225600LL;   // 2026.01.01 00:00 UTC

   ListPatterns("data/GOH_XAUUSD_H4.csv", PERIOD_H4, "H4  (XAUUSD)",
                from, 1782420300LL, "data/patterns_H4.csv");

   ListPatterns("data/GOH_XAUUSD_H1.csv", PERIOD_H1, "H1  (XAUUSD)",
                from, 1778011200LL, "data/patterns_H1.csv");

   return 0;
}
