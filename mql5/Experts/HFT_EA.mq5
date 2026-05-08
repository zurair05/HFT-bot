//+------------------------------------------------------------------+
//|                                        HFT_EA.mq5                 |
//|                    MetaTrader 5 HFT Expert Advisor                   |
//|                   Institutional-Grade Trading System                 |
//|                                                                      |
//|  Features:                                                           |
//|  - Ultra-low latency tick processing                                 |
//|  - Multi-strategy support                                            |
//|  - Advanced risk management                                          |
//|  - Smart order routing                                               |
//|  - Real-time monitoring                                              |
//|  - Prop firm compliance                                              |
//+------------------------------------------------------------------+
#property copyright "Institutional Trading Desk"
#property link      "trading@institutionaldesk.com"
#property version   "1.00"
#property strict

#include <MqlTrade.mqh>
#include "HG_Common.mqh"
#include "HG_RiskManagement.mqh"
#include "HG_ExecutionEngine.mqh"
#include "HG_Strategies.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                     |
//+------------------------------------------------------------------+
input group "=== Trading Settings ==="
input string   InpTradingSymbols = "EURUSD,GBPUSD,USDJPY,XAUUSD,NAS100,US30";
input int      InpMaxPositions = 5;
input double   InpRiskPerTrade = 1.0;
input double   InpMaxDailyDrawdown = 4.0;
input double   InpMaxTotalDrawdown = 8.0;
input int      InpMagicNumber = 101;

input group "=== HFT Settings ==="
input int      InpMaxSpreadPips = 3;
input int      InpTickBufferSize = 10000;
input int      InpExecutionTimeoutMs = 200;
input int      InpOrderRetryAttempts = 3;

input group "=== Strategy Settings ==="
input bool     InpEnableScalping = true;
input bool     InpEnableOrderFlow = true;
input bool     InpEnableMarketMaking = false;
input bool     InpEnableBreakout = true;
input bool     InpEnableMeanReversion = true;
input int      InpMinSignalConfidence = 70;

input group "=== Risk Management ==="
input double   InpMaxLotSize = 10.0;
input int      InpMaxTradesPerSymbol = 2;
input double   InpMaxSymbolExposurePct = 30.0;
input double   InpMaxCorrelatedExposurePct = 50.0;
input bool     InpUseDynamicLotSizing = true;
input double   InpLotSizeMultiplier = 1.0;

input group "=== Prop Firm Settings ==="
input string   InpPropFirmName = "FTMO";
input double   InpPropAccountSize = 100000.0;
input double   InpPropDailyLossLimit = 4.0;
input bool     InpPropFirmMode = true;
input int      InpMaxPositionDurationMin = 120;

input group "=== Session Settings ==="
input bool     InpLondonSession = true;
input bool     InpNYSession = true;
input bool     InpTokyoSession = false;
input bool     InpSydneySession = false;

input group "=== Communication ==="
input string   InpPythonHost = "127.0.0.1";
input int      InpPythonPort = 8000;
input int      InpRedisPort = 6379;
input bool     InpEnablePythonBridge = true;

//+------------------------------------------------------------------+
//| Global Variables                                                     |
//+------------------------------------------------------------------+
CRiskManager      g_riskManager;
CExecutionEngine g_executionEngine;
CStrategy*       g_strategies[];
SStrategyConfig  g_strategyConfigs[];

// Symbol tracking
string           g_tradingSymbols[];
int              g_symbolCount = 0;
CArrayString     g_symbolArray;

// Execution tracking
ulong            g_totalOrdersSent = 0;
ulong            g_totalOrdersFilled = 0;
ulong            g_totalOrdersRejected = 0;
double           g_totalPnL = 0;
double           g_dailyPnL = 0;

// Tick processing
MqlTick          g_currentTick;
MqlTick          g_previousTick;
bool             g_tickAvailable = false;
long             g_tickProcessingTime = 0;

// Timing and state
datetime         g_lastBarTime = 0;
datetime         g_dailyResetTime = 0;
bool             g_tradingEnabled = true;
bool             g_initialized = false;

