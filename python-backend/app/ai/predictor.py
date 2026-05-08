"""AI/ML models for HFT trading predictions."""

import os
import json
import pickle
import math
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any, Tuple
from collections import deque
import numpy as np

from ..core.config import get_config
from ..core.logger import logger

# Optional AI libraries
try:
    import tensorflow as tf
    from tensorflow import keras
    from tensorflow.keras.models import Sequential, load_model
    from tensorflow.keras.layers import LSTM, Dense, Dropout, Input, BatchNormalization
    from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
    TENSORFLOW_AVAILABLE = True
except ImportError:
    TENSORFLOW_AVAILABLE = False
    logger.warning("TensorFlow not available. AI predictions will not work.")


try:
    import joblib
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False


class AIPredictor:
    """AI Predictor for trading signals and market analysis."""
    
    def __init__(self, model_path: str = "./models"):
        """Initialize AI predictor.
        
        Args:
            model_path: Path to model storage directory
        """
        self.model_path = model_path
        self.lstm_model = None
        self.scaler = None
        self.config = get_config().ai
        self.tick_buffer = deque(maxlen=1000)  # Store last 1000 ticks
        self.prediction_cache = {}
        
        # Initialize models if available
        if TENSORFLOW_AVAILABLE:
            try:
                self._load_or_create_model()
            except Exception as e:
                logger.error(f"Failed to initialize AI model: {e}")
                self.lstm_model = None
    
    def _load_or_create_model(self):
        """Load existing model or create a new one."""
        model_file = os.path.join(self.model_path, "lstm_model.h5")
        
        if os.path.exists(model_file):
            try:
                self.lstm_model = load_model(model_file)
                logger.info("Loaded existing LSTM model")
            except Exception as e:
                logger.error(f"Failed to load existing model: {e}")
                self.lstm_model = self._create_lstm_model()
        else:
            self.lstm_model = self._create_lstm_model()
    
    def _create_lstm_model(self) -> tf.keras.Model:
        """Create a new LSTM model.
        
        Returns:
            LSTM model
        """
        if not TENSORFLOW_AVAILABLE:
            raise RuntimeError("TensorFlow not available")
        
        model = Sequential([
            Input(shape=(self.config.lstm_window_size, 5)),
            LSTM(128, return_sequences=True),
            Dropout(0.2),
            BatchNormalization(),
            LSTM(64, return_sequences=False),
            Dropout(0.2),
            BatchNormalization(),
            Dense(32, activation='relu'),
            Dropout(0.2),
            Dense(3, activation='softmax')  # Sell, Hold, Buy
        ])
        
        model.compile(
            optimizer='adam',
            loss='categorical_crossentropy',
            metrics=['accuracy']
        )
        
        return model
    
    def predict_market_direction(self, symbol: str, period: str = 'short') -> Dict[str, Any]:
        """Predict market direction for a given symbol.
        
        Args:
            symbol: Trading symbol
            period: Prediction period ('short' for 1-5 minutes, 'medium' for 15-30 minutes)
        
        Returns:
            Dictionary with prediction results
        """
        if not self.lstm_model:
            return {
                'symbol': symbol,
                'direction': 'unknown',
                'confidence': 0.0,
                'prediction': None
            }
        
        try:
            # Get recent tick data for the symbol
            recent_data = self._get_recent_ticks(symbol)
            
            if len(recent_data) < self.config.lstm_window_size:
                return {
                    'symbol': symbol,
                    'direction': 'insufficient_data',
                    'confidence': 0.0,
                    'prediction': None
                }
            
            # Prepare features
            features = np.array(recent_data)
            features = np.reshape(features, (1, features.shape[0], features.shape[1]))
            
            # Make prediction
            prediction = self.lstm_model.predict(features, verbose=0)
            
            # Interpret prediction
            signal = np.argmax(prediction[0])
            confidence = float(np.max(prediction[0]))
            
            directions = {0: 'sell', 1: 'hold', 2: 'buy'}
            direction = directions.get(signal, 'unknown')
            
            result = {
                'symbol': symbol,
                'direction': direction,
                'confidence': confidence,
                'prediction': {
                    'sell': float(prediction[0][0]),
                    'hold': float(prediction[0][1]),
                    'buy': float(prediction[0][2])
                }
            }
            
            self.prediction_cache[symbol] = result
            return result
        
        except Exception as e:
            logger.error(f"Prediction error for {symbol}: {e}")
            return {
                'symbol': symbol,
                'direction': 'error',
                'confidence': 0.0,
                'prediction': None
            }
    
    def predict_volatility(self, symbol: str, window: int = 20) -> Dict[str, Any]:
        """Predict volatility for a given symbol.
        
        Args:
            symbol: Trading symbol
            window: Rolling window size
        
        Returns:
            Dictionary with volatility predictions
        """
        if not self.lstm_model:
            return {
                'symbol': symbol,
                'current_volatility': 0.0,
                'predicted_volatility': 0.0,
                'regime': 'unknown'
            }
        
        try:
            recent_data = self._get_recent_ticks(symbol)
            
            if len(recent_data) < window:
                return {
                    'symbol': symbol,
                    'current_volatility': 0.0,
                    'predicted_volatility': 0.0,
                    'regime': 'insufficient_data'
                }
            
            # Calculate current volatility
            prices = [d['mid'] for d in recent_data[-window:]]
            returns = [prices[i] - prices[i-1] for i in range(1, len(prices))]
            current_vol = np.std(returns)
            
            # Predict future volatility using simple calculations
            atr = self._calculate_atr(recent_data, 14)
            
            # Determine volatility regime
            regime = self._get_volatility_regime(current_vol, atr)
            
            return {
                'symbol': symbol,
                'current_volatility': float(current_vol),
                'predicted_volatility': float(atr),
                'regime': regime
            }
        
        except Exception as e:
            logger.error(f"Volatility prediction error: {e}")
            return {
                'symbol': symbol,
                'current_volatility': 0.0,
                'predicted_volatility': 0.0,
                'regime': 'error'
            }
    
    def calculate_trade_quality_score(self, trade_data: dict) -> float:
        """Calculate trade quality score based on AI predictions.
        
        Args:
            trade_data: Trade data dictionary
        
        Returns:
            Quality score between 0 and 1
        """
        try:
            symbol = trade_data.get('symbol', '')
            prediction = self.predict_market_direction(symbol)
            
            confidence = prediction.get('confidence', 0)
            direction = prediction.get('direction', 'unknown')
            
            trade_direction = trade_data.get('direction', '')
            
            # High-quality trade if direction matches prediction
            if (direction == 'buy' and trade_direction == 'buy') or \
               (direction == 'sell' and trade_direction == 'sell'):
                return confidence
            elif direction == 'hold':
                return confidence * 0.5  # Neutral
            else:
                return confidence * 0.1  # Low quality
        
        except Exception as e:
            logger.error(f"Error calculating trade quality: {e}")
            return 0.5
    
    def process_new_tick(self, tick_data: Dict[str, Any]):
        """Process a new tick to update the model's internal state.
        
        Args:
            tick_data: Tick data dictionary
        """
        self.tick_buffer.append(tick_data)
    
    def _get_recent_ticks(self, symbol: str, count: int = 100) -> List[Dict[str, Any]]:
        """Get recent ticks for a symbol.
        
        Args:
            symbol: Trading symbol
            count: Number of ticks to return
        
        Returns:
            List of tick data dictionaries
        """
        ticks = []
        for tick in self.tick_buffer:
            if tick.get('symbol') == symbol:
                ticks.append(tick)
        
        return ticks[-count:]
    
    def _calculate_atr(self, ticks: List[Dict], period: int = 14) -> float:
        """Calculate Average True Range.
        
        Args:
            ticks: List of tick data
            period: ATR period
        
        Returns:
            ATR value
        """
        if len(ticks) < period:
            return 0.0
        
        atr_values = []
        
        for i in range(period, len(ticks)):
            high = max([t['high'] for t in ticks[i-period:i+1]])
            low = min([t['low'] for t in ticks[i-period:i+1]])
            close = ticks[i]['close']
            
            tr1 = high - low
            tr2 = abs(high - ticks[i-1]['close'])
            tr3 = abs(low - ticks[i-1]['close'])
            
            atr_values.append(max(tr1, tr2, tr3))
        
        return np.mean(atr_values) if atr_values else 0.0
    
    def _get_volatility_regime(self, current_vol: float, atr: float) -> str:
        """Determine the current volatility regime."""
        if current_vol > atr * 2:
            return 'high'
        elif current_vol < atr * 0.5:
            return 'low'
        else:
            return 'medium'
    
    def train_model(self, historical_data: List[Dict[str, Any]], epochs: int = 50):
        """Train the LSTM model with historical data.
        
        Args:
            historical_data: List of historical data points
            epochs: Number of training epochs
        """
        if not TENSORFLOW_AVAILABLE:
            logger.warning("TensorFlow not available for model training")
            return
        
        try:
            # Prepare training data
            X, y = self._prepare_training_data(historical_data)
            
            if len(X) < self.config.lstm_window_size:
                logger.warning("Insufficient training data")
                return
            
            # Early stopping
            early_stopping = EarlyStopping(
                monitor='val_loss',
                patience=10,
                restore_best_weights=True
            )
            
            # Model checkpoint
            checkpoint = ModelCheckpoint(
                os.path.join(self.model_path, 'lstm_model.h5'),
                monitor='val_loss',
                save_best_only=True
            )
            
            # Train model
            history = self.lstm_model.fit(
                X, y,
                epochs=epochs,
                batch_size=32,
                validation_split=0.2,
                callbacks=[early_stopping, checkpoint],
                verbose=1
            )
            
            logger.info(f"Model training completed. Final loss: {history.history['loss'][-1]:.4f}")
        
        except Exception as e:
            logger.error(f"Error training model: {e}")
    
    def _prepare_training_data(self, historical_data: List[Dict]) -> Tuple[np.ndarray, np.ndarray]:
        """Prepare training data from historical data."""
        X = []
        y = []
        
        window_size = self.config.lstm_window_size
        
        for i in range(window_size, len(historical_data)):
            # Feature window
            window = historical_data[i-window_size:i]
            
            # Extract features (open, high, low, close, volume)
            features = []
            for tick in window:
                features.append([
                    tick.get('open', 0),
                    tick.get('high', 0),
                    tick.get('low', 0),
                    tick.get('close', 0),
                    tick.get('volume', 0)
                ])
            
            X.append(features)
            
            # Label: 0 (sell), 1 (hold), 2 (buy)
            next_close = historical_data[i]['close']
            current_close = historical_data[i-1]['close']
            
            if next_close > current_close:
                y.append(2)  # buy
            elif next_close < current_close:
                y.append(0)  # sell
            else:
                y.append(1)  # hold
        
        # One-hot encode labels
        y_one_hot = np.zeros((len(y), 3))
        for i, label in enumerate(y):
            y_one_hot[i][label] = 1
        
        return np.array(X), y_one_hot
    
    def save_model(self):
        """Save the trained model."""
        if not TENSORFLOW_AVAILABLE or not self.lstm_model:
            return
        
        try:
            model_file = os.path.join(self.model_path, "lstm_model.h5")
            self.lstm_model.save(model_file)
            logger.info("Model saved successfully")
        except Exception as e:
            logger.error(f"Error saving model: {e}")
    
    def load_model_from_disk(self, model_file: str):
        """Load a model from disk.
        
        Args:
            model_file: Path to model file
        """
        if not TENSORFLOW_AVAILABLE:
            return
        
        try:
            self.lstm_model = load_model(model_file)
            logger.info("Model loaded successfully")
        except Exception as e:
            logger.error(f"Error loading model: {e}")


