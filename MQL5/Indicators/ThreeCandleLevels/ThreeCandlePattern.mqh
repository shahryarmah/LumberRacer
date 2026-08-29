//+------------------------------------------------------------------+
//|                                          ThreeCandlePattern.mqh  |
//|   Detection of the three-candle level pattern and the geometry   |
//|   of the levels it produces.                                     |
//+------------------------------------------------------------------+
#property copyright "LumberRacer"
#property strict

//+------------------------------------------------------------------+
//| Which of the four body-size arrangements a pattern falls into.    |
//| The four cases cover every ordering of three distinct bodies, so  |
//| a pattern is only rejected when two bodies compare equal.         |
//+------------------------------------------------------------------+
enum ENUM_TCL_CASE
  {
   TCL_CASE_NONE            = 0, // no case (two bodies compared equal)
   TCL_CASE_MIDDLE_LARGEST  = 1, // b2 > b1 and b2 > b3
   TCL_CASE_MIDDLE_SMALLEST = 2, // b2 < b1 and b2 < b3
   TCL_CASE_ASCENDING       = 3, // b1 < b2 < b3
   TCL_CASE_DESCENDING      = 4  // b1 > b2 > b3
  };

//+------------------------------------------------------------------+
//| One confirmed pattern together with the levels it produces.       |
//| Cases 1 and 2 fill price_a only; cases 3 and 4 fill price_a,      |
//| price_b and the dashed midline between them.                      |
//+------------------------------------------------------------------+
struct STCLPattern
  {
   datetime          time_first;      // open time of candle 1
   datetime          time_third;      // open time of candle 3
   datetime          time_confirm;    // open time of candle 4 (the opposite one)
   int               direction;       // +1 bullish, -1 bearish
   ENUM_TCL_CASE     pattern_case;
   double            price_a;
   double            price_b;
   double            price_dash;
   int               line_count;      // 1 for cases 1-2, 2 for cases 3-4
   bool              has_dash;
   datetime          draw_from;       // left end of the drawn lines
   datetime          draw_to;         // right end of the drawn lines
   int               period_seconds;  // seconds per bar of the detecting timeframe
  };

//+------------------------------------------------------------------+
//| Body helpers. Every measurement in this pattern uses the body     |
//| only, so open/close are read directly and the wicks ignored.      |
//|                                                                   |
//| Using the raw open/close (rather than "top"/"bottom" of the body) |
//| is what makes the bearish variant the mirror image of the bullish |
//| one for free: in a bullish candle the open is the bottom of the   |
//| body, in a bearish candle it is the top.                          |
//+------------------------------------------------------------------+
int TCLDirection(const MqlRates &bar)
  {
   if(bar.close>bar.open)
      return(1);
   if(bar.close<bar.open)
      return(-1);
   return(0);
  }

double TCLBodySize(const MqlRates &bar)
  {
   return(MathAbs(bar.close-bar.open));
  }

double TCLBodyMid(const MqlRates &bar)
  {
   return((bar.open+bar.close)*0.5);
  }

//+------------------------------------------------------------------+
//| Three-way comparison with a tolerance: returns 0 when the two     |
//| values are within 'tolerance' of each other.                      |
//+------------------------------------------------------------------+
int TCLCompare(const double a,const double b,const double tolerance)
  {
   if(MathAbs(a-b)<=tolerance)
      return(0);
   return(a>b ? 1 : -1);
  }

//+------------------------------------------------------------------+
//| Classifies the three bodies into one of the four cases.           |
//+------------------------------------------------------------------+
ENUM_TCL_CASE TCLClassify(const double b1,const double b2,const double b3,const double tolerance)
  {
   int c21=TCLCompare(b2,b1,tolerance);
   int c23=TCLCompare(b2,b3,tolerance);

   if(c21>0 && c23>0)
      return(TCL_CASE_MIDDLE_LARGEST);
   if(c21<0 && c23<0)
      return(TCL_CASE_MIDDLE_SMALLEST);
   if(c21>0 && c23<0)
      return(TCL_CASE_ASCENDING);    // b1 < b2 < b3
   if(c21<0 && c23>0)
      return(TCL_CASE_DESCENDING);   // b1 > b2 > b3

   return(TCL_CASE_NONE);            // at least one pair compared equal
  }

//+------------------------------------------------------------------+
//| Fills in the level prices for a classified pattern.               |
//+------------------------------------------------------------------+
void TCLLevelPrices(const ENUM_TCL_CASE pattern_case,
                    const MqlRates &c1,const MqlRates &c2,const MqlRates &c3,
                    STCLPattern &out)
  {
   double mid1=TCLBodyMid(c1);
   double mid2=TCLBodyMid(c2);
   double mid3=TCLBodyMid(c3);

   out.price_a    = 0.0;
   out.price_b    = 0.0;
   out.price_dash = 0.0;
   out.has_dash   = false;
   out.line_count = 0;

   switch(pattern_case)
     {
      //--- middle body is the largest: midpoint of [open of c2 .. mid of body 3]
      case TCL_CASE_MIDDLE_LARGEST:
         out.price_a    = (c2.open+mid3)*0.5;
         out.line_count = 1;
         break;

      //--- middle body is the smallest: the middle of body 2 itself
      case TCL_CASE_MIDDLE_SMALLEST:
         out.price_a    = mid2;
         out.line_count = 1;
         break;

      //--- bodies grow: [mid of body 1 .. close of c2] and [mid of body 2 .. close of c3]
      case TCL_CASE_ASCENDING:
         out.price_a    = (mid1+c2.close)*0.5;
         out.price_b    = (mid2+c3.close)*0.5;
         out.price_dash = (out.price_a+out.price_b)*0.5;
         out.line_count = 2;
         out.has_dash   = true;
         break;

      //--- bodies shrink: [open of c1 .. mid of body 2] and [open of c2 .. mid of body 3]
      case TCL_CASE_DESCENDING:
         out.price_a    = (c1.open+mid2)*0.5;
         out.price_b    = (c2.open+mid3)*0.5;
         out.price_dash = (out.price_a+out.price_b)*0.5;
         out.line_count = 2;
         out.has_dash   = true;
         break;

      default:
         break;
     }
  }

