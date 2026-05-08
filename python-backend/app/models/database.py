"""Database models and connection management for PostgreSQL."""

from datetime import datetime
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, asdict
from enum import Enum

from sqlalchemy import create_engine, Column, Integer, Float, String, DateTime, Boolean, ForeignKey, Text, Index
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship, Session
from sqlalchemy.pool import QueuePool

from ..core.config import get_config
from ..core.logger import logger

Base = declarative_base()


class TradeStatus(str, Enum):
    """Trade status enumeration."""
    PENDING = "pending"
    OPEN = "open"
    CLOSED = "closed"
    CANCELLED = "cancelled"
    PARTIAL = "partial"
    ERROR = "error"


class SignalType(str, Enum):
    """Signal type enumeration."""
    BUY = "buy"
    SELL = "sell"
    CLOSE = "close"
    MODIFY = "modify"
    NONE = "none"


class StrategyType(str, Enum):
    """Strategy type enumeration."""
    SCALPING = "scalping"
    ORDER_FLOW = "order_flow"
    MARKET_MAKING = "market_making"
    BREAKOUT = "breakout"
    MEAN_REVERSION = "mean_reversion"
    AI = "ai"


class RiskEventLevel(str, Enum):
    """Risk event level enumeration."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


# Database Models
class Trade(Base):
    """Trade model for storing trade data."""
    __tablename__ = 'trades'
    
    id = Column(Integer, primary_key=True, index=True)
    ticket = Column(String(50), unique=True, index=True)
    symbol = Column(String(20), index=True)
    direction = Column(String(10), index=True)
    volume = Column(Float)
    open_price = Column(Float)
    close_price = Column(Float)
    stop_loss = Column(Float)
    take_profit = Column(Float)
    profit = Column(Float)
    commission = Column(Float)
    swap = Column(Float)
    spread_at_open = Column(Float)
    slippage = Column(Float)
    open_time = Column(DateTime)
    close_time = Column(DateTime)
    status = Column(String(20), default=TradeStatus.PENDING.value)
    strategy = Column(String(50), index=True)
    magic_number = Column(Integer)
    comment = Column(Text)
    broker_name = Column(String(100))
    account_number = Column(String(50))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Indexes
    __table_args__ = (
        Index('idx_trade_symbol_time', 'symbol', 'open_time'),
        Index('idx_trade_status', 'status'),
        Index('idx_trade_strategy', 'strategy'),
    )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert trade to dictionary."""
        return {
            'id': self.id,
            'ticket': self.ticket,
            'symbol': self.symbol,
            'direction': self.direction,
            'volume': self.volume,
            'open_price': self.open_price,
            'close_price': self.close_price,
            'stop_loss': self.stop_loss,
            'take_profit': self.take_profit,
            'profit': self.profit,
            'commission': self.commission,
            'swap': self.swap,
            'spread_at_open': self.spread_at_open,
            'slippage': self.slippage,
            'open_time': self.open_time.isoformat() if self.open_time else None,
            'close_time': self.close_time.isoformat() if self.close_time else None,
            'status': self.status,
            'strategy': self.strategy,
            'magic_number': self.magic_number,
            'comment': self.comment,
            'broker_name': self.broker_name,
            'account_number': self.account_number,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }


