// Tests for the three-candle level pattern: case classification, level
// geometry, the "exactly three same-direction candles" rule, the mirror
// symmetry between the bullish and bearish variants, and window filtering.
#include "ThreeCandlePattern.gen.h"

#include <cstdio>
#include <cstdlib>

static int g_failures = 0;

static void Check(bool ok, const std::string &what)
  {
   if(!ok)
     {
      std::printf("  FAIL  %s\n", what.c_str());
      g_failures++;
     }
   else
      std::printf("  ok    %s\n", what.c_str());
  }

static void CheckNear(double got, double want, const std::string &what)
  {
   bool ok = std::fabs(got - want) < 1e-9;
   if(!ok)
      std::printf("  FAIL  %s (got %.6f, want %.6f)\n", what.c_str(), got, want);
   else
      std::printf("  ok    %s = %.4f\n", what.c_str(), got);
   if(!ok)
      g_failures++;
  }

static const int PS = 60;   // one-minute bars in the fixtures

// Deliberately long, lopsided wicks: nothing in the pattern may depend on them.
static MqlRates Bar(int index, double open, double close)
  {
   MqlRates b;
   b.time  = (datetime)index * PS;
   b.open  = open;
   b.close = close;
   b.high  = (open > close ? open : close) + 37.0;
   b.low   = (open < close ? open : close) - 41.0;
   return b;
  }

// Reflects a series around a price axis: bullish candles become bearish and
// every affine level formula should map to the reflected price.
static std::vector<MqlRates> Mirror(const std::vector<MqlRates> &in, double axis)
  {
   std::vector<MqlRates> out;
   for(size_t i = 0; i < in.size(); i++)
     {
      MqlRates b = Bar((int)(in[i].time / PS), 2 * axis - in[i].open, 2 * axis - in[i].close);
      out.push_back(b);
     }
   return out;
  }

static std::vector<STCLPattern> Scan(const std::vector<MqlRates> &bars,
                                     datetime from = 0, datetime to = 1 << 30,
                                     bool strict = true, double tol = 0.0)
  {
   std::vector<STCLPattern> out;
   TCLScan(bars, (int)bars.size(), PS, from, to, tol, strict, 20, 0, out);
   return out;
  }

// c0 bearish, then three bullish candles with the given bodies, then c4 bearish.
static std::vector<MqlRates> Series(double o1, double c1, double o2, double c2,
                                    double o3, double c3)
  {
   std::vector<MqlRates> bars;
   bars.push_back(Bar(0, o1 + 5.0, o1));          // c0, bearish
   bars.push_back(Bar(1, o1, c1));
   bars.push_back(Bar(2, o2, c2));
   bars.push_back(Bar(3, o3, c3));
   bars.push_back(Bar(4, c3, c3 - 10.0));         // c4, bearish
   return bars;
  }

