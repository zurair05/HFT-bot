# MT5 HFT Trading System

A professional institutional-grade Forex HFT trading bot specifically for MetaTrader 5 with ultra-low latency execution, advanced risk management, smart order routing, and scalable architecture.

## System Overview

This system provides:

- **High-frequency scalping** with 1-5 pip targets
- **Tick-level execution** with minimal latency
- **Multi-symbol trading** (EURUSD, GBPUSD, USDJPY, XAUUSD, NAS100, US30)
- **Smart risk management** with prop firm compliance
- **AI/ML integration** for signal enhancement
- **Real-time analytics** and monitoring dashboard
- **Multiple strategies** including scalping, order flow, market making, breakout, and mean reversion

## Architecture

### Components

1. **MQL5 Expert Advisor** - Core execution in MT5
2. **Python FastAPI Backend** - AI/ML, analytics, API
3. **PostgreSQL** - Trade storage & analytics
4. **Redis** - High-speed cache & pub/sub
5. **Grafana** - Monitoring dashboards
6. **Docker** - Containerized deployment

### Directory Structure

```
mt5-hft-trading-bot/
├── configs/                 # Configuration files
│   ├── system_config.json
│   ├── risk_config.json
│   └── strategies_config.json
├── mql5/                    # MetaTrader 5 code
│   ├── Experts/
│   │   └── HFT_EA.mq5      # Main EA
│   ├── Include/
│   │   ├── HG_Common.mqh    # Common definitions
│   │   ├── HG_RiskManagement.mqh
│   │   ├── HG_ExecutionEngine.mqh
│   │   └── HG_Strategies.mqh
│   └── Scripts/
├── python-backend/          # Python backend services
│   ├── app/
│   │   ├── api/            # FastAPI application
│   │   ├── core/           # Core utilities
│   │   ├── models/         # Database models
│   │   ├── services/       # Business logic
│   │   ├── ai/             # AI/ML modules
│   │   ├── dashboard/      # Monitoring dashboard
│   │   └── strategies/     # Strategy implementations
│   ├── ai/                  # AI model implementations
│   ├── backtesting/         # Backtesting engine
│   ├── tests/               # Test suite
│   └── requirements.txt   # Python dependencies
├── database/                # Database scripts
│   ├── migrations/         # Schema migrations
│   └── seeds/              # Seed data
├── docker/                  # Docker configurations
│   ├── docker-compose.yml
│   └── Dockerfile.python
└── docs/                    # Documentation
    ├── ARCHITECTURE.md
    └── DEPLOYMENT.md
```

## Installation

### Prerequisites

- MetaTrader 5
- Python 3.10+
- PostgreSQL 15+
- Redis 7+
- Docker & Docker Compose (optional)

### Step 1: Clone Repository

```bash
git clone https://github.com/your-repo/mt5-hft-trading-bot.git
cd mt5-hft-trading-bot
```

### Step 2: Install Python Dependencies

```bash
cd python-backend
pip install -r requirements.txt
```

### Step 3: Setup PostgreSQL

Create a PostgreSQL database:

```bash
psql -U postgres -c "CREATE DATABASE mt5_hft_db;"
psql -U postgres -c "CREATE USER trading_bot WITH PASSWORD 'your_password';"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE mt5_hft_db TO trading_bot;"
```

### Step 4: Setup Redis

Install and start Redis:

```bash
# Ubuntu/Debian
sudo apt-get install redis-server
sudo service redis-server start

# macOS
brew install redis
brew services start redis
```

### Step 5: Configure Environment Variables

Create a `.env` file in the root directory:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=mt5_hft_db
DB_USER=trading_bot
DB_PASSWORD=your_password
REDIS_HOST=localhost
REDIS_PORT=6379
```

### Step 6: Run the System

Start the Python backend:

```bash
# Start the API server
uvicorn app.api.main:app --host 0.0.0.0 --port 8000 --workers 4

