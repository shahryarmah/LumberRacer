// Runs ABHunterCore's detection on synthetic candles.
#include <cstdio>
#include <cstring>
#include <string>
#include <cmath>
#include <vector>

typedef std::string string;
typedef long long   datetime;
typedef int         ENUM_TIMEFRAMES;

#define PERIOD_M1 1
#define PERIOD_M2 2
#define PERIOD_M3 3
#define PERIOD_M4 4
#define PERIOD_M5 5
#define PERIOD_M6 6
#define PERIOD_M10 10
#define PERIOD_M12 12
#define PERIOD_M15 15
#define PERIOD_M20 20
#define PERIOD_M30 30
#define PERIOD_H1 16385
#define PERIOD_H2 16386
#define PERIOD_H3 16387
#define PERIOD_H4 16388
#define PERIOD_H6 16390
#define PERIOD_H8 16392
#define PERIOD_H12 16396
#define PERIOD_D1 16408

struct MqlRates
{
   datetime time;
   double   open, high, low, close;
   long     tick_volume, real_volume;
   int      spread;
};

template<typename T> T MathAbs(T v) { return v < 0 ? -v : v; }
template<typename T> T MathMin(T a, T b) { return a < b ? a : b; }
template<typename T> T MathMax(T a, T b) { return a > b ? a : b; }
template<typename T, std::size_t N> int ArraySize(T (&)[N]) { return (int)N; }
template<typename T> int ArrayResize(T *, int size, int = 0) { return size; }

static string IntegerToString(long v, int = 0, int = 0) { return std::to_string(v); }

static int  Bars(const string &, int) { return 0; }
template<typename T> bool ArraySetAsSeries(T *, bool) { return true; }
template<typename T> int  CopyRates(const string &, int, int, int, T *) { return 0; }

// فاصله زمانی کندل ها؛ سناریوها می‌توانند عوضش کنند تا قواعد وابسته به
// تایم فریم (مثل سقف یک روزه روی H2 و پایین تر) تست شوند.
static long long g_barSeconds = 14400;   // H4
static int       g_simTF      = PERIOD_H4;

static int PeriodSeconds(int tf)
{
   switch(tf)
   {
      case PERIOD_M1: return 60;      case PERIOD_M2:  return 120;
      case PERIOD_M3: return 180;     case PERIOD_M4:  return 240;
      case PERIOD_M5: return 300;     case PERIOD_M6:  return 360;
      case PERIOD_M10: return 600;    case PERIOD_M12: return 720;
      case PERIOD_M15: return 900;    case PERIOD_M20: return 1200;
      case PERIOD_M30: return 1800;   case PERIOD_H1:  return 3600;
      case PERIOD_H2: return 7200;    case PERIOD_H3:  return 10800;
      case PERIOD_H4: return 14400;   case PERIOD_H6:  return 21600;
      case PERIOD_H8: return 28800;   case PERIOD_H12: return 43200;
      case PERIOD_D1: return 86400;
   }
   return 0;
}

static bool g_verbose = false;
#define DBG(fn, ln) do { if(g_verbose) printf("      x %s check #%d\n", fn, ln); } while(0)

#include "sim_core.h"

//--------------------------------------------------------------------------
static std::vector<MqlRates> g_bars;

static void Bar(double o, double h, double l, double c)
{
   MqlRates r;
   memset(&r, 0, sizeof(r));
   r.time  = 1767225600LL + (long long)g_bars.size() * g_barSeconds;
   r.open = o; r.high = h; r.low = l; r.close = c;
   g_bars.push_back(r);
}

// A clean directional candle: body `body`, wicks a fraction of the body.
static void Impulse(double &px, double body, double wick, bool up)
{
   double o = px;
   double c = up ? px + body : px - body;
   double h = MathMax(o, c) + wick;
   double l = MathMin(o, c) - wick;
   Bar(o, h, l, c);
   px = c;
}

static void Flat(double &px, double range)
{
   Bar(px, px + range, px - range, px);
}

