# Deployment Guide

## Quick Start

### 1. Development Environment

#### Prerequisites
- Python 3.10+
- PostgreSQL 15+
- Redis 7+
- MetaTrader 5

#### Installation
```bash
# Clone repository
git clone https://github.com/your-repo/mt5-hft-trading-bot.git
cd mt5-hft-trading-bot

# Install dependencies
pip install -r python-backend/requirements.txt

# Set up database
psql -U postgres < database/migrations/schema.sql

# Run tests
pytest python-backend/tests/
```

#### Configuration
```json
{
  "system": {
    "mode": "development",
    "log_level": "DEBUG"
  }
}
```

### 2. Production Environment

#### Server Setup
```bash
# Update system
sudo apt-get update
sudo apt-get upgrade

# Install Docker and Docker Compose
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Clone repository
git clone https://github.com/your-repo/mt5-hft-trading-bot.git
cd mt5-hft-trading-bot

# Create environment file
cp .env.example .env
nano .env

# Build and start services
docker-compose up -d
```

#### Production Configuration
```json
{
  "system": {
    "mode": "production",
    "log_level": "INFO",
    "environment": "vps"
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "database": "mt5_hft_db",
    "username": "trading_bot",
    "password": "your_strong_password",
    "pool_size": 20
  }
}
```

## Step-by-Step Deployment

### 1. Server Preparation

#### Choose VPS Provider
Recommended providers:
- DigitalOcean (Droplets)
- AWS (EC2)
- Google Cloud (Compute Engine)
- Azure (Virtual Machines)
- Linode

#### Server Requirements
- CPU: 8+ cores
- RAM: 32GB
- Storage: SSD 500GB
- Bandwidth: 1 Gbps
- OS: Ubuntu 22.04 LTS (recommended)

#### Initial Setup
```bash
# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install essential packages
sudo apt-get install -y git htop vim curl wget
sudo apt-get install -y python3 python3-pip python3-venv
sudo apt-get install -y postgresql postgresql-contrib redis-server

# Install Docker
sudo apt-get install -y docker.io docker-compose
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

### 2. Application Setup

#### Clone Repository
```bash
# Create project directory
mkdir -p /opt/hft-trading-bot
cd /opt/hft-trading-bot

# Clone repository
git clone https://github.com/your-repo/mt5-hft-trading-bot.git .
```

#### Environment Setup
```bash
# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r python-backend/requirements.txt

# Create .env file
cat > .env << EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=mt5_hft_db
DB_USER=trading_bot
DB_PASSWORD=your_strong_password
REDIS_HOST=localhost
REDIS_PORT=6379
API_KEY=your_api_key
TELEGRAM_BOT_TOKEN=your_bot_token
EOF
```

### 3. Database Setup

#### PostgreSQL Setup
```bash
# Switch to postgres user
sudo -u postgres psql

# Create database and user
CREATE DATABASE mt5_hft_db;
CREATE USER trading_bot WITH ENCRYPTED PASSWORD 'your_strong_password';
GRANT ALL PRIVILEGES ON DATABASE mt5_hft_db TO trading_bot;
\q

# Setup schema
psql -U trading_bot -d mt5_hft_db -f database/migrations/schema.sql
```

#### Redis Setup
```bash
# Configure Redis
sudo sed -i 's/# requirepass foobared/requirepass your_redis_password/' /etc/redis/redis.conf
sudo systemctl restart redis-server

# Verify Redis connection
redis-cli -a your_redis_password ping
```

### 4. Application Configuration

#### System Configuration
Create `configs/system_config.json`:
```json
{
  "system": {
    "name": "MT5 HFT Trading Bot",
    "version": "1.0.0",
    "mode": "production",
    "environment": "vps",
    "timezone": "UTC",
    "log_level": "INFO"
  },
  "mt5": {
    "path": "/opt/MetaTrader/terminal64.exe",
    "symbols": ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "NAS100", "US30"],
    "max_tick_latency_ms": 50
  }
}
```

#### Risk Configuration
Create `configs/risk_config.json`:
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

### 5. Docker Deployment

#### Build and Run

##### Method 1: Using Docker Compose
```bash
# Build images
docker-compose build

# Start services
docker-compose up -d

# View logs
docker-compose logs -f python-backend

# Scale services
docker-compose up -d --scale python-backend=4
```

##### Method 2: Manual Docker
```bash
# Build image
docker build -f python-backend/Dockerfile -t hft-trading-bot:latest .

# Run container
docker run -d -p 8000:8000 -p 8001:8001 \
  --name hft-trading-bot \
  -v $(pwd)/configs:/app/configs \
  hft-trading-bot:latest
