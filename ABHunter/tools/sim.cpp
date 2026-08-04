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

static bool g_verbose = false;
#define DBG(fn, ln) do { if(g_verbose) printf("      x %s check #%d\n", fn, ln); } while(0)

#include "sim_core.h"

//--------------------------------------------------------------------------
static std::vector<MqlRates> g_bars;

static void Bar(double o, double h, double l, double c)
{
   MqlRates r;
   memset(&r, 0, sizeof(r));
   r.time  = 1767225600LL + (long long)g_bars.size() * 14400LL;  // H4 spacing
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
   int nAct = BuildActiveSwings(rates, n, avgRange, raw, nRaw, act, false, false);
   printf("  BuildActiveSwings -> %d\n", nAct);

   for(int k = 0; k < nAct; k++)
      printf("    act[%d] %s A=%d B=%d state=%s C=%d\n",
             k, act[k].isBull ? "BULL" : "BEAR", act[k].idxA, act[k].idxB,
             StateName(act[k].state), act[k].idxC);

   // why did a raw swing die?
   for(int k = 0; k < nRaw; k++)
   {
      SwingAB s = raw[k];
      g_verbose = true;
      EvaluateLifecycle(s, rates, n, avgRange);
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
      Run("B taken with too short a retracement");
   }

   return 0;
}
