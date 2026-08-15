// شیم بررسی نحوی فایل های .mq5 با ++g. این کامپایل واقعی MQL5 نیست و
// خطاهای مخصوص متاتریدر را نمی‌گیرد؛ فقط اشتباه تایپی، متغیر تعریف نشده و
// آکولاد جا افتاده را پیدا می‌کند. خطای این شیم باید در همین فایل رفع شود،
// نه در سورس MQL5 — مگر اینکه واقعا باگ باشد. (LESSONS.md بند ۵)
#pragma once
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <string>

typedef std::string        string;
typedef long long          datetime;
typedef int                color;
// glibc خودش uint و ulong را typedef کرده؛ ماکرو به جای typedef تا تداخل نکند
#define uint  unsigned int
#define ulong unsigned long long

// مقادیر واقعی متاتریدر، تا مقایسه عددی «بالاتر/پایین تر» تایم فریم ها که
// کد به آن تکیه دارد در شیم هم همان معنا را بدهد.
enum
{
   PERIOD_CURRENT = 0,
   PERIOD_M1 = 1,     PERIOD_M2 = 2,     PERIOD_M3 = 3,     PERIOD_M4 = 4,
   PERIOD_M5 = 5,     PERIOD_M6 = 6,     PERIOD_M10 = 10,   PERIOD_M12 = 12,
   PERIOD_M15 = 15,   PERIOD_M20 = 20,   PERIOD_M30 = 30,
   PERIOD_H1 = 16385, PERIOD_H2 = 16386, PERIOD_H3 = 16387, PERIOD_H4 = 16388,
   PERIOD_H6 = 16390, PERIOD_H8 = 16392, PERIOD_H12 = 16396,
   PERIOD_D1 = 16408
};

struct MqlRates
{
   datetime time;
   double   open, high, low, close;
   long     tick_volume, real_volume;
   int      spread;
};

struct MqlDateTime
{
   int year, mon, day, hour, min, sec, day_of_week, day_of_year;
};

static string _Symbol = "TEST";
static int    _Period = PERIOD_H4;
static int    _Digits = 5;

template<typename T> T MathAbs(T v) { return v < 0 ? -v : v; }
template<typename T> T MathMin(T a, T b) { return a < b ? a : b; }
template<typename T> T MathMax(T a, T b) { return a > b ? a : b; }

template<typename T, std::size_t N> int ArraySize(T (&)[N]) { return (int)N; }
template<typename T> int  ArrayResize(T *, int size, int = 0) { return size; }
template<typename T> bool ArraySetAsSeries(T *, bool) { return true; }

static string IntegerToString(long long v, int = 0, int = 0) { return std::to_string(v); }
static string DoubleToString(double v, int = 8) { return std::to_string(v); }
template<typename... A> string StringFormat(const char *f, A...) { return string(f); }

static int StringLen(const string &s)            { return (int)s.size(); }
static int StringFind(const string &s, const string &sub, int from = 0)
{
   auto p = s.find(sub, from);
   return p == std::string::npos ? -1 : (int)p;
}
static string StringSubstr(const string &s, int from, int len = -1)
{
   if(from >= (int)s.size()) return "";
   return len < 0 ? s.substr(from) : s.substr(from, len);
}
static long StringToInteger(const string &s) { return atoll(s.c_str()); }
static void StringTrimLeft(string &)  {}
static void StringTrimRight(string &) {}
static void StringToUpper(string &)   {}
template<typename T> int StringSplit(const string &, unsigned short, T *) { return 0; }

// آبجکت ها و چارت — فقط امضا، بدون رفتار
template<typename... A> bool   ObjectCreate(A...)      { return true; }
template<typename... A> bool   ObjectDelete(A...)      { return true; }
template<typename... A> int    ObjectFind(A...)        { return -1; }
template<typename... A> bool   ObjectSetInteger(A...)  { return true; }
template<typename... A> bool   ObjectSetString(A...)   { return true; }
template<typename... A> string ObjectGetString(A...)   { return ""; }
template<typename... A> long   ObjectGetInteger(A...)  { return 0; }
static int    ObjectsTotal(long, int = -1, int = -1)   { return 0; }
static string ObjectName(long, int, int = -1, int = -1){ return ""; }

static void ChartRedraw(long = 0) {}
static long ChartID()             { return 0; }
static long ChartFirst()          { return -1; }
static long ChartNext(long)       { return -1; }
static string ChartSymbol(long = 0) { return ""; }
template<typename... A> long ChartGetInteger(A...) { return 0; }
template<typename... A> bool ChartSetSymbolPeriod(A...) { return true; }
template<typename... A> long ChartOpen(A...) { return 0; }

static int      Period() { return _Period; }
static int      PeriodSeconds(int tf) { return tf; }
static datetime iTime(const string &, int, int) { return 0; }
static datetime TimeCurrent() { return 0; }
static datetime TimeLocal()   { return 0; }
static datetime TimeGMT()     { return 0; }
static void     TimeToStruct(datetime, MqlDateTime &d) { memset(&d, 0, sizeof(d)); }
static ulong    GetMicrosecondCount() { return 0; }

enum { TIME_DATE = 1, TIME_MINUTES = 2, TIME_SECONDS = 4 };
static string TimeToString(datetime, int = 0) { return ""; }

static bool EventSetTimer(int) { return true; }
static void EventKillTimer()   {}
template<typename... A> void Alert(A...) {}
template<typename... A> void Print(A...) {}
static bool SendNotification(const string &) { return true; }

static int  Bars(const string &, int) { return 0; }
template<typename T> int CopyRates(const string &, int, int, int, T *) { return 0; }

// فایل — برای اسکریپت استخراج تاریخچه (ExportRates.mq5)
enum { INVALID_HANDLE = -1, FILE_WRITE = 2, FILE_READ = 1, FILE_CSV = 8,
       FILE_ANSI = 32, FILE_COMMON = 4096 };
static int  FileOpen(const string &, int, unsigned short = 0) { return -1; }
template<typename... A> unsigned int FileWrite(int, A...) { return 0; }
static void FileClose(int) {}
static int  GetLastError() { return 0; }
static long SymbolInfoInteger(const string &, int) { return 0; }
enum { SYMBOL_DIGITS = 0 };

static int    SymbolsTotal(bool)           { return 0; }
static string SymbolName(int, bool)        { return ""; }
static bool   SymbolSelect(const string &, bool) { return true; }

static int    PositionsTotal()                    { return 0; }
static string PositionGetSymbol(int)              { return ""; }
static long   PositionGetInteger(int)             { return 0; }
static double PositionGetDouble(int)              { return 0.0; }

static int    GlobalVariablesTotal()              { return 0; }
static string GlobalVariableName(int)             { return ""; }
static double GlobalVariableGet(const string &)   { return 0.0; }
static bool   GlobalVariableDel(const string &)   { return true; }
static bool   GlobalVariableSet(const string &, double) { return true; }
static bool   GlobalVariableCheck(const string &) { return false; }
