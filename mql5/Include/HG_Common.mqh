//+------------------------------------------------------------------+
//|                                                  HG_Common.mqh   |
//|                        Institutional HFT Trading System            |
//|                        Common Definitions & Enums                |
//+------------------------------------------------------------------+
#ifndef HG_COMMON_MQH
#define HG_COMMON_MQH

#include <MqlTrade.mqh>

//--- System Information
#define EA_VERSION      "1.0.0"
#define EA_NAME         "HG HFT Trader"
#define EA_AUTHOR       "Institutional Trading Desk"
#define MAGIC_PREFIX    100000

//--- Enums
enum ENUM_TRADING_MODE
{
   MODE_FULL_AUTO,
   MODE_SEMI_AUTO,
   MODE_MANUAL
};

enum ENUM_EXECUTION_STATUS
{
   EXEC_PENDING,
   EXEC_SENT,
   EXEC_FILLED,
   EXEC_PARTIAL,
   EXEC_REJECTED,
   EXEC_ERROR,
   EXEC_TIMEOUT
};

enum ENUM_RISK_EVENT
{
   RISK_NONE,
   RISK_DAILY_DRAWDOWN,
   RISK_TOTAL_DRAWDOWN,
   RISK_MARGIN_CALL,
   RISK_SPREAD_SPIKE,
   RISK_VOLATILITY,
   RISK_NEWS,
   RISK_MAX_LOTS,
   RISK_MAX_TRADES
};

enum ENUM_SIGNAL_TYPE
{
   SIGNAL_BUY,
   SIGNAL_SELL,
   SIGNAL_CLOSE,
   SIGNAL_MODIFY,
   SIGNAL_NONE
};

enum ENUM_STRATEGY_TYPE
{
   STRAT_SCALPING,
   STRAT_ORDER_FLOW,
   STRAT_MARKET_MAKING,
   STRAT_BREAKOUT,
   STRAT_MEAN_REVERSION,
   STRAT_AI
};

//--- Structs
struct SSymbolConfig
{
   string   name;
   double   point;
   double   tickSize;
   double   tickValue;
   int      digits;
   double   minLot;
   double   maxLot;
   double   lotStep;
   int      stopLevel;
   double   contractSize;
   bool     tradeAllowed;
   double   swapLong;
   double   swapShort;
   ENUM_SYMBOL_TRADE_EXECUTION executionMode;
   ENUM_SYMBOL_SWAP_MODE       swapMode;
};

struct STickData
{
   datetime time;
   double   bid;
   double   ask;
   double   last;
   ulong    volume;
   ulong    flags;
   double   spread;
   double   midpoint;
   long     latency_us;
   uint     sequence;
};

struct SSignal
{
   ENUM_SIGNAL_TYPE    type;
   ENUM_STRATEGY_TYPE  strategy;
   string              symbol;
   double              entryPrice;
   double              stopLoss;
   double              takeProfit;
   double              lotSize;
   ENUM_ORDER_TYPE     orderType;
   string              comment;
   double              confidence;
   datetime            timestamp;
   int                 magic;
   ulong               ticket;
};

struct SPositionInfo
{
   ulong    ticket;
   string   symbol;
   ENUM_POSITION_TYPE  posType;
   double   volume;
   double   openPrice;
   double   currentPrice;
   double   stopLoss;
   double   takeProfit;
   double   profit;
   double   swap;
   double   commission;
   datetime openTime;
   string   comment;
   int      magic;
   ENUM_STRATEGY_TYPE strategy;
};

struct SRiskMetrics
{
   double   dailyPnL;
   double   totalPnL;
   double   maxDailyDrawdown;
   double   maxTotalDrawdown;
   double   currentDrawdown;
   double   equity;
   double   balance;
   double   marginLevel;
   double   freeMargin;
   int      openTrades;
   double   totalLots;
   double   dailyReturnPct;
};

struct SExecutionConfig
{
   int      maxRetries;
   int      retryDelayMs;
   double   maxSlippagePips;
   bool     partialFillAccept;
   double   minFillPercent;
   ENUM_ORDER_TYPE_FILLING fillingMode;
   ENUM_ORDER_TYPE_TIME    expirationMode;
};

//--- Risk Configuration
struct SRiskConfig
{
   // Account protection
   double   maxDailyDrawdownPct;
   double   maxTotalDrawdownPct;
   double   dailyProfitTargetPct;
   double   equityProtectionPct;
   double   marginCallLevelPct;
   bool     autoDisableOnDrawdown;
   
   // Position risk
   double   maxLotSize;
   int      maxSimultaneousTrades;
   int      maxTradesPerSymbol;
   double   maxCorrelatedExposurePct;
   double   maxSymbolExposurePct;
   double   maxTotalOpenLots;
   bool     useDynamicLotSizing;
   double   riskPerTradePct;
   double   lotSizeMultiplier;
   
   // Market risk
   double   maxSpreadPips;
   double   maxSpreadPercent;
   double   volatilityThresholdATR;
   bool     highVolatilityFilterEnabled;
   bool     newsFilterEnabled;
   int      newsBlackoutMinutesBefore;
   int      newsBlackoutMinutesAfter;
   bool     londonSession;
   bool     newYorkSession;
   bool     tokyoSession;
   bool     sydneySession;
   int      liquidityMinimum;
   
   // Prop firm
   double   dailyLossLimitPct;
   bool     consistencyRuleEnabled;
   int      maxPositionDurationMin;
   bool     newsTradingDisabled;
   double   propAccountSize;
};

//--- Utility Functions
string GetErrorDescription(int error_code)
{
   switch(error_code)
   {
      case 0:    return "No error";
      case 1:    return "No error, but result unknown";
      case 2:    return "Common error";
      case 3:    return "Invalid trade parameters";
      case 4:    return "Trade server busy";
      case 5:    return "Old version of client terminal";
      case 6:    return "No connection with trade server";
      case 7:    return "Not enough rights";
      case 8:    return "Too frequent requests";
      case 9:    return "Malfunctional trade operation";
      case 64:   return "Account disabled";
      case 65:   return "Invalid account";
      case 128:  return "Trade timeout";
      case 129:  return "Invalid price";
      case 130:  return "Invalid stops";
      case 131:  return "Invalid trade volume";
      case 132:  return "Market is closed";
      case 133:  return "Trade is disabled";
      case 134:  return "Not enough money";
      case 135:  return "Price changed";
      case 136:  return "Off quotes";
      case 137:  return "Broker is busy";
      case 138:  return "Requote";
      case 139:  return "Order is locked";
      case 140:  return "Long positions only allowed";
      case 141:  return "Too many requests";
      case 145:  return "Modification denied because order is too close to market";
      case 146:  return "Trade context busy";
      default:   return "Unknown error " + IntegerToString(error_code);
   }
}

double NormalizeLotSize(double lot, double minLot, double maxLot, double lotStep)
{
   double normalized = MathFloor(lot / lotStep) * lotStep;
   normalized = MathMax(minLot, MathMin(maxLot, normalized));
   return NormalizeDouble(normalized, 2);
}

bool IsTradingTime(int startHour, int startMin, int endHour, int endMin)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = startHour * 60 + startMin;
   int endMinutes = endHour * 60 + endMin;
   
   if(startMinutes <= endMinutes)
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   else
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
}

string SymbolToFileName(string symbol)
{
   string result = symbol;
   StringReplace(result, "/", "_");
   return result;
}

#endif // HG_COMMON_MQH
