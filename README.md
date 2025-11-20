# Sentry PostgreSQL Scripts

This directory contains automation scripts for Sentry PostgreSQL maintenance operations.

## 📁 Available Scripts

### Azure Storage Cost Analysis

#### `azure-storage-cost-analyzer.sh` ⭐ **RECOMMENDED**
**Enhanced Script** - Flexible cost analysis for any Azure resources (disks, snapshots, bulk analysis).

**Usage:**
```bash
# Make executable (first time)
chmod +x azure-storage-cost-analyzer.sh

# Analyze specific disk by name (auto-expands to full resource ID)
./azure-storage-cost-analyzer.sh pvc-596782ff-6859-4334-992c-fa519fa2f501 "" "2025-08-01T00:00:00+00:00" "2025-08-31T23:59:59+00:00"

# Analyze ALL disks in subscription
./azure-storage-cost-analyzer.sh all-disks "" "2025-08-01T00:00:00+00:00" "2025-08-31T23:59:59+00:00"

# Analyze ALL snapshots in subscription  
./azure-storage-cost-analyzer.sh all-snapshots "" "2025-08-01T00:00:00+00:00" "2025-08-31T23:59:59+00:00"

# List available resources (no cost analysis)
./azure-storage-cost-analyzer.sh list-disks
./azure-storage-cost-analyzer.sh list-snapshots

# Historical 6-month analysis (PostgreSQL disk)
./azure-storage-cost-analyzer.sh historical
```

#### `azure-storage-cost-analysis.sh` 
**Original Script** - Single resource cost analysis (legacy, kept for backward compatibility).

**Usage:**
```bash
# Query specific month with defaults (PostgreSQL PVC)
./azure-storage-cost-analysis.sh "" "" "2025-08-01T00:00:00+00:00" "2025-08-31T23:59:59+00:00"

# Run historical analysis for last 6 months
./azure-storage-cost-analysis.sh historical
```

**Features:**
- **REST API Based**: Uses Azure Cost Management API directly (az costmanagement query was removed)
- **Detailed Breakdown**: Separates storage capacity costs from transaction costs
- **Historical Analysis**: Built-in support for multi-month cost analysis
- **Resource Filtering**: Queries costs for specific Azure managed disks
- **Cost Categorization**: Automatically categorizes E4 LRS (transactions) vs E30/E40/E50/E60 (storage)

**Prerequisites:**
- Azure CLI installed and logged in (`az login`)
- Access to the target subscription
- jq installed for JSON processing
- **Required Azure Permissions:**
  - **Reader** role (or higher: Contributor, Owner) on the subscription
  - **Cost Management Reader** role for accessing cost data
  - The script validates these permissions before execution

**Output:**
- Storage vs Transaction cost breakdown
- Monthly historical analysis
- Raw JSON saved to `/tmp/azure-cost-query-result.json`

### Zabbix Maintenance Management (Zabbix 6.0+ Compatible)

#### `zabbix6-maintenance.ps1`
**Main Script** - Creates or removes maintenance windows in both Azure and RackSpace Zabbix instances with intelligent credential prompting.

**Usage:**
```powershell
# Create 30-minute maintenance windows (will prompt for credentials intelligently)
./zabbix6-maintenance.ps1 -Action create -Duration 30

# Remove maintenance windows 
./zabbix6-maintenance.ps1 -Action remove

# Custom duration
./zabbix6-maintenance.ps1 -Action create -Duration 60
```

**Credential Flow:**
- Prompts for Azure Zabbix credentials first
- Asks "Use same credentials for Rackspace? (Y/N) [Y]"  
- Press Enter to use same credentials, or N for different ones

**Maintenance Names Created:**
- Azure: "Sentry Postgres DB PV Expanding - YYYY-MM-DD HH:MM"
- RackSpace: "Sentry Postgres DB PV Expanding - YYYY-MM-DD HH:MM"

#### `test-zabbix6-connection.ps1`
**Testing Script** - Tests Zabbix 6.0+ API connectivity and authentication.

**Usage:**
```powershell
# Test connection to Azure Zabbix
./test-zabbix6-connection.ps1 zbx-az.as.arkadiumhosted.com username password

# Test connection to RackSpace Zabbix  
./test-zabbix6-connection.ps1 zbx-rs.as.arkadiumhosted.com username password
```

