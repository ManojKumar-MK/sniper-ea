//+------------------------------------------------------------------+
//|  SR_HTF_StopEntry_EA.mq5                                         |
//|  HTF-gated ICT entry model using Buy Stop / Sell Stop orders     |
//|                                                                  |
//|  Model (long side; short is mirrored):                           |
//|   1. HTF bias: H1 / H4 / D1 swing structure must agree           |
//|   2. Location: price in discount of the HTF dealing range        |
//|   3. Liquidity: an M5 candle sweeps a prior low and closes back  |
//|   4. Entry: BUY STOP above the structure high before the sweep   |
//|      -> only fills if price actually breaks structure (MSS)      |
//|   5. SL below the sweep low, TP at HTF liquidity (min RR gate)   |
//|  Plus: killzones, news filter, daily/max loss guards, target lock|
//|                                                                  |
//|  v1.10 - every input below is additive and defaults to the v1.00  |
//|  behaviour, so an existing .set reproduces its old result:        |
//|   InpMaxOppose      separates "how many agree" from "none may     |
//|                     disagree", which were conflated - 1/2/3 on    |
//|                     InpMinAgree picked nearly the same bars       |
//|   InpTPFallback     take a fixed-RR target when HTF liquidity is  |
//|                     closer than InpMinRR, instead of skipping.    |
//|                     That skip was rejecting almost every setup:   |
//|                     5 trades in 9 months vs 30 without it         |
//|   InpAsia*          a third killzone                              |
//|   InpDailyTargetUSD bank the day once it is made                  |
//|                                                                  |
//|  v1.20 - quality, and the diagnostic that should have come first: |
//|   InpDiagCSV       tally WHY setups are rejected and dump it, so  |
//|                    a grid can tell "input did nothing" from       |
//|                    "input never got reached"                      |
//|   InpTPRMult       target R, separated from the InpMinRR GATE.    |
//|                    One input was doing both jobs, so a 2R target  |
//|                    could not be demanded of a 3R-clear setup      |
//|   InpDirection     longs only / shorts only. Shorts beat longs on |
//|                    every set measured so far - testable, not      |
//|                    assumed                                        |
//|   InpMinATRPts     volatility floor: skip dead tape               |
//|   InpPartialPct    bank part of the position at BE_R, trail the   |
//|   InpTrailATRMult  rest. Turning BE off collapsed the win rate    |
//|                    63%% -> 23%%, so the BE move is where the edge  |
//|                    actually lives - this is built on top of it    |
//|                                                                  |
//|  v1.30 - REFUSES TO RUN on an unparsed timeframe input.           |
//|  An MT5 .set file stores an enum as an INTEGER. A line reading    |
//|  "InpTF1=PERIOD_H1" does not parse: the input silently becomes 0, |
//|  PERIOD_CURRENT, the chart timeframe. Every .set in this repo was |
//|  written that way, so InpTF1/2/3, InpRangeTF and InpEntryTF were  |
//|  collapsing to the chart TF and the EA never ran the H1/H4/D1     |
//|  model it was tested as. Silent, and it invalidated three grids.  |
//|  OnInit now stops instead, and prints the resolved values so the  |
//|  log always proves what actually ran.                            |
//|  Correct .set values: M1=1 M5=5 M15=15 M30=30 H1=16385 H4=16388   |
//|  D1=16408 W1=32769 MN1=49153                                     |
//+------------------------------------------------------------------+
#property copyright "Shriram"
#property version   "1.60"

#include <Trade/Trade.mqh>
CTrade trade;

enum ENUM_SRHTF_DIR { SRHTF_BOTH = 0, SRHTF_LONG_ONLY = 1, SRHTF_SHORT_ONLY = 2 };

//=================== INPUTS ===================
input group "=== HTF Bias ==="
input ENUM_TIMEFRAMES InpTF1          = PERIOD_H1;
input ENUM_TIMEFRAMES InpTF2          = PERIOD_H4;
input ENUM_TIMEFRAMES InpTF3          = PERIOD_D1;
input int             InpMinAgree     = 3;      // TFs that must agree (1-3). 3 = A+ only
input int             InpMaxOppose    = 0;      // TFs allowed to disagree. 0 = v1.00 behaviour
input int             InpSwingStrength= 2;      // Fractal bars each side
input int             InpSwingLookback= 150;    // Bars searched for swings
input bool            InpUsePDFilter  = true;   // Longs in discount, shorts in premium
input ENUM_TIMEFRAMES InpRangeTF      = PERIOD_H4; // Dealing range / liquidity TF
input int             InpRangeBars    = 30;     // Dealing range length (bars)

input group "=== LTF Entry (Stop orders) ==="
input ENUM_TIMEFRAMES InpEntryTF      = PERIOD_M5;
input int             InpSweepLookback= 20;     // Bars forming the liquidity pool
// The pool an N-bar extreme picks is a GUESS at where stops are resting. The
// Asian session high and low are a named level - "their high and low become
// tomorrow's liquidity", Practical ICT Strategies ch9 p105 - and swapping one
// for the other was the single best book-derived change in the SniperEntry
// book grid: best net AND best per-trade on both M3 and M5, +14% and +41% per
// trade over the N-bar version. This EA's sweep had the same weakness.
input bool            InpSweepAsianRange = false; // sweep the PRIOR ASIAN RANGE instead of an N-bar extreme
input int             InpAsiaRangeStart  = 0;     // Asian range start, GMT hour
input int             InpAsiaRangeEnd    = 5;     // ...and end
input int             InpSweepWindow  = 12;     // Sweep must be within last N bars
input double          InpEntryBufPts  = 20;     // Points beyond structure for the stop order
input double          InpSLBufPts     = 30;     // Points beyond sweep extreme for SL
input double          InpTPBufPts     = 20;     // Points in front of HTF liquidity for TP
input double          InpMinRR        = 3.0;    // GATE: setup rejected below this R
input double          InpTPRMult      = 0;      // TARGET in R. 0 = use InpMinRR (v1.10 behaviour)
input bool            InpTargetLiquidity = true;// TP at HTF liquidity (else fixed MinRR)
input bool            InpTPFallback   = false;  // Liquidity too close? take fixed MinRR instead of skipping
input int             InpOrderExpiryBars = 6;   // Pending order life (entry-TF bars)
input double          InpMinSLPts     = 100;    // Skip if stop tighter than this
input double          InpMaxSLPts     = 1500;   // Skip if stop wider than this
input double          InpMinATRPts    = 0;      // Skip if entry-TF ATR below this. 0 = off
input ENUM_SRHTF_DIR  InpDirection    = SRHTF_BOTH;

