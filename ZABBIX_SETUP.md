# Zabbix 7.0.1 Integration Setup and Testing

This guide describes how to set up Zabbix 7.0.1 using Docker Compose and test the Azure Storage Cost Monitor template integration.

## Template Versions

The repository includes three template formats:

1. **zabbix-template-azure-storage-monitor-7.0.yaml** - YAML format (recommended) ⭐
   - **Modern, clean YAML format**
   - Includes all items, discovery rules, and triggers
   - Smaller file size (13K vs 24K XML)
   - Better readability and maintainability
   - UUID format: Without dashes (32 chars - API compatible)
   - Compatible with both Web UI and API import
   - **Used by default in automated tests**

2. **zabbix-template-azure-storage-monitor-7.0.xml** - XML format (Web UI)
   - Full production template in XML format
   - Includes all items, discovery rules, and triggers
   - UUID format: With dashes (UUID v4: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
   - Best for Web UI import
   - Contains triggers inside items (Zabbix 7.0 structure)

3. **zabbix-template-azure-storage-monitor-7.0-test.xml** - Simplified XML (deprecated)
   - Legacy simplified test template
   - UUID format: Without dashes (32 chars)
   - Use YAML version instead for new deployments

**Format Comparison:**

| Format | Size | API Import | Web UI Import | Readability | Recommended |
|--------|------|------------|---------------|-------------|-------------|
| YAML   | 13K  | ✅ Yes     | ✅ Yes        | ⭐⭐⭐       | ✅ **Yes**  |
| XML    | 24K  | ⚠️ Complex | ✅ Yes        | ⭐⭐         | For Web UI only |
| Test XML | 8K | ✅ Yes     | ✅ Yes        | ⭐           | ❌ Deprecated |

**Important UUID Notes:**
- **YAML format**: UUIDs without dashes (works for both API and Web UI)
- **XML format (full)**: UUIDs with dashes (best for Web UI)
- **XML format (test)**: UUIDs without dashes (API compatible)

**Usage Examples:**
```bash
# Use YAML template (recommended, default)
./test-zabbix-integration.sh

# Use full XML template
ZABBIX_TEMPLATE_FILE=./zabbix-template-azure-storage-monitor-7.0.xml \
  ./test-zabbix-integration.sh

# Use legacy test XML
ZABBIX_TEMPLATE_FILE=./zabbix-template-azure-storage-monitor-7.0-test.xml \
  ./test-zabbix-integration.sh
```

## Prerequisites

Before starting, ensure you have the following installed:

- Docker (version 20.10 or later)
- Docker Compose (version 2.0 or later)
- `jq` - JSON processor
- `curl` - HTTP client
- `zabbix_sender` (optional, will use container version if not available)

### Installing Prerequisites

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose jq curl
# Optional: zabbix-sender
sudo apt-get install -y zabbix-sender
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install -y docker docker-compose jq curl
# Optional: zabbix-sender
sudo dnf install -y zabbix-sender
```

**macOS:**
```bash
brew install docker docker-compose jq curl
# Optional: zabbix-sender
brew install zabbix
```

## Quick Start

### 1. Start Zabbix

```bash
# Start all Zabbix services
docker compose -f docker-compose.zabbix.yml up -d

# Check status
docker compose -f docker-compose.zabbix.yml ps

# View logs
docker compose -f docker-compose.zabbix.yml logs -f
```

### 2. Access Zabbix Web Interface

Once all containers are healthy (this may take 1-2 minutes):

- URL: http://localhost:8080
- Username: `Admin`
- Password: `zabbix`

### 3. Run Integration Test

The integration test will automatically:
- Start Zabbix containers
- Wait for services to be ready
- Import the Azure Storage Cost Monitor template
- Create a test host
- Send test data
- Verify data was received

```bash
# Run the test (will clean up automatically)
./test-zabbix-integration.sh

# Keep Zabbix running after test
SKIP_CLEANUP=true ./test-zabbix-integration.sh
```

## Manual Setup (Alternative)

If you prefer to set up manually instead of using the automated test:

### 1. Start Zabbix

```bash
docker compose -f docker-compose.zabbix.yml up -d
```

Wait for all services to become healthy:
```bash
docker compose -f docker-compose.zabbix.yml ps
```

### 2. Login to Zabbix Web Interface

1. Open http://localhost:8080 in your browser
2. Login with credentials:
   - Username: `Admin`
   - Password: `zabbix`

### 3. Import Template

1. Navigate to **Data collection** → **Templates**
2. Click **Import** button (top right)
3. Choose file: `zabbix-template-azure-storage-monitor-7.0.xml`
4. Configure import rules:
   - ✓ Create new templates
   - ✓ Update existing templates
   - ✓ Create new items
   - ✓ Update existing items
   - ✓ Create new triggers
   - ✓ Update existing triggers
   - ✓ Create new discovery rules
   - ✓ Update existing discovery rules
5. Click **Import**

### 4. Create Host

1. Navigate to **Data collection** → **Hosts**
2. Click **Create host** (top right)
3. Configure host:
   - **Host name**: `azure-storage-monitor`
   - **Visible name**: `Azure Storage Cost Monitor`
   - **Groups**: Select or create `Linux servers`
   - **Interfaces**: Add agent interface (127.0.0.1:10050)
4. Go to **Templates** tab
5. Link template: `Azure Storage Cost Monitor`
6. Click **Add**

### 5. Send Test Data

Use the Azure Storage Cost Analyzer script to send real data:

```bash
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions "<your-subscription-id>" \
  --days 30 \
  --output-format json \
  --zabbix-send \
  --zabbix-server localhost \
  --zabbix-host azure-storage-monitor
```

Or send test data manually:

```bash
# Create test data file
cat > /tmp/zabbix_test.txt << 'EOF'
azure-storage-monitor azure.storage.all.total_waste.monthly $(date +%s) 123.45
azure-storage-monitor azure.storage.all.total_disks $(date +%s) 5
azure-storage-monitor azure.storage.all.total_snapshots $(date +%s) 3
azure-storage-monitor azure.storage.all.subscriptions_scanned $(date +%s) 2
EOF

# Send using zabbix_sender
zabbix_sender -z localhost -p 10051 -i /tmp/zabbix_test.txt

# Or use container's zabbix_sender
docker exec zabbix-server zabbix_sender -z localhost -p 10051 -i /tmp/zabbix_test.txt
```

### 6. Verify Data

1. Navigate to **Monitoring** → **Hosts**
2. Click on host: `azure-storage-monitor`
3. Click **Latest data**
4. You should see values for:
   - Total Monthly Waste (All Subscriptions)
   - Total Unattached Disks Count
   - Total Snapshots Count
   - And other metrics

## Template Features

The Azure Storage Cost Monitor template includes:

### Items (Metrics)
- **Total Monthly Waste** - Aggregated cost across all subscriptions
- **Total Unattached Disks Count** - Number of unattached disks
- **Total Snapshots Count** - Number of snapshots
- **Subscriptions Scanned** - Number of scanned subscriptions
- **Invalid Review Tags** - Resources with malformed tags
- **Excluded Pending Review** - Resources excluded due to review dates
- **Script Execution Metrics** - Last run timestamp, execution time, status

### Discovery Rules
- **Azure Subscriptions Discovery** - Auto-discovers subscriptions
  - Creates per-subscription metrics for waste, disks, snapshots
  - Creates triggers for high waste alerts

### Triggers
- **High total storage waste** (>$500) - WARNING
- **Critical total storage waste** (>$1000) - HIGH
- **Script hasn't run in 24 hours** - AVERAGE
- **Script execution failed** - WARNING
- **Invalid review date tags detected** - WARNING
- Per-subscription triggers for high waste and disk counts

## Troubleshooting

### Containers won't start

Check Docker logs:
```bash
docker compose -f docker-compose.zabbix.yml logs
```

### Can't access web interface

1. Check if containers are running:
   ```bash
   docker compose -f docker-compose.zabbix.yml ps
   ```

2. Check if port 8080 is available:
   ```bash
   lsof -i :8080
   # or
   netstat -tuln | grep 8080
   ```

3. Try accessing via curl:
   ```bash
   curl http://localhost:8080/ping
   ```

### Data not appearing in Zabbix

1. Check zabbix_sender output for errors
2. Verify host is monitored (not disabled)
3. Check that template is properly linked to host
4. Review Zabbix server logs:
   ```bash
   docker compose -f docker-compose.zabbix.yml logs zabbix-server | grep -i error
   ```

### Template import fails

- Ensure you're using Zabbix 7.0.x (template is not compatible with older versions)
- Check Zabbix server logs for import errors
- Verify XML file is not corrupted

## Stopping Zabbix

```bash
# Stop containers (preserves data)
docker compose -f docker-compose.zabbix.yml stop

# Stop and remove containers (preserves data in volumes)
docker compose -f docker-compose.zabbix.yml down

# Stop and remove everything including data
docker compose -f docker-compose.zabbix.yml down -v
```

## Configuration Files

- `docker-compose.zabbix.yml` - Docker Compose configuration for Zabbix 7.0.1
- `zabbix-template-azure-storage-monitor-7.0.xml` - Zabbix template
- `test-zabbix-integration.sh` - Automated integration test script

## Default Credentials

**Zabbix Web Interface:**
- URL: http://localhost:8080
- Username: `Admin`
- Password: `zabbix`

**PostgreSQL Database:**
- Host: localhost:5432
- Database: `zabbix`
- Username: `zabbix`
- Password: `zabbix_password`

**Important:** Change these credentials in production!

## Network Ports

- **8080** - Zabbix web interface (HTTP)
- **10051** - Zabbix server (trapper)
- **10050** - Zabbix agent
- **5432** - PostgreSQL (internal only)

## Data Persistence

Data is stored in Docker volumes:
- `postgres-data` - PostgreSQL database
- `zabbix-server-data` - Zabbix server data

To back up:
```bash
docker run --rm \
  -v azure-storage-cost-analyzer_postgres-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/zabbix-backup-$(date +%Y%m%d).tar.gz /data
```

## Integration with Azure Storage Cost Analyzer

The script `azure-storage-cost-analyzer.sh` has built-in Zabbix integration:

```bash
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --output-format json \
  --zabbix-send \
  --zabbix-server localhost \
  --zabbix-port 10051 \
  --zabbix-host azure-storage-monitor
```

You can also configure Zabbix settings in `azure-storage-monitor.conf`:

```ini
[zabbix]
auto_send = true
server = localhost
port = 10051
host = azure-storage-monitor
config_file = /etc/zabbix/zabbix_agentd.conf
```

## Production Deployment

For production use:

1. **Change default passwords** in `docker-compose.zabbix.yml`
2. **Use HTTPS** - add nginx reverse proxy with SSL
3. **Configure backups** for PostgreSQL data
4. **Set up monitoring** for Zabbix containers themselves
5. **Configure firewall** to restrict access to Zabbix ports
6. **Use external database** for better performance and reliability
7. **Configure email** for alert notifications

## Support

For issues related to:
- **Zabbix template**: Check this repository's issues
- **Zabbix software**: Visit https://www.zabbix.com/documentation/7.0/
- **Docker setup**: Check Docker Compose documentation

## License

This setup follows the same license as the main project.