class TickData(Base):
    """Tick data model for storing tick information."""
    __tablename__ = 'tick_data'
    
    id = Column(Integer, primary_key=True)
    symbol = Column(String(20), index=True)
    bid = Column(Float)
    ask = Column(Float)
    spread = Column(Float)
    volume = Column(Integer)
    timestamp = Column(DateTime, index=True)
    latency_ms = Column(Float)
    source = Column(String(50))
    
    # Indexes
    __table_args__ = (
        Index('idx_tick_symbol_time', 'symbol', 'timestamp'),
    )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert tick data to dictionary."""
        return {
            'id': self.id,
            'symbol': self.symbol,
            'bid': self.bid,
            'ask': self.ask,
            'spread': self.spread,
            'volume': self.volume,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None,
            'latency_ms': self.latency_ms,
            'source': self.source,
        }


class TradeSignal(Base):
    """Trade signal model for storing signals."""
    __tablename__ = 'trade_signals'
    
    id = Column(Integer, primary_key=True)
    signal_id = Column(String(100), unique=True, index=True)
    symbol = Column(String(20), index=True)
    signal_type = Column(String(10))
    strategy = Column(String(50))
    entry_price = Column(Float)
    stop_loss = Column(Float)
    take_profit = Column(Float)
    lot_size = Column(Float)
    confidence = Column(Float)
    timestamp = Column(DateTime)
    executed = Column(Boolean, default=False)
    execution_time = Column(DateTime)
    result = Column(String(50))
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert signal to dictionary."""
        return {
            'id': self.id,
            'signal_id': self.signal_id,
            'symbol': self.symbol,
            'signal_type': self.signal_type,
            'strategy': self.strategy,
            'entry_price': self.entry_price,
            'stop_loss': self.stop_loss,
            'take_profit': self.take_profit,
            'lot_size': self.lot_size,
            'confidence': self.confidence,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None,
            'executed': self.executed,
            'execution_time': self.execution_time.isoformat() if self.execution_time else None,
            'result': self.result,
            'notes': self.notes,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


class PerformanceMetric(Base):
    """Performance metric model."""
    __tablename__ = 'performance_metrics'
    
    id = Column(Integer, primary_key=True)
    metric_name = Column(String(100), index=True)
    metric_value = Column(Float)
    metric_type = Column(String(50))
    period = Column(String(50))
    start_date = Column(DateTime)
    end_date = Column(DateTime)
    timestamp = Column(DateTime, default=datetime.utcnow)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert metric to dictionary."""
        return {
            'id': self.id,
            'metric_name': self.metric_name,
            'metric_value': self.metric_value,
            'metric_type': self.metric_type,
            'period': self.period,
            'start_date': self.start_date.isoformat() if self.start_date else None,
            'end_date': self.end_date.isoformat() if self.end_date else None,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None,
        }


class RiskEvent(Base):
    """Risk event model."""
    __tablename__ = 'risk_events'
    
    id = Column(Integer, primary_key=True)
    event_type = Column(String(50), index=True)
    level = Column(String(20))
    description = Column(Text)
    symbol = Column(String(20), index=True)
    trade_id = Column(String(50))
    value = Column(Float)
    threshold = Column(Float)
    triggered_at = Column(DateTime, default=datetime.utcnow)
    resolved = Column(Boolean, default=False)
    resolution = Column(Text)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert risk event to dictionary."""
        return {
            'id': self.id,
            'event_type': self.event_type,
            'level': self.level,
            'description': self.description,
            'symbol': self.symbol,
            'trade_id': self.trade_id,
            'value': self.value,
            'threshold': self.threshold,
            'triggered_at': self.triggered_at.isoformat() if self.triggered_at else None,
            'resolved': self.resolved,
            'resolution': self.resolution,
        }


class StrategyPerformance(Base):
    """Strategy performance model."""
    __tablename__ = 'strategy_performance'
    
    id = Column(Integer, primary_key=True)
    strategy_name = Column(String(50), index=True)
    symbol = Column(String(20), index=True)
    total_trades = Column(Integer)
    winning_trades = Column(Integer)
    losing_trades = Column(Integer)
    total_profit = Column(Float)
    total_loss = Column(Float)
    average_profit = Column(Float)
    average_loss = Column(Float)
    largest_profit = Column(Float)
    largest_loss = Column(Float)
    win_rate = Column(Float)
    profit_factor = Column(Float)
    sharpe_ratio = Column(Float)
    max_drawdown = Column(Float)
    average_trade_duration = Column(Float)
    period = Column(String(50))
    timestamp = Column(DateTime, default=datetime.utcnow)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert strategy performance to dictionary."""
        return {
            'id': self.id,
            'strategy_name': self.strategy_name,
            'symbol': self.symbol,
            'total_trades': self.total_trades,
            'winning_trades': self.winning_trades,
            'losing_trades': self.losing_trades,
            'total_profit': self.total_profit,
            'total_loss': self.total_loss,
            'average_profit': self.average_profit,
            'average_loss': self.average_loss,
            'largest_profit': self.largest_profit,
            'largest_loss': self.largest_loss,
            'win_rate': self.win_rate,
            'profit_factor': self.profit_factor,
            'sharpe_ratio': self.sharpe_ratio,
            'max_drawdown': self.max_drawdown,
            'average_trade_duration': self.average_trade_duration,
            'period': self.period,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None,
        }


class DailySummary(Base):
    """Daily summary model."""
    __tablename__ = 'daily_summary'
    
    id = Column(Integer, primary_key=True)
    date = Column(DateTime, index=True, unique=True)
    starting_balance = Column(Float)
    ending_balance = Column(Float)
    daily_pnl = Column(Float)
    total_trades = Column(Integer)
    winning_trades = Column(Integer)
    losing_trades = Column(Integer)
    max_drawdown = Column(Float)
    max_concurrent_positions = Column(Integer)
    total_volume = Column(Float)
    average_spread = Column(Float)
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert daily summary to dictionary."""
        return {
            'id': self.id,
            'date': self.date.isoformat() if self.date else None,
            'starting_balance': self.starting_balance,
            'ending_balance': self.ending_balance,
            'daily_pnl': self.daily_pnl,
            'total_trades': self.total_trades,
            'winning_trades': self.winning_trades,
            'losing_trades': self.losing_trades,
            'max_drawdown': self.max_drawdown,
            'max_concurrent_positions': self.max_concurrent_positions,
            'total_volume': self.total_volume,
            'average_spread': self.average_spread,
            'notes': self.notes,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


class DatabaseManager:
    """Database manager for PostgreSQL operations."""
    
    def __init__(self):
        """Initialize database manager."""
        self.config = get_config().database
        self.engine = None
        self.SessionLocal = None
        self._init_database()
    
    def _init_database(self):
        """Initialize database engine and tables."""
        try:
            # Create engine
            connection_string = f"postgresql://{self.config.username}:{self.config.password}@{self.config.host}:{self.config.port}/{self.config.database}"
            
            self.engine = create_engine(
                connection_string,
                poolclass=QueuePool,
                pool_size=self.config.pool_size,
                max_overflow=self.config.max_overflow,
                pool_timeout=self.config.pool_timeout,
                pool_recycle=3600,
                echo=False
            )
            
            # Create tables
            Base.metadata.create_all(self.engine)
            
            # Create session factory
            self.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=self.engine)
            
            logger.info("Database initialized successfully")
        
        except Exception as e:
            logger.error(f"Database initialization error: {e}")
            raise
    
    def get_session(self) -> Session:
        """Get database session.
        
        Returns:
            Database session
        """
        return self.SessionLocal()
    
    def create_trade(self, trade_data: Dict[str, Any]) -> Optional[Trade]:
        """Create new trade record.
        
        Args:
            trade_data: Trade data dictionary
        
        Returns:
            Created trade record or None
        """
        session = self.get_session()
        try:
            trade = Trade(**trade_data)
            session.add(trade)
            session.commit()
            session.refresh(trade)
            logger.debug(f"Created trade: {trade.ticket}")
            return trade
        except Exception as e:
            session.rollback()
            logger.error(f"Error creating trade: {e}")
            return None
        finally:
            session.close()
    
    def get_trade_by_ticket(self, ticket: str) -> Optional[Trade]:
        """Get trade by ticket number.
        
        Args:
            ticket: Trade ticket number
        
        Returns:
            Trade record or None
        """
        session = self.get_session()
        try:
            return session.query(Trade).filter(Trade.ticket == ticket).first()
        except Exception as e:
            logger.error(f"Error getting trade: {e}")
            return None
        finally:
            session.close()
    
    def update_trade_status(self, ticket: str, status: str, **kwargs) -> bool:
        """Update trade status.
        
        Args:
            ticket: Trade ticket number
            status: New status
            **kwargs: Additional fields to update
        
        Returns:
            True if updated successfully
        """
        session = self.get_session()
        try:
            trade = session.query(Trade).filter(Trade.ticket == ticket).first()
            if trade:
                trade.status = status
                for key, value in kwargs.items():
                    setattr(trade, key, value)
                session.commit()
                return True
            return False
        except Exception as e:
            session.rollback()
            logger.error(f"Error updating trade: {e}")
            return False
        finally:
            session.close()
    
    def record_tick_data(self, tick_data: Dict[str, Any]) -> bool:
        """Record tick data.
        
        Args:
            tick_data: Tick data dictionary
        
        Returns:
            True if recorded successfully
        """
        session = self.get_session()
        try:
            tick = TickData(**tick_data)
            session.add(tick)
            session.commit()
            return True
        except Exception as e:
            session.rollback()
            logger.error(f"Error recording tick: {e}")
            return False
        finally:
            session.close()
    
    def create_signal(self, signal_data: Dict[str, Any]) -> Optional[TradeSignal]:
        """Create new trade signal.
        
        Args:
            signal_data: Signal data dictionary
        
        Returns:
            Created signal record or None
        """
        session = self.get_session()
        try:
            signal = TradeSignal(**signal_data)
            session.add(signal)
            session.commit()
            session.refresh(signal)
            return signal
        except Exception as e:
            session.rollback()
            logger.error(f"Error creating signal: {e}")
            return None
        finally:
            session.close()
    
    def record_risk_event(self, event_data: Dict[str, Any]) -> bool:
        """Record risk event.
        
        Args:
            event_data: Risk event data dictionary
        
        Returns:
            True if recorded successfully
        """
        session = self.get_session()
        try:
            event = RiskEvent(**event_data)
            session.add(event)
            session.commit()
            return True
        except Exception as e:
            session.rollback()
            logger.error(f"Error recording risk event: {e}")
            return False
        finally:
            session.close()
    
    def record_performance_metric(self, metric_data: Dict[str, Any]) -> bool:
        """Record performance metric.
        
        Args:
            metric_data: Performance metric data dictionary
        
        Returns:
            True if recorded successfully
        """
        session = self.get_session()
        try:
            metric = PerformanceMetric(**metric_data)
            session.add(metric)
            session.commit()
            return True
        except Exception as e:
            session.rollback()
            logger.error(f"Error recording performance metric: {e}")
            return False
        finally:
            session.close()
    
    def record_strategy_performance(self, performance_data: Dict[str, Any]) -> bool:
        """Record strategy performance.
        
        Args:
            performance_data: Strategy performance data dictionary
        
        Returns:
            True if recorded successfully
        """
        session = self.get_session()
        try:
            performance = StrategyPerformance(**performance_data)
            session.add(performance)
            session.commit()
            return True
        except Exception as e:
            session.rollback()
            logger.error(f"Error recording strategy performance: {e}")
            return False
        finally:
            session.close()
    
    def get_trades_for_period(self, start_date: datetime, end_date: datetime, symbol: Optional[str] = None) -> List[Trade]:
        """Get trades for a specific period.
        
        Args:
            start_date: Start date
            end_date: End date
            symbol: Optional symbol filter
        
        Returns:
            List of trade records
        """
        session = self.get_session()
        try:
            query = session.query(Trade).filter(
                Trade.open_time >= start_date,
                Trade.open_time <= end_date
            )
            
            if symbol:
                query = query.filter(Trade.symbol == symbol)
            
            return query.all()
        except Exception as e:
            logger.error(f"Error getting trades: {e}")
            return []
        finally:
            session.close()
    
    def get_daily_summary(self, date: datetime) -> Optional[DailySummary]:
        """Get daily summary for a specific date.
        
        Args:
            date: Date to get summary for
        
        Returns:
            Daily summary record or None
        """
        session = self.get_session()
        try:
            return session.query(DailySummary).filter(
                DailySummary.date == date.date()
            ).first()
        except Exception as e:
            logger.error(f"Error getting daily summary: {e}")
            return None
        finally:
            session.close()
    
    def create_daily_summary(self, summary_data: Dict[str, Any]) -> Optional[DailySummary]:
        """Create daily summary.
        
        Args:
            summary_data: Summary data dictionary
        
        Returns:
            Created summary record or None
        """
        session = self.get_session()
        try:
            summary = DailySummary(**summary_data)
            session.add(summary)
            session.commit()
            session.refresh(summary)
            return summary
        except Exception as e:
            session.rollback()
            logger.error(f"Error creating daily summary: {e}")
            return None
        finally:
            session.close()


# Global database manager instance
_db_manager = None

def get_db_manager() -> DatabaseManager:
    """Get global database manager instance.
    
    Returns:
        DatabaseManager instance
    """
    global _db_manager
    if _db_manager is None:
        _db_manager = DatabaseManager()
    return _db_manager


def init_db_manager() -> DatabaseManager:
    """Initialize database manager."""
    global _db_manager
    _db_manager = DatabaseManager()
    return _db_manager