## 🔧 Prerequisites

### PowerShell Version
- **Windows**: PowerShell 5.1+ (built-in)
- **macOS/Linux**: PowerShell Core 7.0+ (`brew install --cask powershell`)

### Zabbix Compatibility
- **Zabbix 6.0+**: Uses "username" parameter (supported)
- **Zabbix 5.x and earlier**: Not supported (uses deprecated "user" parameter)

### Network Access
- Access to both Zabbix instances:
  - Azure: https://zbx-az.as.arkadiumhosted.com
  - RackSpace: https://zbx-rs.as.arkadiumhosted.com
- HTTPS connectivity with self-signed certificate support

## 🛡️ Security Features

### Built-in Security
- **Secure credential input** using `Read-Host -AsSecureString`
- **Self-signed certificate handling** for both PowerShell Core and Windows PowerShell
- **No credential storage** - prompts each time for security

### Best Practices
```powershell
# Never store passwords in plain text
# Always use the interactive prompts provided by the scripts
```

## 🔍 Troubleshooting

### Common Issues

**"unexpected parameter 'user'" Error:**
- This indicates Zabbix 5.x or earlier (not supported)
- Use the new `zabbix6-maintenance.ps1` script for Zabbix 6.0+

**Connection Failed:**
- Verify Zabbix URLs are accessible
- Check username/password credentials  
- Ensure proper network access to Zabbix instances

**Host Not Found:**
- Azure: Looks for hosts matching pattern `*sentry.arkadiumhosted.com*`
- RackSpace: Looks for hosts matching pattern `*internal-aks-dev*`
- Check if host names match these patterns in your Zabbix

**PowerShell Execution Policy:**
```powershell
# If scripts won't run due to execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**SSL/TLS Issues:**
- Scripts automatically handle self-signed certificates
- No manual SSL configuration needed

## 📋 Script Features

### `zabbix6-maintenance.ps1` Features:
- **Zabbix 6.0+ API compatibility** using "username" parameter
- **Intelligent credential prompting** (asks if same creds for both servers)
- **Dual server management** (Azure + RackSpace simultaneously)
- **Flexible duration** (default 30 minutes, configurable)
- **Pattern-based removal** for cleanup operations
- **Comprehensive error handling** with clear error messages
- **Cross-platform support** (Windows, macOS, Linux)

### `test-zabbix6-connection.ps1` Features:
- **API version detection** shows Zabbix version
- **Host count validation** confirms API access
- **Sample host listing** for verification
- **Detailed error reporting** for troubleshooting

## 🔗 Integration with PV Resize Procedure

These scripts are integrated into the [PV Resize Procedure](../docs/runbooks/pv-resize-procedure.md):

```powershell
# Step 1: Create maintenance windows before resize
./scripts/zabbix6-maintenance.ps1 -Action create -Duration 30

# Step 2: Perform PV resize operations
# ... resize operations ...

# Step 3: Remove maintenance windows after completion
./scripts/zabbix6-maintenance.ps1 -Action remove
```

## 📊 Zabbix Instances

### Azure Zabbix  
- **URL**: https://zbx-az.as.arkadiumhosted.com
- **Monitors**: sentry.arkadiumhosted.com hosts
- **Purpose**: Application-level monitoring
- **Version**: 6.0+ (confirmed via API testing)

### RackSpace Zabbix
- **URL**: https://zbx-rs.as.arkadiumhosted.com  
- **Monitors**: internal-aks-dev infrastructure
- **Purpose**: Infrastructure-level monitoring
- **Version**: 6.0+ (confirmed via API testing)

## 🔗 Related Documentation

- **[PV Resize Procedure](../docs/runbooks/pv-resize-procedure.md)** - Complete PostgreSQL PV resize guide
- **[Main README](../README.md)** - Project overview and navigation
- **[Progress Status](../PROGRESS.md)** - Current project status

---

*These scripts have been updated for Zabbix 6.0+ compatibility and tested against both Azure and RackSpace Zabbix instances. The old psbbix-based scripts have been removed due to API incompatibility.*