input group "=== Sessions (UTC) & News ==="
input int             InpServerGMTOffset = 2;   // Broker server GMT offset (hours)
input bool            InpLondon       = true;
input int             InpLonStart     = 7;
input int             InpLonEnd       = 10;
input bool            InpNY           = true;
input int             InpNYStart      = 12;
input int             InpNYEnd        = 15;
input bool            InpAsia         = false;  // Third killzone. false = v1.00 behaviour
input int             InpAsiaStart    = 0;
input int             InpAsiaEnd      = 3;
input bool            InpNewsFilter   = true;   // Live only (calendar not in tester)
input int             InpNewsMinsBefore = 30;
input int             InpNewsMinsAfter  = 30;

input group "=== Risk ==="
input double          InpRiskPct      = 0.5;    // % of balance risked per trade
input double          InpMaxLots      = 5.0;
input int             InpMaxTradesDay = 2;
input int             InpMaxLossesDay = 2;
input double          InpMaxSpreadPts = 250;
input bool            InpBreakEven    = true;
input double          InpBE_R         = 1.0;    // Move SL to BE at this R
input double          InpBEOffsetPts  = 20;     // Covers commission
input double          InpPartialPct   = 0;      // % of position closed at BE_R. 0 = off
input double          InpTrailATRMult = 0;      // Trail at N x ATR once past BE. NEEDS InpBreakEven=true. 0 = off
input int             InpATRPeriod    = 14;
input bool            InpFridayClose  = true;
input int             InpFridayHourUTC= 19;

input group "=== Prop Firm Guards ==="
input double          InpInitialBalance = 25000;
input double          InpDailyGuardPct  = 2.5;  // EA stops for the day (firm limit 5%)
input double          InpMaxGuardPct    = 6.0;  // EA stops permanently (firm limit 10%)
input bool            InpTargetLock     = true; // Off for funded/instant accounts
input double          InpTargetPct      = 8.0;  // Challenge phase target
input double          InpDailyTargetUSD = 0;    // Bank the day at this realised profit. 0 = off
input bool            InpResetState     = false;// true once to clear saved halts

input group "=== Misc ==="
input long            InpMagic        = 52741;
input string          InpComment      = "SR_HTF";
input bool            InpDiagCSV      = false;  // Dump the rejection tally at OnDeinit
input bool            InpSetupCSV     = false;  // Log every setup's features + realised R

//=================== GLOBALS ===================
datetime g_lastBar      = 0;
datetime g_dayStart     = 0;
double   g_dayStartEq   = 0;
bool     g_dayHalted    = false;
bool     g_accHalted    = false;
int      g_bias         = 0, g_b1 = 0, g_b2 = 0, g_b3 = 0;
bool     g_news         = false;
int      g_tradesToday  = 0, g_lossesToday = 0;
double   g_profitToday  = 0;      // realised only - floating would flap the target check
// Both the max-loss guard and the target lock set g_accHalted, so the reason
// has to be recorded separately or OnTester cannot tell a passed challenge
// from a blown account - they are the two outcomes it exists to distinguish.
int      g_haltReason   = 0;      // 0 none, 1 max-loss floor, 2 target reached
datetime g_haltTime     = 0;
bool     g_dayBanked    = false;
datetime g_lastSweepTime= 0;
string   g_status       = "Starting";
int      g_atrHandle    = INVALID_HANDLE;

// Why setups do not become orders. Without this a grid cannot tell an input
// that changed nothing from an input whose branch was never reached - which
// is exactly the ambiguity 11 identical sets left in the v2 results.
#define SRHTF_NREJ 15
enum ENUM_SRHTF_REJ
{
   REJ_NO_BIAS = 0, REJ_EXPOSURE, REJ_MAX_TRADES, REJ_MAX_LOSSES, REJ_SPREAD,
   REJ_NO_RANGE, REJ_PD_LOCATION, REJ_NO_SWEEP, REJ_STOPS_LEVEL, REJ_SWEEP_REUSED,
   REJ_SL_SIZE, REJ_RR_GATE, REJ_ATR_FLOOR, REJ_DIRECTION, REJ_PLACED
};
int      g_rej[SRHTF_NREJ];

// One row per setup actually placed: the features that were true when the
// decision was made, and what it went on to earn. This is the training and
// evaluation set for any filter - a model, a rule, anything - and nothing can
// be judged without it. Features are chosen to be what a retail CFD feed can
// actually supply: no order book, no depth, no taker flow.
struct SetupRec
{
   ulong    order;        // pending order ticket, to match against history
   datetime t;
   int      hour, dow;
   int      bias, b1, b2, b3;
   double   riskPts, atrPts, spreadPts;
   double   liqRR;        // RR to the HTF liquidity target, BEFORE any fallback
   double   rangePos;     // 0 = at range low, 1 = at range high
   double   ret5, ret20, ret100;   // entry-TF returns in points
   double   lots;
   double   riskUsd;
};
#define SRHTF_MAXSETUP 4000
SetupRec g_setup[SRHTF_MAXSETUP];
int      g_nSetup = 0;

// Defined further down, beside the dumper it feeds; declared here because
// TryPlaceSetup calls it and MQL5 needs the declaration first.
void RecordSetup(ulong order, ENUM_ORDER_TYPE type, double entry, double sl,
                 double risk, double lots, double liqRR,
                 double rHi, double rLo, double bid, double ask);

double RetPts(int bars)
{
   double now = iClose(_Symbol, InpEntryTF, 1);
   double then = iClose(_Symbol, InpEntryTF, 1 + bars);
   if(now <= 0 || then <= 0) return 0;
   return (now - then) / _Point;
}
string RejName(int i)
{
   switch(i)
   {
      case REJ_NO_BIAS:      return "no HTF bias";
      case REJ_EXPOSURE:     return "already exposed";
      case REJ_MAX_TRADES:   return "max trades today";
      case REJ_MAX_LOSSES:   return "max losses today";
      case REJ_SPREAD:       return "spread too wide";
      case REJ_NO_RANGE:     return "no dealing range";
      case REJ_PD_LOCATION:  return "wrong side of equilibrium";
      case REJ_NO_SWEEP:     return "no sweep setup";
      case REJ_STOPS_LEVEL:  return "entry inside stops level";
      case REJ_SWEEP_REUSED: return "sweep already used";
      case REJ_SL_SIZE:      return "SL size out of range";
      case REJ_RR_GATE:      return "below InpMinRR gate";
      case REJ_ATR_FLOOR:    return "ATR below floor";
      case REJ_DIRECTION:    return "blocked by InpDirection";
      case REJ_PLACED:       return "ORDER PLACED";
   }
   return "?";
}
void Rej(ENUM_SRHTF_REJ r) { g_rej[r]++; }

