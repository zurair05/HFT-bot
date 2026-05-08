"""LSTM-based price prediction and signal generation for HFT trading."""

import os
import numpy as np
import pandas as pd
from datetime import datetime
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass
import json

from ..core.logger import logger
from ..core.config import get_config

# Try to import TensorFlow
try:
    import tensorflow as tf
    from tensorflow import keras
    from tensorflow.keras.models import Sequential, load_model, Model
    from tensorflow.keras.layers import LSTM, Dense, Dropout, BatchNormalization, \
        Input, MultiHeadAttention, LayerNormalization, GlobalAveragePooling1D, Add, Concatenate
    from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint, ReduceLROnPlateau
    from tensorflow.keras.optimizers import Adam
    TF_AVAILABLE = True
except ImportError:
    TF_AVAILABLE = False
    logger.warning("TensorFlow not available. AI predictions will be limited.")

try:
    import joblib
    JOBLIB_AVAILABLE = True
except ImportError:
    JOBLIB_AVAILABLE = False


@dataclass
class LSTMConfig:
    """Configuration for LSTM model."""
    model_path: str = "./models"
    window_size: int = 60
    n_features: int = 5
    lstm_units: List[int] = None
    dropout_rate: float = 0.2
    learning_rate: float = 0.0001
    batch_size: int = 32
    epochs: int = 50
    patience: int = 10
    prediction_type: str = "direction"  # 'direction', 'price', 'volatility'