//+------------------------------------------------------------------+
//| Loads the bars of 'tf' covering [from, to], with a few extra bars |
//| on each side so the boundary candles of a pattern sitting at the  |
//| very edge of the window are available too.                        |
//|                                                                   |
//| The still-forming bar is dropped: a pattern is only confirmed on  |
//| closed candles.                                                   |
//|                                                                   |
//| Returns the bar count, or -1 when the history is not ready yet.   |
//+------------------------------------------------------------------+
int TCLLoadRates(const string symbol,const ENUM_TIMEFRAMES tf,
                 const datetime from,const datetime to,MqlRates &rates[])
  {
   int period_seconds=PeriodSeconds(tf);
   if(period_seconds<=0)
      return(-1);

   datetime load_from=from-5*period_seconds;
   datetime load_to  =to  +5*period_seconds;

   ArraySetAsSeries(rates,false);
   int count=CopyRates(symbol,tf,load_from,load_to,rates);
   if(count<=0)
      return(-1);

   //--- drop the bar that is still being built
   while(count>0 && (rates[count-1].time+period_seconds)>TimeCurrent())
      count--;

   return(count);
  }

//+------------------------------------------------------------------+
//| Scans 'rates' for confirmed patterns whose three main candles lie |
//| inside [win_from, win_to) and appends them to 'result'.           |
//|                                                                   |
//| A pattern is exactly three same-direction candles: the candle     |
//| before the first one and the candle after the third one must both |
//| close against that direction, otherwise the run is longer than    |
//| three and is not our pattern.                                     |
//|                                                                   |
//| Returns how many patterns were appended.                          |
//+------------------------------------------------------------------+
int TCLScan(const MqlRates &rates[],const int count,const int period_seconds,
            const datetime win_from,const datetime win_to,
            const double tolerance,const bool strict_boundary,
            const int extend_bars,const int max_patterns,
            STCLPattern &result[])
  {
   int appended=0;

   for(int i=1; i<=count-4; i++)
     {
      //--- the three main candles must sit inside the requested window;
      //--- times ascend, so once we are past it nothing else can fit
      if(rates[i].time<win_from)
         continue;
      if((rates[i+2].time+period_seconds)>win_to)
         break;

      //--- c0 = rates[i-1] is the candle before the pattern,
      //--- c1..c3 the three same-direction candles, c4 the confirmation
      int dir=TCLDirection(rates[i]);
      if(dir==0)
         continue;
      if(TCLDirection(rates[i+1])!=dir || TCLDirection(rates[i+2])!=dir)
         continue;

      int dir_before=TCLDirection(rates[i-1]);
      int dir_after =TCLDirection(rates[i+3]);
      if(strict_boundary)
        {
         if(dir_before!=-dir || dir_after!=-dir)
            continue;
        }
      else
        {
         //--- relaxed: a doji on either side still leaves a run of exactly three
         if(dir_before==dir || dir_after==dir)
            continue;
        }

      double b1=TCLBodySize(rates[i]);
      double b2=TCLBodySize(rates[i+1]);
      double b3=TCLBodySize(rates[i+2]);

      ENUM_TCL_CASE pattern_case=TCLClassify(b1,b2,b3,tolerance);
      if(pattern_case==TCL_CASE_NONE)
         continue;

      if(max_patterns>0 && ArraySize(result)>=max_patterns)
         break;

      STCLPattern pattern;
      pattern.time_first     = rates[i].time;
      pattern.time_third     = rates[i+2].time;
      pattern.time_confirm   = rates[i+3].time;
      pattern.direction      = dir;
      pattern.pattern_case   = pattern_case;
      pattern.period_seconds = period_seconds;
      TCLLevelPrices(pattern_case,rates[i],rates[i+1],rates[i+2],pattern);

      //--- the lines span the pattern itself and run on for 'extend_bars'
      //--- bars of the timeframe the pattern was found on
      pattern.draw_from = rates[i].time;
      pattern.draw_to   = rates[i+3].time+extend_bars*period_seconds;

      int index=ArraySize(result);
      ArrayResize(result,index+1);
      result[index]=pattern;
      appended++;
     }

   return(appended);
  }

//+------------------------------------------------------------------+
//| Short human-readable names, used for tooltips and the panel.      |
//+------------------------------------------------------------------+
string TCLCaseToString(const ENUM_TCL_CASE pattern_case)
  {
   switch(pattern_case)
     {
      case TCL_CASE_MIDDLE_LARGEST:  return("C1 middle largest");
      case TCL_CASE_MIDDLE_SMALLEST: return("C2 middle smallest");
      case TCL_CASE_ASCENDING:       return("C3 ascending");
      case TCL_CASE_DESCENDING:      return("C4 descending");
      default:                       return("-");
     }
  }

string TCLCaseShort(const ENUM_TCL_CASE pattern_case)
  {
   switch(pattern_case)
     {
      case TCL_CASE_MIDDLE_LARGEST:  return("C1");
      case TCL_CASE_MIDDLE_SMALLEST: return("C2");
      case TCL_CASE_ASCENDING:       return("C3");
      case TCL_CASE_DESCENDING:      return("C4");
      default:                       return("-");
     }
  }
//+------------------------------------------------------------------+
