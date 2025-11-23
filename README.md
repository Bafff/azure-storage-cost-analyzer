# Azure Storage Cost Analyzer

CLI tooling to discover and quantify wasted Azure storage spend (unattached disks and snapshots), with optional Zabbix metrics and Azure DevOps pipeline automation.

## Key Features
- Multi-subscription scanning with aggregated JSON/Zabbix/Text output.
- Batch cost queries via Azure Cost Management REST API for speed and reliability.
- Tag-based exclusion (`Resource-Next-Review-Date`) to defer approved resources until a review date.
- Zabbix sender integration (metrics and LLD) and ready-to-run Azure Pipelines YAML.
- Configurable via INI (`azure-storage-monitor.conf.example`) or CLI flags.

## Quick Usage
```bash
# One-time: make executable
chmod +x azure-storage-cost-analyzer.sh

# List disks (no costs)
./azure-storage-cost-analyzer.sh list-disks "<SUBSCRIPTION_ID>"

# Unused resources (disks + snapshots) last 30 days
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions "<SUBSCRIPTION_ID>" \
  --days 30 \
  --output-format json

# Multi-subscription scan with Zabbix send
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30 \
  --output-format json \
  --zabbix-send \
  --zabbix-server monitoring.example.com \
  --zabbix-host azure-storage-monitor
```

## Prerequisites
- Azure CLI authenticated (`az login`)
- `jq`, `bc`, `timeout`/`gtimeout`
- Optional: `zabbix_sender` for metrics
- Permissions per subscription: at least `Reader` + `Cost Management Reader` (the script validates before running)

## Configuration
Copy `azure-storage-monitor.conf.example` and adjust sections `[azure]`, `[output]`, `[zabbix]`, `[thresholds]`, `[advanced]`, `[exclusions]`. CLI flags override config values.

## Tests
Static sanity tests live in the `tests/` directory:
- `tests/test-phase1-features.sh`
- `tests/test-phase2-zabbix.sh`
- `tests/test-phase3-multi-subscription.sh`

They run in CI via `.github/workflows/lint.yml`. Add cloud-backed tests separately when credentials are available.

## Pipeline
`azure-pipelines-storage-monitor.yml` runs the analyzer daily on Azure DevOps agents and fails the build if the script fails. Update the service connection name and Zabbix variables before enabling.
