//+------------------------------------------------------------------+
//|                                         HG_RiskManagement.mqh    |
//|                        Institutional Risk Management System        |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef HG_RISK_MANAGEMENT_MQH
#define HG_RISK_MANAGEMENT_MQH

#include "HG_Common.mqh"
#include <Arrays\ArrayLong.mqh>

class CRiskManager
{
   private:
      SRiskConfig         m_config;
      SRiskMetrics        m_metrics;
      double              m_dailyStartBalance;
      double              m_dailyHighEquity;
      double              m_peakEquity;
      datetime            m_dailyResetTime;
      CArrayLong          m_tradeHistory;
      bool                m_bTradingEnabled;
      ENUM_RISK_EVENT     m_lastRiskEvent;
      datetime            m_lastRiskTime;
      
      // Risk tracking
      double              m_symbolExposure[];
      string              m_trackedSymbols[];
      
   public:
                         CRiskManager();
                        ~CRiskManager();
      
      // Initialization
      bool              Initialize(const SRiskConfig &config);
      void              UpdateConfiguration(const SRiskConfig &config);
      
      // Risk checks
      bool              CanOpenNewTrade(string symbol, double lots, ENUM_POSITION_TYPE posType);
      bool              CheckDailyDrawdown(double currentPnL);
      bool              CheckTotalDrawdown();
      bool              CheckSpreadSpike(string symbol, double currentSpread);
      bool              CheckVolatilityFilter(string symbol);
      bool              CheckNewsFilter();
      bool              CheckMarginLevel();
      bool              CheckMaxLots(double totalOpenLots);
      bool              CheckMaxTrades(int openTradeCount);
      bool              CheckSymbolExposure(string symbol, double lots);
      bool              CheckCorrelationExposure(string symbol);
      bool              CheckPropFirmRules(double currentPnL, datetime openTime);
      
      // Position validation
      double            CalculateLotSize(string symbol, double riskPercent, double stopLossPips);
      double            AdjustLotForSpread(string symbol, double baseLot);
      bool              ValidateStopLoss(string symbol, double entryPrice, double stopLoss, ENUM_ORDER_TYPE orderType);
      bool              ValidateTakeProfit(string symbol, double entryPrice, double takeProfit, ENUM_ORDER_TYPE orderType);
      
      // Update functions
      void              UpdateMetrics();
      void              RecordTradeResult(double profit);
      void              ResetDailyCounters();
      void              CheckAutoDisable();
      
      // Getters
      bool              IsTradingEnabled() const { return m_bTradingEnabled; }
      void              EnableTrading() { m_bTradingEnabled = true; }
      void              DisableTrading() { m_bTradingEnabled = false; }
      ENUM_RISK_EVENT   GetLastRiskEvent() const { return m_lastRiskEvent; }
      datetime          GetLastRiskTime() const { return m_lastRiskTime; }
      double            GetDailyPnL() const { return m_metrics.dailyPnL; }
      double            GetCurrentDrawdown() const { return m_metrics.currentDrawdown; }
      
      // Prop firm functions
      bool              IsWithinTradingHours();
      bool              CheckConsistencyRule(double currentPnL);
      bool              CheckMaxPositionDuration(datetime openTime);
      