//=================== HELPERS ===================
string GVName(string s) { return "SRHTF_" + IntegerToString(InpMagic) + "_" + s; }

double NormPrice(double p)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0) p = MathRound(p / ts) * ts;
   return NormalizeDouble(p, _Digits);
}

string BiasStr(int b) { return b == 1 ? "BULL" : (b == -1 ? "BEAR" : "--"); }

bool IsSwingHigh(ENUM_TIMEFRAMES tf, int i, int s)
{
   double h = iHigh(_Symbol, tf, i);
   for(int k = 1; k <= s; k++)
   {
      if(iHigh(_Symbol, tf, i - k) >= h) return false;
      if(iHigh(_Symbol, tf, i + k) >  h) return false;
   }
   return true;
}

bool IsSwingLow(ENUM_TIMEFRAMES tf, int i, int s)
{
   double l = iLow(_Symbol, tf, i);
   for(int k = 1; k <= s; k++)
   {
      if(iLow(_Symbol, tf, i - k) <= l) return false;
      if(iLow(_Symbol, tf, i + k) <  l) return false;
   }
   return true;
}

// +1 bullish structure, -1 bearish, 0 unclear
int TFBias(ENUM_TIMEFRAMES tf)
{
   int bars = iBars(_Symbol, tf);
   if(bars < InpSwingStrength * 2 + 10) return 0;
   int lim = MathMin(InpSwingLookback, bars - InpSwingStrength - 2);

   double sh[2], sl[2];
   int nh = 0, nl = 0;
   for(int i = InpSwingStrength + 1; i < lim && (nh < 2 || nl < 2); i++)
   {
      if(nh < 2 && IsSwingHigh(tf, i, InpSwingStrength)) sh[nh++] = iHigh(_Symbol, tf, i);
      if(nl < 2 && IsSwingLow(tf, i, InpSwingStrength))  sl[nl++] = iLow(_Symbol, tf, i);
   }
   if(nh < 2 || nl < 2) return 0;

   double c = iClose(_Symbol, tf, 1);
   if(c > sh[0]) return 1;            // broke last swing high
   if(c < sl[0]) return -1;           // broke last swing low
   if(sh[0] > sh[1] && sl[0] > sl[1]) return 1;   // HH + HL
   if(sh[0] < sh[1] && sl[0] < sl[1]) return -1;  // LH + LL
   return 0;
}

int ComputeBias()
{
   g_b1 = TFBias(InpTF1);
   g_b2 = TFBias(InpTF2);
   g_b3 = TFBias(InpTF3);
   int up = (g_b1 == 1 ? 1 : 0) + (g_b2 == 1 ? 1 : 0) + (g_b3 == 1 ? 1 : 0);
   int dn = (g_b1 == -1 ? 1 : 0) + (g_b2 == -1 ? 1 : 0) + (g_b3 == -1 ? 1 : 0);
   int need = MathMax(1, MathMin(3, InpMinAgree));
   // "how many agree" and "none may disagree" are separate questions. v1.00
   // hard-coded the second as dn==0, which dominated the first: InpMinAgree
   // 1, 2 and 3 selected almost the same bars, so the grid could not measure
   // the A+ premise at all. InpMaxOppose=0 keeps the old behaviour.
   int allowOpp = MathMax(0, MathMin(2, InpMaxOppose));
   if(up >= need && dn <= allowOpp) return 1;
   if(dn >= need && up <= allowOpp) return -1;
   return 0;
}

bool GetRange(double &hi, double &lo)
{
   int ih = iHighest(_Symbol, InpRangeTF, MODE_HIGH, InpRangeBars, 1);
   int il = iLowest(_Symbol, InpRangeTF, MODE_LOW, InpRangeBars, 1);
   if(ih < 0 || il < 0) return false;
   hi = iHigh(_Symbol, InpRangeTF, ih);
   lo = iLow(_Symbol, InpRangeTF, il);
   return hi > lo;
}

bool InKillzone()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent() - InpServerGMTOffset * 3600, t);
   if(t.day_of_week == 0 || t.day_of_week == 6) return false;
   int h = t.hour;
   bool lon = InpLondon && h >= InpLonStart && h < InpLonEnd;
   bool ny  = InpNY     && h >= InpNYStart  && h < InpNYEnd;
   // Asia can wrap midnight (e.g. 23 -> 3), so test the wrap explicitly
   // rather than letting start >= end silently match nothing.
   bool asia = false;
   if(InpAsia)
      asia = (InpAsiaStart <= InpAsiaEnd) ? (h >= InpAsiaStart && h < InpAsiaEnd)
                                          : (h >= InpAsiaStart || h < InpAsiaEnd);
   return lon || ny || asia;
}

bool FridayCutoff()
{
   if(!InpFridayClose) return false;
   MqlDateTime t;
   TimeToStruct(TimeCurrent() - InpServerGMTOffset * 3600, t);
   return (t.day_of_week == 5 && t.hour >= InpFridayHourUTC);
}

bool NewsBlocked()
{
   if(!InpNewsFilter || MQLInfoInteger(MQL_TESTER)) return false;
   MqlCalendarValue vals[];
   datetime now = TimeTradeServer();
   if(!CalendarValueHistory(vals, now - InpNewsMinsAfter * 60,
                            now + InpNewsMinsBefore * 60, NULL, "USD"))
      return false;
   for(int i = 0; i < ArraySize(vals); i++)
   {
      MqlCalendarEvent ev;
      if(CalendarEventById(vals[i].event_id, ev) &&
         ev.importance == CALENDAR_IMPORTANCE_HIGH)
         return true;
   }
   return false;
}

bool HasExposure()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic) return true;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic) return true;
   }
   return false;
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         trade.PositionClose(t);
   }
}

void DeletePendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic)
         trade.OrderDelete(t);
   }
}

