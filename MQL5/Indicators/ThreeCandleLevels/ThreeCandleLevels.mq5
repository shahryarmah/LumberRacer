//+------------------------------------------------------------------+
//|                                           ThreeCandleLevels.mq5  |
//|                                                                  |
//|  Draws horizontal levels derived from runs of exactly three       |
//|  same-direction candles, on three independent timeframes that are |
//|  picked from three drop-down buttons on the chart.                |
//|                                                                  |
//|  Pattern: three candles closing the same way, with the candle     |
//|  before them and the candle after them closing the other way, so  |
//|  the run is exactly three long. Only candle bodies are measured;  |
//|  wicks are ignored throughout. The bearish variant falls out of   |
//|  the bullish formulas for free, because they are written in terms |
//|  of the raw open/close rather than the top/bottom of the body.    |
//|                                                                  |
//|  Level geometry, with b1/b2/b3 the three body sizes:              |
//|    case 1  b2 largest   -> one line, midway between the open of   |
//|                            candle 2 and the middle of body 3      |
//|    case 2  b2 smallest  -> one line at the middle of body 2       |
//|    case 3  b1<b2<b3     -> line A midway between the middle of    |
//|                            body 1 and the close of candle 2,      |
//|                            line B midway between the middle of    |
//|                            body 2 and the close of candle 3,      |
//|                            plus a dashed line between A and B     |
//|    case 4  b1>b2>b3     -> line A midway between the open of      |
//|                            candle 1 and the middle of body 2,     |
//|                            line B midway between the open of      |
//|                            candle 2 and the middle of body 3,     |
//|                            plus a dashed line between A and B     |
//|                                                                  |
//|  The structure timeframe is scanned over the whole range. The     |
//|  trigger and double-trigger timeframes are scanned only inside    |
//|  the three candles of each confirmed structure pattern.           |
//+------------------------------------------------------------------+
#property copyright "LumberRacer"
#property version   "1.00"
#property description "Three-candle levels on three selectable timeframes"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- quoted includes resolve next to this file, so all four files live
//--- together in one folder and nothing has to go into MQL5\Include
#include "ChartPanel.mqh"
#include "ThreeCandlePattern.mqh"
#include "TimeframeSelector.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
enum ENUM_TCL_MODE
  {
   TCL_MODE_LIVE,    // Live - scan the last N structure bars
   TCL_MODE_BACKTEST // Backtest - scan a fixed date range
  };

input group "Scan range"
input ENUM_TCL_MODE InpMode      = TCL_MODE_LIVE;              // Mode
input int           InpLiveBars  = 20;                         // Live: last N bars of the structure timeframe
input datetime      InpFrom      = D'2025.01.01 00:00';        // Backtest: range start
input datetime      InpTo        = D'2025.12.31 23:59';        // Backtest: range end

input group "Timeframes (starting values; the buttons override them)"
input ENUM_TIMEFRAMES InpStructureTF = PERIOD_M30;             // Structure timeframe
input ENUM_TIMEFRAMES InpTriggerTF   = PERIOD_M12;             // Trigger timeframe
input ENUM_TIMEFRAMES InpDoubleTF    = PERIOD_M5;              // Double-trigger timeframe
input bool          InpResetSaved  = false;                    // Ignore the timeframes saved from the buttons

input group "Pattern"
input int  InpEqualTolerancePoints = 0;                        // Body-equality tolerance in points (0 = exact)
input bool InpStrictBoundary       = true;                     // Boundary candles must close strictly opposite
input int  InpExtendBars           = 20;                       // Extend levels N bars of their own timeframe

input group "Colours and style"
input color InpStructureColor = clrGold;                       // Structure levels
input color InpTriggerColor   = clrDeepSkyBlue;                // Trigger levels
input color InpDoubleColor    = clrMediumOrchid;               // Double-trigger levels
input int   InpLineWidth      = 2;                             // Level line width
input int   InpDashWidth      = 1;                             // Dashed midline width

input group "Buttons"
input int InpButtonX      = 10;                                // Buttons: X offset (from the top-left)
input int InpButtonY      = 22;                                // Buttons: Y offset
input int InpButtonWidth  = 150;                               // Buttons: width
input int InpButtonHeight = 22;                                // Buttons: height

input group "Info panel"
input bool             InpShowPanel   = true;                  // Show the info panel
input ENUM_BASE_CORNER InpPanelCorner = CORNER_RIGHT_UPPER;    // Panel corner
input int              InpPanelX      = 10;                    // Panel: X offset
input int              InpPanelY      = 22;                    // Panel: Y offset
input int              InpPanelWidth  = 235;                   // Panel: width