static const char *StateName(ABState s)
{
   switch(s)
   {
      case AB_FORMING:      return "FORMING";
      case AB_WAIT_RETRACE: return "WAIT";
      case AB_RETRACED:     return "C ok";
      case AB_BROKEN:       return "BROKEN";
      case AB_DONE:         return "DONE";
      case AB_INVALID:      return "INVALID";
   }
   return "?";
}

static void Run(const char *title)
{
   int n = (int)g_bars.size();
   printf("\n=== %s   (%d bars)\n", title, n);

   MqlRates *rates = g_bars.data();

   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += rates[i].high - rates[i].low;
   double avgRange = sum / n;

   static SwingAB raw[8192];
   int nRaw = CollectSwings(rates, n, MinCandles, raw);
   printf("  CollectSwings -> %d\n", nRaw);

   for(int k = 0; k < nRaw; k++)
      printf("    raw[%d] %s A=%d(%.5f) B=%d(%.5f) size=%.5f live=%d\n",
             k, raw[k].isBull ? "BULL" : "BEAR", raw[k].idxA, raw[k].priceA,
             raw[k].idxB, raw[k].priceB, raw[k].size, (int)raw[k].live);

   // regression guard: two accepted swings may share only the turning bar
   for(int k = 0; k + 1 < nRaw; k++)
      if(raw[k].idxB > raw[k+1].idxA)
         printf("    !! OVERLAP raw[%d].B=%d > raw[%d].A=%d\n",
                k, raw[k].idxB, k+1, raw[k+1].idxA);

   static SwingAB act[8192];
   int nAct = BuildActiveSwings(rates, n, avgRange, raw, nRaw, act, false, false, g_simTF);
   printf("  BuildActiveSwings -> %d\n", nAct);

   for(int k = 0; k < nAct; k++)
      printf("    act[%d] %s A=%d Adraw=%d Z=%d B=%d state=%-7s C=%-3d %s\n",
             k, act[k].isBull ? "BULL" : "BEAR", act[k].idxA, act[k].idxADraw,
             act[k].idxZero, act[k].idxB, StateName(act[k].state), act[k].idxC,
             DeadReasonText(act[k].deadReason).c_str());

   // why did a raw swing die?
   for(int k = 0; k < nRaw; k++)
   {
      SwingAB s = raw[k];
      g_verbose = true;
      EvaluateLifecycle(s, rates, n, avgRange, g_simTF);
      g_verbose = false;
      printf("    lifecycle raw[%d] -> %s\n", k, StateName(s.state));
   }
}

