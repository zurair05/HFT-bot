"""Redis client for high-speed data caching and inter-process communication."""

import json
import asyncio
from typing import Optional, Any, Dict, List
from datetime import datetime, timedelta

try:
    import redis
    from redis.asyncio import Redis as AsyncRedis
    REDIS_AVAILABLE = True
except ImportError:
    REDIS_AVAILABLE = False
    print("Redis not available. Install with: pip install redis[hiredis]")

from .config import get_config
from .logger import logger


class RedisClient:
    """High-performance Redis client for trading data."""
    
    def __init__(self):
        """Initialize Redis client."""
        self.config = get_config().redis
        self.client = None
        self.async_client = None
        self.connected = False
    
    def connect(self) -> bool:
        """Connect to Redis server.
        
        Returns:
            True if connected successfully
        """
        if not REDIS_AVAILABLE:
            logger.warning("Redis not available")
            return False
        
        try:
            self.client = redis.Redis(
                host=self.config.host,
                port=self.config.port,
                db=self.config.db,
                password=self.config.password,
                socket_timeout=self.config.socket_timeout,
                socket_connect_timeout=self.config.socket_connect_timeout,
                health_check_interval=self.config.health_check_interval,
                decode_responses=True
            )
            
            # Test connection
            self.client.ping()
            self.connected = True
            logger.info("Connected to Redis server")
            return True
        
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            self.connected = False
            return False
    
    async def connect_async(self) -> bool:
        """Connect to Redis server asynchronously.
        
        Returns:
            True if connected successfully
        """
        if not REDIS_AVAILABLE:
            logger.warning("Redis not available")
            return False
        
        try:
            self.async_client = await AsyncRedis(
                host=self.config.host,
                port=self.config.port,
                db=self.config.db,
                password=self.config.password,
                socket_timeout=self.config.socket_timeout,
                socket_connect_timeout=self.config.socket_connect_timeout,
                health_check_interval=self.config.health_check_interval,
                decode_responses=True
            )
            
            await self.async_client.ping()
            self.connected = True
            logger.info("Connected to Redis server (async)")
            return True
        
        except Exception as e:
            logger.error(f"Failed to connect to Redis (async): {e}")
            self.connected = False
            return False
    
    def disconnect(self):
        """Disconnect from Redis server."""
        if self.client:
            self.client.close()
            self.client = None
        
        self.connected = False
        logger.info("Disconnected from Redis server")
    
    # Tick Data Operations
    def store_tick(self, symbol: str, tick_data: dict, ttl: int = 3600) -> bool:
        """Store tick data in Redis.
        
        Args:
            symbol: Trading symbol
            tick_data: Tick data dictionary
            ttl: Time to live in seconds
        
        Returns:
            True if stored successfully
        """
        try:
            if not self.connected:
                return False
            
            key = f"tick:{symbol}"
            self.client.hset(key, mapping={
                'bid': str(tick_data.get('bid', 0)),
                'ask': str(tick_data.get('ask', 0)),
                'spread': str(tick_data.get('spread', 0)),
                'volume': str(tick_data.get('volume', 0)),
                'timestamp': str(datetime.utcnow().isoformat())
            })
            
            self.client.expire(key, ttl)
            return True
        
        except Exception as e:
            logger.error(f"Error storing tick data: {e}")
            return False
    
    def get_tick(self, symbol: str) -> Optional[Dict[str, Any]]:
        """Get latest tick data from Redis.
        
        Args:
            symbol: Trading symbol
        
        Returns:
            Tick data dictionary or None
        """
        try:
            if not self.connected:
                return None
            
            key = f"tick:{symbol}"
            data = self.client.hgetall(key)
            return data if data else None
        
        except Exception as e:
            logger.error(f"Error getting tick data: {e}")
            return None
    
    # Trade Signals
    def store_signal(self, signal_id: str, signal_data: dict, ttl: int = 3600) -> bool:
        """Store trade signal in Redis.
        
        Args:
            signal_id: Unique signal identifier
            signal_data: Signal data dictionary
            ttl: Time to live in seconds
        
        Returns:
            True if stored successfully
        """
        try:
            if not self.connected:
                return False
            
            key = f"signal:{signal_id}"
            self.client.hset(key, mapping={
                'type': str(signal_data.get('type', '')),
                'symbol': str(signal_data.get('symbol', '')),
                'price': str(signal_data.get('price', 0)),
                'confidence': str(signal_data.get('confidence', 0)),
                'strategy': str(signal_data.get('strategy', '')),
                'timestamp': str(datetime.utcnow().isoformat())
            })
            
            self.client.expire(key, ttl)
            return True
        
        except Exception as e:
            logger.error(f"Error storing signal: {e}")
            return False
    
    def get_signal(self, signal_id: str) -> Optional[Dict[str, Any]]:
        """Get trade signal from Redis.
        
        Args:
            signal_id: Unique signal identifier
        
        Returns:
            Signal data dictionary or None
        """
        try:
            if not self.connected:
                return None
            
            key = f"signal:{signal_id}"
            data = self.client.hgetall(key)
            return data if data else None
        
        except Exception as e:
            logger.error(f"Error getting signal: {e}")
            return None
    
    # Risk Metrics
    def store_risk_metrics(self, metrics: dict) -> bool:
        """Store risk metrics in Redis.
        
        Args:
            metrics: Risk metrics dictionary
        
        Returns:
            True if stored successfully
        """
        try:
            if not self.connected:
                return False
            
            self.client.hset('risk:metrics', mapping={
                'daily_pnl': str(metrics.get('daily_pnl', 0)),
                'total_pnl': str(metrics.get('total_pnl', 0)),
                'open_positions': str(metrics.get('open_positions', 0)),
                'margin_used': str(metrics.get('margin_used', 0)),
                'equity': str(metrics.get('equity', 0)),
                'balance': str(metrics.get('balance', 0)),
                'drawdown': str(metrics.get('drawdown', 0)),
                'timestamp': str(datetime.utcnow().isoformat())
            })
            
            return True
        
        except Exception as e:
            logger.error(f"Error storing risk metrics: {e}")
            return False
    
    def get_risk_metrics(self) -> Optional[Dict[str, Any]]:
        """Get risk metrics from Redis.
        
        Returns:
            Risk metrics dictionary or None
        """
        try:
            if not self.connected:
                return None
            
            data = self.client.hgetall('risk:metrics')
            return data if data else None
        
        except Exception as e:
            logger.error(f"Error getting risk metrics: {e}")
            return None
    
    # Performance Metrics
    def store_performance(self, metric_name: str, value: float) -> bool:
        """Store performance metric in Redis.
        
        Args:
            metric_name: Name of the metric
            value: Metric value
        
        Returns:
            True if stored successfully
        """
        try:
            if not self.connected:
                return False
            
            self.client.hset('performance:metrics', 
                           metric_name, str(value))
            return True
        
        except Exception as e:
            logger.error(f"Error storing performance metric: {e}")
            return False
    
    # Session Management
    def register_session(self, session_id: str, data: dict, ttl: int = 3600) -> bool:
        """Register session in Redis.
        
        Args:
            session_id: Unique session identifier
            data: Session data
            ttl: Time to live in seconds
        
        Returns:
            True if registered successfully
        """
        try:
            if not self.connected:
                return False
            
            key = f"session:{session_id}"
            self.client.hset(key, mapping={
                'data': json.dumps(data),
                'created_at': str(datetime.utcnow().isoformat()),
                'last_active': str(datetime.utcnow().isoformat())
            })
            
            self.client.expire(key, ttl)
            return True
        
        except Exception as e:
            logger.error(f"Error registering session: {e}")
            return False
    
    def update_session_activity(self, session_id: str) -> bool:
        """Update session activity timestamp.
        
        Args:
            session_id: Unique session identifier
        
        Returns:
            True if updated successfully
        """
        try:
            if not self.connected:
                return False
            
            key = f"session:{session_id}"
            self.client.hset(key, 'last_active', 
                           str(datetime.utcnow().isoformat()))
            return True
        
        except Exception as e:
            logger.error(f"Error updating session: {e}")
            return False
    
    # Pub/Sub Operations
    def publish(self, channel: str, message: dict) -> bool:
        """Publish message to Redis channel.
        
        Args:
            channel: Channel name
            message: Message dictionary
        
        Returns:
            True if published successfully
        """
        try:
            if not self.connected:
                return False
            
            self.client.publish(channel, json.dumps(message))
            return True
        
        except Exception as e:
            logger.error(f"Error publishing to channel {channel}: {e}")
            return False
    
    def subscribe(self, channel: str):
        """Subscribe to Redis channel.
        
        Args:
            channel: Channel name
        
        Returns:
            PubSub object or None
        """
        try:
            if not self.connected:
                return None
            
            pubsub = self.client.pubsub()
            pubsub.subscribe(channel)
            return pubsub
        
        except Exception as e:
            logger.error(f"Error subscribing to channel {channel}: {e}")
            return None
    
    # Cache Operations
    def set_cache(self, key: str, value: Any, ttl: int = 3600) -> bool:
        """Cache data in Redis.
        
        Args:
            key: Cache key
            value: Value to cache
            ttl: Time to live in seconds
        
        Returns:
            True if cached successfully
        """
        try:
            if not self.connected:
                return False
            
            serialized = json.dumps(value) if not isinstance(value, str) else value
            self.client.setex(key, ttl, serialized)
            return True
        
        except Exception as e:
            logger.error(f"Error caching data: {e}")
            return False
    
    def get_cache(self, key: str) -> Optional[Any]:
        """Get cached data from Redis.
        
        Args:
            key: Cache key
        
        Returns:
            Cached value or None
        """
        try:
            if not self.connected:
                return None
            
            value = self.client.get(key)
            
            if value:
                try:
                    return json.loads(value)
                except (json.JSONDecodeError, TypeError):
                    return value
            
            return None
        
        except Exception as e:
            logger.error(f"Error getting cached data: {e}")
            return None
    
    def delete_cache(self, key: str) -> bool:
        """Delete cached data from Redis.
        
        Args:
            key: Cache key
        
        Returns:
            True if deleted successfully
        """
        try:
            if not self.connected:
                return False
            
            self.client.delete(key)
            return True
        
        except Exception as e:
            logger.error(f"Error deleting cached data: {e}")
            return False
    
    # Health Check
    def health_check(self) -> bool:
        """Check Redis connection health.
        
        Returns:
            True if healthy
        """
        try:
            if not self.connected or not self.client:
                return False
            
            response = self.client.ping()
            return response == True
        
        except Exception as e:
            logger.error(f"Redis health check failed: {e}")
            return False
    
    # Stats
    def get_stats(self) -> dict:
        """Get Redis server statistics.
        
        Returns:
            Dictionary with server stats
        """
        try:
            if not self.connected:
                return {}
            
            info = self.client.info()
            return {
                'used_memory': info.get('used_memory', 0),
                'used_memory_human': info.get('used_memory_human', '0B'),
                'connected_clients': info.get('connected_clients', 0),
                'total_connections_received': info.get('total_connections_received', 0),
                'total_commands_processed': info.get('total_commands_processed', 0),
                'keyspace_hits': info.get('keyspace_hits', 0),
                'keyspace_misses': info.get('keyspace_misses', 0),
                'uptime_in_seconds': info.get('uptime_in_seconds', 0),
            }
        
        except Exception as e:
            logger.error(f"Error getting Redis stats: {e}")
            return {}


# Global Redis client instance
_redis_client = None

def get_redis_client() -> RedisClient:
    """Get global Redis client instance.
    
    Returns:
        RedisClient instance
    """
    global _redis_client
    if _redis_client is None:
        _redis_client = RedisClient()
        _redis_client.connect()
    return _redis_client


def init_redis_client() -> RedisClient:
    """Initialize and connect Redis client."""
    global _redis_client
    _redis_client = RedisClient()
    _redis_client.connect()
    return _redis_client
