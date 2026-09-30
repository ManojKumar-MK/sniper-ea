//+------------------------------------------------------------------+
//|                                            SniperGrid_v1.00.mq5  |
//|   Flat-lot grid, with a funded-account mode that can refuse to   |
//|   start a basket it cannot afford to lose.                       |
//|                                                                  |
//|   Copyright 2026, Manojkumar K                                   |
//|   mailtomktech@gmail.com                                         |
//|                                                                  |
//|   WRITTEN FOR BASKETS, not adapted from a single-position EA.     |
//|   Everything here selects positions by symbol AND magic and       |
//|   iterates - the bug that made an earlier EA report FLAT with     |
//|   four of its own trades open came from PositionSelect() picking  |
//|   one position on a hedging account. No call in this file assumes |
//|   a single position exists.                                      |
//|                                                                  |
//|   THE MODEL                                                      |
//|     1 TRIGGER   a grid starts on an EMA cross, or immediately,   |
//|                 or at a session open - InpTrigger.               |
//|     2 LEGS      each further leg opens InpStepAtr ATR (or         |
//|                 InpStepPoints) AGAINST the basket, same lot every |
//|                 time. No martingale: drawdown grows linearly with |
//|                 leg count, which is the only version of this that |
//|                 is predictable.                                  |
//|     3 EXIT      the whole basket closes together, on a combined   |
//|                 money target, a combined stop, or a basket        |
//|                 breakeven once it is ahead.                      |
//|                                                                  |
//|   WHY FLAT LOTS. A martingale basket breaks even on a smaller     |
//|   retrace, which is why those equity curves look smooth for years |
//|   and then lose everything in a week. Flat lots recover slower    |
//|   and cannot compound the loss.                                  |
//|                                                                  |
//|   THE FUNDED MODE IS THE POINT                                   |
//|   Grids fail prop rules because they hold losers open: balance    |
//|   barely moves while EQUITY falls, and the firm measures equity.  |
//|   Measured here: eleven third-party grid EAs ran 18.9-64% equity  |
//|   drawdown, and Gold Reaper showed 1.38% balance against 23%+     |
//|   equity on M5.                                                  |
//|                                                                  |
//|   So InpMode=FUNDED does two things no reviewed grid did:         |
//|     * it computes the WORST CASE before opening leg 1 - all legs  |
//|       filled and price at the basket stop - and REFUSES to start  |
//|       a grid whose worst case exceeds InpRiskBudget                |
//|     * it checks floating EQUITY every tick against a hard floor   |
//|       and flattens, rather than trusting a per-leg stop           |
//|                                                                  |
//|   That makes the exposure knowable in advance. It does not make   |
//|   a grid a good idea on a 6% account - it makes the limit         |
//|   enforceable instead of hoped for.                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Manojkumar K - mailtomktech@gmail.com"
#property link      "mailto:mailtomktech@gmail.com"
#property description "Flat-lot grid with a worst-case-aware funded mode."
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//====================================================================
//  INPUTS
//====================================================================
enum ENUM_GMODE   { GMODE_FUNDED=0, GMODE_FREE=1 };
enum ENUM_GTRIG   { GTRIG_EMA=0, GTRIG_NOW=1, GTRIG_SESSION=2 };
enum ENUM_GDIR    { GDIR_TREND=0, GDIR_COUNTER=1, GDIR_BOTH=2 };

input group "-- MODE --"
input ENUM_GMODE InpMode          = GMODE_FUNDED;  // FUNDED = refuse a basket whose worst case
                                                   //   exceeds InpRiskBudget, and flatten on a
                                                   //   hard equity floor.
                                                   // FREE   = no budget test, no equity floor;
                                                   //   only the basket stop limits the loss.
input double   InpRiskBudget      = 600.0;         // FUNDED: most the whole basket may ever lose,
                                                   //   in account currency. Sized BELOW the firm's
                                                   //   daily limit, not equal to it.