//+------------------------------------------------------------------+
//| Expert initialization                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("--- HFT Expert Advisor Initialization ---");
   
   if(!InitializeSymbols())
   {
      Print("Failed to initialize trading symbols");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(!InitializeRiskManager())
   {
      Print("Failed to initialize risk manager");
      return INIT_FAILED;
   }
   
   if(!InitializeExecutionEngine())
   {
      Print("Failed to initialize execution engine");
      return INIT_FAILED;
   }
   
   if(!InitializeStrategies())
   {
      Print("Failed to initialize strategies");
      return INIT_FAILED;
   }
   
   // Setup event timers
   EventSetMillisecondTimer(100); // 100ms timer for check processing
   EventSetTimer(60); // 1-minute timer for daily resets and checks
   
   g_dailyResetTime = TimeCurrent();
   g_initialized = true;
   
   Print("HFT Expert Advisor initialized successfully");
   Print("Trading symbols: ", InpTradingSymbols);
   Print("Risk per trade: ", InpRiskPerTrade, "%");
   Print("Max positions: ", InpMaxPositions);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Clean up strategies
   for(int i = 0; i < ArraySize(g_strategies); i++)
   {
      if(g_strategies[i] != NULL)
      {
         g_strategies[i].Deinitialize();
         delete g_strategies[i];
         g_strategies[i] = NULL;
      }
   }
   
   Print("HFT Expert Advisor deinitialized. Reason: ", EnumToString((ENUM_INIT_REASON)reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized || !g_tradingEnabled)
      return;
   
   // Update current tick
   if(!SymbolInfoTick(_Symbol, g_currentTick))
      return;
   
   g_tickAvailable = true;
   g_previousTick = g_currentTick;
   
   // Process tick for each symbol
   for(int i = 0; i < g_symbolCount; i++)
   {
      string symbol = g_tradingSymbols[i];
      
      if(symbol == "")
         continue;
      
      ProcessTickForSymbol(symbol);
   }
   
   // Update execution queue
   g_executionEngine.ProcessQueue();
   
   // Update risk metrics
   g_riskManager.UpdateMetrics();
   
   // Check auto-disable conditions
   g_riskManager.CheckAutoDisable();
   g_tradingEnabled = g_riskManager.IsTradingEnabled();
}

//+------------------------------------------------------------------+
//| Timer function                                                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_initialized)
      return;
   
   // Daily reset check
   MqlDateTime dt, resetDt;
   TimeToStruct(TimeCurrent(), dt);
   TimeToStruct(g_dailyResetTime, resetDt);
   
   if(dt.day != resetDt.day)
   {
      g_riskManager.ResetDailyCounters();
      g_dailyResetTime = TimeCurrent();
      g_dailyPnL = 0;
      g_tradingEnabled = true;
   }
   
   // Check for positions that need management
   ManageOpenPositions();
   
   // Clean up completed orders
   g_executionEngine.CleanUpCompletedOrders();
   
   // Send status update to Python
   if(InpEnablePythonBridge)
   {
      SendStatusToPython();
   }
}

//+------------------------------------------------------------------+
//| Process tick for symbol                                               |
//+------------------------------------------------------------------+
void ProcessTickForSymbol(string symbol)
{
   if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
      return;
   
   // Get current tick data
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return;
   
   // Create tick data structure
   STickData tickData;
   tickData.time = tick.time;
   tickData.bid = tick.bid;
   tickData.ask = tick.ask;
   tickData.last = tick.last;
   tickData.volume = tick.volume;
   tickData.spread = tick.ask - tick.bid;
   tickData.midpoint = (tick.bid + tick.ask) / 2.0;
   
   // Run each strategy
   for(int i = 0; i < ArraySize(g_strategies); i++)
   {
      if(g_strategies[i] == NULL)
         continue;
      
      CStrategy* strategy = g_strategies[i];
      
      // Check if strategy is enabled for this symbol
      if(!strategy.FilterSymbol(symbol))
         continue;
      
      // Process tick and get signal
      SSignal signal = strategy.ProcessTick(symbol, tickData);
      
      // Process signal if valid
      if(signal.type != SIGNAL_NONE && signal.confidence * 100.0 >= InpMinSignalConfidence)
      {
         ProcessSignal(signal);
      }
   }
}