input group "Limits"
input int InpMaxLevelsPerTF = 500;                             // Safety cap on patterns per timeframe (0 = no cap)

//+------------------------------------------------------------------+
//| State                                                             |
//+------------------------------------------------------------------+
#define TCL_LEVEL_PREFIX  "TCL_lvl_"
#define TCL_PANEL_PREFIX  "TCL_pnl_"
#define TCL_RETRY_LIMIT   30

CChartPanel        g_panel;
CTimeframeSelector g_structure_button;
CTimeframeSelector g_trigger_button;
CTimeframeSelector g_double_button;

bool     g_rebuild_pending  = true;
bool     g_history_pending  = false;   // a timeframe had no history yet
int      g_retries          = 0;
datetime g_last_structure_bar = 0;

int      g_level_count[3];             // drawn solid levels per timeframe
int      g_pattern_count[3];           // confirmed patterns per timeframe
string   g_status            = "";
string   g_last_pattern_text = "-";

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ResolveTimeframe(const ENUM_TIMEFRAMES tf)
  {
   return(tf==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : tf);
  }

//--- the buttons remember their pick per chart, so it survives a chart
//--- timeframe change or a terminal restart
string SavedTimeframeName(const string key)
  {
   return("TCL_"+IntegerToString((long)ChartID())+"_"+key);
  }

bool IsKnownTimeframe(const int value)
  {
   int total=ArraySize(TCL_TIMEFRAMES);
   for(int i=0; i<total; i++)
      if((int)TCL_TIMEFRAMES[i]==value)
         return(true);
   return(false);
  }

ENUM_TIMEFRAMES LoadSavedTimeframe(const string key,const ENUM_TIMEFRAMES fallback)
  {
   string name=SavedTimeframeName(key);
   if(!InpResetSaved && GlobalVariableCheck(name))
     {
      int value=(int)GlobalVariableGet(name);
      if(IsKnownTimeframe(value))
         return((ENUM_TIMEFRAMES)value);
     }
   return(ResolveTimeframe(fallback));
  }

void SaveTimeframe(const string key,const ENUM_TIMEFRAMES tf)
  {
   GlobalVariableSet(SavedTimeframeName(key),(double)tf);
  }

void ForgetSavedTimeframes(void)
  {
   GlobalVariableDel(SavedTimeframeName("structure"));
   GlobalVariableDel(SavedTimeframeName("trigger"));
   GlobalVariableDel(SavedTimeframeName("double"));
  }

//+------------------------------------------------------------------+
//| Level drawing. Levels are trend-line objects with both ends at    |
//| the same price and fixed times, so they keep their position and   |
//| length when the chart timeframe is switched.                      |
//+------------------------------------------------------------------+
void DrawLevelLine(const string name,const datetime from,const datetime to,
                   const double price,const color clr,
                   const ENUM_LINE_STYLE style,const int width,const string tooltip)
  {
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_TREND,0,from,price,to,price))
         return;
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
     }
   ObjectMove(0,name,0,from,price);
   ObjectMove(0,name,1,to,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
  }

void DeleteAllLevels(void)
  {
   ObjectsDeleteAll(0,TCL_LEVEL_PREFIX,0,-1);
  }

//+------------------------------------------------------------------+
//| Draws every level of one timeframe group and returns how many     |
//| solid level lines were produced.                                  |
//+------------------------------------------------------------------+
int DrawPatterns(const STCLPattern &patterns[],const string tag,
                 const ENUM_TIMEFRAMES tf,const color clr)
  {
   int total=ArraySize(patterns);
   int drawn=0;
   string tf_name=TCLTimeframeName(tf);

   for(int i=0; i<total; i++)
     {
      string base=TCL_LEVEL_PREFIX+tag+"_"+IntegerToString(i)+"_";
      string tooltip=tag+" "+tf_name+"  |  "+
                     (patterns[i].direction>0 ? "bullish" : "bearish")+"  |  "+
                     TCLCaseToString(patterns[i].pattern_case)+"  |  "+
                     TimeToString(patterns[i].time_first,TIME_DATE|TIME_MINUTES);

      DrawLevelLine(base+"a",patterns[i].draw_from,patterns[i].draw_to,patterns[i].price_a,
                    clr,STYLE_SOLID,InpLineWidth,tooltip+"  (line A)");
      drawn++;

      if(patterns[i].line_count>1)
        {
         DrawLevelLine(base+"b",patterns[i].draw_from,patterns[i].draw_to,patterns[i].price_b,
                       clr,STYLE_SOLID,InpLineWidth,tooltip+"  (line B)");
         drawn++;
        }

      if(patterns[i].has_dash)
         DrawLevelLine(base+"m",patterns[i].draw_from,patterns[i].draw_to,patterns[i].price_dash,
                       clr,STYLE_DASH,InpDashWidth,tooltip+"  (midline)");
     }

   return(drawn);
  }

