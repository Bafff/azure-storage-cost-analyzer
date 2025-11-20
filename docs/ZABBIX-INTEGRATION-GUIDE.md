# Zabbix Integration Guide - Azure Storage Cost Monitor

**Version:** 1.0
**Zabbix Version:** 7.0.5+
**Script:** `azure-storage-cost-analyzer.sh`
**Last Updated:** 2025-11-20

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Zabbix Server Setup](#zabbix-server-setup)
5. [Azure DevOps Pipeline Integration](#azure-devops-pipeline-integration)
6. [Manual Execution](#manual-execution)
7. [Metrics Reference](#metrics-reference)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This integration enables automated monitoring of Azure storage waste (unattached disks and snapshots) across multiple Azure subscriptions, with metrics sent to Zabbix 7.0.5+ for alerting and trending.

### Key Features

- **Multi-subscription scanning**: Scan all Azure subscriptions in one execution
- **Automatic Zabbix reporting**: Metrics sent directly to Zabbix via `zabbix_sender`
- **Low-Level Discovery (LLD)**: Per-subscription metrics with dynamic discovery
- **Cost alerting**: Warning ($100/month, $500/month) and critical ($250/month, $1000/month) thresholds
- **Azure DevOps native**: Designed for pipeline execution

---

## Architecture

```
┌─────────────────────────┐
│  Azure DevOps Pipeline  │
│   (Scheduled/Manual)    │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────────────────────────────┐
│  azure-storage-cost-analyzer.sh        │
│  ─────────────────────────────────────────────  │
│  1. Scan all Azure subscriptions                │
│  2. Collect unattached disks & snapshots        │
│  3. Query Azure Cost Management API             │
│  4. Aggregate metrics (JSON format)             │
│  5. Send to Zabbix via zabbix_sender            │
└────────────┬────────────────────────────────────┘
             │
             ▼
    ┌────────────────┐
    │ Zabbix Server  │
    │   (7.0.5+)     │
    │                │
    │  ┌──────────┐  │
    │  │ Template │  │
    │  │  Items   │  │
    │  │ Triggers │  │
    │  │   LLD    │  │
    │  └──────────┘  │
    └────────┬───────┘
             │
             ▼
    ┌────────────────┐
    │   Dashboards   │
    │     Alerts     │
    │    Reports     │
    └────────────────┘
```

---

## Prerequisites

### 1. Zabbix Server Requirements

- **Zabbix version**: 7.0.5 or higher
- **Zabbix Trapper port**: 10051 (default) open and accessible from Azure DevOps agents
- **Template imported**: `zabbix-template-azure-storage-monitor-7.0.xml`
- **Host created**: `azure-storage-monitor` (or custom name)

### 2. Azure DevOps Requirements

- **Azure CLI**: Installed on DevOps agents (usually pre-installed)
- **Service Principal**: With Reader access to all subscriptions
- **zabbix_sender**: Must be available on agents (see [Installing zabbix_sender](#installing-zabbix_sender))
- **Network access**: Agents can reach Zabbix server on port 10051

### 3. Script Requirements

- **Bash**: Version 3.2+ (default on Linux/macOS)
- **jq**: JSON processor (for parsing)
- **bc**: Calculator (for cost aggregation)

---

## Zabbix Server Setup

### Step 1: Import Template

1. Log in to Zabbix frontend
2. Navigate to: **Configuration** → **Templates**
3. Click **Import**
4. Upload `zabbix-template-azure-storage-monitor-7.0.xml`
5. Click **Import**

### Step 2: Create Host

1. Navigate to: **Configuration** → **Hosts**
2. Click **Create host**
3. Configure:
   - **Host name**: `azure-storage-monitor` (must match `--zabbix-host` parameter)
   - **Templates**: Link "Azure Storage Cost Monitor" template
   - **Interfaces**: Add Trapper interface (port 10051)
   - **Groups**: Add to appropriate host group (e.g., "Cloud/Azure")

### Step 3: Verify Items

After importing, verify these items exist:

**Aggregated Items:**
- `azure.storage.all.total_waste.monthly` - Total waste across all subscriptions
- `azure.storage.all.total_disks` - Total unattached disks
- `azure.storage.all.total_snapshots` - Total snapshots
- `azure.storage.all.subscriptions_scanned` - Number of subscriptions scanned

**Script Health Items:**
- `azure.storage.script.last_run_timestamp` - Last execution timestamp
- `azure.storage.script.execution_time_seconds` - Script duration
- `azure.storage.script.last_run_status` - Execution status (0=success, 1=warning, 2=error)

**Discovery Rule:**
- `azure.storage.discovery.subscriptions` - Discovers Azure subscriptions

### Step 4: Configure Triggers

Default triggers (can be customized):

| Trigger | Severity | Threshold |
|---------|----------|-----------|
| High total waste | Warning | $500/month |
| Critical total waste | High | $1000/month |
| Script hasn't run | Average | 24 hours |
| Per-subscription high waste | Warning | $100/month |
| Per-subscription critical waste | High | $250/month |
| Many unattached disks | Warning | 20+ disks |

---

## Azure DevOps Pipeline Integration

### Installing zabbix_sender

Your Azure DevOps agents need `zabbix_sender` installed. Add this to your pipeline:

```yaml
# For Ubuntu agents
- task: Bash@3
  displayName: 'Install zabbix-sender'
  inputs:
    targetType: 'inline'
    script: |
      sudo apt-get update
      sudo apt-get install -y zabbix-sender jq bc
```

### Pipeline YAML Example

Create `azure-pipelines-storage-monitor.yml`:

```yaml
trigger: none  # Manual or scheduled only

schedules:
  - cron: "0 2 * * *"  # Daily at 2 AM UTC
    displayName: Daily Storage Cost Analysis
    branches:
      include:
        - master
    always: true  # Run even if no code changes

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: zabbix-rs-credentials  # Variable group with ZABBIX_SERVER
  - name: ZABBIX_HOST
    value: 'azure-storage-monitor'
  - name: SCAN_DAYS
    value: 30

steps:
  - checkout: self
    displayName: 'Checkout repository'

  - task: Bash@3
    displayName: 'Install dependencies'
    inputs:
      targetType: 'inline'
      script: |
        sudo apt-get update -qq
        sudo apt-get install -y zabbix-sender jq bc coreutils

  - task: AzureCLI@2
    displayName: 'Run Azure Storage Cost Analysis'
    inputs:
      azureSubscription: 'Azure-Service-Connection'  # Your service connection
      scriptType: 'bash'
      scriptLocation: 'scriptPath'
      scriptPath: '$(Build.Repository.LocalPath)/azure-storage-cost-analyzer.sh'
      arguments: |
        unused-report \
        --subscriptions all \
        --days $(SCAN_DAYS) \
        --output-format json \
        --zabbix-send \
        --zabbix-server $(ZABBIX_SERVER) \
        --zabbix-host $(ZABBIX_HOST) \
        --quiet
      workingDirectory: '$(Build.Repository.LocalPath)'

  - task: PublishBuildArtifacts@1
    displayName: 'Publish JSON Report'
    condition: always()
    inputs:
      PathtoPublish: '$(Build.Repository.LocalPath)/*.json'
      ArtifactName: 'storage-cost-reports'
```

### Variable Group Setup

1. In Azure DevOps, navigate to **Pipelines** → **Library**
2. Create variable group: `zabbix-rs-credentials`
3. Add variable:
   - **Name**: `ZABBIX_SERVER`
   - **Value**: `your-zabbix-server.company.com`
   - **Secret**: ☐ (not needed, it's just a hostname)

### Service Principal Setup

Your Azure service connection needs **Reader** role on all subscriptions:

```bash
# Grant Reader access to all subscriptions
az role assignment create \
  --assignee <service-principal-app-id> \
  --role "Reader" \
  --scope "/subscriptions/<subscription-id>"
```

Repeat for each subscription or use management group scope.

---

## Manual Execution

### Basic Command

```bash
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --output-format json \
  --zabbix-send \
  --zabbix-server monitoring.company.com \
  --zabbix-host azure-storage-monitor
```

### Scan Specific Subscriptions

```bash
# Comma-separated list
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions "sub-1-id,sub-2-id,sub-3-id" \
  --days 30 \
  --zabbix-send \
  --zabbix-server monitoring.company.com \
  --zabbix-host azure-storage-monitor
```

### Using Config File

Create `/etc/azure-storage-monitor/config.conf`:

```ini
[azure]
subscriptions = all
date_range_days = 30

[output]
format = json
verbosity = quiet

[zabbix]
enabled = true
server = monitoring.company.com
port = 10051
hostname = azure-storage-monitor
auto_send = true
```

Then run:

```bash
./azure-storage-cost-analyzer.sh unused-report \
  --config /etc/azure-storage-monitor/config.conf
```

### Dry Run (No Zabbix Send)

```bash
# See JSON output without sending to Zabbix
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --output-format json
```

---

## Metrics Reference

### Aggregated Metrics

| Metric Key | Type | Unit | Description |
|------------|------|------|-------------|
| `azure.storage.all.total_waste.monthly` | Float | USD | Total monthly cost (disks + snapshots) |
| `azure.storage.all.total_disks` | Unsigned | disks | Number of unattached disks |
| `azure.storage.all.total_snapshots` | Unsigned | snapshots | Number of snapshots |
| `azure.storage.all.subscriptions_scanned` | Unsigned | count | Subscriptions scanned |

### Per-Subscription Metrics (LLD)

| Metric Key | Type | Unit | Description |
|------------|------|------|-------------|
| `azure.storage.subscription[{#SUBSCRIPTION_ID}].waste_monthly` | Float | USD | Monthly waste for this subscription |
| `azure.storage.subscription[{#SUBSCRIPTION_ID}].disk_count` | Unsigned | disks | Unattached disks in this subscription |
| `azure.storage.subscription[{#SUBSCRIPTION_ID}].snapshot_count` | Unsigned | snapshots | Snapshots in this subscription |

### Script Health Metrics

| Metric Key | Type | Unit | Description |
|------------|------|------|-------------|
| `azure.storage.script.last_run_timestamp` | Unsigned | unixtime | Last successful execution |
| `azure.storage.script.execution_time_seconds` | Unsigned | seconds | Script duration |
| `azure.storage.script.last_run_status` | Unsigned | enum | 0=success, 1=warning, 2=error |

### Example JSON Output

```json
{
  "version": "1.0",
  "timestamp": "2025-11-20T14:30:00Z",
  "scan_type": "multi-subscription",
  "execution": {
    "start_time": "2025-11-20T14:30:00Z",
    "end_time": "2025-11-20T14:32:15Z",
    "duration_seconds": 135,
    "status": "success"
  },
  "subscriptions_scanned": 3,
  "subscriptions_successful": 3,
  "subscriptions_failed": 0,
  "aggregated_metrics": {
    "total_unattached_disks": 12,
    "total_unattached_size_gb": 2400,
    "total_unattached_cost_monthly": 45.60,
    "total_snapshots": 89,
    "total_snapshots_size_gb": 15600,
    "total_snapshots_cost_monthly": 234.50,
    "total_waste_monthly_usd": 280.10,
    "total_waste_annual_usd": 3361.20
  },
  "by_subscription": [...]
}
```

---

## Troubleshooting

### Issue: zabbix_sender not found

**Error:** `ERROR: zabbix_sender not found in PATH`

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install zabbix-sender

# RHEL/CentOS
sudo yum install zabbix-sender

# macOS
brew install zabbix
```

### Issue: Connection to Zabbix failed

**Error:** `Failed to send metrics to Zabbix`

**Check:**
1. Zabbix server hostname is correct
2. Port 10051 is reachable from agent:
   ```bash
   telnet your-zabbix-server.com 10051
   ```
3. Firewall allows outbound connections to port 10051

### Issue: No data in Zabbix

**Check:**
1. Host `azure-storage-monitor` exists in Zabbix
2. Template is linked to host
3. Items are enabled (not disabled)
4. Check Zabbix server logs:
   ```bash
   tail -f /var/log/zabbix/zabbix_server.log | grep azure-storage
   ```

### Issue: Permission denied accessing subscriptions

**Error:** `AuthorizationFailed` when querying Azure

**Solution:**
Grant Reader role to service principal:
```bash
az role assignment create \
  --assignee <app-id> \
  --role "Reader" \
  --scope "/subscriptions/<subscription-id>"
```

### Issue: Script timeout in Azure DevOps

**Error:** Pipeline times out

**Solution:**
Increase timeout or reduce scope:
```yaml
- task: AzureCLI@2
  timeoutInMinutes: 30  # Increase from default 60
  inputs:
    arguments: |
      unused-report \
      --days 7 \  # Reduce from 30 to 7 days
      --subscriptions "specific-sub-id"  # Target specific subscription
```

### Debug Mode

Enable verbose logging:

```bash
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --verbose \  # Add verbose flag
  --zabbix-send \
  --zabbix-server monitoring.company.com \
  --zabbix-host azure-storage-monitor
```

### Validate Metrics Manually

Send test metric to Zabbix:

```bash
echo "azure-storage-monitor azure.storage.all.total_waste.monthly $(date +%s) 123.45" | \
  zabbix_sender -z your-zabbix-server.com -p 10051 -i -
```

Check if received in Zabbix: **Monitoring** → **Latest data** → Filter by host

---

## Support

For issues or questions:

1. Check script help: `./azure-storage-cost-analyzer.sh --help`
2. Review test results: `TEST_RESULTS.md`
3. Check PRD: `PRD_Zabbix_Implementation.md`
4. Contact: DevOps Team

---

## Appendix: All Command-Line Options

```
--subscriptions <list>          Scan comma-separated subscription IDs or 'all'
--subscriptions-file <path>     Load subscription IDs from file
--exclude-subscriptions <list>  Exclude specific subscriptions
--days <N>                      Analyze last N days
--last-month                    Analyze previous month
--current-month                 Analyze current month
--output-format <fmt>           Output format: text|json|zabbix
--zabbix-send                   Enable automatic sending to Zabbix
--zabbix-server <host>          Zabbix server hostname
--zabbix-port <port>            Zabbix server port (default: 10051)
--zabbix-host <name>            Zabbix host name for metrics
--zabbix-config <path>          Use zabbix_agentd.conf
--quiet                         Minimal output
--silent                        No output (errors only)
--verbose                       Debug output
--config <path>                 Configuration file path
```

---

**End of Guide**
