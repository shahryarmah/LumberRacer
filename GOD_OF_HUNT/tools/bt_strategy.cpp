// بک تست سیستم دو معامله ای فراکتالی روی داده واقعی.
//
// زنجیره (مثال با AB صعودی در تایم بالا):
//
//   تایم بالا: AB تشکیل -> C تایید -> قیمت در فاز اصلاح به FVG داخل AB
//              می‌رسد (الگو باید زنده باشد)  =>  پنجره معامله اول باز می‌شود
//
//   معامله ۱ (خرید): در تایم پایین یک AB *نزولی* تشکیل می‌شود، B اش شکسته
//              می‌شود (کندل شکننده = سیگنال)، بعد کندلی بالای کندل سیگنال
//              بسته می‌شود => ورود.
//              SL زیر D تایم پایین | TP1 نقطه A تایم پایین | TP2 سطح B تایم بالا
//
//   تایم بالا: قیمت به B نفوذ می‌کند  =>  پنجره معامله دوم باز می‌شود
//
//   معامله ۲ (فروش): در تایم پایین یک AB *صعودی* که B اش بالای B تایم بالا
//              باشد، C تشکیل می‌شود، قیمت برمی‌گردد بالای B (کندل نفوذکننده
//              = سیگنال)، بعد کندلی زیر کندل سیگنال بسته می‌شود => ورود.
//              SL بالای D تایم پایین | TP1 نقطه A تایم پایین | TP2 نقطه C تایم بالا
//
// در AB نزولی تایم بالا همه چیز آینه می‌شود.
//
// تشخیص از sim_core.h می‌آید (ساخته شده از GOD_OF_HUNT_Core.mqh) و بازپخش
// بدون نگاه به آینده است: در هر کندل فقط کندل های تا همان لحظه دیده می‌شوند.
#include "bt_common.h"

//--------------------------------------------------------------------------
// فرض های مدل سازی، همه جا صریح گزارش می‌شوند:
//   - ورود روی کلوز کندل تایید
//   - استاپ دقیقا روی خود D، بدون حاشیه
//   - بدون اسپرد، کمیسیون و اسلیپیج
//   - اگر در یک کندل هم استاپ و هم TP در دسترس باشند، استاپ اول فرض می‌شود
static const int MAX_WAIT_LO_BARS  = 400;  // سقف انتظار برای ورود در تایم پایین
static const int MAX_HOLD_LO_BARS  = 800;  // سقف نگهداری معامله
// پیگیری بعد از استاپ عمدا کوتاه است: روی طلا در چند روز قیمت تقریبا به هر
// سطحی برمی‌گردد، پس پنجره بلند جمله «بعد از استاپ به تارگت رسید» را
// بی معنا می‌کند.
static const int AFTER_STOP_BARS   = 60;
// «استاپ با اختلاف کم» یعنی نفوذ کمتر از این نسبت از فاصله استاپ
static const double NEAR_STOP_R    = 0.5;

// --- تنظیمات قابل تغییر بک تست، تا بشود اثر هر قاعده را جدا سنجید
struct Cfg
{
   // کندل سیگنال (کندلی که B را می‌شکند) نباید ضعیف و پرسایه باشد:
   // بادی حداقل این درصد از کل رنج کندل. صفر = فیلتر خاموش.
   double sigMinBodyPct = 0.0;

   // ورود با ریسک به ریوارد هدف تا TP1.
   // اگر کلوز کندل تایید نسبت بدتری بدهد، به جای ورود فوری یک سفارش
   // برگشتی روی قیمتی گذاشته می‌شود که دقیقا این نسبت را بسازد:
   //     E = (TP1 + rr * SL) / (1 + rr)
   // صفر = ورود روی کلوز کندل تایید (رفتار قدیم).
   double targetRR = 0.0;

   // چند کندل برای برگشت قیمت به نقطه ورود صبر می‌کنیم
   int    pullbackBars = 60;
};
static Cfg g_cfg;
// تنظیمی که گزارش تفصیلی با آن چاپ می‌شود
static const double SHOW_BODY = 70.0;
static const double SHOW_RR   = 2.0;
static bool g_quiet = false;
#define OUT if(!g_quiet) printf

enum MissReason { MISS_NONE = 0, MISS_NO_AB, MISS_NO_BREAK, MISS_NO_CONFIRM,
                  MISS_WINDOW, MISS_BAD_TARGET, MISS_WEAK_SIGNAL,
                  MISS_NO_PULLBACK };