//=================== DAY / GUARDS ===================
void CheckNewDay()
{
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(ds == g_dayStart) return;
   g_dayStart = ds;

   string key = IntegerToString((long)ds);
   string gvEq = GVName("deq_" + key);
   if(GlobalVariableCheck(gvEq))
      g_dayStartEq = GlobalVariableGet(gvEq);
   else
   {
      g_dayStartEq = MathMax(AccountInfoDouble(ACCOUNT_BALANCE),
                             AccountInfoDouble(ACCOUNT_EQUITY));
      GlobalVariableSet(gvEq, g_dayStartEq);
   }
   g_dayHalted = GlobalVariableCheck(GVName("dh_" + key));
   g_dayBanked = GlobalVariableCheck(GVName("dt_" + key));
   CountToday();
}

bool RunGuards()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_accHalted) { CloseAll(); DeletePendings(); return false; }

   if(eq <= InpInitialBalance * (1.0 - InpMaxGuardPct / 100.0))
   {
      CloseAll(); DeletePendings();
      g_accHalted = true;
      g_haltReason = 1; g_haltTime = TimeCurrent();
      GlobalVariableSet(GVName("acc_halt"), 1);
      g_status = "MAX LOSS GUARD hit - EA stopped";
      Print(g_status);
      return false;
   }
   if(InpTargetLock && eq >= InpInitialBalance * (1.0 + InpTargetPct / 100.0))
   {
      CloseAll(); DeletePendings();
      g_accHalted = true;
      g_haltReason = 2; g_haltTime = TimeCurrent();
      GlobalVariableSet(GVName("acc_halt"), 1);
      g_status = "TARGET reached - EA locked";
      Print(g_status);
      return false;
   }
   if(g_dayHalted) { g_status = "Daily guard active - resumes next day"; return false; }

   if(eq <= g_dayStartEq * (1.0 - InpDailyGuardPct / 100.0))
   {
      CloseAll(); DeletePendings();
      g_dayHalted = true;
      GlobalVariableSet(GVName("dh_" + IntegerToString((long)g_dayStart)), 1);
      g_status = "DAILY GUARD hit - stopped for today";
      Print(g_status);
      return false;
   }

   // Checked AFTER the daily loss guard above, and deliberately: a banked day
   // can still be holding an open position, and returning early here would
   // leave nothing watching it drag equity through the daily limit.
   // Daily target, checked on REALISED profit. Floating profit would flip this
   // on and off as price moved. Open positions are left to reach their own TP
   // or SL - only new entries stop, and the pendings are pulled.
   if(InpDailyTargetUSD > 0 && !g_dayBanked && g_profitToday >= InpDailyTargetUSD)
   {
      DeletePendings();
      g_dayBanked = true;
      GlobalVariableSet(GVName("dt_" + IntegerToString((long)g_dayStart)), 1);
      g_status = StringFormat("DAILY TARGET %.0f made (%.2f) - done for today",
                              InpDailyTargetUSD, g_profitToday);
      Print(g_status);
   }
   if(g_dayBanked)
   {
      g_status = StringFormat("Daily target banked (%.2f) - resumes next day", g_profitToday);
      return false;
   }
   return true;
}

void CountToday()
{
   g_tradesToday = 0; g_lossesToday = 0; g_profitToday = 0;
   if(!HistorySelect(g_dayStart, TimeCurrent() + 60)) return;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      long e = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(e == DEAL_ENTRY_IN) g_tradesToday++;
      else if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY)
      {
         double net = HistoryDealGetDouble(d, DEAL_PROFIT) +
                      HistoryDealGetDouble(d, DEAL_SWAP) +
                      HistoryDealGetDouble(d, DEAL_COMMISSION);
         if(net < 0) g_lossesToday++;
         g_profitToday += net;
      }
   }
}

//=================== SETUP DETECTION ===================
// Most recently COMPLETED Asian range, cached per day. Returns false until one
// exists, so an EA started mid-session cannot invent a level.
datetime g_asiaDay = 0;
double   g_asiaHi  = 0, g_asiaLo = 0;
bool     g_asiaOk  = false;
bool AsianRange(double &hi, double &lo)
{
   long off = (long)InpServerGMTOffset * 3600;
   datetime nowG = (datetime)((long)TimeCurrent() - off);
   MqlDateTime n; TimeToStruct(nowG, n);
   datetime dayG = (datetime)(((long)nowG / 86400) * 86400);
   if(n.hour < InpAsiaRangeEnd) dayG -= 86400;      // today's window not finished
   if(dayG == g_asiaDay) { hi = g_asiaHi; lo = g_asiaLo; return g_asiaOk; }

   double h = -DBL_MAX, l = DBL_MAX; int seen = 0;
   int bars = (int)MathMin(5000, iBars(_Symbol, InpEntryTF));
   for(int i = 1; i < bars; i++)
   {
      datetime bt = iTime(_Symbol, InpEntryTF, i);
      if(bt == 0) break;
      datetime bg = (datetime)((long)bt - off);
      datetime bday = (datetime)(((long)bg / 86400) * 86400);
      if(bday > dayG) continue;
      if(bday < dayG) break;
      MqlDateTime b; TimeToStruct(bg, b);
      bool inWin = (InpAsiaRangeStart <= InpAsiaRangeEnd)
                   ? (b.hour >= InpAsiaRangeStart && b.hour < InpAsiaRangeEnd)
                   : (b.hour >= InpAsiaRangeStart || b.hour < InpAsiaRangeEnd);
      if(!inWin) continue;
      h = MathMax(h, iHigh(_Symbol, InpEntryTF, i));
      l = MathMin(l, iLow (_Symbol, InpEntryTF, i));
      seen++;
   }
   g_asiaDay = dayG; g_asiaOk = (seen > 0 && h > l);
   g_asiaHi = h; g_asiaLo = l;
   hi = h; lo = l;
   return g_asiaOk;
}

