# Product Requirements Document: Zabbix Integration for Azure Storage Cost Analysis

**Document Version:** 1.0
**Date:** 2025-10-22
**Author:** DevOps Team
**Status:** Draft

> **Note (2025-11):** LLD (Low-Level Discovery) described in this PRD was later simplified.
> The current implementation uses aggregate metrics only (no per-subscription discovery).
> See `docs/ZabbixIntegrationGuide.md` for current implementation details.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Objectives](#goals--objectives)
4. [Current State Analysis](#current-state-analysis)
5. [Requirements](#requirements)
   - [Phase 1: Core Monitoring Foundation](#phase-1-core-monitoring-foundation-mvp)
   - [Phase 2: Zabbix Integration](#phase-2-zabbix-integration)
   - [Phase 3: Multi-Subscription Support](#phase-3-multi-subscription-support)
   - [Phase 4: Production Hardening](#phase-4-production-hardening)
6. [Technical Architecture](#technical-architecture)
7. [Zabbix Integration Details](#zabbix-integration-details)
8. [Exit Codes & Error Handling](#exit-codes--error-handling)
9. [Configuration Management](#configuration-management)
10. [Deployment & Operations](#deployment--operations)
11. [Success Metrics](#success-metrics)
12. [Timeline & Phases](#timeline--phases)
13. [Risks & Mitigations](#risks--mitigations)
14. [Appendix](#appendix)

---

## Executive Summary

This PRD outlines the transformation of the Azure Storage Cost Analysis script from an interactive reporting tool into a production-ready monitoring solution integrated with Zabbix. The implementation will enable automated, unattended monitoring of Azure storage waste across multiple subscriptions with alerting capabilities.

**Key Deliverables:**
- Machine-readable output formats (JSON, Zabbix)
- Unattended execution mode (silent, exit codes)
- Zabbix sender integration with LLD support
- Multi-subscription scanning capability
- Configuration-driven operation
- Production-grade logging and error handling

---

## Problem Statement

### Current Limitations

The existing script (`azure-storage-cost-analyzer.sh`) is designed for **interactive use** with the following limitations:

1. **No Automation Support**
   - Human-readable output only (ASCII tables)
   - Verbose progress messages to stderr
   - No machine-readable formats

2. **No Monitoring Integration**
   - No Zabbix integration
   - No metrics export
   - No alerting capabilities

3. **Single Subscription Only**
   - Cannot scan multiple Azure subscriptions in one run
   - Manual process to analyze each subscription

4. **No Configuration Management**
   - Hardcoded defaults
   - Command-line only configuration
   - No centralized config file

5. **Limited Error Handling**
   - Basic exit codes only
   - No threshold-based alerting
   - No structured logging

### Business Impact

- **Manual Overhead:** DevOps team must manually run reports for each subscription
- **Delayed Detection:** Waste detection depends on manual checks
- **No Proactive Alerting:** Cannot alert when waste exceeds thresholds
- **Limited Visibility:** No historical trending or dashboards
- **Scale Limitations:** Time-consuming to analyze multiple subscriptions

---

## Goals & Objectives

### Primary Goals

1. **Enable Unattended Monitoring**
   - Run automatically via cron/scheduled tasks
   - Zero manual intervention required
   - Reliable exit codes for automation

2. **Zabbix Integration**
   - Send metrics to Zabbix server
   - Support Low-Level Discovery (LLD)
   - Enable alerting on cost thresholds

3. **Multi-Subscription Support**
   - Scan all Azure subscriptions in single run
   - Aggregate metrics across subscriptions
   - Per-subscription and total reporting

4. **Production Readiness**
   - Robust error handling
   - Structured logging
   - Configuration-driven operation

### Success Criteria

- [ ] Script runs unattended in cron without errors
- [ ] Metrics appear in Zabbix within 5 minutes of execution
- [ ] Alerts trigger when waste exceeds defined thresholds
- [ ] All Azure subscriptions scanned automatically
- [ ] Zero manual configuration per run
- [ ] 99.9% successful execution rate

---

## Current State Analysis

### Script Capabilities (As of 2025-10-22)

✅ **Implemented:**
- Azure Resource Graph API integration (fast queries)
- Cost Management API integration
- Batch processing (100 resources per batch)
- Multiple sorting options (size, RG, date)
- Dynamic column widths
- Resource group filtering
- Include/exclude attached disks

✅ **Now Implemented (as of Nov 2025):**
- Machine-readable output formats (JSON via `--output-format json`)
- Zabbix integration (`--zabbix-send`, templates in `templates/`)
- Multi-subscription support (`--subscriptions all`)
- Configuration files (`azure-storage-cost-analyzer.conf`)
- Automatic date range calculation (`--days N`, `--last-month`)
- Threshold-based alerting (Zabbix triggers)
- Tag-based exclusion (`--skip-tagged`)
- Resource Group exclusion (`--exclude-rgs`)
- macOS compatibility (bash 3.2+)

❌ **Not Yet Implemented:**
- Silent/quiet execution mode
- Structured logging

### Current Output Format

```
=== AZURE UNUSED RESOURCES COST ANALYSIS REPORT ===
Generated: Wed Oct 22 07:12:32 WEST 2025
Subscription: 2f929c0a-d1f4-480c-a610-f75d1862fd53
...
Disk Name                                | Size GB  | SKU             | ...
---------------------------------------- | -------- | --------------- | ...
pvc-ef3fc2dc-b478-4687-acd5-613b206124f5 | 8        | StandardSSD_LRS | ...
```

**Issues for Monitoring:**
- Not parseable by monitoring tools
- Mixed with progress messages
- No structured data format

---

## Requirements

## Phase 1: Core Monitoring Foundation (MVP)

### 1.1 Machine-Readable Output Formats

**Priority:** P0 (Critical)

**Requirement:**
Support multiple output formats for different use cases.

**Acceptance Criteria:**

```bash
# Command-line flags
--output-format <format>     # json|zabbix|text

# Behaviors
--output-format json         # Pure JSON output, no extra text
--output-format zabbix       # Zabbix sender format
--output-format text         # Current human-readable format (default)
```

**JSON Output Schema:**

```json
{
  "version": "1.0",
  "timestamp": "2025-10-22T07:00:00Z",
  "execution": {
    "start_time": "2025-10-22T07:00:00Z",
    "end_time": "2025-10-22T07:00:15Z",
    "duration_seconds": 15,
    "status": "success"
  },
  "subscription": {
    "id": "2f929c0a-d1f4-480c-a610-f75d1862fd53",
    "name": "Production Subscription"
  },
  "analysis_period": {
    "start_date": "2025-10-01T00:00:00Z",
    "end_date": "2025-10-22T23:59:59Z",
    "days": 21
  },
  "metrics": {
    "unattached_disks": {
      "count": 12,
      "total_size_gb": 552,
      "total_cost_monthly_usd": 37.66,
      "total_cost_annual_usd": 451.92,
      "by_resource_group": {
        "mc_testing-aks-rg_testing-aks_centralus": {
          "count": 8,
          "size_gb": 352,
          "cost_monthly_usd": 25.00
        },
        "mc_airflow-data-aks-rg_airflow-data-aks_centralus": {
          "count": 4,
          "size_gb": 200,
          "cost_monthly_usd": 12.66
        }
      }
    },
    "snapshots": {
      "count": 98,
      "total_size_gb": 5300,
      "total_cost_monthly_usd": 0.97,
      "total_cost_annual_usd": 11.64
    },
    "total_waste": {
      "monthly_usd": 38.63,
      "annual_usd": 463.56
    }
  },
  "items": {
    "disks": [
      {
        "name": "pvc-ef3fc2dc-b478-4687-acd5-613b206124f5",
        "id": "/subscriptions/.../disks/pvc-ef3fc2dc...",
        "resource_group": "mc_airflow-data-aks-rg_airflow-data-aks_centralus",
        "size_gb": 8,
        "sku": "StandardSSD_LRS",
        "tier": "Standard",
        "state": "Unattached",
        "created": "2025-08-04",
        "age_days": 79,
        "cost_monthly_usd": 1.67,
        "cost_annual_usd": 20.04
      }
    ],
    "snapshots": [
      {
        "name": "snapshot-0535036c-9d80-498f-a4c5-5e99cd1ec88c",
        "id": "/subscriptions/.../snapshots/snapshot-0535036c...",
        "resource_group": "backup-rg",
        "size_gb": 8,
        "sku": "Standard_ZRS",
        "created": "2025-02-05",
        "age_days": 259,
        "cost_monthly_usd": 0.01
      }
    ]
  }
}
```

**Zabbix Sender Format:**

```
# Format: <hostname> <key> <timestamp> <value>
azure-monitor azure.storage.unattached.disks.count 1729580400 12
azure-monitor azure.storage.unattached.disks.size_gb 1729580400 552
azure-monitor azure.storage.unattached.disks.cost_monthly 1729580400 37.66
azure-monitor azure.storage.snapshots.count 1729580400 98
azure-monitor azure.storage.total_waste.monthly 1729580400 38.63
```

---

### 1.2 Silent/Quiet Execution Mode

**Priority:** P0 (Critical)

**Requirement:**
Support unattended execution without terminal output pollution.

**Acceptance Criteria:**

```bash
--quiet           # Minimal output (errors only to stderr)
--silent          # Zero output (exit codes only)
--verbose         # Current behavior (default)
--debug           # Extra debugging information

# Example behaviors:

# Quiet mode (only critical errors)
$ ./script.sh --quiet --output-format json > output.json
# stderr: only errors if any occur
# stdout: JSON output only

# Silent mode (nothing)
$ ./script.sh --silent --zabbix-send
# stderr: empty
# stdout: empty
# exit code: indicates status
```

**Implementation:**
- All progress messages (`echo "Sorting disks..." >&2`) respect quiet flag
- Only structured output goes to stdout
- Errors always go to stderr (even in silent mode for logging)

---

### 1.3 Exit Codes

**Priority:** P0 (Critical)

**Requirement:**
Standardized exit codes for automation and monitoring.

**Exit Code Table:**

| Code | Meaning | Description | Action |
|------|---------|-------------|--------|
| 0 | Success | Analysis completed, no issues | Continue |
| 1 | General Error | Unexpected error occurred | Alert ops team |
| 2 | Authentication Failed | Azure login failed | Check credentials |
| 3 | API Rate Limit | Azure API throttling | Retry with backoff |
| 4 | Invalid Arguments | Command-line args invalid | Fix invocation |
| 5 | Configuration Error | Config file invalid/missing | Fix configuration |
| 10 | Warning Threshold | Waste > warning threshold | Minor alert |
| 11 | Critical Threshold | Waste > critical threshold | Major alert |
| 20 | No Data | No resources found (might be OK) | Informational |
| 21 | Partial Failure | Some subscriptions failed | Check logs |

**Usage in Monitoring:**

```bash
# In cron:
./script.sh --config /etc/azure-monitor/config.conf
EXIT_CODE=$?

case $EXIT_CODE in
  0)  logger "Azure storage analysis: OK" ;;
  10) logger "Azure storage analysis: WARNING - waste threshold exceeded" ;;
  11) logger "Azure storage analysis: CRITICAL - high waste detected" ;;
  *)  logger "Azure storage analysis: ERROR - exit code $EXIT_CODE" ;;
esac
```

---

### 1.4 Automatic Date Range Calculation

**Priority:** P0 (Critical)

**Requirement:**
Eliminate manual date input for automation.

**Acceptance Criteria:**

```bash
# New flags:
--days <N>                   # Last N days (default: 30)
--last-month                 # Previous calendar month
--current-month              # Current calendar month to date
--last-week                  # Previous 7 days
--yesterday                  # Previous day only

# Still support manual dates:
--date-range <start> <end>   # ISO format

# Examples:
./script.sh unused-report --days 7        # Last 7 days
./script.sh unused-report --last-month    # Sept 1-30 if run in Oct
./script.sh unused-report --current-month # Oct 1 to today
```

**Date Calculation Logic:**

```bash
# Automatic date range
calculate_date_range() {
    local range_type="$1"

    case "$range_type" in
        days)
            END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
            START_DATE=$(date -u -d "$DAYS days ago" +"%Y-%m-%dT%H:%M:%S+00:00")
            ;;
        last-month)
            START_DATE=$(date -u -d "first day of last month" +"%Y-%m-01T00:00:00+00:00")
            END_DATE=$(date -u -d "last day of last month" +"%Y-%m-%dT23:59:59+00:00")
            ;;
        current-month)
            START_DATE=$(date -u +"%Y-%m-01T00:00:00+00:00")
            END_DATE=$(date -u +"%Y-%m-%dT23:59:59+00:00")
            ;;
    esac
}
```

---

### 1.5 Configuration File Support

**Priority:** P0 (Critical)

**Requirement:**
Centralized configuration management.

**Configuration File Location (Priority Order):**

1. `--config <path>` (command-line override)
2. `/etc/azure-storage-cost-analyzer/config.conf` (system-wide)
3. `~/.azure-storage-cost-analyzer.conf` (user-specific)
4. `./azure-storage-cost-analyzer.conf` (local directory)

**Configuration File Format (INI-style):**

```ini
# /etc/azure-storage-cost-analyzer/config.conf

[azure]
# Azure subscriptions to scan
# Comma-separated list of subscription IDs, or "all" for all accessible subscriptions
subscriptions = all
# Alternative: specific list
# subscriptions = 2f929c0a-d1f4-480c-a610-f75d1862fd53, 03d76f78-4676-4116-b53a-162546996207

# Resource group filter (optional, empty = all)
resource_group =

# Date range for cost analysis
date_range_days = 30

# Include attached disks in analysis
include_attached = false

[output]
# Output format: json, zabbix, text
format = json

# Output file path (if saving to file)
# Use strftime format codes: %Y, %m, %d, %H, %M, %S
file_path = /var/log/azure-monitor/report-%Y%m%d-%H%M%S.json

# Verbosity: silent, quiet, normal, verbose, debug
verbosity = quiet

[zabbix]
# Enable Zabbix integration
enabled = true

# Zabbix server configuration
server = monitoring.company.com
port = 10051
hostname = azure-storage-cost-analyzer

# Auto-send metrics to Zabbix
auto_send = true

# Zabbix agentd config file (alternative to server/port)
# config_file = /etc/zabbix/zabbix_agentd.conf

[thresholds]
# Warning threshold (monthly cost in USD)
warning_monthly = 50.00

# Critical threshold (monthly cost in USD)
critical_monthly = 100.00

# Alert on count thresholds
warning_disk_count = 10
critical_disk_count = 20

[logging]
# Log file path
file = /var/log/azure-monitor/azure-storage-cost-analyzer.log

# Log level: debug, info, warn, error
level = info

# Enable syslog
syslog = false

# Syslog facility
syslog_facility = local0

[advanced]
# Retry count for failed API calls
retry_count = 3

# Retry delay in seconds
retry_delay = 5

# Sort order: size, rg, date
sort_by = size
```

**Configuration Precedence:**

```
Command-line flags > Config file > Environment variables > Defaults
```

---

## Phase 2: Zabbix Integration

### 2.1 Zabbix Sender Integration

**Priority:** P0 (Critical)

**Requirement:**
Send metrics to Zabbix server using zabbix_sender.

**Acceptance Criteria:**

```bash
# Send metrics to Zabbix
./script.sh unused-report \
    --days 7 \
    --output-format zabbix \
    --zabbix-send \
    --zabbix-server monitoring.company.com \
    --zabbix-host azure-storage-cost-analyzer

# Or use config file:
./script.sh unused-report --config /etc/azure-monitor/config.conf
```

**Zabbix Item Keys:**

```
# Primary metrics (single subscription)
azure.storage.unattached.disks.count
azure.storage.unattached.disks.size_gb
azure.storage.unattached.disks.cost_monthly
azure.storage.unattached.disks.cost_annual

azure.storage.snapshots.count
azure.storage.snapshots.size_gb
azure.storage.snapshots.cost_monthly
azure.storage.snapshots.cost_annual

azure.storage.total_waste.monthly
azure.storage.total_waste.annual

# Script execution metrics
azure.storage.script.execution_time
azure.storage.script.last_run_timestamp
azure.storage.script.last_run_status
```

**Implementation:**

```bash
send_to_zabbix() {
    local server="$1"
    local port="$2"
    local hostname="$3"
    local key="$4"
    local value="$5"

    # Use zabbix_sender
    zabbix_sender -z "$server" \
                  -p "$port" \
                  -s "$hostname" \
                  -k "$key" \
                  -o "$value" \
                  2>&1 | logger -t azure-storage-cost-analyzer

    return $?
}

# Send all metrics
send_metrics_to_zabbix() {
    local metrics_json="$1"

    # Extract and send each metric
    send_to_zabbix "$ZABBIX_SERVER" "$ZABBIX_PORT" "$ZABBIX_HOST" \
        "azure.storage.unattached.disks.count" \
        "$(echo "$metrics_json" | jq -r '.metrics.unattached_disks.count')"

    send_to_zabbix "$ZABBIX_SERVER" "$ZABBIX_PORT" "$ZABBIX_HOST" \
        "azure.storage.total_waste.monthly" \
        "$(echo "$metrics_json" | jq -r '.metrics.total_waste.monthly_usd')"

    # ... send all other metrics
}
```

---

### 2.2 Low-Level Discovery (LLD)

**Priority:** P1 (High)

**Requirement:**
Support Zabbix Low-Level Discovery for automatic item creation.

**Discovery Keys:**

```
# Discover all subscriptions
azure.storage.subscriptions.discovery

# Discover all resource groups
azure.storage.resourcegroups.discovery

# Discover all unattached disks
azure.storage.disks.discovery

# Discover all snapshots
azure.storage.snapshots.discovery
```

**LLD JSON Format:**

```json
{
  "data": [
    {
      "{#SUBSCRIPTION_ID}": "2f929c0a-d1f4-480c-a610-f75d1862fd53",
      "{#SUBSCRIPTION_NAME}": "Production Subscription"
    },
    {
      "{#SUBSCRIPTION_ID}": "03d76f78-4676-4116-b53a-162546996207",
      "{#SUBSCRIPTION_NAME}": "Dev/Test Subscription"
    }
  ]
}
```

**Disk Discovery:**

```json
{
  "data": [
    {
      "{#DISK_NAME}": "pvc-ef3fc2dc-b478-4687-acd5-613b206124f5",
      "{#DISK_ID}": "/subscriptions/.../disks/pvc-ef3fc2dc...",
      "{#DISK_SIZE_GB}": "8",
      "{#DISK_RG}": "mc_airflow-data-aks-rg_airflow-data-aks_centralus",
      "{#DISK_STATE}": "Unattached",
      "{#DISK_SKU}": "StandardSSD_LRS",
      "{#DISK_CREATED}": "2025-08-04",
      "{#SUBSCRIPTION_ID}": "2f929c0a-d1f4-480c-a610-f75d1862fd53"
    }
  ]
}
```

**Usage:**

```bash
# Generate LLD JSON
./script.sh --zabbix-discovery subscriptions --output-format json

./script.sh --zabbix-discovery disks --output-format json

./script.sh --zabbix-discovery snapshots --output-format json
```

**Zabbix Item Prototypes (Created via LLD):**

```
# Per-disk metrics
azure.storage.disk[{#DISK_NAME}].size_gb
azure.storage.disk[{#DISK_NAME}].cost_monthly
azure.storage.disk[{#DISK_NAME}].age_days
azure.storage.disk[{#DISK_NAME}].state

# Per-subscription metrics
azure.storage.subscription.total_waste[{#SUBSCRIPTION_ID}]
azure.storage.subscription.disk_count[{#SUBSCRIPTION_ID}]
azure.storage.subscription.snapshot_count[{#SUBSCRIPTION_ID}]

# Per-resource-group metrics
azure.storage.rg[{#RG_NAME}].disk_count
azure.storage.rg[{#RG_NAME}].total_cost
```

---

### 2.3 Threshold-Based Alerting

**Priority:** P1 (High)

**Requirement:**
Exit codes based on cost thresholds for Zabbix triggers.

**Acceptance Criteria:**

```bash
# Set thresholds via config or CLI
--warning-threshold 50.00      # Warning at $50/month
--critical-threshold 100.00    # Critical at $100/month

# Check thresholds and set exit code
check_thresholds() {
    local monthly_cost="$1"
    local warning="$2"
    local critical="$3"

    if (( $(echo "$monthly_cost > $critical" | bc -l) )); then
        log "CRITICAL: Monthly waste $monthly_cost exceeds critical threshold $critical"
        return 11  # Critical exit code
    elif (( $(echo "$monthly_cost > $warning" | bc -l) )); then
        log "WARNING: Monthly waste $monthly_cost exceeds warning threshold $warning"
        return 10  # Warning exit code
    fi

    return 0  # OK
}
```

**Zabbix Triggers:**

```
# In Zabbix UI or API:

Trigger: Azure Storage Waste - Warning
Expression: last(/azure-storage-cost-analyzer/azure.storage.total_waste.monthly) > 50
Severity: Average

Trigger: Azure Storage Waste - Critical
Expression: last(/azure-storage-cost-analyzer/azure.storage.total_waste.monthly) > 100
Severity: High

Trigger: Large Number of Unattached Disks
Expression: last(/azure-storage-cost-analyzer/azure.storage.unattached.disks.count) > 20
Severity: Average
```

---

## Phase 3: Multi-Subscription Support

### 3.1 Subscription Scanning

**Priority:** P1 (High)

**Current State:**
- Script processes only ONE subscription per execution
- Subscription ID passed as argument: `$2`
- No iteration over multiple subscriptions

**Requirement:**
Enable scanning of multiple Azure subscriptions in a single execution.

**Acceptance Criteria:**

```bash
# Scan all accessible subscriptions
./script.sh unused-report --subscriptions all --days 7

# Scan specific subscriptions (comma-separated)
./script.sh unused-report \
    --subscriptions "2f929c0a-d1f4-480c-a610-f75d1862fd53,03d76f78-4676-4116-b53a-162546996207" \
    --days 7

# Scan subscriptions from file
./script.sh unused-report --subscriptions-file /etc/azure-monitor/subscriptions.txt

# Exclude specific subscriptions
./script.sh unused-report --subscriptions all --exclude-subscriptions "test-sub-id"

# Default behavior (backward compatible)
./script.sh unused-report "2f929c0a-d1f4-480c-a610-f75d1862fd53" --days 7
```

**Implementation:**

```bash
# Get all accessible subscriptions
get_all_subscriptions() {
    az account list --query '[].id' -o tsv
}

# Main iteration loop
main_multi_subscription() {
    local subscription_list="$1"

    if [[ "$subscription_list" == "all" ]]; then
        subscription_list=$(get_all_subscriptions)
    fi

    # Convert comma-separated to array
    IFS=',' read -ra SUBSCRIPTIONS <<< "$subscription_list"

    local total_waste=0
    local total_disks=0
    local total_snapshots=0
    local failed_subscriptions=()

    for subscription_id in "${SUBSCRIPTIONS[@]}"; do
        log "Processing subscription: $subscription_id"

        # Process single subscription
        if ! process_single_subscription "$subscription_id"; then
            failed_subscriptions+=("$subscription_id")
            continue
        fi

        # Aggregate results
        # ...
    done

    # Generate aggregated report
    generate_multi_subscription_report
}
```

---

### 3.2 Aggregated Reporting

**Priority:** P1 (High)

**Requirement:**
Aggregate metrics across all subscriptions.

**JSON Output for Multi-Subscription:**

```json
{
  "version": "1.0",
  "timestamp": "2025-10-22T07:00:00Z",
  "scan_type": "multi-subscription",
  "subscriptions_scanned": 3,
  "subscriptions_failed": 0,
  "aggregated_metrics": {
    "total_unattached_disks": 45,
    "total_unattached_size_gb": 2150,
    "total_snapshots": 250,
    "total_snapshots_size_gb": 15000,
    "total_waste_monthly_usd": 185.50,
    "total_waste_annual_usd": 2226.00
  },
  "by_subscription": [
    {
      "subscription_id": "2f929c0a-d1f4-480c-a610-f75d1862fd53",
      "subscription_name": "Production",
      "status": "success",
      "metrics": {
        "unattached_disks_count": 12,
        "snapshots_count": 98,
        "waste_monthly_usd": 38.63
      }
    },
    {
      "subscription_id": "03d76f78-4676-4116-b53a-162546996207",
      "subscription_name": "Dev/Test",
      "status": "success",
      "metrics": {
        "unattached_disks_count": 33,
        "snapshots_count": 152,
        "waste_monthly_usd": 146.87
      }
    }
  ]
}
```

**Zabbix Metrics for Multi-Subscription:**

```
# Aggregated metrics
azure.storage.all.total_waste.monthly = 185.50
azure.storage.all.total_disks = 45
azure.storage.all.total_snapshots = 250

# Per-subscription metrics (via LLD)
azure.storage.subscription.waste_monthly[Production] = 38.63
azure.storage.subscription.waste_monthly[Dev/Test] = 146.87
```

---

### 3.3 Performance Optimization - Batch Zabbix Sender

**Priority:** P1 (High)

**Problem:**
Sending metrics individually to Zabbix creates N separate TCP connections, which is slow and inefficient.

**Solution:**
Use Batch Zabbix Sender - collect all metrics in one file, send with single `zabbix_sender` call.

**Acceptance Criteria:**

```bash
# Instead of N individual calls:
# zabbix_sender -k metric1 -o value1
# zabbix_sender -k metric2 -o value2
# ... (N times)

# Use ONE batch call:
zabbix_sender -z server -i batch_file.txt
```

**Implementation:**

```bash
# Create batch file with all metrics
create_zabbix_batch_file() {
    local batch_file="/tmp/zabbix_batch_$$.txt"
    local timestamp=$(date +%s)

    # Format: hostname key timestamp value
    # Subscription metrics
    for sub_id in "${SUBSCRIPTIONS[@]}"; do
        local sub_metrics=$(get_subscription_metrics "$sub_id")

        echo "$ZABBIX_HOST azure.storage.subscription.waste_monthly[$sub_id] $timestamp $(jq -r '.waste' <<< $sub_metrics)" >> "$batch_file"
        echo "$ZABBIX_HOST azure.storage.subscription.disk_count[$sub_id] $timestamp $(jq -r '.disks' <<< $sub_metrics)" >> "$batch_file"
        echo "$ZABBIX_HOST azure.storage.subscription.snapshot_count[$sub_id] $timestamp $(jq -r '.snapshots' <<< $sub_metrics)" >> "$batch_file"
    done

    # Aggregated metrics
    echo "$ZABBIX_HOST azure.storage.all.total_waste.monthly $timestamp $total_waste" >> "$batch_file"
    echo "$ZABBIX_HOST azure.storage.all.total_disks $timestamp $total_disks" >> "$batch_file"
    echo "$ZABBIX_HOST azure.storage.all.total_snapshots $timestamp $total_snapshots" >> "$batch_file"
    echo "$ZABBIX_HOST azure.storage.all.subscriptions_scanned $timestamp ${#SUBSCRIPTIONS[@]}" >> "$batch_file"

    # Script health metrics
    echo "$ZABBIX_HOST azure.storage.script.last_run_timestamp $timestamp $timestamp" >> "$batch_file"
    echo "$ZABBIX_HOST azure.storage.script.last_run_status $timestamp 0" >> "$batch_file"
    echo "$ZABBIX_HOST azure.storage.script.execution_time_seconds $timestamp $execution_time" >> "$batch_file"

    echo "$batch_file"
}

# Send all metrics with ONE call
send_batch_to_zabbix() {
    local batch_file="$1"

    log INFO "Sending $(wc -l < "$batch_file") metrics to Zabbix in batch"

    # Single zabbix_sender call for ALL metrics
    if zabbix_sender -z "$ZABBIX_SERVER" \
                     -p "$ZABBIX_PORT" \
                     -i "$batch_file" \
                     -vv 2>&1 | tee -a "$LOG_FILE"; then
        log INFO "Successfully sent all metrics to Zabbix"
        rm -f "$batch_file"
        return 0
    else
        log ERROR "Failed to send metrics to Zabbix"
        # Keep batch file for debugging
        mv "$batch_file" "/var/log/azure-monitor/failed_batch_$(date +%Y%m%d-%H%M%S).txt"
        return 1
    fi
}

# Main workflow
main() {
    # Process all subscriptions SEQUENTIALLY
    for sub in "${SUBSCRIPTIONS[@]}"; do
        process_subscription "$sub"
        # Rate limiting between subscriptions
        sleep 2
    done

    # Create batch file with ALL metrics
    local batch_file=$(create_zabbix_batch_file)

    # Send everything in ONE call
    send_batch_to_zabbix "$batch_file"
}
```

**Benefits:**

✅ **Single TCP Connection**
- Instead of N connections, just 1
- Reduced network overhead
- Faster execution

✅ **Atomic Operation**
- All metrics sent together
- All succeed or all fail
- No partial data in Zabbix

✅ **Easier Debugging**
- Batch file preserved on failure
- Can inspect what was sent
- Can retry manually

✅ **No Race Conditions**
- Sequential processing
- Deterministic order
- No conflicts

**Performance Comparison:**

```
# Individual sender (10 subscriptions, 5 metrics each = 50 calls)
Time: ~25 seconds (0.5s per TCP connection × 50)

# Batch sender (same data, 1 call)
Time: ~2 seconds (1 TCP connection)

Improvement: 12.5x faster! 🚀
```

**Recommended Approach for Multi-Subscription:**

```
┌─────────────────────────────────────────┐
│ SEQUENTIAL Processing (Recommended)     │
│                                         │
│  Subscription 1 → Collect metrics      │
│  Subscription 2 → Collect metrics      │
│  Subscription 3 → Collect metrics      │
│  ...                                   │
│  Subscription N → Collect metrics      │
│                                         │
│  ↓                                     │
│  Aggregate all metrics                 │
│  ↓                                     │
│  Create batch file (ALL metrics)       │
│  ↓                                     │
│  ONE zabbix_sender call                │
└─────────────────────────────────────────┘

Pros:
✅ No race conditions
✅ Easy aggregation
✅ No Azure API throttling
✅ Simple error handling
✅ Predictable execution

Performance:
⏱️ 3-10 subscriptions: 10-30 minutes
⏱️ 10-20 subscriptions: 30-60 minutes
⏱️ Acceptable for hourly cron job
```

**Why NOT Parallel Execution in Phase 3:**

❌ **Zabbix Sender Conflicts**
- Multiple processes writing to same items
- Last write wins = data loss
- Race conditions

❌ **Azure API Rate Limiting**
- Cost Management API: 30 calls/min/subscription
- Parallel requests = faster rate limit hit
- Results in 429 errors

❌ **Complex Aggregation**
- Need synchronization mechanisms
- Shared state management
- Difficult error handling

❌ **Added Complexity**
- No significant benefit for <20 subscriptions
- Maintenance overhead
- Harder debugging

**Note:** Parallel execution moved to Phase 5 (Extended Features) as optional optimization for environments with 30+ subscriptions.

---

## Phase 4: Production Hardening

### 4.1 Structured Logging

**Priority:** P1 (High)

**Requirement:**
Production-grade logging with levels, rotation, and syslog support.

**Log Levels:**

```
DEBUG   - Detailed diagnostic information
INFO    - General informational messages
WARN    - Warning messages (non-critical issues)
ERROR   - Error messages (operation failed but script continues)
FATAL   - Fatal errors (script must exit)
```

**Log Format:**

```
# File log format (JSON for parsing)
{"timestamp":"2025-10-22T07:00:00Z","level":"INFO","subscription":"2f929c0a...","message":"Starting analysis","duration_ms":null}
{"timestamp":"2025-10-22T07:00:05Z","level":"INFO","subscription":"2f929c0a...","message":"Found 12 unattached disks","duration_ms":5000}
{"timestamp":"2025-10-22T07:00:10Z","level":"WARN","subscription":"2f929c0a...","message":"Monthly waste $38.63 exceeds warning threshold","duration_ms":null}

# Syslog format
Oct 22 07:00:00 azure-monitor[12345]: [INFO] [2f929c0a] Starting analysis
Oct 22 07:00:05 azure-monitor[12345]: [WARN] [2f929c0a] Monthly waste $38.63 exceeds threshold
```

**Implementation:**

```bash
# Logging function
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Skip if log level not enabled
    case "$LOG_LEVEL" in
        ERROR) [[ "$level" =~ ^(ERROR|FATAL)$ ]] || return ;;
        WARN)  [[ "$level" =~ ^(WARN|ERROR|FATAL)$ ]] || return ;;
        INFO)  [[ "$level" =~ ^(INFO|WARN|ERROR|FATAL)$ ]] || return ;;
        DEBUG) ;;  # All levels
    esac

    # File logging
    if [[ -n "$LOG_FILE" ]]; then
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}" >> "$LOG_FILE"
    fi

    # Syslog
    if [[ "$ENABLE_SYSLOG" == "true" ]]; then
        logger -t azure-storage-cost-analyzer -p "${SYSLOG_FACILITY}.${level,,}" "[$level] $message"
    fi

    # Console (if verbose)
    if [[ "$VERBOSITY" != "silent" ]]; then
        echo "[$timestamp] [$level] $message" >&2
    fi
}

# Usage
log INFO "Starting Azure storage analysis"
log WARN "Found ${count} unattached disks"
log ERROR "Failed to query subscription ${sub_id}"
```

---

### 4.2 Error Recovery & Retries

**Priority:** P1 (High)

**Requirement:**
Robust error handling with automatic retries.

**Current State:**
- Has `retry_azure_api()` for Azure API calls
- No retry for Zabbix sender
- No partial failure handling for multi-subscription

**Enhancement:**

```bash
# Enhanced retry with exponential backoff
retry_with_backoff() {
    local max_attempts="$1"
    local base_delay="$2"
    shift 2
    local command=("$@")

    local attempt=1
    local delay=$base_delay

    while [[ $attempt -le $max_attempts ]]; do
        log DEBUG "Attempt $attempt/$max_attempts: ${command[*]}"

        if "${command[@]}"; then
            log DEBUG "Command succeeded on attempt $attempt"
            return 0
        fi

        local exit_code=$?

        if [[ $attempt -eq $max_attempts ]]; then
            log ERROR "Command failed after $max_attempts attempts"
            return $exit_code
        fi

        log WARN "Command failed (exit code $exit_code), retrying in ${delay}s..."
        sleep $delay

        delay=$((delay * 2))  # Exponential backoff
        ((attempt++))
    done
}

# Usage
retry_with_backoff 5 2 zabbix_sender -z "$server" -s "$host" -k "$key" -o "$value"
```

**Partial Failure Handling:**

```bash
# For multi-subscription scanning
process_all_subscriptions() {
    local -a failed_subs=()
    local -a success_subs=()

    for sub in "${SUBSCRIPTIONS[@]}"; do
        if process_subscription "$sub"; then
            success_subs+=("$sub")
        else
            failed_subs+=("$sub")
            log ERROR "Failed to process subscription: $sub"
        fi
    done

    if [[ ${#failed_subs[@]} -gt 0 ]]; then
        log WARN "Completed with ${#failed_subs[@]} failures out of ${#SUBSCRIPTIONS[@]} subscriptions"
        return 21  # Partial failure exit code
    fi

    return 0
}
```

---

## Technical Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Storage Monitor Script                  │
│                                                                   │
│  ┌───────────────┐         ┌────────────────┐                   │
│  │ Configuration │────────▶│ Main Execution │                   │
│  │   Manager     │         │     Engine     │                   │
│  └───────────────┘         └────────┬───────┘                   │
│                                     │                            │
│                    ┌────────────────┼────────────────┐          │
│                    │                │                │          │
│           ┌────────▼─────┐  ┌──────▼──────┐  ┌─────▼──────┐   │
│           │ Multi-Sub    │  │ Data        │  │ Output     │   │
│           │ Coordinator  │  │ Collector   │  │ Formatter  │   │
│           └────────┬─────┘  └──────┬──────┘  └─────┬──────┘   │
│                    │                │                │          │
│         ┌──────────▼──────────┐    │                │          │
│         │ Subscription Loop   │    │                │          │
│         │ (parallel/serial)   │    │                │          │
│         └──────────┬──────────┘    │                │          │
│                    │                │                │          │
│                    └────────────────▼────────────────┘          │
│                                     │                            │
│                    ┌────────────────┼────────────────┐          │
│                    │                │                │          │
│           ┌────────▼─────┐                   ┌─────▼──────┐   │
│           │ Azure        │                   │ Logging    │   │
│           │ API Client   │                   │ System     │   │
│           └────────┬─────┘                   └─────┬──────┘   │
└────────────────────┼────────────────────────────────┼──────────┘
                     │                │                │
                     │                │                │
          ┌──────────▼──────────┐    │      ┌─────────▼────────┐
          │  Azure Resources    │    │      │  Log Files       │
          │  - Subscriptions    │    │      │  - JSON logs     │
          │  - Disks            │    │      │  - Syslog        │
          │  - Snapshots        │    │      └──────────────────┘
          │  - Cost API         │
          └─────────────────────┘
          ┌──────────────────────────┼──────────────────────────┐
          │                          │                          │
   ┌──────▼──────┐         ┌─────────▼────────┐    ┌──────────▼────────┐
   │ File Output │         │ Zabbix Sender    │    │ Webhook/Email     │
   │ - JSON      │         │ - Metrics        │    │ (Future)          │
   │ - Text      │         │ - LLD            │    └───────────────────┘
   └─────────────┘         └──────────────────┘
```

---

## Zabbix Integration Details

### Zabbix Template

Create Zabbix template: **Azure Storage Cost Monitoring**

**Template Items:**

```xml
<!-- Main metrics -->
<item>
  <name>Azure Storage: Total Waste (Monthly)</name>
  <key>azure.storage.total_waste.monthly</key>
  <type>ZABBIX_TRAPPER</type>
  <value_type>FLOAT</value_type>
  <units>USD</units>
  <description>Total monthly cost of wasted storage resources</description>
</item>

<item>
  <name>Azure Storage: Unattached Disks Count</name>
  <key>azure.storage.unattached.disks.count</key>
  <type>ZABBIX_TRAPPER</type>
  <value_type>UNSIGNED</value_type>
  <description>Number of unattached managed disks</description>
</item>

<!-- Discovery rules -->
<discovery_rule>
  <name>Azure Subscriptions Discovery</name>
  <key>azure.storage.subscriptions.discovery</key>
  <type>ZABBIX_TRAPPER</type>
  <lifetime>30d</lifetime>
  <description>Discover all Azure subscriptions</description>

  <item_prototypes>
    <item_prototype>
      <name>Azure [{#SUBSCRIPTION_NAME}]: Monthly Waste</name>
      <key>azure.storage.subscription.waste_monthly[{#SUBSCRIPTION_ID}]</key>
      <type>ZABBIX_TRAPPER</type>
      <value_type>FLOAT</value_type>
      <units>USD</units>
    </item_prototype>
  </item_prototypes>

  <trigger_prototypes>
    <trigger_prototype>
      <name>Azure [{#SUBSCRIPTION_NAME}]: High waste detected</name>
      <expression>{Azure Storage Monitor:azure.storage.subscription.waste_monthly[{#SUBSCRIPTION_ID}].last()} &gt; 100</expression>
      <priority>HIGH</priority>
    </trigger_prototype>
  </trigger_prototypes>
</discovery_rule>
```

**Triggers:**

```
Name: Azure Storage: Critical waste detected
Expression: {Azure Storage Monitor:azure.storage.total_waste.monthly.last()} > 500
Severity: High
Description: Total monthly storage waste exceeds $500

Name: Azure Storage: Warning waste detected
Expression: {Azure Storage Monitor:azure.storage.total_waste.monthly.last()} > 200
Severity: Average
Description: Total monthly storage waste exceeds $200

Name: Azure Storage: Large number of unattached disks
Expression: {Azure Storage Monitor:azure.storage.unattached.disks.count.last()} > 50
Severity: Average
Description: More than 50 unattached disks found
```

---

## Zabbix Actions and Notifications

### Actions Configuration

**Action 1: Azure Storage - High Waste Alert**

```yaml
Name: Azure Storage - High Waste Alert
Conditions:
  - Trigger severity >= Warning
  - Trigger name contains "Azure Storage"
  - Tag name = "component" AND Tag value = "azure-storage"

Operations:
  Step 1 (0s - 1h):
    - Send message to: DevOps Team
    - Via: Email, Slack

  Step 2 (1h - 2h):
    - Send message to: DevOps Lead
    - Via: Email, Slack, PagerDuty

  Step 3 (2h+):
    - Send message to: Platform Team Lead
    - Via: Email, PagerDuty

Recovery Operations:
  - Send recovery message to: DevOps Team
  - Via: Email, Slack
  - Message: "Azure Storage waste is now below threshold"

Update Operations:
  - Send update every: 4 hours
  - Only if problem persists
```

**Action 2: Azure Storage - Critical Errors**

```yaml
Name: Azure Storage - Critical Errors
Conditions:
  - Trigger severity >= High
  - Trigger name contains "Azure Storage"
  - OR: Tag name = "error" AND Tag value = "critical"

Operations:
  Step 1 (immediately):
    - Send message to: DevOps Team, Platform Team
    - Via: Slack, PagerDuty
    - Subject: "[CRITICAL] Azure Storage Monitoring Issue"

Recovery Operations:
  - Notify all recipients
  - Via: Slack, Email
```

---

### Media Types Configuration

**Email Configuration:**

```yaml
Media Type: Email
SMTP Server: smtp.company.com
SMTP Port: 587
SMTP Security: STARTTLS
Authentication: Yes
Username: zabbix-alerts@company.com

Message Format:
  Subject: {TRIGGER.STATUS}: {TRIGGER.NAME}
  Body: |
    Problem: {TRIGGER.NAME}
    Severity: {TRIGGER.SEVERITY}
    Started: {EVENT.DATE} {EVENT.TIME}

    Subscription: {ITEM.VALUE:azure.storage.subscription.name}
    Monthly Waste: ${ITEM.VALUE:azure.storage.total_waste.monthly}
    Unattached Disks: {ITEM.VALUE:azure.storage.unattached.disks.count}

    Details: {TRIGGER.DESCRIPTION}

    Link: {TRIGGER.URL}
```

**Slack Configuration:**

```yaml
Media Type: Slack Webhook
Webhook URL: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
Channel: #azure-alerts

Message Template:
  {
    "channel": "#azure-alerts",
    "username": "Zabbix Azure Monitor",
    "icon_emoji": ":warning:",
    "attachments": [{
      "color": "{TRIGGER.SEVERITY.COLOR}",
      "title": "{TRIGGER.NAME}",
      "text": "{TRIGGER.DESCRIPTION}",
      "fields": [
        {"title": "Severity", "value": "{TRIGGER.SEVERITY}", "short": true},
        {"title": "Status", "value": "{TRIGGER.STATUS}", "short": true},
        {"title": "Monthly Waste", "value": "${ITEM.VALUE}", "short": true},
        {"title": "Subscription", "value": "{SUBSCRIPTION.NAME}", "short": true}
      ],
      "footer": "Azure Storage Monitor",
      "ts": "{EVENT.TIMESTAMP}"
    }]
  }

Color Mapping:
  - Not classified: #97AAB3
  - Information: #7499FF
  - Warning: #FFC859
  - Average: #FFA059
  - High: #E97659
  - Disaster: #E45959
```

**Teams Configuration:**

```yaml
Media Type: Microsoft Teams Webhook
Webhook URL: https://outlook.office.com/webhook/YOUR/WEBHOOK/URL

Message Template (Adaptive Card):
  {
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "{TRIGGER.SEVERITY.COLOR}",
    "summary": "{TRIGGER.NAME}",
    "sections": [{
      "activityTitle": "Azure Storage Alert",
      "activitySubtitle": "{TRIGGER.NAME}",
      "facts": [
        {"name": "Severity", "value": "{TRIGGER.SEVERITY}"},
        {"name": "Status", "value": "{TRIGGER.STATUS}"},
        {"name": "Subscription", "value": "{SUBSCRIPTION.NAME}"},
        {"name": "Monthly Waste", "value": "${ITEM.VALUE}"},
        {"name": "Started", "value": "{EVENT.DATE} {EVENT.TIME}"}
      ],
      "markdown": true
    }],
    "potentialAction": [{
      "@type": "OpenUri",
      "name": "View in Zabbix",
      "targets": [{"os": "default", "uri": "{TRIGGER.URL}"}]
    }]
  }
```

---

### User Groups

**DevOps Team:**
```yaml
Name: Azure Storage - DevOps Team
Members:
  - john.doe@company.com (Email, Slack)
  - jane.smith@company.com (Email, Slack)
  - devops-oncall@company.com (PagerDuty)

Permissions:
  - Read: Azure Storage monitoring data
  - Acknowledge: Problems
  - Close: Problems (after verification)
```

**Platform Team:**
```yaml
Name: Azure Storage - Platform Team
Members:
  - platform-lead@company.com (Email, Slack, PagerDuty)
  - platform-oncall@company.com (PagerDuty)

Permissions:
  - Read: All monitoring data
  - Acknowledge: All problems
  - Configure: Triggers, actions
```

---

### Escalation Schemes

**Standard Escalation:**

```
Time: 0min - Send to DevOps Team (Slack + Email)
         ↓
Time: 60min - If not acknowledged → Send to DevOps Lead (Slack + Email + PagerDuty)
         ↓
Time: 120min - If not resolved → Send to Platform Team Lead (PagerDuty)
         ↓
Time: 180min - If not resolved → Escalate to CTO
```

**Critical Escalation (for >$500 waste or auth failures):**

```
Time: 0min - Send to DevOps Team + Platform Team (Slack + PagerDuty)
         ↓
Time: 30min - If not acknowledged → Send to DevOps Lead + Platform Lead
         ↓
Time: 60min - If not resolved → Page CTO
```

---

### Recovery Actions

**Recovery Message Template:**

```yaml
Email Subject: [RESOLVED] {TRIGGER.NAME}

Email Body: |
  ✅ PROBLEM RESOLVED

  Problem: {TRIGGER.NAME}
  Resolved: {EVENT.RECOVERY.DATE} {EVENT.RECOVERY.TIME}
  Duration: {EVENT.DURATION}

  Resolution Details:
  - Previous Monthly Waste: ${ITEM.LASTVALUE}
  - Current Monthly Waste: ${ITEM.VALUE}
  - Improvement: ${ITEM.VALUE.CHANGE}

  Subscription: {SUBSCRIPTION.NAME}

  Actions Taken:
  - Unattached disks deleted: {DISKS.DELETED.COUNT}
  - Snapshots cleaned up: {SNAPSHOTS.DELETED.COUNT}

  Next Review: {NEXT.SCHEDULED.RUN}

Slack Message:
  ✅ *Azure Storage Alert Resolved*

  _Problem:_ {TRIGGER.NAME}
  _Duration:_ {EVENT.DURATION}

  Monthly waste reduced from ${ITEM.LASTVALUE} to ${ITEM.VALUE}

  Great work! 🎉
```

---

### Message Templates

**Warning Alert Template:**

```
📊 AZURE STORAGE WARNING

Subscription: Production (2f929c0a-d1f4...)
Alert: Monthly waste exceeds warning threshold

Current Status:
├─ Monthly Waste: $285.50 (⚠️ Warning: >$200)
├─ Annual Projection: $3,426.00
├─ Unattached Disks: 45 disks (1,250 GB)
└─ Old Snapshots: 120 snapshots (8,500 GB)

Top Wasters:
1. mc_testing-aks-rg: $150.25 (25 disks)
2. mc_airflow-data-aks-rg: $85.50 (12 disks)
3. backup-rg: $49.75 (8 disks)

Recommendations:
• Review and delete unattached disks in testing environments
• Implement snapshot retention policy (max 30 days)
• Consider disk SKU downgrades for non-production

View Details: https://zabbix.company.com/triggers.php?triggerid={TRIGGER.ID}
```

**Critical Alert Template:**

```
🚨 AZURE STORAGE CRITICAL ALERT

Subscription: Production
Alert: Monthly waste CRITICAL - immediate action required!

⚠️ CRITICAL STATUS:
├─ Monthly Waste: $525.00 (🔴 Critical: >$500)
├─ Annual Cost: $6,300.00
├─ Unattached Disks: 85 disks (2,500 GB)
├─ Old Snapshots: 250 snapshots (15,000 GB)
└─ Oldest Unattached Disk: 247 days old!

IMMEDIATE ACTIONS REQUIRED:
1. Review unattached disks older than 90 days (35 disks found)
2. Delete test environment leftovers (estimated savings: $200/month)
3. Implement automated cleanup policies

Estimated Savings if Cleaned:
├─ Delete disks >90 days old: $150.00/month
├─ Delete snapshots >30 days old: $80.00/month
└─ Total potential savings: $230.00/month ($2,760/year)

URGENT: Assign owner and ACK within 30 minutes

Zabbix: https://zabbix.company.com/triggers.php?triggerid={TRIGGER.ID}
Azure Portal: https://portal.azure.com/#blade/Microsoft_Azure_CostManagement
```

---

## Problem Tags and Trigger Dependencies

### Problem Tags

**Tag Strategy:**

```yaml
# Tags automatically added by script/Zabbix
Tags:
  component: azure-storage          # Component identifier
  subscription_id: {SUB_ID}         # Azure subscription ID
  subscription_name: {SUB_NAME}     # Human-readable name
  resource_group: {RG_NAME}         # Resource group (if filtered)
  severity: average|high        # Alert severity
  cost_tier: low|medium|high        # Based on waste amount
  environment: production|staging|development

# Cost tier mapping:
cost_tier: low      # Monthly waste < $100
cost_tier: medium   # Monthly waste $100-$500
cost_tier: high     # Monthly waste > $500

# Auto-tagging in script:
if [[ $monthly_waste -lt 100 ]]; then
    COST_TIER="low"
elif [[ $monthly_waste -lt 500 ]]; then
    COST_TIER="medium"
else
    COST_TIER="high"
fi
```

**Tag Usage in Actions:**

```yaml
Action: High Cost Alerts
Conditions:
  - Tag: cost_tier = high
  - Tag: environment = production

Action: Development Environment Alerts
Conditions:
  - Tag: environment = development
  - Only during business hours (9-18 weekdays)

Action: Critical Subscription Alerts
Conditions:
  - Tag: subscription_name = "Production"
  - Severity >= High
```

---

### Trigger Dependencies

**Dependency Chain:**

```yaml
# Parent trigger: Script execution health
Trigger: Azure Storage Script - Not Running
Expression: nodata(/azure-storage-cost-analyzer/azure.storage.script.last_run_timestamp, 2h)
Severity: High
Description: Script hasn't run in 2 hours

# Dependent triggers (disabled if parent fails):
Depends on: Azure Storage Script - Not Running
Triggers:
  - Azure Storage: High waste detected
  - Azure Storage: Large number of unattached disks
  - Azure Storage: Critical threshold exceeded

Reason: If script isn't running, all data is stale - no point alerting
```

**Authentication Dependency:**

```yaml
# Parent: Azure authentication
Trigger: Azure Storage Script - Authentication Failed
Expression: last(/azure-storage-cost-analyzer/azure.storage.script.last_run_status) = 2
Severity: High

# Dependent triggers:
Depends on: Azure Storage Script - Authentication Failed
Triggers:
  - All subscription-specific triggers

Reason: Can't collect data without valid authentication
```

**Multi-Subscription Dependencies:**

```yaml
# Parent: Overall monitoring health
Trigger: Azure Storage - Partial Failure
Expression: last(/azure-storage-cost-analyzer/azure.storage.script.last_run_status) = 21
Severity: Average
Description: Some subscriptions failed to process

# Child triggers still fire for successful subscriptions
# Only failed subscriptions are suppressed
```

---

## Resource Exclusion Logic (Static vs Dynamic Resources)

### Problem Statement

**Two Types of Unattached Disks:**

1. **Static/Intentional Unattached Disks**
   - Reserved disks kept for future use
   - Backup disks intentionally detached
   - Disaster recovery standby disks
   - SHOULD NOT TRIGGER ALERTS

2. **Dynamic/Temporary Unattached Disks**
   - Databricks/Spark worker VM disks (lifecycle: hours/days)
   - CI/CD ephemeral build VM disks
   - Auto-scaling cluster disks
   - SHOULD ONLY ALERT if orphaned (not deleted after X days)

---

### Solution Architecture

**Multi-Layer Filtering Approach:**

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Azure Tag Filtering (in script)                    │
│ ├─ Filter out resources with tag: monitoring:exclude=true   │
│ └─ For STATIC resources that should never alert             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Name Pattern Exclusion (in script config)          │
│ ├─ Exclude patterns: databricks-*, temp-*, worker-*         │
│ └─ For KNOWN dynamic resource patterns                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Age-Based Filtering (in Zabbix Trigger)            │
│ ├─ Alert only if unattached > 7 days                        │
│ └─ For UNKNOWN dynamic resources (grace period)             │
└─────────────────────────────────────────────────────────────┘
                            ↓
                      [Alert Fires]
```

---

### Layer 1: Azure Tag Filtering (Static Resources)

**Configuration in Script:**

```ini
# /etc/azure-storage-cost-analyzer/config.conf

[exclusions]
# Azure tags for permanent exclusions
# Disks with these tags will be completely excluded from reports
exclude_tags = monitoring:exclude, keep-unattached:true, reserved:disk

# Examples:
# - monitoring:exclude=true  → Never monitor this resource
# - keep-unattached:true     → This disk is intentionally unattached
# - reserved:disk=backup     → Reserved for backup purposes
```

**Azure Tagging Process:**

```bash
# DevOps team tags resources that should never alert:

# Tag a specific disk to exclude it permanently
az disk update \
  --name my-reserved-disk \
  --resource-group production-rg \
  --tags monitoring:exclude=true reason="DR standby disk"

# Tag multiple disks in a resource group
az disk list --resource-group backup-rg \
  --query '[].id' -o tsv | xargs -I {} \
  az disk update --ids {} --tags keep-unattached:true
```

**Script Implementation:**

```bash
# In script: Filter disks with exclusion tags
filter_by_tags() {
    local disks_json="$1"
    local exclude_tags="$EXCLUDE_TAGS"  # From config

    # Parse exclude tags
    IFS=',' read -ra TAG_ARRAY <<< "$exclude_tags"

    for disk in $(echo "$disks_json" | jq -r '.[] | @base64'); do
        _jq() {
            echo "${disk}" | base64 --decode | jq -r "${1}"
        }

        local disk_id=$(_jq '.Id')
        local disk_tags=$(_jq '.tags // {}')

        # Check if disk has any exclusion tags
        local should_exclude=false
        for tag in "${TAG_ARRAY[@]}"; do
            IFS=':' read -r tag_name tag_value <<< "$tag"

            if echo "$disk_tags" | jq -e ".[\"$tag_name\"] == \"$tag_value\"" > /dev/null; then
                log INFO "Excluding disk $disk_id (tag: $tag_name=$tag_value)"
                should_exclude=true
                break
            fi
        done

        if [[ "$should_exclude" == "false" ]]; then
            # Include this disk in report
            echo "$disk" | base64 --decode
        fi
    done
}
```

**Azure Resource Graph Query with Tag Filter:**

```kusto
Resources
| where type == 'microsoft.compute/disks'
| where subscriptionId == '$subscription_id'
| where properties.diskState == 'Unattached'
// Exclude disks with monitoring:exclude tag
| where tags['monitoring:exclude'] != 'true'
| where tags['keep-unattached'] != 'true'
| project
    Id = id,
    Name = name,
    SizeGb = properties.diskSizeGB,
    ResourceGroup = resourceGroup,
    Created = properties.timeCreated,
    Tags = tags
```

---

### Layer 2: Name Pattern Exclusion (Known Dynamic Resources)

**Configuration:**

```ini
# /etc/azure-storage-cost-analyzer/config.conf

[exclusions]
# Exclude disks matching these name patterns (regex)
# These are typically dynamic resources (Databricks, CI/CD, etc.)
exclude_patterns = ^databricks-.*$, ^worker-.*$, ^temp-.*$, ^ci-build-.*$, ^spark-worker-.*$

# Examples:
# - databricks-worker-12345-disk   → Databricks cluster disk
# - worker-pool-abc-osdisk          → AKS worker node disk
# - temp-vm-20251022-disk           → Temporary build VM disk
# - ci-build-job-456-disk           → CI/CD ephemeral disk
```

**Script Implementation:**

```bash
# In script: Filter by name patterns
filter_by_patterns() {
    local disks_json="$1"
    local exclude_patterns="$EXCLUDE_PATTERNS"  # From config

    # Convert patterns to array
    IFS=',' read -ra PATTERN_ARRAY <<< "$exclude_patterns"

    echo "$disks_json" | jq --argjson patterns "$(printf '%s\n' "${PATTERN_ARRAY[@]}" | jq -R . | jq -s .)" '
    [.[] | select(
        # Check if disk name matches any exclusion pattern
        [.Name | test($patterns[]; "i")] | any | not
    )]'
}

# Usage in main function:
process_subscription() {
    local sub_id="$1"

    # Get all unattached disks
    local disks=$(list_unattached_disks "$sub_id")

    # Apply filters
    disks=$(filter_by_tags "$disks")
    disks=$(filter_by_patterns "$disks")
    disks=$(filter_by_age "$disks")  # Layer 3

    # Now report only filtered disks
    send_to_zabbix "$disks"
}
```

**Pattern Examples:**

```bash
# Databricks cluster disks
# Pattern: databricks-worker-*-*
# Example: databricks-worker-12345-osdisk
# Lifecycle: Created when cluster starts, deleted when cluster stops (hours)

# AKS worker node disks (autoscaling)
# Pattern: worker-pool-*-osdisk-*
# Example: worker-pool-default-osdisk-abc123
# Lifecycle: Created on scale-up, deleted on scale-down (hours/days)

# CI/CD build VM disks
# Pattern: ci-build-*
# Example: ci-build-job-456-20251022-disk
# Lifecycle: Created for build, deleted after (minutes/hours)

# Spark/EMR temporary worker disks
# Pattern: spark-worker-*, emr-worker-*
# Example: spark-worker-node-789-disk
# Lifecycle: Job duration (hours)
```

---

### Layer 3: Age-Based Filtering (Unknown Dynamic Resources)

**Why Age-Based Filtering?**

- **Problem:** New dynamic resources we don't know about yet
- **Solution:** Grace period - only alert if disk is old AND unattached
- **Logic:**
  - Databricks disk unattached for 2 hours → Normal, don't alert
  - Databricks disk unattached for 10 days → Orphaned, ALERT!

**Implementation in Zabbix Trigger:**

```yaml
# Trigger with age condition
Trigger: Azure Storage: Old Unattached Disks
Expression: |
  // Only alert if disk is unattached AND older than grace period
  {Azure Storage Monitor:azure.storage.unattached.disks.count.last()} > 0
  AND
  {Azure Storage Monitor:azure.storage.unattached.disks.oldest_age_days.last()} > 7

Severity: Average
Description: |
  Found {ITEM.VALUE1} unattached disks.
  Oldest disk has been unattached for {ITEM.VALUE2} days (threshold: 7 days)

  This likely indicates orphaned resources that should be cleaned up.
```

**Script Enhancement - Add Age Metrics:**

```bash
# In JSON output, add age-related metrics
{
  "metrics": {
    "unattached_disks": {
      "count": 12,
      "oldest_age_days": 45,        # NEW: Age of oldest disk
      "avg_age_days": 15,            # NEW: Average age
      "count_over_7_days": 5,        # NEW: Count older than 7 days
      "count_over_30_days": 2        # NEW: Count older than 30 days
    }
  }
}

# Calculate age in script
calculate_disk_age() {
    local created_date="$1"  # Format: 2025-08-04
    local current_date=$(date +%s)
    local created_epoch=$(date -d "$created_date" +%s)
    local age_seconds=$((current_date - created_epoch))
    local age_days=$((age_seconds / 86400))
    echo "$age_days"
}

# Send age metrics to Zabbix
zabbix_sender -k "azure.storage.unattached.disks.oldest_age_days" -o "$oldest_age"
zabbix_sender -k "azure.storage.unattached.disks.count_over_7_days" -o "$count_over_7days"
```

**Multi-Tier Trigger Strategy:**

```yaml
# Trigger 1: Informational (recent unattached)
Trigger: Azure Storage: Recently Unattached Disks
Expression: |
  {azure.storage.unattached.disks.count.last()} > 10
  AND
  {azure.storage.unattached.disks.oldest_age_days.last()} <= 7

Severity: Warning
Description: Found new unattached disks (age < 7 days). Monitoring for orphaned resources.

# Trigger 2: Warning (potentially orphaned)
Trigger: Azure Storage: Potentially Orphaned Disks
Expression: |
  {azure.storage.unattached.disks.count_over_7_days.last()} > 5
  AND
  {azure.storage.unattached.disks.count_over_7_days.last()} < 20

Severity: Average
Description: Found {ITEM.VALUE} disks unattached for >7 days. Review for cleanup.

# Trigger 3: High (definitely orphaned)
Trigger: Azure Storage: Orphaned Disks - Action Required
Expression: |
  {azure.storage.unattached.disks.count_over_30_days.last()} > 0
  OR
  {azure.storage.unattached.disks.count_over_7_days.last()} >= 20

Severity: High
Description: |
  CRITICAL: Found orphaned disks requiring immediate action:
  - {ITEM.VALUE1} disks unattached for >30 days
  - {ITEM.VALUE2} disks unattached for >7 days
```

---

### Configuration File - Complete Exclusions Section

```ini
# /etc/azure-storage-cost-analyzer/config.conf

[exclusions]
# ============================================================================
# LAYER 1: Azure Tag Filtering (Static Resources)
# ============================================================================
# Disks with these Azure tags will be COMPLETELY excluded from monitoring
# Use for resources that should NEVER alert (DR disks, reserved disks, etc.)
#
# How to tag a disk in Azure:
#   az disk update --name <disk> --resource-group <rg> --tags monitoring:exclude=true
#
exclude_tags = monitoring:exclude, keep-unattached:true, reserved:disk

# ============================================================================
# LAYER 2: Name Pattern Exclusion (Known Dynamic Resources)
# ============================================================================
# Regex patterns for disk names that should be excluded
# Use for known dynamic resources (Databricks, CI/CD, auto-scaling, etc.)
#
# Examples of dynamic resources:
# - Databricks worker disks (created/deleted automatically)
# - AKS autoscaling worker node disks
# - CI/CD ephemeral build VM disks
# - Spark/EMR temporary worker disks
#
exclude_patterns = ^databricks-.*$, ^worker-.*$, ^temp-.*$, ^ci-build-.*$, ^spark-worker-.*$, ^emr-.*$

# ============================================================================
# LAYER 3: Age-Based Grace Period (Unknown Dynamic Resources)
# ============================================================================
# Days to wait before alerting on unattached disks
# This provides a grace period for dynamic resources to be cleaned up
#
# Recommendation:
# - 7 days: Good balance (catches orphaned resources, allows cleanup time)
# - 3 days: More aggressive (faster detection, more false positives)
# - 14 days: Conservative (fewer false positives, slower detection)
#
age_grace_period_days = 7

# Alert thresholds based on age
age_threshold_warning = 7   # Warn if disk unattached > 7 days
age_threshold_critical = 30  # Critical if disk unattached > 30 days

# ============================================================================
# Resource Group Exclusions (Optional)
# ============================================================================
# Completely exclude specific resource groups from monitoring
# Use for sandbox/dev environments where waste is acceptable
#
exclude_resource_groups = sandbox-rg, temp-testing-rg, dev-playground-rg
```

---

### Operational Workflow

**For Static Resources (Permanent Exclusions):**

```bash
# Step 1: DevOps identifies disk that should never alert
# Example: DR standby disk for database

# Step 2: Tag the disk in Azure
az disk update \
  --name dr-standby-postgres-disk \
  --resource-group production-rg \
  --tags monitoring:exclude=true reason="DR standby - do not alert"

# Step 3: Verify tag
az disk show --name dr-standby-postgres-disk -g production-rg \
  --query tags

# Step 4: Next script run will exclude this disk automatically
# No Zabbix configuration needed!
```

**For Dynamic Resources (Pattern-Based Exclusions):**

```bash
# Step 1: DevOps notices false alerts for Databricks disks
# Example: databricks-worker-12345-osdisk keeps alerting

# Step 2: Add pattern to config file
# Edit /etc/azure-storage-cost-analyzer/config.conf:
[exclusions]
exclude_patterns = ..., ^databricks-.*$

# Step 3: Restart monitoring (or wait for next run)
# All databricks-* disks now excluded

# Step 4: Monitor for orphaned Databricks disks via age filter
# If databricks-worker-* disk is unattached for >7 days → still alerts!
```

**For Unknown Dynamic Resources (Age-Based Grace Period):**

```bash
# Scenario: New autoscaling system creates/deletes VMs we don't know about

# Script behavior:
# - Day 1: New disk "unknown-worker-abc" becomes unattached
#   → Included in report, BUT no Zabbix alert (age < 7 days)
#   → Informational item shows: "5 recently unattached disks"
#
# - Day 3: Disk still unattached
#   → Still no alert (within grace period)
#
# - Day 8: Disk STILL unattached
#   → Zabbix WARNING alert fires!
#   → "Potentially orphaned disk detected"
#
# - Day 31: Disk STILL unattached
#   → Zabbix CRITICAL alert fires!
#   → "Orphaned disk - immediate action required"

# DevOps response:
# Option A: Add pattern to exclusions (if expected behavior)
# Option B: Delete the disk (if truly orphaned)
# Option C: Tag the disk (if should be kept permanently)
```

---

### Summary: Recommended Approach

**For Static Resources:**
✅ **USE: Azure Tags** (`monitoring:exclude=true`)
- Easy to manage in Azure Portal
- Self-documenting (can add reason in tags)
- No script reconfiguration needed
- Auditable (who tagged what and when)

**For Known Dynamic Resources:**
✅ **USE: Name Patterns** (`exclude_patterns` in config)
- Fast exclusion (no Azure API calls)
- Centrally managed in config file
- Works for predictable naming conventions

**For Unknown Dynamic Resources:**
✅ **USE: Age-Based Filtering** (Zabbix trigger condition)
- Grace period prevents false alerts
- Catches truly orphaned resources
- No manual configuration per resource
- Automatic escalation (7 days → warning, 30 days → critical)

**BEST PRACTICE - Layered Defense:**
1. Tag permanent exclusions in Azure → Never see them
2. Configure patterns for known dynamic resources → Excluded from reports
3. Let age-based triggers catch unknown/orphaned resources → Alert after grace period

This approach minimizes false positives while ensuring no real waste goes undetected! 🎯

---

## Exit Codes & Error Handling

### Complete Exit Code Matrix

| Code | Name | Trigger Condition | Zabbix Action | Ops Action |
|------|------|------------------|---------------|------------|
| 0 | SUCCESS | All OK | None | None |
| 1 | GENERAL_ERROR | Unexpected failure | Alert | Investigate logs |
| 2 | AUTH_FAILED | Azure login failed | Critical alert | Fix credentials |
| 3 | RATE_LIMIT | API throttling | Warning | Retry later |
| 4 | INVALID_ARGS | Bad arguments | Critical alert | Fix script call |
| 5 | CONFIG_ERROR | Config invalid | Critical alert | Fix config file |
| 10 | WARNING_THRESHOLD | Waste > warning | Warning alert | Review resources |
| 11 | CRITICAL_THRESHOLD | Waste > critical | Critical alert | Immediate action |
| 20 | NO_DATA | No resources found | Info | Normal (maybe) |
| 21 | PARTIAL_FAILURE | Some subs failed | Warning | Check failed subs |
| 22 | ZABBIX_SEND_FAILED | Zabbix unavailable | Warning | Check Zabbix |

---

## Configuration Management

### Environment Variables

Support environment variables for containerized deployments:

```bash
# Azure configuration
AZURE_SUBSCRIPTION_ID
AZURE_SUBSCRIPTIONS        # Comma-separated list
AZURE_RESOURCE_GROUP

# Dates
AZURE_MONITOR_DAYS=30
AZURE_MONITOR_DATE_START
AZURE_MONITOR_DATE_END

# Zabbix
ZABBIX_SERVER=monitoring.company.com
ZABBIX_PORT=10051
ZABBIX_HOSTNAME=azure-storage-cost-analyzer
ZABBIX_ENABLED=true

# Thresholds
AZURE_MONITOR_WARNING_THRESHOLD=50.00
AZURE_MONITOR_CRITICAL_THRESHOLD=100.00

# Logging
AZURE_MONITOR_LOG_LEVEL=info
AZURE_MONITOR_LOG_FILE=/var/log/azure-monitor/monitor.log

# Output
AZURE_MONITOR_OUTPUT_FORMAT=json
AZURE_MONITOR_VERBOSITY=quiet
```

---

## Deployment & Operations

### Installation

```bash
# 1. Install script
sudo cp azure-storage-cost-analyzer.sh /usr/local/bin/azure-storage-cost-analyzer
sudo chmod +x /usr/local/bin/azure-storage-cost-analyzer

# 2. Create directories
sudo mkdir -p /etc/azure-storage-cost-analyzer
sudo mkdir -p /var/log/azure-storage-cost-analyzer

# 3. Create configuration
sudo cp config.conf /etc/azure-storage-cost-analyzer/config.conf
sudo chmod 600 /etc/azure-storage-cost-analyzer/config.conf

# 4. Create service account (optional)
sudo useradd -r -s /bin/false azure-monitor
sudo chown -R azure-monitor:azure-monitor /var/log/azure-storage-cost-analyzer
```

### Systemd Service

```ini
# /etc/systemd/system/azure-storage-cost-analyzer.service
[Unit]
Description=Azure Storage Cost Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=azure-monitor
Group=azure-monitor
ExecStart=/usr/local/bin/azure-storage-cost-analyzer \
    --config /etc/azure-storage-cost-analyzer/config.conf \
    unused-report
StandardOutput=journal
StandardError=journal
SyslogIdentifier=azure-storage-cost-analyzer

[Install]
WantedBy=multi-user.target
```

### Systemd Timer

```ini
# /etc/systemd/system/azure-storage-cost-analyzer.timer
[Unit]
Description=Run Azure Storage Monitor hourly
Requires=azure-storage-cost-analyzer.service

[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable azure-storage-cost-analyzer.timer
sudo systemctl start azure-storage-cost-analyzer.timer
```

### Cron Example

```bash
# /etc/cron.d/azure-storage-cost-analyzer

# Run every hour at :05
5 * * * * azure-monitor /usr/local/bin/azure-storage-cost-analyzer --config /etc/azure-storage-cost-analyzer/config.conf unused-report --quiet 2>&1 | logger -t azure-storage-cost-analyzer

# Daily detailed report
0 8 * * * azure-monitor /usr/local/bin/azure-storage-cost-analyzer --config /etc/azure-storage-cost-analyzer/config.conf unused-report --output-format json > /var/log/azure-storage-cost-analyzer/daily-$(date +\%Y\%m\%d).json

# LLD for Zabbix - every 6 hours
0 */6 * * * azure-monitor /usr/local/bin/azure-storage-cost-analyzer --zabbix-discovery subscriptions --output-format json --quiet
```

---

## Success Metrics

### KPIs

1. **Reliability**
   - Target: 99.9% successful executions
   - Metric: `success_rate = successful_runs / total_runs`

2. **Performance**
   - Target: Complete within 5 minutes for all subscriptions
   - Metric: `avg_execution_time < 300 seconds`

3. **Detection Speed**
   - Target: Detect waste within 1 hour of creation
   - Metric: `detection_lag < 60 minutes`

4. **Alert Accuracy**
   - Target: <5% false positives
   - Metric: `false_positive_rate < 0.05`

5. **Cost Savings**
   - Target: Identify and enable deletion of >$1000/month waste
   - Metric: `identified_savings >= $1000/month`

### Monitoring the Monitor

```
# Zabbix items to monitor the script itself:
azure.storage.script.last_run_timestamp      # When did it last run?
azure.storage.script.last_run_status         # Did it succeed?
azure.storage.script.execution_time_seconds  # How long did it take?
azure.storage.script.api_calls_count         # Azure API usage

# Triggers for script health:
- Script hasn't run in 90 minutes (should run hourly)
- Script failing for 3 consecutive runs
- Execution time > 10 minutes (performance degradation)
```

---

## Timeline & Phases

### Phase 1: Core Foundation (Week 1-2)
**Duration:** 10 days
**Resources:** 1 developer

**Deliverables:**
- [ ] JSON output format
- [ ] Silent/quiet modes
- [ ] Exit codes
- [ ] Auto date calculation
- [ ] Config file support
- [ ] Basic unit tests

**Milestone:** Script can run unattended with JSON output

---

### Phase 2: Zabbix Integration (Week 3)
**Duration:** 5 days
**Resources:** 1 developer + 1 DevOps

**Deliverables:**
- [ ] Zabbix sender integration
- [ ] Zabbix template
- [ ] Basic metrics sending
- [ ] Threshold alerts
- [ ] Zabbix triggers configured

**Milestone:** Metrics flowing to Zabbix, alerts working

---

### Phase 3: Multi-Subscription (Week 4)
**Duration:** 5 days
**Resources:** 1 developer

**Deliverables:**
- [ ] Subscription iteration logic
- [ ] Aggregated reporting
- [ ] Batch Zabbix Sender (performance optimization)
- [ ] LLD for subscriptions
- [ ] Per-subscription metrics

**Milestone:** All subscriptions scanned automatically

---

### Phase 4: Production Hardening (Week 5)
**Duration:** 5 days
**Resources:** 1 developer + 1 DevOps

**Deliverables:**
- [ ] Structured logging
- [ ] Enhanced error handling
- [ ] Documentation
- [ ] Deployment automation

**Milestone:** Production-ready, deployed to prod

---

### Phase 5: Extended Features (Week 6) - Optional
**Duration:** 5 days
**Resources:** 1 developer

**Deliverables:**
- [ ] Parallel execution (ONLY for 30+ subscriptions)
- [ ] Full LLD support (disks, snapshots, RGs)
- [ ] Webhook notifications
- [ ] Email reports
- [ ] Advanced filtering
- [ ] Custom report templates

**Milestone:** Enhanced monitoring capabilities

---

#### 5.1 Parallel Execution (Optional - Advanced Use Case Only)

**Priority:** P3 (Low - Optional)

⚠️ **WARNING: ONLY implement if you have 30+ subscriptions AND understand the risks!**

**When to Use:**
- ✅ 30+ Azure subscriptions
- ✅ Execution time > 90 minutes with sequential processing
- ✅ Advanced bash scripting expertise available
- ✅ Able to handle complex debugging scenarios

**When NOT to Use:**
- ❌ < 30 subscriptions (sequential is fast enough)
- ❌ Limited bash expertise
- ❌ Need simple, maintainable solution
- ❌ First-time implementation

**Architecture: Parallel Scanning + Sequential Zabbix Sending**

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: PARALLEL Data Collection (Fast)                    │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │ Sub 1      │  │ Sub 2      │  │ Sub 3      │           │
│  │ Scan disks │  │ Scan disks │  │ Scan disks │           │
│  │ & costs    │  │ & costs    │  │ & costs    │           │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘           │
│        │                │                │                   │
│        └────────────────┴────────────────┘                   │
│                         ↓                                    │
│                  Save to files:                              │
│                  /tmp/sub1.json                              │
│                  /tmp/sub2.json                              │
│                  /tmp/sub3.json                              │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ Phase 2: SEQUENTIAL Aggregation & Zabbix Send (Safe)        │
│                                                              │
│  Read all JSON files → Aggregate metrics                    │
│  ↓                                                           │
│  Create Zabbix batch file                                   │
│  ↓                                                           │
│  ONE zabbix_sender call                                     │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:**

```bash
# Phase 1: Parallel data collection
scan_subscription_to_file() {
    local sub_id="$1"
    local output_file="/tmp/azure_scan_${sub_id}.json"

    log INFO "Scanning subscription: $sub_id (PID: $$)"

    # Scan subscription and save to file
    local metrics=$(scan_single_subscription "$sub_id")

    # Save metrics to JSON file
    echo "$metrics" > "$output_file"

    log INFO "Completed subscription: $sub_id"
}

# Parallel execution with limit
parallel_scan_subscriptions() {
    local -a subscriptions=("$@")
    local max_parallel=5  # Limit to 5 concurrent scans
    local -a pids=()

    for sub_id in "${subscriptions[@]}"; do
        # Start background scan
        scan_subscription_to_file "$sub_id" &
        pids+=($!)

        # Limit concurrent jobs
        if [[ ${#pids[@]} -ge $max_parallel ]]; then
            # Wait for any job to finish
            wait -n "${pids[@]}" 2>/dev/null || true
            # Remove finished PIDs
            pids=($(jobs -r -p))
        fi
    done

    # Wait for all remaining jobs
    wait
}

# Phase 2: Sequential aggregation and Zabbix send
aggregate_and_send() {
    local -a subscriptions=("$@")
    local total_waste=0
    local total_disks=0

    # Read all JSON files (SEQUENTIAL - safe)
    for sub_id in "${subscriptions[@]}"; do
        local metrics_file="/tmp/azure_scan_${sub_id}.json"

        if [[ ! -f "$metrics_file" ]]; then
            log ERROR "Missing metrics for subscription: $sub_id"
            continue
        fi

        local metrics=$(cat "$metrics_file")

        # Aggregate
        total_waste=$(echo "$total_waste + $(echo $metrics | jq -r '.waste')" | bc)
        total_disks=$(( total_disks + $(echo $metrics | jq -r '.disks') ))

        # Clean up temp file
        rm -f "$metrics_file"
    done

    # Create batch file and send (ONE call)
    local batch_file=$(create_zabbix_batch_file)
    send_batch_to_zabbix "$batch_file"
}

# Main workflow
main() {
    # Phase 1: Parallel scanning (FAST)
    log INFO "Starting parallel data collection for ${#SUBSCRIPTIONS[@]} subscriptions"
    parallel_scan_subscriptions "${SUBSCRIPTIONS[@]}"

    # Phase 2: Sequential aggregation and send (SAFE)
    log INFO "Aggregating results and sending to Zabbix"
    aggregate_and_send "${SUBSCRIPTIONS[@]}"
}
```

**Risks & Mitigations:**

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Azure API Rate Limiting** | High | Limit to 5 concurrent scans, add delays |
| **File system race conditions** | Medium | Use PID in filenames, proper locking |
| **Partial failures** | High | Check for missing files, retry logic |
| **Debugging complexity** | High | Comprehensive logging with PIDs |
| **Resource exhaustion** | Medium | Monitor memory/CPU, limit concurrency |

**Performance Comparison:**

```
Scenario: 50 subscriptions, 5 minutes per subscription

SEQUENTIAL:
50 × 5 min = 250 minutes (4 hours 10 minutes)

PARALLEL (5 concurrent):
50 ÷ 5 × 5 min = 50 minutes

Speedup: 5x faster ⚡

But: Added complexity, debugging difficulty, risk of failures
```

**Recommendation:**

```
Subscriptions    Approach                Reason
─────────────────────────────────────────────────────────────
< 10            Sequential              Fast enough (<30 min)
10-20           Sequential              Acceptable (<60 min)
20-30           Sequential + Batch      Good balance
30+             Parallel (optional)     Only if time critical

Default: ALWAYS start with sequential.
Only add parallel if proven necessary.
```

**Exit Criteria for Parallel:**

Before implementing parallel execution, answer YES to ALL:

- [ ] We have 30+ Azure subscriptions
- [ ] Sequential execution takes >90 minutes
- [ ] We need faster execution (hourly cron requires <60 min)
- [ ] Team has advanced bash expertise
- [ ] We have time for debugging complex issues
- [ ] Sequential + Batch Zabbix Sender was tried first

If ANY answer is NO → DO NOT implement parallel execution.

**Note:** Most organizations will NEVER need this. Sequential + Batch Zabbix Sender is sufficient for 99% of use cases.

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Azure API rate limiting** | Medium | High | Implement caching, exponential backoff, spread requests |
| **Zabbix sender failures** | Low | Medium | Retry logic, fallback to file output, alerting on failures |
| **Multi-subscription timeout** | Medium | Medium | Parallel execution, configurable timeouts, partial results |
| **Config file security** | Low | High | Restrict permissions (600), no secrets in config, use Azure MSI |
| **Log disk space** | Medium | Low | Log rotation, compression, cleanup policies |
| **Breaking changes in Azure API** | Low | High | Version pinning, API compatibility tests, graceful degradation |
| **Zabbix server downtime** | Low | Medium | Queue metrics locally, retry on recovery, file backup |
| **Permission issues** | Medium | High | Service principal with minimal permissions, proper error codes |

---

## Appendix

### A. Sample Zabbix Configuration

**Import Template:**
```bash
# Export template from Zabbix UI:
Configuration → Templates → Export → azure_storage_monitor_template.xml

# Import via CLI:
zabbix_get -s zabbix-server -k template.import[azure_storage_monitor_template.xml]
```

### B. Sample Cron Output

```bash
# Normal execution (quiet mode)
$ /usr/local/bin/azure-storage-cost-analyzer --config /etc/azure-storage-cost-analyzer/config.conf unused-report --quiet
$ echo $?
0

# With warning threshold exceeded
$ /usr/local/bin/azure-storage-cost-analyzer --config /etc/azure-storage-cost-analyzer/config.conf unused-report --quiet
$ echo $?
10
```

### C. Testing Checklist

- [ ] Unit tests for all core functions
- [ ] Integration tests with mock Azure API
- [ ] Zabbix sender integration test
- [ ] Multi-subscription test (3+ subscriptions)
- [ ] Performance test (100+ disks)
- [ ] Error handling test (network failures, auth failures)
- [ ] Exit code validation for all scenarios
- [ ] Config file parsing with various formats
- [ ] Log rotation test

### D. Documentation Links

- Azure Cost Management API: https://learn.microsoft.com/en-us/rest/api/cost-management/
- Azure Resource Graph: https://learn.microsoft.com/en-us/azure/governance/resource-graph/
- Zabbix Sender Protocol: https://www.zabbix.com/documentation/current/en/manpages/zabbix_sender
- Zabbix LLD: https://www.zabbix.com/documentation/current/en/manual/discovery/low_level_discovery

---

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-22 | DevOps Team | Initial PRD |

---

**Approval:**

- [ ] Product Owner: _______________  Date: _______
- [ ] Tech Lead: _______________  Date: _______
- [ ] DevOps Lead: _______________  Date: _______