static const char *MissText(MissReason m)
{
   switch(m)
   {
      case MISS_NONE:       return "-";
      case MISS_NO_AB:      return "AB لازم در تایم پایین تشکیل نشد";
      case MISS_NO_BREAK:   return "AB بود ولی B شکسته نشد";
      case MISS_NO_CONFIRM: return "B شکست ولی کندل تایید نیامد";
      case MISS_WINDOW:     return "پنجره تمام شد";
      case MISS_BAD_TARGET: return "تارگت پشت سر ورود بود (قیمت رد شده بود)";
      case MISS_WEAK_SIGNAL:return "کندل سیگنال ضعیف/پرسایه بود";
      case MISS_NO_PULLBACK:return "قیمت به نقطه ورود برنگشت";
   }
   return "?";
}

struct Trade
{
   bool      entered = false;
   MissReason miss   = MISS_NO_AB;

   bool      isLong  = false;
   long long tEntry  = 0;
   double    entry   = 0, stop = 0, tp1 = 0, tp2 = 0;

   bool      hitTP1  = false, hitTP2 = false, stopped = false;
   long long tExit   = 0;
   double    rTP1    = 0;     // R اگر همه حجم روی TP1 بسته شود
   double    rTP2    = 0;     // R اگر همه حجم روی TP2 بسته شود
   double    rHalf   = 0;     // R اگر نصف روی TP1 و نصف روی TP2

   // تحلیل «استاپ با اختلاف کم»
   double    beyondStop   = 0;    // چقدر قیمت از استاپ رد شد (واحد قیمت)
   double    beyondStopR  = 0;    // همان، بر حسب فاصله استاپ
   bool      tp1AfterStop = false; // بعد از استاپ، به TP1 می‌رسید؟
   bool      tp2AfterStop = false;
};

// همه معامله های انجام شده، برای تحلیل ریسک به ریوارد در انتها
struct TradeRec
{
   const char *pair;
   int         leg;
   Trade       tr;
   double      risk, rr1, rr2;
};
static std::vector<TradeRec> g_all;

struct Setup
{
   long long keyA = 0;
   bool      isBull = false;
   double    hiA = 0, hiB = 0, hiC = 0;
   long long tCok = 0, tFvg = 0, tHunt = 0, tDead = 0;
   Trade     t1, t2;
};

//--------------------------------------------------------------------------
// مرحله های تایم بالا: برای هر الگو، اولین لحظه هر رویداد ثبت می‌شود.
static void CollectSetups(const std::vector<MqlRates> &hi, int hiTF,
                          long long from, std::vector<Setup> &out)
{
   int first = 0;
   while(first < (int)hi.size() && hi[first].time < from) first++;

   static SwingAB sw[512];

   for(int i = first; i < (int)hi.size(); i++)
   {
      int n = SwingsAt(hi, i, hiTF, sw, 512);

      for(int k = 0; k < n; k++)
      {
         SwingAB &s = sw[k];
         if(s.live) continue;

         Setup *set = nullptr;
         for(size_t q = 0; q < out.size(); q++)
            if(out[q].keyA == (long long)s.timeA) { set = &out[q]; break; }

         bool cok = (s.state == AB_RETRACED || s.state == AB_BROKEN);
         if(!set)
         {
            if(!cok) continue;              // فقط از «C ok» به بعد دنبال می‌شود
            out.push_back(Setup());
            set = &out.back();
            set->keyA   = (long long)s.timeA;
            set->isBull = s.isBull;
            set->hiA    = s.priceA;
            set->hiB    = s.priceB;
            set->tCok   = (long long)hi[i].time;
         }

         if(s.priceC != 0.0) set->hiC = s.priceC;

         // --- رسیدن قیمت به FVG داخل AB، در فاز اصلاح و با الگوی زنده
         if(set->tFvg == 0 && s.state == AB_RETRACED)
         {
            std::vector<Fvg> fv;
            if(FvgsInSwing(hi, s, fv) > 0)
            {
               for(size_t g = 0; g < fv.size() && set->tFvg == 0; g++)
               {
                  bool touched = s.isBull ? (hi[i].low  <= fv[g].hi)
                                          : (hi[i].high >= fv[g].lo);
                  if(touched) set->tFvg = (long long)hi[i].time;
               }
            }
         }

         if(set->tHunt == 0 && s.state == AB_BROKEN)
            set->tHunt = (long long)hi[i].time;

         if(set->tDead == 0 && (s.state == AB_INVALID || s.state == AB_DONE))
            set->tDead = (long long)hi[i].time;
      }
   }
}