// Bullish: sweep of M5 sell-side liquidity, entry above prior structure high
bool FindBullSetup(double &entry, double &sl, datetime &sweepTime)
{
   double aHi = 0, aLo = 0;
   if(InpSweepAsianRange && !AsianRange(aHi, aLo)) return false;
   for(int k = 1; k <= InpSweepWindow; k++)
   {
      int idx = iLowest(_Symbol, InpEntryTF, MODE_LOW, InpSweepLookback, k + 1);
      if(idx < 0) return false;
      double pool = InpSweepAsianRange ? aLo : iLow(_Symbol, InpEntryTF, idx);
      double lk   = iLow(_Symbol, InpEntryTF, k);
      double ck   = iClose(_Symbol, InpEntryTF, k);
      if(!(lk < pool && ck > pool)) continue;

      // Sweep low must still be the lowest point since the sweep
      int lowIdx = iLowest(_Symbol, InpEntryTF, MODE_LOW, k, 1);
      if(lowIdx < 0 || iLow(_Symbol, InpEntryTF, lowIdx) < lk) continue;

      // Structure high between the pool and the sweep
      int hiIdx = iHighest(_Symbol, InpEntryTF, MODE_HIGH, idx - k + 1, k);
      if(hiIdx < 0) continue;
      double structHi = iHigh(_Symbol, InpEntryTF, hiIdx);

      // Already broken -> missed, don't chase
      for(int j = 1; j < k; j++)
         if(iClose(_Symbol, InpEntryTF, j) > structHi) return false;

      entry     = structHi + InpEntryBufPts * _Point;
      sl        = lk - InpSLBufPts * _Point;
      sweepTime = iTime(_Symbol, InpEntryTF, k);
      return true;
   }
   return false;
}

// Bearish: sweep of M5 buy-side liquidity, entry below prior structure low
bool FindBearSetup(double &entry, double &sl, datetime &sweepTime)
{
   double aHi = 0, aLo = 0;
   if(InpSweepAsianRange && !AsianRange(aHi, aLo)) return false;
   for(int k = 1; k <= InpSweepWindow; k++)
   {
      int idx = iHighest(_Symbol, InpEntryTF, MODE_HIGH, InpSweepLookback, k + 1);
      if(idx < 0) return false;
      double pool = InpSweepAsianRange ? aHi : iHigh(_Symbol, InpEntryTF, idx);
      double hk   = iHigh(_Symbol, InpEntryTF, k);
      double ck   = iClose(_Symbol, InpEntryTF, k);
      if(!(hk > pool && ck < pool)) continue;

      int hiIdx = iHighest(_Symbol, InpEntryTF, MODE_HIGH, k, 1);
      if(hiIdx < 0 || iHigh(_Symbol, InpEntryTF, hiIdx) > hk) continue;

      int loIdx = iLowest(_Symbol, InpEntryTF, MODE_LOW, idx - k + 1, k);
      if(loIdx < 0) continue;
      double structLo = iLow(_Symbol, InpEntryTF, loIdx);

      for(int j = 1; j < k; j++)
         if(iClose(_Symbol, InpEntryTF, j) < structLo) return false;

      entry     = structLo - InpEntryBufPts * _Point;
      sl        = hk + InpSLBufPts * _Point;
      sweepTime = iTime(_Symbol, InpEntryTF, k);
      return true;
   }
   return false;
}

double CalcLots(ENUM_ORDER_TYPE type, double entry, double sl)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   double pl = 0;
   ENUM_ORDER_TYPE calcType = (type == ORDER_TYPE_BUY_STOP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(calcType, _Symbol, 1.0, entry, sl, pl)) return 0;
   double lossPerLot = MathAbs(pl);
   if(lossPerLot <= 0) return 0;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), InpMaxLots);

   double lots = riskMoney / lossPerLot;
   lots = MathFloor(lots / step) * step;
   if(lots < vmin) return 0;          // never round UP past the risk budget
   lots = MathMin(lots, vmax);
   int vd = (int)MathMax(0, MathRound(-MathLog10(step)));
   lots = NormalizeDouble(lots, vd);

   double margin = 0;
   if(OrderCalcMargin(calcType, _Symbol, lots, entry, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9) return 0;
   return lots;
}

