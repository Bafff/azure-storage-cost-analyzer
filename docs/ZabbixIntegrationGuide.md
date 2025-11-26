# Zabbix Integration Guide - Azure Storage Cost Monitor

**Version:** 2.0
**Zabbix Version:** 7.0.5+
**Script:** `azure-storage-cost-analyzer.sh`
**Last Updated:** 2025-11-26

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
- **Aggregate metrics**: Total waste, disk counts, and snapshot counts across all subscriptions
- **Cost alerting**: Warning ($500/month) and critical ($1000/month) thresholds
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
- **Template imported**: `templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml`
- **Host created**: `azure-storage-cost-analyzer` (or custom name)

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
4. Upload `templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml`
5. Click **Import**

### Step 2: Create Host

1. Navigate to: **Configuration** → **Hosts**
2. Click **Create host**
3. Configure:
   - **Host name**: `azure-storage-cost-analyzer` (must match `--zabbix-host` parameter)
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
- `azure.storage.all.invalid_tags` - Resources with malformed tags
- `azure.storage.all.excluded_pending_review` - Resources pending review
- `azure.storage.all.resource_details` - **TEXT** item showing (in order): invalid tags, disks, snapshots

**Script Health Items:**
- `azure.storage.script.last_run_timestamp` - Last execution timestamp
- `azure.storage.script.execution_time_seconds` - Script duration
- `azure.storage.script.last_run_status` - Execution status (0=success, 1=warning, 2=error)

### Step 4: Configure Macros

Template macros allow you to customize thresholds without modifying triggers:

| Macro | Default | Description |
|-------|---------|-------------|
| `{$DISK_THRESHOLD}` | 0 | Alert when unattached disk count exceeds this value |
| `{$SNAPSHOT_THRESHOLD}` | 0 | Alert when snapshot count exceeds this value |
| `{$WASTE_WARNING_THRESHOLD}` | 100 | Warning threshold for monthly waste (USD) |
| `{$WASTE_CRITICAL_THRESHOLD}` | 200 | Critical threshold for monthly waste (USD) |

To customize thresholds per-host:
1. Navigate to: **Configuration** → **Hosts**
2. Click on your host
3. Go to **Macros** tab
4. Override macro values as needed

### Step 5: Configure Triggers

Default triggers (thresholds controlled by macros):

| Trigger | Severity | Default Threshold |
|---------|----------|-------------------|
| Unattached disks detected | Warning | > 0 disks (`{$DISK_THRESHOLD}`) |
| No disk data received | Average | No data for 25 hours |
| Snapshots detected | Warning | > 0 snapshots (`{$SNAPSHOT_THRESHOLD}`) |
| High total waste | Warning | > $100/month (`{$WASTE_WARNING_THRESHOLD}`) |
| Critical total waste | Average | > $200/month (`{$WASTE_CRITICAL_THRESHOLD}`) |
| Invalid review tags | Warning | Any invalid tags |
| Script hasn't run | Average | 24 hours |
| Script execution failed | Warning | Status > 0 |

### Trigger Links and Resource Details

The following triggers include a **"Check Resource details"** link that navigates directly to the Resource Details item in Latest Data:

- **Unattached disks detected** - Click link to see disk names, resource groups, and sizes
- **Snapshots detected** - Click link to see snapshot names, resource groups, and sizes
- **Invalid review tags detected** - Click link to identify resources with malformed tags

When a trigger fires:
1. Open the trigger in Zabbix (**Monitoring** → **Problems**)
2. Click the **"Check Resource details"** link in the trigger's Links section
3. View the `Resource Details` item to see affected resources
4. Take action based on the resource list (delete, attach, fix tags, etc.)

### Best Practices: Adding Trigger URL Links

When adding URL links to Zabbix triggers that reference other items, follow these guidelines:

**URL Format for Zabbix 7.0+:**
```
/zabbix.php?action=latest.view&hostids[]={HOST.ID}&name=<Item Display Name>&filter_set=1
```

**Key points:**
- Use `hostids[]` (not `filter_hostids[]`) for host filtering
- Use `name=` with the **item's display name** (not the key), URL-encoded
- Example: `name=Resource%20Details` (not `name=resource_details`)
- Add `filter_set=1` to apply the filter immediately
- Use `url_name` property to set a descriptive link label (e.g., "Check Resource details")

**Template YAML example:**
```yaml
triggers:
- uuid: abc123...
  expression: last(/Template Name/item.key)>0
  name: 'Alert: {ITEM.LASTVALUE}'
  url: '/zabbix.php?action=latest.view&hostids[]={HOST.ID}&name=Resource%20Details&filter_set=1'
  url_name: Check Resource details
```

**Limitations:**
- The `{ITEM.ID}` macro refers to the triggering item, not other items
- Cannot dynamically link to `history.php?itemids[]=XXX` for a different item
- Use Latest Data filtering by item name as the workaround

### Trigger Design Checklist

When creating or updating triggers, ensure each trigger includes:

