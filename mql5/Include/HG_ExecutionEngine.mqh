//+------------------------------------------------------------------+
//|                                        HG_ExecutionEngine.mqh     |
//|                        Ultra-Low Latency Execution System          |
//|                                                                   |
//+------------------------------------------------------------------+
#ifndef HG_EXECUTION_ENGINE_MQH
#define HG_EXECUTION_ENGINE_MQH

#include "HG_Common.mqh"
#include "HG_RiskManagement.mqh"

class CExecutionEngine
{
   private:
      struct SExecutionQueue
      {
         ulong    ticket;
         ENUM_ORDER_TYPE orderType;
         string   symbol;
         double   volume;
         double   price;
         double   stopLoss;
         double   takeProfit;
         datetime expiry;
         string   comment;
         int      magic;
         int      retries;
         ENUM_EXECUTION_STATUS status;
         datetime queuedTime;
         datetime lastAttemptTime;
      };
      
      struct SPositionDuration
      {
         ulong    ticket;
         datetime openTime;
         bool     breakEvenActive;
         double   breakEvenPrice;
      };
      
      MqlTradeRequest      m_request;
      MqlTradeResult       m_result;
      SExecutionConfig    m_config;
      SExecutionQueue     m_queue[];
      SPositionDuration   m_positions[];
      int                 m_queueSize;
      int                 m_maxQueueSize;
      ulong               m_totalOrdersSent;
      ulong               m_totalOrdersFilled;
      ulong               m_totalOrdersRejected;
      double              m_averageSlippage;
      datetime            m_lastExecutionTime;
      double              m_spreadHistory[];
      int                 m_spreadHistorySize;
      
   public:
                         CExecutionEngine();
                        ~CExecutionEngine();
      
      bool              Initialize(const SExecutionConfig &config);
      void              UpdateConfiguration(const SExecutionConfig &config);
      
      // Order execution
      bool              SendMarketOrder(string symbol, ENUM_ORDER_TYPE type, double volume,
                                       double stopLoss, double takeProfit, string comment, int magic);
      bool              SendPendingOrder(string symbol, ENUM_ORDER_TYPE type, double volume,
                                         double price, double stopLoss, double takeProfit,
                                         datetime expiry, string comment, int magic);
      bool              ModifyOrder(ulong ticket, double price, double stopLoss, double takeProfit);
      bool              ClosePosition(ulong ticket, double volume, string comment = "Manual Close");
      bool              CloseAllPositions(string symbol = "", int magic = 0);
      
      // Order management
      bool              CancelPendingOrder(ulong ticket);
      void              ProcessQueue();
      void              CleanUpCompletedOrders();
      
      // Position management
      bool              ModifyPosition(ulong ticket, double newStopLoss, double newTakeProfit);
      bool              ApplyTrailingStop(ulong ticket, double trailingDistance, double stepSize);
      bool              ApplyBreakEven(ulong ticket, double activationDistance, double offset);
      bool              PartialClose(ulong ticket, double closeVolume, string comment = "Partial Close");
      
      // Risk management
      bool              ValidateOrder(string symbol, double volume, double price,
                                       double stopLoss, double takeProfit, ENUM_ORDER_TYPE type);
      double            CalculateSlippage(string symbol, double requestedPrice, double executedPrice,
                                          ENUM_ORDER_TYPE type);
      bool              CheckDuplicateOrder(string symbol, ENUM_ORDER_TYPE type, double volume, int magic);
      
      // Execution monitoring
      double            GetAverageSlippage() const { return m_averageSlippage; }
      ulong             GetTotalOrdersSent() const { return m_totalOrdersSent; }
      ulong             GetTotalOrdersFilled() const { return m_totalOrdersFilled; }
      ulong             GetTotalOrdersRejected() const { return m_totalOrdersRejected; }
      int               GetQueueSize() const { return m_queueSize; }
      
      // Spread monitoring
      void              RecordSpread(string symbol);
      double            GetAverageSpread(string symbol) const;
      double            GetMaxSpread(string symbol) const;
      
      // Utility functions
      static string     OrderTypeToString(ENUM_ORDER_TYPE type);
      static string     ExecutionStatusToString(ENUM_EXECUTION_STATUS status);
      