class LSTMPredictor:
    """LSTM-based predictor for trading signals."""
    
    def __init__(self, config: Optional[LSTMConfig] = None):
        """Initialize LSTM predictor.
        
        Args:
            config: LSTM configuration
        """
        self.config = config or LSTMConfig()
        self.model = None
        self.scaler = None
        self.features = None
        
        if TF_AVAILABLE:
            self._build_model()
        else:
            logger.warning("TensorFlow not available - LSTM predictions disabled")
    
    def _build_model(self):
        """Build the LSTM model."""
        if not TF_AVAILABLE:
            return
        
        try:
            # Use Transformer-based architecture
            inputs = Input(shape=(self.config.window_size, self.config.n_features))
            
            # Encoder layers with Attention
            encoder_output = inputs
            
            # Self-attention mechanism
            for units in [128, 64]:
                # Self-attention block
                attention = MultiHeadAttention(num_heads=4, key_dim=32)(encoder_output, encoder_output)
                attention = LayerNormalization()(attention)
                attention = Add()([encoder_output, attention])
                attention = Dropout(self.config.dropout_rate)(attention)
                
                # Feed-forward block
                ff = Dense(units * 4, activation='relu')(attention)
                ff = Dense(units)(ff)
                ff = Add()([attention, ff])
                ff = LayerNormalization()(ff)
                
                encoder_output = Dropout(self.config.dropout_rate)(ff)
            
            # LSTM layers
            x = LSTM(128, return_sequences=True, dropout=0.2)(encoder_output)
            x = LSTM(64, return_sequences=False, dropout=0.2)(x)
            x = Dropout(self.config.dropout_rate)(x)
            x = BatchNormalization()(x)
            
            # Dense layers
            x = Dense(32, activation='relu')(x)
            x = Dropout(self.config.dropout_rate)(x)
            
            # Output layer
            if self.config.prediction_type == "direction":
                # Three-class classification (Buy, Hold, Sell)
                outputs = Dense(3, activation='softmax', name='direction_prediction')(x)
            elif self.config.prediction_type == "price":
                # Price prediction
                outputs = Dense(1, name='price_prediction')(x)
            else:  # volatility
                # Volatility prediction
                outputs = Dense(1, activation='relu', name='volatility_prediction')(x)
            
            self.model = Model(inputs=inputs, outputs=outputs)
            
            # Compile model
            if self.config.prediction_type == "direction":
                self.model.compile(
                    optimizer=Adam(learning_rate=self.config.learning_rate),
                    loss='categorical_crossentropy',
                    metrics=['accuracy']
                )
            else:
                self.model.compile(
                    optimizer=Adam(learning_rate=self.config.learning_rate),
                    loss='mse',
                    metrics=['mae']
                )
            
            logger.info(f"LSTM model built successfully - Prediction type: {self.config.prediction_type}")
        
        except Exception as e:
            logger.error(f"Error building LSTM model: {e}")
            self.model = None
    
    def _prepare_features(self, data: pd.DataFrame, window_size: int = 60) -> Tuple[np.ndarray, np.ndarray]:
        """Prepare features from price data.
        
        Args:
            data: DataFrame with OHLCV data
            window_size: Size of the window
        
        Returns:
            Tuple of (X, y) arrays
        """
        try:
            # Calculate technical indicators
            dataset = self._calculate_technical_indicators(data)
            
            # Select features
            feature_cols = ['open', 'high', 'low', 'close', 'volume', 
                           'sma_10', 'sma_20', 'ema_10', 'rsi', 'macd',
                           'bb_upper', 'bb_lower', 'volume_ma', 'volatility',
                           'price_momentum', 'trend_strength']
            
            # Drop any NaN values
            dataset = dataset.dropna()
            
            if len(dataset) < window_size:
                logger.warning(f"Insufficient data: {len(dataset)} < {window_size}")
                return np.array([]), np.array([])
            
            # Create sequences
            X, y = [], []
            
            for i in range(len(dataset) - window_size):
                X.append(dataset[feature_cols].values[i:i + window_size])
                
                # Target variable
                if self.config.prediction_type == "direction":
                    # Classify next day direction
                    current_price = dataset['close'].values[i + window_size]
                    previous_price = dataset['close'].values[i + window_size - 1]
                    
                    price_change = (current_price - previous_price) / previous_price
                    
                    # Three-class encoding
                    if price_change > 0.0001:
                        y.append([0, 0, 1])  # Buy
                    elif price_change < -0.0001:
                        y.append([1, 0, 0])  # Sell
                    else:
                        y.append([0, 1, 0])  # Hold
                else:
                    # Return as float
                    y.append(dataset['close'].values[i + window_size])
            
            return np.array(X), np.array(y)
        
        except Exception as e:
            logger.error(f"Error preparing features: {e}")
            return np.array([]), np.array([])
    
    def _calculate_technical_indicators(self, data: pd.DataFrame) -> pd.DataFrame:
        """Calculate technical indicators for data.
        
        Args:
            data: DataFrame with OHLCV data
        
        Returns:
            DataFrame with added technical indicators
        """
        df = data.copy()
        
        # Simple Moving Averages
        df['sma_10'] = df['close'].rolling(10).mean()
        df['sma_20'] = df['close'].rolling(20).mean()
        df['sma_50'] = df['close'].rolling(50).mean()
        
        # Exponential Moving Averages
        df['ema_10'] = df['close'].ewm(span=10).mean()
        df['ema_20'] = df['close'].ewm(span=20).mean()
        
        # Relative Strength Index (RSI)
        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
        rs = gain / loss
        df['rsi'] = 100 - (100 / (1 + rs))
        
        # MACD
        exp1 = df['close'].ewm(span=12).mean()
        exp2 = df['close'].ewm(span=26).mean()
        df['macd'] = exp1 - exp2
        df['macd_signal'] = df['macd'].ewm(span=9).mean()
        
        # Bollinger Bands
        df['bb_middle'] = df['close'].rolling(window=20).mean()
        bb_std = df['close'].rolling(window=20).std()
        df['bb_upper'] = df['bb_middle'] + (bb_std * 2)
        df['bb_lower'] = df['bb_middle'] - (bb_std * 2)
        
        # Volume indicators
        df['volume_ma'] = df['volume'].rolling(20).mean()
        
        # Volatility
        df['volatility'] = df['close'].rolling(window=20).std()
        
        # Price momentum
        df['price_momentum'] = df['close'] - df['close'].shift(5)
        
        # Trend strength
        df['trend_strength'] = df['close'].rolling(5).apply(lambda x: (x.iloc[-1] - x.iloc[0]) / x.iloc[0] if x.iloc[0] != 0 else 0)
        
        return df
    
    def train(self, train_data: pd.DataFrame, test_data: Optional[pd.DataFrame] = None):
        """Train the LSTM model.
        
        Args:
            train_data: Training data
            test_data: Optional test data
        """
        if not TF_AVAILABLE or self.model is None:
            logger.error("Cannot train - TensorFlow not available")
            return
        
        try:
            X_train, y_train = self._prepare_features(train_data)
            
            if len(X_train) == 0:
                logger.error("No training data available")
                return
            
            # Prepare test data if available
            X_test, y_test = None, None
            if test_data is not None:
                X_test, y_test = self._prepare_features(test_data)
            
            # Callbacks
            callbacks = [
                EarlyStopping(
                    monitor='val_loss',
                    patience=self.config.patience,
                    restore_best_weights=True
                ),
                ModelCheckpoint(
                    filepath=os.path.join(self.config.model_path, 'lstm_best_model.h5'),
                    monitor='val_loss',
                    save_best_only=True
                ),
                ReduceLROnPlateau(monitor='val_loss', factor=0.5, patience=5, min_lr=1e-7)
            ]
            
            # Train model
            history = self.model.fit(
                X_train, y_train,
                validation_data=(X_test, y_test) if X_test is not None else None,
                epochs=self.config.epochs,
                batch_size=self.config.batch_size,
                callbacks=callbacks,
                verbose=1
            )
            
            logger.info(f"Model training completed. Best loss: {min(history.history['val_loss']) if 'val_loss' in history.history else 'N/A'}")
            
            # Save model
            self.save_model()
        
        except Exception as e:
            logger.error(f"Error training model: {e}")
    
    def predict(self, recent_data: pd.DataFrame) -> Optional[Dict[str, Any]]:
        """Make predictions using the model.
        
        Args:
            recent_data: Recent price data for prediction
        
        Returns:
            Prediction results
        """
        if not TF_AVAILABLE or self.model is None:
            logger.error("Cannot predict - model not available")
            return None
        
        try:
            X, _ = self._prepare_features(recent_data, self.config.window_size)
            
            if len(X) == 0:
                return None
            
            prediction = self.model.predict(X, verbose=0)
            
            if self.config.prediction_type == "direction":
                # Interpret direction prediction
                signal = np.argmax(prediction[0])
                confidence = float(np.max(prediction[0]))
                
                signal_map = {0: "sell", 1: "hold", 2: "buy"}
                
                return {
                    'signal': signal_map.get(signal, "unknown"),
                    'confidence': confidence,
                    'raw_prediction': prediction[0].tolist()
                }
            else:
                return {
                    'predicted_value': float(prediction[0][0]),
                    'confidence': None,
                    'raw_prediction': prediction.tolist()
                }
        
        except Exception as e:
            logger.error(f"Error making prediction: {e}")
            return None
    
    def save_model(self):
        """Save the trained model."""
        if self.model is not None:
            try:
                os.makedirs(self.config.model_path, exist_ok=True)
                model_file = os.path.join(self.config.model_path, "lstm_model.h5")
                self.model.save(model_file)
                logger.info(f"Model saved to {model_file}")
            except Exception as e:
                logger.error(f"Error saving model: {e}")
    
    def load_model(self, model_path: str = "./models/lstm_model.h5"):
        """Load a trained model.
        
        Args:
            model_path: Path to model file
        """
        if TF_AVAILABLE and os.path.exists(model_path):
            try:
                self.model = load_model(model_path)
                logger.info(f"Model loaded from {model_path}")
            except Exception as e:
                logger.error(f"Error loading model: {e}")


