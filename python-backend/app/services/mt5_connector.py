"""MetaTrader 5 connector for executing trades and retrieving market data."""

import time
import threading
from datetime import datetime
from typing import Optional, List, Dict, Any, Tuple
from dataclasses import dataclass

from ..core.logger import logger
from ..core.config import get_config

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    logger.warning("MetaTrader5 module not available. Install with: pip install MetaTrader5")


@dataclass
class MT5TradeRequest:
    """Trade request for MT5."""
    symbol: str
    direction: str  # 'BUY' or 'SELL'
    volume: float
    stop_loss: Optional[float] = None
    take_profit: Optional[float] = None
    order_type: str = "MARKET"
    price: Optional[float] = None
    deviation: int = 20
    magic: int = 0
    comment: str = "HFT Bot"
    slippage: float = 0.0


@dataclass
class MT5TradeResult:
    """Trade result from MT5."""
    success: bool
    ticket: int
    volume: float
    price: float
    deal_price: float
    deviation: int
    retcode: int
    message: str
    order_id: int


class MT5Connector:
    """Connector for MetaTrader 5."""
    
    def __init__(self):
        """Initialize MT5 connector."""
        self.config = get_config().mt5
        self.connected = False
        self._lock = threading.Lock()
        
        if not MT5_AVAILABLE:
            logger.error("MetaTrader5 module not available")
    
    def connect(self) -> bool:
        """Connect to MetaTrader 5.
        
        Returns:
            True if connected successfully
        """
        if not MT5_AVAILABLE:
            logger.error("MetaTrader5 module not available")
            return False
        
        try:
            # Initialize MT5 connection
            if not mt5.initialize(path=self.config.path, login=self.config.account, 
                                  password=self.config.password, server=self.config.server):
                logger.error(f"MT5 initialization failed: {mt5.last_error()}")
                return False
            
            # Verify connection
            account_info = mt5.account_info()
            if account_info is None:
                logger.error("Failed to get account info")
                return False
            
            self.connected = True
            logger.info(f"MT5 connected. Account: {account_info.login}, Server: {account_info.server}")
            return True
        
        except Exception as e:
            logger.error(f"MT5 connection error: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from MetaTrader 5."""
        if not MT5_AVAILABLE:
            return
        
        try:
            mt5.shutdown()
            self.connected = False
            logger.info("MT5 disconnected")
        except Exception as e:
            logger.error(f"MT5 disconnect error: {e}")
    
    def is_connected(self) -> bool:
        """Check if connected to MT5.
        
        Returns:
            True if connected
        """
        if not MT5_AVAILABLE:
            return False
        
        try:
            account_info = mt5.account_info()
            return account_info is not None
        except:
            return False
    
    def get_account_info(self) -> Dict[str, Any]:
        """Get account information.
        
        Returns:
            Dictionary with account information
        """
        if not MT5_AVAILABLE or not self.connected:
            return {}
        
        try:
            info = mt5.account_info()
            if info is None:
                return {}
            
            return {
                'login': info.login,
                'server': info.server,
                'balance': info.balance,
                'equity': info.equity,
                'margin': info.margin,
                'free_margin': info.margin_free,
                'margin_level': info.margin_level,
                'leverage': info.leverage,
                'currency': info.currency,
            }
        except Exception as e:
            logger.error(f"Error getting account info: {e}")
            return {}
    
    def send_order(self, request: MT5TradeRequest) -> MT5TradeResult:
        """Send a trade order to MT5.
        
        Args:
            request: Trade request
        
        Returns:
            Trade result
        """
        if not MT5_AVAILABLE or not self.connected:
            return MT5TradeResult(success=False, ticket=0, volume=0, price=0, 
                                  deal_price=0, deviation=0, retcode=-1, 
                                  message="MT5 not connected", order_id=0)
        
        with self._lock:
            try:
                symbol = request.symbol
                
                # Get symbol info
                symbol_info = mt5.symbol_info(symbol)
                if symbol_info is None:
                    return MT5TradeResult(success=False, ticket=0, volume=0, price=0,
                                        deal_price=0, deviation=0, retcode=-1,
                                        message=f"Symbol {symbol} not found", order_id=0)
                
                if not symbol_info.visible:
                    logger.warning(f"Symbol {symbol} is not visible. Attempting to select it...")
                    if not mt5.symbol_select(symbol, True):
                        return MT5TradeResult(success=False, ticket=0, volume=0, price=0,
                                            deal_price=0, deviation=0, retcode=-1,
                                            message=f"Failed to select symbol {symbol}", order_id=0)
                
                # Prepare order parameters
                order = {
                    'symbol': symbol,
                    'volume': request.volume,
                    'type': mt5.ORDER_TYPE_BUY if request.direction == 'BUY' else mt5.ORDER_TYPE_SELL,
                    'price': request.price or (symbol_info.ask if request.direction == 'BUY' else symbol_info.bid),
                    'sl': request.stop_loss or 0.0,
                    'tp': request.take_profit or 0.0,
                    'deviation': request.deviation,
                    'magic': request.magic,
                    'comment': request.comment,
                }
                
                # Send order
                result = mt5.order_send(order)
                
                if result is None:
                    error = mt5.last_error()
                    return MT5TradeResult(success=False, ticket=0, volume=0, price=0,
                                        deal_price=0, deviation=0, retcode=error,
                                        message=f"Order send failed: {error}", order_id=0)
                
                if result.retcode == mt5.TRADE_RETCODE_DONE:
                    return MT5TradeResult(success=True, ticket=result.order, volume=result.volume,
                                        price=result.price, deal_price=result.price,
                                        deviation=result.deviation, retcode=result.retcode,
                                        message="Order executed successfully", order_id=result.order)
                else:
                    return MT5TradeResult(success=False, ticket=result.order, volume=request.volume,
                                        price=0, deal_price=0, deviation=0,
                                        retcode=result.retcode, message=f"Order failed: {result.comment}",
                                        order_id=result.order)
            
            except Exception as e:
                logger.error(f"Error executing order: {e}")
                return MT5TradeResult(success=False, ticket=0, volume=0, price=0,
                                      deal_price=0, deviation=0, retcode=-1,
                                      message=f"Order error: {str(e)}", order_id=0)
    
    def close_position(self, ticket: int, volume: float = 0.0) -> bool:
        """Close an open position.
        
        Args:
            ticket: Position ticket
            volume: Volume to close (0 for full position)
        
        Returns:
            True if closed successfully
        """
        if not MT5_AVAILABLE or not self.connected:
            return False
        
        try:
            position = mt5.positions_get(ticket=ticket)
            if not position:
                logger.warning(f"Position {ticket} not found")
                return False
            
            position = position[0]
            symbol = position.symbol
            
            # Determine order type for close
            if position.type == mt5.ORDER_TYPE_BUY:
                order_type = mt5.ORDER_TYPE_SELL
                price = mt5.symbol_info(symbol).bid
            else:
                order_type = mt5.ORDER_TYPE_BUY
                price = mt5.symbol_info(symbol).ask
            
            close_volume = volume if volume > 0 else position.volume
            
            order = {
                'action': mt5.TRADE_ACTION_DEAL,
                'position': ticket,
                'symbol': symbol,
                'volume': close_volume,
                'type': order_type,
                'price': price,
                'deviation': 20,
                'magic': position.magic,
                'comment': 'HFT Close',
            }
            
            result = mt5.order_send(order)
            
            if result is not None and result.retcode == mt5.TRADE_RETCODE_DONE:
                logger.info(f"Position {ticket} closed successfully")
                return True
            else:
                logger.error(f"Failed to close position {ticket}: {result.comment if result else 'Unknown error'}")
                return False
        
        except Exception as e:
            logger.error(f"Error closing position {ticket}: {e}")
            return False
    
    def modify_position(self, ticket: int, stop_loss: Optional[float] = None, 
                       take_profit: Optional[float] = None) -> bool:
        """Modify an existing position.
        
        Args:
            ticket: Position ticket
            stop_loss: New stop loss (None to keep existing)
            take_profit: New take profit (None to keep existing)
        
        Returns:
            True if modified successfully
        """
        if not MT5_AVAILABLE or not self.connected:
            return False
        
        try:
            position = mt5.positions_get(ticket=ticket)
            if not position:
                return False
            
            position = position[0]
            
            order = {
                'action': mt5.TRADE_ACTION_SLTP,
                'position': ticket,
            }
            
            if stop_loss is not None:
                order['sl'] = stop_loss
            
            if take_profit is not None:
                order['tp'] = take_profit
            
            result = mt5.order_send(order)
            
            return result is not None and result.retcode == mt5.TRADE_RETCODE_DONE
        
        except Exception as e:
            logger.error(f"Error modifying position {ticket}: {e}")
            return False
    
    def get_positions(self) -> List[Dict[str, Any]]:
        """Get all open positions.
        
        Returns:
            List of position dictionaries
        """
        if not MT5_AVAILABLE or not self.connected:
            return []
        
        try:
            positions = mt5.positions_get()
            if positions is None:
                return []
            
            return [{
                'ticket': pos.ticket,
                'symbol': pos.symbol,
                'type': 'BUY' if pos.type == mt5.ORDER_TYPE_BUY else 'SELL',
                'volume': pos.volume,
                'open_price': pos.price_open,
                'current_price': pos.price_current,
                'profit': pos.profit,
                'swap': pos.swap,
                'stop_loss': pos.sl,
                'take_profit': pos.tp,
                'magic': pos.magic,
                'comment': pos.comment,
                'time': pos.time,
            } for pos in positions]
        
        except Exception as e:
            logger.error(f"Error getting positions: {e}")
            return []
    
    def get_orders(self) -> List[Dict[str, Any]]:
        """Get all pending orders.
        
        Returns:
            List of order dictionaries
        """
        if not MT5_AVAILABLE or not self.connected:
            return []
        
        try:
            orders = mt5.orders_get()
            if orders is None:
                return []
            
            return [{
                'ticket': order.ticket,
                'symbol': order.symbol,
                'type': str(order.type),
                'volume': order.volume_current,
                'price_open': order.price_open,
                'price_current': order.price_current,
                'sl': order.sl,
                'tp': order.tp,
                'magic': order.magic,
                'comment': order.comment,
                'time_setup': order.time_setup,
            } for order in orders]
        
        except Exception as e:
            logger.error(f"Error getting orders: {e}")
            return []
    
    def get_tick_data(self, symbol: str) -> Tuple[bool, Dict[str, Any]]:
        """Get latest tick data for a symbol.
        
        Args:
            symbol: Trading symbol
        
        Returns:
            Tuple of (success, tick_data)
        """
        if not MT5_AVAILABLE or not self.connected:
            return False, {}
        
        try:
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                return False, {}
            
            tick_data = {
                'symbol': symbol,
                'bid': tick.bid,
                'ask': tick.ask,
                'last': tick.last,
                'volume': tick.volume,
                'time': datetime.fromtimestamp(tick.time),
                'time_msc': tick.time_msc,
                'flags': tick.flags,
                'spread': round(tick.ask - tick.bid, 5) if tick.ask and tick.bid else 0,
            }
            
            return True, tick_data
        
        except Exception as e:
            logger.error(f"Error getting tick data for {symbol}: {e}")
            return False, {}
    
    def get_ohlc_data(self, symbol: str, timeframe: str = 'M1', count: int = 100, offset: int = 0) -> Dict[str, Any]:
        """Get OHLC data for a symbol.
        
        Args:
            symbol: Trading symbol
            timeframe: Time frame (e.g., 'M1', 'M5', 'H1', 'D1')
            count: Number of bars to retrieve
            offset: Offset from current bar
        
        Returns:
            Dictionary with OHLC data
        """
        if not MT5_AVAILABLE or not self.connected:
            return {}
        
        try:
            tf_map = {
                'M1': mt5.TIMEFRAME_M1,
                'M2': mt5.TIMEFRAME_M2,
                'M3': mt5.TIMEFRAME_M3,
                'M5': mt5.TIMEFRAME_M5,
                'M15': mt5.TIMEFRAME_M15,
                'M30': mt5.TIMEFRAME_M30,
                'H1': mt5.TIMEFRAME_H1,
                'H4': mt5.TIMEFRAME_H4,
                'D1': mt5.TIMEFRAME_D1,
                'W1': mt5.TIMEFRAME_W1,
                'MN1': mt5.TIMEFRAME_MN1,
            }
            
            tf = tf_map.get(timeframe, mt5.TIMEFRAME_M1)
            
            rates = mt5.copy_rates_from_pos(symbol, tf, offset, count)
            if rates is None:
                return {}
            
            return {
                'time': [datetime.fromtimestamp(r[0]) for r in rates],
                'open': [r[1] for r in rates],
                'high': [r[2] for r in rates],
                'low': [r[3] for r in rates],
                'close': [r[4] for r in rates],
                'tick_volume': [r[5] for r in rates],
                'spread': [r[6] for r in rates],
                'real_volume': [r[7] for r in rates],
            }
        
        except Exception as e:
            logger.error(f"Error getting OHLC data for {symbol}: {e}")
            return {}
    
    def get_symbol_info(self, symbol: str) -> Dict[str, Any]:
        """Get symbol information.
        
        Args:
            symbol: Trading symbol
        
        Returns:
            Dictionary with symbol information
        """
        if not MT5_AVAILABLE:
            return {}
        
        try:
            info = mt5.symbol_info(symbol)
            if info is None:
                return {}
            
            return {
                'name': info.name,
                'description': info.description,
                'bid': info.bid,
                'ask': info.ask,
                'last': info.last,
                'spread': info.point * info.ask - info.point * info.bid,
                'point': info.point,
                'digits': info.digits,
                'volume': info.volume,
                'volume_min': info.volume_min,
                'volume_max': info.volume_max,
                'volume_step': info.volume_step,
                'contract_size': info.trade_contract_size,
                'swap_long': info.swap_long,
                'swap_short': info.swap_short,
                'margin_initial': info.margin_initial,
            }
        
        except Exception as e:
            logger.error(f"Error getting symbol info for {symbol}: {e}")
            return {}
    
    def get_market_depth(self, symbol: str, volume: float = 0.1, count: int = 5) -> Dict[str, Any]:
        """Get market depth (Depth of Market) for a symbol.
        
        Args:
            symbol: Trading symbol
            volume: Order volume
            count: Number of levels to retrieve
        
        Returns:
            Dictionary with market depth information
        """
        if not MT5_AVAILABLE:
            return {}
        
        try:
            market_depth = mt5.market_book_get(symbol)
            if market_depth is None:
                return {}
            
            bids = []
            asks = []
            
            for item in market_depth:
                if item.type == mt5.ORDER_TYPE_BUY:
                    bids.append({'price': item.price, 'volume': item.volume})
                elif item.type == mt5.ORDER_TYPE_SELL:
                    asks.append({'price': item.price, 'volume': item.volume})
            
            return {
                'bids': bids[:count],
                'asks': asks[:count],
            }
        
        except Exception as e:
            logger.error(f"Error getting market depth for {symbol}: {e}")
            return {'bids': [], 'asks': []}
    
    def cancel_order(self, ticket: int) -> bool:
        """Cancel a pending order.
        
        Args:
            ticket: Order ticket
        
        Returns:
            True if cancelled successfully
        """
        if not MT5_AVAILABLE or not self.connected:
            return False
        
        try:
            order = {
                'action': mt5.TRADE_ACTION_REMOVE,
                'order': ticket,
            }
            
            result = mt5.order_send(order)
            
            return result is not None and result.retcode == mt5.TRADE_RETCODE_DONE
        
        except Exception as e:
            logger.error(f"Error cancelling order {ticket}: {e}")
            return False
    
    def get_total_profit(self) -> float:
        """Get total profit from all closed trades.
        
        Returns:
            Total profit
            
        """
        if not MT5_AVAILABLE or not self.connected:
            return 0.0
        
        try:
            history = mt5.history_deals_get(days=30)
            if history is None:
                return 0.0
            
            total_profit = sum(deal.profit + deal.commission + deal.swap for deal in history)
            return total_profit
        
        except Exception as e:
            logger.error(f"Error getting total profit: {e}")
            return 0.0
    
    def get_last_error(self) -> str:
        """Get the last error from MT5.
        
        Returns:
            Error description
        """
        if not MT5_AVAILABLE:
            return "MT5 not available"
        
        try:
            error = mt5.last_error()
            return f"Error {error[0]}: {error[1]}"
        except:
            return "Unknown error"


# Global MT5 connector instance
_mt5_connector = None

def get_mt5_connector() -> MT5Connector:
    """Get global MT5 connector instance.
    
    Returns:
        MT5Connector instance
    """
    global _mt5_connector
    if _mt5_connector is None:
        _mt5_connector = MT5Connector()
    return _mt5_connector


def init_mt5_connector() -> MT5Connector:
    """Initialize and connect the MT5 connector."""
    global _mt5_connector
    _mt5_connector = MT5Connector()
    _mt5_connector.connect()
    return _mt5_connector