int main()
  {
   //--- case 1: middle body largest (bodies 10, 30, 20)
   std::printf("case 1 - middle body largest\n");
     {
      std::vector<MqlRates> bars = Series(95, 105, 104, 134, 130, 150);
      std::vector<STCLPattern> p = Scan(bars);
      Check(p.size() == 1, "one pattern found");
      if(p.size() == 1)
        {
         Check(p[0].pattern_case == TCL_CASE_MIDDLE_LARGEST, "classified as case 1");
         Check(p[0].direction == 1, "bullish");
         Check(p[0].line_count == 1 && !p[0].has_dash, "one line, no midline");
         CheckNear(p[0].price_a, 122.0, "level");
         Check(p[0].draw_to == bars[4].time + 20 * PS, "extends 20 bars past the confirmation");
        }
     }

   //--- case 2: middle body smallest (bodies 30, 10, 20)
   std::printf("case 2 - middle body smallest\n");
     {
      std::vector<STCLPattern> p = Scan(Series(95, 125, 120, 130, 128, 148));
      Check(p.size() == 1, "one pattern found");
      if(p.size() == 1)
        {
         Check(p[0].pattern_case == TCL_CASE_MIDDLE_SMALLEST, "classified as case 2");
         Check(p[0].line_count == 1 && !p[0].has_dash, "one line, no midline");
         CheckNear(p[0].price_a, 125.0, "level");
        }
     }

   //--- case 3: ascending bodies (10, 20, 30)
   std::printf("case 3 - ascending bodies\n");
     {
      std::vector<STCLPattern> p = Scan(Series(95, 105, 104, 124, 120, 150));
      Check(p.size() == 1, "one pattern found");
      if(p.size() == 1)
        {
         Check(p[0].pattern_case == TCL_CASE_ASCENDING, "classified as case 3");
         Check(p[0].line_count == 2 && p[0].has_dash, "two lines plus midline");
         CheckNear(p[0].price_a, 112.0, "line A");
         CheckNear(p[0].price_b, 132.0, "line B");
         CheckNear(p[0].price_dash, 122.0, "dashed midline");
        }
     }

   //--- case 4: descending bodies (30, 20, 10)
   std::printf("case 4 - descending bodies\n");
     {
      std::vector<STCLPattern> p = Scan(Series(95, 125, 120, 140, 138, 148));
      Check(p.size() == 1, "one pattern found");
      if(p.size() == 1)
        {
         Check(p[0].pattern_case == TCL_CASE_DESCENDING, "classified as case 4");
         Check(p[0].line_count == 2 && p[0].has_dash, "two lines plus midline");
         CheckNear(p[0].price_a, 112.5, "line A");
         CheckNear(p[0].price_b, 131.5, "line B");
         CheckNear(p[0].price_dash, 122.0, "dashed midline");
        }
     }

   //--- the bearish variant must be the exact mirror of the bullish one
   std::printf("mirror symmetry - bearish is the reflection of bullish\n");
     {
      const double axis = 200.0;
      std::vector<MqlRates> bull = Series(95, 105, 104, 124, 120, 150);   // case 3
      std::vector<STCLPattern> pb = Scan(bull);
      std::vector<STCLPattern> pm = Scan(Mirror(bull, axis));
      Check(pb.size() == 1 && pm.size() == 1, "both directions found");
      if(pb.size() == 1 && pm.size() == 1)
        {
         Check(pm[0].direction == -1, "mirrored series is bearish");
         Check(pm[0].pattern_case == pb[0].pattern_case, "same case on both sides");
         CheckNear(pm[0].price_a, 2 * axis - pb[0].price_a, "line A reflects");
         CheckNear(pm[0].price_b, 2 * axis - pb[0].price_b, "line B reflects");
         CheckNear(pm[0].price_dash, 2 * axis - pb[0].price_dash, "midline reflects");
        }
     }

   //--- exactly three: a fourth same-direction candle disqualifies the run
   std::printf("run length - the run must be exactly three candles\n");
     {
      std::vector<MqlRates> bars;
      bars.push_back(Bar(0, 100, 95));       // bearish
      bars.push_back(Bar(1, 95, 105));
      bars.push_back(Bar(2, 104, 134));
      bars.push_back(Bar(3, 130, 150));
      bars.push_back(Bar(4, 148, 158));      // a fourth bullish candle
      bars.push_back(Bar(5, 158, 150));      // bearish
      bars.push_back(Bar(6, 150, 140));
      Check(Scan(bars).empty(), "four bullish candles produce no pattern");
     }
     {
      std::vector<MqlRates> bars;
      bars.push_back(Bar(0, 90, 95));        // bullish candle before the run
      bars.push_back(Bar(1, 95, 105));
      bars.push_back(Bar(2, 104, 134));
      bars.push_back(Bar(3, 130, 150));
      bars.push_back(Bar(4, 150, 140));      // bearish
      Check(Scan(bars).empty(), "a same-direction candle before the run disqualifies it");
     }

   //--- a doji boundary: strict mode rejects it, relaxed mode accepts it
   std::printf("doji boundary\n");
     {
      std::vector<MqlRates> bars;
      bars.push_back(Bar(0, 95, 95));        // doji before the run
      bars.push_back(Bar(1, 95, 105));
      bars.push_back(Bar(2, 104, 134));
      bars.push_back(Bar(3, 130, 150));
      bars.push_back(Bar(4, 150, 140));      // bearish
      Check(Scan(bars, 0, 1 << 30, true).empty(), "strict mode rejects a doji boundary");
      Check(Scan(bars, 0, 1 << 30, false).size() == 1, "relaxed mode accepts it");
     }

   //--- equal bodies match no case
   std::printf("equal bodies\n");
     {
      std::vector<STCLPattern> p = Scan(Series(95, 105, 104, 114, 120, 130));  // 10, 10, 10
      Check(p.empty(), "three equal bodies produce no level");
     }
     {
      // bodies 10, 10.4, 30: within a 0.5 tolerance b1 and b2 compare equal
      std::vector<STCLPattern> p = Scan(Series(95, 105, 104, 114.4, 120, 150), 0, 1 << 30, true, 0.5);
      Check(p.empty(), "bodies inside the tolerance are treated as equal");
      std::vector<STCLPattern> q = Scan(Series(95, 105, 104, 114.4, 120, 150), 0, 1 << 30, true, 0.0);
      Check(q.size() == 1 && q[0].pattern_case == TCL_CASE_ASCENDING,
            "without tolerance the same bodies are ascending");
     }

   //--- window filtering
   std::printf("window filtering\n");
     {
      std::vector<MqlRates> bars = Series(95, 105, 104, 134, 130, 150);
      Check(Scan(bars, 2 * PS, 1 << 30).empty(), "pattern starting before the window is skipped");
      Check(Scan(bars, 0, 3 * PS).empty(), "pattern ending after the window is skipped");
      Check(Scan(bars, PS, 4 * PS).size() == 1, "pattern exactly inside the window is kept");
     }

   std::printf("\n%s\n", g_failures == 0 ? "all checks passed" : "THERE WERE FAILURES");
   return g_failures == 0 ? 0 : 1;
  }