//--------------------------------------------------------------------------
// اجرای یک معامله در تایم پایین.
//
// wantBull: جهت AB لازم در تایم پایین.
// longTrade: جهت خود معامله.
// bMin/bMax: اگر لازم باشد B تایم پایین آن طرف سطحی باشد (معامله دوم).
static Trade RunLegTrade(const std::vector<MqlRates> &lo, int loTF,
                         long long tFrom, long long tTo,
                         bool wantBull, bool longTrade,
                         bool useBGate, double bGate, bool bAbove,
                         double tp2)
{
   Trade tr;
   tr.isLong = longTrade;

   int i = 0;
   while(i < (int)lo.size() && lo[i].time < tFrom) i++;
   if(i >= (int)lo.size()) { tr.miss = MISS_WINDOW; return tr; }

   int waited = 0;
   static SwingAB sw[512];

   long long sigTime = 0;
   double    sigHigh = 0, sigLow = 0, sigA = 0, sigD = 0;
   bool      haveSignal = false;

   for(; i < (int)lo.size(); i++)
   {
      if(tTo > 0 && lo[i].time > tTo) { if(!haveSignal) tr.miss = MISS_WINDOW; break; }
      if(++waited > MAX_WAIT_LO_BARS)  { if(!haveSignal) tr.miss = MISS_WINDOW; break; }

      if(!haveSignal)
      {
         int n = SwingsAt(lo, i, loTF, sw, 512);

         for(int k = 0; k < n; k++)
         {
            SwingAB &s = sw[k];
            if(s.live || s.isBull != wantBull) continue;

            if(tr.miss == MISS_NO_AB) tr.miss = MISS_NO_BREAK;

            if(useBGate)
            {
               if(bAbove  && !(s.priceB > bGate)) continue;
               if(!bAbove && !(s.priceB < bGate)) continue;
            }

            if(s.state != AB_BROKEN || s.idxHunt < 0) continue;

            // --- کیفیت کندل سیگنال: نباید ضعیف و پرسایه باشد.
            // بادی نسبت به کل رنج کندل سنجیده می‌شود، پس این شرط خودبه‌خود
            // مجموع سایه ها را هم محدود می‌کند.
            if(g_cfg.sigMinBodyPct > 0.0)
            {
               const MqlRates &sc = lo[s.idxHunt];
               double rng  = sc.high - sc.low;
               double body = MathAbs(sc.close - sc.open);

               if(rng <= 0.0 || body / rng * 100.0 < g_cfg.sigMinBodyPct)
               {
                  if(tr.miss == MISS_NO_BREAK) tr.miss = MISS_WEAK_SIGNAL;
                  continue;
               }
            }

            // کندل سیگنال = کندلی که B را شکست
            tr.miss    = MISS_NO_CONFIRM;
            sigTime    = (long long)lo[s.idxHunt].time;
            sigHigh    = lo[s.idxHunt].high;
            sigLow     = lo[s.idxHunt].low;
            sigA       = s.priceA;
            sigD       = s.priceD;
            haveSignal = true;
            break;
         }
         continue;
      }

      // --- کندل تایید: کلوز آن طرف کندل سیگنال
      if(lo[i].time <= sigTime) continue;

      // D تا لحظه ورود ادامه دارد. اگر قیمت بین شکست B و کندل تایید بیشتر
      // نفوذ کند، استاپ باید پشت همان نفوذ تازه باشد نه پشت D لحظه شکست.
      if(longTrade) { if(lo[i].low  < sigD) sigD = lo[i].low;  }
      else          { if(lo[i].high > sigD) sigD = lo[i].high; }

      bool confirmed = longTrade ? (lo[i].close > sigHigh) : (lo[i].close < sigLow);
      if(!confirmed) continue;

      double entry = lo[i].close;

      // --- ورود با ریسک به ریوارد هدف تا TP1.
      //
      // اگر کلوز کندل تایید خیلی به تارگت نزدیک و از استاپ دور باشد، نسبت
      // بد می‌شود. به جای ورود فوری، قیمتی حساب می‌شود که دقیقا نسبت هدف را
      // بسازد و منتظر برگشت قیمت به آن می‌مانیم:
      //
      //     |TP1 - E| = rr * |E - SL|   ->   E = (TP1 + rr*SL) / (1 + rr)
      //
      // اگر کلوز از قبل نسبت بهتری بدهد، همانجا وارد می‌شویم.
      if(g_cfg.targetRR > 0.0)
      {
         double want = (sigA + g_cfg.targetRR * sigD) / (1.0 + g_cfg.targetRR);
         bool   needPullback = longTrade ? (entry > want) : (entry < want);

         if(needPullback)
         {
            int  j = i + 1, waitedPb = 0;
            bool filled = false;

            for(; j < (int)lo.size() && waitedPb < g_cfg.pullbackBars; j++, waitedPb++)
            {
               // اگر قیمت بدون برگشت به تارگت رسید، معامله از دست رفت
               if(longTrade ? (lo[j].high >= sigA) : (lo[j].low <= sigA)) break;

               bool touched = longTrade ? (lo[j].low <= want) : (lo[j].high >= want);
               if(touched) { filled = true; break; }
            }

            if(!filled) { tr.miss = MISS_NO_PULLBACK; break; }

            entry = want;
            i     = j;          // معامله از همین کندل پیگیری می‌شود
         }
      }

      // اعتبار هندسی: استاپ باید پشت ورود و هر دو تارگت جلوی آن باشند.
      // اگر قیمت قبل از ورود از تارگت رد شده باشد، فرض ستاپ از بین رفته و
      // معامله ای در کار نیست — این را جدا می‌شماریم تا در آمار گم نشود.
      double sgn = longTrade ? 1.0 : -1.0;
      if(sgn * (entry - sigD) <= 0.0 ||
         sgn * (sigA - entry) <= 0.0 ||
         sgn * (tp2  - entry) <= 0.0)
      {
         tr.miss = MISS_BAD_TARGET;
         break;
      }

      tr.entered = true;
      tr.miss    = MISS_NONE;
      tr.tEntry  = (long long)lo[i].time;
      tr.entry   = entry;
      tr.stop    = sigD;                 // D = بیشترین نفوذ تا لحظه ورود
      tr.tp1     = sigA;
      tr.tp2     = tp2;
      break;
   }

   if(!tr.entered) return tr;

   double risk = MathAbs(tr.entry - tr.stop);
   if(risk <= 0.0) { tr.entered = false; tr.miss = MISS_NO_CONFIRM; return tr; }

   // --- پیگیری معامله
   double worstBeyond = 0.0;
   bool   done = false;
   int    held = 0, afterStop = 0;

   for(int j = i + 1; j < (int)lo.size() && held < MAX_HOLD_LO_BARS; j++, held++)
   {
      double hh = lo[j].high, ll = lo[j].low;

      if(!done)
      {
         // استاپ اول فرض می‌شود اگر هر دو در یک کندل باشند
         bool hitStop = longTrade ? (ll <= tr.stop) : (hh >= tr.stop);
         if(hitStop)
         {
            tr.stopped = true;
            tr.tExit   = (long long)lo[j].time;
            done       = true;
         }
         else
         {
            if(!tr.hitTP1 && (longTrade ? (hh >= tr.tp1) : (ll <= tr.tp1)))
            { tr.hitTP1 = true; tr.tExit = (long long)lo[j].time; }

            if(longTrade ? (hh >= tr.tp2) : (ll <= tr.tp2))
            { tr.hitTP2 = true; tr.tExit = (long long)lo[j].time; done = true; }
         }
      }
      else if(tr.stopped && afterStop < AFTER_STOP_BARS)
      {
         // بعد از استاپ: چقدر رد شد و آیا بعدش به تارگت می‌رسید؟
         // پنجره کوتاه است تا «برگشت به تارگت» معنای واقعی داشته باشد.
         afterStop++;

         double beyond = longTrade ? (tr.stop - ll) : (hh - tr.stop);
         if(beyond > worstBeyond) worstBeyond = beyond;

         if(longTrade ? (hh >= tr.tp1) : (ll <= tr.tp1)) tr.tp1AfterStop = true;
         if(longTrade ? (hh >= tr.tp2) : (ll <= tr.tp2)) tr.tp2AfterStop = true;
      }
   }

   tr.beyondStop  = worstBeyond;
   tr.beyondStopR = (risk > 0.0) ? worstBeyond / risk : 0.0;

   double sgn = longTrade ? 1.0 : -1.0;
   double r1  = sgn * (tr.tp1 - tr.entry) / risk;
   double r2  = sgn * (tr.tp2 - tr.entry) / risk;

   tr.rTP1  = tr.hitTP1 ? r1 : -1.0;
   tr.rTP2  = tr.hitTP2 ? r2 : -1.0;
   tr.rHalf = (tr.hitTP1 ? 0.5 * r1 : -0.5) + (tr.hitTP2 ? 0.5 * r2 : -0.5);

   if(!tr.stopped && !tr.hitTP1 && !tr.hitTP2)
   {
      // نه استاپ خورد نه تارگت — تا انتهای پنجره باز ماند
      tr.rTP1 = tr.rTP2 = tr.rHalf = 0.0;
   }

   return tr;
}