   private:
      double            CalculateATR(string symbol, int period = 14);
      int               CountOpenTrades();
      double            CalculateExposure(string symbol);
      double            CalculateCorrelation(string sym1, string sym2);
      bool              IsHighImpactNewsTime();
      void              SetRiskEvent(ENUM_RISK_EVENT event);
};

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager()
{
   m_dailyStartBalance = 0;
   m_dailyHighEquity = 0;
   m_peakEquity = 0;
   m_bTradingEnabled = true;
   m_lastRiskEvent = RISK_NONE;
   m_lastRiskTime = 0;
   m_dailyResetTime = 0;
   ZeroMemory(m_config);
   ZeroMemory(m_metrics);
   ArrayResize(m_symbolExposure, 0);
   ArrayResize(m_trackedSymbols, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
   ArrayFree(m_symbolExposure);
   ArrayFree(m_trackedSymbols);
}

//+------------------------------------------------------------------+
//| Initialize                                                         |
//+------------------------------------------------------------------+
bool CRiskManager::Initialize(const SRiskConfig &config)
{
   m_config = config;
   m_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_dailyHighEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_dailyResetTime = TimeCurrent();
   
   return true;
}

//+------------------------------------------------------------------+
//| Update configuration                                               |
//+------------------------------------------------------------------+
void CRiskManager::UpdateConfiguration(const SRiskConfig &config)
{
   m_config = config;
}

//+------------------------------------------------------------------+
//| Can open new trade                                                 |
//+------------------------------------------------------------------+
bool CRiskManager::CanOpenNewTrade(string symbol, double lots, ENUM_POSITION_TYPE posType)
{
   if(!m_bTradingEnabled)
   {
      SetRiskEvent(RISK_NONE);
      return false;
   }
   
   // Check daily drawdown
   if(!CheckDailyDrawdown(m_metrics.dailyPnL))
   {
      SetRiskEvent(RISK_DAILY_DRAWDOWN);
      return false;
   }
   
   // Check total drawdown
   if(!CheckTotalDrawdown())
   {
      SetRiskEvent(RISK_TOTAL_DRAWDOWN);
      return false;
   }
   
   // Check margin level
   if(!CheckMarginLevel())
   {
      SetRiskEvent(RISK_MARGIN_CALL);
      return false;
   }
   
   // Check max lots
   double totalLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
         totalLots += PositionGetDouble(POSITION_VOLUME);
   }
   
   if(!CheckMaxLots(totalLots + lots))
   {
      SetRiskEvent(RISK_MAX_LOTS);
      return false;
   }
   
   // Check max trades
   int openTradeCount = PositionsTotal();
   if(!CheckMaxTrades(openTradeCount + 1))
   {
      SetRiskEvent(RISK_MAX_TRADES);
      return false;
   }
   
   // Check symbol exposure
   if(!CheckSymbolExposure(symbol, lots))
   {
      SetRiskEvent(RISK_NONE); // Not critical
      return false;
   }
   
   // Check spread spike
   double currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(!CheckSpreadSpike(symbol, currentSpread))
   {
      SetRiskEvent(RISK_SPREAD_SPIKE);
      return false;
   }
   
   // Check volatility
   if(!CheckVolatilityFilter(symbol))
   {
      SetRiskEvent(RISK_VOLATILITY);
      return false;
   }
   
   // Check news filter
   if(m_config.newsFilterEnabled && !CheckNewsFilter())
   {
      SetRiskEvent(RISK_NEWS);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check daily drawdown                                               |
//+------------------------------------------------------------------+
bool CRiskManager::CheckDailyDrawdown(double currentPnL)
{
   double maxDailyLoss = m_dailyStartBalance * (m_config.maxDailyDrawdownPct / 100.0);
   return (currentPnL > -maxDailyLoss);
}

//+------------------------------------------------------------------+
//| Check total drawdown                                               |
//+------------------------------------------------------------------+
bool CRiskManager::CheckTotalDrawdown()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > m_peakEquity)
      m_peakEquity = currentEquity;
   
   double drawdown = (m_peakEquity - currentEquity) / m_peakEquity * 100.0;
   m_metrics.currentDrawdown = drawdown;
   
   return (drawdown < m_config.maxTotalDrawdownPct);
}

//+------------------------------------------------------------------+
//| Check spread spike                                                 |
//+------------------------------------------------------------------+
bool CRiskManager::CheckSpreadSpike(string symbol, double currentSpread)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spreadPips = currentSpread / point;
   
   return (spreadPips <= m_config.maxSpreadPips);
}

//+------------------------------------------------------------------+
//| Check volatility filter                                            |
//+------------------------------------------------------------------+
bool CRiskManager::CheckVolatilityFilter(string symbol)
{
   if(!m_config.highVolatilityFilterEnabled)
      return true;
   
   double atr = CalculateATR(symbol, 14);
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   double volatilityPct = (atr / currentPrice) * 100.0;
   
   return (volatilityPct < m_config.volatilityThresholdATR);
}

//+------------------------------------------------------------------+
//| Check news filter                                                  |
//+------------------------------------------------------------------+
bool CRiskManager::CheckNewsFilter()
{
   return !IsHighImpactNewsTime();
}

//+------------------------------------------------------------------+
//| Check margin level                                                 |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMarginLevel()
{
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   if(marginLevel == 0) // No open positions
      return true;
   
   return (marginLevel > m_config.marginCallLevelPct);
}

//+------------------------------------------------------------------+
//| Check max lots                                                     |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMaxLots(double totalOpenLots)
{
   return (totalOpenLots <= m_config.maxTotalOpenLots);
}

//+------------------------------------------------------------------+
//| Check max trades                                                     |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMaxTrades(int openTradeCount)
{
   return (openTradeCount <= m_config.maxSimultaneousTrades);
}

//+------------------------------------------------------------------+
//| Check symbol exposure                                                |
//+------------------------------------------------------------------+
bool CRiskManager::CheckSymbolExposure(string symbol, double lots)
{
   double currentExposure = CalculateExposure(symbol);
   double newExposure = currentExposure + lots;
   double maxExposure = AccountInfoDouble(ACCOUNT_EQUITY) * (m_config.maxSymbolExposurePct / 100.0);
   
   return (newExposure <= maxExposure);
}

//+------------------------------------------------------------------+
//| Check correlation exposure                                           |
//+------------------------------------------------------------------+
bool CRiskManager::CheckCorrelationExposure(string symbol)
{
   return true; // Simplified - can be extended with full correlation matrix
}

