//+------------------------------------------------------------------+
//|                                          HG_Strategies.mqh       |
//|                        HFT Strategy Definitions & Base Classes     |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef HG_STRATEGIES_MQH
#define HG_STRATEGIES_MQH

#include "HG_Common.mqh"
#include "HG_RiskManagement.mqh"

//--- Strategy Configuration
struct SStrategyConfig
{
   bool              enabled;
   int               priority;
   string            symbols[];
   ENUM_TIMEFRAMES   timeframes[];
   double            maxSpreadPips;
   double            riskPercent;
   double            lotSize;
   int               magicNumber;
   bool              partialCloseEnabled;
   double            partialClosePercent;
   bool              trailingStopEnabled;
   double            trailingStopPips;
   bool              breakEvenEnabled;
   double            breakEvenTriggerPips;
   double            breakEvenOffsetPips;
};

//--- Strategy Base Class
class CStrategy
{
   protected:
      SStrategyConfig   m_config;
      ENUM_STRATEGY_TYPE m_type;
      string            m_name;
      int               m_magicNumber;
      CRiskManager     *m_riskManager;
      
      // Internal buffers for indicators
      double            m_bufferPrice[];
      double            m_bufferMA[];
      double            m_bufferRSI[];
      double            m_bufferMACD[];
      double            m_bufferSignal[];
      
   public:
                         CStrategy();
      virtual          ~CStrategy();
      
      // Initialization
      virtual bool      Initialize(const SStrategyConfig &config, CRiskManager *riskManager);
      virtual void      Deinitialize();
      
      // Core strategy functions
      virtual SSignal   ProcessTick(string symbol, const STickData &tick) = 0;
      virtual bool      ShouldClose(string symbol, ulong ticket, double currentProfit) = 0;
      
      // Configuration
      virtual void      UpdateConfig(const SStrategyConfig &config);
      SStrategyConfig   GetConfig() const { return m_config; }
      ENUM_STRATEGY_TYPE GetType() const { return m_type; }
      string            GetName() const { return m_name; }
      
      // Utility functions
      virtual bool      FilterSymbol(string symbol) const;
      virtual bool      FilterTimeframe(ENUM_TIMEFRAMES tf) const;
      virtual bool      FilterSpread(string symbol, double spreadPips) const;
      
   protected:
      // Technical indicators
      double            CalculateMA(string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 0);
      double            CalculateRSI(string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 0);
      double            CalculateMACD(string symbol, ENUM_TIMEFRAMES tf, int fast, int slow, int signal, int shift = 0);
      double            CalculateATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 0);
      double            CalculateBollingerBand(string symbol, ENUM_TIMEFRAMES tf, int period, double deviation, ENUM_BAND_LINE bandLine, int shift = 0);
      double            CalculateVWAP(string symbol, int shift = 0);
      
      // Signal helpers
      SSignal           CreateSignal(ENUM_SIGNAL_TYPE type, string symbol, double price,
                                    double sl, double tp, double lots, string comment);
      
      // Price action
      bool              IsBullishCandle(int shift);
      bool              IsBearishCandle(int shift);
      double            GetCandleBody(int shift);
      double            GetCandleRange(int shift);
      double            GetUpperWick(int shift);
      double            GetLowerWick(int shift);
      
      // Market conditions
      double            GetAverageVolume(string symbol, ENUM_TIMEFRAMES tf, int period);
      double            GetVolumeImbalance(string symbol);
      double            GetPriceVelocity(string symbol, int bars);
};

//+------------------------------------------------------------------+
//| Ultra Fast Scalping Strategy                                       |
//+------------------------------------------------------------------+
class CScalpingStrategy : public CStrategy
{
   private:
      double            m_tickMomentumThreshold;
      double            m_microPullbackPercent;
      double            m_targetPips;
      double            m_stopLossPips;
      double            m_takeProfitPips;
      double            m_volumeThreshold;
      int               m_minTradeDurationSec;
      int               m_maxTradeDurationSec;
      MqlTick           m_prevTick;
      double            m_momentumBuffer[];
      double            m_spreadFilter;
      
   public:
                         CScalpingStrategy();
                        ~CScalpingStrategy();
      
      virtual bool      Initialize(const SStrategyConfig &config, CRiskManager *riskManager);
      virtual SSignal   ProcessTick(string symbol, const STickData &tick);
      virtual bool      ShouldClose(string symbol, ulong ticket, double currentProfit);
      
   private:
      bool              DetectTickMomentum(string symbol, const STickData &currentTick,
                                            const MqlTick &previousTick);
      bool              DetectMicroPullback(string symbol, double price);
      bool              CheckVolumeThreshold(string symbol);
      bool              IsWithinTradeDuration(datetime openTime);
      double            GetCurrentATR(string symbol);
};

//+------------------------------------------------------------------+
//| Order Flow Strategy                                                |
//+------------------------------------------------------------------+
class COrderFlowStrategy : public CStrategy
{
   private:
      int               m_tickPressureWindow;
      double            m_imbalanceThreshold;
      double            m_aggressiveCandleMultiplier;
      bool              m_volumeProfileEnabled;
      bool              m_deltaAnalysisEnabled;
      MqlTick           m_tickBuffer[];
      double            m_deltaBuffer[];
      double            m_pressureIndex[];
      
   public:
                         COrderFlowStrategy();
                        ~COrderFlowStrategy();
      
      virtual bool      Initialize(const SStrategyConfig &config, CRiskManager *riskManager);
      virtual SSignal   ProcessTick(string symbol, const STickData &tick);
      virtual bool      ShouldClose(string symbol, ulong ticket, double currentProfit);
      
