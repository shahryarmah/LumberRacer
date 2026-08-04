// Differential test: current CollectSwings vs the old ShinMim one that worked.
#include <cstdio>
#include <cstring>
#include <string>
#include <cmath>
#include <vector>
#include <random>

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

struct MqlRates { datetime time; double open, high, low, close; long tick_volume, real_volume; int spread; };

template<typename T> T MathAbs(T v) { return v < 0 ? -v : v; }
template<typename T> T MathMin(T a, T b) { return a < b ? a : b; }
template<typename T> T MathMax(T a, T b) { return a > b ? a : b; }
template<typename T, std::size_t N> int ArraySize(T (&)[N]) { return (int)N; }
template<typename T> int ArrayResize(T *, int size, int = 0) { return size; }
static string IntegerToString(long v, int = 0, int = 0) { return std::to_string(v); }
static int  Bars(const string &, int) { return 0; }
template<typename T> bool ArraySetAsSeries(T *, bool) { return true; }
template<typename T> int  CopyRates(const string &, int, int, int, T *) { return 0; }

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
static int  g_hits[400];
#define DBG(fn, ln) do { g_hits[ln]++; } while(0)

#include "sim_core.h"
#include "sim_old.h"

//--------------------------------------------------------------------------
static std::mt19937 rng(20260804);
static std::vector<MqlRates> bars;

static void Push(double o, double h, double l, double c)
{
   MqlRates r; memset(&r, 0, sizeof(r));
   r.time = 1767225600LL + (long long)bars.size() * 3600LL;
   r.open = o; r.high = h; r.low = l; r.close = c;
   bars.push_back(r);
}

// Random walk with trending stretches — rough stand-in for real FX bars.
static void MakeSeries(int n)
{
   bars.clear();
   std::uniform_real_distribution<double> u(0.0, 1.0);
   double px = 1.0;
   double drift = 0.0;
   int    left  = 0;

   for(int i = 0; i < n; i++)
   {
      if(left <= 0)
      {
         left  = 3 + (int)(u(rng) * 10);
         drift = (u(rng) - 0.5) * 0.0020;
      }
      left--;

      double body = drift + (u(rng) - 0.5) * 0.0010;
      double o = px, c = px + body;
      double wu = u(rng) * 0.0004, wd = u(rng) * 0.0004;
      Push(o, MathMax(o, c) + wu, MathMin(o, c) - wd, c);
      px = c;
   }
}

int main()
{
   static SwingAB a[8192], b[8192];
   long totNew = 0, totOld = 0, both = 0, onlyOld = 0, onlyNew = 0;

   for(int trial = 0; trial < 300; trial++)
   {
      MakeSeries(300);
      MqlRates *r = bars.data();
      int n = (int)bars.size();

      int nNew = CollectSwings(r, n, MinCandles, a);
      int nOld = CollectSwingsOld(r, n, MinCandles, b);
      totNew += nNew; totOld += nOld;

      for(int i = 0; i < nOld; i++)
      {
         bool found = false;
         for(int j = 0; j < nNew; j++)
            if(a[j].idxB == b[i].idxB && a[j].isBull == b[i].isBull) { found = true; break; }
         if(found) both++; else onlyOld++;
      }
      for(int j = 0; j < nNew; j++)
      {
         bool found = false;
         for(int i = 0; i < nOld; i++)
            if(a[j].idxB == b[i].idxB && a[j].isBull == b[i].isBull) { found = true; break; }
         if(!found) onlyNew++;
      }
   }

   printf("300 series x 300 bars\n");
   printf("  old (ShinMim, works) : %ld swings\n", totOld);
   printf("  new (v2.53)          : %ld swings\n", totNew);
   printf("  matched by B         : %ld\n", both);
   printf("  found only by OLD    : %ld   <-- what we regressed on\n", onlyOld);
   printf("  found only by NEW    : %ld\n", onlyNew);

   printf("\nValidateAB rejections by check #:\n");
   for(int i = 0; i < 400; i++)
      if(g_hits[i]) printf("   #%-4d %d\n", i, g_hits[i]);
   return 0;
}
