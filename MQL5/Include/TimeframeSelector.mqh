//+------------------------------------------------------------------+
//|                                          TimeframeSelector.mqh   |
//|   A chart button that opens a drop-down of MetaTrader 5          |
//|   timeframes and reports the one the user picks.                 |
//+------------------------------------------------------------------+
#property copyright "LumberRacer"
#property strict

//--- every standard MetaTrader 5 timeframe, in ascending order
const ENUM_TIMEFRAMES TCL_TIMEFRAMES[]=
  {
   PERIOD_M1,  PERIOD_M2,  PERIOD_M3,  PERIOD_M4,  PERIOD_M5,  PERIOD_M6,
   PERIOD_M10, PERIOD_M12, PERIOD_M15, PERIOD_M20, PERIOD_M30,
   PERIOD_H1,  PERIOD_H2,  PERIOD_H3,  PERIOD_H4,  PERIOD_H6,  PERIOD_H8,
   PERIOD_H12, PERIOD_D1,  PERIOD_W1,  PERIOD_MN1
  };

//+------------------------------------------------------------------+
//| "PERIOD_M30" -> "M30". PERIOD_CURRENT resolves to the chart's     |
//| own timeframe first, so the label never reads "CURRENT".          |
//+------------------------------------------------------------------+
string TCLTimeframeName(const ENUM_TIMEFRAMES tf)
  {
   ENUM_TIMEFRAMES resolved=(tf==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : tf);
   return(StringSubstr(EnumToString(resolved),7));
  }

//+------------------------------------------------------------------+
//| Result of feeding a chart event to a selector.                    |
//+------------------------------------------------------------------+
enum ENUM_TCL_CLICK
  {
   TCL_CLICK_NONE    = 0, // the event was not ours
   TCL_CLICK_TOGGLED = 1, // our menu was opened or closed
   TCL_CLICK_CHANGED = 2  // a timeframe was picked
  };

//+------------------------------------------------------------------+
//| CTimeframeSelector                                                |
//|                                                                   |
//| The drop-down is a grid of small buttons drawn under the main     |
//| button. Note on the menu closing itself the instant it opens: a   |
//| click on a button raises CHARTEVENT_OBJECT_CLICK, but the chart   |
//| also raises CHARTEVENT_CLICK for the same physical click, and a   |
//| naive "any chart click closes the menu" rule then closes the menu |
//| before it is ever seen. Two guards prevent that here: a chart     |
//| click is ignored for a short moment after the menu opens, and a   |
//| chart click landing inside the menu's own rectangle never closes  |
//| it. Picking an item, or clicking anywhere else, closes it.        |
//+------------------------------------------------------------------+
class CTimeframeSelector
  {
private:
   long              m_chart;
   int               m_subwindow;
   string            m_prefix;
   string            m_caption;
   ENUM_TIMEFRAMES   m_timeframe;

   int               m_x;
   int               m_y;
   int               m_width;
   int               m_height;

   int               m_columns;
   int               m_item_width;
   int               m_item_height;

   bool              m_open;
   ulong             m_opened_at;      // GetTickCount64() when the menu opened

   color             m_button_bg;
   color             m_button_fg;
   color             m_border;
   color             m_item_bg;
   color             m_item_fg;
   color             m_item_selected_bg;
   string            m_font;
   int               m_font_size;

   string            ButtonName(void)      const { return(m_prefix+"btn");     }
   string            MenuBackName(void)    const { return(m_prefix+"menu");    }
   string            ItemName(const int i) const { return(m_prefix+"item"+IntegerToString(i)); }

   int               ItemCount(void)  const { return(ArraySize(TCL_TIMEFRAMES)); }
   int               RowCount(void)   const { return((ItemCount()+m_columns-1)/m_columns); }
   //--- the menu opens to the right of the button so it never covers
   //--- the sibling buttons stacked underneath it
   int               MenuLeft(void)   const { return(m_x+m_width+2); }
   int               MenuTop(void)    const { return(m_y); }
   int               MenuWidth(void)  const { return(m_item_width*m_columns); }
   int               MenuHeight(void) const { return(m_item_height*RowCount()); }

   void              BuildButton(void);
   void              BuildMenu(void);
   void              RemoveMenu(void);
   void              StyleButtonObject(const string name,const int x,const int y,
                                       const int width,const int height,
                                       const string text,const color bg,const color fg);

public:
                     CTimeframeSelector(void);
                    ~CTimeframeSelector(void);

   void              Create(const long chart_id,const string prefix,const string caption,
                            const ENUM_TIMEFRAMES timeframe,
                            const int x,const int y,const int width,const int height);
   void              Destroy(void);

   void              SetColors(const color button_bg,const color button_fg,const color border,
                               const color item_bg,const color item_fg,const color item_selected_bg);
   void              SetFont(const string font,const int size) { m_font=font; m_font_size=size; }

   ENUM_TIMEFRAMES   Timeframe(void) const { return(m_timeframe); }
   void              SetTimeframe(const ENUM_TIMEFRAMES timeframe);
   string            Caption(void) const { return(m_caption); }

   bool              IsOpen(void) const { return(m_open); }
   void              OpenMenu(void);
   void              CloseMenu(void);

   ENUM_TCL_CLICK    OnObjectClick(const string object_name);
   void              OnChartClick(const int x,const int y);
  };