void TryPlaceSetup()
{
   if(g_bias == 0) { g_status = "No HTF agreement - standing aside"; Rej(REJ_NO_BIAS); return; }
   if(HasExposure()) { Rej(REJ_EXPOSURE); return; }
   if(g_tradesToday >= InpMaxTradesDay) { g_status = "Max trades today"; Rej(REJ_MAX_TRADES); return; }
   if(g_lossesToday >= InpMaxLossesDay) { g_status = "Max losses today"; Rej(REJ_MAX_LOSSES); return; }

   if((g_bias == 1  && InpDirection == SRHTF_SHORT_ONLY) ||
      (g_bias == -1 && InpDirection == SRHTF_LONG_ONLY))
   { g_status = "Direction blocked by InpDirection"; Rej(REJ_DIRECTION); return; }

   if(InpMinATRPts > 0)
   {
      double atr[1];
      if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1)
         if(atr[0] / _Point < InpMinATRPts)
         { g_status = StringFormat("ATR %.0f pts below floor %.0f", atr[0]/_Point, InpMinATRPts);
           Rej(REJ_ATR_FLOOR); return; }
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if((ask - bid) / _Point > InpMaxSpreadPts) { g_status = "Spread too wide"; Rej(REJ_SPREAD); return; }

   double rHi, rLo;
   if(!GetRange(rHi, rLo)) { Rej(REJ_NO_RANGE); return; }
   double eqm = (rHi + rLo) / 2.0;
   double stopsLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   double entry, sl, tp;
   datetime sweepT;
   ENUM_ORDER_TYPE type;

   if(g_bias == 1)
   {
      if(InpUsePDFilter && bid >= eqm) { g_status = "Bull bias, price in premium - waiting"; Rej(REJ_PD_LOCATION); return; }
      if(!FindBullSetup(entry, sl, sweepT)) { g_status = "Bull bias - waiting for sweep"; Rej(REJ_NO_SWEEP); return; }
      type = ORDER_TYPE_BUY_STOP;
      if(entry - ask <= stopsLvl) { Rej(REJ_STOPS_LEVEL); return; }
   }
   else
   {
      if(InpUsePDFilter && ask <= eqm) { g_status = "Bear bias, price in discount - waiting"; Rej(REJ_PD_LOCATION); return; }
      if(!FindBearSetup(entry, sl, sweepT)) { g_status = "Bear bias - waiting for sweep"; Rej(REJ_NO_SWEEP); return; }
      type = ORDER_TYPE_SELL_STOP;
      if(bid - entry <= stopsLvl) { Rej(REJ_STOPS_LEVEL); return; }
   }

   if(sweepT == g_lastSweepTime) { Rej(REJ_SWEEP_REUSED); return; }   // same setup already used

   double risk = MathAbs(entry - sl);
   if(risk < InpMinSLPts * _Point || risk > InpMaxSLPts * _Point)
   { g_status = "Setup stop size out of range - skipped"; Rej(REJ_SL_SIZE); g_lastSweepTime = sweepT; return; }

   // InpMinRR is the GATE (is this setup clear enough to take?) and InpTPRMult
   // is the TARGET (how far do we actually aim?). v1.10 used one input for
   // both, so "only take 3R-clear setups but exit at 2R" was inexpressible -
   // and 2.0 beat 3.0 on identical trades, which is what made it worth
   // separating. 0 keeps the old behaviour.
   double tpR = (InpTPRMult > 0) ? InpTPRMult : InpMinRR;
   double fixedTP = (type == ORDER_TYPE_BUY_STOP) ? entry + tpR * risk
                                                  : entry - tpR * risk;
   double liqRR = 0;   // RR to HTF liquidity as it was BEFORE any fallback
   if(InpTargetLiquidity)
   {
      tp = (type == ORDER_TYPE_BUY_STOP) ? rHi - InpTPBufPts * _Point
                                         : rLo + InpTPBufPts * _Point;
      double rr = MathAbs(tp - entry) / risk;
      liqRR = rr;
      bool wrongSide = (type == ORDER_TYPE_BUY_STOP) ? (tp <= entry) : (tp >= entry);
      if(wrongSide || rr < InpMinRR)
      {
         // This skip is what held v1.00 to 5 trades in nine months: the HTF
         // range extreme is rarely InpMinRR or more beyond entry, so a valid
         // sweep was thrown away for want of a distant target. With the
         // fallback the setup is still taken, at a fixed InpMinRR target.
         if(!InpTPFallback)
         {
            g_status = StringFormat("Setup RR %.2f < %.1f - skipped", rr, InpMinRR);
            Rej(REJ_RR_GATE);
            g_lastSweepTime = sweepT;
            return;
         }
         tp = fixedTP;
         g_status = StringFormat("Liquidity RR %.2f < %.1f - fixed %.1fR target", rr, InpMinRR, tpR);
      }
   }
   else
      tp = fixedTP;

   entry = NormPrice(entry); sl = NormPrice(sl); tp = NormPrice(tp);
   double lots = CalcLots(type, entry, sl);
   if(lots <= 0) { g_status = "Lot size below minimum for this risk - skipped"; g_lastSweepTime = sweepT; return; }

   bool ok = (type == ORDER_TYPE_BUY_STOP)
             ? trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment)
             : trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment);

   if(ok)
   {
      g_lastSweepTime = sweepT;
      Rej(REJ_PLACED);
      if(InpSetupCSV)
         RecordSetup(trade.ResultOrder(), type, entry, sl, risk, lots,
                     liqRR, rHi, rLo, bid, ask);
      g_status = StringFormat("%s placed @ %.2f SL %.2f TP %.2f lots %.2f",
                  type == ORDER_TYPE_BUY_STOP ? "BUY STOP" : "SELL STOP", entry, sl, tp, lots);
      Print(g_status);
   }
   else
      Print("Order failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

//=================== MANAGEMENT ===================
void ManagePendings(bool allowed)
{
   int life = InpOrderExpiryBars * PeriodSeconds(InpEntryTF);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      long     type  = OrderGetInteger(ORDER_TYPE);
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      double   osl   = OrderGetDouble(ORDER_SL);

      bool kill = !allowed || (TimeCurrent() - setup > life);
      if(type == ORDER_TYPE_BUY_STOP  && (g_bias != 1  || bid <= osl)) kill = true;  // bias flip / sweep low broken
      if(type == ORDER_TYPE_SELL_STOP && (g_bias != -1 || ask >= osl)) kill = true;

      if(kill && trade.OrderDelete(t)) Print("Pending ", t, " cancelled");
   }
}

// Scales out at BE_R and trails the remainder. The partial and the BE move
// happen in the SAME branch (sl still beyond open), so each fires exactly once
// per position without needing per-ticket state: moving the SL to BE is itself
// what closes the branch.
void PartialOut(ulong ticket, double volume)
{
   if(InpPartialPct <= 0) return;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double want = volume * InpPartialPct / 100.0;
   want = MathFloor(want / step) * step;
   // Both halves must survive as tradeable volume: a partial that leaves less
   // than the minimum behind would be rejected, and one below the minimum
   // itself cannot be sent at all.
   if(want < vmin || volume - want < vmin) return;
   if(trade.PositionClosePartial(ticket, want))
      Print(StringFormat("Partial out %.2f of %.2f at BE_R", want, volume));
}

void ManageBreakEven()
{
   double stopsLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double atr[1];
   bool haveATR = (InpTrailATRMult > 0 && g_atrHandle != INVALID_HANDLE &&
                   CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      if(sl == 0) continue;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(sl < open)
         {
            if(bid - open >= InpBE_R * (open - sl))
            {
               double nsl = NormPrice(open + InpBEOffsetPts * _Point);
               if(nsl < bid - stopsLvl && trade.PositionModify(t, nsl, tp))
                  PartialOut(t, vol);
            }
         }
         else if(haveATR)                       // past BE - trail the remainder
         {
            double nsl = NormPrice(bid - InpTrailATRMult * atr[0]);
            if(nsl > sl && nsl < bid - stopsLvl) trade.PositionModify(t, nsl, tp);
         }
      }
      else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(sl > open)
         {
            if(open - ask >= InpBE_R * (sl - open))
            {
               double nsl = NormPrice(open - InpBEOffsetPts * _Point);
               if(nsl > ask + stopsLvl && trade.PositionModify(t, nsl, tp))
                  PartialOut(t, vol);
            }
         }
         else if(haveATR)
         {
            double nsl = NormPrice(ask + InpTrailATRMult * atr[0]);
            if(nsl < sl && nsl > ask + stopsLvl) trade.PositionModify(t, nsl, tp);
         }
      }
   }
}