//--------------------------------------------------------------------------
static void RecordTrade(const char *pair, int leg, const Trade &tr)
{
   TradeRec r;
   r.pair = pair; r.leg = leg; r.tr = tr;
   r.risk = MathAbs(tr.entry - tr.stop);
   r.rr1  = (r.risk > 0) ? MathAbs(tr.tp1 - tr.entry) / r.risk : 0.0;
   r.rr2  = (r.risk > 0) ? MathAbs(tr.tp2 - tr.entry) / r.risk : 0.0;
   g_all.push_back(r);
}

struct Stats
{
   int n = 0, win1 = 0, win2 = 0, loss = 0, open = 0;
   double sum1 = 0, sum2 = 0, sumH = 0;

   void add(const Trade &t)
   {
      n++;
      if(t.stopped)      loss++;
      else if(t.hitTP2)  win2++;
      else if(t.hitTP1)  win1++;
      else               open++;
      sum1 += t.rTP1; sum2 += t.rTP2; sumH += t.rHalf;
   }

   void print(const char *label) const
   {
      if(n == 0) { OUT("  %-12s معامله ای نبود\n", label); return; }
      OUT("  %-12s معامله=%2d  TP2=%2d  TP1=%2d  استاپ=%2d  باز=%2d"
             "  |  R کل:  TP1=%+.2f  TP2=%+.2f  نصف=%+.2f\n",
             label, n, win2, win1, loss, open, sum1, sum2, sumH);
   }
};