//+------------------------------------------------------------------+
//| Check prop firm rules                                                |
//+------------------------------------------------------------------+
bool CRiskManager::CheckPropFirmRules(double currentPnL, datetime openTime)
{
   // Check max position duration
   if(!CheckMaxPositionDuration(openTime))
      return false;
   
   // Check consistency rule
   if(!CheckConsistencyRule(currentPnL))
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                   |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLotSize(string symbol, double riskPercent, double stopLossPips)
{
   if(!m_config.useDynamicLotSizing)
      return NormalizeLotSize(m_config.maxLotSize, 
                               SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                               SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                               SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));
   
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(tickSize == 0 || tickValue == 0)
      return 0;
   
   double riskAmount = balance * (riskPercent / 100.0);
   double pipsValue = (tickValue / tickSize) * point;
   double lots = riskAmount / (stopLossPips * pipsValue);
   
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lots = NormalizeLotSize(lots * m_config.lotSizeMultiplier, minLot, maxLot, lotStep);
   
   return lots;
}

//+------------------------------------------------------------------+
//| Adjust lot for spread                                                |
//+------------------------------------------------------------------+
double CRiskManager::AdjustLotForSpread(string symbol, double baseLot)
{
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
   double maxSpread = m_config.maxSpreadPips * SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   if(maxSpread <= 0)
      return baseLot;
   
   double spreadRatio = spread / maxSpread;
   double adjustedLot = baseLot * (1.0 - (spreadRatio * 0.5)); // Reduce lot by up to 50%
   
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   return NormalizeLotSize(MathMax(adjustedLot, minLot), minLot, maxLot, lotStep);
}

//+------------------------------------------------------------------+
//| Validate stop loss                                                   |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateStopLoss(string symbol, double entryPrice, double stopLoss, ENUM_ORDER_TYPE orderType)
{
   if(stopLoss == 0)
      return true;
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int stopLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopLevel * point;
   
   if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP)
   {
      return (entryPrice - stopLoss >= minDistance);
   }
   else if(orderType == ORDER_TYPE_SELL || orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP)
   {
      return (stopLoss - entryPrice >= minDistance);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Validate take profit                                                 |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateTakeProfit(string symbol, double entryPrice, double takeProfit, ENUM_ORDER_TYPE orderType)
{
   if(takeProfit == 0)
      return true;
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int stopLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopLevel * point;
   
   if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP)
   {
      return (takeProfit - entryPrice >= minDistance);
   }
   else if(orderType == ORDER_TYPE_SELL || orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP)
   {
      return (entryPrice - takeProfit >= minDistance);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update metrics                                                       |
//+------------------------------------------------------------------+
void CRiskManager::UpdateMetrics()
{
   m_metrics.equity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_metrics.balance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_metrics.freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   m_metrics.marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   m_metrics.openTrades = PositionsTotal();
   
   // Calculate daily PnL
   m_metrics.dailyPnL = m_metrics.equity - m_dailyStartBalance;
   
   // Update peak equity
   if(m_metrics.equity > m_peakEquity)
      m_peakEquity = m_metrics.equity;
   
   // Calculate total lots
   m_metrics.totalLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
         m_metrics.totalLots += PositionGetDouble(POSITION_VOLUME);
   }
   
   // Reset daily counters if needed
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   MqlDateTime resetDt;
   TimeToStruct(m_dailyResetTime, resetDt);
   
   if(dt.day != resetDt.day)
   {
      ResetDailyCounters();
   }
}

//+------------------------------------------------------------------+
//| Record trade result                                                  |
//+------------------------------------------------------------------+
void CRiskManager::RecordTradeResult(double profit)
{
   m_metrics.dailyPnL += profit;
   
   if(m_tradeHistory.Add(TimeCurrent()) < 0)
   {
      Print("Failed to record trade result");
   }
}

//+------------------------------------------------------------------+
//| Reset daily counters                                                 |
//+------------------------------------------------------------------+
void CRiskManager::ResetDailyCounters()
{
   m_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_dailyHighEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_dailyResetTime = TimeCurrent();
   m_metrics.dailyPnL = 0;
   m_bTradingEnabled = true;
   m_lastRiskEvent = RISK_NONE;
}

//+------------------------------------------------------------------+
//| Check auto disable                                                   |
//+------------------------------------------------------------------+
void CRiskManager::CheckAutoDisable()
{
   if(!m_config.autoDisableOnDrawdown)
      return;
   
   if(!CheckDailyDrawdown(m_metrics.dailyPnL) || !CheckTotalDrawdown())
   {
      m_bTradingEnabled = false;
      Print("AUTO DISABLE: Trading disabled due to risk limits");
   }
}

//+------------------------------------------------------------------+
//| Is within trading hours                                              |
//+------------------------------------------------------------------+
bool CRiskManager::IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // Check London session (8:00-16:00 GMT)
   bool londonActive = (currentMinutes >= 480 && currentMinutes < 960) && m_config.londonSession;
   
   // Check NY session (13:00-21:00 GMT)
   bool nyActive = (currentMinutes >= 780 && currentMinutes < 1260) && m_config.newYorkSession;
   
   // Check Tokyo session (0:00-9:00 GMT)
   bool tokyoActive = (currentMinutes >= 0 && currentMinutes < 540) && m_config.tokyoSession;
   
   // Check Sydney session (22:00-7:00 GMT)
   bool sydneyActive = ((currentMinutes >= 1320 || currentMinutes < 420)) && m_config.sydneySession;
   
   return (londonActive || nyActive || tokyoActive || sydneyActive);
}