//+------------------------------------------------------------------+
//| Process trading signal                                              |
//+------------------------------------------------------------------+
void ProcessSignal(const SSignal &signal)
{
   string symbol = signal.symbol;
   
   // Check if we can open a new trade
   if(!g_riskManager.CanOpenNewTrade(symbol, signal.lotSize, signal.type == SIGNAL_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
   {
      return;
   }
   
   // Get filling mode
   ENUM_ORDER_TYPE_FILLING filling = ORDER_FILLING_FOK;
   if((SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE) & SYMBOL_FILLING_IOC) != 0)
      filling = ORDER_FILLING_IOC;
   
   // Execute order
   if(signal.type == SIGNAL_BUY || signal.type == SIGNAL_SELL)
   {
      ENUM_ORDER_TYPE orderType = (signal.type == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double price = (signal.type == SIGNAL_BUY) ? signal.entryPrice : signal.entryPrice;
      
      bool result = g_executionEngine.SendMarketOrder(
         symbol,
         orderType,
         signal.lotSize,
         signal.stopLoss,
         signal.takeProfit,
         signal.comment,
         signal.magic
      );
      
      if(result)
      {
         g_totalOrdersSent++;
         g_totalPnL += (signal.type == SIGNAL_BUY) ? (signal.takeProfit - price) : (price - signal.takeProfit);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                                 |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      // Check if position duration has exceeded maximum
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int durationMin = (int)(TimeCurrent() - openTime) / 60;
      
      if(durationMin > InpMaxPositionDurationMin)
      {
         g_executionEngine.ClosePosition(ticket, PositionGetDouble(POSITION_VOLUME), "Max duration exceeded");
         continue;
      }
      
      // Check break-even
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double breakEvenTrigger = InpPropFirmMode ? 2.0 : 5.0; // pips
      double breakEvenOffset = InpPropFirmMode ? 1.0 : 2.0; // pips
      
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double priceDistance = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point : (openPrice - currentPrice) / point;
      
      if(priceDistance >= breakEvenTrigger)
      {
         g_executionEngine.ApplyBreakEven(ticket, breakEvenTrigger, breakEvenOffset);
      }
      
      // Check trailing stop
      if(InpRiskPerTrade > 0)
      {
         double trailingDistance = 10.0; // pips
         double stepSize = 1.0; // pips
         g_executionEngine.ApplyTrailingStop(ticket, trailingDistance, stepSize);
      }
      
      // Check strategies for close signal
      for(int j = 0; j < ArraySize(g_strategies); j++)
      {
         if(g_strategies[j] == NULL)
            continue;
         
         if(g_strategies[j].ShouldClose(symbol, ticket, profit))
         {
            g_executionEngine.ClosePosition(ticket, PositionGetDouble(POSITION_VOLUME), "Strategy close signal");
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Initialize symbols                                                    |
//+------------------------------------------------------------------+
bool InitializeSymbols()
{
   StringSplit(InpTradingSymbols, ',', g_tradingSymbols);
   g_symbolCount = ArraySize(g_tradingSymbols);
   
   for(int i = 0; i < g_symbolCount; i++)
   {
      StringTrimLeft(g_tradingSymbols[i]);
      StringTrimRight(g_tradingSymbols[i]);
      
      // Select symbol
      if(!SymbolSelect(g_tradingSymbols[i], true))
      {
         Print("Failed to select symbol: ", g_tradingSymbols[i]);
         return false;
      }
      
      // Check if symbol is available for trading
      if(!SymbolInfoInteger(g_tradingSymbols[i], SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL)
      {
         Print("Symbol ", g_tradingSymbols[i], " is not available for trading");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Initialize risk manager                                            |
//+------------------------------------------------------------------+
bool InitializeRiskManager()
{
   SRiskConfig config;
   ZeroMemory(config);
   
   config.maxDailyDrawdownPct = InpMaxDailyDrawdown;
   config.maxTotalDrawdownPct = InpMaxTotalDrawdown;
   config.equityProtectionPct = 85.0;
   config.useDynamicLotSizing = InpUseDynamicLotSizing;
   config.riskPerTradePct = InpRiskPerTrade;
   config.lotSizeMultiplier = InpLotSizeMultiplier;
   config.marginCallLevelPct = 100.0;
   config.maxLotSize = InpMaxLotSize;
   config.maxSimultaneousTrades = InpMaxPositions;
   config.maxTradesPerSymbol = InpMaxTradesPerSymbol;
   config.maxSymbolExposurePct = InpMaxSymbolExposurePct;
   config.maxCorrelatedExposurePct = InpMaxCorrelatedExposurePct;
   config.maxSpreadPips = InpMaxSpreadPips;
   config.highVolatilityFilterEnabled = true;
   config.newsFilterEnabled = true;
   config.dailyLossLimitPct = InpPropDailyLossLimit;
   config.maxPositionDurationMin = InpMaxPositionDurationMin;
   config.londonSession = InpLondonSession;
   config.newYorkSession = InpNYSession;
   config.tokyoSession = InpTokyoSession;
   config.sydneySession = InpSydneySession;
   config.propAccountSize = InpPropAccountSize;
   
   return g_riskManager.Initialize(config);
}

//+------------------------------------------------------------------+
//| Initialize execution engine                                          |
//+------------------------------------------------------------------+
bool InitializeExecutionEngine()
{
   SExecutionConfig config;
   ZeroMemory(config);
   
   config.maxRetries = InpOrderRetryAttempts;
   config.retryDelayMs = 100;
   config.maxSlippagePips = 2.0;
   config.partialFillAccept = true;
   config.minFillPercent = 80.0;
   config.fillingMode = ORDER_FILLING_IOC;
   config.expirationMode = ORDER_TIME_GTC;
   
   return g_executionEngine.Initialize(config);
}

//+------------------------------------------------------------------+
//| Initialize strategies                                                |
//+------------------------------------------------------------------+
bool InitializeStrategies()
{
   ENUM_STRATEGY_TYPE strategyTypes[] = { STRAT_SCALPING, STRAT_ORDER_FLOW, STRAT_MARKET_MAKING, STRAT_BREAKOUT, STRAT_MEAN_REVERSION };
   bool enableFlags[] = { InpEnableScalping, InpEnableOrderFlow, InpEnableMarketMaking, InpEnableBreakout, InpEnableMeanReversion };
   
   int strategyCount = 0;
   
   for(int i = 0; i < ArraySize(strategyTypes); i++)
   {
      if(!enableFlags[i])
         continue;
      
      CStrategy* strategy = CStrategyFactory::CreateStrategy(strategyTypes[i]);
      if(strategy == NULL)
      {
         Print("Failed to create strategy: ", EnumToString(strategyTypes[i]));
         continue;
      }
      
      SStrategyConfig stratConfig;
      ZeroMemory(stratConfig);
      
      stratConfig.enabled = true;
      stratConfig.priority = i + 1;
      stratConfig.riskPercent = InpRiskPerTrade;
      stratConfig.lotSize = 0.01; // Will be calculated by risk manager
      stratConfig.maxSpreadPips = InpMaxSpreadPips;
      stratConfig.magicNumber = InpMagicNumber + i * 100;
      stratConfig.partialCloseEnabled = InpPropFirmMode;
      stratConfig.partialClosePercent = 50.0;
      stratConfig.trailingStopEnabled = true;
      stratConfig.trailingStopPips = 5.0;
      stratConfig.breakEvenEnabled = true;
      
      // Set symbols for different strategies
      if(strategyTypes[i] == STRAT_BREAKOUT)
      {
         string breakoutSymbols[] = { "XAUUSD", "NAS100", "US30" };
         ArrayCopy(stratConfig.symbols, breakoutSymbols);
      }
      else
      {
         string defaultSymbols[] = { "EURUSD", "GBPUSD", "USDJPY" };
         ArrayCopy(stratConfig.symbols, defaultSymbols);
      }
      
      if(!strategy->Initialize(stratConfig, &g_riskManager))
      {
         Print("Failed to initialize strategy: ", EnumToString(strategyTypes[i]));
         delete strategy;
         continue;
      }
      
      // Add to strategies array
      int newSize = strategyCount + 1;
      ArrayResize(g_strategies, newSize);
      g_strategies[strategyCount] = strategy;
      strategyCount++;
   }
   
   return (strategyCount > 0);
}

//+------------------------------------------------------------------+
//| Send status to Python                                              |
//+------------------------------------------------------------------+
void SendStatusToPython()
{
   // Create status JSON string
   string status = "{\"status\": \"running\", \n";
   status += "\"daily_pnl\": " + DoubleToString(g_dailyPnL, 2) + ", \n";
   status += "\"total_pnl\": " + DoubleToString(g_totalPnL, 2) + ", \n";
   status += "\"open_positions\": " + IntegerToString(PositionsTotal()) + ", \n";
   status += "\"pending_orders\": " + IntegerToString(OrdersTotal()) + ", \n";
   status += "\"equity\": " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ", \n";
   status += "\"balance\": " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "} \n";
   
   Print("Status: ", status);
   
   // Here you would send the status to the Python API
   // via HTTP request or Redis
}

//+------------------------------------------------------------------+
//| OnTrade event                                                       |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Update PnL tracking
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_totalPnL = currentEquity - InpPropAccountSize;
   
   // Process any trade events
   int total = HistoryTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryGetTicket(i);
      if(ticket <= 0)
         continue;
      
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      
      if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
      {
         g_dailyPnL += profit;
         g_totalOrdersFilled++;
      }
   }
}

//+------------------------------------------------------------------+
//| ChartEvent                                                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle any chart events if needed
   if(id == CHARTEVENT_KEYDOWN)
   {
      // Handle keyboard shortcuts
      if(lparam == 'Q') // 'Q' key to disable trading
      {
         g_tradingEnabled = false;
         Print("Trading disabled by user");
      }
      else if(lparam == 'S') // 'S' key to enable trading
      {
         g_tradingEnabled = true;
         Print("Trading enabled by user");
      }
   }
}

//+------------------------------------------------------------------+
//| OnTester                                                            |
//+------------------------------------------------------------------+
double OnTester()
{
   // Custom backtesting metrics
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxDrawdown = 0; // Calculate max drawdown
   
   // Return a custom optimization parameter
   if(balance > 0 && maxDrawdown > 0)
      return profit / maxDrawdown;
   
   return profit;
}

//+------------------------------------------------------------------+
//| OnBookEvent                                                           |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
{
   // Process market depth events if needed
   if(!g_initialized)
      return;
   
   // This is triggered when the order book changes
   // Can be used for order flow analysis
}

//+------------------------------------------------------------------+
//| OnCalculate for custom indicator                                    |
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
   // Custom calculations if needed
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Additional utility functions                                        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get account metrics                                                  |
//+------------------------------------------------------------------+
void GetAccountMetrics(double &balance, double &equity, double &margin, double &freeMargin)
{
   balance = AccountInfoDouble(ACCOUNT_BALANCE);
   equity = AccountInfoDouble(ACCOUNT_EQUITY);
   margin = AccountInfoDouble(ACCOUNT_MARGIN);
   freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
}

//+------------------------------------------------------------------+
//| Print trade status                                                  |
//+------------------------------------------------------------------+
void PrintTradeStatus()
{
   Print("=== Trade Status ===");
   Print("Daily PnL: $", DoubleToString(g_dailyPnL, 2));
   Print("Total PnL: $", DoubleToString(g_totalPnL, 2));
   Print("Open Positions: ", PositionsTotal());
   Print("Pending Orders: ", OrdersTotal());
   Print("Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print("Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   Print("Margin Level: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2), "%");
   Print("Total Orders Sent: ", g_totalOrdersSent);
   Print("Total Orders Filled: ", g_totalOrdersFilled);
   Print("Total Orders Rejected: ", g_totalOrdersRejected);
}

//+------------------------------------------------------------------+
//| Emergency stop all trading                                          |
//+------------------------------------------------------------------+
void EmergencyStop()
{
   Print("EMERGENCY STOP ACTIVATED");
   g_tradingEnabled = false;
   
   // Close all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         g_executionEngine.ClosePosition(ticket, PositionGetDouble(POSITION_VOLUME), "Emergency Stop");
      }
   }
   
   // Cancel all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         g_executionEngine.CancelPendingOrder(ticket);
      }
   }
   
   Print("All positions closed and orders cancelled");
}

//+------------------------------------------------------------------+
//| Performance statistics                                                |
//+------------------------------------------------------------------+
void PrintPerformanceStats()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalPnL = equity - balance;
   
   double winRate = (g_totalOrdersSent > 0) ? (double)g_totalOrdersFilled / (double)g_totalOrdersSent * 100.0 : 0.0;
   double fillRate = (g_totalOrdersSent > 0) ? (double)g_totalOrdersFilled / (double)g_totalOrdersSent * 100.0 : 0.0;
   
   Print("=== Performance Statistics ===");
   Print("Total Orders Sent: ", g_totalOrdersSent);
   Print("Total Orders Filled: ", g_totalOrdersFilled);
   Print("Total Orders Rejected: ", g_totalOrdersRejected);
   Print("Win Rate: ", DoubleToString(winRate, 2), "%");
   Print("Fill Rate: ", DoubleToString(fillRate, 2), "%");
   Print("Total PnL: $", DoubleToString(totalPnL, 2));
   Print("Average Slippage: ", DoubleToString(g_executionEngine.GetAverageSlippage(), 2), " pips");
}

//+------------------------------------------------------------------+