   private:
      double            CalculateTickPressure(string symbol);
      double            CalculateImbalanceMetric(string symbol);
      bool              DetectAggressiveCandle(string symbol);
      double            CalculateDelta(string symbol);
      double            GetVolumeAtPrice(string symbol, double price);
};

//+------------------------------------------------------------------+
//| Market Making Strategy                                             |
//+------------------------------------------------------------------+
class CMarketMakingStrategy : public CStrategy
{
   private:
      double            m_spreadCapturePercent;
      double            m_inventoryLimitLots;
      double            m_rebalanceThreshold;
      bool              m_volatilityAdjustment;
      double            m_maxPositionImbalance;
      double            m_currentInventory;
      double            m_spreadCapturePrice;
      
   public:
                         CMarketMakingStrategy();
                        ~CMarketMakingStrategy();
      
      virtual bool      Initialize(const SStrategyConfig &config, CRiskManager *riskManager);
      virtual SSignal   ProcessTick(string symbol, const STickData &tick);
      virtual bool      ShouldClose(string symbol, ulong ticket, double currentProfit);
      
   private:
      double            CalculateOptimalSpread(string symbol);
      double            CalculateInventoryExposure(string symbol);
      bool              ShouldRebalance(string symbol);
      double            GetDynamicSpread(string symbol);
};

//+------------------------------------------------------------------+
//| Volatility Breakout Strategy                                       |
//+------------------------------------------------------------------+
class CVolatilityBreakoutStrategy : public CStrategy
{
   private:
      string            m_londonSession;
      string            m_nySession;
      double            m_breakoutThresholdATR;
      bool              m_confirmVolumeIncrease;
      string            m_newsVolatilityMode;
      double            m_sessionHigh;
      double            m_sessionLow;
      datetime          m_sessionStartTime;
      bool              m_breakoutTriggered;
      
   public:
                         CVolatilityBreakoutStrategy();
                        ~CVolatilityBreakoutStrategy();
      
      virtual bool      Initialize(const SStrategyConfig &config, CRiskManager *riskManager);
      virtual SSignal   ProcessTick(string symbol, const STickData &tick);
      virtual bool      ShouldClose(string symbol, ulong ticket, double currentProfit);
      
   private:
      bool              IsLondonSession();
      bool              IsNYSession();
      bool              IsTokyoSession();
      bool              IsSydneySession();
      bool              CheckVolumeIncrease(string symbol);
      bool              CheckNewsVolatilityFilter();
      void              UpdateSessionLevels(string symbol);
      bool              IsBreakoutValid(string symbol, double price);
};

//+------------------------------------------------------------------+
//| Mean Reversion Strategy                                            |
//+------------------------------------------------------------------+
class CMeanReversionStrategy : public CStrategy
{
   private:
      double            m_vwapDeviationThreshold;
      int               m_reversalConfirmationCandles;
      bool              m_liquidityGrabDetection;
      double            m_stopLossMultiplier;
      double            m_vwapValue;
      double            m_deviationBuffer[];
      double            m_reversalBuffer[];
      
   public:
                         CMeanReversionStrategy();
                        ~CMeanReversionStrategy();
      
      virtual bool      Initialize(const SStrategyConfig &config, CRiskManager *riskManager);
      virtual SSignal   ProcessTick(string symbol, const STickData &tick);
      virtual bool      ShouldClose(string symbol, ulong ticket, double currentProfit);
      
   private:
      double            CalculateVWAPDeviation(string symbol);
      bool              DetectReversalCandles(string symbol, int requiredCandles);
      bool              DetectLiquidityGrab(string symbol);
      double            FindSupportLevel(string symbol, int bars);
      double            FindResistanceLevel(string symbol, int bars);
      bool              IsPriceExtreme(string symbol, double price);
};

//--- Strategy Factory
class CStrategyFactory
{
   public:
      static CStrategy* CreateStrategy(ENUM_STRATEGY_TYPE type);
      static void DestroyStrategy(CStrategy* strategy);
};

//+------------------------------------------------------------------+
//| Strategy Constructor                                               |
//+------------------------------------------------------------------+
CStrategy::CStrategy()
{
   m_magicNumber = MAGIC_PREFIX;
   m_riskManager = NULL;
}

//+------------------------------------------------------------------+
//| Strategy Destructor                                                |
//+------------------------------------------------------------------+
CStrategy::~CStrategy()
{
   // Cleanup
}