static void Report(const char *title,
                   const char *hiPath, int hiTF,
                   const char *loPath, int loTF)
{
   std::vector<MqlRates> hi, lo;
   if(!LoadCsv(hiPath, hi) || !LoadCsv(loPath, lo)) return;

   long long from = MathMax(hi.front().time, lo.front().time);

   OUT("\n================================================================\n");
   OUT(" %s   از %s\n", title, Stamp(from).c_str());
   OUT("================================================================\n");

   std::vector<Setup> setups;
   CollectSetups(hi, hiTF, from, setups);

   Stats s1, s2;
   int nFvg = 0, nHunt = 0;
   int miss1[8] = {0}, miss2[8] = {0};
   std::vector<const Setup*> nearMiss;

   for(size_t q = 0; q < setups.size(); q++)
   {
      Setup &st = setups[q];
      long long endT = st.tDead;   // 0 یعنی تا انتهای داده

      if(st.tFvg > 0)
      {
         nFvg++;
         st.t1 = RunLegTrade(lo, loTF, st.tFvg, endT,
                             !st.isBull,          // AB تایم پایین خلاف جهت
                             st.isBull,           // جهت معامله = جهت تایم بالا
                             false, 0, false,
                             st.hiB);             // TP2 = سطح B تایم بالا
         if(st.t1.entered) s1.add(st.t1); else miss1[st.t1.miss]++;
         if(st.t1.entered) RecordTrade(title, 1, st.t1);
      }

      if(st.tHunt > 0)
      {
         nHunt++;
         st.t2 = RunLegTrade(lo, loTF, st.tHunt, endT,
                             st.isBull,           // AB تایم پایین هم جهت
                             !st.isBull,          // معامله خلاف جهت تایم بالا
                             true, st.hiB, st.isBull,  // B تایم پایین آن طرف B تایم بالا
                             st.hiC);             // TP2 = نقطه C تایم بالا
         if(st.t2.entered) s2.add(st.t2); else miss2[st.t2.miss]++;
         if(st.t2.entered) RecordTrade(title, 2, st.t2);
      }
   }

   OUT("\n--- ستاپ ها\n");
   OUT("  الگوی تایم بالا (C ok)                : %d\n", (int)setups.size());
   OUT("  قیمت به FVG رسید (پنجره معامله ۱)     : %d\n", nFvg);
   OUT("  B تایم بالا هانت شد (پنجره معامله ۲)  : %d\n", nHunt);

   OUT("\n--- نتیجه معامله ها\n");
   s1.print("معامله ۱:");
   s2.print("معامله ۲:");

   OUT("\n--- چرا ورود انجام نشد (سطح هانت شد ولی تایم پایین ورود نداد)\n");
   for(int m = 1; m <= 7; m++)
      if(miss1[m] || miss2[m])
         OUT("  %-28s  معامله۱=%d  معامله۲=%d\n", MissText((MissReason)m),
                miss1[m], miss2[m]);

   // --- ستاپ های از دست رفته: اگر ورود نداشتیم، آیا تارگت زده می‌شد؟
   OUT("\n--- ستاپ های بدون ورود: قیمت به تارگت رسید یا نه؟\n");
   int missedHitB = 0, missedNotB = 0, missedHitC = 0, missedNotC = 0;

   for(size_t q = 0; q < setups.size(); q++)
   {
      const Setup &st = setups[q];

      if(st.tFvg > 0 && !st.t1.entered)
      {
         bool reached = (st.tHunt > 0);   // TP2 معامله ۱ = B تایم بالا
         if(reached) missedHitB++; else missedNotB++;
      }

      if(st.tHunt > 0 && !st.t2.entered)
      {
         // TP2 معامله ۲ = C تایم بالا: بعد از هانت، قیمت به C برگشت؟
         bool reached = false;
         for(size_t j = 0; j < hi.size(); j++)
         {
            if((long long)hi[j].time <= st.tHunt) continue;
            if(st.tDead > 0 && (long long)hi[j].time > st.tDead) break;
            if(st.isBull ? (hi[j].low <= st.hiC) : (hi[j].high >= st.hiC))
            { reached = true; break; }
         }
         if(reached) missedHitC++; else missedNotC++;
      }
   }

   OUT("  معامله ۱ از دست رفته: به B تایم بالا رسید=%d   نرسید=%d\n",
          missedHitB, missedNotB);
   OUT("  معامله ۲ از دست رفته: به C تایم بالا رسید=%d   نرسید=%d\n",
          missedHitC, missedNotC);

   // --- استاپ های با اختلاف کم
   OUT("\n--- استاپ ها: چقدر قیمت از استاپ رد شد و بعدش چه شد\n");
   OUT("  (beyond = بیشترین نفوذ بعد از استاپ، بر حسب فاصله استاپ،");
   OUT(" در %d کندل بعد)\n", AFTER_STOP_BARS);

   int nStop = 0, nNear = 0, nNearThenTP = 0;
   double sumBeyond = 0.0;

   for(size_t q = 0; q < setups.size(); q++)
   {
      const Setup &st = setups[q];
      const Trade *ts[2] = { &st.t1, &st.t2 };

      for(int t = 0; t < 2; t++)
      {
         const Trade &tr = *ts[t];
         if(!tr.entered || !tr.stopped) continue;

         nStop++;
         sumBeyond += tr.beyondStopR;

         bool near = (tr.beyondStopR <= NEAR_STOP_R);
         if(near) nNear++;
         if(near && (tr.tp1AfterStop || tr.tp2AfterStop)) nNearThenTP++;
      }
   }

   OUT("  کل استاپ ها: %d   |   میانگین نفوذ بعد از استاپ: %.0f%% از ریسک\n",
          nStop, nStop ? (sumBeyond / nStop) * 100.0 : 0.0);
   OUT("  «کم رد شد» (نفوذ <= %.0f%% ریسک): %d   از آنها بعدش به تارگت رسید: %d\n",
          NEAR_STOP_R * 100.0, nNear, nNearThenTP);

   if(nNear > 0)
   {
      OUT("\n  موارد «کم رد شد» — اینها با کمی استاپ بازتر نجات می‌یافتند:\n");
      for(size_t q = 0; q < setups.size(); q++)
      {
         const Setup &st = setups[q];
         const Trade *ts[2] = { &st.t1, &st.t2 };

         for(int t = 0; t < 2; t++)
         {
            const Trade &tr = *ts[t];
            if(!tr.entered || !tr.stopped) continue;
            if(tr.beyondStopR > NEAR_STOP_R) continue;

            OUT("   %s  معامله%d %s  ورود %.2f  SL %.2f  ریسک %.2f"
                   "  نفوذ %.2f (%.0f%%)  بعدش: %s%s\n",
                   Stamp(tr.tEntry).c_str(), t + 1, tr.isLong ? "خرید" : "فروش",
                   tr.entry, tr.stop, MathAbs(tr.entry - tr.stop),
                   tr.beyondStop, tr.beyondStopR * 100.0,
                   tr.tp1AfterStop ? "TP1 " : "",
                   tr.tp2AfterStop ? "TP2" : (tr.tp1AfterStop ? "" : "هیچ"));
         }
      }
   }

   // --- فهرست کامل معامله ها
   OUT("\n--- فهرست معامله ها\n");
   for(size_t q = 0; q < setups.size(); q++)
   {
      const Setup &st = setups[q];
      const Trade *ts[2] = { &st.t1, &st.t2 };

      for(int t = 0; t < 2; t++)
      {
         const Trade &tr = *ts[t];
         if(!tr.entered) continue;

         const char *res = tr.stopped ? "استاپ" : tr.hitTP2 ? "TP2" : tr.hitTP1 ? "TP1" : "باز";
         OUT("  %s  معامله%d %s  ورود %.2f  SL %.2f  TP1 %.2f  TP2 %.2f  -> %-6s"
                "  R(TP2)=%+.2f\n",
                Stamp(tr.tEntry).c_str(), t + 1, tr.isLong ? "خرید " : "فروش",
                tr.entry, tr.stop, tr.tp1, tr.tp2, res, tr.rTP2);
      }
   }
}