//+------------------------------------------------------------------+
//| Loads the structure bars and the window they define.              |
//| In live mode the window is the last InpLiveBars closed bars; in   |
//| backtest mode it is the configured date range.                    |
//+------------------------------------------------------------------+
bool LoadStructureRates(const ENUM_TIMEFRAMES tf,MqlRates &rates[],int &count,
                        datetime &window_from,datetime &window_to)
  {
   int period_seconds=PeriodSeconds(tf);
   if(period_seconds<=0)
      return(false);

   if(InpMode==TCL_MODE_BACKTEST)
     {
      count=TCLLoadRates(_Symbol,tf,InpFrom,InpTo,rates);
      if(count<5)
         return(false);
      window_from = InpFrom;
      window_to   = InpTo;
      return(true);
     }

   //--- live: a few bars beyond the window so the boundary candle of a
   //--- pattern starting on the first bar of the window is available
   int bars_wanted=(int)MathMax(5,InpLiveBars)+8;
   ArraySetAsSeries(rates,false);
   count=CopyRates(_Symbol,tf,0,bars_wanted,rates);
   if(count<=0)
      return(false);

   while(count>0 && (rates[count-1].time+period_seconds)>TimeCurrent())
      count--;
   if(count<5)
      return(false);

   int first=(int)MathMax(0,count-(int)MathMax(5,InpLiveBars));
   window_from = rates[first].time;
   window_to   = rates[count-1].time+period_seconds;
   return(true);
  }

