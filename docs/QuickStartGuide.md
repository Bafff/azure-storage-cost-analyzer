# Quick Start Guide - Azure Storage Cost Analyzer

## Fast Commands

### 1) Unattached Disks Only (fast)
```bash
./azure-storage-cost-analyzer.sh unattached-disks-only \
  --subscriptions "<SUBSCRIPTION_ID>" \
  --days 30
```
Runs in ~20-30 seconds; skips snapshots for speed.

### 2) Full Unused Report (disks + snapshots)
```bash
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions "<SUBSCRIPTION_ID>" \
  --days 30
```
Use when snapshot counts are reasonable (<50); large snapshot sets will take longer.

### 3) Lists Only (no cost analysis)
```bash
./azure-storage-cost-analyzer.sh list-disks "<SUBSCRIPTION_ID>"
./azure-storage-cost-analyzer.sh list-snapshots "<SUBSCRIPTION_ID>"
```

## Multi-Subscription Example
```bash
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --output-format json
```

## With Exclusions
```bash
# Exclude resources with future review dates AND specific resource groups
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --skip-tagged \
  --exclude-rgs "databricks-rg,temp-rg,velero-backup-rg"
```

Resources in excluded RGs younger than 60 days are excluded from alerts.
Resources older than 60 days are included as potential anomalies.

## Enable Cost Management Validation
```bash
# By default, Cost Management validation is skipped. Enable it when needed:
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --validate-costs
```

## Notes
- Replace `<SUBSCRIPTION_ID>` with your target subscription or use `all` for all accessible subscriptions.
- For Zabbix sending, add `--zabbix-send --zabbix-server <host> --zabbix-host azure-storage-cost-analyzer`.
- Tag-based exclusion: set `Resource-Next-Review-Date=YYYY.MM.DD` on a disk/snapshot to suppress alerts until that date (use `--skip-tagged` flag).
- RG exclusion: use `--exclude-rgs "rg1,rg2"` to exclude ephemeral resource groups (default 60-day age threshold).
- Works on both Linux and macOS (bash 3.2+ compatible).