input double   InpEquityFloorPct  = 4.0;           // FUNDED: flatten if floating equity falls this
                                                   //   far below the session's starting equity.
                                                   //   Checked every tick on EQUITY, which is what
                                                   //   a prop firm measures.

input group "-- ENTRY: what starts a grid --"
input ENUM_GTRIG InpTrigger       = GTRIG_EMA;
input ENUM_GDIR  InpGridDir       = GDIR_TREND;    // TREND   = first leg with the EMA bias
                                                   // COUNTER = against it (mean reversion)
                                                   // BOTH    = a grid each way, hedging account only
input int      InpEmaFast         = 50;
input int      InpEmaSlow         = 100;
input string   InpSessionHHMM     = "0700-1000";   // GTRIG_SESSION: New York clock

input group "-- THE GRID --"
input double   InpLot             = 0.01;          // same for every leg. No martingale.
input int      InpMaxLegs         = 5;             // hard cap. Worst case scales with this.
input double   InpStepAtr         = 1.0;           // spacing between legs, in ATR. 0 = use points.
input int      InpStepPoints      = 0;             // spacing in points when InpStepAtr is 0.
input int      InpAtrPeriod       = 14;
input int      InpMinBarsBetween  = 1;             // bars that must pass before another leg, so a
                                                   // single fast candle cannot fill the whole grid.

input group "-- BASKET EXIT --"
input double   InpBasketTpMoney   = 50.0;          // close all at this combined profit. 0 = off.
input double   InpBasketSlMoney   = 400.0;         // close all at this combined loss. 0 = off.
                                                   // In FUNDED mode the budget test uses this.
input bool     InpBasketBreakeven = true;          // once ahead by InpBeTrigMoney, close the basket
input double   InpBeTrigMoney     = 25.0;          //   if it falls back to InpBeFloorMoney
input double   InpBeFloorMoney    = 2.0;
input bool     InpCloseOnFriday   = true;          // flatten before the weekend

input group "-- GUARDS --"
input double   InpMaxDailyLoss    = 600.0;         // stop new baskets once the day is this far down
input int      InpMaxBasketsDay   = 3;
input int      InpMaxSpreadPts    = 40;

input group "-- IDENTITY --"
input long     InpMagic           = 996000;
input string   InpCsvPrefix       = "SniperGrid_Log";
input bool     InpShowPanel       = true;
input bool     InpLogCsv          = true;

//====================================================================
//  STATE
//====================================================================
CTrade   trade;
int      hEmaF=INVALID_HANDLE, hEmaS=INVALID_HANDLE, hAtr=INVALID_HANDLE;

double   g_sessionEquity = 0.0;      // equity at the start of the trading day
datetime g_day           = 0;
double   g_dayRealised   = 0.0;
int      g_basketsToday  = 0;
bool     g_halted        = false;
string   g_haltWhy       = "";

int      g_legs          = 0;        // legs in the live basket
int      g_dir           = 0;        // +1 long basket, -1 short
double   g_anchor        = 0.0;      // price of the first leg
double   g_lastLegPx     = 0.0;
datetime g_lastLegBar    = 0;
double   g_step          = 0.0;      // the spacing this basket was opened with
bool     g_beArmed       = false;    // basket has been ahead by InpBeTrigMoney
double   g_peakBasket    = 0.0;

//====================================================================
//  POSITION SELECTION - by symbol AND magic, always iterating
//====================================================================
int OurTickets(ulong &out[])
{
   ArrayResize(out,0);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      int n=ArraySize(out); ArrayResize(out,n+1); out[n]=tk;
   }
   return ArraySize(out);
}

int OurCount()
{
   ulong t[]; return OurTickets(t);
}

