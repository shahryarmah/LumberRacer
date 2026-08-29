// Minimal MQL5 shim so ThreeCandlePattern.mqh can be compiled and tested
// with a host C++ compiler. Only the language and library pieces the
// pattern code actually touches are provided.
#pragma once
#include <cmath>
#include <string>
#include <vector>

typedef long long datetime;
typedef std::string string;

struct MqlRates
  {
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
  };

inline double MathAbs(double v) { return std::fabs(v); }

template<typename T> int ArraySize(const std::vector<T> &a) { return (int)a.size(); }
template<typename T> int ArrayResize(std::vector<T> &a, int n) { a.resize((size_t)n); return n; }
