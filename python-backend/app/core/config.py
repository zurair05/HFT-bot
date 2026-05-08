"""Configuration management for the HFT trading system."""

import os
import json
from dataclasses import dataclass, field
from typing import List, Optional
from pathlib import Path


@dataclass
class DatabaseConfig:
    """Database configuration."""
    host: str = "localhost"
    port: int = 5432
    database: str = "mt5_hft_db"
    username: str = "trading_bot"
    password: str = ""
    pool_size: int = 20
    max_overflow: int = 10
    pool_timeout: int = 30


@dataclass
class RedisConfig:
    """Redis configuration."""
    host: str = "localhost"
    port: int = 6379
    db: int = 0
    password: Optional[str] = None
    socket_timeout: int = 5
    socket_connect_timeout: int = 5
    health_check_interval: int = 30


@dataclass
class MT5Config:
    """MetaTrader 5 configuration."""
    account: int = 0
    password: str = ""
    server: str = ""
    path: str = "C:/Program Files/MetaTrader 5/terminal64.exe"
    symbols: List[str] = field(default_factory=lambda: [
        "EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "NAS100", "US30"
    ])
    timeframes: List[str] = field(default_factory=lambda: ["M1", "M5", "M15", "H1"])
    max_tick_latency_ms: int = 50
    execution_mode: str = "auto"
    filling_mode: str = "ioc"


@dataclass
class APIConfig:
    """API server configuration."""
    host: str = "0.0.0.0"
    port: int = 8000
    workers: int = 4
    reload: bool = False
    cors_origins: List[str] = field(default_factory=lambda: [
        "http://localhost:3000", "http://127.0.0.1:3000"
    ])
    api_key_header: str = "X-API-Key"
    rate_limit: str = "100/minute"


@dataclass
class WebSocketConfig:
    """WebSocket configuration."""
    host: str = "0.0.0.0"
    port: int = 8001
    ping_interval: int = 20
    ping_timeout: int = 10
    max_connections: int = 100


@dataclass
class AIConfig:
    """AI/ML configuration."""
    model_path: str = "./models"
    prediction_interval_ms: int = 100
    lstm_window_size: int = 60
    confidence_threshold: float = 0.75
    feature_engineering_enabled: bool = True


@dataclass
class MonitoringConfig:
    """Monitoring and alerting configuration."""
    prometheus_port: int = 9090
    grafana_port: int = 3000
    alert_webhook_url: str = ""
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""
    discord_webhook_url: str = ""
    email_smtp_host: str = ""
    email_smtp_port: int = 587
    email_username: str = ""
    email_password: str = ""
    alert_email_to: str = ""


@dataclass
class TradingConfig:
    """Trading configuration."""
    mode: str = "production"
    environment: str = "vps"
    timezone: str = "UTC"
    log_level: str = "INFO"
    trading_enabled: bool = True
    simulation_mode: bool = False
    max_daily_drawdown_percent: float = 4.0
    max_total_drawdown_percent: float = 8.0
    equity_protection_percent: float = 85.0
    margin_call_level: float = 100.0


class Configuration:
    """Main configuration class."""
    
    def __init__(self, config_file: Optional[str] = None):
        """Initialize configuration.
        
        Args:
            config_file: Path to configuration file
        """
        self.database = DatabaseConfig()
        self.redis = RedisConfig()
        self.mt5 = MT5Config()
        self.api = APIConfig()
        self.websocket = WebSocketConfig()
        self.ai = AIConfig()
        self.monitoring = MonitoringConfig()
        self.trading = TradingConfig()
        
        if config_file and Path(config_file).exists():
            self.load_from_file(config_file)
        
        self.load_from_env()
    
    def load_from_file(self, config_file: str):
        """Load configuration from JSON file."""
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            
            # Update database config
            if 'database' in config:
                self.database = DatabaseConfig(**config['database'])
            
            # Update Redis config
            if 'redis' in config:
                self.redis = RedisConfig(**config['redis'])
            
            # Update MT5 config
            if 'mt5' in config:
                self.mt5 = MT5Config(**config['mt5'])
            
            # Update API config
            if 'api' in config:
                self.api = APIConfig(**config['api'])
            
            # Update WebSocket config
            if 'websocket' in config:
                self.websocket = WebSocketConfig(**config['websocket'])
            
            # Update AI config
            if 'ai' in config:
                self.ai = AIConfig(**config['ai'])
            
            # Update monitoring config
            if 'monitoring' in config:
                self.monitoring = MonitoringConfig(**config['monitoring'])
            
            # Update trading config
            if 'trading' in config:
                self.trading = TradingConfig(**config['trading'])
        
        except Exception as e:
            print(f"Error loading configuration file: {e}")
    
    def load_from_env(self):
        """Load configuration from environment variables."""
        # Database
        if os.getenv('DB_HOST'):
            self.database.host = os.getenv('DB_HOST')
        if os.getenv('DB_PORT'):
            self.database.port = int(os.getenv('DB_PORT'))
        if os.getenv('DB_NAME'):
            self.database.database = os.getenv('DB_NAME')
        if os.getenv('DB_USER'):
            self.database.username = os.getenv('DB_USER')
        if os.getenv('DB_PASSWORD'):
            self.database.password = os.getenv('DB_PASSWORD')
        
        # Redis
        if os.getenv('REDIS_HOST'):
            self.redis.host = os.getenv('REDIS_HOST')
        if os.getenv('REDIS_PORT'):
            self.redis.port = int(os.getenv('REDIS_PORT'))
        
        # MT5
        if os.getenv('MT5_PATH'):
            self.mt5.path = os.getenv('MT5_PATH')
        if os.getenv('MT5_ACCOUNT'):
            self.mt5.account = int(os.getenv('MT5_ACCOUNT'))
        if os.getenv('MT5_PASSWORD'):
            self.mt5.password = os.getenv('MT5_PASSWORD')
        if os.getenv('MT5_SERVER'):
            self.mt5.server = os.getenv('MT5_SERVER')
        
        # Trading
        if os.getenv('TRADING_LOG_LEVEL'):
            self.trading.log_level = os.getenv('TRADING_LOG_LEVEL')
        if os.getenv('TRADING_MODE'):
            self.trading.mode = os.getenv('TRADING_MODE')
        if os.getenv('TRADING_ENABLED'):
            self.trading.trading_enabled = os.getenv('TRADING_ENABLED').lower() == 'true'
    
    def to_dict(self) -> dict:
        """Convert configuration to dictionary."""
        return {
            'database': self.database.__dict__,
            'redis': self.redis.__dict__,
            'mt5': self.mt5.__dict__,
            'api': self.api.__dict__,
            'websocket': self.websocket.__dict__,
            'ai': self.ai.__dict__,
            'monitoring': self.monitoring.__dict__,
            'trading': self.trading.__dict__,
        }
    
    def save_to_file(self, config_file: str):
        """Save configuration to JSON file."""
        try:
            with open(config_file, 'w') as f:
                json.dump(self.to_dict(), f, indent=4, default=str)
        except Exception as e:
            print(f"Error saving configuration: {e}")


# Global configuration instance
_config = None

def get_config(config_file: Optional[str] = None) -> Configuration:
    """Get global configuration instance.
    
    Args:
        config_file: Optional path to configuration file
    
    Returns:
        Configuration instance
    """
    global _config
    if _config is None:
        _config = Configuration(config_file)
    return _config


def init_config(config_file: Optional[str] = None) -> Configuration:
    """Initialize configuration with optional file."""
    global _config
    _config = Configuration(config_file)
    return _config