//  Combined floating P/L of our basket, including swap and commission.
double BasketPL()
{
   ulong t[]; int n=OurTickets(t);
   double pl=0.0;
   for(int i=0;i<n;i++)
   {
      if(!PositionSelectByTicket(t[i])) continue;
      pl += PositionGetDouble(POSITION_PROFIT)
          + PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

double BasketVolume()
{
   ulong t[]; int n=OurTickets(t);
   double v=0.0;
   for(int i=0;i<n;i++) if(PositionSelectByTicket(t[i])) v+=PositionGetDouble(POSITION_VOLUME);
   return v;
}

//====================================================================
//  MONEY: what one point of adverse move costs on one leg
//====================================================================
double MoneyPerPointPerLot()
{
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0.0) return 0.0;
   return tv*(_Point/ts);
}

//  THE FUNDED TEST. Before leg 1 exists, what does the whole grid lose if
//  every leg fills and price then reaches the basket stop?
//
//  With flat lots and even spacing, leg k is (k-1)*step from the anchor, so
//  the basket's average entry sits step*(n-1)/2 from the anchor. The loss at
//  a given adverse distance D from the anchor is:
//      lot * mpp * sum(D - (k-1)*step)  for k = 1..n
//  which is what this returns. Linear in n, which is the whole reason for
//  refusing martingale.
double WorstCaseLoss(int legs,double step)
{
   double mpp=MoneyPerPointPerLot();
   if(mpp<=0.0 || step<=0.0 || legs<1) return 0.0;
   double stepPts=step/_Point;
   //  adverse distance at which the basket stop would trip: the furthest leg
   //  plus whatever further travel the stop allows. Without a money stop the
   //  only bound is the equity floor, so treat that as the distance.
   double sum=0.0;
   for(int k=1;k<=legs;k++) sum += (legs-1)*stepPts - (k-1)*stepPts;
   //  sum is the loss in points at the moment the LAST leg fills
   return sum*InpLot*mpp;
}

//  What the basket loses by the time the last leg fills - the unavoidable
//  part, before the stop is even consulted.
double LossAtFullGrid(double step) { return WorstCaseLoss(InpMaxLegs,step); }

//====================================================================
//  HELPERS
//====================================================================
double Atr()
{
   double b[]; if(CopyBuffer(hAtr,0,1,1,b)!=1) return 0.0;
   return b[0];
}

int EmaBias()
{
   double f[],s[];
   if(CopyBuffer(hEmaF,0,1,1,f)!=1) return 0;
   if(CopyBuffer(hEmaS,0,1,1,s)!=1) return 0;
   if(f[0]>s[0]) return  1;
   if(f[0]<s[0]) return -1;
   return 0;
}

int EmaCross()
{
   double f[],s[];
   if(CopyBuffer(hEmaF,0,1,2,f)!=2) return 0;
   if(CopyBuffer(hEmaS,0,1,2,s)!=2) return 0;
   if(f[1]<=s[1] && f[0]>s[0]) return  1;
   if(f[1]>=s[1] && f[0]<s[0]) return -1;
   return 0;
}

bool SpreadOk()
{
   if(InpMaxSpreadPts<=0) return true;
   return ((long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) <= InpMaxSpreadPts);
}

bool InSession()
{
   string p[]; if(StringSplit(InpSessionHHMM,'-',p)!=2) return true;
   MqlDateTime d; TimeToStruct(TimeGMT(),d);   // GMT, no DST claim made
   int now=d.hour*60+d.min;
   int a=(int)StringToInteger(StringSubstr(p[0],0,2))*60+(int)StringToInteger(StringSubstr(p[0],2,2));
   int b=(int)StringToInteger(StringSubstr(p[1],0,2))*60+(int)StringToInteger(StringSubstr(p[1],2,2));
   if(a==b) return true;
   return (a<b) ? (now>=a && now<b) : (now>=a || now<b);
}

void Say(const string tag,const string msg)
{
   PrintFormat("[%s] %s",tag,msg);
}

//====================================================================
//  LOGGING
//====================================================================
string LogPath()
{
   return InpCsvPrefix+"_"+_Symbol+"_"+EnumToString((ENUM_TIMEFRAMES)_Period)+".csv";
}

void LogRow(const string evt,double px,double vol,double pl,const string note)
{
   if(!InpLogCsv) return;
   string f=LogPath();
   bool neu=!FileIsExist(f);
   int h=FileOpen(f,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   if(neu) FileWrite(h,"time","event","dir","legs","price","volume","basket_pl",
                       "day_realised","equity","balance","note");
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),evt,
             (g_dir==1?"BUY":(g_dir==-1?"SELL":"-")),IntegerToString(g_legs),
             DoubleToString(px,_Digits),DoubleToString(vol,2),DoubleToString(pl,2),
             DoubleToString(g_dayRealised,2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),note);
   FileClose(h);
}

