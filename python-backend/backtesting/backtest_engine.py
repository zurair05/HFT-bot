"""Backtesting engine for testing and optimization."""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
import json

from ..core.logger import logger
from ..core.config import get_config
from ..ai.predictor import AIPredictor, FeatureEngineering


class SignalType(Enum):
    BUY = "buy"
    SELL = "sell"
    HOLD = "hold"
    CLOSE = "close"


@dataclass
class BacktestConfig:
    """Configuration for backtesting."""
    symbol: str = "EURUSD"
    timeframe: str = "M1"
    start_date: str = "2023-01-01"
    end_date: str = "2023-12-31"
    initial_balance: float = 10000.0
    risk_per_trade: float = 0.01
    commission: float = 0.0
    spread: float = 0.0
    slippage: float = 0.0
    lot_size: float = 0.01
    max_positions: int = 5
    use_sl: bool = True
    use_tp: bool = True
    
    # Strategy test parameters
    use_ai: bool = True
    use_indicators: bool = True
    
    # Performance thresholds
    min_trades: int = 50
    min_sharpe_ratio: float = 0.5
    max_drawdown_limit: float = 0.15


@dataclass
class TradeRecord:
    """Record of a single trade."""
    entry_time: datetime
    exit_time: Optional[datetime] = None
    entry_price: float = 0.0
    exit_price: float = 0.0
    stop_loss: float = 0.0
    take_profit: float = 0.0
    volume: float = 0.0
    direction: str = "buy"
    profit: float = 0.0
    status: str = "open"
    strategy: str = ""
    close_reason: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'entry_time': self.entry_time.isoformat(),
            'exit_time': self.exit_time.isoformat() if self.exit_time else None,
            'entry_price': self.entry_price,
            'exit_price': self.exit_price,
            'stop_loss': self.stop_loss,
            'take_profit': self.take_profit,
            'volume': self.volume,
            'direction': self.direction,
            'profit': self.profit,
            'status': self.status,
            'strategy': self.strategy,
            'close_reason': self.close_reason
        }


class BacktestReport:
    """Comprehensive backtest report."""
    
    def __init__(self):
        self.start_time: Optional[datetime] = None
        self.end_time: Optional[datetime] = None
        self.total_trades: int = 0
        self.winning_trades: int = 0
        self.losing_trades: int = 0
        self.total_profit: float = 0.0
        self.total_loss: float = 0.0
        self.max_drawdown: float = 0.0
        self.max_drawdown_pct: float = 0.0
        self.max_consecutive_losses: int = 0
        self.sharpe_ratio: float = 0.0
        self.profit_factor: float = 0.0
        self.average_win: float = 0.0
        self.average_loss: float = 0.0
        self.largest_win: float = 0.0
        self.largest_loss: float = 0.0
        self.ending_balance: float = 0.0
        self.return_pct: float = 0.0
        self.annualized_return: float = 0.0
        self.volatility: float = 0.0
        self.trades: List[TradeRecord] = []
        self.equity_curve: List[Dict[str, Any]] = []
        self.metrics_per_period: List[Dict[str, Any]] = []
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'start_time': self.start_time.isoformat() if self.start_time else None,
            'end_time': self.end_time.isoformat() if self.end_time else None,
            'total_trades': self.total_trades,
            'winning_trades': self.winning_trades,
            'losing_trades': self.losing_trades,
            'win_rate': self.winning_trades / self.total_trades if self.total_trades > 0 else 0,
            'total_profit': round(self.total_profit, 2),
            'total_loss': round(self.total_loss, 2),
            'net_profit': round(self.total_profit + self.total_loss, 2),
            'max_drawdown': round(self.max_drawdown, 2),
            'max_drawdown_pct': round(self.max_drawdown_pct * 100, 2),
            'sharpe_ratio': round(self.sharpe_ratio, 4),
            'profit_factor': round(self.profit_factor, 4),
            'average_win': round(self.average_win, 2),
            'average_loss': round(self.average_loss, 2),
            'largest_win': round(self.largest_win, 2),
            'largest_loss': round(self.largest_loss, 2),
            'ending_balance': round(self.ending_balance, 2),
            'return_pct': round(self.return_pct * 100, 2),
            'annualized_return': round(self.annualized_return * 100, 2),
            'volatility': round(self.volatility, 4),
            'trades': [t.to_dict() for t in self.trades]
        }