//--------------------------------------------------------------------------
// تحلیل ریسک به ریوارد: نسبت فاصله تارگت به فاصله استاپ، و اینکه برایند
// روی هر بازه از این نسبت مثبت بوده یا منفی.
static void RRAnalysis()
{
   if(g_all.empty()) { printf("\nمعامله ای برای تحلیل نیست\n"); return; }

   printf("\n\n================================================================\n");
   printf(" تحلیل ریسک به ریوارد — همه معامله ها (%d)\n", (int)g_all.size());
   printf("================================================================\n");

   printf("\n--- فهرست: فاصله ها و نسبت ها\n");
   printf("  %-16s %-4s %-5s %8s %8s %8s %7s %7s %8s\n",
          "زمان ورود", "پر", "جهت", "ریسک", "تا TP1", "تا TP2", "RR1", "RR2", "نتیجه");

   double sumRisk = 0, sumRR1 = 0, sumRR2 = 0;

   for(size_t i = 0; i < g_all.size(); i++)
   {
      const TradeRec &r = g_all[i];
      const Trade &t = r.tr;
      const char *res = t.stopped ? "استاپ" : t.hitTP2 ? "TP2" : t.hitTP1 ? "TP1" : "باز";

      printf("  %-16s  %d   %-5s %8.2f %8.2f %8.2f %7.2f %7.2f %8s\n",
             Stamp(t.tEntry).c_str(), r.leg, t.isLong ? "خرید" : "فروش",
             r.risk, MathAbs(t.tp1 - t.entry), MathAbs(t.tp2 - t.entry),
             r.rr1, r.rr2, res);

      sumRisk += r.risk; sumRR1 += r.rr1; sumRR2 += r.rr2;
   }

   int n = (int)g_all.size();
   printf("\n  میانگین: ریسک %.2f   RR1 %.2f   RR2 %.2f\n",
          sumRisk / n, sumRR1 / n, sumRR2 / n);

   // میانه RR2
   std::vector<double> v;
   for(size_t i = 0; i < g_all.size(); i++) v.push_back(g_all[i].rr2);
   std::sort(v.begin(), v.end());
   printf("  میانه RR2: %.2f   |   کمترین %.2f   بیشترین %.2f\n",
          v[n / 2], v.front(), v.back());

   // --- برایند به تفکیک بازه RR2
   printf("\n--- برایند به تفکیک نسبت ریسک به ریوارد (تارگت دوم)\n");
   printf("  %-12s %6s %6s %8s %10s %10s\n",
          "بازه RR2", "تعداد", "برد", "نرخ برد", "R (TP2)", "R (TP1)");

   double edges[] = { 0.0, 1.0, 2.0, 3.0, 5.0, 1e9 };
   const char *names[] = { "زیر 1", "1 تا 2", "2 تا 3", "3 تا 5", "بالای 5" };

   for(int b = 0; b < 5; b++)
   {
      int cnt = 0, win = 0;
      double r2 = 0, r1 = 0;

      for(size_t i = 0; i < g_all.size(); i++)
      {
         const TradeRec &r = g_all[i];
         if(r.rr2 < edges[b] || r.rr2 >= edges[b + 1]) continue;
         cnt++;
         if(r.tr.hitTP2) win++;
         r2 += r.tr.rTP2; r1 += r.tr.rTP1;
      }

      if(cnt == 0) continue;
      printf("  %-12s %6d %6d %7.0f%% %+10.2f %+10.2f\n",
             names[b], cnt, win, 100.0 * win / cnt, r2, r1);
   }

   // --- اگر فقط معامله هایی با حداقل RR مشخص گرفته می‌شد
   printf("\n--- اگر فقط معامله های با RR2 بالای حد مشخص گرفته می‌شد\n");
   printf("  %-10s %6s %6s %8s %10s %12s\n",
          "حداقل RR2", "تعداد", "برد", "نرخ برد", "R کل", "R هر معامله");

   double mins[] = { 0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0 };
   for(int m = 0; m < 7; m++)
   {
      int cnt = 0, win = 0;
      double tot = 0;

      for(size_t i = 0; i < g_all.size(); i++)
      {
         if(g_all[i].rr2 < mins[m]) continue;
         cnt++;
         if(g_all[i].tr.hitTP2) win++;
         tot += g_all[i].tr.rTP2;
      }

      if(cnt == 0) continue;
      printf("  >= %-7.1f %6d %6d %7.0f%% %+10.2f %+12.2f\n",
             mins[m], cnt, win, 100.0 * win / cnt, tot, tot / cnt);
   }

   // --- سربه سر لازم: با این RR میانگین، چه نرخ بردی لازم بود؟
   printf("\n--- نرخ برد لازم برای سربه سر\n");
   double avgRR2 = sumRR2 / n;
   int wins2 = 0;
   for(size_t i = 0; i < g_all.size(); i++) if(g_all[i].tr.hitTP2) wins2++;
   printf("  با RR2 میانگین %.2f، نرخ برد لازم %.0f%% است؛ نرخ برد واقعی %.0f%%\n",
          avgRR2, 100.0 / (1.0 + avgRR2), 100.0 * wins2 / n);
}

