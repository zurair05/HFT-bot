"""FastAPI application for the HFT trading dashboard."""

from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import uvicorn

from ..core.logger import logger
from ..core.config import get_config
from ..core.redis_client import get_redis_client
from ..services.mt5_connector import get_mt5_connector

# Create FastAPI app
app = FastAPI(
    title="MT5 HFT Dashboard",
    description="Real-time Monitoring Dashboard for HFT Trading System",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc"
)

# Templates
templates = Jinja2Templates(directory="templates")

# WebSocket manager for real-time updates
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        logger.info(f"Dashboard WebSocket connected. Total: {len(self.active_connections)}")
    
    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        logger.info(f"Dashboard WebSocket disconnected. Total: {len(self.active_connections)}")
    
    async def broadcast(self, message: Dict[str, Any]):
        disconnected = []
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                disconnected.append(connection)
        
        for connection in disconnected:
            if connection in self.active_connections:
                self.active_connections.remove(connection)

manager = ConnectionManager()


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page."""
    return templates.TemplateResponse("index.html", {"request": request, "title": "HFT Dashboard"})


@app.get("/api/status")
async def get_status():
    """Get system status."""
    try:
        mt5 = get_mt5_connector()
        redis_client = get_redis_client()
        
        account_info = mt5.get_account_info() if mt5.is_connected() else {}
        
        return {
            "status": "operational",
            "mt5_connected": mt5.is_connected(),
            "redis_connected": redis_client.connected,
            "account_info": account_info,
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Error getting status: {e}")
        return {"status": "error", "message": str(e)}


@app.get("/api/trades")
async def get_trades(limit: int = 100):
    """Get recent trades."""
    try:
        mt5 = get_mt5_connector()
        trades = mt5.get_positions() if mt5.is_connected() else []
        
        return {
            "trades": trades[:limit],
            "total": len(trades)
        }
    except Exception as e:
        logger.error(f"Error getting trades: {e}")
        return {"trades": [], "total": 0}


@app.get("/api/tick-data/{symbol}")
async def get_tick_data(symbol: str):
    """Get tick data for a symbol."""
    try:
        mt5 = get_mt5_connector()
        tick_data = mt5.get_tick_data(symbol)
        
        return {
            "symbol": symbol,
            "data": tick_data[1] if tick_data else {}
        }
    except Exception as e:
        logger.error(f"Error getting tick data: {e}")
        return {"symbol": symbol, "data": {}}


@app.get("/api/ohlc/{symbol}")
async def get_ohlc(symbol: str, timeframe: str = "M1", count: int = 100):
    """Get OHLC data for a symbol."""
    try:
        mt5 = get_mt5_connector()
        ohlc_data = mt5.get_ohlc_data(symbol, timeframe, count)
        
        return {
            "symbol": symbol,
            "timeframe": timeframe,
            "data": ohlc_data
        }
    except Exception as e:
        logger.error(f"Error getting OHLC data: {e}")
        return {"symbol": symbol, "data": {}}


@app.get("/api/performance")
async def get_performance():
    """Get performance metrics."""
    try:
        mt5 = get_mt5_connector()
        profit = mt5.get_total_profit() if mt5.is_connected() else 0.0
        
        return {
            "total_profit": profit,
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Error getting performance: {e}")
        return {"total_profit": 0.0}


@app.websocket("/ws/dashboard")
async def dashboard_websocket(websocket: WebSocket):
    """WebSocket for real-time dashboard updates."""
    await manager.connect(websocket)
    
    try:
        while True:
            # Wait for messages from client
            data = await websocket.receive_text()
            
            # Handle different message types
            if data == "ping":
                await websocket.send_text("pong")
            elif data == "status":
                status = await get_status()
                await websocket.send_json(status)
            else:
                await websocket.send_json({"message": f"Echo: {data}"})
    
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"Dashboard WebSocket error: {e}")
        manager.disconnect(websocket)


def run_dashboard_server(host: str = "0.0.0.0", port: int = 8080):
    """Run the dashboard server."""
    uvicorn.run(
        "app.dashboard.app:app",
        host=host,
        port=port,
        reload=False,
        log_level="info"
    )