# Quick Start Guide - Azure Storage Cost Analyzer

## Fast Commands

### 1) Unattached Disks Only (fast)
```bash
./azure-storage-cost-analyzer.sh unattached-disks-only \
  "<SUBSCRIPTION_ID>" \
  "2025-09-01T00:00:00+00:00" \
  "2025-10-13T23:59:59+00:00"
```
Runs in ~20-30 seconds; skips snapshots for speed.

### 2) Full Unused Report (disks + snapshots)
```bash
./azure-storage-cost-analyzer.sh unused-report \
  "<SUBSCRIPTION_ID>" \
  "2025-09-01T00:00:00+00:00" \
  "2025-10-13T23:59:59+00:00"
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
  --output-format json \
  --quiet
```

## Notes
- Replace `<SUBSCRIPTION_ID>` with your target subscription.
- For Zabbix sending, add `--zabbix-send --zabbix-server <host> --zabbix-host azure-storage-monitor`.
- Tag-based exclusion: set `Resource-Next-Review-Date=YYYY.MM.DD` on a disk/snapshot to suppress alerts until that date (when `exclude_pending_review=true` in config).