//+------------------------------------------------------------------+
//| Check consistency rule                                               |
//+------------------------------------------------------------------+
bool CRiskManager::CheckConsistencyRule(double currentPnL)
{
   if(!m_config.consistencyRuleEnabled)
      return true;
   
   double avgDailyPnL = m_metrics.dailyPnL / MathMax(1, TimeDay(TimeCurrent()) - TimeDay(m_dailyResetTime) + 1);
   double consistencyThreshold = avgDailyPnL * 5.0;
   
   return (MathAbs(currentPnL) <= consistencyThreshold);
}

//+------------------------------------------------------------------+
//| Check max position duration                                          |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMaxPositionDuration(datetime openTime)
{
   if(m_config.maxPositionDurationMin <= 0)
      return true;
   
   int durationMin = (int)((TimeCurrent() - openTime) / 60);
   return (durationMin <= m_config.maxPositionDurationMin);
}

//+------------------------------------------------------------------+
//| Calculate ATR                                                        |
//+------------------------------------------------------------------+
double CRiskManager::CalculateATR(string symbol, int period)
{
   double atrSum = 0;
   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(symbol, PERIOD_CURRENT, i);
      double low = iLow(symbol, PERIOD_CURRENT, i);
      double close = iClose(symbol, PERIOD_CURRENT, i + 1);
      
      double tr1 = high - low;
      double tr2 = MathAbs(high - close);
      double tr3 = MathAbs(low - close);
      
      atrSum += MathMax(tr1, MathMax(tr2, tr3));
   }
   
   return atrSum / period;
}

//+------------------------------------------------------------------+
//| Count open trades                                                    |
//+------------------------------------------------------------------+
int CRiskManager::CountOpenTrades()
{
   return PositionsTotal();
}

//+------------------------------------------------------------------+
//| Calculate exposure                                                   |
//+------------------------------------------------------------------+
double CRiskManager::CalculateExposure(string symbol)
{
   double exposure = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) == symbol)
         exposure += PositionGetDouble(POSITION_VOLUME);
   }
   
   return exposure;
}

//+------------------------------------------------------------------+
//| Calculate correlation                                                |
//+------------------------------------------------------------------+
double CRiskManager::CalculateCorrelation(string sym1, string sym2)
{
   // Simplified - would require historical data calculation
   if(sym1 == sym2)
      return 1.0;
   
   // Basic correlation for known pairs
   if((sym1 == "EURUSD" && sym2 == "GBPUSD") || (sym1 == "GBPUSD" && sym2 == "EURUSD"))
      return 0.8;
   if((sym1 == "EURUSD" && sym2 == "USDJPY") || (sym1 == "USDJPY" && sym2 == "EURUSD"))
      return -0.6;
   if((sym1 == "GBPUSD" && sym2 == "USDJPY") || (sym1 == "USDJPY" && sym2 == "GBPUSD"))
      return -0.5;
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| Is high impact news time                                             |
//+------------------------------------------------------------------+
bool CRiskManager::IsHighImpactNewsTime()
{
   // Simplified news filter - would integrate with actual news API
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // Check for common high-impact news times (simplified)
   // NFP (first Friday, 8:30 AM EST - 13:30 GMT)
   if(dt.day_of_week == 5 && dt.hour == 13 && dt.min >= 25 && dt.min <= 35)
      return true;
   
   // FOMC (usually 2:00 PM EST - 19:00 GMT)
   if(dt.day_of_week == 3 && dt.hour == 19 && dt.min >= 0 && dt.min <= 30)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Set risk event                                                       |
//+------------------------------------------------------------------+
void CRiskManager::SetRiskEvent(ENUM_RISK_EVENT event)
{
   m_lastRiskEvent = event;
   m_lastRiskTime = TimeCurrent();
   
   if(event != RISK_NONE)
   {
      Print("RISK EVENT: ", EnumToString(event), " at ", TimeToString(TimeCurrent()));
   }
}

#endif // HG_RISK_MANAGEMENT_MQH
