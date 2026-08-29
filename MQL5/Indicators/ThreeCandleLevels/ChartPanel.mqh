//+------------------------------------------------------------------+
//|                                                   ChartPanel.mqh |
//|                    Reusable on-chart information panel for MT5    |
//+------------------------------------------------------------------+
#property copyright "LumberRacer"
#property strict

//+------------------------------------------------------------------+
//| A single row of the panel: a caption on the left and a value on   |
//| the right, each with its own colour.                              |
//+------------------------------------------------------------------+
struct SPanelRow
  {
   string            caption;
   string            value;
   color             caption_color;
   color             value_color;
   bool              is_header;   // header rows span the full width
  };

//+------------------------------------------------------------------+
//| CChartPanel                                                       |
//|                                                                   |
//| Draws a rectangle-label background with a stack of text rows on   |
//| top of it. Rows are filled in with SetRow()/AddRow() and pushed   |
//| to the chart with Redraw(). All four chart corners are supported; |
//| positions are computed in panel-local coordinates (x to the       |
//| right, y downwards from the panel's top-left) and translated to   |
//| the corner-relative distances MetaTrader expects.                 |
//+------------------------------------------------------------------+
class CChartPanel
  {
private:
   long              m_chart;
   string            m_prefix;
   int               m_subwindow;

   ENUM_BASE_CORNER  m_corner;
   int               m_x;              // offset of the panel from the corner
   int               m_y;
   int               m_width;
   int               m_height;         // recomputed from the row count

   int               m_padding;
   int               m_row_height;
   int               m_font_size;
   string            m_font;

   color             m_bg_color;
   color             m_border_color;

   SPanelRow         m_rows[];
   int               m_drawn_rows;     // labels currently on the chart

   bool              IsRightCorner(void) const
     { return(m_corner==CORNER_RIGHT_UPPER || m_corner==CORNER_RIGHT_LOWER); }
   bool              IsLowerCorner(void) const
     { return(m_corner==CORNER_LEFT_LOWER || m_corner==CORNER_RIGHT_LOWER); }

   string            RowName(const int index,const bool value_part) const
     { return(m_prefix+(value_part ? "val_" : "cap_")+IntegerToString(index)); }
   string            BackgroundName(void) const
     { return(m_prefix+"bg"); }

   void              Place(const string name,const int lx,const int ly,const bool right_aligned);
   bool              EnsureLabel(const string name);
   void              ApplyBackground(void);
   void              RemoveExtraLabels(const int keep_rows);

public:
                     CChartPanel(void);
                    ~CChartPanel(void);

   //--- configuration; call before Redraw()
   void              SetPrefix(const string prefix)          { m_prefix=prefix;         }
   void              SetChart(const long chart_id)           { m_chart=chart_id;        }
   void              SetSubwindow(const int subwindow)       { m_subwindow=subwindow;   }
   void              SetPosition(const ENUM_BASE_CORNER corner,const int x,const int y)
     { m_corner=corner; m_x=x; m_y=y; }
   void              SetWidth(const int width)               { m_width=width;           }
   void              SetRowHeight(const int height)          { m_row_height=height;     }
   void              SetPadding(const int padding)           { m_padding=padding;       }
   void              SetFont(const string font,const int size) { m_font=font; m_font_size=size; }
   void              SetColors(const color background,const color border)
     { m_bg_color=background; m_border_color=border; }

   //--- content
   void              Clear(void)                             { ArrayResize(m_rows,0);   }
   int               RowCount(void) const                    { return(ArraySize(m_rows)); }
   int               AddRow(const string caption,const string value,
                            const color caption_color,const color value_color);
   int               AddHeader(const string caption,const color text_color);
   int               AddSeparator(void);
   bool              SetRow(const int index,const string caption,const string value,
                            const color caption_color,const color value_color);

   //--- output
   void              Redraw(void);
   void              Destroy(void);
  };

//+------------------------------------------------------------------+
//| Constructor: sensible defaults so a caller only has to set what   |
//| it actually cares about.                                          |
//+------------------------------------------------------------------+
CChartPanel::CChartPanel(void)
  {
   m_chart        = 0;
   m_prefix       = "panel_";
   m_subwindow    = 0;
   m_corner       = CORNER_LEFT_UPPER;
   m_x            = 10;
   m_y            = 20;
   m_width        = 210;
   m_height       = 0;
   m_padding      = 8;
   m_row_height   = 16;
   m_font_size    = 9;
   m_font         = "Tahoma";
   m_bg_color     = C'32,32,38';
   m_border_color = C'70,70,80';
   m_drawn_rows   = 0;
   ArrayResize(m_rows,0);
  }

//+------------------------------------------------------------------+
CChartPanel::~CChartPanel(void)
  {
   Destroy();
  }

//+------------------------------------------------------------------+
//| Appends a caption/value row and returns its index.                |
//+------------------------------------------------------------------+
int CChartPanel::AddRow(const string caption,const string value,
                        const color caption_color,const color value_color)
  {
   int index=ArraySize(m_rows);
   ArrayResize(m_rows,index+1);
   m_rows[index].caption       = caption;
   m_rows[index].value         = value;
   m_rows[index].caption_color = caption_color;
   m_rows[index].value_color   = value_color;
   m_rows[index].is_header     = false;
   return(index);
  }

//+------------------------------------------------------------------+
//| Appends a full-width header row.                                  |
//+------------------------------------------------------------------+
int CChartPanel::AddHeader(const string caption,const color text_color)
  {
   int index=AddRow(caption,"",text_color,text_color);
   m_rows[index].is_header=true;
   return(index);
  }