class BacktestEngine:
    """Main backtesting engine."""
    
    def __init__(self, config: BacktestConfig):
        """Initialize backtest engine.
        
        Args:
            config: Backtest configuration
        """
        self.config = config
        self.data: pd.DataFrame = pd.DataFrame()
        self.trades: List[TradeRecord] = []
        self.open_trades: List[TradeRecord] = []
        self.equity: float = config.initial_balance
        self.balance_history: List[Dict[str, Any]] = []
        self.current_date: datetime = datetime.strptime(config.start_date, "%Y-%m-%d")
        
        # AI Components
        if config.use_ai:
            self.ai_predictor = AIPredictor()
        else:
            self.ai_predictor = None
    
    def load_data(self, data_path: str) -> bool:
        """Load historical data for backtesting.
        
        Args:
            data_path: Path to CSV data file
        
        Returns:
            True if data loaded successfully
        """
        try:
            self.data = pd.read_csv(data_path, parse_dates=['time'])
            self.data = self.data.sort_values('time')
            
            # Filter by date range
            start_dt = datetime.strptime(self.config.start_date, "%Y-%m-%d")
            end_dt = datetime.strptime(self.config.end_date, "%Y-%m-%d")
            
            self.data = self.data[(self.data['time'] >= start_dt) & (self.data['time'] <= end_dt)]
            
            logger.info(f"Loaded {len(self.data)} rows of data for {self.config.symbol}")
            return True
        
        except Exception as e:
            logger.error(f"Error loading data: {e}")
            return False
    
    def run_backtest(self) -> BacktestReport:
        """Run the full backtest.
        
        Returns:
            Backtest report
        """
        report = BacktestReport()
        report.start_time = datetime.utcnow()
        
        if len(self.data) == 0:
            logger.error("No data available for backtesting")
            return report
        
        # Iterate through data
        for index, row in self.data.iterrows():
            self.current_date = row['time']
            
            # Check open trades
            self._check_open_trades(row)
            
            # Generate signals and place trades
            signal = self._generate_signal(row)
            if signal and len(self.open_trades) < self.config.max_positions:
                self._place_trade(signal, row)
            
            # Record equity
            self._record_equity(row)
        
        # Close any remaining open trades
        self._close_all_trades(self.data.iloc[-1])
        
        # Calculate metrics
        report.end_time = datetime.utcnow()
        report.trades = self.trades
        report.equity_curve = self.balance_history
        report.ending_balance = self.equity
        
        self._calculate_metrics(report)
        
        return report
    
    def _generate_signal(self, row: pd.Series) -> Optional[Dict[str, Any]]:
        """Generate trading signal based on strategy.
        
        Args:
            row: Current data row
        
        Returns:
            Signal dict or None
        """
        # Simplified signal generation
        # In a real implementation, this would use AI models and technical indicators
        
        if len(self.data) < 20:
            return None
        
        # Simple moving average crossover
        current_price = row['close']
        
        # Calculate SMAs
        if 'sma_10' not in row or 'sma_20' not in row:
            return None
        
        sma_10 = row.get('sma_10', current_price)
        sma_20 = row.get('sma_20', current_price)
        
        if current_price > sma_10 and sma_10 > sma_20:
            return {'type': SignalType.BUY, 'confidence': 0.7, 'price': current_price}
        elif current_price < sma_10 and sma_10 < sma_20:
            return {'type': SignalType.SELL, 'confidence': 0.7, 'price': current_price}
        
        return None
    
    def _place_trade(self, signal: Dict[str, Any], row: pd.Series):
        """Place a trade.
        
        Args:
            signal: Trading signal
            row: Current data row
        """
        current_price = row['close']
        
        # Determine lot size based on risk
        risk_amount = self.equity * self.config.risk_per_trade
        stop_distance = 0.0010  # 10 pips
        lot_size = risk_amount / (stop_distance * 100000)  # Assuming pip value
        
        lot_size = min(lot_size, self.config.lot_size)
        
        trade = TradeRecord(
            entry_time=row['time'],
            entry_price=current_price,
            stop_loss=current_price - stop_distance if signal['type'] == SignalType.BUY else current_price + stop_distance,
            take_profit=current_price + stop_distance * 2 if signal['type'] == SignalType.BUY else current_price - stop_distance * 2,
            volume=lot_size,
            direction=signal['type'].value,
            strategy="backtest"
        )
        
        trade.status = "open"
        self.trades.append(trade)
        self.open_trades.append(trade)
    
    def _check_open_trades(self, row: pd.Series):
        """Check and manage open trades.
        
        Args:
            row: Current data row
        """
        current_price = row['close']
        
        for trade in self.open_trades[:]:
            if trade.status != "open":
                continue
            
            # Check stop loss
            if trade.direction == "buy" and current_price <= trade.stop_loss:
                self._close_trade(trade, row, "stop_loss")
            elif trade.direction == "sell" and current_price >= trade.stop_loss:
                self._close_trade(trade, row, "stop_loss")
            
            # Check take profit
            elif trade.direction == "buy" and current_price >= trade.take_profit:
                self._close_trade(trade, row, "take_profit")
            elif trade.direction == "sell" and current_price <= trade.take_profit:
                self._close_trade(trade, row, "take_profit")
    
    def _close_trade(self, trade: TradeRecord, row: pd.Series, reason: str):
        """Close a trade.
        
        Args:
            trade: Trade to close
            row: Current data row
            reason: Reason for closing
        """
        trade.exit_time = row['time']
        trade.exit_price = row['close']
        trade.status = "closed"
        trade.close_reason = reason
        
        # Calculate profit
        if trade.direction == "buy":
            trade.profit = (trade.exit_price - trade.entry_price) * trade.volume * 100000
        else:
            trade.profit = (trade.entry_price - trade.exit_price) * trade.volume * 100000
        
        # Update equity
        self.equity += trade.profit
        
        if trade in self.open_trades:
            self.open_trades.remove(trade)
    
    def _close_all_trades(self, row: pd.Series):
        """Close all open trades.
        
        Args:
            row: Current data row
        """
        for trade in self.open_trades[:]:
            if trade.status == "open":
                self._close_trade(trade, row, "end_of_backtest")
    
    def _record_equity(self, row: pd.Series):
        """Record equity for a given time.
        
        Args:
            row: Current data row
        """
        self.balance_history.append({
            'time': row['time'],
            'equity': self.equity,
            'open_trades': len(self.open_trades)
        })
    
    def _calculate_metrics(self, report: BacktestReport):
        """Calculate comprehensive metrics.
        
        Args:
            report: Backtest report to populate
        """
        closed_trades = [t for t in self.trades if t.status == "closed"]
        report.total_trades = len(closed_trades)
        
        if report.total_trades == 0:
            return
        
        # Basic metrics
        profits = [t.profit for t in closed_trades]
        report.total_profit = sum(p for p in profits if p > 0)
        report.total_loss = sum(p for p in profits if p < 0)
        
        # Win/Loss
        report.winning_trades = len([p for p in profits if p > 0])
        report.losing_trades = len([p for p in profits if p <= 0])
        
        # Average
        report.average_win = report.total_profit / report.winning_trades if report.winning_trades > 0 else 0
        report.average_loss = report.total_loss / report.losing_trades if report.losing_trades > 0 else 0
        
        # Extreme trades
        report.largest_win = max((p for p in profits if p > 0), default=0)
        report.largest_loss = min((p for p in profits if p < 0), default=0)
        
        # Calculate Sharpe Ratio
        try:
            returns = pd.DataFrame(self.balance_history)
            if len(returns) > 1:
                returns['equity_change'] = returns['equity'].pct_change()
                mean_return = returns['equity_change'].mean()
                std_return = returns['equity_change'].std()
                if std_return > 0:
                    report.sharpe_ratio = (mean_return / std_return) * np.sqrt(252)
        except Exception as e:
            logger.error(f"Error calculating Sharpe ratio: {e}")
            report.sharpe_ratio = 0
        
        # Calculate Max Drawdown
        try:
            equity_values = [b['equity'] for b in self.balance_history]
            cum_max = np.maximum.accumulate(equity_values)
            drawdown = (cum_max - equity_values) / cum_max
            report.max_drawdown = np.max(drawdown)
        except:
            report.max_drawdown = 0
        
        # Profit factor
        if report.total_loss != 0:
            report.profit_factor = abs(report.total_profit / report.total_loss)
        
        # Return percentage
        report.return_pct = (self.equity - self.config.initial_balance) / self.config.initial_balance
        
        # Annualized return
        if self.balance_history:
            start_time = self.balance_history[0]['time']
            end_time = self.balance_history[-1]['time']
            if isinstance(start_time, str):
                start_time = datetime.fromisoformat(start_time)
            if isinstance(end_time, str):
                end_time = datetime.fromisoformat(end_time)
            
            days = (end_time - start_time).days
            if days > 0:
                years = days / 365.25
                report.annualized_return = ((self.equity / self.config.initial_balance) ** (1/years)) - 1


