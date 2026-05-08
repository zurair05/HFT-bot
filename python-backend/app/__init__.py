"""HFT Trading System Python Backend."""

__version__ = "1.0.0"
__author__ = "Institutional Trading Desk"

from .core.config import get_config, init_config
from .core.logger import get_logger, setup_logging
from .core.redis_client import get_redis_client, init_redis_client

__all__ = [
    'get_config',
    'init_config',
    'get_logger',
    'setup_logging',
    'get_redis_client',
    'init_redis_client',
]