//--------------------------------------------------------------------------
int main()
{

   // --- 1: textbook clean bullish impulse + retracement, nothing after
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);          // quiet base
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);   // AB
      for(int i = 0; i < 4; i++) Impulse(px, 0.00100, 0.00020, false);  // B->C (40%)
      for(int i = 0; i < 3; i++) Flat(px, 0.00020);
      Run("clean bullish AB + retracement");
   }

   // --- 2: same, then a strong counter impulse after C
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00120, 0.00020, false);  // deeper, itself a clean leg
      for(int i = 0; i < 3; i++) Flat(px, 0.00020);
      Run("bullish AB followed by a clean counter leg");
   }

   // --- 3: bearish leg ending on a small-bodied reversal candle (AUDUSD H4 shape)
   {
      g_bars.clear();
      double px = 0.70500;
      for(int i = 0; i < 6; i++) Flat(px, 0.00030);
      Impulse(px, 0.00206, 0.00030, false);
      Impulse(px, 0.00090, 0.00015, false);
      Impulse(px, 0.00150, 0.00020, false);
      Bar(px, px + 0.00015, px - 0.00070, px + 0.00005);      // pin bottom = B
      px = px + 0.00005;
      for(int i = 0; i < 4; i++) Impulse(px, 0.00060, 0.00015, true);
      Run("bearish leg with a pin-bar bottom");
   }

   // --- 4: long noisy zig-zag; watch the swing count does not explode
   {
      g_bars.clear();
      double px = 1.20000;
      for(int leg = 0; leg < 6; leg++)
      {
         bool up = (leg % 2 == 0);
         for(int i = 0; i < 5; i++) Impulse(px, 0.00180, 0.00030, up);
         for(int i = 0; i < 3; i++) Impulse(px, 0.00070, 0.00025, !up);
      }
      Run("long zig-zag, 6 legs");
   }

   // --- 5: B hunted by the still-forming candle (AUDCAD H8 shape)
   //     valid retracement of 4 bars, then the live bar poking above B
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);   // A -> B
      double bLevel = px;
      for(int i = 0; i < 4; i++) Impulse(px, 0.00100, 0.00020, false);  // B -> C, 40%
      Bar(px, bLevel + 0.00060, px - 0.00020, bLevel + 0.00040);        // live bar crosses B
      Run("B hunted by the unclosed candle");
   }

   // --- 6: same, but the retracement is only 2 bars -> must invalidate
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);
      double bLevel = px;
      for(int i = 0; i < 2; i++) Impulse(px, 0.00200, 0.00020, false);
      Bar(px, bLevel + 0.00060, px - 0.00020, bLevel + 0.00040);
      Run("B taken after a 2-bar retracement -> invalid, C needs 3 bars");
   }

   // --- 7: deep but SHORT retracement (2 bars), then B hunted.
   //     must be HUNT, not deleted: only a shallow (<20%) retracement kills it
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);   // AB = 0.01040
      double bLevel = px;
      Impulse(px, 0.00250, 0.00020, false);        // 2-bar retrace, ~48% - deep enough
      Impulse(px, 0.00250, 0.00020, false);
      Bar(px, bLevel + 0.00060, px - 0.00020, bLevel + 0.00040);        // live bar takes B
      Run("deep but 2-bar retracement -> invalid, rest is too short");
   }

   // --- 8: a pullback under 20% is not a retracement at all -- B simply
   //     extends through it, so there is no AB waiting to be invalidated.
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);
      for(int i = 0; i < 2; i++) Impulse(px, 0.00025, 0.00005, false);  // ~5%
      for(int i = 0; i < 3; i++) Impulse(px, 0.00200, 0.00020, true);
      for(int i = 0; i < 4; i++) Impulse(px, 0.00120, 0.00020, false);
      Run("sub-20% pullback: B extends through it");
   }

   // --- 9: hunt happens late in the retracement, then the trade runs on.
   //     MaxRetraceBars must stop counting at the hunt, or the pattern would
   //     be deleted mid-trade.
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);   // AB = 0.01040
      double bLevel = px;
      for(int i = 0; i < 4; i++) Impulse(px, 0.00090, 0.00015, false);  // ~35% retrace
      for(int i = 0; i < 17; i++) Flat(px, 0.00020);                    // long, quiet drift
      Impulse(px, 0.00400, 0.00020, true);                              // bar 22: takes B
      for(int i = 0; i < 10; i++) Flat(px, 0.00020);                    // trade runs on
      printf("\n  (MaxRetraceBars = %d, bars after B = %d)\n",
             MaxRetraceBars, (int)g_bars.size() - 1 - 10);
      Run("hunt at bar B+22, then 10 more bars");
   }

   // --- 10: A must sit on the first SAME-DIRECTION candle of the leg.
   //     A bullish spike makes the highest high right before a bearish leg;
   //     A belongs on the first bearish candle, not on that spike.
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      Impulse(px, 0.00300, 0.00080, true);          // spike up - highest high
      double spikeHigh = px + 0.00080;
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, false);   // the leg
      for(int i = 0; i < 6; i++) Impulse(px, 0.00080, 0.00015, true);    // retrace
      printf("\n  (spike high = %.5f, first bearish candle high = %.5f)\n",
             spikeHigh, spikeHigh - 0.00080);
      Run("A on the first same-direction candle, not the spike");
   }

   // --- 11: within the 3-bar window a wick pierces candle 0 -> B moves there
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);
      double h0 = px + 0.00020;                      // candle 0 high
      Bar(px, h0 + 0.00050, px - 0.00100, px - 0.00090);   // wick above, closes below
      px -= 0.00090;
      for(int i = 0; i < 6; i++) Impulse(px, 0.00080, 0.00015, false);
      printf("\n  (candle0 high = %.5f, piercing wick = %.5f)\n", h0, h0 + 0.00050);
      Run("wick pierces candle 0 inside the window -> B moves to the wick");
   }

   // --- 12: a body close beyond candle 0 restarts the window
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);
      Impulse(px, 0.00050, 0.00010, false);          // candle 1, small pullback
      Impulse(px, 0.00250, 0.00020, true);           // candle 2 closes above candle 0
      for(int i = 0; i < 6; i++) Impulse(px, 0.00080, 0.00015, false);
      Run("body close beyond candle 0 restarts the window");
   }

   // --- 13: the whole retracement happens in candles 1-3 and price is already
   //     back near B by candle 4, which then takes it. Must reach HUNT, not
   //     "X earlyB" — candles 1-3 are part of the BC correction (NZDJPY M15).
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);   // A -> B
      double bLevel = px + 0.00020;
      Impulse(px, 0.00250, 0.00020, false);       // candle 1
      Impulse(px, 0.00200, 0.00020, false);       // candle 2  -> ~43% down
      double low = px;
      Impulse(px, 0.00380, 0.00020, true);        // candle 3, back up near B
      Impulse(px, 0.00300, 0.00020, true);        // candle 4 takes B
      for(int i = 0; i < 3; i++) Flat(px, 0.00020);
      printf("\n  (B = %.5f, 20%% level = %.5f, retrace low = %.5f)\n",
             bLevel, bLevel - 0.00208, low);
      Run("retracement lives in candles 1-3, B taken at candle 4");
   }

   // --- 14: the one-day cap applies on H2 and below only.
   //     Same bars, same pattern, evaluated once as M15 (one day = 96 bars,
   //     so it must expire) and once as H4 (rule off, so it must stay alive).
   {
      int savedRetraceBars = MaxRetraceBars;
      MaxRetraceBars = 0;                 // بی نهایت، تا فقط قاعده روز تست شود

      g_bars.clear();
      double px = 1.00000;
      g_barSeconds = 900;                 // M15
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);
      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);   // A -> B
      for(int i = 0; i < 4; i++) Impulse(px, 0.00080, 0.00015, false);  // C معتبر
      for(int i = 0; i < 110; i++) Flat(px, 0.00020);                   // بیش از یک روز

      g_simTF = PERIOD_M15;
      Run("one-day cap ON at M15 (should be X old)");

      g_simTF = PERIOD_H4;
      Run("same bars at H4 (rule off, should stay alive)");

      g_simTF      = PERIOD_H4;
      g_barSeconds = 14400;
      MaxRetraceBars = savedRetraceBars;
   }

   // --- 15: the leg's true origin is the candle AFTER the first bullish one:
   //     a bearish candle whose long lower wick dips below it. A must land on
   //     that wick, not on the first bullish candle's low (NDXUSD H6).
   {
      g_bars.clear();
      double px = 1.00000;
      for(int i = 0; i < 6; i++) Flat(px, 0.00020);

      Impulse(px, 0.00060, 0.00010, true);       // اولین کندل هم جهت
      double firstBullLow = px - 0.00060 - 0.00010;

      double o = px;                              // کندل نزولی با شدوی بلند
      double c = px - 0.00030;
      double deepLow = firstBullLow - 0.00090;    // مبدا واقعی لگ
      Bar(o, o + 0.00010, deepLow, c);
      px = c;

      for(int i = 0; i < 5; i++) Impulse(px, 0.00200, 0.00020, true);
      for(int i = 0; i < 6; i++) Impulse(px, 0.00080, 0.00015, false);

      printf("\n  (first bullish low = %.5f, true origin wick = %.5f)\n",
             firstBullLow, deepLow);
      Run("A drawn on the deeper wick just after the first bullish candle");

      int saved = AConfirmBars;
      AConfirmBars = 0;                 // رفتار نسخه 2.75
      Run("same bars with AConfirmBars=0 (Adraw must fall back to A)");
      AConfirmBars = saved;
   }

   return 0;
}