class MonteCarloSimulation:
    """Monte Carlo simulation for backtesting."""
    
    def __init__(self, returns: List[float], num_simulations: int = 1000):
        """Initialize Monte Carlo simulation.
        
        Args:
            returns: List of trade returns
            num_simulations: Number of simulations to run
        """
        self.returns = returns
        self.num_simulations = num_simulations
    
    def run_simulation(self) -> Dict[str, Any]:
        """Run Monte Carlo simulation.
        
        Returns:
            Simulation results
        """
        results = []
        
        for _ in range(self.num_simulations):
            np.random.shuffle(self.returns)
            cumulative_return = np.cumprod(1 + np.array(self.returns)) - 1
            results.append(cumulative_return[-1])
        
        results = np.array(results)
        
        return {
            'mean_return': np.mean(results),
            'std_return': np.std(results),
            'min_return': np.min(results),
            'max_return': np.max(results),
            'median_return': np.median(results),
            'percentile_5': np.percentile(results, 5),
            'percentile_95': np.percentile(results, 95),
        }
    
    def get_distribution(self) -> Dict[str, Any]:
        """Get return distribution.
        
        Returns:
            Distribution statistics
        """
        returns = np.array(self.returns)
        
        return {
            'mean': np.mean(returns),
            'std': np.std(returns),
            'skew': self._calculate_skewness(returns),
            'kurtosis': self._calculate_kurtosis(returns),
            'sharpe_ratio': np.mean(returns) / np.std(returns) if np.std(returns) > 0 else 0
        }
    
    @staticmethod
    def _calculate_skewness(data: np.ndarray) -> float:
        """Calculate skewness.
        
        Args:
            data: Input data
        
        Returns:
            Skewness value
        """
        if len(data) < 3:
            return 0.0
        
        mean = np.mean(data)
        std = np.std(data)
        
        if std == 0:
            return 0.0
        
        skew = np.mean(((data - mean) / std) ** 3)
        return skew
    
    @staticmethod
    def _calculate_kurtosis(data: np.ndarray) -> float:
        """Calculate kurtosis.
        
        Args:
            data: Input data
        
        Returns:
            Kurtosis value
        """
        if len(data) < 4:
            return 0.0
        
        mean = np.mean(data)
        std = np.std(data)
        
        if std == 0:
            return 0.0
        
        kurt = np.mean(((data - mean) / std) ** 4) - 3
        return kurt