```

### 6. MetaTrader 5 Setup

#### Requirements
- MetaTrader 5 installed on VPS
- Valid MT5 account with broker
- DLL imports enabled

#### Configuration
1. Copy MQL5 files to `MQL5/Experts`
2. Compile EA in MetaEditor
3. Configure input parameters
4. Enable "Allow DLL imports"
5. Attach to chart in MT5

### 7. Monitoring Setup

#### Grafana Dashboard
```bash
# Access Grafana at http://your-server:3000
# Login: admin/admin

# Import dashboard
curl -X POST \
  http://admin:admin@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @configs/grafana/dashboards/hft_dashboard.json
```

#### Prometheus Configuration
Edit `configs/prometheus/prometheus.yml`:
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'hft-trading-bot'
    static_configs:
      - targets: ['localhost:8000']
```

### 8. SSL/TLS Setup

#### Using Let's Encrypt
```bash
# Install certbot
sudo apt-get install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal
echo "0 0 * * * certbot renew --quiet" | sudo crontab -
```

## Advanced Configuration

### 1. Performance Tuning

#### PostgreSQL Optimization
```sql
-- Increase max connections
ALTER SYSTEM SET max_connections = 200;

-- Memory settings
ALTER SYSTEM SET shared_buffers = '8GB';
ALTER SYSTEM SET effective_cache_size = '24GB';
ALTER SYSTEM SET work_mem = '64MB';

-- WAL settings
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET max_wal_size = '4GB';
```

#### Redis Optimization
```bash
# Edit redis.conf
sudo nano /etc/redis/redis.conf

# Key settings
maxmemory 2gb
maxmemory-policy allkeys-lru
tcp-keepalive 60
timeout 0
```

#### Python Optimization
```python
# app/core/config.py
class DatabaseConfig:
    pool_size = 20
    max_overflow = 10
    pool_timeout = 30

class APIConfig:
    workers = 4
    max_requests = 1000
```

### 2. Security Hardening

#### Firewall Setup
```bash
# Install and configure UFW
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 8000/tcp  # API
sudo ufw allow 3000/tcp  # Grafana
sudo ufw enable
```

#### API Security
```python
# app/api/auth.py
from fastapi import Depends, HTTPException
from fastapi.security import APIKeyHeader

api_key_header = APIKeyHeader(name="X-API-Key")

def verify_api_key(api_key: str = Depends(api_key_header)):
    if api_key != SECRET_API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return api_key
```

### 3. Backup Strategy

#### Database Backup
```bash
# Create backup script
cat > /opt/backup-db.sh << 'EOF'
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
pg_dump -U trading_bot mt5_hft_db > /backup/mt5_hft_db_$TIMESTAMP.sql
find /backup -name "*.sql" -mtime +7 -delete
EOF

chmod +x /opt/backup-db.sh

# Schedule daily backups
echo "0 2 * * * /opt/backup-db.sh" | crontab -
```

#### Redis Backup
```bash
# Enable AOF persistence
sudo sed -i 's/appendonly no/appendonly yes/' /etc/redis/redis.conf
sudo systemctl restart redis-server
```

### 4. Scaling

#### Horizontal Scaling
```bash
# Run multiple instances behind load balancer
docker-compose up -d --scale python-backend=4

# Nginx configuration
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

### 5. Troubleshooting

#### Common Issues

**Issue:** Connection refused to PostgreSQL
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check port
sudo netstat -tlnp | grep 5432

# Update pg_hba.conf
sudo nano /etc/postgresql/15/main/pg_hba.conf
# Add: host all all 0.0.0.0/0 md5
```

**Issue:** Redis connection timeout
```bash
# Check Redis status
sudo systemctl status redis-server

# Check max memory
redis-cli info memory

# Flush old data
redis-cli FLUSHALL
```

**Issue:** High latency
```bash
# Check CPU usage
htop

# Check memory usage
free -h

# Profile Python application
python -m cProfile -o stats.prof app/main.py
```

#### Logs
```bash
# View Python application logs
docker-compose logs -f python-backend

# View system logs
sudo journalctl -u hft-trading-bot -f

# Check database logs
sudo tail -f /var/log/postgresql/postgresql-15-main.log
```

### 6. Maintenance

#### Regular Tasks
```bash
# Daily
docker system prune -f

# Weekly
sudo apt-get update && sudo apt-get upgrade

# Monthly
psql -U trading_bot -d mt5_hft_db -c "VACUUM ANALYZE;"
```

#### Upgrades
```bash
# Update code
git pull origin main

# Rebuild containers
docker-compose build --no-cache
docker-compose up -d

# Update database schema
alembic upgrade head
```

## Support

For issues and support:
- GitHub Issues: https://github.com/your-repo/mt5-hft-trading-bot/issues
- Email: trading@institutionaldesk.com
- Documentation: https://docs.mt5-hft-bot.com

---

**Version:** 1.0.0
**Last Updated:** 2025-01-15