//+------------------------------------------------------------------+
//| Scans one nested timeframe inside the three candles of every      |
//| confirmed structure pattern.                                      |
//+------------------------------------------------------------------+
bool ScanNested(const ENUM_TIMEFRAMES tf,const STCLPattern &structure_patterns[],
                const datetime window_from,const datetime window_to,
                const double tolerance,STCLPattern &result[])
  {
   int period_seconds=PeriodSeconds(tf);
   if(period_seconds<=0)
      return(false);

   MqlRates rates[];
   int count=TCLLoadRates(_Symbol,tf,window_from,window_to,rates);
   if(count<5)
      return(false);

   int total=ArraySize(structure_patterns);
   for(int i=0; i<total; i++)
     {
      datetime sub_from = structure_patterns[i].time_first;
      datetime sub_to   = structure_patterns[i].time_third+structure_patterns[i].period_seconds;

      TCLScan(rates,count,period_seconds,sub_from,sub_to,
              tolerance,InpStrictBoundary,InpExtendBars,InpMaxLevelsPerTF,result);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Panel                                                             |
//+------------------------------------------------------------------+
void UpdatePanel(void)
  {
   if(!InpShowPanel)
      return;

   g_panel.Clear();
   g_panel.AddHeader("THREE-CANDLE LEVELS",clrWhite);
   g_panel.AddSeparator();

   string mode_text = (InpMode==TCL_MODE_LIVE)
                      ? "Live - last "+IntegerToString((int)MathMax(5,InpLiveBars))+" bars"
                      : "Backtest";
   g_panel.AddRow("Mode",mode_text,clrSilver,clrWhiteSmoke);
   if(InpMode==TCL_MODE_BACKTEST)
     {
      g_panel.AddRow("From",TimeToString(InpFrom,TIME_DATE|TIME_MINUTES),clrSilver,clrWhiteSmoke);
      g_panel.AddRow("To",  TimeToString(InpTo,  TIME_DATE|TIME_MINUTES),clrSilver,clrWhiteSmoke);
     }
   g_panel.AddSeparator();

   g_panel.AddRow("Structure  "+TCLTimeframeName(g_structure_button.Timeframe()),
                  IntegerToString(g_pattern_count[0])+" pat / "+IntegerToString(g_level_count[0])+" lines",
                  InpStructureColor,InpStructureColor);
   g_panel.AddRow("Trigger  "+TCLTimeframeName(g_trigger_button.Timeframe()),
                  IntegerToString(g_pattern_count[1])+" pat / "+IntegerToString(g_level_count[1])+" lines",
                  InpTriggerColor,InpTriggerColor);
   g_panel.AddRow("Double  "+TCLTimeframeName(g_double_button.Timeframe()),
                  IntegerToString(g_pattern_count[2])+" pat / "+IntegerToString(g_level_count[2])+" lines",
                  InpDoubleColor,InpDoubleColor);

   g_panel.AddSeparator();
   g_panel.AddRow("Last structure",g_last_pattern_text,clrSilver,clrWhiteSmoke);
   g_panel.AddRow("Status",g_status,clrSilver,
                  (StringFind(g_status,"OK")==0 ? clrLimeGreen : clrOrange));

   g_panel.Redraw();
  }

//+------------------------------------------------------------------+
//| Full recomputation of all three timeframes.                       |
//+------------------------------------------------------------------+
void Rebuild(void)
  {
   g_rebuild_pending = false;
   g_history_pending = false;

   DeleteAllLevels();
   for(int i=0; i<3; i++)
     {
      g_level_count[i]   = 0;
      g_pattern_count[i] = 0;
     }
   g_last_pattern_text = "-";
   g_status            = "OK";

   ENUM_TIMEFRAMES tf_structure = g_structure_button.Timeframe();
   ENUM_TIMEFRAMES tf_trigger   = g_trigger_button.Timeframe();
   ENUM_TIMEFRAMES tf_double    = g_double_button.Timeframe();

   double tolerance=InpEqualTolerancePoints*_Point;

   MqlRates structure_rates[];
   int      structure_count=0;
   datetime window_from=0,window_to=0;

   if(!LoadStructureRates(tf_structure,structure_rates,structure_count,window_from,window_to))
     {
      g_status="waiting for "+TCLTimeframeName(tf_structure)+" history";
      g_history_pending=true;
      UpdatePanel();
      return;
     }

   STCLPattern structure_patterns[];
   ArrayResize(structure_patterns,0);
   TCLScan(structure_rates,structure_count,PeriodSeconds(tf_structure),
           window_from,window_to,tolerance,InpStrictBoundary,InpExtendBars,
           InpMaxLevelsPerTF,structure_patterns);

   g_pattern_count[0] = ArraySize(structure_patterns);
   g_level_count[0]   = DrawPatterns(structure_patterns,"s",tf_structure,InpStructureColor);

   if(g_pattern_count[0]>0)
     {
      int last=g_pattern_count[0]-1;
      g_last_pattern_text=TimeToString(structure_patterns[last].time_first,TIME_DATE|TIME_MINUTES)+
                          " "+(structure_patterns[last].direction>0 ? "up" : "down")+
                          " "+TCLCaseShort(structure_patterns[last].pattern_case);
     }

   //--- both nested timeframes are scanned inside the same window: the
   //--- three candles of each confirmed structure pattern
   if(g_pattern_count[0]>0)
     {
      STCLPattern trigger_patterns[];
      ArrayResize(trigger_patterns,0);
      if(ScanNested(tf_trigger,structure_patterns,window_from,window_to,tolerance,trigger_patterns))
        {
         g_pattern_count[1] = ArraySize(trigger_patterns);
         g_level_count[1]   = DrawPatterns(trigger_patterns,"t",tf_trigger,InpTriggerColor);
        }
      else
        {
         g_status="waiting for "+TCLTimeframeName(tf_trigger)+" history";
         g_history_pending=true;
        }

      STCLPattern double_patterns[];
      ArrayResize(double_patterns,0);
      if(ScanNested(tf_double,structure_patterns,window_from,window_to,tolerance,double_patterns))
        {
         g_pattern_count[2] = ArraySize(double_patterns);
         g_level_count[2]   = DrawPatterns(double_patterns,"d",tf_double,InpDoubleColor);
        }
      else
        {
         g_status="waiting for "+TCLTimeframeName(tf_double)+" history";
         g_history_pending=true;
        }
     }

   //--- a nested timeframe at or above the structure timeframe can never
   //--- fit three candles inside a structure pattern
   if(g_status=="OK")
     {
      if(PeriodSeconds(tf_trigger)>=PeriodSeconds(tf_structure))
         g_status="trigger TF is not below structure TF";
      else
         if(PeriodSeconds(tf_double)>=PeriodSeconds(tf_structure))
            g_status="double TF is not below structure TF";
     }

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if(InpMode==TCL_MODE_BACKTEST && InpFrom>=InpTo)
     {
      Print("ThreeCandleLevels: backtest range start must be earlier than its end");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpExtendBars<0)
     {
      Print("ThreeCandleLevels: the forward extension cannot be negative");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorSetString(INDICATOR_SHORTNAME,"ThreeCandleLevels");

   int spacing=InpButtonHeight+4;
   g_structure_button.Create(0,"TCL_b1_","Structure",
                             LoadSavedTimeframe("structure",InpStructureTF),
                             InpButtonX,InpButtonY,InpButtonWidth,InpButtonHeight);
   g_trigger_button.Create(0,"TCL_b2_","Trigger",
                           LoadSavedTimeframe("trigger",InpTriggerTF),
                           InpButtonX,InpButtonY+spacing,InpButtonWidth,InpButtonHeight);
   g_double_button.Create(0,"TCL_b3_","Double trigger",
                          LoadSavedTimeframe("double",InpDoubleTF),
                          InpButtonX,InpButtonY+2*spacing,InpButtonWidth,InpButtonHeight);

   g_structure_button.SetColors(C'58,50,24',clrGold,C'90,90,105',C'38,38,46',clrSilver,C'20,90,130');
   g_trigger_button.SetColors(C'24,48,60',clrDeepSkyBlue,C'90,90,105',C'38,38,46',clrSilver,C'20,90,130');
   g_double_button.SetColors(C'48,32,58',clrMediumOrchid,C'90,90,105',C'38,38,46',clrSilver,C'20,90,130');

   g_panel.SetPrefix(TCL_PANEL_PREFIX);
   g_panel.SetPosition(InpPanelCorner,InpPanelX,InpPanelY);
   g_panel.SetWidth(InpPanelWidth);

   g_rebuild_pending=true;
   g_retries=0;
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   g_structure_button.Destroy();
   g_trigger_button.Destroy();
   g_double_button.Destroy();
   g_panel.Destroy();
   DeleteAllLevels();

   //--- the saved picks are only meaningful while the indicator is on the
   //--- chart; a chart timeframe change or a recompile must keep them
   if(reason==REASON_REMOVE || reason==REASON_CHARTCLOSE)
      ForgetSavedTimeframes();

   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(g_rebuild_pending)
      Rebuild();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| The timer drives two things: picking up a freshly closed bar on   |
//| the structure timeframe, and retrying while a timeframe's history |
//| is still being downloaded.                                        |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   if(InpMode==TCL_MODE_LIVE)
     {
      datetime current=iTime(_Symbol,g_structure_button.Timeframe(),0);
      if(current>0 && current!=g_last_structure_bar)
        {
         g_last_structure_bar = current;
         g_rebuild_pending    = true;
         g_retries            = 0;
        }
     }

   if(g_history_pending && g_retries<TCL_RETRY_LIMIT)
     {
      g_retries++;
      g_rebuild_pending=true;
     }

   if(g_rebuild_pending)
      Rebuild();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      //--- find which of the three selectors the click belongs to
      int            owner  = -1;
      ENUM_TCL_CLICK result = g_structure_button.OnObjectClick(sparam);
      if(result!=TCL_CLICK_NONE)
         owner=0;
      else
        {
         result=g_trigger_button.OnObjectClick(sparam);
         if(result!=TCL_CLICK_NONE)
            owner=1;
         else
           {
            result=g_double_button.OnObjectClick(sparam);
            if(result!=TCL_CLICK_NONE)
               owner=2;
           }
        }
      if(owner<0)
         return;

      //--- only the selector that was clicked may keep its menu open
      if(owner!=0)
         g_structure_button.CloseMenu();
      if(owner!=1)
         g_trigger_button.CloseMenu();
      if(owner!=2)
         g_double_button.CloseMenu();

      if(result==TCL_CLICK_CHANGED)
        {
         if(owner==0)
            SaveTimeframe("structure",g_structure_button.Timeframe());
         else
            if(owner==1)
               SaveTimeframe("trigger",g_trigger_button.Timeframe());
            else
               SaveTimeframe("double",g_double_button.Timeframe());

         g_retries         = 0;
         g_rebuild_pending = true;
         Rebuild();
        }

      ChartRedraw();
      return;
     }

   if(id==CHARTEVENT_CLICK)
     {
      int x=(int)lparam;
      int y=(int)dparam;
      g_structure_button.OnChartClick(x,y);
      g_trigger_button.OnChartClick(x,y);
      g_double_button.OnChartClick(x,y);
      ChartRedraw();
      return;
     }

   if(id==CHARTEVENT_CHART_CHANGE)
      ChartRedraw();
  }
//+------------------------------------------------------------------+