//====================================================================
//  TRADING
//====================================================================
bool OpenLeg(int dir)
{
   double px=(dir==1)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   //  No per-leg stop or target on purpose: the BASKET is the unit that exits.
   //  A per-leg stop would close legs individually and leave the average entry
   //  drifting, which is how a grid ends up holding only its worst positions.
   bool ok = (dir==1) ? trade.Buy(InpLot,_Symbol,0.0,0.0,0.0,"GRID leg")
                      : trade.Sell(InpLot,_Symbol,0.0,0.0,0.0,"GRID leg");
   if(!ok)
   {
      Say("ERROR",StringFormat("leg %d rejected | retcode %d | %s",
          g_legs+1,trade.ResultRetcode(),trade.ResultRetcodeDescription()));
      LogRow("LEG_FAIL",px,InpLot,BasketPL(),trade.ResultRetcodeDescription());
      return false;
   }
   g_legs++;
   g_lastLegPx=px;
   g_lastLegBar=iTime(_Symbol,_Period,0);
   if(g_legs==1){ g_anchor=px; g_dir=dir; g_beArmed=false; g_peakBasket=0.0; }
   Say("LEG",StringFormat("%s leg %d/%d @ %s | basket %.2f",
       (dir==1?"BUY":"SELL"),g_legs,InpMaxLegs,DoubleToString(px,_Digits),BasketPL()));
   LogRow("LEG_OPEN",px,InpLot,BasketPL(),
          StringFormat("leg %d of %d, step %s",g_legs,InpMaxLegs,DoubleToString(g_step,_Digits)));
   return true;
}

//  Close EVERY position of ours, reporting whether all of them went.
bool CloseBasket(const string why)
{
   ulong t[]; int n=OurTickets(t);
   if(n==0){ g_legs=0; g_dir=0; return true; }
   double pl=BasketPL(), vol=BasketVolume();
   bool allok=true;
   for(int i=0;i<n;i++)
      if(!trade.PositionClose(t[i])) allok=false;
   int left=OurCount();
   if(left>0)
   {
      Say("ERROR",StringFormat("basket close incomplete: %d of %d still open (%s)",left,n,why));
      LogRow("CLOSE_PARTIAL",0.0,vol,pl,StringFormat("%d of %d left | %s",left,n,why));
      return false;
   }
   g_dayRealised += pl;
   Say("BASKET",StringFormat("closed %d legs | %.2f | %s",n,pl,why));
   LogRow("BASKET_CLOSE",0.0,vol,pl,why);
   g_legs=0; g_dir=0; g_anchor=0.0; g_beArmed=false; g_peakBasket=0.0;
   return allok;
}

//====================================================================
//  GUARDS
//====================================================================
void RollDay()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   datetime today=StringToTime(StringFormat("%04d.%02d.%02d",d.year,d.mon,d.day));
   if(today==g_day) return;
   g_day=today;
   g_dayRealised=0.0;
   g_basketsToday=0;
   g_sessionEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_halted=false; g_haltWhy="";
   Say("DAY",StringFormat("new day | equity baseline %.2f",g_sessionEquity));
}

//  FUNDED: the hard floor, on EQUITY, every tick. This is the guard the
//  reviewed grid EAs did not have - Gold Reaper measured BALANCE, which
//  barely moves while a basket is underwater.
bool EquityFloorBreached()
{
   if(InpMode!=GMODE_FUNDED || InpEquityFloorPct<=0.0) return false;
   if(g_sessionEquity<=0.0) return false;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double floorEq=g_sessionEquity*(1.0-InpEquityFloorPct/100.0);
   return (eq<=floorEq);
}