//+------------------------------------------------------------------+
CTimeframeSelector::CTimeframeSelector(void)
  {
   m_chart            = 0;
   m_subwindow        = 0;
   m_prefix           = "tfsel_";
   m_caption          = "TF";
   m_timeframe        = PERIOD_M30;
   m_x                = 10;
   m_y                = 20;
   m_width            = 150;
   m_height           = 22;
   m_columns          = 3;
   m_item_width       = 50;
   m_item_height      = 20;
   m_open             = false;
   m_opened_at        = 0;
   m_button_bg        = C'48,48,58';
   m_button_fg        = clrWhiteSmoke;
   m_border           = C'90,90,105';
   m_item_bg          = C'38,38,46';
   m_item_fg          = clrSilver;
   m_item_selected_bg = C'20,90,130';
   m_font             = "Tahoma";
   m_font_size        = 8;
  }

//+------------------------------------------------------------------+
CTimeframeSelector::~CTimeframeSelector(void)
  {
   Destroy();
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::SetColors(const color button_bg,const color button_fg,const color border,
                                   const color item_bg,const color item_fg,const color item_selected_bg)
  {
   m_button_bg        = button_bg;
   m_button_fg        = button_fg;
   m_border           = border;
   m_item_bg          = item_bg;
   m_item_fg          = item_fg;
   m_item_selected_bg = item_selected_bg;
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::Create(const long chart_id,const string prefix,const string caption,
                                const ENUM_TIMEFRAMES timeframe,
                                const int x,const int y,const int width,const int height)
  {
   m_chart     = chart_id;
   m_prefix    = prefix;
   m_caption   = caption;
   m_timeframe = (timeframe==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : timeframe);
   m_x         = x;
   m_y         = y;
   m_width     = width;
   m_height    = height;
   m_item_width= (int)MathMax(34,width/m_columns);
   m_open      = false;

   BuildButton();
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::Destroy(void)
  {
   ObjectsDeleteAll(m_chart,m_prefix,m_subwindow);
   m_open=false;
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::SetTimeframe(const ENUM_TIMEFRAMES timeframe)
  {
   m_timeframe=(timeframe==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : timeframe);
   BuildButton();
  }

//+------------------------------------------------------------------+
//| Creates or refreshes one button-shaped object.                    |
//+------------------------------------------------------------------+
void CTimeframeSelector::StyleButtonObject(const string name,const int x,const int y,
                                           const int width,const int height,
                                           const string text,const color bg,const color fg)
  {
   if(ObjectFind(m_chart,name)<0)
     {
      if(!ObjectCreate(m_chart,name,OBJ_BUTTON,m_subwindow,0,0))
         return;
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTED,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
     }
   ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(m_chart,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(m_chart,name,OBJPROP_YSIZE,height);
   ObjectSetString(m_chart,name,OBJPROP_TEXT,text);
   ObjectSetString(m_chart,name,OBJPROP_FONT,m_font);
   ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,m_font_size);
   ObjectSetInteger(m_chart,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(m_chart,name,OBJPROP_COLOR,fg);
   ObjectSetInteger(m_chart,name,OBJPROP_BORDER_COLOR,m_border);
   ObjectSetInteger(m_chart,name,OBJPROP_STATE,false);
   ObjectSetInteger(m_chart,name,OBJPROP_ZORDER,10);
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::BuildButton(void)
  {
   string text=m_caption+": "+TCLTimeframeName(m_timeframe);
   StyleButtonObject(ButtonName(),m_x,m_y,m_width,m_height,text,m_button_bg,m_button_fg);
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::BuildMenu(void)
  {
   //--- a plain background so the grid reads as one menu
   string back=MenuBackName();
   if(ObjectFind(m_chart,back)<0)
     {
      if(ObjectCreate(m_chart,back,OBJ_RECTANGLE_LABEL,m_subwindow,0,0))
        {
         ObjectSetInteger(m_chart,back,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart,back,OBJPROP_SELECTED,false);
         ObjectSetInteger(m_chart,back,OBJPROP_HIDDEN,true);
         ObjectSetInteger(m_chart,back,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart,back,OBJPROP_BORDER_TYPE,BORDER_FLAT);
        }
     }
   ObjectSetInteger(m_chart,back,OBJPROP_XDISTANCE,MenuLeft());
   ObjectSetInteger(m_chart,back,OBJPROP_YDISTANCE,MenuTop());
   ObjectSetInteger(m_chart,back,OBJPROP_XSIZE,MenuWidth());
   ObjectSetInteger(m_chart,back,OBJPROP_YSIZE,MenuHeight());
   ObjectSetInteger(m_chart,back,OBJPROP_BGCOLOR,m_item_bg);
   ObjectSetInteger(m_chart,back,OBJPROP_COLOR,m_border);
   ObjectSetInteger(m_chart,back,OBJPROP_ZORDER,9);

   int total=ItemCount();
   for(int i=0; i<total; i++)
     {
      int column=i%m_columns;
      int row   =i/m_columns;
      int x     =MenuLeft()+column*m_item_width;
      int y     =MenuTop()+row*m_item_height;

      bool selected=(TCL_TIMEFRAMES[i]==m_timeframe);
      StyleButtonObject(ItemName(i),x,y,m_item_width,m_item_height,
                        TCLTimeframeName(TCL_TIMEFRAMES[i]),
                        selected ? m_item_selected_bg : m_item_bg,
                        selected ? clrWhite : m_item_fg);
     }
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::RemoveMenu(void)
  {
   ObjectDelete(m_chart,MenuBackName());
   int total=ItemCount();
   for(int i=0; i<total; i++)
      ObjectDelete(m_chart,ItemName(i));
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::OpenMenu(void)
  {
   if(m_open)
      return;
   BuildMenu();
   m_open=true;
   m_opened_at=GetTickCount64();
  }

//+------------------------------------------------------------------+
void CTimeframeSelector::CloseMenu(void)
  {
   if(!m_open)
      return;
   RemoveMenu();
   m_open=false;
  }

//+------------------------------------------------------------------+
//| Handles CHARTEVENT_OBJECT_CLICK. Returns what the click did so    |
//| the caller can close sibling menus or trigger a rebuild.          |
//+------------------------------------------------------------------+
ENUM_TCL_CLICK CTimeframeSelector::OnObjectClick(const string object_name)
  {
   if(StringFind(object_name,m_prefix)!=0)
      return(TCL_CLICK_NONE);

   //--- MetaTrader leaves a clicked button latched down; release it
   ObjectSetInteger(m_chart,object_name,OBJPROP_STATE,false);

   if(object_name==ButtonName())
     {
      if(m_open)
         CloseMenu();
      else
         OpenMenu();
      return(TCL_CLICK_TOGGLED);
     }

   int total=ItemCount();
   for(int i=0; i<total; i++)
     {
      if(object_name!=ItemName(i))
         continue;

      CloseMenu();
      if(TCL_TIMEFRAMES[i]==m_timeframe)
         return(TCL_CLICK_TOGGLED);   // same timeframe: nothing to recompute

      m_timeframe=TCL_TIMEFRAMES[i];
      BuildButton();
      return(TCL_CLICK_CHANGED);
     }

   return(TCL_CLICK_NONE);
  }

//+------------------------------------------------------------------+
//| Handles CHARTEVENT_CLICK: closes the menu unless the click is the |
//| very one that opened it, or landed inside the menu itself.        |
//+------------------------------------------------------------------+
void CTimeframeSelector::OnChartClick(const int x,const int y)
  {
   if(!m_open)
      return;

   //--- the click that opened the menu reaches us twice; ignore the echo
   if(GetTickCount64()-m_opened_at<300)
      return;

   bool inside_menu = (x>=MenuLeft() && x<=MenuLeft()+MenuWidth() &&
                       y>=MenuTop() && y<=MenuTop()+MenuHeight());
   bool inside_button = (x>=m_x && x<=m_x+m_width &&
                         y>=m_y && y<=m_y+m_height);
   if(inside_menu || inside_button)
      return;

   CloseMenu();
  }
//+------------------------------------------------------------------+