   protected:
      bool              ExecuteOrderInternal(const SExecutionQueue &order);
      bool              RetryOrder(int queueIndex);
      void              UpdateExecutionMetrics(double slippage, bool filled);
      ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol);
      double            GetPriceForOrderType(string symbol, ENUM_ORDER_TYPE type);
      double            NormalizeStopLoss(string symbol, double price, double stopLoss,
                                        ENUM_ORDER_TYPE type);
      double            NormalizeTakeProfit(string symbol, double price, double takeProfit,
                                            ENUM_ORDER_TYPE type);
      void              AddToQueue(const SExecutionQueue &order);
      void              RemoveFromQueue(int index);
      bool              IsOrderExpired(const SExecutionQueue &order);
};

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CExecutionEngine::CExecutionEngine()
{
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   ZeroMemory(m_config);
   m_queueSize = 0;
   m_maxQueueSize = 100;
   m_totalOrdersSent = 0;
   m_totalOrdersFilled = 0;
   m_totalOrdersRejected = 0;
   m_averageSlippage = 0;
   m_lastExecutionTime = 0;
   ArrayResize(m_queue, m_maxQueueSize);
   ArrayResize(m_positions, m_maxQueueSize);
   ArrayResize(m_spreadHistory, 100);
   m_spreadHistorySize = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CExecutionEngine::~CExecutionEngine()
{
   ArrayFree(m_queue);
   ArrayFree(m_positions);
   ArrayFree(m_spreadHistory);
}

//+------------------------------------------------------------------+
//| Initialize execution engine                                        |
//+------------------------------------------------------------------+
bool CExecutionEngine::Initialize(const SExecutionConfig &config)
{
   m_config = config;
   return true;
}

//+------------------------------------------------------------------+
//| Update configuration                                               |
//+------------------------------------------------------------------+
void CExecutionEngine::UpdateConfiguration(const SExecutionConfig &config)
{
   m_config = config;
}

//+------------------------------------------------------------------+
//| Send market order                                                  |
//+------------------------------------------------------------------+
bool CExecutionEngine::SendMarketOrder(string symbol, ENUM_ORDER_TYPE type, double volume,
                                        double stopLoss, double takeProfit, string comment, int magic)
{
   double price = GetPriceForOrderType(symbol, type);
   
   if(!ValidateOrder(symbol, volume, price, stopLoss, takeProfit, type))
   {
      Print("Order validation failed for ", symbol, " ", EnumToString(type));
      return false;
   }
   
   if(CheckDuplicateOrder(symbol, type, volume, magic))
   {
      Print("Duplicate order detected for ", symbol, " ", EnumToString(type));
      return false;
   }
   
   SExecutionQueue order;
   order.ticket = 0;
   order.orderType = type;
   order.symbol = symbol;
   order.volume = volume;
   order.price = price;
   order.stopLoss = stopLoss;
   order.takeProfit = takeProfit;
   order.expiry = 0;
   order.comment = comment;
   order.magic = magic;
   order.retries = 0;
   order.status = EXEC_PENDING;
   order.queuedTime = TimeCurrent();
   order.lastAttemptTime = TimeCurrent();
   
   if(ExecuteOrderInternal(order))
   {
      m_totalOrdersSent++;
      return true;
   }
   else
   {
      AddToQueue(order);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Send pending order                                                 |
//+------------------------------------------------------------------+
bool CExecutionEngine::SendPendingOrder(string symbol, ENUM_ORDER_TYPE type, double volume,
                                       double price, double stopLoss, double takeProfit,
                                       datetime expiry, string comment, int magic)
{
   if(!ValidateOrder(symbol, volume, price, stopLoss, takeProfit, type))
      return false;
   
   SExecutionQueue order;
   order.ticket = 0;
   order.orderType = type;
   order.symbol = symbol;
   order.volume = volume;
   order.price = price;
   order.stopLoss = stopLoss;
   order.takeProfit = takeProfit;
   order.expiry = expiry;
   order.comment = comment;
   order.magic = magic;
   order.retries = 0;
   order.status = EXEC_PENDING;
   order.queuedTime = TimeCurrent();
   order.lastAttemptTime = TimeCurrent();
   
   if(ExecuteOrderInternal(order))
   {
      m_totalOrdersSent++;
      return true;
   }
   else
   {
      AddToQueue(order);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Close position                                                     |
//+------------------------------------------------------------------+
bool CExecutionEngine::ClosePosition(ulong ticket, double volume, string comment)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("Position not found for ticket #", ticket);
      return false;
   }
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   
   m_request.action = TRADE_ACTION_DEAL;
   m_request.position = ticket;
   m_request.symbol = symbol;
   m_request.volume = volume;
   m_request.deviation = (int)(m_config.maxSlippagePips * 10); // Convert to points
   m_request.magic = (int)PositionGetInteger(POSITION_MAGIC);
   m_request.comment = comment;
   
   // Set price for closing
   if(posType == POSITION_TYPE_BUY)
      m_request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
   else
      m_request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   m_request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   m_request.type_filling = GetFillingMode(symbol);
   
   if(!OrderSend(m_request, m_result))
   {
      Print("Close order failed | Error: ", GetLastError(), " | Ticket: ", ticket);
      return false;
   }
   
   if(m_result.retcode == TRADE_RETCODE_DONE || m_result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      m_totalOrdersFilled++;
      Print("Position closed | Ticket: ", ticket, " | Volume: ", volume);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close all positions                                                |
//+------------------------------------------------------------------+
bool CExecutionEngine::CloseAllPositions(string symbol, int magic)
{
   bool result = true;
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
      
      // Filter by symbol if specified
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      
      // Filter by magic if specified
      if(magic != 0 && (int)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(!ClosePosition(ticket, volume, "Close All"))
         result = false;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Modify order                                                       |
//+------------------------------------------------------------------+
bool CExecutionEngine::ModifyOrder(ulong ticket, double price, double stopLoss, double takeProfit)
{
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   
   m_request.action = TRADE_ACTION_MODIFY;
   m_request.order = ticket;
   
   if(price > 0)
      m_request.price = price;
   if(stopLoss > 0)
      m_request.sl = stopLoss;
   if(takeProfit > 0)
      m_request.tp = takeProfit;
   
   if(!OrderSend(m_request, m_result))
   {
      Print("Modify order failed | Error: ", GetLastError(), " | Ticket: ", ticket);
      return false;
   }
   
   return (m_result.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| Cancel pending order                                               |
//+------------------------------------------------------------------+
bool CExecutionEngine::CancelPendingOrder(ulong ticket)
{
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   
   m_request.action = TRADE_ACTION_REMOVE;
   m_request.order = ticket;
   
   if(!OrderSend(m_request, m_result))
   {
      Print("Cancel order failed | Error: ", GetLastError(), " | Ticket: ", ticket);
      return false;
   }
   
   return (m_result.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| Modify position                                                    |
//+------------------------------------------------------------------+
bool CExecutionEngine::ModifyPosition(ulong ticket, double newStopLoss, double newTakeProfit)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   // Validate new SL/TP
   if(newStopLoss > 0 && !ValidateStopLoss(symbol, currentPrice, newStopLoss,
                                             (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE)))
   {
      Print("Invalid stop loss for position #", ticket);
      return false;
   }
   
   m_request.action = TRADE_ACTION_SLTP;
   m_request.position = ticket;
   m_request.symbol = symbol;
   
   if(newStopLoss > 0)
      m_request.sl = newStopLoss;
   if(newTakeProfit > 0)
      m_request.tp = newTakeProfit;
   
   if(!OrderSend(m_request, m_result))
   {
      Print("Modify SL/TP failed | Error: ", GetLastError(), " | Ticket: ", ticket);
      return false;
   }
   
   return (m_result.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                                |
//+------------------------------------------------------------------+
bool CExecutionEngine::ApplyTrailingStop(ulong ticket, double trailingDistance, double stepSize)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double trailingDistancePrice = trailingDistance * point;
   double stepPrice = stepSize * point;
   
   if(posType == POSITION_TYPE_BUY)
   {
      double newSL = SymbolInfoDouble(symbol, SYMBOL_BID) - trailingDistancePrice;
      newSL = MathFloor(newSL / stepPrice) * stepPrice;
      
      if(newSL > openPrice && (currentSL == 0 || newSL > currentSL + stepPrice))
      {
         return ModifyPosition(ticket, newSL, currentTP);
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double newSL = SymbolInfoDouble(symbol, SYMBOL_ASK) + trailingDistancePrice;
      newSL = MathCeil(newSL / stepPrice) * stepPrice;
      
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - stepPrice))
      {
         return ModifyPosition(ticket, newSL, currentTP);
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Apply break even                                                   |
//+------------------------------------------------------------------+
bool CExecutionEngine::ApplyBreakEven(ulong ticket, double activationDistance, double offset)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double activationPrice = activationDistance * point;
   double offsetPrice = offset * point;
   
   if(posType == POSITION_TYPE_BUY)
   {
      double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(currentPrice >= openPrice + activationPrice)
      {
         double newSL = openPrice + offsetPrice;
         if(currentSL == 0 || newSL > currentSL)
         {
            return ModifyPosition(ticket, newSL, 0);
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double currentPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(currentPrice <= openPrice - activationDistance)
      {
         double newSL = openPrice - offsetPrice;
         if(currentSL == 0 || newSL < currentSL)
         {
            return ModifyPosition(ticket, newSL, 0);
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Partial close                                                      |
//+------------------------------------------------------------------+
bool CExecutionEngine::PartialClose(ulong ticket, double closeVolume, string comment)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   double currentVolume = PositionGetDouble(POSITION_VOLUME);
   
   if(closeVolume >= currentVolume)
   {
      Print("Partial close volume must be less than current position volume");
      return false;
   }
   
   return ClosePosition(ticket, closeVolume, comment);
}

//+------------------------------------------------------------------+
//| Validate order                                                     |
//+------------------------------------------------------------------+
bool CExecutionEngine::ValidateOrder(string symbol, double volume, double price,
                                      double stopLoss, double takeProfit, ENUM_ORDER_TYPE type)
{
   // Check if symbol is available for trading
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL)
   {
      Print("Symbol ", symbol, " is not available for trading");
      return false;
   }
   
   // Check volume limits
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(volume < minLot || volume > maxLot)
   {
      Print("Volume ", volume, " is outside allowed range [", minLot, ", ", maxLot, "]");
      return false;
   }
   
   // Check stop levels
   if(stopLoss > 0)
   {
      int stopLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double minDistance = stopLevel * point;
      
      if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
      {
         if(price - stopLoss < minDistance)
         {
            Print("Stop loss is too close to entry price (min distance: ", minDistance, ")");
            return false;
         }
      }
      else
      {
         if(stopLoss - price < minDistance)
         {
            Print("Stop loss is too close to entry price (min distance: ", minDistance, ")");
            return false;
         }
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate slippage                                                   |
//+------------------------------------------------------------------+
double CExecutionEngine::CalculateSlippage(string symbol, double requestedPrice, double executedPrice,
                                            ENUM_ORDER_TYPE type)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double slippage = 0;
   
   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
   {
      slippage = (executedPrice - requestedPrice) / point;
   }
   else
   {
      slippage = (requestedPrice - executedPrice) / point;
   }
   
   return slippage;
}

//+------------------------------------------------------------------+
//| Check duplicate order                                                |
//+------------------------------------------------------------------+
bool CExecutionEngine::CheckDuplicateOrder(string symbol, ENUM_ORDER_TYPE type, double volume, int magic)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0)
         continue;
      
      if(OrderGetString(ORDER_SYMBOL) == symbol &&
         (int)OrderGetInteger(ORDER_TYPE) == (int)type &&
         MathAbs(OrderGetDouble(ORDER_VOLUME_CURRENT) - volume) < 0.0001 &&
         (int)OrderGetInteger(ORDER_MAGIC) == magic)
      {
         return true;
      }
   }
   
   // Also check positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         (int)PositionGetInteger(POSITION_MAGIC) == magic &&
         MathAbs(PositionGetDouble(POSITION_VOLUME) - volume) < 0.0001)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Process queue                                                      |
//+------------------------------------------------------------------+
void CExecutionEngine::ProcessQueue()
{
   for(int i = m_queueSize - 1; i >= 0; i--)
   {
      if(m_queue[i].status == EXEC_FILLED || m_queue[i].status == EXEC_REJECTED)
      {
         RemoveFromQueue(i);
         continue;
      }
      
      if(m_queue[i].retries >= m_config.maxRetries)
      {
         m_queue[i].status = EXEC_REJECTED;
         m_totalOrdersRejected++;
         RemoveFromQueue(i);
         continue;
      }
      
      // Check if order has expired
      if(m_config.expirationMode != ORDER_TIME_GTC && IsOrderExpired(m_queue[i]))
      {
         m_queue[i].status = EXEC_TIMEOUT;
         RemoveFromQueue(i);
         continue;
      }
      
      // Retry order
      if(!RetryOrder(i))
      {
         m_queue[i].retries++;
         m_queue[i].lastAttemptTime = TimeCurrent();
      }
      else
      {
         m_queue[i].status = EXEC_FILLED;
         m_totalOrdersFilled++;
      }
   }
}

//+------------------------------------------------------------------+
//| Clean up completed orders                                          |
//+------------------------------------------------------------------+
void CExecutionEngine::CleanUpCompletedOrders()
{
   for(int i = m_queueSize - 1; i >= 0; i--)
   {
      if(m_queue[i].status == EXEC_FILLED || m_queue[i].status == EXEC_REJECTED ||
         m_queue[i].status == EXEC_TIMEOUT)
      {
         RemoveFromQueue(i);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute order internally                                           |
//+------------------------------------------------------------------+
bool CExecutionEngine::ExecuteOrderInternal(const SExecutionQueue &order)
{
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   
   m_request.action = TRADE_ACTION_DEAL;
   m_request.symbol = order.symbol;
   m_request.volume = order.volume;
   m_request.price = order.price;
   m_request.deviation = (int)(m_config.maxSlippagePips * 10); // Convert to points
   m_request.type = order.orderType;
   m_request.type_filling = GetFillingMode(order.symbol);
   m_request.magic = order.magic;
   m_request.comment = order.comment;
   
   if(order.stopLoss > 0)
      m_request.sl = order.stopLoss;
   if(order.takeProfit > 0)
      m_request.tp = order.takeProfit;
   
   if(!OrderSend(m_request, m_result))
   {
      int error = GetLastError();
      Print("OrderSend failed: ", error, " - ", GetErrorDescription(error));
      return false;
   }
   
   if(m_result.retcode == TRADE_RETCODE_DONE || m_result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      double slippage = CalculateSlippage(order.symbol, order.price, m_result.price, order.orderType);
      UpdateExecutionMetrics(slippage, true);
      m_totalOrdersFilled++;
      return true;
   }
   else if(m_result.retcode == TRADE_RETCODE_REQUOTE || m_result.retcode == TRADE_RETCODE_PRICE_OFF)
   {
      // Retry with new price
      return false;
   }
   else
   {
      m_totalOrdersRejected++;
      return false;
   }
}

//+------------------------------------------------------------------+
//| Retry order                                                        |
//+------------------------------------------------------------------+
bool CExecutionEngine::RetryOrder(int queueIndex)
{
   if(queueIndex < 0 || queueIndex >= m_queueSize)
      return false;
   
   SExecutionQueue &order = m_queue[queueIndex];
   
   // Update price
   order.price = GetPriceForOrderType(order.symbol, order.orderType);
   
   if(ExecuteOrderInternal(order))
   {
      order.status = EXEC_FILLED;
      return true;
   }
   
   order.retries++;
   return false;
}

//+------------------------------------------------------------------+
//| Update execution metrics                                           |
//+------------------------------------------------------------------+
void CExecutionEngine::UpdateExecutionMetrics(double slippage, bool filled)
{
   if(!filled)
      return;
   
   // Update average slippage
   m_averageSlippage = (m_averageSlippage * (m_totalOrdersFilled - 1) + slippage) / m_totalOrdersFilled;
   
   // Record execution time
   m_lastExecutionTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Get filling mode                                                   |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CExecutionEngine::GetFillingMode(string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   
   if(filling == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   else if(filling == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   else
      return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Get price for order type                                           |
//+------------------------------------------------------------------+
double CExecutionEngine::GetPriceForOrderType(string symbol, ENUM_ORDER_TYPE type)
{
   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
      return SymbolInfoDouble(symbol, SYMBOL_ASK);
   else if(type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)
      return SymbolInfoDouble(symbol, SYMBOL_BID);
   
   return 0;
}

//+------------------------------------------------------------------+
//| Normalize stop loss                                                |
//+------------------------------------------------------------------+
double CExecutionEngine::NormalizeStopLoss(string symbol, double price, double stopLoss,
                                            ENUM_ORDER_TYPE type)
{
   if(stopLoss <= 0)
      return 0;
   
   // Implementation would normalize to valid stop levels
   return stopLoss;
}

//+------------------------------------------------------------------+
//| Normalize take profit                                              |
//+------------------------------------------------------------------+
double CExecutionEngine::NormalizeTakeProfit(string symbol, double price, double takeProfit,
                                              ENUM_ORDER_TYPE type)
{
   if(takeProfit <= 0)
      return 0;
   
   // Implementation would normalize to valid price levels
   return takeProfit;
}

//+------------------------------------------------------------------+
//| Add to queue                                                       |
//+------------------------------------------------------------------+
void CExecutionEngine::AddToQueue(const SExecutionQueue &order)
{
   if(m_queueSize >= m_maxQueueSize)
   {
      m_maxQueueSize += 50;
      ArrayResize(m_queue, m_maxQueueSize);
   }
   
   m_queue[m_queueSize] = order;
   m_queueSize++;
}

//+------------------------------------------------------------------+
//| Remove from queue                                                  |
//+------------------------------------------------------------------+
void CExecutionEngine::RemoveFromQueue(int index)
{
   if(index < 0 || index >= m_queueSize)
      return;
   
   for(int i = index; i < m_queueSize - 1; i++)
   {
      m_queue[i] = m_queue[i + 1];
   }
   
   m_queueSize--;
}

//+------------------------------------------------------------------+
//| Is order expired                                                   |
//+------------------------------------------------------------------+
bool CExecutionEngine::IsOrderExpired(const SExecutionQueue &order)
{
   if(order.expiry <= 0)
      return false;
   
   return (TimeCurrent() >= order.expiry);
}

//+------------------------------------------------------------------+
//| Record spread                                                      |
//+------------------------------------------------------------------+
void CExecutionEngine::RecordSpread(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
   
   if(m_spreadHistorySize < 100)
   {
      m_spreadHistory[m_spreadHistorySize] = spread;
      m_spreadHistorySize++;
   }
   else
   {
      // Shift array
      for(int i = 0; i < 99; i++)
      {
         m_spreadHistory[i] = m_spreadHistory[i + 1];
      }
      m_spreadHistory[99] = spread;
   }
}

//+------------------------------------------------------------------+
//| Get average spread                                                 |
//+------------------------------------------------------------------+
double CExecutionEngine::GetAverageSpread(string symbol) const
{
   if(m_spreadHistorySize == 0)
      return 0;
   
   double sum = 0;
   for(int i = 0; i < m_spreadHistorySize; i++)
   {
      sum += m_spreadHistory[i];
   }
   
   return sum / m_spreadHistorySize;
}

//+------------------------------------------------------------------+
//| Get max spread                                                     |
//+------------------------------------------------------------------+
double CExecutionEngine::GetMaxSpread(string symbol) const
{
   if(m_spreadHistorySize == 0)
      return 0;
   
   double maxSpread = m_spreadHistory[0];
   for(int i = 1; i < m_spreadHistorySize; i++)
   {
      if(m_spreadHistory[i] > maxSpread)
         maxSpread = m_spreadHistory[i];
   }
   
   return maxSpread;
}

//+------------------------------------------------------------------+
//| Order type to string                                               |
//+------------------------------------------------------------------+
string CExecutionEngine::OrderTypeToString(ENUM_ORDER_TYPE type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY:    return "BUY";
      case ORDER_TYPE_SELL:   return "SELL";
      case ORDER_TYPE_BUY_LIMIT:   return "BUY LIMIT";
      case ORDER_TYPE_SELL_LIMIT:  return "SELL LIMIT";
      case ORDER_TYPE_BUY_STOP:  return "BUY STOP";
      case ORDER_TYPE_SELL_STOP: return "SELL STOP";
      default:    return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Execution status to string                                           |
//+------------------------------------------------------------------+
string CExecutionEngine::ExecutionStatusToString(ENUM_EXECUTION_STATUS status)
{
   switch(status)
   {
      case EXEC_PENDING:    return "PENDING";
      case EXEC_SENT:       return "SENT";
      case EXEC_FILLED:     return "FILLED";
      case EXEC_PARTIAL:    return "PARTIAL";
      case EXEC_REJECTED:   return "REJECTED";
      case EXEC_ERROR:      return "ERROR";
      case EXEC_TIMEOUT:    return "TIMEOUT";
      default:              return "UNKNOWN";
   }
}

#endif // HG_EXECUTION_ENGINE_MQH