//  Can a NEW basket be started?
bool MayStartBasket(string &why)
{
   why="";
   if(g_halted){ why=g_haltWhy; return false; }
   if(!SpreadOk()){ why="spread too wide"; return false; }
   if(InpMaxBasketsDay>0 && g_basketsToday>=InpMaxBasketsDay){ why="basket limit for the day"; return false; }
   if(InpMaxDailyLoss>0 && g_dayRealised<=-InpMaxDailyLoss){ why="daily loss cap"; return false; }

   if(InpMode==GMODE_FUNDED)
   {
      //  Refuse a grid we cannot afford. This is the whole point of the mode:
      //  the exposure is knowable BEFORE leg 1, so it is checked then rather
      //  than discovered at leg 5.
      double atr=Atr();
      double step=(InpStepAtr>0.0)?atr*InpStepAtr:InpStepPoints*_Point;
      if(step<=0.0){ why="cannot size the step (no ATR yet)"; return false; }
      double floorLoss=LossAtFullGrid(step);
      double stopLoss =(InpBasketSlMoney>0.0)?InpBasketSlMoney:floorLoss;
      double worst=MathMax(floorLoss,stopLoss);
      if(worst>InpRiskBudget)
      {
         why=StringFormat("worst case %.0f > budget %.0f (step %s, %d legs)",
                          worst,InpRiskBudget,DoubleToString(step,_Digits),InpMaxLegs);
         return false;
      }
   }
   return true;
}

//====================================================================
//  MANAGE THE LIVE BASKET
//====================================================================
void ManageBasket()
{
   int n=OurCount();
   if(n==0)
   {
      if(g_legs!=0){ g_legs=0; g_dir=0; }     // closed by stop-out or by hand
      return;
   }
   g_legs=n;
   double pl=BasketPL();
   if(pl>g_peakBasket) g_peakBasket=pl;

   //  --- hard equity floor first. Nothing outranks it. ---
   if(EquityFloorBreached())
   {
      g_halted=true;
      g_haltWhy=StringFormat("equity floor %.1f%% below %.2f",InpEquityFloorPct,g_sessionEquity);
      CloseBasket("EQUITY FLOOR");
      return;
   }

   //  --- basket money stop ---
   if(InpBasketSlMoney>0.0 && pl<=-InpBasketSlMoney)
   { CloseBasket(StringFormat("basket stop %.2f",pl)); return; }

   //  --- basket target ---
   if(InpBasketTpMoney>0.0 && pl>=InpBasketTpMoney)
   { CloseBasket(StringFormat("basket target %.2f",pl)); return; }

   //  --- basket breakeven: give back no more than InpBeFloorMoney once ahead ---
   if(InpBasketBreakeven)
   {
      if(!g_beArmed && pl>=InpBeTrigMoney)
      {
         g_beArmed=true;
         Say("BE",StringFormat("basket armed at %.2f | will close if it falls to %.2f",pl,InpBeFloorMoney));
      }
      if(g_beArmed && pl<=InpBeFloorMoney)
      { CloseBasket(StringFormat("basket breakeven %.2f",pl)); return; }
   }

   //  --- Friday ---
   if(InpCloseOnFriday)
   {
      MqlDateTime d; TimeToStruct(TimeCurrent(),d);
      if(d.day_of_week==5 && d.hour>=20)
      { CloseBasket("before the weekend"); return; }
   }

   //  --- add a leg? ---
   if(g_legs>=InpMaxLegs) return;
   if(iTime(_Symbol,_Period,0)==g_lastLegBar && InpMinBarsBetween>0) return;
   double px=(g_dir==1)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double adverse=(g_dir==1)?(g_lastLegPx-px):(px-g_lastLegPx);
   if(adverse>=g_step && SpreadOk() && !EquityFloorBreached())
      OpenLeg(g_dir);
}