//+------------------------------------------------------------------+
//| Initialize                                                           |
//+------------------------------------------------------------------+
bool CStrategy::Initialize(const SStrategyConfig &config, CRiskManager *riskManager)
{
   m_config = config;
   m_riskManager = riskManager;
   m_magicNumber = config.magicNumber;
   
   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                         |
//+------------------------------------------------------------------+
void CStrategy::Deinitialize()
{
   // Cleanup
}

//+------------------------------------------------------------------+
//| Update configuration                                                 |
//+------------------------------------------------------------------+
void CStrategy::UpdateConfig(const SStrategyConfig &config)
{
   m_config = config;
}

//+------------------------------------------------------------------+
//| Filter symbol                                                        |
//+------------------------------------------------------------------+
bool CStrategy::FilterSymbol(string symbol) const
{
   for(int i = 0; i < ArraySize(m_config.symbols); i++)
   {
      if(m_config.symbols[i] == symbol)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Filter timeframe                                                   |
//+------------------------------------------------------------------+
bool CStrategy::FilterTimeframe(ENUM_TIMEFRAMES tf) const
{
   for(int i = 0; i < ArraySize(m_config.timeframes); i++)
   {
      if(m_config.timeframes[i] == tf)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Filter spread                                                        |
//+------------------------------------------------------------------+
bool CStrategy::FilterSpread(string symbol, double spreadPips) const
{
   return (spreadPips <= m_config.maxSpreadPips);
}

//+------------------------------------------------------------------+
//| Calculate Moving Average                                           |
//+------------------------------------------------------------------+
double CStrategy::CalculateMA(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double ma = 0;
   int handle = iMA(symbol, tf, period, 0, MODE_SMA, PRICE_CLOSE);
   if(handle != INVALID_HANDLE)
   {
      CopyBuffer(handle, 0, shift, 1, m_bufferMA);
      ma = m_bufferMA[0];
      IndicatorRelease(handle);
   }
   return ma;
}

//+------------------------------------------------------------------+
//| Calculate RSI                                                       |
//+------------------------------------------------------------------+
double CStrategy::CalculateRSI(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double rsi = 0;
   int handle = iRSI(symbol, tf, period, PRICE_CLOSE);
   if(handle != INVALID_HANDLE)
   {
      CopyBuffer(handle, 0, shift, 1, m_bufferRSI);
      rsi = m_bufferRSI[0];
      IndicatorRelease(handle);
   }
   return rsi;
}

//+------------------------------------------------------------------+
//| Create signal                                                       |
//+------------------------------------------------------------------+
SSignal CStrategy::CreateSignal(ENUM_SIGNAL_TYPE type, string symbol, double price,
                                double sl, double tp, double lots, string comment)
{
   SSignal signal;
   signal.type = type;
   signal.symbol = symbol;
   signal.entryPrice = price;
   signal.stopLoss = sl;
   signal.takeProfit = tp;
   signal.lotSize = lots;
   signal.comment = comment;
   signal.timestamp = TimeCurrent();
   signal.magic = m_magicNumber;
   signal.strategy = m_type;
   signal.confidence = 0.5;
   
   return signal;
}

//+------------------------------------------------------------------+
//| Scalping Strategy Constructor                                       |
//+------------------------------------------------------------------+
CScalpingStrategy::CScalpingStrategy()
{
   m_type = STRAT_SCALPING;
   m_name = "UltraFastScalping";
   m_tickMomentumThreshold = 0.0001;
   m_microPullbackPercent = 0.3;
   m_targetPips = 1.0;
   m_stopLossPips = 3.0;
   m_takeProfitPips = 2.0;
   m_volumeThreshold = 100;
   m_minTradeDurationSec = 5;
   m_maxTradeDurationSec = 300;
   m_spreadFilter = 1.5;
}

//+------------------------------------------------------------------+
//| Scalping Strategy Destructor                                         |
//+------------------------------------------------------------------+
CScalpingStrategy::~CScalpingStrategy()
{
   // Cleanup
}

//+------------------------------------------------------------------+
//| Scalping Strategy Initialize                                       |
//+------------------------------------------------------------------+
bool CScalpingStrategy::Initialize(const SStrategyConfig &config, CRiskManager *riskManager)
{
   if(!CStrategy::Initialize(config, riskManager))
      return false;
   
   // Scalping-specific parameters (could be loaded from config)
   m_tickMomentumThreshold = 0.0001;
   m_microPullbackPercent = 0.3;
   m_targetPips = 2.0;
   m_stopLossPips = 3.0;
   m_takeProfitPips = 2.0;
   m_volumeThreshold = 100;
   
   return true;
}

//+------------------------------------------------------------------+
//| Process tick (Scalping)                                             |
//+------------------------------------------------------------------+
SSignal CScalpingStrategy::ProcessTick(string symbol, const STickData &tick)
{
   SSignal signal;
   signal.type = SIGNAL_NONE;
   
   // Check if scalping is enabled for this symbol
   if(!FilterSymbol(symbol))
      return signal;
   
   // Check spread filter
   double spreadPips = tick.spread / SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(!FilterSpread(symbol, spreadPips))
      return signal;
   
   // Check tick momentum
   if(DetectTickMomentum(symbol, tick, m_prevTick))
   {
      // Calculate entry, SL, and TP
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double sl = tick.ask - m_stopLossPips * point;
      double tp = tick.ask + m_takeProfitPips * point;
      
      double lots = m_riskManager.CalculateLotSize(symbol, m_config.riskPercent, m_stopLossPips);
      
      if(lots > 0)
      {
         if(tick.bid > m_prevTick.bid) // Bullish momentum
         {
            signal = CreateSignal(SIGNAL_BUY, symbol, tick.ask, sl, tp, lots, "Scalp Buy");
         }
         else if(tick.bid < m_prevTick.bid) // Bearish momentum
         {
            sl = tick.bid + m_stopLossPips * point;
            tp = tick.bid - m_takeProfitPips * point;
            signal = CreateSignal(SIGNAL_SELL, symbol, tick.bid, sl, tp, lots, "Scalp Sell");
         }
      }
   }
   
   // Check for micro pullback opportunities
   if(signal.type == SIGNAL_NONE && DetectMicroPullback(symbol, tick.midpoint))
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double lots = m_riskManager.CalculateLotSize(symbol, m_config.riskPercent, m_stopLossPips);
      
      if(lots > 0)
      {
         if(tick.ask < SymbolInfoDouble(symbol, SYMBOL_ASK)) // Price pulled back
         {
            double sl = tick.ask - m_stopLossPips * point;
            double tp = tick.ask + m_takeProfitPips * point;
            signal = CreateSignal(SIGNAL_BUY, symbol, tick.ask, sl, tp, lots, "Pullback Buy");
         }
         else
         {
            double sl = tick.bid + m_stopLossPips * point;
            double tp = tick.bid - m_takeProfitPips * point;
            signal = CreateSignal(SIGNAL_SELL, symbol, tick.bid, sl, tp, lots, "Pullback Sell");
         }
      }
   }
   
   m_prevTick.bid = tick.bid;
   m_prevTick.ask = tick.ask;
   
   return signal;
}

//+------------------------------------------------------------------+
//| Detect tick momentum                                                |
//+------------------------------------------------------------------+
bool CScalpingStrategy::DetectTickMomentum(string symbol, const STickData &currentTick,
                                            const MqlTick &previousTick)
{
   if(previousTick.bid <= 0 || previousTick.ask <= 0)
      return false;
   
   double priceChange = (currentTick.bid - previousTick.bid) / SymbolInfoDouble(symbol, SYMBOL_POINT);
   double momentum = priceChange / (currentTick.time - previousTick.time + 1); // per second
   
   return (MathAbs(momentum) > m_tickMomentumThreshold);
}

//+------------------------------------------------------------------+
//| Detect micro pullback                                              |
//+------------------------------------------------------------------+
bool CScalpingStrategy::DetectMicroPullback(string symbol, double price)
{
   double ma = CalculateMA(symbol, PERIOD_M1, 20, 0);
   double deviation = MathAbs(price - ma) / ma * 100.0;
   
   return (deviation < m_microPullbackPercent);
}

//+------------------------------------------------------------------+
//| Check volume threshold                                              |
//+------------------------------------------------------------------+
bool CScalpingStrategy::CheckVolumeThreshold(string symbol)
{
   long tickVolume = SymbolInfoInteger(symbol, SYMBOL_VOLUME);
   return (tickVolume >= m_volumeThreshold);
}

//+------------------------------------------------------------------+
//| Check within trade duration                                        |
//+------------------------------------------------------------------+
bool CScalpingStrategy::IsWithinTradeDuration(datetime openTime)
{
   int durationSec = (int)(TimeCurrent() - openTime);
   return (durationSec >= m_minTradeDurationSec && durationSec <= m_maxTradeDurationSec);
}

//+------------------------------------------------------------------+
//| Should close position (Scalping)                                    |
//+------------------------------------------------------------------+
bool CScalpingStrategy::ShouldClose(string symbol, ulong ticket, double currentProfit)
{
   // Check if profit target reached
   if(currentProfit >= m_takeProfitPips * SymbolInfoDouble(symbol, SYMBOL_POINT) * SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE))
      return true;
   
   // Check if trade duration exceeded
   if(PositionSelectByTicket(ticket))
   {
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(!IsWithinTradeDuration(openTime))
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get current ATR                                                      |
//+------------------------------------------------------------------+
double CScalpingStrategy::GetCurrentATR(string symbol)
{
   return CalculateATR(symbol, PERIOD_M1, 14, 0);
}

//+------------------------------------------------------------------+
//| Order Flow Strategy Constructor                                     |
//+------------------------------------------------------------------+
COrderFlowStrategy::COrderFlowStrategy()
{
   m_type = STRAT_ORDER_FLOW;
   m_name = "OrderFlow";
   m_tickPressureWindow = 50;
   m_imbalanceThreshold = 0.6;
   m_aggressiveCandleMultiplier = 2.0;
   m_volumeProfileEnabled = true;
   m_deltaAnalysisEnabled = true;
   ArrayResize(m_tickBuffer, 0);
   ArrayResize(m_deltaBuffer, 0);
   ArrayResize(m_pressureIndex, 0);
}

//+------------------------------------------------------------------+
//| Order Flow Strategy Destructor                                     |
//+------------------------------------------------------------------+
COrderFlowStrategy::~COrderFlowStrategy()
{
   ArrayFree(m_tickBuffer);
   ArrayFree(m_deltaBuffer);
   ArrayFree(m_pressureIndex);
}

//+------------------------------------------------------------------+
//| Process tick (Order Flow)                                           |
//+------------------------------------------------------------------+
SSignal COrderFlowStrategy::ProcessTick(string symbol, const STickData &tick)
{
   SSignal signal;
   signal.type = SIGNAL_NONE;
   
   // Update tick buffer
   int bufferSize = ArraySize(m_tickBuffer);
   if(bufferSize >= m_tickPressureWindow)
   {
      ArrayResize(m_tickBuffer, m_tickPressureWindow - 1);
      ArrayResize(m_deltaBuffer, m_tickPressureWindow - 1);
   }
   
   MqlTick mqlTick;
   mqlTick.bid = tick.bid;
   mqlTick.ask = tick.ask;
   mqlTick.last = tick.last;
   mqlTick.volume = tick.volume;
   mqlTick.time = tick.time;
   ArrayInsertMqlTick(m_tickBuffer, mqlTick, 0);
   
   // Calculate order flow metrics
   double pressure = CalculateTickPressure(symbol);
   double imbalance = CalculateImbalanceMetric(symbol);
   
   if(pressure > m_imbalanceThreshold || imbalance > m_imbalanceThreshold)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double lots = m_riskManager.CalculateLotSize(symbol, m_config.riskPercent, 5.0);
      
      if(lots > 0)
      {
         if(pressure > 0) // Buying pressure
         {
            double sl = tick.ask - 5.0 * point;
            double tp = tick.ask + 3.0 * point;
            signal = CreateSignal(SIGNAL_BUY, symbol, tick.ask, sl, tp, lots, "OrderFlow Buy");
         }
         else // Selling pressure
         {
            double sl = tick.bid + 5.0 * point;
            double tp = tick.bid - 3.0 * point;
            signal = CreateSignal(SIGNAL_SELL, symbol, tick.bid, sl, tp, lots, "OrderFlow Sell");
         }
      }
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Calculate tick pressure                                            |
//+------------------------------------------------------------------+
double COrderFlowStrategy::CalculateTickPressure(string symbol)
{
   if(ArraySize(m_tickBuffer) < 10)
      return 0.0;
   
   int bullishTicks = 0;
   int bearishTicks = 0;
   
   for(int i = 1; i < ArraySize(m_tickBuffer); i++)
   {
      if(m_tickBuffer[i].bid > m_tickBuffer[i-1].bid)
         bullishTicks++;
      else if(m_tickBuffer[i].bid < m_tickBuffer[i-1].bid)
         bearishTicks++;
   }
   
   double totalTicks = (double)(bullishTicks + bearishTicks);
   if(totalTicks == 0)
      return 0.0;
   
   return (double)(bullishTicks - bearishTicks) / totalTicks;
}

//+------------------------------------------------------------------+
//| Calculate imbalance metric                                           |
//+------------------------------------------------------------------+
double COrderFlowStrategy::CalculateImbalanceMetric(string symbol)
{
   if(ArraySize(m_tickBuffer) < 20)
      return 0.0;
   
   double askVolume = 0;
   double bidVolume = 0;
   
   for(int i = 0; i < ArraySize(m_tickBuffer); i++)
   {
      if(m_tickBuffer[i].ask > m_tickBuffer[i].bid)
         askVolume += m_tickBuffer[i].volume;
      else
         bidVolume += m_tickBuffer[i].volume;
   }
   
   double totalVolume = askVolume + bidVolume;
   if(totalVolume == 0)
      return 0.0;
   
   return MathAbs(askVolume - bidVolume) / totalVolume;
}

//+------------------------------------------------------------------+
//| Should close (Order Flow)                                           |
//+------------------------------------------------------------------+
bool COrderFlowStrategy::ShouldClose(string symbol, ulong ticket, double currentProfit)
{
   // Check if order flow has reversed
   double pressure = CalculateTickPressure(symbol);
   double imbalance = CalculateImbalanceMetric(symbol);
   
   if(MathAbs(pressure) < m_imbalanceThreshold * 0.5 && MathAbs(imbalance) < m_imbalanceThreshold * 0.5)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect aggressive candle                                           |
//+------------------------------------------------------------------+
bool COrderFlowStrategy::DetectAggressiveCandle(string symbol)
{
   MqlRates rates[];
   if(CopyRates(symbol, PERIOD_M1, 0, 3, rates) < 3)
      return false;
   
   double avgBody = 0;
   for(int i = 1; i < 3; i++)
   {
      avgBody += MathAbs(rates[i].close - rates[i].open);
   }
   avgBody /= 2.0;
   
   double currentBody = MathAbs(rates[0].close - rates[0].open);
   
   return (currentBody > avgBody * m_aggressiveCandleMultiplier);
}

//+------------------------------------------------------------------+
//| Calculate delta                                                    |
//+------------------------------------------------------------------+
double COrderFlowStrategy::CalculateDelta(string symbol)
{
   long buyVolume = 0;
   long sellVolume = 0;
   
   for(int i = 0; i < ArraySize(m_tickBuffer); i++)
   {
      if(m_tickBuffer[i].bid > m_tickBuffer[i].ask)
         buyVolume += m_tickBuffer[i].volume;
      else
         sellVolume += m_tickBuffer[i].volume;
   }
   
   return (double)(buyVolume - sellVolume);
}

//+------------------------------------------------------------------+
//| Volatility Breakout Strategy Constructor                            |
//+------------------------------------------------------------------+
CVolatilityBreakoutStrategy::CVolatilityBreakoutStrategy()
{
   m_type = STRAT_BREAKOUT;
   m_name = "VolatilityBreakout";
   m_londonSession = "07:00-10:00";
   m_nySession = "13:00-16:00";
   m_breakoutThresholdATR = 1.5;
   m_confirmVolumeIncrease = true;
   m_newsVolatilityMode = "disable";
   m_sessionHigh = 0;
   m_sessionLow = 0;
   m_sessionStartTime = 0;
   m_breakoutTriggered = false;
}

//+------------------------------------------------------------------+
//| Volatility Breakout Strategy Destructor                            |
//+------------------------------------------------------------------+
CVolatilityBreakoutStrategy::~CVolatilityBreakoutStrategy()
{
}

//+------------------------------------------------------------------+
//| Process tick (Volatility Breakout)                                  |
//+------------------------------------------------------------------+
SSignal CVolatilityBreakoutStrategy::ProcessTick(string symbol, const STickData &tick)
{
   SSignal signal;
   signal.type = SIGNAL_NONE;
   
   // Check if in London or NY session
   if(!IsLondonSession() && !IsNYSession())
      return signal;
   
   // Update session levels
   UpdateSessionLevels(symbol);
   
   // Check for breakout
   double atr = CalculateATR(symbol, PERIOD_M1, 14, 0);
   double breakoutDistance = m_breakoutThresholdATR * atr;
   
   if(tick.bid > m_sessionHigh + breakoutDistance && !m_breakoutTriggered)
   {
      // Bullish breakout
      if(!m_confirmVolumeIncrease || CheckVolumeIncrease(symbol))
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double lots = m_riskManager.CalculateLotSize(symbol, m_config.riskPercent, 10.0);
         
         if(lots > 0)
         {
            double sl = tick.ask - 5.0 * point;
            double tp = tick.ask + 10.0 * point;
            signal = CreateSignal(SIGNAL_BUY, symbol, tick.ask, sl, tp, lots, "Breakout Buy");
            m_breakoutTriggered = true;
         }
      }
   }
   else if(tick.bid < m_sessionLow - breakoutDistance && !m_breakoutTriggered)
   {
      // Bearish breakout
      if(!m_confirmVolumeIncrease || CheckVolumeIncrease(symbol))
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double lots = m_riskManager.CalculateLotSize(symbol, m_config.riskPercent, 10.0);
         
         if(lots > 0)
         {
            double sl = tick.bid + 5.0 * point;
            double tp = tick.bid - 10.0 * point;
            signal = CreateSignal(SIGNAL_SELL, symbol, tick.bid, sl, tp, lots, "Breakout Sell");
            m_breakoutTriggered = true;
         }
      }
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Should close (Volatility Breakout)                                 |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::ShouldClose(string symbol, ulong ticket, double currentProfit)
{
   // Check if price has retraced significantly
   if(m_breakoutTriggered)
   {
      double atr = CalculateATR(symbol, PERIOD_M1, 14, 0);
      if(MathAbs(currentProfit) < -atr * 2)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Is London session                                                  |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::IsLondonSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // London session: 07:00-10:00 GMT
   return (currentMinutes >= 420 && currentMinutes < 600);
}

//+------------------------------------------------------------------+
//| Is NY session                                                      |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::IsNYSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // NY session: 13:00-16:00 GMT
   return (currentMinutes >= 780 && currentMinutes < 960);
}

//+------------------------------------------------------------------+
//| Is Tokyo session                                                   |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::IsTokyoSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // Tokyo session: 00:00-09:00 GMT
   return (currentMinutes >= 0 && currentMinutes < 540);
}

//+------------------------------------------------------------------+
//| Is Sydney session                                                  |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::IsSydneySession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // Sydney session: 22:00-07:00 GMT
   return (currentMinutes >= 1320 || currentMinutes < 420);
}

//+------------------------------------------------------------------+
//| Check volume increase                                              |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::CheckVolumeIncrease(string symbol)
{
   long currentVolume = SymbolInfoInteger(symbol, SYMBOL_VOLUME);
   long avgVolume = (long)GetAverageVolume(symbol, PERIOD_M1, 20);
   
   return (currentVolume > avgVolume * 1.5);
}

//+------------------------------------------------------------------+
//| Update session levels                                              |
//+------------------------------------------------------------------+
void CVolatilityBreakoutStrategy::UpdateSessionLevels(string symbol)
{
   if(TimeCurrent() - m_sessionStartTime > PeriodSeconds(PERIOD_H1))
   {
      m_sessionHigh = iHigh(symbol, PERIOD_M1, 1);
      m_sessionLow = iLow(symbol, PERIOD_M1, 1);
      m_sessionStartTime = TimeCurrent();
      m_breakoutTriggered = false;
   }
   else
   {
      m_sessionHigh = MathMax(m_sessionHigh, iHigh(symbol, PERIOD_M1, 0));
      m_sessionLow = MathMin(m_sessionLow, iLow(symbol, PERIOD_M1, 0));
   }
}

//+------------------------------------------------------------------+
//| Is breakout valid                                                    |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::IsBreakoutValid(string symbol, double price)
{
   return (price > m_sessionHigh || price < m_sessionLow);
}

//+------------------------------------------------------------------+
//| Market Making Strategy Constructor                                  |
//+------------------------------------------------------------------+
CMarketMakingStrategy::CMarketMakingStrategy()
{
   m_type = STRAT_MARKET_MAKING;
   m_name = "MarketMaking";
   m_spreadCapturePercent = 0.5;
   m_inventoryLimitLots = 5.0;
   m_rebalanceThreshold = 0.2;
   m_volatilityAdjustment = true;
   m_maxPositionImbalance = 2.0;
   m_currentInventory = 0;
   m_spreadCapturePrice = 0;
}

//+------------------------------------------------------------------+
//| Process tick (Market Making)                                       |
//+------------------------------------------------------------------+
SSignal CMarketMakingStrategy::ProcessTick(string symbol, const STickData &tick)
{
   SSignal signal;
   signal.type = SIGNAL_NONE;
   
   // Check inventory limits
   if(MathAbs(m_currentInventory) >= m_inventoryLimitLots)
      return signal;
   
   double currentSpread = tick.ask - tick.bid;
   double optimalSpread = CalculateOptimalSpread(symbol);
   
   if(currentSpread > optimalSpread * m_spreadCapturePercent)
   {
      double lots = m_riskManager.CalculateLotSize(symbol, m_config.riskPercent * 0.5, 2.0);
      
      if(lots > 0)
      {
         if(m_currentInventory < m_maxPositionImbalance)
         {
            double sl = tick.ask - 2.0 * SymbolInfoDouble(symbol, SYMBOL_POINT);
            signal = CreateSignal(SIGNAL_BUY, symbol, tick.ask, sl, 0, lots, "Market Maker Buy");
            m_currentInventory += lots;
         }
         else if(m_currentInventory > -m_maxPositionImbalance)
         {
            double sl = tick.bid + 2.0 * SymbolInfoDouble(symbol, SYMBOL_POINT);
            signal = CreateSignal(SIGNAL_SELL, symbol, tick.bid, sl, 0, lots, "Market Maker Sell");
            m_currentInventory -= lots;
         }
      }
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Should close (Market Making)                                       |
//+------------------------------------------------------------------+
bool CMarketMakingStrategy::ShouldClose(string symbol, ulong ticket, double currentProfit)
{
   // Check if we should rebalance inventory
   return ShouldRebalance(symbol);
}

//+------------------------------------------------------------------+
//| Calculate optimal spread                                           |
//+------------------------------------------------------------------+
double CMarketMakingStrategy::CalculateOptimalSpread(string symbol)
{
   double atr = CalculateATR(symbol, PERIOD_M1, 14, 0);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   return atr / point * m_spreadCapturePercent;
}

//+------------------------------------------------------------------+
//| Calculate inventory exposure                                       |
//+------------------------------------------------------------------+
double CMarketMakingStrategy::CalculateInventoryExposure(string symbol)
{
   return m_currentInventory;
}

//+------------------------------------------------------------------+
//| Should rebalance                                                   |
//+------------------------------------------------------------------+
bool CMarketMakingStrategy::ShouldRebalance(string symbol)
{
   return (MathAbs(m_currentInventory) > m_inventoryLimitLots * m_rebalanceThreshold);
}

//+------------------------------------------------------------------+
//| Get dynamic spread                                                 |
//+------------------------------------------------------------------+
double CMarketMakingStrategy::GetDynamicSpread(string symbol)
{
   double baseSpread = CalculateOptimalSpread(symbol);
   double atr = CalculateATR(symbol, PERIOD_M1, 14, 0);
   
   if(m_volatilityAdjustment)
      return baseSpread * (1.0 + atr);
   
   return baseSpread;
}

//+------------------------------------------------------------------+
//| Mean Reversion Strategy Constructor                                 |
//+------------------------------------------------------------------+
CMeanReversionStrategy::CMeanReversionStrategy()
{
   m_type = STRAT_MEAN_REVERSION;
   m_name = "MeanReversion";
   m_vwapDeviationThreshold = 0.3;
   m_reversalConfirmationCandles = 3;
   m_liquidityGrabDetection = true;
   m_stopLossMultiplier = 1.5;
   m_vwapValue = 0;
}

//+------------------------------------------------------------------+
//| Process tick (Mean Reversion)                                      |
//+------------------------------------------------------------------+
SSignal CMeanReversionStrategy::ProcessTick(string symbol, const STickData &tick)
{
   SSignal signal;
   signal.type = SIGNAL_NONE;
   
   // Calculate VWAP and deviation
   double vwap = CalculateVWAP(symbol, 0);
   double deviation = CalculateVWAPDeviation(symbol);
   
   if(MathAbs(deviation) > m_vwapDeviationThreshold)
   {
      double lots = m_riskManager.CalculateLotSize(symbol, m_config.riskPercent, 5.0);
      
      if(lots > 0)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         
         if(deviation > 0 && DetectReversalCandles(symbol, m_reversalConfirmationCandles))
         {
            // Price is above VWAP and showing reversal
            double sl = tick.ask + 3.0 * point * m_stopLossMultiplier;
            double tp = vwap;
            signal = CreateSignal(SIGNAL_SELL, symbol, tick.bid, sl, tp, lots, "Mean Reversion Sell");
         }
         else if(deviation < 0 && DetectReversalCandles(symbol, m_reversalConfirmationCandles))
         {
            // Price is below VWAP and showing reversal
            double sl = tick.bid - 3.0 * point * m_stopLossMultiplier;
            double tp = vwap;
            signal = CreateSignal(SIGNAL_BUY, symbol, tick.ask, sl, tp, lots, "Mean Reversion Buy");
         }
      }
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Should close (Mean Reversion)                                      |
//+------------------------------------------------------------------+
bool CMeanReversionStrategy::ShouldClose(string symbol, ulong ticket, double currentProfit)
{
   // Check if price has reverted to mean
   double vwap = CalculateVWAP(symbol, 0);
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   if(MathAbs(currentPrice - vwap) < SymbolInfoDouble(symbol, SYMBOL_POINT) * 2)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Calculate VWAP deviation                                           |
//+------------------------------------------------------------------+
double CMeanReversionStrategy::CalculateVWAPDeviation(string symbol)
{
   double vwap = CalculateVWAP(symbol, 0);
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   if(vwap > 0)
      return (currentPrice - vwap) / vwap;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Detect reversal candles                                            |
//+------------------------------------------------------------------+
bool CMeanReversionStrategy::DetectReversalCandles(string symbol, int requiredCandles)
{
   MqlRates rates[];
   if(CopyRates(symbol, PERIOD_M1, 0, requiredCandles + 1, rates) < requiredCandles + 1)
      return false;
   
   bool bullishReversal = true;
   bool bearishReversal = true;
   
   for(int i = 1; i <= requiredCandles; i++)
   {
      if(rates[i].close >= rates[i].open)
         bearishReversal = false;
      if(rates[i].close <= rates[i].open)
         bullishReversal = false;
   }
   
   return (bullishReversal || bearishReversal);
}

//+------------------------------------------------------------------+
//| Detect liquidity grab                                              |
//+------------------------------------------------------------------+
bool CMeanReversionStrategy::DetectLiquidityGrab(string symbol)
{
   if(!m_liquidityGrabDetection)
      return false;
   
   MqlRates rates[];
   if(CopyRates(symbol, PERIOD_M1, 0, 5, rates) < 5)
      return false;
   
   // Check for sudden spike followed by reversal
   double avgRange = 0;
   for(int i = 1; i < 5; i++)
   {
      avgRange += (rates[i].high - rates[i].low);
   }
   avgRange /= 4.0;
   
   double currentRange = rates[0].high - rates[0].low;
   
   return (currentRange > avgRange * 3.0); // 3x average range indicates liquidity grab
}

//+------------------------------------------------------------------+
//| Calculate VWAP                                                       |
//+------------------------------------------------------------------+
double CMeanReversionStrategy::CalculateVWAP(string symbol, int shift)
{
   // Simple VWAP calculation (can be improved with proper tick data)
   MqlRates rates[];
   int copied = CopyRates(symbol, PERIOD_M1, shift, 20, rates);
   if(copied < 20)
      return 0.0;
   
   double sumPV = 0;
   double sumV = 0;
   
   for(int i = 0; i < copied; i++)
   {
      double typicalPrice = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double volume = (double)rates[i].tick_volume;
      
      sumPV += typicalPrice * volume;
      sumV += volume;
   }
   
   if(sumV > 0)
      return sumPV / sumV;
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| Strategy Factory - Create Strategy                                   |
//+------------------------------------------------------------------+
CStrategy* CStrategyFactory::CreateStrategy(ENUM_STRATEGY_TYPE type)
{
   switch(type)
   {
      case STRAT_SCALPING:
         return new CScalpingStrategy();
      
      case STRAT_ORDER_FLOW:
         return new COrderFlowStrategy();
      
      case STRAT_MARKET_MAKING:
         return new CMarketMakingStrategy();
      
      case STRAT_BREAKOUT:
         return new CVolatilityBreakoutStrategy();
      
      case STRAT_MEAN_REVERSION:
         return new CMeanReversionStrategy();
      
      default:
         Print("Unknown strategy type");
         return NULL;
   }
}

//+------------------------------------------------------------------+
//| Strategy Factory - Destroy Strategy                                  |
//+------------------------------------------------------------------+
void CStrategyFactory::DestroyStrategy(CStrategy* strategy)
{
   if(strategy != NULL)
      delete strategy;
}

//+------------------------------------------------------------------+
//| Helper methods for CStrategy                                          |
//+------------------------------------------------------------------+
double CStrategy::CalculateATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double atr = 0;
   int handle = iATR(symbol, tf, period);
   if(handle != INVALID_HANDLE)
   {
      CopyBuffer(handle, 0, shift, 1, m_bufferPrice);
      atr = m_bufferPrice[0];
      IndicatorRelease(handle);
   }
   return atr;
}

double CStrategy::CalculateBollingerBand(string symbol, ENUM_TIMEFRAMES tf, int period, double deviation, ENUM_BAND_LINE bandLine, int shift)
{
   double bbValue = 0;
   int handle = iBands(symbol, tf, period, 0, deviation, PRICE_CLOSE);
   if(handle != INVALID_HANDLE)
   {
      CopyBuffer(handle, bandLine, shift, 1, m_bufferPrice);
      bbValue = m_bufferPrice[0];
      IndicatorRelease(handle);
   }
   return bbValue;
}

double CStrategy::CalculateVWAP(string symbol, int shift)
{
   // Implementation similar to the one in Mean Reversion strategy
   MqlRates rates[];
   int copied = CopyRates(symbol, PERIOD_M1, shift, 20, rates);
   if(copied < 20)
      return 0.0;
   
   double sumPV = 0;
   double sumV = 0;
   
   for(int i = 0; i < copied; i++)
   {
      double typicalPrice = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double volume = (double)rates[i].tick_volume;
      
      sumPV += typicalPrice * volume;
      sumV += volume;
   }
   
   if(sumV > 0)
      return sumPV / sumV;
   
   return 0.0;
}

double CStrategy::GetAverageVolume(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   long totalVolume = 0;
   MqlRates rates[];
   int copied = CopyRates(symbol, tf, 0, period, rates);
   
   for(int i = 0; i < copied; i++)
   {
      totalVolume += rates[i].tick_volume;
   }
   
   if(copied > 0)
      return (double)totalVolume / copied;
   
   return 0.0;
}

double CStrategy::GetVolumeImbalance(string symbol)
{
   // Simplified - would use actual tick data for proper calculation
   long buyVolume = SymbolInfoInteger(symbol, SYMBOL_VOLUME_BUY);
   long sellVolume = SymbolInfoInteger(symbol, SYMBOL_VOLUME_SELL);
   long totalVolume = buyVolume + sellVolume;
   
   if(totalVolume > 0)
      return (double)(buyVolume - sellVolume) / totalVolume;
   
   return 0.0;
}

double CStrategy::GetPriceVelocity(string symbol, int bars)
{
   MqlRates rates[];
   int copied = CopyRates(symbol, PERIOD_M1, 0, bars + 1, rates);
   if(copied < 2)
      return 0.0;
   
   double priceChange = rates[copied - 1].close - rates[0].close;
   int timeSpan = (int)(rates[copied - 1].time - rates[0].time);
   
   if(timeSpan > 0)
      return priceChange / timeSpan;
   
   return 0.0;
}

#endif // HG_STRATEGIES_MQH