# Start the Dashboard
uvicorn app.dashboard.app:app --host 0.0.0.0 --port 8080
```

### Step 7: Install MQL5 EA

1. Copy MQL5 files to the `MQL5/Experts` directory in your MT5 data folder
2. Compile the EA in MetaEditor
3. Attach the EA to the chart in MT5

## Configuration

### System Configuration

Edit `configs/system_config.json`:

```json
{
  "system": {
    "name": "MT5 HFT Trading Bot",
    "version": "1.0.0",
    "mode": "production",
    "environment": "vps",
    "timezone": "UTC"
  },
  "mt5": {
    "symbols": ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "NAS100", "US30"],
    "max_tick_latency_ms": 50,
    "execution_mode": "auto"
  }
}
```

### Risk Configuration

Edit `configs/risk_config.json`:

```json
{
  "account_protection": {
    "max_daily_drawdown_percent": 4.0,
    "max_total_drawdown_percent": 8.0,
    "equity_protection_percent": 85.0
  },
  "position_risk": {
    "max_lot_size": 10.0,
    "max_simultaneous_trades": 5,
    "risk_per_trade_percent": 1.0
  }
}
```

### Strategy Configuration

Edit `configs/strategies_config.json` for strategy settings.

## Usage

### Running in MetaTrader 5

1. Attach `HFT_EA.mq5` to a chart
2. Configure input parameters
3. Enable "Allow DLL imports" in MT5
4. Start the EA

### Running Python Backend

```bash
# Development
uvicorn app.api.main:app --reload --port 8000

# Production
uvicorn app.api.main:app --host 0.0.0.0 --port 8000 --workers 4
```

### Running with Docker

```bash
# Build and start services
docker-compose up -d

# View logs
docker-compose logs -f python-backend

# Stop services
docker-compose down
```

## API Endpoints

### Trade Signals

- `POST /trade/signal` - Submit a new trade signal
- `GET /trades` - Get all trades
- `GET /trades/{trade_id}` - Get specific trade

### Risk Management

- `POST /risk/alert` - Submit risk alert
- `GET /risk/metrics` - Get current risk metrics

### Performance

- `GET /performance` - Get performance metrics
- `GET /strategies` - Get active strategies

### System Status

- `GET /health` - Health check
- `GET /status` - System status

### WebSockets

- `/ws` - Real-time data stream

## Strategies

### 1. Ultra Fast Scalping

- 1-5 pip targets
- Tick momentum detection
- Spread-aware entries
- Micro pullback entries

### 2. Order Flow

- Tick pressure analysis
- Bid/ask imbalance
- Aggressive candle detection

### 3. Market Making

- Dynamic spread capture
- Inventory balancing
- Volatility-adjusted entries

### 4. Volatility Breakout

- Session breakouts (London, NY, Tokyo)
- ATR-based entries
- Volume confirmation

### 5. Mean Reversion

- VWAP reversion
- Statistical reversals
- Liquidity grab detection

## Risk Management

The system implements comprehensive risk management:

### Account Protection
- Daily drawdown limit
- Max total drawdown
- Equity protection
- Margin monitoring

### Position Risk
- Max lot size
- Max simultaneous trades
- Symbol exposure limits
- Correlation exposure

### Market Risk
- Spread spike detection
- High volatility filter
- News filter
- Session filters

### Prop Firm Features
- Daily loss rule protection
- Consistency rule support
- Max position duration
- News trading disable

## AI/ML Integration

The system uses AI for:

- **LSTM Price Prediction** - Predict price direction
- **Volatility Analysis** - Predict market volatility
- **Trade Quality Scoring** - Score potential trades
- **Feature Engineering** - Technical indicator analysis

## Performance Monitoring

### Key Metrics
- Tick-to-trade latency
- Broker response time
- Signal processing time
- Slippage statistics
- Win rate per strategy
- PnL per symbol

### Dashboard
Access the Grafana dashboard at `http://localhost:3000`

### Alerts
Configure alerts in `configs/system_config.json` for:
- Telegram
- Discord
- Email

## Testing

### Run Tests

```bash
cd python-backend
pytest tests/ -v
```

### Test Coverage
- Unit tests for core components
- Integration tests for API endpoints
- Stress tests for execution engine
- Broker disconnect simulation

## Backtesting

### Run Backtest

```python
from backtesting.backtest_engine import BacktestEngine, BacktestConfig

config = BacktestConfig(
    symbol="EURUSD",
    timeframe="M1",
    start_date="2023-01-01",
    end_date="2023-12-31"
)

engine = BacktestEngine(config)
engine.load_data("data/eurusd_ticks.csv")
report = engine.run_backtest()
```

### Reports
View comprehensive backtest reports with:
- Trade statistics
- Performance metrics
- Equity curves
- Risk analysis

## Deployment

### VPS Setup

Recommended VPS configuration:
- CPU: 8+ cores
- RAM: 32GB
- Storage: SSD 500GB
- Bandwidth: 1000 Mbps
- OS: Ubuntu 22.04 LTS

### Production Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions.

## Support

For support, contact: 

## License

MIT License - See LICENSE file for details

---

**Version:** 1.0.0
**Last Updated:** 2025-01-15