void UpdatePanel(bool kz)
{
   Comment(StringFormat(
      "SR HTF Stop-Entry EA\n"
      "Bias  %s:%s  %s:%s  %s:%s  ->  %s\n"
      "Killzone: %s   News block: %s\n"
      "Day start eq: %.2f   Daily guard at: %.2f\n"
      "Max guard at: %.2f   Target: %s\n"
      "Trades today: %d/%d   Losses: %d/%d\n"
      "P/L today: %.2f   Day target: %s\n"
      "Status: %s",
      EnumToString(InpTF1), BiasStr(g_b1), EnumToString(InpTF2), BiasStr(g_b2),
      EnumToString(InpTF3), BiasStr(g_b3), BiasStr(g_bias),
      kz ? "YES" : "no", g_news ? "YES" : "no",
      g_dayStartEq, g_dayStartEq * (1.0 - InpDailyGuardPct / 100.0),
      InpInitialBalance * (1.0 - InpMaxGuardPct / 100.0),
      InpTargetLock ? DoubleToString(InpInitialBalance * (1.0 + InpTargetPct / 100.0), 2) : "off",
      g_tradesToday, InpMaxTradesDay, g_lossesToday, InpMaxLossesDay,
      g_profitToday,
      InpDailyTargetUSD > 0 ? DoubleToString(InpDailyTargetUSD, 0) + (g_dayBanked ? " BANKED" : "")
                            : "off",
      g_status));
}

//=================== EVENTS ===================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);

   if(InpResetState) GlobalVariablesDeleteAll(GVName(""));
   g_accHalted = GlobalVariableCheck(GVName("acc_halt"));

   ArrayInitialize(g_rej, 0);

   // A .set line of "InpTF1=PERIOD_H1" does not parse - MT5 stores enums as
   // integers, the value lands as 0 = PERIOD_CURRENT, and the EA quietly runs
   // its three "higher" timeframes on the chart timeframe instead. That is
   // indistinguishable from a working run in the report, so refuse it here.
   if(InpTF1 == PERIOD_CURRENT || InpTF2 == PERIOD_CURRENT || InpTF3 == PERIOD_CURRENT ||
      InpRangeTF == PERIOD_CURRENT || InpEntryTF == PERIOD_CURRENT)
   {
      Print("REFUSING TO RUN: a timeframe input resolved to PERIOD_CURRENT (0).");
      Print("  A .set file must give enums as INTEGERS, not names:");
      Print("  M1=1  M5=5  M15=15  M30=30  H1=16385  H4=16388  D1=16408");
      Print(StringFormat("  got TF1=%d TF2=%d TF3=%d RangeTF=%d EntryTF=%d",
            InpTF1, InpTF2, InpTF3, InpRangeTF, InpEntryTF));
      return INIT_FAILED;
   }
   Print(StringFormat("SR_HTF v1.30 resolved: bias %s/%s/%s  range %s  entry %s  dir %s  minAgree %d maxOpp %d",
         EnumToString(InpTF1), EnumToString(InpTF2), EnumToString(InpTF3),
         EnumToString(InpRangeTF), EnumToString(InpEntryTF),
         EnumToString(InpDirection), InpMinAgree, InpMaxOppose));
   if(InpMinATRPts > 0 || InpTrailATRMult > 0)
   {
      g_atrHandle = iATR(_Symbol, InpEntryTF, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Print("iATR failed - InpMinATRPts and InpTrailATRMult need it, refusing to run half-configured");
         return INIT_FAILED;
      }
   }

   CheckNewDay();
   g_bias = ComputeBias();
   g_news = NewsBlocked();
   return INIT_SUCCEEDED;
}

void RecordSetup(ulong order, ENUM_ORDER_TYPE type, double entry, double sl,
                 double risk, double lots, double liqRR,
                 double rHi, double rLo, double bid, double ask)
{
   if(g_nSetup >= SRHTF_MAXSETUP) return;
   MqlDateTime t; TimeToStruct(TimeCurrent() - InpServerGMTOffset * 3600, t);

   double atrPts = 0;
   if(g_atrHandle != INVALID_HANDLE)
   {
      double a[1];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, a) == 1) atrPts = a[0] / _Point;
   }

   SetupRec r;
   r.order     = order;
   r.t         = TimeCurrent();
   r.hour      = t.hour;
   r.dow       = t.day_of_week;
   r.bias      = g_bias;
   r.b1        = g_b1;
   r.b2        = g_b2;
   r.b3        = g_b3;
   r.riskPts   = risk / _Point;
   r.atrPts    = atrPts;
   r.spreadPts = (ask - bid) / _Point;
   r.liqRR     = liqRR;
   r.rangePos  = (rHi > rLo) ? (bid - rLo) / (rHi - rLo) : 0;
   r.ret5      = RetPts(5);
   r.ret20     = RetPts(20);
   r.ret100    = RetPts(100);
   r.lots      = lots;
   r.riskUsd   = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   g_setup[g_nSetup++] = r;
}