class WalkForwardOptimization:
    """Walk-forward optimization for strategies."""
    
    def __init__(self, data: pd.DataFrame, train_pct: float = 0.6,
                 validation_pct: float = 0.2, test_pct: float = 0.2):
        """Initialize walk-forward optimization.
        
        Args:
            data: Historical data
            train_pct: Percentage for training
            validation_pct: Percentage for validation
            test_pct: Percentage for testing
        """
        self.data = data
        self.train_pct = train_pct
        self.validation_pct = validation_pct
        self.test_pct = test_pct
    
    def get_train_validation_test(self) -> Tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
        """Split data into train, validation, and test sets.
        
        Returns:
            Tuple of (train, validation, test) DataFrames
        """
        n = len(self.data)
        train_size = int(n * self.train_pct)
        validation_size = int(n * self.validation_pct)
        
        train_data = self.data.iloc[:train_size]
        validation_data = self.data.iloc[train_size:train_size + validation_size]
        test_data = self.data.iloc[train_size + validation_size:]
        
        return train_data, validation_data, test_data
    
    def optimize_parameters(self, strategy, param_grid: Dict[str, List], 
                          metric: str = 'sharpe_ratio') -> Dict[str, Any]:
        """Optimize strategy parameters using walk-forward optimization.
        
        Args:
            strategy: Strategy to optimize
            param_grid: Parameter grid
            metric: Performance metric to optimize
        
        Returns:
            Best parameters
        """
        train_data, validation_data, _ = self.get_train_validation_test()
        
        best_score = float('-inf')
        best_params = {}
        
        # Grid search over parameters
        import itertools
        keys = list(param_grid.keys())
        values = list(param_grid.values())
        
        for combination in itertools.product(*values):
            params = dict(zip(keys, combination))
            
            # Train on training data
            # This is a simplified version - real implementation would train model
            
            # Evaluate on validation data
            # Placeholder for actual evaluation
            score = 0.5  # Placeholder
            
            if score > best_score:
                best_score = score
                best_params = params
        
        return best_params


