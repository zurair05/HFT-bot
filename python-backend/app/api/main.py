"""FastAPI main application for the HFT trading system."""

import os
import time
import asyncio
from datetime import datetime
from typing import Optional, List, Dict, Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, Query, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
import uvicorn

from ..core.config import get_config
from ..core.logger import logger
from ..core.redis_client import get_redis_client
from ..models.database import get_db_manager, Trade, TradeSignal, RiskEvent, PerformanceMetric

# Security
security = HTTPBearer()

# FastAPI app
app = FastAPI(
    title="MT5 HFT Trading API",
    description="Institutional-grade HFT trading system API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_config().api.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global state
connection_manager = None


# Pydantic models
class TickDataModel(BaseModel):    
    symbol: str = Field(..., description="Trading symbol")
    bid: float = Field(..., description="Bid price")
    ask: float = Field(..., description="Ask price")
    spread: Optional[float] = Field(None, description="Spread")
    volume: Optional[int] = Field(None, description="Volume")
    timestamp: Optional[datetime] = Field(None, description="Timestamp")
    latency_ms: Optional[float] = Field(None, description="Latency in milliseconds")


class TradeSignalModel(BaseModel):
    signal_id: str = Field(..., description="Unique signal identifier")
    symbol: str = Field(..., description="Trading symbol")
    signal_type: str = Field(..., description="Signal type (buy/sell/close)")
    strategy: str = Field(..., description="Strategy name")
    entry_price: Optional[float] = Field(None, description="Entry price")
    stop_loss: Optional[float] = Field(None, description="Stop loss price")
    take_profit: Optional[float] = Field(None, description="Take profit price")
    lot_size: Optional[float] = Field(None, description="Lot size")
    confidence: Optional[float] = Field(None, description="Signal confidence (0-1)")
    timestamp: Optional[datetime] = Field(None, description="Signal timestamp")


class RiskAlertsModel(BaseModel):
    event_type: str = Field(..., description="Event type")
    level: str = Field(..., description="Risk level (low/medium/high/critical)")
    description: str = Field(..., description="Event description")
    symbol: Optional[str] = Field(None, description="Related symbol")
    value: Optional[float] = Field(None, description="Current value")
    threshold: Optional[float] = Field(None, description="Threshold value")


class SystemStatusModel(BaseModel):
    status: str = Field(..., description="System status")
    uptime: Optional[str] = Field(None, description="System uptime")
    active_connections: int = Field(0, description="Active WebSocket connections")
    total_trades: int = Field(0, description="Total trades executed")
    open_positions: int = Field(0, description="Current open positions")
    daily_pnl: Optional[float] = Field(None, description="Daily profit/loss")
    total_pnl: Optional[float] = Field(None, description="Total profit/loss")


class WebSocketManager:
    """WebSocket connection manager."""
    
    def __init__(self):
        self.active_connections: List[WebSocket] = []
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        logger.info(f"WebSocket connected. Total connections: {len(self.active_connections)}")
    
    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        logger.info(f"WebSocket disconnected. Total connections: {len(self.active_connections)}")
    
    async def send_personal_message(self, message: str, websocket: WebSocket):
        await websocket.send_text(message)
    
    async def broadcast(self, message: str):
        disconnected = []
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception:
                disconnected.append(connection)
        
        for connection in disconnected:
            if connection in self.active_connections:
                self.active_connections.remove(connection)
    
    async def send_json(self, data: dict):
        """Send JSON data to all connected clients."""
        disconnected = []
        for connection in self.active_connections:
            try:
                await connection.send_json(data)
            except Exception:
                disconnected.append(connection)
        
        for connection in disconnected:
            if connection in self.active_connections:
                self.active_connections.remove(connection)


# Initialize connection manager
manager = WebSocketManager()

# API Key validation
def verify_api_key(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify API key."""
    api_key = credentials.credentials
    # In production, implement proper API key validation
    if api_key != "your-secret-api-key":
        raise HTTPException(status_code=401, detail="Invalid API key")
    return api_key


# API Endpoints
@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "name": "MT5 HFT Trading API",
        "version": "1.0.0",
        "status": "operational",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/status", response_model=SystemStatusModel)
async def get_system_status():
    """Get system status."""
    try:
        redis_client = get_redis_client()
        redis_healthy = redis_client.health_check()
    except Exception as e:
        redis_healthy = False
        logger.error(f"Redis health check failed: {e}")
    
    return SystemStatusModel(
        status="operational",
        active_connections=len(manager.active_connections),
        daily_pnl=0.0,  # Replace with actual daily PnL
        total_pnl=0.0,  # Replace with actual total PnL
        open_positions=0,  # Replace with actual open positions
        total_trades=0  # Replace with actual total trades
    )


@app.post("/trade/signal")
async def receive_trade_signal(signal: TradeSignalModel):
    """Receive a trade signal from external systems."""
    try:
        # Log signal
        logger.info(f"Received trade signal: {signal}")
        
        # Store in database
        db_manager = get_db_manager()
        signal_data = signal.dict()
        db_manager.create_signal(signal_data)
        
        # Store in Redis for real-time access
        redis_client = get_redis_client()
        redis_client.store_signal(signal.signal_id, signal_data)
        
        # Broadcast to WebSocket clients
        await manager.broadcast(f"New trading signal: {signal.signal_type} {signal.symbol}")
        
        return {"status": "success", "message": "Signal received and processed"}
    
    except Exception as e:
        logger.error(f"Error processing trade signal: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.post("/tick/data")
async def receive_tick_data(tick: TickDataModel):
    """Receive tick data from MT5."""
    try:
        # Log tick data
        logger.debug(f"Received tick data: {tick.symbol} - {tick.bid}/{tick.ask}")
        
        # Store in database (optional, can be done in batch)
        # store tick data in Redis for fast access
        redis_client = get_redis_client()
        redis_client.store_tick(tick.symbol, tick.dict())
        
        return {"status": "success", "message": "Tick data received"}
    
    except Exception as e:
        logger.error(f"Error processing tick data: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.post("/risk/alert")
async def receive_risk_alert(alert: RiskAlertsModel):
    """Receive risk alert."""    
    try:
        # Log risk alert
        logger.warning(f"Risk alert: {alert.level} - {alert.description}")
        
        # Store in database
        db_manager = get_db_manager()
        db_manager.record_risk_event(alert.dict())
        
        # Broadcast to WebSocket clients
        alert_message = f"Risk Alert ({alert.level}): {alert.description}"
        await manager.broadcast(alert_message)
        
        return {"status": "success", "message": "Risk alert received and processed"}
    
    except Exception as e:
        logger.error(f"Error processing risk alert: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.get("/trades")
async def get_trades(status: Optional[str] = None, symbol: Optional[str] = None):
    """Get trades with optional filters."""
    try:
        db_manager = get_db_manager()
        # This would need to be implemented in the Database Manager
        # returning a placeholder response for now
        return {"trades": [], "total": 0}
    
    except Exception as e:
        logger.error(f"Error getting trades: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.get("/trades/{trade_id}")
async def get_trade(trade_id: str):
    """Get specific trade by ID."""
    try:
        return {"trade_id": trade_id, "status": "placeholder"}
    
    except Exception as e:
        logger.error(f"Error getting trade: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.get("/performance")
async def get_performance(days: int = 30):
    """Get performance metrics for the last N days."""
    try:
        return {
            "period_days": days,
            "total_trades": 0,
            "winning_trades": 0,
            "losing_trades": 0,
            "win_rate": 0.0,
            "profit_factor": 0.0,
            "sharpe_ratio": 0.0,
            "max_drawdown": 0.0,
            "total_pnl": 0.0
        }
    
    except Exception as e:
        logger.error(f"Error getting performance: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.get("/strategies")
async def get_strategies():
    """Get active strategies and their performance."""
    try:
        db_manager = get_db_manager()
        # This would be implemented to fetch strategies from database
        return {
            "strategies": [
                {"name": "UltraFastScalping", "type": "screener", "status": "active"},
                {"name": "OrderFlow", "type": "reversal", "status": "active"},
                {"name": "VolatilityBreakout", "type": "momentum", "status": "active"},
                {"name": "MeanReversion", "type": "reversal", "status": "active"}
            ],
            "total_active": 4
        }
    
    except Exception as e:
        logger.error(f"Error getting strategies: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.get("/risk/metrics")
async def get_risk_metrics():
    """Get current risk metrics."""
    try:
        redis_client = get_redis_client()
        metrics = redis_client.get_risk_metrics()
        return {
            "metrics": metrics or {}
        }
    
    except Exception as e:
        logger.error(f"Error getting risk metrics: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.post("/trading/disable")
async def disable_trading():
    """Disable trading for all strategies."""
    try:
        # Set trading enabled to false in Redis
        redis_client = get_redis_client()
        redis_client.set_cache('trading_enabled', False)
        
        logger.warning("Trading DISABLED via API")
        return {"status": "success", "message": "Trading disabled"}
    
    except Exception as e:
        logger.error(f"Error disabling trading: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


@app.post("/trading/enable")
async def enable_trading():
    """Enable trading for all strategies."""
    try:
        # Set trading enabled to true in Redis
        redis_client = get_redis_client()
        redis_client.set_cache('trading_enabled', True)
        
        logger.info("Trading ENABLED via API")
        return {"status": "success", "message": "Trading enabled"}
    
    except Exception as e:
        logger.error(f"Error enabling trading: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {e}")


# WebSocket endpoints
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates."""
    await manager.connect(websocket)
    
    try:
        while True:
            data = await websocket.receive_text()
            logger.debug(f"WebSocket received: {data}")
            
            # Echo back for testing
            await manager.send_personal_message(f"Echo: {data}", websocket)
    
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        manager.disconnect(websocket)


@app.websocket("/ws/market-data")
async def market_data_websocket(websocket: WebSocket):
    """WebSocket endpoint for real-time market data."""
    await manager.connect(websocket)
    
    try:
        while True:
            # In a real implementation, this would stream market data
            # For now, just keeping the connection alive
            data = await websocket.receive_text()
    
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"Market data WebSocket error: {e}")
        manager.disconnect(websocket)


# Health check
@app.get("/health")
async def health_check():
    """Health check endpoint."""
    try:
        redis_client = get_redis_client()
        redis_healthy = redis_client.health_check()
    except Exception as e:
        redis_healthy = False
        logger.error(f"Redis health check failed: {e}")
    
    return {
        "status": "healthy",
        "redis": "up" if redis_healthy else "down",
        "database": "up",
        "timestamp": datetime.utcnow().isoformat()
    }


# Error handlers
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler."""
    logger.error(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )


def run_api_server(host: str = "0.0.0.0", port: int = 8000, workers: int = 4, reload: bool = False):
    """Run the API server.
    
    Args:
        host: Host address
        port: Port number
        workers: Number of worker processes
        reload: Enable auto-reload for development
    """
    uvicorn.run(
        "app.api.main:app",
        host=host,
        port=port,
        workers=workers,
        reload=reload,
        log_level="info"
    )
