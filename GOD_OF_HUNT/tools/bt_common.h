// بستر مشترک بک تست: شیم MQL5، بارگذاری CSV، و بازپخش بدون نگاه به آینده.
//
// نکته اصلی: منطق تشخیص از sim_core.h می‌آید که mksim.py آن را از خود
// GOD_OF_HUNT_Core.mqh می‌سازد. پس بک تست روی همان کدی اجرا می‌شود که در
// متاتریدر کار می‌کند، نه روی یک بازنویسی موازی. (LESSONS.md بند ۱)
#pragma once
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <ctime>
#include <string>
#include <vector>
#include <algorithm>

typedef std::string string;
typedef long long   datetime;

enum ENUM_TIMEFRAMES {
  PERIOD_CURRENT = 0,
  PERIOD_M1 = 1, PERIOD_M2 = 2, PERIOD_M3 = 3, PERIOD_M4 = 4, PERIOD_M5 = 5,
  PERIOD_M6 = 6, PERIOD_M10 = 10, PERIOD_M12 = 12, PERIOD_M15 = 15,
  PERIOD_M20 = 20, PERIOD_M30 = 30,
  PERIOD_H1 = 16385, PERIOD_H2 = 16386, PERIOD_H3 = 16387, PERIOD_H4 = 16388,
  PERIOD_H6 = 16390, PERIOD_H8 = 16392, PERIOD_H12 = 16396, PERIOD_D1 = 16408
};

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
template<typename T> int  ArrayResize(T *, int size, int = 0) { return size; }
template<typename T> bool ArraySetAsSeries(T *, bool) { return true; }
template<typename T> int  CopyRates(const string &, int, int, int, T *) { return 0; }
static string IntegerToString(long v, int = 0, int = 0) { return std::to_string(v); }
static int    Bars(const string &, int) { return 0; }

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
// بارگذاری CSV تولید شده با ExportRates.mq5:  time,open,high,low,close
// زمان به وقت سرور بروکر است و به عنوان UTC خوانده می‌شود؛ چون همه مقایسه ها
// نسبی اند، فقط باید بین دو تایم فریم یکسان باشد.
static long long ParseStamp(const char *s)
{
   struct tm tmv;
   memset(&tmv, 0, sizeof(tmv));
   int Y, M, D, h, m;
   if(sscanf(s, "%d.%d.%d %d:%d", &Y, &M, &D, &h, &m) != 5) return -1;
   tmv.tm_year = Y - 1900; tmv.tm_mon = M - 1; tmv.tm_mday = D;
   tmv.tm_hour = h;        tmv.tm_min = m;
   return (long long)timegm(&tmv);
}

static bool LoadCsv(const char *path, std::vector<MqlRates> &out)
{
   FILE *f = fopen(path, "r");
   if(!f) { printf("cannot open %s\n", path); return false; }

   char line[512];
   bool first = true;
   out.clear();

   while(fgets(line, sizeof(line), f))
   {
      if(first) { first = false; continue; }          // سربرگ

      char stamp[64];
      double o, h, l, c;
      // زمان تا اولین کاما، بعد چهار عدد
      const char *comma = strchr(line, ',');
      if(!comma) continue;
      size_t len = (size_t)(comma - line);
      if(len >= sizeof(stamp)) continue;
      memcpy(stamp, line, len); stamp[len] = 0;

      if(sscanf(comma + 1, "%lf,%lf,%lf,%lf", &o, &h, &l, &c) != 4) continue;

      long long t = ParseStamp(stamp);
      if(t < 0) continue;

      MqlRates r; memset(&r, 0, sizeof(r));
      r.time = t; r.open = o; r.high = h; r.low = l; r.close = c;
      out.push_back(r);
   }

   fclose(f);
   return !out.empty();
}

static string Stamp(long long t)
{
   time_t tt = (time_t)t;
   struct tm g;
   gmtime_r(&tt, &g);
   char buf[32];
   strftime(buf, sizeof(buf), "%Y.%m.%d %H:%M", &g);
   return string(buf);
}

//--------------------------------------------------------------------------
// وضعیت الگوها «همانطور که در لحظه بسته شدن کندل idx دیده می‌شد».
//
// بدون نگاه به آینده: فقط کندل های 0..idx پاس داده می‌شوند و هسته آخرین
// کندل را «در حال تشکیل» می‌بیند — دقیقا مثل زنده. چون در بک تست کندل idx
// کامل است، نتیجه همان چیزی است که در لحظه بسته شدنش به دست می‌آمد.
static int SwingsAt(const std::vector<MqlRates> &bars, int idx, int tf,
                    SwingAB *out, int maxOut)
{
   int total = idx + 1;
   int from  = total - ABCDHistoryBars;
   if(from < 0) from = 0;
   int n = total - from;

   static std::vector<MqlRates> win;
   win.assign(bars.begin() + from, bars.begin() + total);

   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += win[i].high - win[i].low;
   double avgRange = (n > 0) ? sum / n : 0.0;

   static SwingAB raw[8192];
   int nRaw = CollectSwings(win.data(), n, MinCandles, raw);

   static SwingAB act[8192];
   int nAct = BuildActiveSwings(win.data(), n, avgRange, raw, nRaw, act,
                                false, false, (ENUM_TIMEFRAMES)tf);

   if(nAct > maxOut) nAct = maxOut;
   for(int k = 0; k < nAct; k++) out[k] = act[k];

   // اندیس ها نسبت به پنجره اند؛ به اندیس مطلق آرایه اصلی تبدیل می‌شوند
   for(int k = 0; k < nAct; k++)
   {
      out[k].idxA       += from;
      out[k].idxADraw   += from;
      out[k].idxB       += from;
      out[k].idxZero    += from;
      if(out[k].idxC          >= 0) out[k].idxC          += from;
      if(out[k].idxBreakFrom  >= 0) out[k].idxBreakFrom  += from;
      if(out[k].idxBreakTo    >= 0) out[k].idxBreakTo    += from;
      if(out[k].idxHunt       >= 0) out[k].idxHunt       += from;
      if(out[k].idxSignal     >= 0) out[k].idxSignal     += from;
   }

   return nAct;
}

//--------------------------------------------------------------------------
// FVG داخل یک سویینگ AB — همان قاعده ای که اندیکاتور رسم می‌کند:
// سه کندلی، بین سقف کندل m-2 و کف کندل m (در لگ صعودی).
struct Fvg { int idx; double lo, hi; };

static int FvgsInSwing(const std::vector<MqlRates> &b, const SwingAB &s,
                       std::vector<Fvg> &out)
{
   out.clear();
   for(int m = s.idxA + 2; m <= s.idxB && m < (int)b.size(); m++)
   {
      if(s.isBull && b[m].low > b[m-2].high)
         out.push_back({m, b[m-2].high, b[m].low});
      else if(!s.isBull && b[m].high < b[m-2].low)
         out.push_back({m, b[m].high, b[m-2].low});
   }
   return (int)out.size();
}