- [ ] **Clear action items** - Tell users what to do (delete, fix, tag, etc.)
- [ ] **Link to supporting data** - Use `url` + `url_name` to link to related items
- [ ] **Reference the link in description** - Point users to the clickable link (`{HOST.ID}` doesn't expand in descriptions)
- [ ] **Helper item reference** - If a TEXT item contains details, reference it in the trigger

**Example trigger description structure:**
```
{ITEM.LASTVALUE} issue(s) detected.

Click "Check Resource details" link above, or go to Monitoring → Latest data → filter by "Resource Details".

Action: [Specific steps to resolve the issue]
```

**Note:** `{HOST.ID}` macro is not expanded in description text, so use the trigger's URL link instead of embedding URLs in descriptions.

---

## Local Development with Docker Compose

Use the provided Docker Compose setup to test Zabbix integration locally before deploying to production. This enables faster iteration and catches issues early.

### Quick Start

```bash
# Start Zabbix stack
cd tests
docker compose up -d

# Wait for services (takes ~60 seconds)
docker ps --format '{{.Names}}: {{.Status}}' | grep zabbix

# Access Zabbix UI
open http://localhost:8080
# Login: Admin / zabbix
```

### Testing Workflow

1. **Import template:**
   ```bash
   # Use Zabbix API or UI to import
   # templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml
   ```

2. **Create test host** named `azure-storage-cost-analyzer`

3. **Send test data:**
   ```bash
   # Create test batch file
   cat > /tmp/test_batch.txt << 'EOF'
   azure-storage-cost-analyzer azure.storage.all.total_disks 5
   azure-storage-cost-analyzer azure.storage.all.total_snapshots 10
   azure-storage-cost-analyzer azure.storage.all.invalid_tags 2
   azure-storage-cost-analyzer azure.storage.all.resource_details "[INVALID TAG] test-disk | test-rg | Tag: bad-date\nDISK | disk-1 | rg-1 | Sub-1 | 30GB"
   EOF

   # Send to local Zabbix
   zabbix_sender -z localhost -p 10051 -i /tmp/test_batch.txt -vv
   ```

4. **Verify in UI:**
   - Check **Monitoring → Latest data** for received values
   - Check **Monitoring → Problems** for triggered alerts
   - Test trigger URL links work correctly

### Cleanup

```bash
cd tests
docker compose down -v  # -v removes volumes
```

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

### Agent Pool Options (self-hosted vs hosted)

- **Repository default:** The shipped pipeline YAML uses a self-hosted Linux pool so you control outbound access to Zabbix. Change `pool.name` to the name of your pool; keep the `Agent.OS -equals Linux` demand.
- **Self-hosted requirements:** Agent must reach your Zabbix server on port 10051 and be able to install or already have `zabbix-sender`, `jq`, `bc`, and `coreutils` available (via `sudo apt-get` or preinstall).
- **Hosted option:** If your Zabbix endpoint is internet-accessible, you can switch to Microsoft-hosted agents by replacing the `pool` block with `vmImage: 'ubuntu-latest'`.

### Pipeline YAML Example

Create `.pipelines/azure-pipelines-storage-cost-analyzer.yml`:

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
  name: '<your-self-hosted-linux-pool>'  # Update to your pool name
  demands:
    - Agent.OS -equals Linux
# Hosted alternative:
# pool:
#   vmImage: 'ubuntu-latest'

variables:
  - group: zabbix-rs-credentials  # Variable group with ZABBIX_SERVER
  - name: ZABBIX_HOST
    value: 'azure-storage-cost-analyzer'
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
  --zabbix-host azure-storage-cost-analyzer
```

### Scan Specific Subscriptions

```bash
# Comma-separated list
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions "sub-1-id,sub-2-id,sub-3-id" \
  --days 30 \
  --zabbix-send \
  --zabbix-server monitoring.company.com \
  --zabbix-host azure-storage-cost-analyzer
```

### Using Config File

Create `/etc/azure-storage-cost-analyzer/config.conf`:

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
hostname = azure-storage-cost-analyzer
auto_send = true
```

Then run:

```bash
./azure-storage-cost-analyzer.sh unused-report \
  --config /etc/azure-storage-cost-analyzer/config.conf
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
| `azure.storage.all.invalid_tags` | Unsigned | tags | Resources with malformed tags |
| `azure.storage.all.excluded_pending_review` | Unsigned | resources | Resources pending review |

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
1. Host `azure-storage-cost-analyzer` exists in Zabbix
2. Template is linked to host
3. Items are enabled (not disabled)
4. Check Zabbix server logs:
   ```bash
   tail -f /var/log/zabbix/zabbix_server.log | grep azure-storage
   ```

### Issue: Items show "Not supported" with type mismatch error

**Error:** `Value of type "string" is not suitable for value type "Numeric (unsigned)"`

This happens when corrupted data (e.g., with timestamps in value field) was sent to items.

**Solution:**
1. In Zabbix: **Data collection** → **Hosts** → `azure-storage-cost-analyzer` → **Items**
2. Select affected items
3. Click **Mass update** → **Clear history and trends**
4. Or recreate the host from scratch

**Prevention:** Always use format `hostname key value` without timestamps.

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
  --zabbix-host azure-storage-cost-analyzer
```

### Validate Metrics Manually

Send test metric to Zabbix:

```bash
# Single metric (no timestamp - Zabbix uses current time)
zabbix_sender -z your-zabbix-server.com -p 10051 \
  -s "azure-storage-cost-analyzer" \
  -k "azure.storage.all.total_waste.monthly" \
  -o "123.45"

# Batch file format (hostname key value - NO timestamps)
cat > /tmp/test_batch.txt << 'EOF'
azure-storage-cost-analyzer azure.storage.all.total_waste.monthly 123.45
azure-storage-cost-analyzer azure.storage.all.total_disks 5
EOF
zabbix_sender -z your-zabbix-server.com -p 10051 -i /tmp/test_batch.txt
```

> **Important:** Do NOT use timestamps in batch files. The format is `hostname key value` only.
> Using `-T` flag with timestamps can cause data to be silently ignored.

Check if received in Zabbix: **Monitoring** → **Latest data** → Filter by host

---

## Support

For issues or questions:

1. Check script help: `./azure-storage-cost-analyzer.sh --help`
2. Check PRD: `docs/PrdZabbixImplementation.md`
3. Contact: DevOps Team

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