//+------------------------------------------------------------------+
//| Appends an empty row, used as vertical spacing between groups.    |
//+------------------------------------------------------------------+
int CChartPanel::AddSeparator(void)
  {
   return(AddHeader("",clrNONE));
  }

//+------------------------------------------------------------------+
//| Overwrites an existing row. Returns false for an unknown index so |
//| callers can fall back to AddRow().                                |
//+------------------------------------------------------------------+
bool CChartPanel::SetRow(const int index,const string caption,const string value,
                         const color caption_color,const color value_color)
  {
   if(index<0 || index>=ArraySize(m_rows))
      return(false);
   m_rows[index].caption       = caption;
   m_rows[index].value         = value;
   m_rows[index].caption_color = caption_color;
   m_rows[index].value_color   = value_color;
   return(true);
  }

//+------------------------------------------------------------------+
//| Creates the label object if it is not on the chart yet.           |
//+------------------------------------------------------------------+
bool CChartPanel::EnsureLabel(const string name)
  {
   if(ObjectFind(m_chart,name)<0)
     {
      if(!ObjectCreate(m_chart,name,OBJ_LABEL,m_subwindow,0,0))
         return(false);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTED,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
      ObjectSetInteger(m_chart,name,OBJPROP_ZORDER,1);
     }
   ObjectSetInteger(m_chart,name,OBJPROP_CORNER,m_corner);
   ObjectSetString(m_chart,name,OBJPROP_FONT,m_font);
   ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,m_font_size);
   return(true);
  }

//+------------------------------------------------------------------+
//| Translates panel-local coordinates (lx to the right, ly down from |
//| the panel's top-left) into the corner-relative distances and the  |
//| anchor MetaTrader needs, then applies them to the object.         |
//+------------------------------------------------------------------+
void CChartPanel::Place(const string name,const int lx,const int ly,const bool right_aligned)
  {
   int x = IsRightCorner() ? m_x+m_width-lx : m_x+lx;
   int y = IsLowerCorner() ? m_y+m_height-(ly+m_row_height) : m_y+ly;

   ENUM_ANCHOR_POINT anchor;
   if(right_aligned)
      anchor = IsLowerCorner() ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER;
   else
      anchor = IsLowerCorner() ? ANCHOR_LEFT_LOWER  : ANCHOR_LEFT_UPPER;

   ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(m_chart,name,OBJPROP_ANCHOR,anchor);
  }

//+------------------------------------------------------------------+
//| Creates/updates the rectangle label used as the panel background. |
//+------------------------------------------------------------------+
void CChartPanel::ApplyBackground(void)
  {
   string name=BackgroundName();
   if(ObjectFind(m_chart,name)<0)
     {
      if(!ObjectCreate(m_chart,name,OBJ_RECTANGLE_LABEL,m_subwindow,0,0))
         return;
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTED,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
      ObjectSetInteger(m_chart,name,OBJPROP_ZORDER,0);
     }
   ObjectSetInteger(m_chart,name,OBJPROP_CORNER,m_corner);
   ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,m_x);
   ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,m_y);
   ObjectSetInteger(m_chart,name,OBJPROP_XSIZE,m_width);
   ObjectSetInteger(m_chart,name,OBJPROP_YSIZE,m_height);
   ObjectSetInteger(m_chart,name,OBJPROP_BGCOLOR,m_bg_color);
   ObjectSetInteger(m_chart,name,OBJPROP_COLOR,m_border_color);
   ObjectSetInteger(m_chart,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
  }

//+------------------------------------------------------------------+
//| Deletes labels left over from a previous, longer layout.          |
//+------------------------------------------------------------------+
void CChartPanel::RemoveExtraLabels(const int keep_rows)
  {
   for(int i=keep_rows; i<m_drawn_rows; i++)
     {
      ObjectDelete(m_chart,RowName(i,false));
      ObjectDelete(m_chart,RowName(i,true));
     }
  }

//+------------------------------------------------------------------+
//| Pushes the current rows to the chart.                             |
//+------------------------------------------------------------------+
void CChartPanel::Redraw(void)
  {
   int rows=ArraySize(m_rows);
   m_height=2*m_padding+rows*m_row_height;

   ApplyBackground();

   for(int i=0; i<rows; i++)
     {
      int ly=m_padding+i*m_row_height;

      string caption_name=RowName(i,false);
      if(EnsureLabel(caption_name))
        {
         ObjectSetString(m_chart,caption_name,OBJPROP_TEXT,m_rows[i].caption);
         ObjectSetInteger(m_chart,caption_name,OBJPROP_COLOR,m_rows[i].caption_color);
         Place(caption_name,m_padding,ly,false);
        }

      //--- header rows span the whole width, so they carry no value label
      string value_name=RowName(i,true);
      if(m_rows[i].is_header)
        {
         ObjectDelete(m_chart,value_name);
         continue;
        }
      if(EnsureLabel(value_name))
        {
         ObjectSetString(m_chart,value_name,OBJPROP_TEXT,m_rows[i].value);
         ObjectSetInteger(m_chart,value_name,OBJPROP_COLOR,m_rows[i].value_color);
         Place(value_name,m_width-m_padding,ly,true);
        }
     }

   RemoveExtraLabels(rows);
   m_drawn_rows=rows;
  }

//+------------------------------------------------------------------+
//| Removes every object the panel owns.                              |
//+------------------------------------------------------------------+
void CChartPanel::Destroy(void)
  {
   ObjectsDeleteAll(m_chart,m_prefix,m_subwindow);
   m_drawn_rows=0;
  }
//+------------------------------------------------------------------+