class FeatureEngineering:
    """Feature engineering for trading data."""
    
    @staticmethod
    def create_features(ticks: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Create features from tick data.
        
        Args:
            ticks: List of tick data
        
        Returns:
            Dictionary of features
        """
        if not ticks:
            return {}
        
        prices = [tick['mid'] for tick in ticks]
        volumes = [tick.get('volume', 0) for tick in ticks]
        
        # Price features
        price_changes = [prices[i] - prices[i-1] for i in range(1, len(prices))]
        
        # Technical indicators
        features = {
            'price_mean': np.mean(prices),
            'price_std': np.std(prices),
            'price_min': np.min(prices),
            'price_max': np.max(prices),
            'price_range': np.max(prices) - np.min(prices),
            'price_change_mean': np.mean(price_changes) if price_changes else 0,
            'price_change_std': np.std(price_changes) if price_changes else 0,
            'volume_mean': np.mean(volumes),
            'volume_std': np.std(volumes),
            'rsi': FeatureEngineering.calculate_rsi(prices),
            'ema_10': FeatureEngineering.calculate_ema(prices, 10),
            'ema_20': FeatureEngineering.calculate_ema(prices, 20),
        }
        
        return features
    
    @staticmethod
    def calculate_rsi(prices: List[float], period: int = 14) -> float:
        """Calculate RSI (Relative Strength Index)."""
        if len(prices) < period:
            return 50.0
        
        deltas = [prices[i] - prices[i-1] for i in range(1, len(prices))]
        
        gains = [d if d > 0 else 0 for d in deltas[-period:]]
        losses = [-d if d < 0 else 0 for d in deltas[-period:]]
        
        avg_gain = sum(gains) / len(gains) if gains else 0
        avg_loss = sum(losses) / len(losses) if losses else 0
        
        if avg_loss == 0:
            return 100.0
        
        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        
        return rsi
    
    @staticmethod
    def calculate_ema(prices: List[float], period: int = 20) -> float:
        """Calculate Exponential Moving Average."""
        if len(prices) < period:
            return prices[-1] if prices else 0
        
        ema = sum(prices[:period]) / period
        multiplier = 2 / (period + 1)
        
        for price in prices[period:]:
            ema = (price - ema) * multiplier + ema
        
        return ema
    
    @staticmethod
    def calculate_momentum(prices: List[float], period: int = 10) -> float:
        """Calculate price momentum."""
        if len(prices) < period:
            return 0.0
        
        return prices[-1] - prices[-period]
    
    @staticmethod
    def calculate_volatility(prices: List[float], period: int = 20) -> float:
        """Calculate rolling volatility."""
        if len(prices) < period:
            return 0.0
        
        returns = [(prices[i] - prices[i-1]) / prices[i-1] for i in range(1, len(prices))]
        recent_returns = returns[-period:]
        
        return np.std(recent_returns) * np.sqrt(252)  # Annualized


class TradeQualityScorer:
    """Score trade quality based on AI predictions."""
    
    def __init__(self, predictor: AIPredictor):
        self.predictor = predictor
    
    def score_trade(self, trade_data: Dict[str, Any]) -> float:
        """Score a trade based on AI analysis.
        
        Args:
            trade_data: Trade data with symbol, direction, entry price, etc.
        
        Returns:
            Quality score (0-1)
        """
        scores = []
        
        # Market direction score
        prediction = self.predictor.predict_market_direction(trade_data['symbol'])
        market_score = self._market_direction_score(trade_data, prediction)
        scores.append(market_score)
        
        # Volatility score
        volatility = self.predictor.predict_volatility(trade_data['symbol'])
        volatility_score = self._volatility_score(trade_data, volatility)
        scores.append(volatility_score)
        
        # Risk-adjusted score
        risk_score = self._risk_adjusted_score(trade_data)
        scores.append(risk_score)
        
        return np.mean(scores)
    
    def _market_direction_score(self, trade_data: dict, prediction: dict) -> float:
        """Score based on market direction."""
        confidence = prediction.get('confidence', 0)
        direction = prediction.get('direction', 'unknown')
        
        if direction == 'hold':
            return 0.5
        
        trade_direction = trade_data.get('direction', '')
        if (direction == 'buy' and trade_direction == 'buy') or \
           (direction == 'sell' and trade_direction == 'sell'):
            return confidence
        
        return confidence * 0.1
    
    def _volatility_score(self, trade_data: dict, volatility: dict) -> float:
        """Score based on volatility."""
        regime = volatility.get('regime', 'medium')
        
        if regime == 'medium':
            return 1.0
        elif regime == 'high':
            return 0.6
        else:  # low
            return 0.8
    
    def _risk_adjusted_score(self, trade_data: dict) -> float:
        """Score based on risk parameters."""
        sl_distance = trade_data.get('stop_loss_distance', 0)
        tp_distance = trade_data.get('take_profit_distance', 0)
        
        if tp_distance <= 0 or sl_distance <= 0:
            return 0.0
        
        # Risk-reward ratio
        risk_reward = tp_distance / sl_distance
        
        # Normalize to 0-1 scale
        if risk_reward >= 2:
            return 1.0
        elif risk_reward >= 1.5:
            return 0.8
        elif risk_reward >= 1.0:
            return 0.6
        else:
            return max(0, risk_reward / 2)


# Global predictor instances
_ai_predictor = None
_feature_engineering = None
_trade_scorer = None

def get_ai_predictor() -> AIPredictor:
    """Get global AI predictor instance."""
    global _ai_predictor
    if _ai_predictor is None:
        _ai_predictor = AIPredictor()
    return _ai_predictor


def get_feature_engineering() -> FeatureEngineering:
    """Get global feature engineering instance."""
    global _feature_engineering
    if _feature_engineering is None:
        _feature_engineering = FeatureEngineering()
    return _feature_engineering


def get_trade_scorer() -> TradeQualityScorer:
    """Get global trade scorer instance."""
    global _trade_scorer
    if _trade_scorer is None:
        _trade_scorer = TradeQualityScorer(get_ai_predictor())
    return _trade_scorer