//--------------------------------------------------------------------------
// اجرای ساکت یک تنظیم، فقط برای جدول مقایسه
struct Summary { int n=0, win=0; double R=0; };

static Summary RunQuiet()
{
   g_all.clear();
   g_quiet = true;

   Report("H1  <->  M5", "data/GOH_XAUUSD_H1.csv", PERIOD_H1,
          "data/GOH_XAUUSD_M5.csv", PERIOD_M5);
   Report("H4  <->  M15", "data/GOH_XAUUSD_H4.csv", PERIOD_H4,
          "data/GOH_XAUUSD_M15.csv", PERIOD_M15);

   g_quiet = false;

   Summary s;
   for(size_t i = 0; i < g_all.size(); i++)
   {
      s.n++;
      if(g_all[i].tr.hitTP2) s.win++;
      s.R += g_all[i].tr.rTP2;
   }
   return s;
}

static void Matrix()
{
   printf("\n\n================================================================\n");
   printf(" اثر دو قاعده جدید — همه ترکیب ها\n");
   printf("================================================================\n");
   printf("  (R بر مبنای بستن کل حجم روی TP2)\n\n");
   printf("  %-14s %-10s %7s %6s %8s %10s %12s\n",
          "بادی سیگنال", "RR هدف", "معامله", "برد", "نرخ برد", "R کل", "R هر معامله");

   double bodies[] = { 0.0, 40.0, 50.0, 60.0, 70.0 };
   double rrs[]    = { 0.0, 2.0, 3.0, 4.0 };

   for(int b = 0; b < 5; b++)
   {
      for(int r = 0; r < 4; r++)
      {
         g_cfg = Cfg();
         g_cfg.sigMinBodyPct = bodies[b];
         g_cfg.targetRR      = rrs[r];

         Summary s = RunQuiet();

         char bl[32], rl[32];
         if(bodies[b] <= 0) snprintf(bl, sizeof(bl), "خاموش");
         else               snprintf(bl, sizeof(bl), ">= %.0f%%", bodies[b]);
         if(rrs[r] <= 0)    snprintf(rl, sizeof(rl), "کلوز");
         else               snprintf(rl, sizeof(rl), "1:%.0f", rrs[r]);

         printf("  %-14s %-10s %7d %6d %7.0f%% %+10.2f %+12.2f\n",
                bl, rl, s.n, s.win,
                s.n ? 100.0 * s.win / s.n : 0.0, s.R,
                s.n ? s.R / s.n : 0.0);
      }
      printf("\n");
   }
}

int main()
{
   printf("بک تست سیستم دو معامله ای فراکتالی — XAUUSD\n");
   printf("فرض ها: ورود روی کلوز کندل تایید | استاپ روی خود D بدون حاشیه |\n");
   printf("        بدون اسپرد و اسلیپیج | استاپ قبل از TP در کندل مشترک\n");

   Matrix();

   // اجرای پرگزارش با تنظیم انتخاب شده
   g_cfg = Cfg();
   g_cfg.sigMinBodyPct = SHOW_BODY;
   g_cfg.targetRR      = SHOW_RR;
   g_all.clear();

   printf("\n\n################################################################\n");
   printf(" گزارش کامل با تنظیم:  بادی سیگنال >= %.0f%%   |   RR هدف 1:%.0f\n",
          SHOW_BODY, SHOW_RR);
   printf("################################################################\n");

   Report("H1  <->  M5", "data/GOH_XAUUSD_H1.csv", PERIOD_H1,
          "data/GOH_XAUUSD_M5.csv", PERIOD_M5);

   Report("H4  <->  M15", "data/GOH_XAUUSD_H4.csv", PERIOD_H4,
          "data/GOH_XAUUSD_M15.csv", PERIOD_M15);

   RRAnalysis();
   return 0;
}