class VolatilityPredictor:
    """Specialized predictor for volatility forecasting."""
    
    def __init__(self, window_size: int = 60):
        """Initialize volatility predictor.
        
        Args:
            window_size: Window size for calculations
        """
        self.window_size = window_size
    
    def predict_volatility(self, high_prices: List[float], low_prices: List[float], 
                          close_prices: List[float]) -> Dict[str, Any]:
        """Predict future volatility using simple models.
        
        Args:
            high_prices: List of high prices
            low_prices: List of low prices
            close_prices: List of closing prices
        
        Returns:
            Volatility prediction
        """
        if len(close_prices) < self.window_size:
            return {'current_volatility': 0, 'predicted_volatility': 0, 'trend': 'unknown'}
        
        try:
            # Calculate returns
            returns = [(close_prices[i] - close_prices[i-1]) / close_prices[i-1] 
                      for i in range(1, len(close_prices))]
            
            # Calculate current volatility
            current_vol = np.std(returns[-self.window_size:])
            
            # Simple trend-based prediction
            trend = 'increasing' if returns[-1] > returns[-2] else 'decreasing'
            
            return {
                'current_volatility': current_vol,
                'predicted_volatility': current_vol * 1.1 if trend == 'increasing' else current_vol * 0.9,
                'trend': trend,
                'max_volatility': max(returns[-self.window_size:]),
                'min_volatility': min(returns[-self.window_size:]);
            }
        
        except Exception as e:
            logger.error(f"Error predicting volatility: {e}")
            return {'current_volatility': 0, 'predicted_volatility': 0, 'trend': 'unknown'}