// Resolve each setup to what it actually earned, and write one row. Matching is
// by DEAL_ORDER on the entry deal: that is our pending order's ticket. From
// there DEAL_POSITION_ID collects every deal of that position, so a scaled-out
// trade is summed rather than counted as its first exit only.
void DumpSetups()
{
   if(g_nSetup == 0) { Print("SETUPS: none recorded"); return; }
   if(!HistorySelect(0, TimeCurrent() + 86400)) { Print("SETUPS: HistorySelect failed"); return; }
   int nd = HistoryDealsTotal();

   int h = FileOpen("SRHTF_setups.csv", FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) { Print("SETUPS: cannot write, error ", GetLastError()); return; }
   FileWrite(h, "time", "hour", "dow", "bias", "b1", "b2", "b3", "riskPts", "atrPts",
             "spreadPts", "liqRR", "rangePos", "ret5", "ret20", "ret100",
             "lots", "riskUsd", "filled", "profitUsd", "R");

   int filled = 0;
   for(int i = 0; i < g_nSetup; i++)
   {
      long posId = -1;
      for(int d = 0; d < nd; d++)
      {
         ulong tk = HistoryDealGetTicket(d);
         if(tk == 0) continue;
         if(HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if((ulong)HistoryDealGetInteger(tk, DEAL_ORDER) != g_setup[i].order) continue;
         posId = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
         break;
      }

      double profit = 0;
      if(posId >= 0)
      {
         filled++;
         for(int d = 0; d < nd; d++)
         {
            ulong tk = HistoryDealGetTicket(d);
            if(tk == 0) continue;
            if(HistoryDealGetInteger(tk, DEAL_POSITION_ID) != posId) continue;
            profit += HistoryDealGetDouble(tk, DEAL_PROFIT)
                    + HistoryDealGetDouble(tk, DEAL_SWAP)
                    + HistoryDealGetDouble(tk, DEAL_COMMISSION);
         }
      }

      // An unfilled pending is a real outcome, not a missing row: the stop was
      // never taken out. R is 0 for those and `filled` says which is which.
      double R = (g_setup[i].riskUsd > 0) ? profit / g_setup[i].riskUsd : 0;
      FileWrite(h, TimeToString(g_setup[i].t, TIME_DATE | TIME_MINUTES),
                IntegerToString(g_setup[i].hour), IntegerToString(g_setup[i].dow),
                IntegerToString(g_setup[i].bias), IntegerToString(g_setup[i].b1),
                IntegerToString(g_setup[i].b2), IntegerToString(g_setup[i].b3),
                DoubleToString(g_setup[i].riskPts, 1), DoubleToString(g_setup[i].atrPts, 1),
                DoubleToString(g_setup[i].spreadPts, 1), DoubleToString(g_setup[i].liqRR, 3),
                DoubleToString(g_setup[i].rangePos, 4), DoubleToString(g_setup[i].ret5, 1),
                DoubleToString(g_setup[i].ret20, 1), DoubleToString(g_setup[i].ret100, 1),
                DoubleToString(g_setup[i].lots, 2), DoubleToString(g_setup[i].riskUsd, 2),
                posId >= 0 ? "1" : "0", DoubleToString(profit, 2), DoubleToString(R, 3));
   }
   FileClose(h);
   Print(StringFormat("SETUPS: %d recorded, %d filled -> SRHTF_setups.csv", g_nSetup, filled));
}

void DumpDiag()
{
   int considered = 0;
   for(int i = 0; i < SRHTF_NREJ; i++) considered += g_rej[i];
   if(considered == 0) { Print("DIAG: TryPlaceSetup was never reached - check killzone, guards, news"); return; }

   Print("=== SR_HTF setup diagnostic: ", considered, " evaluations ===");
   for(int i = 0; i < SRHTF_NREJ; i++)
      if(g_rej[i] > 0)
         Print(StringFormat("  %-28s %6d  %5.1f%%", RejName(i), g_rej[i],
                            100.0 * g_rej[i] / considered));

   // Fixed filename: the EA cannot know which .set it was given, so the runner
   // renames this per pass. Overwritten each run on purpose.
   int h = FileOpen("SRHTF_diag.csv", FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) { Print("DIAG: could not write SRHTF_diag.csv, error ", GetLastError()); return; }
   // The resolved inputs go in the file as well. The tester report echoes the
   // .set as given, so it cannot show a value that failed to parse - the two
   // disagreeing is exactly the bug this grid went looking for.
   FileWrite(h, "resolved", "value", "raw");
   FileWrite(h, "InpTF1", EnumToString(InpTF1), IntegerToString(InpTF1));
   FileWrite(h, "InpTF2", EnumToString(InpTF2), IntegerToString(InpTF2));
   FileWrite(h, "InpTF3", EnumToString(InpTF3), IntegerToString(InpTF3));
   FileWrite(h, "InpRangeTF", EnumToString(InpRangeTF), IntegerToString(InpRangeTF));
   FileWrite(h, "InpEntryTF", EnumToString(InpEntryTF), IntegerToString(InpEntryTF));
   FileWrite(h, "InpDirection", EnumToString(InpDirection), IntegerToString(InpDirection));
   FileWrite(h, "InpMinAgree", IntegerToString(InpMinAgree), "");
   FileWrite(h, "InpMaxOppose", IntegerToString(InpMaxOppose), "");
   FileWrite(h, "InpMinRR", DoubleToString(InpMinRR, 2), "");
   FileWrite(h, "InpTPRMult", DoubleToString(InpTPRMult, 2), "");
   FileWrite(h, "", "", "");
   FileWrite(h, "reason", "count", "pct");
   for(int i = 0; i < SRHTF_NREJ; i++)
      FileWrite(h, RejName(i), IntegerToString(g_rej[i]),
                DoubleToString(100.0 * g_rej[i] / considered, 2));
   FileClose(h);
}

void OnDeinit(const int reason)
{
   Comment("");
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(InpDiagCSV) DumpDiag();
   if(InpSetupCSV) DumpSetups();
}

// Optimisation criterion. MT5's built-in choices all rank on profit, Sharpe or
// drawdown, and none of them describe a prop challenge, where the outcome is
// binary and asymmetric: reaching the target is a pass, touching the static
// floor is a dead account that no amount of profit elsewhere makes up for.
// Ranking a search on "max balance" would hand back the sets that blow up
// spectacularly in one year and recover in another.
//
//   floor hit        -1000      nothing recovers from this
//   no trades        -2000      worse than losing: it has not been tested
//   target reached   +1000 and faster is better
//   neither          the year's return in %, which is 0..10 by construction
double OnTester()
{
   if(HistorySelect(0, TimeCurrent() + 86400))
   {
      int deals = 0;
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) deals++;
      }
      if(deals == 0) return -2000.0;
   }

   if(g_haltReason == 1) return -1000.0;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double pct = (InpInitialBalance > 0) ? (eq - InpInitialBalance) / InpInitialBalance * 100.0 : 0;

   if(g_haltReason == 2)
   {
      // Reward reaching it EARLY: a target made in March leaves the rest of
      // the year free, and in a challenge it is time that costs money.
      double days = (g_haltTime > 0) ? (double)(g_haltTime - g_dayStart) / 86400.0 : 0;
      double doy  = 0;
      MqlDateTime h; TimeToStruct(g_haltTime, h);
      doy = h.day_of_year;
      return 1000.0 + (366.0 - doy);
   }
   return pct;
}

void OnTick()
{
   CheckNewDay();
   bool kz = InKillzone();

   // BE runs BEFORE the guards, not after. A banked day (daily target made)
   // deliberately leaves its open position alone to reach its own TP, and the
   // guards return false for the rest of the day - so managing break-even
   // after them would abandon that position unmanaged until it closed.
   if(InpBreakEven) ManageBreakEven();

   if(!RunGuards()) { UpdatePanel(kz); return; }

   datetime bt = iTime(_Symbol, InpEntryTF, 0);
   bool newBar = (bt != g_lastBar && bt != 0);
   if(newBar)
   {
      g_lastBar = bt;
      g_bias = ComputeBias();
      g_news = NewsBlocked();
      CountToday();
   }

   bool fri = FridayCutoff();
   if(fri) { CloseAll(); DeletePendings(); g_status = "Friday cutoff - flat for weekend"; }

   ManagePendings(kz && !fri && !g_news);

   if(newBar && kz && !fri && !g_news) TryPlaceSetup();
   else if(newBar && !kz && !fri) g_status = "Outside killzone";

   UpdatePanel(kz);
}
//+------------------------------------------------------------------+