def run_monte_carlo_analysis(results: List[Dict[str, Any]], num_simulations: int = 1000) -> Dict[str, Any]:
    """Run comprehensive Monte Carlo analysis.
    
    Args:
        results: List of backtest results
        num_simulations: Number of simulations
    
    Returns:
        Analysis results
    """
    returns = [r['return'] for r in results if 'return' in r]
    
    if not returns:
        return {}
    
    simulation = MonteCarloSimulation(returns, num_simulations)
    
    return {
        'simulation': simulation.run_simulation(),
        'distribution': simulation.get_distribution()
    }


def generate_backtest_report(results: Dict[str, Any]) -> str:
    """Generate a formatted backtest report.
    
    Args:
        results: Backtest results
    
    Returns:
        Formatted report string
    """
    report = f"""
    ================== BACKTEST REPORT ==================
    
    Start Time: {results.get('start_time', 'N/A')}
    End Time: {results.get('end_time', 'N/A')}
    
    TRADE STATISTICS:
        Total Trades: {results.get('total_trades', 0)}
        Winning Trades: {results.get('winning_trades', 0)}
        Losing Trades: {results.get('losing_trades', 0)}
        Win Rate: {results.get('win_rate', 0) * 100:.2f}%
    
    PROFIT & LOSS:
        Total Profit: ${results.get('total_profit', 0):.2f}
        Total Loss: ${results.get('total_loss', 0):.2f}
        Net Profit: ${results.get('net_profit', 0):.2f}
        Profit Factor: {results.get('profit_factor', 0):.2f}
    
    PERFORMANCE METRICS:
        Sharpe Ratio: {results.get('sharpe_ratio', 0):.4f}
        Max Drawdown: {results.get('max_drawdown_pct', 0):.2f}%
        Return: {results.get('return_pct', 0):.2f}%
        Annualized Return: {results.get('annualized_return', 0):.2f}%
    
    ====================================================
    """
    
    return report


def run_monte_carlo_analysis(results: List[Dict[str, Any]], num_simulations: int = 1000):
    """Run comprehensive Monte Carlo analysis.
    
    Args:
        results: List of backtest results
        num_simulations: Number of simulations
    
    Returns:
        Analysis results
    """
    returns = [r['return'] for r in results if 'return' in r]
    
    if not returns:
        return {}
    
    simulation = MonteCarloSimulation(returns, num_simulations)
    
    return {
        'simulation': simulation.run_simulation(),
        'distribution': simulation.get_distribution()
    }