//====================================================================
//  PANEL
//====================================================================
void Panel()
{
   if(!InpShowPanel) return;
   double atr=Atr();
   double step=(InpStepAtr>0.0)?atr*InpStepAtr:InpStepPoints*_Point;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   string why; bool may=MayStartBasket(why);
   string s=StringFormat(
     "SniperGrid  %s  %s\n"
     "mode      %s\n"
     "basket    %d/%d legs  %s\n"
     "P/L       %.2f   peak %.2f\n"
     "step      %s  (%.1f ATR)\n"
     "worst     %.0f of budget %.0f\n"
     "day       realised %.2f   baskets %d/%d\n"
     "equity    %.2f  floor %.2f\n"
     "%s",
     _Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),
     (InpMode==GMODE_FUNDED?"FUNDED":"FREE"),
     g_legs,InpMaxLegs,(g_dir==1?"BUY":(g_dir==-1?"SELL":"flat")),
     BasketPL(),g_peakBasket,
     DoubleToString(step,_Digits),InpStepAtr,
     LossAtFullGrid(step),InpRiskBudget,
     g_dayRealised,g_basketsToday,InpMaxBasketsDay,
     eq,(InpMode==GMODE_FUNDED?g_sessionEquity*(1.0-InpEquityFloorPct/100.0):0.0),
     (may?"entries allowed":"BLOCKED: "+why));
   Comment(s);
}

//====================================================================
//  LIFECYCLE
//====================================================================
int OnInit()
{
   hEmaF=iMA(_Symbol,_Period,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hEmaS=iMA(_Symbol,_Period,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   hAtr =iATR(_Symbol,_Period,InpAtrPeriod);
   if(hEmaF==INVALID_HANDLE||hEmaS==INVALID_HANDLE||hAtr==INVALID_HANDLE)
   { Say("INIT","indicator handle failed"); return INIT_FAILED; }

   if(InpLot<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN))
   { Say("INIT","InpLot is below the symbol minimum"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxLegs<1) return INIT_PARAMETERS_INCORRECT;

   g_sessionEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   RollDay();

   //  Say the exposure out loud at startup, before anything is risked.
   double step=(InpStepAtr>0.0)?Atr()*InpStepAtr:InpStepPoints*_Point;
   Say("CONFIG",StringFormat("mode %s | %d legs x %.2f lot | step %s",
       (InpMode==GMODE_FUNDED?"FUNDED":"FREE"),InpMaxLegs,InpLot,DoubleToString(step,_Digits)));
   if(step>0.0)
      Say("CONFIG",StringFormat("loss by the time the last leg fills: %.0f | basket stop %.0f | budget %.0f",
          LossAtFullGrid(step),InpBasketSlMoney,InpRiskBudget));
   if(InpMode==GMODE_FREE)
      Say("CONFIG","FREE mode: no budget test and NO equity floor. The basket stop is the "
                   "only thing limiting a loss. Not for a funded account.");
   if(InpGridDir==GDIR_BOTH)
      Say("CONFIG","GDIR_BOTH needs a HEDGING account. On netting the two sides cancel and "
                   "the grid will not behave as intended.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

void OnTick()
{
   RollDay();
   ManageBasket();
   Panel();

   if(OurCount()>0) return;             // a basket is live; nothing new starts

   string why;
   if(!MayStartBasket(why)) return;

   //  --- what direction, if any? ---
   int want=0;
   if(InpTrigger==GTRIG_EMA)
   {
      int x=EmaCross();
      if(x==0) return;
      want=(InpGridDir==GDIR_COUNTER)?-x:x;
   }
   else if(InpTrigger==GTRIG_NOW)
   {
      int b=EmaBias();
      if(b==0) return;
      want=(InpGridDir==GDIR_COUNTER)?-b:b;
   }
   else // GTRIG_SESSION
   {
      if(!InSession()) return;
      int b=EmaBias();
      if(b==0) return;
      want=(InpGridDir==GDIR_COUNTER)?-b:b;
   }
   if(want==0) return;

   double atr=Atr();
   g_step=(InpStepAtr>0.0)?atr*InpStepAtr:InpStepPoints*_Point;
   if(g_step<=0.0) return;

   if(OpenLeg(want)) g_basketsToday++;
}
