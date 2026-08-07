// Does a change cost us patterns *after* the lifecycle runs?
//
// diff.cpp only counts what CollectSwings finds. But moving A changes
// s.size, which moves the 20% floor, the 60% ceiling and the CD > AB
// threshold — so a swing can survive detection and still die differently.
// This runs BuildActiveSwings twice over identical bars with one input
// changed, matches patterns by (idxZero, direction), and reports how the
// outcome moved.
#include <cstdio>
#include <cstring>
#include <string>
#include <cmath>
#include <vector>
#include <map>
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
#define DBG(fn, ln) do { } while(0)

#include "sim_core.h"

//--------------------------------------------------------------------------
static std::mt19937 rng(20260804);
static std::vector<MqlRates> bars;
static long long g_barSeconds = 3600;

static void Push(double o, double h, double l, double c)
{
   MqlRates r; memset(&r, 0, sizeof(r));
   r.time = 1767225600LL + (long long)bars.size() * g_barSeconds;
   r.open = o; r.high = h; r.low = l; r.close = c;
   bars.push_back(r);
}

static void MakeSeries(int n)
{
   bars.clear();
   std::uniform_real_distribution<double> u(0.0, 1.0);
   double px = 1.0, drift = 0.0;
   int left = 0;

   for(int i = 0; i < n; i++)
   {
      if(left <= 0) { left = 3 + (int)(u(rng) * 10); drift = (u(rng) - 0.5) * 0.0020; }
      left--;
      double body = drift + (u(rng) - 0.5) * 0.0010;
      double o = px, c = px + body;
      Push(o, MathMax(o, c) + u(rng) * 0.0004, MathMin(o, c) - u(rng) * 0.0004, c);
      px = c;
   }
}

static const char *Outcome(SwingAB &s)
{
   if(s.state == AB_INVALID)
   {
      switch(s.deadReason)
      {
         case AB_DEAD_RETRACE: return "X >60%";
         case AB_DEAD_BEARLY:  return "X earlyB";
         case AB_DEAD_CD:      return "X CD>AB";
         case AB_DEAD_EXPIRED: return "X old";
         default:              return "X ?";
      }
   }
   switch(s.state)
   {
      case AB_FORMING:      return "...";
      case AB_WAIT_RETRACE: return "WAIT";
      case AB_RETRACED:     return "C ok";
      case AB_BROKEN:       return "HUNT/BREAK";
      case AB_DONE:         return "DONE";
   }
   return "?";
}

// آیا این نتیجه یعنی الگو هنوز در جدول و روی چارت هست؟
static bool Alive(SwingAB &s)
{
   return (s.state == AB_WAIT_RETRACE || s.state == AB_RETRACED || s.state == AB_BROKEN);
}

struct Result { long long key; std::string outcome; bool alive; };

static void RunOnce(int series, int nbars, ENUM_TIMEFRAMES tf, std::vector<Result> &out)
{
   static MqlRates r[8192];
   static SwingAB  raw[8192], act[8192];

   int n = (int)bars.size();
   for(int i = 0; i < n; i++) r[i] = bars[i];

   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += (r[i].high - r[i].low);

   int nRaw = CollectSwings(r, n, MinCandles, raw);
   int nAct = BuildActiveSwings(r, n, sum / n, raw, nRaw, act, false, false, tf);

   out.clear();
   for(int k = 0; k < nAct; k++)
   {
      Result q;
      q.key     = (long long)series * 1000000LL + act[k].idxZero * 2 + (act[k].isBull ? 1 : 0);
      q.outcome = Outcome(act[k]);
      q.alive   = Alive(act[k]);
      out.push_back(q);
   }
}

int main(int argc, char **argv)
{
   const int SERIES = 400, NBARS = 300;
   ENUM_TIMEFRAMES tf = PERIOD_H4;

   int savedA = AConfirmBars;

   std::map<std::string, int> moves;
   long aliveBefore = 0, aliveAfter = 0, lostAlive = 0, gainedAlive = 0;
   long onlyBefore = 0, onlyAfter = 0, total = 0;

   for(int s = 0; s < SERIES; s++)
   {
      MakeSeries(NBARS);

      std::vector<Result> before, after;

      AConfirmBars = 0;   // v2.75
      RunOnce(s, NBARS, tf, before);

      AConfirmBars = savedA;   // v2.76
      RunOnce(s, NBARS, tf, after);

      std::map<long long, Result> mb, ma;
      for(size_t i = 0; i < before.size(); i++) mb[before[i].key] = before[i];
      for(size_t i = 0; i < after.size();  i++) ma[after[i].key]  = after[i];

      for(std::map<long long, Result>::iterator it = mb.begin(); it != mb.end(); ++it)
      {
         total++;
         if(it->second.alive) aliveBefore++;

         std::map<long long, Result>::iterator jt = ma.find(it->first);
         if(jt == ma.end())
         {
            onlyBefore++;
            if(it->second.alive) lostAlive++;
            moves[it->second.outcome + "  ->  (gone)"]++;
            continue;
         }
         if(jt->second.outcome != it->second.outcome)
            moves[it->second.outcome + "  ->  " + jt->second.outcome]++;

         if(it->second.alive && !jt->second.alive) lostAlive++;
         if(!it->second.alive && jt->second.alive) gainedAlive++;
      }

      for(std::map<long long, Result>::iterator it = ma.begin(); it != ma.end(); ++it)
      {
         if(it->second.alive) aliveAfter++;
         if(mb.find(it->first) == mb.end())
         {
            onlyAfter++;
            if(it->second.alive) gainedAlive++;
            moves[std::string("(new)  ->  ") + it->second.outcome]++;
         }
      }
   }

   printf("%d series x %d bars, tf=H4\n\n", SERIES, NBARS);
   printf("  patterns, AConfirmBars=0 : %ld\n", total);
   printf("  only before (lost)       : %ld\n", onlyBefore);
   printf("  only after  (new)        : %ld\n", onlyAfter);
   printf("\n  ON CHART / IN LIST (WAIT, C ok, HUNT/BREAK)\n");
   printf("    before : %ld\n", aliveBefore);
   printf("    after  : %ld\n", aliveAfter);
   printf("    lost   : %ld   <-- الگویی که قبلا بود و حالا نیست\n", lostAlive);
   printf("    gained : %ld\n", gainedAlive);

   printf("\n  outcome changes\n");
   for(std::map<std::string, int>::iterator it = moves.begin(); it != moves.end(); ++it)
      printf("    %-28s %d\n", it->first.c_str(), it->second);

   return 0;
}
