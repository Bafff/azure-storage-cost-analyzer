#!/bin/bash

# Enhanced Azure Storage Cost Analysis Script
# Created: 2025-09-15
# Purpose: Query Azure Cost Management API for storage costs of any Azure resources
#
# IMPORTANT: This script uses Azure REST API because az_with_timeout costmanagement query
# command was removed in extension version 0.2.1
#
# PERFORMANCE: For subscription-wide queries, this script automatically uses Azure Resource
# Graph API which is significantly faster than traditional az_with_timeout disk/snapshot list commands.
# Resource group specific queries use traditional az_with_timeout CLI commands.
#
# CONFIGURATION: Supports INI-style configuration files for centralized settings management.
# Use --config flag or place config at: /etc/azure-storage-monitor/config.conf,
# ~/.azure-storage-monitor.conf, or ./azure-storage-monitor.conf
#
# Usage:
#   ./azure-storage-cost-analyzer.sh [RESOURCE_IDENTIFIER] [SUBSCRIPTION_ID] [START_DATE] [END_DATE] [OPTIONS]

set -euo pipefail

# Default values
DEFAULT_SUBSCRIPTION_ID="03d76f78-4676-4116-b53a-162546996207"
DEFAULT_RESOURCE_GROUP="MC_internal-aks-dev-rg_internal-aks-dev_centralus"
DEFAULT_PG_DISK="pvc-596782ff-6859-4334-992c-fa519fa2f501"

# Configuration file variables (will be populated by load_config)
CONFIG_FILE=""
CONFIG_SUBSCRIPTIONS=""
CONFIG_RESOURCE_GROUP=""
CONFIG_DATE_RANGE_DAYS=""
CONFIG_INCLUDE_ATTACHED=""
CONFIG_OUTPUT_FORMAT=""
CONFIG_VERBOSITY=""
CONFIG_ZABBIX_ENABLED=""
CONFIG_ZABBIX_SERVER=""
CONFIG_ZABBIX_PORT=""
CONFIG_ZABBIX_HOSTNAME=""
CONFIG_ZABBIX_AUTO_SEND=""
CONFIG_THRESHOLD_WARNING_MONTHLY=""
CONFIG_THRESHOLD_CRITICAL_MONTHLY=""
CONFIG_THRESHOLD_WARNING_DISK_COUNT=""
CONFIG_THRESHOLD_CRITICAL_DISK_COUNT=""
CONFIG_SORT_BY=""
CONFIG_REVIEW_DATE_TAG_NAME=""
CONFIG_REVIEW_DATE_FORMAT=""
CONFIG_EXCLUDE_PENDING_REVIEW=""

# Exit codes (standardized for monitoring integration)
readonly EXIT_SUCCESS=0           # Success - no issues found or operation completed successfully
readonly EXIT_CONFIG_ERROR=2      # Invalid arguments or configuration error
readonly EXIT_WARNING=10          # Warning threshold exceeded (monitoring alert level)
readonly EXIT_CRITICAL=11         # Critical threshold exceeded (monitoring alert level)
readonly EXIT_PARTIAL_FAILURE=21  # Partial failure (some subscriptions failed, others succeeded)
readonly EXIT_API_ERROR=3         # Azure API temporary failure
# Verbosity level (can be set via --silent, --quiet, --verbose, --debug or CONFIG_VERBOSITY)
# Levels: silent (no output except errors), quiet (summary only), normal (default), verbose/debug (detailed)
VERBOSITY_LEVEL="normal"

# Azure CLI timeout in seconds
AZURE_CLI_TIMEOUT=60

# Function to execute Azure CLI with timeout
az_with_timeout() {
    local timeout_seconds="${AZURE_CLI_TIMEOUT:-60}"

    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" az "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$timeout_seconds" az "$@"
    else
        az "$@"
    fi

    local exit_code=$?
    if [[ $exit_code -eq 124 || $exit_code -eq 137 ]]; then
        echo "ERROR: Azure CLI timed out after ${timeout_seconds}s" >&2
        return 1
    fi
    return $exit_code
}

# ============================================================================
# DEPENDENCY VALIDATION
# ============================================================================

# Function to check for required dependencies before script execution
# This prevents the script from failing 10 minutes into execution
check_dependencies() {
    local missing_deps=()
    local all_deps=("az" "jq" "bc")

    # Check for timeout command (used by az_with_timeout)
    # Note: timeout is optional but recommended for better error handling
    if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
        echo "Warning: 'timeout' command not found. Azure CLI calls will not have timeout protection." >&2
        echo "Install 'coreutils' package (or 'gtimeout' on macOS) for better error handling." >&2
    fi

    # Check each required dependency
    for dep in "${all_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "ERROR: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "" >&2
        echo "Please install the missing tools:" >&2

        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                az)
                    echo "  - Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" >&2
                    ;;
                jq)
                    echo "  - jq (JSON processor): https://stedolan.github.io/jq/download/" >&2
                    echo "    Ubuntu/Debian: sudo apt-get install jq" >&2
                    echo "    macOS: brew install jq" >&2
                    echo "    RHEL/CentOS: sudo yum install jq" >&2
                    ;;
                bc)
                    echo "  - bc (calculator): Usually included in base system" >&2
                    echo "    Ubuntu/Debian: sudo apt-get install bc" >&2
                    echo "    macOS: brew install bc" >&2
                    echo "    RHEL/CentOS: sudo yum install bc" >&2
                    ;;
            esac
        done

        return 1
    fi

    # Verify Azure CLI is logged in
    if ! az_with_timeout account show >/dev/null 2>&1; then
        echo "ERROR: Azure CLI is not logged in or configured." >&2
        echo "Please run: az login" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# AZURE PERMISSION VALIDATION
# ============================================================================

# Function to validate Azure permissions for a subscription
# Args: subscription_id
# Returns: 0 if permissions are valid, 1 otherwise
validate_azure_permissions() {
    local subscription_id="$1"
    local current_user
    local has_reader_role=false
    local has_cost_access=false

    log_verbose "Validating Azure permissions for subscription: $subscription_id"

    # Get current user/service principal
    current_user=$(az_with_timeout account show --query 'user.name' -o tsv 2>/dev/null)
    if [[ -z "$current_user" ]]; then
        log_progress "ERROR: Failed to get current Azure user"
        return 1
    fi

    log_verbose "Checking permissions for user: $current_user"

    # Check for Reader role or higher (Contributor, Owner)
    local role_assignments
    role_assignments=$(az_with_timeout role assignment list \
        --assignee "$current_user" \
        --subscription "$subscription_id" \
        --query "[?scope=='/subscriptions/${subscription_id}' || starts_with(scope, '/subscriptions/${subscription_id}/')].roleDefinitionName" \
        -o tsv 2>/dev/null)

    if [[ -n "$role_assignments" ]]; then
        if echo "$role_assignments" | grep -qiE '(Reader|Contributor|Owner|Cost Management Reader)'; then
            has_reader_role=true
            log_verbose "✓ Found required role assignment"
        fi
    fi

    if [[ "$has_reader_role" == "false" ]]; then
        log_progress "ERROR: User '$current_user' does not have Reader role or higher on subscription '$subscription_id'"
        log_progress "Required: At least 'Reader' role on the subscription"
        return 1
    fi

    # Validate Cost Management access by attempting a simple cost query
    log_verbose "Validating Cost Management access..."
    local yesterday today cost_query_result
    yesterday=$(date -u -d "yesterday" '+%Y-%m-%d' 2>/dev/null || date -u -v-1d '+%Y-%m-%d' 2>/dev/null)
    today=$(date -u '+%Y-%m-%d')

    if cost_query_result=$(az_with_timeout costmanagement query \
        --type "ActualCost" \
        --dataset-aggregation "{\"totalCost\":{\"name\":\"PreTaxCost\",\"function\":\"Sum\"}}" \
        --dataset-grouping name="ResourceId" type="Dimension" \
        --timeframe "Custom" \
        --time-period from="$yesterday" to="$today" \
        --scope "/subscriptions/$subscription_id" \
        --query "rows" \
        -o tsv 2>/dev/null); then
        has_cost_access=true
        log_verbose "✓ Cost Management access validated"
    else
        log_progress "ERROR: User '$current_user' does not have Cost Management access on subscription '$subscription_id'"
        log_progress "Required: Cost Management Reader role or equivalent permissions"
        log_progress "Hint: Grant 'Cost Management Reader' role with:"
        log_progress "  az role assignment create --assignee '$current_user' --role 'Cost Management Reader' --scope '/subscriptions/$subscription_id'"
        return 1
    fi

    log_verbose "✓ All required permissions validated for subscription: $subscription_id"
    return 0
}

# Output format (can be set via --output-format or CONFIG_OUTPUT_FORMAT)
# Formats: text (default), json, zabbix
OUTPUT_FORMAT="text"

# ============================================================================
# VERBOSITY AND LOGGING FUNCTIONS
# ============================================================================

# Function to log informational messages (respects verbosity level)
# Usage: log_info "message"
log_info() {
    [[ "$VERBOSITY_LEVEL" == "silent" ]] && return
    echo "$@"
}

# Function to log verbose/debug messages (only in verbose mode)
# Usage: log_verbose "debug message"
log_verbose() {
    [[ "$VERBOSITY_LEVEL" == "verbose" || "$VERBOSITY_LEVEL" == "debug" ]] && echo "$@" >&2
}

# Function to log progress messages to stderr (respects verbosity)
# Usage: log_progress "Loading..."
log_progress() {
    [[ "$VERBOSITY_LEVEL" == "silent" ]] && return
    echo "$@" >&2
}

# ============================================================================
# END VERBOSITY AND LOGGING
# ============================================================================

# ============================================================================
# OUTPUT FORMATTING FUNCTIONS
# ============================================================================

# Function to output report summary in JSON format
# Args: report_type total_cost total_count disk_count snapshot_count exit_code
output_json_summary() {
    local report_type="$1"
    local total_cost="$2"
    local total_count="$3"
    local disk_count="${4:-0}"
    local snapshot_count="${5:-0}"
    local exit_code="${6:-0}"

    cat <<EOF
{
  "report_type": "$report_type",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "subscription_id": "${subscription_id:-unknown}",
  "summary": {
    "total_cost_monthly": $total_cost,
    "total_cost_annual": $(echo "$total_cost * 12" | bc -l),
    "total_resources": $total_count,
    "disk_count": $disk_count,
    "snapshot_count": $snapshot_count
  },
  "exit_code": $exit_code,
  "thresholds": {
    "warning_monthly": ${CONFIG_THRESHOLD_WARNING_MONTHLY:-null},
    "critical_monthly": ${CONFIG_THRESHOLD_CRITICAL_MONTHLY:-null},
    "warning_disk_count": ${CONFIG_THRESHOLD_WARNING_DISK_COUNT:-null},
    "critical_disk_count": ${CONFIG_THRESHOLD_CRITICAL_DISK_COUNT:-null}
  }
}
EOF
}

# Function to output in Zabbix sender format
# Args: key value
output_zabbix_metric() {
    local key="$1"
    local value="$2"
    local hostname="${CONFIG_ZABBIX_HOSTNAME:-$(hostname)}"
    local timestamp=$(date +%s)

    echo "$hostname $key $timestamp $value"
}

# ============================================================================
# END OUTPUT FORMATTING
# ============================================================================

# ============================================================================
# AUTOMATIC DATE CALCULATION FUNCTIONS
# ============================================================================

# Function to calculate date range based on preset
# Args: preset (--days N, --last-month, --current-month)
# Returns: Sets global START_DATE and END_DATE variables
calculate_date_range() {
    local preset="$1"
    local param="${2:-}"

    case "$preset" in
        days)
            # Last N days
            local days="$param"
            if [[ ! "$days" =~ ^[0-9]+$ ]]; then
                echo "Error: --days requires a number" >&2
                return 1
            fi

            # End date: now (with timezone)
            END_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

            # Start date: N days ago
            if command -v gdate &>/dev/null; then
                # GNU date (Linux, or brew install coreutils on Mac)
                START_DATE="$(gdate -u -d "$days days ago" +"%Y-%m-%dT%H:%M:%SZ")"
            elif date -v-1d &>/dev/null 2>&1; then
                # BSD date (macOS default)
                START_DATE="$(date -u -v-"${days}"d +"%Y-%m-%dT%H:%M:%SZ")"
            else
                echo "Error: Unable to calculate dates (date command not supported)" >&2
                return 1
            fi
            ;;

        last-month)
            # Previous full month (1st to last day)
            if command -v gdate &>/dev/null; then
                # GNU date
                START_DATE="$(gdate -u -d 'last month' +"%Y-%m-01T00:00:00Z")"
                END_DATE="$(gdate -u -d "$(gdate -d 'last month' +%Y-%m-01) +1 month -1 day" +"%Y-%m-%dT23:59:59Z")"
            elif date -v-1d &>/dev/null 2>&1; then
                # BSD date (macOS)
                local last_month_first=$(date -u -v-1m -v1d +"%Y-%m-%dT00:00:00Z")
                START_DATE="$last_month_first"
                # Get last day of previous month
                local this_month_first=$(date -u -v1d +"%Y-%m-%d")
                END_DATE="$(date -u -j -v-1d -f "%Y-%m-%d" "$this_month_first" +"%Y-%m-%dT23:59:59Z")"
            else
                echo "Error: Unable to calculate dates (date command not supported)" >&2
                return 1
            fi
            ;;

        current-month)
            # Current month from 1st to now
            START_DATE="$(date -u +"%Y-%m-01T00:00:00Z")"
            END_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            ;;
        last-week)
            # Previous 7 days (equivalent to --days 7)
            calculate_date_range "days" 7
            return $?
            ;;
        yesterday)
            if command -v gdate &>/dev/null; then
                START_DATE="$(gdate -u -d 'yesterday' +"%Y-%m-%dT00:00:00Z")"
                END_DATE="$(gdate -u -d 'yesterday' +"%Y-%m-%dT23:59:59Z")"
            elif date -v-1d &>/dev/null 2>&1; then
                START_DATE="$(date -u -v-1d -v0H -v0M -v0S +"%Y-%m-%dT00:00:00Z")"
                END_DATE="$(date -u -v-1d -v23H -v59M -v59S +"%Y-%m-%dT23:59:59Z")"
            else
                echo "Error: Unable to calculate yesterday (date command not supported)" >&2
                return 1
            fi
            ;;

        *)
            echo "Error: Unknown date preset '$preset'" >&2
            return 1
            ;;
    esac

    log_verbose "Calculated date range: $START_DATE to $END_DATE"
    return 0
}

# ============================================================================
# END AUTOMATIC DATE CALCULATION
# ============================================================================

# Function to display usage
usage() {
    echo "Enhanced Azure Storage Cost Analysis Script"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                         RECOMMENDED USAGE (Easy!)                         ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Most common commands:"
    echo "  # Generate report for last 7 days"
    echo "  $0 unused-report --days 7"
    echo ""
    echo "  # Generate report for last 30 days with JSON output"
    echo "  $0 unused-report --days 30 --output-format json"
    echo ""
    echo "  # Filter by resource group"
    echo "  $0 unused-report --days 7 --resource-group \"MC_testing-aks-rg\""
    echo ""
    echo "  # Scan all subscriptions"
    echo "  $0 unused-report --days 7 --subscriptions all"
    echo ""
    echo "  # List all disks"
    echo "  $0 list-disks"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                            DETAILED USAGE                                 ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  unused-report          - Generate comprehensive report of unused resources"
    echo "  unattached-disks-only  - Analyze only unattached disks (faster)"
    echo "  list-disks             - List all disks (no cost analysis)"
    echo "  list-snapshots         - List all snapshots (no cost analysis)"
    echo "  zabbix-discovery       - Generate Zabbix LLD JSON (requires --zabbix-discovery)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Basic Examples:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  # Generate unused resources report for last 7 days"
    echo "  $0 unused-report --days 7"
    echo ""
    echo "  # Generate report for last 30 days"
    echo "  $0 unused-report --days 30"
    echo ""
    echo "  # Analyze last month (full calendar month)"
    echo "  $0 unused-report --last-month"
    echo ""
    echo "  # Analyze current month (1st to today)"
    echo "  $0 unused-report --current-month"
    echo ""
    echo "  # Fast mode - only unattached disks (no snapshots)"
    echo "  $0 unattached-disks-only --days 7"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Filtering & Sorting:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  # Filter by resource group (using flag)"
    echo "  $0 unused-report --days 7 --resource-group \"MC_testing-aks-rg\""
    echo ""
    echo "  # Filter by resource group (short form)"
    echo "  $0 unused-report --days 7 -g \"MC_testing-aks-rg\""
    echo ""
    echo "  # Include attached disks in analysis"
    echo "  $0 unused-report --days 7 --include-attached"
    echo ""
    echo "  # Sort by resource group"
    echo "  $0 unused-report --days 7 --sort-by-rg"
    echo ""
    echo "  # Sort by creation date (oldest first)"
    echo "  $0 unused-report --days 7 --sort-by-date"
    echo ""
    echo "  # Combine multiple options"
    echo "  $0 unused-report --days 30 -g \"MC_testing-aks-rg\" --include-attached --sort-by-rg"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Output Formats:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  # JSON output (for automation)"
    echo "  $0 unused-report --days 7 --output-format json"
    echo ""
    echo ""
    echo "  # Zabbix sender format"
    echo "  $0 unused-report --days 7 --output-format zabbix"
    echo ""
    echo "  # Text format (default)"
    echo "  $0 unused-report --days 7 --output-format text"
    echo ""
    echo "  # Quiet mode (minimal output)"
    echo "  $0 unused-report --days 7 --quiet"
    echo ""
    echo "  # Silent mode (no output, exit codes only)"
    echo "  $0 unused-report --days 7 --silent"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Multi-Subscription Flags:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  --subscriptions <list>      - Scan comma-separated subscription IDs or 'all'"
    echo "  --subscriptions-file <path> - Load subscription IDs from file"
    echo "  --exclude-subscriptions <l> - Exclude comma-separated subscription IDs"
    echo "  --output-format <fmt>       - Combine with multi-subscription mode (json|zabbix|text)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Multi-Subscription Examples:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  # Basic multi-subscription scan"
    echo "  $0 unused-report --days 7 --subscriptions all"
    echo ""
    echo "  # Exclude specific subscriptions"
    echo "  $0 unused-report --days 30 --subscriptions all --exclude-subscriptions \"test-sub-id\""
    echo ""
    echo "  # Use subscriptions list from a file"
    echo "  $0 unused-report --last-month --subscriptions-file /etc/azure-monitor/subscriptions.txt"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Zabbix Integration Flags:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  --zabbix-send               - Enable automatic metric submission"
    echo "  --zabbix-server <hostname>  - Target Zabbix server"
    echo "  --zabbix-port <port>        - Zabbix server port (default 10051)"
    echo "  --zabbix-host <hostname>    - Hostname used for metrics in Zabbix"
    echo "  --zabbix-config <path>      - Use zabbix_agentd.conf instead of server/port"
    echo "  --zabbix-discovery <type>   - Generate LLD JSON (subscriptions|disks|snapshots)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Zabbix Examples:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  # Generate discovery payload for Zabbix"
    echo "  $0 zabbix-discovery --zabbix-discovery subscriptions --output-format json"
    echo ""
    echo "  # Send metrics using explicit server and host"
    echo "  $0 unused-report --days 7 --output-format zabbix --zabbix-send \\"
    echo "     --zabbix-server monitoring.company.com --zabbix-host azure-storage-monitor"
    echo ""
    echo "  # Send metrics using agent config file"
    echo "  $0 unused-report --days 7 --output-format zabbix --zabbix-send \\"
    echo "     --zabbix-config /etc/zabbix/zabbix_agentd.conf"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "All Available Flags:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Date/Time:"
    echo "  --days <N>              - Analyze last N days (auto-calculate dates)"
    echo "  --last-month            - Analyze previous full month"
    echo "  --current-month         - Analyze current month (1st to today)"
    echo "  --last-week             - Analyze the last 7 days"
    echo "  --yesterday             - Analyze the previous calendar day"
    echo ""
    echo "Filtering:"
    echo "  --resource-group <name> - Filter by specific resource group"
    echo "  -g <name>               - Short form of --resource-group"
    echo "  --include-attached      - Include attached disks (default: only unattached)"
    echo ""
    echo "Sorting:"
    echo "  --sort-by-size          - Sort by size ascending (default)"
    echo "  --sort-by-rg            - Sort by Resource Group, then by size"
    echo "  --sort-by-date          - Sort by creation date (oldest first)"
    echo ""
    echo "Output:"
    echo "  --output-format <fmt>   - Output format: text (default), json, zabbix"
    echo "  --silent                - No output (exit codes only)"
    echo "  --quiet                 - Minimal output (summary only)"
    echo "  --verbose               - Detailed progress information"
    echo "  --debug                 - Same as --verbose"
    echo ""
    echo "Multi-Subscription:"
    echo "  --subscriptions <list>       - Scan multiple: 'all' or comma-separated IDs"
    echo "  --subscriptions-file <path>  - Read subscription IDs from file"
    echo "  --exclude-subscriptions <l>  - Exclude specific subscriptions"
    echo ""
    echo "Zabbix Integration:"
    echo "  --zabbix-send                    - Enable automatic sending to Zabbix"
    echo "  --zabbix-server <hostname>       - Zabbix server hostname"
    echo "  --zabbix-port <port>             - Zabbix server port (default: 10051)"
    echo "  --zabbix-host <hostname>         - Zabbix host name for metrics"
    echo "  --zabbix-config <path>           - Use Zabbix agent config file"
    echo "  --zabbix-discovery <type>        - Generate LLD JSON (subscriptions|disks|snapshots|resourcegroups)"
    echo ""
    echo "Thresholds:"
    echo "  --warning-threshold <usd>    - Warn when monthly cost exceeds amount"
    echo "  --critical-threshold <usd>   - Critical when monthly cost exceeds amount"
    echo "  --warning-disk-count <n>     - Warn when unattached disks reach count"
    echo "  --critical-disk-count <n>    - Critical when unattached disks reach count"
    echo ""
    echo "Configuration:"
    echo "  --config <path>         - Path to configuration file (INI format)"
    echo ""
    echo "Exit Codes:"
    echo "  0  - Success (no issues found or below thresholds)"
    echo "  2  - Configuration error (invalid arguments)"
    echo "  10 - Warning threshold exceeded"
    echo "  11 - Critical threshold exceeded"
    echo "  21 - Partial failure (multi-subscription context)"
    echo ""
    exit $EXIT_CONFIG_ERROR
}

# ============================================================================
# CONFIGURATION FILE SUPPORT
# ============================================================================

# Function to parse INI configuration file
# Sets global CONFIG_* variables based on file content
parse_config_file() {
    local config_file="$1"
    local section=""

    if [[ ! -f "$config_file" ]]; then
        echo "Warning: Configuration file not found: $config_file" >&2
        return 1
    fi

    if [[ ! -r "$config_file" ]]; then
        echo "Warning: Configuration file not readable: $config_file" >&2
        return 1
    fi

    # Read file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Check for section header [section]
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse key=value pairs
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Trim whitespace from key and value
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Remove quotes from value if present
            value=$(echo "$value" | sed 's/^["'\'']\(.*\)["'\'']$/\1/')

            # Map config keys to global variables based on section
            case "$section" in
                azure)
                    case "$key" in
                        subscriptions) CONFIG_SUBSCRIPTIONS="$value" ;;
                        resource_group) CONFIG_RESOURCE_GROUP="$value" ;;
                        date_range_days) CONFIG_DATE_RANGE_DAYS="$value" ;;
                        include_attached) CONFIG_INCLUDE_ATTACHED="$value" ;;
                    esac
                    ;;
                output)
                    case "$key" in
                        format) CONFIG_OUTPUT_FORMAT="$value" ;;
                        verbosity) CONFIG_VERBOSITY="$value" ;;
                    esac
                    ;;
                zabbix)
                    case "$key" in
                        enabled) CONFIG_ZABBIX_ENABLED="$value" ;;
                        server) CONFIG_ZABBIX_SERVER="$value" ;;
                        port) CONFIG_ZABBIX_PORT="$value" ;;
                        hostname) CONFIG_ZABBIX_HOSTNAME="$value" ;;
                        auto_send) CONFIG_ZABBIX_AUTO_SEND="$value" ;;
                    esac
                    ;;
                thresholds)
                    case "$key" in
                        warning_monthly) CONFIG_THRESHOLD_WARNING_MONTHLY="$value" ;;
                        critical_monthly) CONFIG_THRESHOLD_CRITICAL_MONTHLY="$value" ;;
                        warning_disk_count) CONFIG_THRESHOLD_WARNING_DISK_COUNT="$value" ;;
                        critical_disk_count) CONFIG_THRESHOLD_CRITICAL_DISK_COUNT="$value" ;;
                    esac
                    ;;
                advanced)
                    case "$key" in
                        sort_by) CONFIG_SORT_BY="$value" ;;
                    esac
                    ;;
                exclusions)
                    case "$key" in
                        review_date_tag_name) CONFIG_REVIEW_DATE_TAG_NAME="$value" ;;
                        review_date_format) CONFIG_REVIEW_DATE_FORMAT="$value" ;;
                        exclude_pending_review) CONFIG_EXCLUDE_PENDING_REVIEW="$value" ;;
                    esac
                    ;;
            esac
        fi
    done < "$config_file"

    return 0
}

# Function to find configuration file in priority order
# Returns the first found config file path, or empty string if none found
find_config_file() {
    local explicit_config="${1:-}"

    # Priority 1: Explicit --config path
    if [[ -n "$explicit_config" ]]; then
        if [[ -f "$explicit_config" ]]; then
            echo "$explicit_config"
            return 0
        else
            echo "Error: Specified config file not found: $explicit_config" >&2
            return 1
        fi
    fi

    # Priority 2: System-wide config
    if [[ -f "/etc/azure-storage-monitor/config.conf" ]]; then
        echo "/etc/azure-storage-monitor/config.conf"
        return 0
    fi

    # Priority 3: User-specific config
    if [[ -f "$HOME/.azure-storage-monitor.conf" ]]; then
        echo "$HOME/.azure-storage-monitor.conf"
        return 0
    fi

    # Priority 4: Local directory config
    if [[ -f "./azure-storage-monitor.conf" ]]; then
        echo "./azure-storage-monitor.conf"
        return 0
    fi

    # No config file found
    return 0
}

# Function to load configuration from file
# Accepts optional explicit config path
load_config() {
    local explicit_config="${1:-}"

    # Find config file
    local config_path
    config_path=$(find_config_file "$explicit_config")
    local find_result=$?

    # If find_config_file returned error (explicit file not found), propagate error
    if [[ $find_result -ne 0 ]]; then
        return 1
    fi

    # If no config found, that's OK - return success
    if [[ -z "$config_path" ]]; then
        return 0
    fi

    # Store the config file path for reference
    CONFIG_FILE="$config_path"

    # Parse the config file
    if parse_config_file "$config_path"; then
        log_verbose "Loaded configuration from: $config_path"
        return 0
    else
        echo "Warning: Failed to parse configuration file: $config_path" >&2
        return 1
    fi
}

# ============================================================================
# END CONFIGURATION FILE SUPPORT
# ============================================================================

# ============================================================================
# THRESHOLD CHECKING AND EXIT CODE DETERMINATION
# ============================================================================

# Function to check thresholds and return appropriate exit code
# Args: total_monthly_cost total_disk_count
# Returns: EXIT_SUCCESS, EXIT_WARNING, or EXIT_CRITICAL
check_thresholds() {
    local total_monthly_cost="${1:-0}"
    local total_disk_count="${2:-0}"

    # Get thresholds from config (with defaults)
    local warning_monthly="${CONFIG_THRESHOLD_WARNING_MONTHLY:-1000000}"  # Default: $1M (effectively disabled)
    local critical_monthly="${CONFIG_THRESHOLD_CRITICAL_MONTHLY:-10000000}"  # Default: $10M
    local warning_disk_count="${CONFIG_THRESHOLD_WARNING_DISK_COUNT:-1000000}"  # Default: 1M disks
    local critical_disk_count="${CONFIG_THRESHOLD_CRITICAL_DISK_COUNT:-10000000}"  # Default: 10M disks

    # Check critical thresholds first (highest priority)
    if (( $(echo "$total_monthly_cost >= $critical_monthly" | bc -l) )); then
        return $EXIT_CRITICAL
    fi

    if (( total_disk_count >= critical_disk_count )); then
        return $EXIT_CRITICAL
    fi

    # Check warning thresholds
    if (( $(echo "$total_monthly_cost >= $warning_monthly" | bc -l) )); then
        return $EXIT_WARNING
    fi

    if (( total_disk_count >= warning_disk_count )); then
        return $EXIT_WARNING
    fi

    # All thresholds OK
    return $EXIT_SUCCESS
}

# ============================================================================
# END THRESHOLD CHECKING
# ============================================================================

# ============================================================================
# TAG-BASED EXCLUSION FUNCTIONS
# ============================================================================

# Function to validate review date tag value
# Args: tag_value, expected_format
# Returns: 0 if valid, 1 if invalid
# Output: normalized date (YYYY-MM-DD) on stdout if valid
validate_review_date_tag() {
    local tag_value="$1"
    local expected_format="${2:-YYYY.MM.DD}"

    # Empty tag is invalid
    if [[ -z "$tag_value" ]]; then
        return 1
    fi

    # Validate format based on expected_format config
    local normalized_date
    case "$expected_format" in
        "YYYY.MM.DD")
            # Match format: 2025.12.30
            if [[ ! "$tag_value" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
                log_verbose "Invalid tag format: '$tag_value' (expected YYYY.MM.DD)"
                return 1
            fi
            # Normalize to YYYY-MM-DD for date comparison
            normalized_date=$(echo "$tag_value" | tr '.' '-')
            ;;
        "YYYY-MM-DD")
            # Match format: 2025-12-30
            if [[ ! "$tag_value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                log_verbose "Invalid tag format: '$tag_value' (expected YYYY-MM-DD)"
                return 1
            fi
            normalized_date="$tag_value"
            ;;
        *)
            log_verbose "Unknown date format in config: '$expected_format'"
            return 1
            ;;
    esac

    # Validate date components
    local year month day
    IFS='-' read -r year month day <<< "$normalized_date"

    # Basic range checks
    if (( year < 2000 || year > 2100 )); then
        log_verbose "Invalid year in tag: $year"
        return 1
    fi

    if (( month < 1 || month > 12 )); then
        log_verbose "Invalid month in tag: $month"
        return 1
    fi

    if (( day < 1 || day > 31 )); then
        log_verbose "Invalid day in tag: $day"
        return 1
    fi

    # Output normalized date
    echo "$normalized_date"
    return 0
}

# Function to compare review date with current date
# Args: review_date (YYYY-MM-DD format)
# Returns: 0 if future date, 1 if past/today
is_review_date_future() {
    local review_date="$1"

    # Get current date in YYYY-MM-DD format
    local current_date
    if command -v gdate &>/dev/null; then
        current_date=$(gdate -u +"%Y-%m-%d")
    else
        current_date=$(date -u +"%Y-%m-%d")
    fi

    # Compare dates (string comparison works for YYYY-MM-DD format)
    if [[ "$review_date" > "$current_date" ]]; then
        return 0  # Future date
    else
        return 1  # Past or today
    fi
}

# Function to check resource tag status and determine if it should be excluded
# Args: tags_json, tag_name, tag_format
# Returns: exit code
#   0 = include (no tag, invalid tag, or expired tag)
#   1 = exclude (valid future review date)
# Output: JSON object with tag status info
check_resource_tag_status() {
    local tags_json="$1"
    local tag_name="${2:-Resource-Next-Review-Date}"
    local tag_format="${3:-YYYY.MM.DD}"

    # Default response: include resource (no special tag status)
    local default_response='{"should_exclude":false,"tag_status":"none","review_date":"","is_valid":false,"is_future":false}'

    # Check if tag exclusion is disabled or tags_json is empty/null
    if [[ -z "$tag_name" ]] || [[ "$tags_json" == "null" ]] || [[ -z "$tags_json" ]]; then
        echo "$default_response"
        return 0
    fi

    # Extract tag value from tags JSON
    # Azure Resource Graph returns tags as an object: {"tagName": "tagValue"}
    local tag_value
    tag_value=$(echo "$tags_json" | jq -r --arg tagname "$tag_name" '.[$tagname] // empty' 2>/dev/null)

    # No tag found
    if [[ -z "$tag_value" ]] || [[ "$tag_value" == "null" ]]; then
        echo "$default_response"
        return 0
    fi

    # Tag exists - validate format
    local normalized_date
    if ! normalized_date=$(validate_review_date_tag "$tag_value" "$tag_format" 2>/dev/null); then
        # Invalid tag format
        echo '{"should_exclude":false,"tag_status":"invalid","review_date":"'"$tag_value"'","is_valid":false,"is_future":false}'
        return 0  # Include in alerts (invalid tag)
    fi

    # Valid tag - check if date is in future
    if is_review_date_future "$normalized_date"; then
        # Future date - exclude from alerts
        echo '{"should_exclude":true,"tag_status":"pending","review_date":"'"$normalized_date"'","is_valid":true,"is_future":true}'
        return 1  # Exclude from reports
    else
        # Past/today date - include in alerts (review overdue)
        echo '{"should_exclude":false,"tag_status":"expired","review_date":"'"$normalized_date"'","is_valid":true,"is_future":false}'
        return 0  # Include in alerts
    fi
}

# Function to filter resources array by tag status
# Args: resources_json, tag_name, tag_format, skip_tagged_mode, show_tagged_only_mode
# Returns: JSON object with filtered resources and statistics
# Output format:
# {
#   "resources": [...],  // Filtered resource array
#   "stats": {
#     "total": N,
#     "included": N,
#     "excluded_pending": N,
#     "excluded_expired": N,
#     "invalid_tags": N
#   }
# }
filter_resources_by_tags() {
    local resources_json="$1"
    local tag_name="${2:-}"
    local tag_format="${3:-YYYY.MM.DD}"
    local skip_tagged="${4:-false}"
    local show_tagged_only="${5:-false}"

    # If tag filtering is disabled, return all resources
    if [[ -z "$tag_name" ]]; then
        local total_count=$(echo "$resources_json" | jq 'length' 2>/dev/null || echo "0")
        echo "$resources_json" | jq --argjson total "$total_count" '{
            resources: .,
            stats: {
                total: $total,
                included: $total,
                excluded_pending: 0,
                excluded_expired: 0,
                invalid_tags: 0
            }
        }' 2>/dev/null
        return 0
    fi

    # Process each resource and annotate with tag status
    local annotated_json
    annotated_json=$(echo "$resources_json" | jq --arg tagname "$tag_name" --arg tagfmt "$tag_format" '
        map(
            . + {
                "TagStatus": (
                    if .Tags then
                        if .Tags[$tagname] then
                            {
                                "has_tag": true,
                                "tag_value": .Tags[$tagname],
                                "tag_name": $tagname
                            }
                        else
                            {
                                "has_tag": false,
                                "tag_value": null,
                                "tag_name": $tagname
                            }
                        end
                    else
                        {
                            "has_tag": false,
                            "tag_value": null,
                            "tag_name": $tagname
                        }
                    end
                )
            }
        )
    ' 2>/dev/null)

    # Now evaluate each resource's tag status using bash function
    local -a filtered_resources=()
    local total=0
    local excluded_pending=0
    local excluded_expired=0
    local invalid_tags=0
    local included=0

    while IFS= read -r resource; do
        ((total++))

        local tags_json=$(echo "$resource" | jq -c '.Tags // {}' 2>/dev/null)
        local tag_status_result
        tag_status_result=$(check_resource_tag_status "$tags_json" "$tag_name" "$tag_format" 2>/dev/null)

        local should_exclude=$(echo "$tag_status_result" | jq -r '.should_exclude' 2>/dev/null)
        local tag_status_type=$(echo "$tag_status_result" | jq -r '.tag_status' 2>/dev/null)
        local review_date=$(echo "$tag_status_result" | jq -r '.review_date' 2>/dev/null)

        # Annotate resource with detailed tag status
        resource=$(echo "$resource" | jq --argjson tagstatus "$tag_status_result" '. + {TagStatusDetail: $tagstatus}' 2>/dev/null)

        # Track statistics
        case "$tag_status_type" in
            "invalid")
                ((invalid_tags++))
                ;;
            "pending")
                ((excluded_pending++))
                ;;
            "expired")
                ((excluded_expired++))
                ;;
        esac

        # Apply filtering logic
        local include_resource=true

        if [[ "$skip_tagged" == "true" ]]; then
            # Skip resources with valid future review dates
            if [[ "$should_exclude" == "true" ]]; then
                include_resource=false
            fi
        fi

        if [[ "$show_tagged_only" == "true" ]]; then
            # Show only resources with tags (valid, invalid, or expired)
            if [[ "$tag_status_type" == "none" ]]; then
                include_resource=false
            fi
        fi

        if [[ "$include_resource" == "true" ]]; then
            filtered_resources+=("$resource")
            ((included++))
        fi
    done < <(echo "$annotated_json" | jq -c '.[]' 2>/dev/null)

    # Build output JSON
    local resources_array="["
    local first=true
    for res in "${filtered_resources[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            resources_array+=","
        fi
        resources_array+="$res"
    done
    resources_array+="]"

    # Return filtered resources with statistics
    echo "$resources_array" | jq --argjson total "$total" \
        --argjson included "$included" \
        --argjson pending "$excluded_pending" \
        --argjson expired "$excluded_expired" \
        --argjson invalid "$invalid_tags" '{
        resources: .,
        stats: {
            total: $total,
            included: $included,
            excluded_pending: $pending,
            excluded_expired: $expired,
            invalid_tags: $invalid
        }
    }' 2>/dev/null
}

# ============================================================================
# END TAG-BASED EXCLUSION
# ============================================================================

# Function to construct full resource ID from disk name
construct_disk_resource_id() {
    local disk_name="$1"
    local subscription_id="$2"
    local resource_group="$3"
    
    echo "/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.Compute/disks/$disk_name"
}

# Function to list all managed disks
list_disks() {
    local subscription_id="$1"
    local resource_group="${2:-}"

    echo "=== All Managed Disks in Subscription ==="
    echo "Subscription: $subscription_id"
    [[ -n "$resource_group" ]] && echo "Resource Group: $resource_group"
    echo ""

    # Use Resource Graph API for better reliability
    local rg_filter=""
    if [[ -n "$resource_group" ]]; then
        rg_filter="| where resourceGroup =~ '$resource_group'"
    fi

    az_with_timeout graph query -q "
        Resources
        | where type == 'microsoft.compute/disks'
        | where subscriptionId == '$subscription_id'
        $rg_filter
        | project Name=name, Size=properties.diskSizeGB, ResourceGroup=resourceGroup, State=properties.diskState, Tier=sku.tier
    " --subscriptions "$subscription_id" --first 1000 --output table
}

# Function to list unattached disks with details
# Uses Azure Resource Graph API for fast and reliable queries
list_unattached_disks() {
    local subscription_id="$1"
    local resource_group="${2:-}"  # Optional resource group filter
    local include_attached="${3:-false}"  # Optional flag to include attached disks

    # Always use Resource Graph API (fast and reliable)
    echo "Using Azure Resource Graph API for query..." >&2

    # Build resource group filter if specified
    local rg_filter=""
    if [[ -n "$resource_group" ]]; then
        rg_filter="| where resourceGroup =~ '$resource_group'"
    fi

    # Build disk state filter based on include_attached flag
    local state_filter=""
    if [[ "$include_attached" == "false" ]]; then
        state_filter="| where properties.diskState == 'Unattached'"
    fi

    az_with_timeout graph query -q "
        Resources
        | where type == 'microsoft.compute/disks'
        | where subscriptionId == '$subscription_id'
        $rg_filter
        $state_filter
        | project
            Id = id,
            Name = name,
            SizeGb = properties.diskSizeGB,
            SizeBytes = properties.diskSizeBytes,
            ResourceGroup = resourceGroup,
            Sku = sku.name,
            Tier = sku.tier,
            Created = properties.timeCreated,
            State = properties.diskState,
            Tags = tags
    " --subscriptions "$subscription_id" --first 1000 --output json 2>/dev/null \
    | jq '[.data[] | .Size = (if .SizeGb then .SizeGb else (.SizeBytes / 1073741824 | floor) end) | del(.SizeGb, .SizeBytes)]' 2>/dev/null || { echo "ERROR: Failed to parse Azure response" >&2; return 1; }
}

# Function to list all snapshots
list_snapshots() {
    local subscription_id="$1"

    echo "=== All Snapshots in Subscription ==="
    echo "Subscription: $subscription_id"
    echo ""

    az_with_timeout snapshot list --subscription "$subscription_id" \
        --query '[].{Name:name, Size:diskSizeGb, ResourceGroup:resourceGroup, State:provisioningState, CreationDate:timeCreated}' \
        --output table
}

# Function to get all unattached snapshot resource IDs
# Uses Azure Resource Graph API for fast and reliable queries
get_all_snapshots_with_details() {
    local subscription_id="$1"
    local resource_group="${2:-}"  # Optional resource group filter

    # Always use Resource Graph API (fast and reliable)
    echo "Using Azure Resource Graph API for snapshot query..." >&2

    # Build resource group filter if specified
    local rg_filter=""
    if [[ -n "$resource_group" ]]; then
        rg_filter="| where resourceGroup =~ '$resource_group'"
    fi

    az_with_timeout graph query -q "
        Resources
        | where type == 'microsoft.compute/snapshots'
        | where subscriptionId == '$subscription_id'
        $rg_filter
        | project
            Id = id,
            Name = name,
            Size = properties.diskSizeGB,
            ResourceGroup = resourceGroup,
            Sku = sku.name,
            Tier = sku.tier,
            Created = properties.timeCreated,
            Tags = tags
    " --subscriptions "$subscription_id" --first 1000 --output json 2>/dev/null | jq '.data' 2>/dev/null || echo "[]"
}

# Function to list disks using Azure Resource Graph API (fast, subscription-wide)
# This is significantly faster than az_with_timeout disk list for subscription-wide queries
list_disks_with_resource_graph() {
    local subscription_id="$1"
    local include_attached="$2"

    local state_filter=""
    if [[ "$include_attached" == "false" ]]; then
        state_filter="| where properties.diskState == 'Unattached'"
    fi

    az_with_timeout graph query -q "
        Resources
        | where type == 'microsoft.compute/disks'
        | where subscriptionId == '$subscription_id'
        $state_filter
        | project
            Id = id,
            Name = name,
            SizeGb = properties.diskSizeGB,
            SizeBytes = properties.diskSizeBytes,
            ResourceGroup = resourceGroup,
            Sku = sku.name,
            Tier = sku.tier,
            Created = properties.timeCreated,
            State = properties.diskState
    " --subscriptions "$subscription_id" --first 1000 --output json 2>/dev/null \
    | jq '[.data[] | .Size = (if .SizeGb then .SizeGb else (.SizeBytes / 1073741824 | floor) end) | del(.SizeGb, .SizeBytes)]' 2>/dev/null || echo "[]"
}

# Function to list snapshots using Azure Resource Graph API (fast, subscription-wide)
# This is significantly faster than az_with_timeout snapshot list for subscription-wide queries
list_snapshots_with_resource_graph() {
    local subscription_id="$1"

    az_with_timeout graph query -q "
        Resources
        | where type == 'microsoft.compute/snapshots'
        | where subscriptionId == '$subscription_id'
        | project
            Id = id,
            Name = name,
            Size = properties.diskSizeGB,
            ResourceGroup = resourceGroup,
            Sku = sku.name,
            Tier = sku.tier,
            Created = properties.timeCreated
    " --subscriptions "$subscription_id" --first 1000 --output json 2>/dev/null | jq '.data' 2>/dev/null || echo "[]"
}

# Function to get all disk resource IDs
get_all_disk_resource_ids() {
    local subscription_id="$1"
    local resource_group="${2:-}"  # Optional resource group filter

    local rg_filter=""
    if [[ -n "$resource_group" ]]; then
        rg_filter="| where resourceGroup =~ '$resource_group'"
    fi

    az_with_timeout graph query -q "
        Resources
        | where type == 'microsoft.compute/disks'
        | where subscriptionId == '$subscription_id'
        $rg_filter
        | project id
    " --subscriptions "$subscription_id" --first 1000 --output json 2>/dev/null \
    | jq -r '.data[].id' 2>/dev/null || true
}

# Function to get all snapshot resource IDs
get_all_snapshot_resource_ids() {
    local subscription_id="$1"
    local resource_group="${2:-}"  # Optional resource group filter

    local rg_filter=""
    if [[ -n "$resource_group" ]]; then
        rg_filter="| where resourceGroup =~ '$resource_group'"
    fi

    az_with_timeout graph query -q "
        Resources
        | where type == 'microsoft.compute/snapshots'
        | where subscriptionId == '$subscription_id'
        $rg_filter
        | project id
    " --subscriptions "$subscription_id" --first 1000 --output json 2>/dev/null \
    | jq -r '.data[].id' 2>/dev/null || true
}

# ============================================================================
# MULTI-SUBSCRIPTION SUPPORT FUNCTIONS (Phase 3)
# ============================================================================

# Function to get all accessible Azure subscriptions
# Returns: List of subscription IDs (one per line)
get_all_subscriptions() {
    log_verbose "Fetching list of accessible Azure subscriptions..."
    az_with_timeout account list --query '[].id' -o tsv 2>/dev/null || {
        log_progress "ERROR: Failed to list Azure subscriptions"
        return 1
    }
}

# Function to get subscription details (ID and Name)
# Returns: JSON array with subscription info
get_subscriptions_with_names() {
    log_verbose "Fetching subscription details..."
    az_with_timeout account list --query '[].{id:id, name:name}' -o json 2>/dev/null || {
        log_progress "ERROR: Failed to get subscription details"
        return 1
    }
}

# Function to parse subscription list from various inputs
# Input: comma-separated list, "all", or file path
# Output: Array of subscription IDs
# Usage: parse_subscription_list "all"
#        parse_subscription_list "sub1,sub2,sub3"
#        parse_subscription_list "$(cat file.txt)"
parse_subscription_list() {
    local input="$1"
    local exclude_list="${2:-}"  # Optional exclusion list

    local -a subscription_ids=()

    if [[ "$input" == "all" ]]; then
        # Get all accessible subscriptions
        while IFS= read -r sub_id; do
            [[ -n "$sub_id" ]] && subscription_ids+=("$sub_id")
        done < <(get_all_subscriptions)
    else
        # Parse comma-separated list
        IFS=',' read -ra subscription_ids <<< "$input"
    fi

    # Apply exclusions if provided
    if [[ -n "$exclude_list" ]]; then
        IFS=',' read -ra exclude_ids <<< "$exclude_list"
        local -a filtered_ids=()

        for sub_id in "${subscription_ids[@]}"; do
            local excluded=false
            for exclude_id in "${exclude_ids[@]}"; do
                if [[ "$sub_id" == "$exclude_id" ]]; then
                    excluded=true
                    break
                fi
            done

            if [[ "$excluded" == "false" ]]; then
                filtered_ids+=("$sub_id")
            else
                log_verbose "Excluding subscription: $sub_id"
            fi
        done

        subscription_ids=("${filtered_ids[@]}")
    fi

    # Return subscription IDs (one per line)
    printf '%s\n' "${subscription_ids[@]}"
}

# Function to get subscription name by ID
# Usage: get_subscription_name "subscription-id"
get_subscription_name() {
    local subscription_id="$1"
    az_with_timeout account show --subscription "$subscription_id" --query 'name' -o tsv 2>/dev/null || echo "Unknown"
}

# Function to collect metrics for a single subscription (used in multi-subscription mode)
# Returns JSON with subscription metrics only (no full report)
# Usage: collect_subscription_metrics "subscription-id" "start-date" "end-date" "resource-group" "include-attached"
collect_subscription_metrics() {
    local subscription_id="$1"
    local start_date="$2"
    local end_date="$3"
    local resource_group="${4:-}"
    local include_attached="${5:-false}"

    log_verbose "Collecting metrics for subscription: $subscription_id"

    # Set the active subscription
    az_with_timeout account set --subscription "$subscription_id" >/dev/null 2>&1 || {
        log_progress "ERROR: Failed to set subscription: $subscription_id"
        return 1
    }

    # Validate permissions for this subscription
    if ! validate_azure_permissions "$subscription_id"; then
        log_progress "ERROR: Insufficient permissions on subscription: $subscription_id"
        return 1
    fi

    # Get subscription name
    local subscription_name
    subscription_name=$(get_subscription_name "$subscription_id")

    # Get unattached disks (raw data)
    local unattached_disks_raw
    unattached_disks_raw=$(list_unattached_disks "$subscription_id" "$resource_group" "$include_attached" 2>/dev/null)

    local disk_count=0
    local total_disk_size=0
    local total_disk_cost=0.00
    local disk_invalid_tags=0
    local disk_excluded_pending=0

    # Apply tag filtering (if enabled in config)
    local unattached_disks_json
    local tag_name="${CONFIG_REVIEW_DATE_TAG_NAME:-}"
    if [[ -n "$tag_name" && -n "$unattached_disks_raw" ]]; then
        local filtered_result
        filtered_result=$(filter_resources_by_tags \
            "$unattached_disks_raw" \
            "$tag_name" \
            "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
            "${CONFIG_EXCLUDE_PENDING_REVIEW:-false}" \
            "false" 2>/dev/null)

        unattached_disks_json=$(echo "$filtered_result" | jq -r '.resources' 2>/dev/null)
        disk_count=$(echo "$filtered_result" | jq -r '.stats.included' 2>/dev/null || echo "0")
        disk_invalid_tags=$(echo "$filtered_result" | jq -r '.stats.invalid_tags' 2>/dev/null || echo "0")
        disk_excluded_pending=$(echo "$filtered_result" | jq -r '.stats.excluded_pending' 2>/dev/null || echo "0")
    else
        # No tag filtering
        unattached_disks_json="$unattached_disks_raw"
        if [[ -n "$unattached_disks_json" ]] && echo "$unattached_disks_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
            disk_count=$(echo "$unattached_disks_json" | jq '. | length' 2>/dev/null || echo "0")
        fi
    fi

    # Validate JSON and count disks
    if [[ -n "$unattached_disks_json" ]] && echo "$unattached_disks_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        [[ $disk_count -eq 0 ]] && disk_count=$(echo "$unattached_disks_json" | jq '. | length' 2>/dev/null || echo "0")

        # Collect disk IDs
        local -a disk_ids=()
        while IFS= read -r disk_id; do
            [[ -n "$disk_id" ]] && disk_ids+=("$disk_id")
        done < <(echo "$unattached_disks_json" | jq -r '.[].Id')

        # Calculate total size
        total_disk_size=$(echo "$unattached_disks_json" | jq '[.[].Size] | add // 0' 2>/dev/null || echo "0")

        # Query costs in batches
        if [[ ${#disk_ids[@]} -gt 0 ]]; then
            log_verbose "Querying costs for $disk_count disks..."
            local batch_size=100
            local total_batches=$(( (${#disk_ids[@]} + batch_size - 1) / batch_size ))

            for ((batch_num=0; batch_num<total_batches; batch_num++)); do
                local start_idx=$((batch_num * batch_size))
                local end_idx=$(( start_idx + batch_size ))
                [[ $end_idx -gt ${#disk_ids[@]} ]] && end_idx=${#disk_ids[@]}

                local -a batch_ids=("${disk_ids[@]:$start_idx:$((end_idx - start_idx))}")
                local batch_result
                batch_result=$(query_batch_resource_costs "$subscription_id" "$start_date" "$end_date" "${batch_ids[@]}")

                # Sum costs from batch
                if echo "$batch_result" | jq -e '.properties.rows | length > 0' > /dev/null 2>&1; then
                    local batch_cost
                    batch_cost=$(echo "$batch_result" | jq '[.properties.rows[][0]] | add // 0' 2>/dev/null || echo "0")
                    total_disk_cost=$(echo "$total_disk_cost + $batch_cost" | bc -l 2>/dev/null || echo "$total_disk_cost")
                fi

                # Rate limiting
                if [[ $((batch_num + 1)) -lt $total_batches ]]; then
                    sleep 2
                fi
            done
        fi
    fi

    # Get snapshots (raw data)
    local snapshots_raw
    snapshots_raw=$(get_all_snapshots_with_details "$subscription_id" "$resource_group" 2>/dev/null)

    local snapshot_count=0
    local total_snapshot_size=0
    local total_snapshot_cost=0.00
    local snapshot_invalid_tags=0
    local snapshot_excluded_pending=0

    # Apply tag filtering (if enabled in config)
    local snapshots_json
    if [[ -n "$tag_name" && -n "$snapshots_raw" ]]; then
        local filtered_result
        filtered_result=$(filter_resources_by_tags \
            "$snapshots_raw" \
            "$tag_name" \
            "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
            "${CONFIG_EXCLUDE_PENDING_REVIEW:-false}" \
            "false" 2>/dev/null)

        snapshots_json=$(echo "$filtered_result" | jq -r '.resources' 2>/dev/null)
        snapshot_count=$(echo "$filtered_result" | jq -r '.stats.included' 2>/dev/null || echo "0")
        snapshot_invalid_tags=$(echo "$filtered_result" | jq -r '.stats.invalid_tags' 2>/dev/null || echo "0")
        snapshot_excluded_pending=$(echo "$filtered_result" | jq -r '.stats.excluded_pending' 2>/dev/null || echo "0")
    else
        # No tag filtering
        snapshots_json="$snapshots_raw"
        if [[ -n "$snapshots_json" ]] && echo "$snapshots_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
            snapshot_count=$(echo "$snapshots_json" | jq '. | length' 2>/dev/null || echo "0")
        fi
    fi

    # Validate JSON and count snapshots
    if [[ -n "$snapshots_json" ]] && echo "$snapshots_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        [[ $snapshot_count -eq 0 ]] && snapshot_count=$(echo "$snapshots_json" | jq '. | length' 2>/dev/null || echo "0")
        total_snapshot_size=$(echo "$snapshots_json" | jq '[.[].Size] | add // 0' 2>/dev/null || echo "0")

        # Collect snapshot IDs
        local -a snapshot_ids=()
        while IFS= read -r snapshot_id; do
            [[ -n "$snapshot_id" ]] && snapshot_ids+=("$snapshot_id")
        done < <(echo "$snapshots_json" | jq -r '.[].Id')

        # Query snapshot costs in batches
        if [[ ${#snapshot_ids[@]} -gt 0 ]]; then
            log_verbose "Querying costs for $snapshot_count snapshots..."
            local batch_size=100
            local total_batches=$(( (${#snapshot_ids[@]} + batch_size - 1) / batch_size ))

            for ((batch_num=0; batch_num<total_batches; batch_num++)); do
                local start_idx=$((batch_num * batch_size))
                local end_idx=$(( start_idx + batch_size ))
                [[ $end_idx -gt ${#snapshot_ids[@]} ]] && end_idx=${#snapshot_ids[@]}

                local -a batch_ids=("${snapshot_ids[@]:$start_idx:$((end_idx - start_idx))}")
                local batch_result
                batch_result=$(query_batch_resource_costs "$subscription_id" "$start_date" "$end_date" "${batch_ids[@]}")

                # Sum costs from batch
                if echo "$batch_result" | jq -e '.properties.rows | length > 0' > /dev/null 2>&1; then
                    local batch_cost
                    batch_cost=$(echo "$batch_result" | jq '[.properties.rows[][0]] | add // 0' 2>/dev/null || echo "0")
                    total_snapshot_cost=$(echo "$total_snapshot_cost + $batch_cost" | bc -l 2>/dev/null || echo "$total_snapshot_cost")
                fi

                # Rate limiting
                if [[ $((batch_num + 1)) -lt $total_batches ]]; then
                    sleep 2
                fi
            done
        fi
    fi

    # Calculate total waste
    local total_waste_monthly
    total_waste_monthly=$(echo "$total_disk_cost + $total_snapshot_cost" | bc -l)
    local total_waste_annual
    total_waste_annual=$(echo "$total_waste_monthly * 12" | bc -l)

    # Calculate total tag metrics
    local total_invalid_tags=$((disk_invalid_tags + snapshot_invalid_tags))
    local total_excluded_pending=$((disk_excluded_pending + snapshot_excluded_pending))

    # Output JSON
    cat <<EOF
{
  "subscription_id": "$subscription_id",
  "subscription_name": "$subscription_name",
  "status": "success",
  "metrics": {
    "unattached_disks_count": $disk_count,
    "unattached_disks_size_gb": $total_disk_size,
    "unattached_disks_cost_monthly": $(printf "%.2f" "$total_disk_cost"),
    "snapshots_count": $snapshot_count,
    "snapshots_size_gb": $total_snapshot_size,
    "snapshots_cost_monthly": $(printf "%.2f" "$total_snapshot_cost"),
    "total_waste_monthly": $(printf "%.2f" "$total_waste_monthly"),
    "total_waste_annual": $(printf "%.2f" "$total_waste_annual"),
    "invalid_tags": $total_invalid_tags,
    "excluded_pending_review": $total_excluded_pending
  }
}
EOF

    return 0
}

# Function to process multiple subscriptions and generate aggregated report
# Usage: process_multi_subscription "subscription1,subscription2" "start-date" "end-date" "resource-group" "include-attached"
process_multi_subscription() {
    local subscriptions_input="$1"
    local start_date="$2"
    local end_date="$3"
    local resource_group="${4:-}"
    local include_attached="${5:-false}"
    local exclude_list="${6:-}"

    local execution_start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local execution_start_epoch=$(date +%s)

    log_progress "Starting multi-subscription analysis..."

    # Parse subscription list
    local -a subscription_ids=()
    while IFS= read -r sub_id; do
        [[ -n "$sub_id" ]] && subscription_ids+=("$sub_id")
    done < <(parse_subscription_list "$subscriptions_input" "$exclude_list")

    if [[ ${#subscription_ids[@]} -eq 0 ]]; then
        log_progress "ERROR: No subscriptions to process"
        return $EXIT_CONFIG_ERROR
    fi

    log_progress "Processing ${#subscription_ids[@]} subscription(s)..."

    # Arrays to store results
    local -a success_subscriptions=()
    local -a failed_subscriptions=()
    local -a subscription_results=()

    # Aggregate metrics
    local total_disk_count=0
    local total_disk_size=0
    local total_disk_cost=0
    local total_snapshot_count=0
    local total_snapshot_size=0
    local total_snapshot_cost=0
    local total_invalid_tags=0
    local total_excluded_pending=0

    # Process each subscription sequentially
    local sub_index=1
    for subscription_id in "${subscription_ids[@]}"; do
        log_progress "[$sub_index/${#subscription_ids[@]}] Processing subscription: $subscription_id"

        # Collect metrics for this subscription
        local sub_metrics
        if sub_metrics=$(collect_subscription_metrics "$subscription_id" "$start_date" "$end_date" "$resource_group" "$include_attached"); then
            success_subscriptions+=("$subscription_id")
            subscription_results+=("$sub_metrics")

            # Extract and aggregate metrics
            local sub_disk_count=$(echo "$sub_metrics" | jq -r '.metrics.unattached_disks_count' 2>/dev/null || echo "0")
            local sub_disk_size=$(echo "$sub_metrics" | jq -r '.metrics.unattached_disks_size_gb' 2>/dev/null || echo "0")
            local sub_disk_cost=$(echo "$sub_metrics" | jq -r '.metrics.unattached_disks_cost_monthly' 2>/dev/null || echo "0")
            local sub_snapshot_count=$(echo "$sub_metrics" | jq -r '.metrics.snapshots_count' 2>/dev/null || echo "0")
            local sub_snapshot_size=$(echo "$sub_metrics" | jq -r '.metrics.snapshots_size_gb' 2>/dev/null || echo "0")
            local sub_snapshot_cost=$(echo "$sub_metrics" | jq -r '.metrics.snapshots_cost_monthly' 2>/dev/null || echo "0")
            local sub_invalid_tags=$(echo "$sub_metrics" | jq -r '.metrics.invalid_tags // 0' 2>/dev/null || echo "0")
            local sub_excluded_pending=$(echo "$sub_metrics" | jq -r '.metrics.excluded_pending_review // 0' 2>/dev/null || echo "0")

            total_disk_count=$((total_disk_count + sub_disk_count))
            total_disk_size=$((total_disk_size + sub_disk_size))
            total_disk_cost=$(echo "$total_disk_cost + $sub_disk_cost" 2>/dev/null | bc -l)
            total_snapshot_count=$((total_snapshot_count + sub_snapshot_count))
            total_snapshot_size=$((total_snapshot_size + sub_snapshot_size))
            total_snapshot_cost=$(echo "$total_snapshot_cost + $sub_snapshot_cost" 2>/dev/null | bc -l)
            total_invalid_tags=$((total_invalid_tags + sub_invalid_tags))
            total_excluded_pending=$((total_excluded_pending + sub_excluded_pending))

            log_progress "  ✓ Success: $sub_disk_count disks, $sub_snapshot_count snapshots, \$$(printf "%.2f" "$(echo "$sub_disk_cost + $sub_snapshot_cost" 2>/dev/null | bc -l)")/month"
        else
            failed_subscriptions+=("$subscription_id")
            log_progress "  ✗ Failed to process subscription: $subscription_id"

            # Add failed subscription to results
            local sub_name=$(get_subscription_name "$subscription_id")
            subscription_results+=($(cat <<EOF
{
  "subscription_id": "$subscription_id",
  "subscription_name": "$sub_name",
  "status": "failed",
  "error": "Failed to collect metrics"
}
EOF
))
        fi

        # Rate limiting between subscriptions
        if [[ $sub_index -lt ${#subscription_ids[@]} ]]; then
            sleep 2
        fi

        ((sub_index++))
    done

    # Calculate execution time
    local execution_end_epoch=$(date +%s)
    local execution_duration=$((execution_end_epoch - execution_start_epoch))
    local execution_end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Calculate total waste
    local total_waste_monthly=$(echo "$total_disk_cost + $total_snapshot_cost" 2>/dev/null | bc -l)
    local total_waste_annual=$(echo "$total_waste_monthly * 12" 2>/dev/null | bc -l)

    log_progress "Multi-subscription analysis complete:"
    log_progress "  Subscriptions processed: ${#subscription_ids[@]}"
    log_progress "  Successful: ${#success_subscriptions[@]}"
    log_progress "  Failed: ${#failed_subscriptions[@]}"
    log_progress "  Total waste: \$$(printf "%.2f" "$total_waste_monthly")/month (\$$(printf "%.2f" "$total_waste_annual")/year)"

    # Generate output based on format
    case "$OUTPUT_FORMAT" in
        json)
            # Build JSON array of subscription results
            local subscriptions_json="["
            local first=true
            for result in "${subscription_results[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    subscriptions_json+=","
                fi
                subscriptions_json+="$result"
            done
            subscriptions_json+="]"

            # Output multi-subscription JSON
            cat <<EOF
{
  "version": "1.0",
  "timestamp": "$execution_start_time",
  "scan_type": "multi-subscription",
  "execution": {
    "start_time": "$execution_start_time",
    "end_time": "$execution_end_time",
    "duration_seconds": $execution_duration,
    "status": "$([ ${#failed_subscriptions[@]} -eq 0 ] && echo "success" || echo "partial_failure")"
  },
  "subscriptions_scanned": ${#subscription_ids[@]},
  "subscriptions_successful": ${#success_subscriptions[@]},
  "subscriptions_failed": ${#failed_subscriptions[@]},
  "analysis_period": {
    "start_date": "$start_date",
    "end_date": "$end_date"
  },
  "aggregated_metrics": {
    "total_unattached_disks": $total_disk_count,
    "total_unattached_size_gb": $total_disk_size,
    "total_unattached_cost_monthly": $(printf "%.2f" "$total_disk_cost"),
    "total_snapshots": $total_snapshot_count,
    "total_snapshots_size_gb": $total_snapshot_size,
    "total_snapshots_cost_monthly": $(printf "%.2f" "$total_snapshot_cost"),
    "total_waste_monthly_usd": $(printf "%.2f" "$total_waste_monthly"),
    "total_waste_annual_usd": $(printf "%.2f" "$total_waste_annual"),
    "invalid_tags": $total_invalid_tags,
    "excluded_pending_review": $total_excluded_pending
  },
  "by_subscription": $subscriptions_json
}
EOF
            ;;

        zabbix)
            # Output Zabbix metrics (batch format)
            local timestamp=$(date +%s)
            local zabbix_host="${CONFIG_ZABBIX_HOSTNAME:-azure-storage-monitor}"

            echo "$zabbix_host azure.storage.all.total_waste.monthly $timestamp $(printf "%.2f" "$total_waste_monthly")"
            echo "$zabbix_host azure.storage.all.total_disks $timestamp $total_disk_count"
            echo "$zabbix_host azure.storage.all.total_snapshots $timestamp $total_snapshot_count"
            echo "$zabbix_host azure.storage.all.subscriptions_scanned $timestamp ${#subscription_ids[@]}"
            echo "$zabbix_host azure.storage.all.invalid_tags $timestamp $total_invalid_tags"
            echo "$zabbix_host azure.storage.all.excluded_pending_review $timestamp $total_excluded_pending"
            echo "$zabbix_host azure.storage.script.last_run_timestamp $timestamp $timestamp"
            echo "$zabbix_host azure.storage.script.execution_time_seconds $timestamp $execution_duration"
            echo "$zabbix_host azure.storage.script.last_run_status $timestamp 0"

            # Per-subscription metrics
            for result in "${subscription_results[@]}"; do
                local sub_id=$(echo "$result" | jq -r '.subscription_id')
                local sub_name=$(echo "$result" | jq -r '.subscription_name')
                local sub_status=$(echo "$result" | jq -r '.status')

                if [[ "$sub_status" == "success" ]]; then
                    local sub_waste=$(echo "$result" | jq -r '.metrics.total_waste_monthly')
                    local sub_disks=$(echo "$result" | jq -r '.metrics.unattached_disks_count')
                    local sub_snapshots=$(echo "$result" | jq -r '.metrics.snapshots_count')
                    local sub_invalid_tags=$(echo "$result" | jq -r '.metrics.invalid_tags // 0')
                    local sub_excluded_pending=$(echo "$result" | jq -r '.metrics.excluded_pending_review // 0')

                    echo "$zabbix_host azure.storage.subscription.waste_monthly[$sub_id] $timestamp $sub_waste"
                    echo "$zabbix_host azure.storage.subscription.disk_count[$sub_id] $timestamp $sub_disks"
                    echo "$zabbix_host azure.storage.subscription.snapshot_count[$sub_id] $timestamp $sub_snapshots"
                    echo "$zabbix_host azure.storage.subscription.invalid_tags[$sub_id] $timestamp $sub_invalid_tags"
                    echo "$zabbix_host azure.storage.subscription.excluded_pending_review[$sub_id] $timestamp $sub_excluded_pending"
                fi
            done
            ;;

        text)
            # Human-readable text output
            echo "=== AZURE MULTI-SUBSCRIPTION COST ANALYSIS ==="
            echo "Generated: $(date)"
            echo "Subscriptions scanned: ${#subscription_ids[@]}"
            echo "Analysis period: $start_date to $end_date"
            echo ""
            echo "=== AGGREGATED METRICS ==="
            echo "Total unattached disks: $total_disk_count ($total_disk_size GB)"
            echo "Total snapshots: $total_snapshot_count ($total_snapshot_size GB)"
            echo "Total waste: \$$(printf "%.2f" "$total_waste_monthly")/month (\$$(printf "%.2f" "$total_waste_annual")/year)"
            echo ""
            echo "=== PER-SUBSCRIPTION BREAKDOWN ==="
            printf "%-40s | %-10s | %-10s | %-15s\n" "Subscription" "Disks" "Snapshots" "Monthly Cost"
            printf "%-40s | %-10s | %-10s | %-15s\n" "----------------------------------------" "----------" "----------" "---------------"

            for result in "${subscription_results[@]}"; do
                local sub_name=$(echo "$result" | jq -r '.subscription_name')
                local sub_status=$(echo "$result" | jq -r '.status')

                if [[ "$sub_status" == "success" ]]; then
                    local sub_disks=$(echo "$result" | jq -r '.metrics.unattached_disks_count')
                    local sub_snapshots=$(echo "$result" | jq -r '.metrics.snapshots_count')
                    local sub_waste=$(echo "$result" | jq -r '.metrics.total_waste_monthly')

                    printf "%-40s | %-10d | %-10d | \$%-14.2f\n" "$sub_name" "$sub_disks" "$sub_snapshots" "$sub_waste"
                else
                    printf "%-40s | %-10s | %-10s | %-15s\n" "$sub_name" "FAILED" "-" "-"
                fi
            done
            ;;
    esac

    # Determine exit code
    if [[ ${#failed_subscriptions[@]} -gt 0 ]]; then
        if [[ ${#success_subscriptions[@]} -eq 0 ]]; then
            # All failed
            return $EXIT_CONFIG_ERROR
        else
            # Partial failure
            return $EXIT_PARTIAL_FAILURE
        fi
    fi

    # Check thresholds (if configured)
    if [[ -n "$CONFIG_THRESHOLD_CRITICAL_MONTHLY" ]] && (( $(echo "$total_waste_monthly > $CONFIG_THRESHOLD_CRITICAL_MONTHLY" | bc -l) )); then
        return $EXIT_CRITICAL
    elif [[ -n "$CONFIG_THRESHOLD_WARNING_MONTHLY" ]] && (( $(echo "$total_waste_monthly > $CONFIG_THRESHOLD_WARNING_MONTHLY" | bc -l) )); then
        return $EXIT_WARNING
    fi

    return $EXIT_SUCCESS
}

# ============================================================================
# END MULTI-SUBSCRIPTION SUPPORT FUNCTIONS
# ============================================================================

# ============================================================================
# ZABBIX INTEGRATION FUNCTIONS (Phase 2)
# ============================================================================

# Function to send a single metric to Zabbix
# Usage: send_to_zabbix "server" "port" "hostname" "key" "value"
send_to_zabbix() {
    local server="$1"
    local port="$2"
    local hostname="$3"
    local key="$4"
    local value="$5"

    if ! command -v zabbix_sender &> /dev/null; then
        log_progress "ERROR: zabbix_sender not found in PATH"
        return 1
    fi

    log_verbose "Sending to Zabbix: $hostname $key = $value"

    # Send metric to Zabbix
    if zabbix_sender -z "$server" \
                     -p "$port" \
                     -s "$hostname" \
                     -k "$key" \
                     -o "$value" \
                     2>&1 | grep -q "processed: 1"; then
        log_verbose "Successfully sent metric: $key"
        return 0
    else
        log_progress "ERROR: Failed to send metric: $key"
        return 1
    fi
}

# Function to create Zabbix batch file with all metrics
# Usage: create_zabbix_batch_file "hostname" "timestamp" "metrics_json"
# Returns: Path to batch file
create_zabbix_batch_file() {
    local hostname="$1"
    local timestamp="$2"
    local metrics_json="$3"

    local batch_file="/tmp/zabbix_batch_$$.txt"

    # Clear batch file
    > "$batch_file"

    # Extract metrics from JSON and format for Zabbix
    # Format: hostname key timestamp value

    # Aggregated metrics
    local total_waste=$(echo "$metrics_json" | jq -r '.aggregated_metrics.total_waste_monthly_usd // .metrics.total_waste_monthly // 0')
    local total_disks=$(echo "$metrics_json" | jq -r '.aggregated_metrics.total_unattached_disks // .metrics.unattached_disks_count // 0')
    local total_snapshots=$(echo "$metrics_json" | jq -r '.aggregated_metrics.total_snapshots // .metrics.snapshots_count // 0')

    echo "$hostname azure.storage.all.total_waste.monthly $timestamp $total_waste" >> "$batch_file"
    echo "$hostname azure.storage.all.total_disks $timestamp $total_disks" >> "$batch_file"
    echo "$hostname azure.storage.all.total_snapshots $timestamp $total_snapshots" >> "$batch_file"

    # Script health metrics
    echo "$hostname azure.storage.script.last_run_timestamp $timestamp $timestamp" >> "$batch_file"
    echo "$hostname azure.storage.script.last_run_status $timestamp 0" >> "$batch_file"

    # Per-subscription metrics (if available)
    if echo "$metrics_json" | jq -e '.by_subscription' > /dev/null 2>&1; then
        local sub_count=$(echo "$metrics_json" | jq '.by_subscription | length')
        echo "$hostname azure.storage.all.subscriptions_scanned $timestamp $sub_count" >> "$batch_file"

        # Iterate through subscriptions
        for ((i=0; i<sub_count; i++)); do
            local sub_id=$(echo "$metrics_json" | jq -r ".by_subscription[$i].subscription_id")
            local sub_status=$(echo "$metrics_json" | jq -r ".by_subscription[$i].status")

            if [[ "$sub_status" == "success" ]]; then
                local sub_waste=$(echo "$metrics_json" | jq -r ".by_subscription[$i].metrics.total_waste_monthly")
                local sub_disks=$(echo "$metrics_json" | jq -r ".by_subscription[$i].metrics.unattached_disks_count")
                local sub_snapshots=$(echo "$metrics_json" | jq -r ".by_subscription[$i].metrics.snapshots_count")

                echo "$hostname azure.storage.subscription.waste_monthly[$sub_id] $timestamp $sub_waste" >> "$batch_file"
                echo "$hostname azure.storage.subscription.disk_count[$sub_id] $timestamp $sub_disks" >> "$batch_file"
                echo "$hostname azure.storage.subscription.snapshot_count[$sub_id] $timestamp $sub_snapshots" >> "$batch_file"
            fi
        done
    fi

    echo "$batch_file"
}

# Function to send batch metrics to Zabbix
# Usage: send_batch_to_zabbix "server" "port" "batch_file"
send_batch_to_zabbix() {
    local server="$1"
    local port="$2"
    local batch_file="$3"

    if ! command -v zabbix_sender &> /dev/null; then
        log_progress "ERROR: zabbix_sender not found in PATH"
        return 1
    fi

    if [[ ! -f "$batch_file" ]]; then
        log_progress "ERROR: Batch file not found: $batch_file"
        return 1
    fi

    local metric_count=$(wc -l < "$batch_file")
    log_progress "Sending $metric_count metrics to Zabbix server $server:$port..."

    # Send all metrics in one batch
    if zabbix_sender -z "$server" \
                     -p "$port" \
                     -i "$batch_file" \
                     -vv 2>&1 | tee -a /tmp/zabbix_send.log | grep -q "processed:"; then
        log_progress "Successfully sent all metrics to Zabbix"
        rm -f "$batch_file"
        return 0
    else
        log_progress "ERROR: Failed to send metrics to Zabbix"
        # Keep batch file for debugging
        local failed_batch="/tmp/failed_zabbix_batch_$(date +%Y%m%d-%H%M%S).txt"
        mv "$batch_file" "$failed_batch"
        log_progress "Batch file saved to: $failed_batch"
        return 1
    fi
}

# Function to send metrics to Zabbix using config file
# Usage: send_batch_to_zabbix_with_config "config_file" "batch_file"
send_batch_to_zabbix_with_config() {
    local config_file="$1"
    local batch_file="$2"

    if ! command -v zabbix_sender &> /dev/null; then
        log_progress "ERROR: zabbix_sender not found in PATH"
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        log_progress "ERROR: Zabbix config file not found: $config_file"
        return 1
    fi

    if [[ ! -f "$batch_file" ]]; then
        log_progress "ERROR: Batch file not found: $batch_file"
        return 1
    fi

    local metric_count=$(wc -l < "$batch_file")
    log_progress "Sending $metric_count metrics to Zabbix using config: $config_file..."

    # Send using config file
    if zabbix_sender -c "$config_file" \
                     -i "$batch_file" \
                     -vv 2>&1 | tee -a /tmp/zabbix_send.log | grep -q "processed:"; then
        log_progress "Successfully sent all metrics to Zabbix"
        rm -f "$batch_file"
        return 0
    else
        log_progress "ERROR: Failed to send metrics to Zabbix"
        local failed_batch="/tmp/failed_zabbix_batch_$(date +%Y%m%d-%H%M%S).txt"
        mv "$batch_file" "$failed_batch"
        log_progress "Batch file saved to: $failed_batch"
        return 1
    fi
}

# ============================================================================
# ZABBIX LOW-LEVEL DISCOVERY (LLD) FUNCTIONS
# ============================================================================

# Function to generate LLD JSON for subscriptions
# Usage: generate_subscriptions_lld
generate_subscriptions_lld() {
    log_verbose "Generating subscription LLD JSON..."

    local subscriptions_json=$(get_subscriptions_with_names)

    if [[ -z "$subscriptions_json" ]]; then
        echo '{"data":[]}'
        return 1
    fi

    # Convert to Zabbix LLD format
    echo "$subscriptions_json" | jq '{data: [.[] | {
        "{#SUBSCRIPTION_ID}": .id,
        "{#SUBSCRIPTION_NAME}": .name
    }]}'
}

# Function to generate LLD JSON for unattached disks
# Usage: generate_disks_lld "subscription-id" "resource-group"
generate_disks_lld() {
    local subscription_id="$1"
    local resource_group="${2:-}"

    log_verbose "Generating disks LLD JSON for subscription: $subscription_id..."

    local disks_json=$(list_unattached_disks "$subscription_id" "$resource_group" "false")

    if [[ -z "$disks_json" ]] || ! echo "$disks_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        echo '{"data":[]}'
        return 0
    fi

    # Convert to Zabbix LLD format
    echo "$disks_json" | jq '{data: [.[] | {
        "{#DISK_NAME}": .Name,
        "{#DISK_ID}": .Id,
        "{#DISK_SIZE_GB}": (.Size | tostring),
        "{#DISK_RG}": .ResourceGroup,
        "{#DISK_STATE}": .State,
        "{#DISK_SKU}": .Sku,
        "{#DISK_CREATED}": .Created,
        "{#SUBSCRIPTION_ID}": "'"$subscription_id"'"
    }]}'
}

# Function to generate LLD JSON for snapshots
# Usage: generate_snapshots_lld "subscription-id" "resource-group"
generate_snapshots_lld() {
    local subscription_id="$1"
    local resource_group="${2:-}"

    log_verbose "Generating snapshots LLD JSON for subscription: $subscription_id..."

    local snapshots_json=$(get_all_snapshots_with_details "$subscription_id" "$resource_group")

    if [[ -z "$snapshots_json" ]] || ! echo "$snapshots_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        echo '{"data":[]}'
        return 0
    fi

    # Convert to Zabbix LLD format
    echo "$snapshots_json" | jq '{data: [.[] | {
        "{#SNAPSHOT_NAME}": .Name,
        "{#SNAPSHOT_ID}": .Id,
        "{#SNAPSHOT_SIZE_GB}": (.Size | tostring),
        "{#SNAPSHOT_RG}": .ResourceGroup,
        "{#SNAPSHOT_SKU}": .Sku,
        "{#SNAPSHOT_CREATED}": .Created,
        "{#SUBSCRIPTION_ID}": "'"$subscription_id"'"
    }]}'
}

# Function to generate LLD JSON for resource groups
# Usage: generate_resource_groups_lld "subscription-id"
generate_resource_groups_lld() {
    local subscription_id="$1"

    log_verbose "Generating resource group LLD JSON for subscription: ${subscription_id:-all subscriptions}..."

    local groups_json
    if [[ -n "$subscription_id" ]]; then
        groups_json=$(az_with_timeout group list --subscription "$subscription_id" -o json 2>/dev/null) || groups_json="[]"
    else
        groups_json=$(az_with_timeout group list -o json 2>/dev/null) || groups_json="[]"
    fi

    if [[ -z "$groups_json" ]] || [[ "$groups_json" == "[]" ]]; then
        echo '{"data":[]}'
        return 0
    fi

    echo "$groups_json" | jq '{data: [.[] | {
        "{#RG_NAME}": .name,
        "{#SUBSCRIPTION_ID}": (.id | split("/")[2])
    }]}' 2>/dev/null || echo '{"data":[]}'
}

# ============================================================================
# END ZABBIX INTEGRATION FUNCTIONS
# ============================================================================

# Function to retry Azure API calls with exponential backoff
retry_azure_api() {
    local max_attempts=5
    local delay=2
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi

        local exit_code=$?
        if [[ $attempt -eq $max_attempts ]]; then
            echo "ERROR: Max retry attempts ($max_attempts) reached" >&2
            return $exit_code
        fi

        echo "Rate limited, attempt $attempt/$max_attempts, waiting ${delay}s..." >&2
        sleep $delay
        delay=$((delay * 2))  # Exponential backoff
        ((attempt++))
    done
}

# Helper function to lookup cost from parallel arrays (bash 3.2 compatible)
# This replaces associative array lookups for bash 3.2 compatibility
# Usage: lookup_cost <search_id> <keys_array_name> <values_array_name>
# NOTE: Azure Cost Management API returns resource IDs in lowercase, so we do case-insensitive comparison
# Helper function to truncate long names with ellipsis (smart truncate - keep start and end)
truncate_name() {
    local name="$1"
    local max_length="${2:-40}"  # Default 40 chars

    if [[ ${#name} -le $max_length ]]; then
        echo "$name"
    else
        # Smart truncate: keep first 20 chars and last 17 chars with "..." in middle
        local keep_start=20
        local keep_end=17
        local start="${name:0:$keep_start}"
        local end="${name: -$keep_end}"
        echo "${start}...${end}"
    fi
}

# shellcheck disable=SC2154  # dynamic array indirection via eval
lookup_cost() {
    local search_id="$1"
    local keys_var="$2"
    local values_var="$3"

    # Check if arrays exist and have elements (avoid unbound variable error)
    eval "local array_length=\${#${keys_var}[@]}"
    if [[ $array_length -eq 0 ]]; then
        echo "0.00"
        return 0
    fi

    # Use eval to access array by name (bash 3.2 compatible way)
    # shellcheck disable=SC2154  # dynamic array indirection
    eval "local -a keys=(\"\${${keys_var}[@]}\")"
    # shellcheck disable=SC2154  # dynamic array indirection
    eval "local -a values=(\"\${${values_var}[@]}\")"

    # Convert search ID to lowercase for comparison
    local search_id_lower=$(echo "$search_id" | tr '[:upper:]' '[:lower:]')

    for ((i=0; i<${#keys[@]}; i++)); do
        # Convert stored key to lowercase for comparison
        local key_lower=$(echo "${keys[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$key_lower" == "$search_id_lower" ]]; then
            echo "${values[$i]}"
            return 0
        fi
    done
    echo "0.00"  # Default if not found
}

# Function to sort parallel arrays by size (ascending order)
# Bash 3.2 compatible bubble sort that keeps all arrays in sync
# Usage: sort_by_size_ascending array1_name array2_name ... size_array_name
# The last argument must be the array containing numeric sizes to sort by
# shellcheck disable=SC2154  # dynamic array indirection via eval
sort_by_size_ascending() {
    # Get all array names (last one is the size array)
    local -a array_names=("$@")
    local size_array_name="${array_names[${#array_names[@]}-1]}"

    # Get array length from size array
    # shellcheck disable=SC2154  # dynamic array name via eval
    eval "local n=\${#${size_array_name}[@]}"

    # Bubble sort - swap elements in all arrays simultaneously
    for ((i=0; i<n-1; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            local k=$((j+1))

            # Get sizes to compare
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local size_j=\${${size_array_name}[$j]}"
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local size_k=\${${size_array_name}[$k]}"

            # Compare sizes (ascending order)
            if [[ $size_j -gt $size_k ]]; then
                # Swap elements in ALL arrays
                for array_name in "${array_names[@]}"; do
                    eval "local temp=\${${array_name}[$j]}"
                    eval "${array_name}[$j]=\${${array_name}[$k]}"
                    eval "${array_name}[$k]=\$temp"
                done
            fi
        done
    done
}

# Function to sort parallel arrays by resource group, then by size within each group
# Bash 3.2 compatible bubble sort with two-level comparison
# Usage: sort_by_rg_then_size array1_name array2_name ... rg_array_name size_array_name
# The last two arguments must be: resource_group_array size_array
# shellcheck disable=SC2154  # dynamic array indirection via eval
sort_by_rg_then_size() {
    local -a array_names=("$@")
    local size_array_name="${array_names[${#array_names[@]}-1]}"
    local rg_array_name="${array_names[${#array_names[@]}-2]}"

    # Get array length
    # shellcheck disable=SC2154  # dynamic array name via eval
    eval "local n=\${#${size_array_name}[@]}"

    # Bubble sort with two-level comparison: RG first, then size within RG
    for ((i=0; i<n-1; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            local k=$((j+1))

            # Get RGs and sizes to compare
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local rg_j=\${${rg_array_name}[$j]}"
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local rg_k=\${${rg_array_name}[$k]}"
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local size_j=\${${size_array_name}[$j]}"
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local size_k=\${${size_array_name}[$k]}"

            local should_swap=false

            # Primary sort: by Resource Group (alphabetical)
            if [[ "$rg_j" > "$rg_k" ]]; then
                should_swap=true
            # Secondary sort: within same RG, sort by size (ascending)
            elif [[ "$rg_j" == "$rg_k" ]] && [[ $size_j -gt $size_k ]]; then
                should_swap=true
            fi

            if [[ "$should_swap" == "true" ]]; then
                # Swap elements in ALL arrays
                for array_name in "${array_names[@]}"; do
                    eval "local temp=\${${array_name}[$j]}"
                    eval "${array_name}[$j]=\${${array_name}[$k]}"
                    eval "${array_name}[$k]=\$temp"
                done
            fi
        done
    done
}

# Function to sort parallel arrays by creation date (ascending - oldest first)
# Bash 3.2 compatible bubble sort that keeps all arrays in sync
# Usage: sort_by_created_date array1_name array2_name ... created_date_array_name
# The last argument must be the array containing ISO date strings (YYYY-MM-DD) to sort by
# shellcheck disable=SC2154  # dynamic array indirection via eval
sort_by_created_date() {
    # Get all array names (last one is the created date array)
    local -a array_names=("$@")
    local date_array_name="${array_names[${#array_names[@]}-1]}"

    # Get array length from date array
    # shellcheck disable=SC2154  # dynamic array name via eval
    eval "local n=\${#${date_array_name}[@]}"

    # Bubble sort - swap elements in all arrays simultaneously
    for ((i=0; i<n-1; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            local k=$((j+1))

            # Get dates to compare (ISO format: YYYY-MM-DD allows string comparison)
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local date_j=\${${date_array_name}[$j]}"
            # shellcheck disable=SC2154  # dynamic arrays via eval
            eval "local date_k=\${${date_array_name}[$k]}"

            # Compare dates (ascending order: oldest first)
            # String comparison works for ISO dates (YYYY-MM-DD)
            if [[ "$date_j" > "$date_k" ]]; then
                # Swap elements in ALL arrays
                for array_name in "${array_names[@]}"; do
                    eval "local temp=\${${array_name}[$j]}"
                    eval "${array_name}[$j]=\${${array_name}[$k]}"
                    eval "${array_name}[$k]=\$temp"
                done
            fi
        done
    done
}

# Function to query costs for a single resource
query_resource_costs() {
    local resource_id="$1"
    local subscription_id="$2"
    local start_date="$3"
    local end_date="$4"
    local resource_name

    # Extract resource name from ID for display
    resource_name=$(basename "$resource_id")

    echo "Analyzing: $resource_name"
    
    # Use retry mechanism for API calls
    local result
    if ! result=$(retry_azure_api az_with_timeout rest --method POST \
      --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
      --body "{
        \"type\": \"ActualCost\",
        \"timeframe\": \"Custom\",
        \"timePeriod\": {
          \"from\": \"$start_date\",
          \"to\": \"$end_date\"
        },
        \"dataset\": {
          \"granularity\": \"None\",
          \"aggregation\": {
            \"totalCost\": {
              \"name\": \"Cost\",
              \"function\": \"Sum\"
            }
          },
          \"grouping\": [
            {
              \"type\": \"Dimension\",
              \"name\": \"Meter\"
            }
          ],
          \"filter\": {
            \"dimensions\": {
              \"name\": \"ResourceId\",
              \"operator\": \"In\",
              \"values\": [\"$resource_id\"]
            }
          }
        }
      }"); then
        printf "%-40s | API call failed after retries\\n" "$resource_name"
        echo "0.00,0.00,0.00"
        return 1
    fi
    
    # Parse and display results
    if echo "$result" | jq -e '.properties.rows | length > 0' > /dev/null 2>&1; then
        local storage_total transaction_total grand_total
        
        storage_total=$(echo "$result" | jq -r '.properties.rows[] | select(.[1] | contains("Operations") | not) | .[0]' | awk '{sum += $1} END {printf "%.2f", sum}')
        transaction_total=$(echo "$result" | jq -r '.properties.rows[] | select(.[1] | contains("Operations")) | .[0]' | awk '{sum += $1} END {printf "%.2f", sum}')
        grand_total=$(echo "$result" | jq -r '.properties.rows[] | .[0]' | awk '{sum += $1} END {printf "%.2f", sum}')
        
        # Handle empty results
        [[ -z "$storage_total" || "$storage_total" == "0.00" ]] && storage_total="0.00"
        [[ -z "$transaction_total" || "$transaction_total" == "0.00" ]] && transaction_total="0.00"
        [[ -z "$grand_total" || "$grand_total" == "0.00" ]] && grand_total="0.00"
        
        printf "%-40s | Storage: $%8s | Transactions: $%8s | Total: $%8s\\n" "$resource_name" "$storage_total" "$transaction_total" "$grand_total"
        
        # Return totals for aggregation
        echo "$storage_total,$transaction_total,$grand_total"
    else
        printf "%-40s | No cost data found\\n" "$resource_name"
        echo "0.00,0.00,0.00"
    fi
}

# Function to query costs for multiple resources in batch (OPTIMIZED)
query_batch_resource_costs() {
    local subscription_id="$1"
    local start_date="$2"
    local end_date="$3"
    shift 3
    local resource_ids=("$@")  # Array of resource IDs

    if [[ ${#resource_ids[@]} -eq 0 ]]; then
        echo "{}"
        return 0
    fi

    # Build JSON array of resource IDs
    local resource_ids_json=$(printf ',"%s"' "${resource_ids[@]}")
    resource_ids_json="[${resource_ids_json:1}]"  # Remove leading comma

    echo "Querying costs for ${#resource_ids[@]} resource(s) in batch..." >&2

    # Use retry mechanism for API calls
    local result
    if ! result=$(retry_azure_api az_with_timeout rest --method POST \
      --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
      --body "{
        \"type\": \"ActualCost\",
        \"timeframe\": \"Custom\",
        \"timePeriod\": {
          \"from\": \"$start_date\",
          \"to\": \"$end_date\"
        },
        \"dataset\": {
          \"granularity\": \"None\",
          \"aggregation\": {
            \"totalCost\": {
              \"name\": \"Cost\",
              \"function\": \"Sum\"
            }
          },
          \"grouping\": [
            {
              \"type\": \"Dimension\",
              \"name\": \"ResourceId\"
            }
          ],
          \"filter\": {
            \"dimensions\": {
              \"name\": \"ResourceId\",
              \"operator\": \"In\",
              \"values\": $resource_ids_json
            }
          }
        }
      }"); then
        echo "ERROR: Batch API call failed after retries" >&2
        echo "{}"
        return 1
    fi

    # Return raw JSON for caller to parse
    echo "$result"
}

# Function to query costs for multiple resources in batch with Meter breakdown
# This version groups by both ResourceId AND Meter for Storage/Transaction split
query_batch_resource_costs_with_meter() {
    local subscription_id="$1"
    local start_date="$2"
    local end_date="$3"
    shift 3
    local resource_ids=("$@")  # Array of resource IDs

    if [[ ${#resource_ids[@]} -eq 0 ]]; then
        echo "{}"
        return 0
    fi

    # Build JSON array of resource IDs
    local resource_ids_json=$(printf ',"%s"' "${resource_ids[@]}")
    resource_ids_json="[${resource_ids_json:1}]"  # Remove leading comma

    echo "Querying costs for ${#resource_ids[@]} resource(s) with Meter breakdown..." >&2

    # Use retry mechanism for API calls
    local result
    if ! result=$(retry_azure_api az_with_timeout rest --method POST \
      --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
      --body "{
        \"type\": \"ActualCost\",
        \"timeframe\": \"Custom\",
        \"timePeriod\": {
          \"from\": \"$start_date\",
          \"to\": \"$end_date\"
        },
        \"dataset\": {
          \"granularity\": \"None\",
          \"aggregation\": {
            \"totalCost\": {
              \"name\": \"Cost\",
              \"function\": \"Sum\"
            }
          },
          \"grouping\": [
            {
              \"type\": \"Dimension\",
              \"name\": \"ResourceId\"
            },
            {
              \"type\": \"Dimension\",
              \"name\": \"Meter\"
            }
          ],
          \"filter\": {
            \"dimensions\": {
              \"name\": \"ResourceId\",
              \"operator\": \"In\",
              \"values\": $resource_ids_json
            }
          }
        }
      }"); then
        echo "ERROR: Batch API call with Meter grouping failed after retries" >&2
        echo "{}"
        return 1
    fi

    # Return raw JSON for caller to parse
    echo "$result"
}

# Function to analyze multiple resources
analyze_multiple_resources() {
    local resource_ids=("$@")
    local subscription_id start_date end_date

    # Extract last 3 arguments
    local len=${#resource_ids[@]}
    subscription_id="${resource_ids[$((len-3))]}"
    start_date="${resource_ids[$((len-2))]}"
    end_date="${resource_ids[$((len-1))]}"

    # Remove last 3 arguments to get just resource IDs
    unset resource_ids[$((len-1))] resource_ids[$((len-2))] resource_ids[$((len-3))]

    echo "=== Multiple Resource Cost Analysis ==="
    echo "Period: $start_date to $end_date"
    echo "Subscription: $subscription_id"
    echo ""

    # STEP 1: Collect resource metadata (including sizes for sorting)
    local -a resource_names=()
    local -a resource_sizes=()

    for resource_id in "${resource_ids[@]}"; do
        [[ -z "$resource_id" ]] && continue

        local resource_name=$(basename "$resource_id")
        resource_names+=("$resource_name")

        # Get size based on resource type
        local size=0
        if [[ "$resource_id" == */disks/* ]]; then
            # Query disk size
            size=$(az_with_timeout disk show --ids "$resource_id" --query 'diskSizeGB' -o tsv 2>/dev/null || echo "0")
        elif [[ "$resource_id" == */snapshots/* ]]; then
            # Query snapshot size
            size=$(az_with_timeout snapshot show --ids "$resource_id" --query 'diskSizeGB' -o tsv 2>/dev/null || echo "0")
        fi
        resource_sizes+=("$size")
    done

    # STEP 2: Query costs in batches (with Meter grouping for Storage/Transaction breakdown)
    local batch_size=100
    local total_resources=${#resource_ids[@]}
    local total_batches=$(( (total_resources + batch_size - 1) / batch_size ))

    # Arrays to store cost data: parallel arrays for lookup
    local -a cost_keys=()
    local -a storage_costs=()
    local -a transaction_costs=()
    local -a total_costs=()

    for ((batch_num=0; batch_num<total_batches; batch_num++)); do
        local batch_start=$((batch_num * batch_size))
        local batch_end=$((batch_start + batch_size))
        [[ $batch_end -gt $total_resources ]] && batch_end=$total_resources

        local batch_ids=("${resource_ids[@]:$batch_start:$((batch_end - batch_start))}")

        if [[ $batch_num -gt 0 ]]; then
            sleep 3  # Rate limiting between batches
        fi

        # Query batch with Meter grouping
        local batch_result
        batch_result=$(query_batch_resource_costs_with_meter "$subscription_id" "$start_date" "$end_date" "${batch_ids[@]}")

        # Parse results: group by ResourceId, split Storage vs Operations
        for resource_id in "${batch_ids[@]}"; do
            [[ -z "$resource_id" ]] && continue

            local storage_cost transaction_cost grand_total

            # Extract storage costs (not Operations) - case insensitive comparison
            storage_cost=$(echo "$batch_result" | jq -r --arg rid "$resource_id" \
                '.properties.rows[] | select((.[1] | ascii_downcase) == ($rid | ascii_downcase) and (.[2] | contains("Operations") | not)) | .[0]' \
                | awk '{sum += $1} END {printf "%.2f", sum}')

            # Extract transaction costs (Operations) - case insensitive comparison
            transaction_cost=$(echo "$batch_result" | jq -r --arg rid "$resource_id" \
                '.properties.rows[] | select((.[1] | ascii_downcase) == ($rid | ascii_downcase) and (.[2] | contains("Operations"))) | .[0]' \
                | awk '{sum += $1} END {printf "%.2f", sum}')

            # Calculate grand total - case insensitive comparison
            grand_total=$(echo "$batch_result" | jq -r --arg rid "$resource_id" \
                '.properties.rows[] | select((.[1] | ascii_downcase) == ($rid | ascii_downcase)) | .[0]' \
                | awk '{sum += $1} END {printf "%.2f", sum}')

            # Handle empty results
            [[ -z "$storage_cost" ]] && storage_cost="0.00"
            [[ -z "$transaction_cost" ]] && transaction_cost="0.00"
            [[ -z "$grand_total" ]] && grand_total="0.00"

            cost_keys+=("$resource_id")
            storage_costs+=("$storage_cost")
            transaction_costs+=("$transaction_cost")
            total_costs+=("$grand_total")
        done
    done

    # Sort all resource arrays by size (ascending order) before displaying
    sort_by_size_ascending resource_ids resource_names resource_sizes

    # STEP 3: Print results
    printf "%-40s | %-11s | %-10s | %-10s\\n" "Resource Name" "Storage (\$)" "Trans. (\$)" "Cost (\$)"
    printf "%-40s-|-%11s-|-%10s-|-%10s\\n" \
        "$(printf '%.*s' 40 '-----------------------------------------')" \
        "$(printf '%.*s' 11 '-----------')" \
        "$(printf '%.*s' 10 '----------')" \
        "$(printf '%.*s' 10 '----------')"

    local total_storage=0 total_transactions=0 total_grand=0

    for ((i=0; i<${#resource_ids[@]}; i++)); do
        local resource_id="${resource_ids[$i]}"
        [[ -z "$resource_id" ]] && continue

        local resource_name="${resource_names[$i]}"
        local display_name=$(truncate_name "$resource_name" 40)
        local storage=$(lookup_cost "$resource_id" cost_keys storage_costs)
        local transactions=$(lookup_cost "$resource_id" cost_keys transaction_costs)
        local grand=$(lookup_cost "$resource_id" cost_keys total_costs)

        # Handle lookup failures
        [[ -z "$storage" ]] && storage="0.00"
        [[ -z "$transactions" ]] && transactions="0.00"
        [[ -z "$grand" ]] && grand="0.00"

        printf "%-40s | %11.2f | %10.2f | %10.2f\\n" \
            "$display_name" "$storage" "$transactions" "$grand"

        total_storage=$(echo "$total_storage + $storage" | bc -l)
        total_transactions=$(echo "$total_transactions + $transactions" | bc -l)
        total_grand=$(echo "$total_grand + $grand" | bc -l)
    done

    printf "%-40s-|-%11s-|-%10s-|-%10s\\n" \
        "$(printf '%.*s' 40 '-----------------------------------------')" \
        "$(printf '%.*s' 11 '-----------')" \
        "$(printf '%.*s' 10 '----------')" \
        "$(printf '%.*s' 10 '----------')"
    printf "%-40s | %11.2f | %10.2f | %10.2f\\n" \
        "TOTAL ACROSS ALL RESOURCES" "$total_storage" "$total_transactions" "$total_grand"
}

# Function to analyze ONLY unattached disks (no snapshots)
analyze_unattached_disks_only() {
    local subscription_id="$1"
    local start_date="$2"
    local end_date="$3"
    local resource_group="${4:-}"  # Optional resource group filter
    local include_attached="${5:-false}"  # Optional flag to include attached disks
    local sort_by="${6:-size}"  # Optional: "size" or "rg" (default: size)
    local output_file="${7:-unattached-disks-report-$(date +%Y%m%d-%H%M%S).txt}"
    local skip_tagged="${8:-false}"  # Optional: skip resources with valid future review dates
    local show_tagged_only="${9:-false}"  # Optional: show only resources with review tags

    # Adjust report title based on include_attached flag
    local report_title="AZURE UNATTACHED DISKS COST ANALYSIS REPORT"
    local section_title="UNATTACHED DISKS COST ANALYSIS (Not attached to any VM)"
    if [[ "$include_attached" == "true" ]]; then
        report_title="AZURE ALL DISKS COST ANALYSIS REPORT"
        section_title="ALL DISKS COST ANALYSIS (Attached and Unattached)"
    fi

    echo "=== $report_title ===" | tee "$output_file"
    echo "Generated: $(date)" | tee -a "$output_file"
    echo "Subscription: $subscription_id" | tee -a "$output_file"
    if [[ -n "$resource_group" ]]; then
        echo "Resource Group: $resource_group" | tee -a "$output_file"
    fi
    echo "Analysis Period: $start_date to $end_date" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "NOTE: Azure Cost Management data may take 24-48 hours to finalize." | tee -a "$output_file"
    echo "      Costs for very recent resources may vary between runs as data stabilizes." | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    # Get disks (unattached or all based on flag)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "$section_title" | tee -a "$output_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    local unattached_disks_raw
    unattached_disks_raw=$(list_unattached_disks "$subscription_id" "$resource_group" "$include_attached")

    # Apply tag filtering if enabled
    local unattached_disks_json
    local tag_filter_stats=""
    local tag_name="${CONFIG_REVIEW_DATE_TAG_NAME:-}"
    if [[ -n "$tag_name" && -n "$unattached_disks_raw" ]]; then
        local filtered_result
        filtered_result=$(filter_resources_by_tags \
            "$unattached_disks_raw" \
            "$tag_name" \
            "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
            "$skip_tagged" \
            "$show_tagged_only" 2>/dev/null)

        unattached_disks_json=$(echo "$filtered_result" | jq -r '.resources' 2>/dev/null)
        tag_filter_stats="$filtered_result"
    else
        unattached_disks_json="$unattached_disks_raw"
    fi

    if [[ -n "$unattached_disks_json" ]] && echo "$unattached_disks_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        local disk_count
        disk_count=$(echo "$unattached_disks_json" | jq '. | length')

        local disk_noun="disk(s)"
        if [[ "$include_attached" == "true" ]]; then
            disk_noun="disk(s) (attached and unattached)"
        fi
        echo "Found $disk_count $disk_noun" | tee -a "$output_file"
        echo "" | tee -a "$output_file"

        # STEP 1: Collect all disk IDs and metadata into arrays (show progress before table)
        echo "Collecting disk metadata..." >&2
        local -a disk_ids
        local -a disk_names
        local -a disk_sizes
        local -a disk_skus
        local -a disk_createds
        local -a disk_rgs
        local -a disk_states
        local -a disk_tag_statuses
        local -a disk_tag_dates

        while IFS= read -r disk; do
            disk_ids+=($(echo "$disk" | jq -r '.Id // ""'))
            disk_names+=($(echo "$disk" | jq -r '.Name // "unknown"'))
            disk_sizes+=($(echo "$disk" | jq -r '.Size // 0'))
            disk_skus+=($(echo "$disk" | jq -r '.Sku // "Unknown"'))
            disk_createds+=($(echo "$disk" | jq -r '.Created // "Unknown"' | cut -d'T' -f1))
            disk_rgs+=($(echo "$disk" | jq -r '.ResourceGroup // "Unknown"'))
            disk_states+=($(echo "$disk" | jq -r '.State // "Unknown"'))

            # Extract tag status information
            local tag_status=$(echo "$disk" | jq -r '.TagStatusDetail.tag_status // "none"')
            local review_date=$(echo "$disk" | jq -r '.TagStatusDetail.review_date // ""')
            disk_tag_statuses+=("$tag_status")
            disk_tag_dates+=("$review_date")
        done < <(echo "$unattached_disks_json" | jq -c '.[]')

        # STEP 2: Query costs in batches of 100 and build cost map
        echo "Querying costs for ${#disk_ids[@]} disk(s) in batches..." >&2
        # Parallel arrays for bash 3.2 compatibility (instead of declare -A)
        local -a cost_keys=()    # Resource IDs
        local -a cost_values=()  # Costs
        local batch_size=100
        local total_batches=$(( (${#disk_ids[@]} + batch_size - 1) / batch_size ))

        for ((batch_num=0; batch_num<total_batches; batch_num++)); do
            local start_idx=$((batch_num * batch_size))
            local end_idx=$(( start_idx + batch_size ))
            [[ $end_idx -gt ${#disk_ids[@]} ]] && end_idx=${#disk_ids[@]}

            # Extract batch of disk IDs
            local -a batch_ids=("${disk_ids[@]:$start_idx:$((end_idx - start_idx))}")

            echo "Processing batch $((batch_num + 1))/$total_batches (${#batch_ids[@]} disks)..." >&2

            # Query batch costs
            local batch_result
            batch_result=$(query_batch_resource_costs "$subscription_id" "$start_date" "$end_date" "${batch_ids[@]}")

            # Parse batch results into parallel arrays
            # Result format: {"properties": {"columns": [...], "rows": [[cost, resource_id, currency], ...]}}
            if echo "$batch_result" | jq -e '.properties.rows | length > 0' > /dev/null 2>&1; then
                while IFS=$'\t' read -r cost resource_id currency; do
                    cost_keys+=("$resource_id")
                    cost_values+=("$cost")
                done < <(echo "$batch_result" | jq -r '.properties.rows[] | @tsv')
            fi

            # Rate limiting between batches (not between individual disks!)
            if [[ $((batch_num + 1)) -lt $total_batches ]]; then
                sleep 3
            fi
        done

        # Sort all disk arrays before displaying (based on sort_by parameter)
        if [[ "$sort_by" == "rg" ]]; then
            echo "Sorting disks by Resource Group, then by size..." >&2
            sort_by_rg_then_size disk_ids disk_names disk_skus disk_createds disk_states disk_tag_statuses disk_tag_dates disk_rgs disk_sizes
        elif [[ "$sort_by" == "date" ]]; then
            echo "Sorting disks by creation date (oldest first)..." >&2
            sort_by_created_date disk_ids disk_names disk_skus disk_rgs disk_states disk_tag_statuses disk_tag_dates disk_sizes disk_createds
        else
            echo "Sorting disks by size..." >&2
            sort_by_size_ascending disk_ids disk_names disk_skus disk_createds disk_rgs disk_states disk_tag_statuses disk_tag_dates disk_sizes
        fi

        # Calculate dynamic column width for Resource Group
        echo "Calculating column widths..." >&2
        local max_rg_len=14  # Minimum width for "Resource Group" header
        for ((i=0; i<${#disk_rgs[@]}; i++)); do
            local rg_len=${#disk_rgs[$i]}
            [[ $rg_len -gt $max_rg_len ]] && max_rg_len=$rg_len
        done

        # STEP 3: Loop through disks and print results using cost map (no API calls!)
        echo "Generating report..." >&2
        echo "" | tee -a "$output_file"

        # Generate separator line of appropriate length
        local rg_separator=$(printf '%0.s-' $(seq 1 "$max_rg_len"))

        # Print header with or without State column (using dynamic RG width)
        if [[ "$include_attached" == "true" ]]; then
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | %-12s\n" "Disk Name" "Size GB" "SKU" "Resource Group" "Created" "State" "Cost ($)" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "----------" "------------" | tee -a "$output_file"
        else
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-12s\n" "Disk Name" "Size GB" "SKU" "Resource Group" "Created" "Cost ($)" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "------------" | tee -a "$output_file"
        fi

        local total_disk_cost=0
        local total_disk_size=0

        for ((i=0; i<${#disk_ids[@]}; i++)); do
            local disk_id="${disk_ids[$i]}"
            local disk_name="${disk_names[$i]}"
            local disk_size="${disk_sizes[$i]}"
            local disk_sku="${disk_skus[$i]}"
            local disk_created="${disk_createds[$i]}"
            local disk_rg="${disk_rgs[$i]}"
            local disk_state="${disk_states[$i]}"
            local tag_status="${disk_tag_statuses[$i]}"
            local tag_date="${disk_tag_dates[$i]}"

            # Lookup cost from parallel arrays (bash 3.2 compatible)
            local disk_cost=$(lookup_cost "$disk_id" cost_keys cost_values)

            # Format cost to 2 decimal places
            disk_cost=$(printf "%.2f" "$disk_cost")

            # Build tag annotation if tag filtering is enabled
            local annotation=""
            if [[ -n "$tag_name" ]]; then
                case "$tag_status" in
                    "pending")
                        annotation="  [Review: $tag_date]"
                        ;;
                    "expired")
                        annotation="  [OVERDUE: $tag_date]"
                        ;;
                    "invalid")
                        annotation="  [INVALID TAG: $tag_date]"
                        ;;
                esac
            fi

            # Print row with or without State column (using dynamic RG width)
            if [[ "$include_attached" == "true" ]]; then
                printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | \$%-11s%s\n" \
                    "${disk_name:0:40}" "$disk_size" "${disk_sku:0:15}" "$disk_rg" "$disk_created" "$disk_state" "$disk_cost" "$annotation" | tee -a "$output_file"
            else
                printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | \$%-11s%s\n" \
                    "${disk_name:0:40}" "$disk_size" "${disk_sku:0:15}" "$disk_rg" "$disk_created" "$disk_cost" "$annotation" | tee -a "$output_file"
            fi

            total_disk_cost=$(echo "$total_disk_cost + ${disk_cost:-0}" | bc -l)
            total_disk_size=$((total_disk_size + ${disk_size:-0}))
        done

        # Print footer with or without State column (using dynamic RG width)
        if [[ "$include_attached" == "true" ]]; then
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "----------" "------------" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | \$%-11.2f\n" \
                "Total Disks" "$total_disk_size GB" "" "" "" "" "$total_disk_cost" | tee -a "$output_file"
        else
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "------------" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | \$%-11.2f\n" \
                "Total Disks" "$total_disk_size GB" "" "" "" "$total_disk_cost" | tee -a "$output_file"
        fi
        echo "" | tee -a "$output_file"

        # Show tag filtering summary if enabled
        if [[ -n "$tag_name" && -n "$tag_filter_stats" ]]; then
            local excluded_count=$(echo "$tag_filter_stats" | jq -r '.stats.excluded_pending // 0' 2>/dev/null || echo "0")
            local invalid_count=$(echo "$tag_filter_stats" | jq -r '.stats.invalid_tags // 0' 2>/dev/null || echo "0")

            if [[ $excluded_count -gt 0 || $invalid_count -gt 0 ]]; then
                echo "TAG FILTERING SUMMARY:" | tee -a "$output_file"
                if [[ $excluded_count -gt 0 ]]; then
                    echo "  - Excluded $excluded_count resource(s) with pending review (future dates)" | tee -a "$output_file"
                fi
                if [[ $invalid_count -gt 0 ]]; then
                    echo "  - WARNING: $invalid_count resource(s) have invalid review date tags" | tee -a "$output_file"
                fi
                echo "" | tee -a "$output_file"
            fi
        fi

        # Summary
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
        echo "SUMMARY & RECOMMENDATIONS" | tee -a "$output_file"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "IMMEDIATE ACTION ITEMS:" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "1. UNATTACHED DISKS - Can be deleted (after verification)" | tee -a "$output_file"
        echo "   - Count: $disk_count disk(s)" | tee -a "$output_file"
        echo "   - Total storage: $total_disk_size GB" | tee -a "$output_file"
        printf "   - Current monthly cost: \$%.2f\n" "$total_disk_cost" | tee -a "$output_file"
        printf "   - Annual cost: \$%.2f\n" "$(echo "$total_disk_cost * 12" | bc -l)" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "   ACTION: Review each disk, verify not needed by any VM, then delete" | tee -a "$output_file"
        echo "   COMMAND: az_with_timeout disk delete --name <disk-name> --resource-group <rg-name> --yes" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "   VERIFICATION:" | tee -a "$output_file"
        echo "   - Check Azure Portal for disk details" | tee -a "$output_file"
        echo "   - Verify disk is not part of any backup/DR plan" | tee -a "$output_file"
        echo "   - For PVC disks, check if PVC exists in Kubernetes:" | tee -a "$output_file"
        echo "     kubectl get pvc -A | grep <pvc-id>" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
    else
        echo "✓ No unattached disks found - excellent!" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "Report saved to: $output_file" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "⚠️  IMPORTANT: DO NOT delete resources without proper verification!" | tee -a "$output_file"
    echo "    Always verify in Azure Portal and with your team before deletion." | tee -a "$output_file"

    # Check thresholds and determine exit code
    check_thresholds "$total_disk_cost" "$disk_count"
    local exit_code=$?

    # Output in requested format (JSON, Zabbix, etc.)
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        output_json_summary "unattached-disks" "$total_disk_cost" "$disk_count" "$disk_count" "0" "$exit_code"
    elif [[ "$OUTPUT_FORMAT" == "zabbix" ]]; then
        output_zabbix_metric "azure.storage.unattached.disks.cost_monthly" "$total_disk_cost"
        output_zabbix_metric "azure.storage.unattached.disks.count" "$disk_count"
        output_zabbix_metric "azure.storage.unattached.disks.size_gb" "${total_disk_size:-0}"
    fi

    return $exit_code
}

# Function to generate unused resources report with cost analysis
generate_unused_resources_report() {
    local subscription_id="$1"
    local start_date="$2"
    local end_date="$3"
    local resource_group="${4:-}"  # Optional resource group filter
    local include_attached="${5:-false}"  # Optional flag to include attached disks
    local sort_by="${6:-size}"  # Optional: "size" or "rg" (default: size)
    local output_file="${7:-unused-resources-report-$(date +%Y%m%d-%H%M%S).txt}"
    local skip_tagged="${8:-false}"  # Optional: skip resources with valid future review dates
    local show_tagged_only="${9:-false}"  # Optional: show only resources with review tags

    # For JSON/Zabbix output, suppress all text output to stdout (only write to file)
    # Save original stdout for later restoration
    local text_output_fd
    if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "zabbix" ]]; then
        # Redirect stdout to /dev/null for text output
        exec 3>&1  # Save stdout to fd 3
        exec 1>/dev/null  # Redirect stdout to /dev/null
        text_output_fd=3
    fi

    echo "=== AZURE UNUSED RESOURCES COST ANALYSIS REPORT ===" | tee "$output_file"
    echo "Generated: $(date)" | tee -a "$output_file"
    echo "Subscription: $subscription_id" | tee -a "$output_file"
    if [[ -n "$resource_group" ]]; then
        echo "Resource Group: $resource_group" | tee -a "$output_file"
    fi
    echo "Analysis Period: $start_date to $end_date" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "NOTE: Azure Cost Management data may take 24-48 hours to finalize." | tee -a "$output_file"
    echo "      Costs for very recent resources may vary between runs as data stabilizes." | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    # Section 1: Unattached Disks
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "SECTION 1: UNATTACHED DISKS (Not in use - can be deleted)" | tee -a "$output_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    local unattached_disks_raw
    unattached_disks_raw=$(list_unattached_disks "$subscription_id" "$resource_group" "$include_attached")

    # Apply tag filtering if enabled
    local unattached_disks_json
    local disk_tag_filter_stats=""
    local tag_name="${CONFIG_REVIEW_DATE_TAG_NAME:-}"
    if [[ -n "$tag_name" && -n "$unattached_disks_raw" ]]; then
        local filtered_result
        filtered_result=$(filter_resources_by_tags \
            "$unattached_disks_raw" \
            "$tag_name" \
            "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
            "$skip_tagged" \
            "$show_tagged_only" 2>/dev/null)

        unattached_disks_json=$(echo "$filtered_result" | jq -r '.resources' 2>/dev/null)
        disk_tag_filter_stats="$filtered_result"
    else
        unattached_disks_json="$unattached_disks_raw"
    fi

    if echo "$unattached_disks_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        local disk_count
        disk_count=$(echo "$unattached_disks_json" | jq '. | length')

        # Adjust labels based on include_attached flag
        local disk_noun="unattached disk(s)"
        if [[ "$include_attached" == "true" ]]; then
            disk_noun="disk(s) (attached and unattached)"
        fi
        echo "Found $disk_count $disk_noun" | tee -a "$output_file"
        echo "" | tee -a "$output_file"

        # STEP 1: Collect all disk IDs and metadata into arrays (show progress before table)
        echo "Collecting disk metadata..." >&2
        local -a disk_ids
        local -a disk_names
        local -a disk_sizes
        local -a disk_skus
        local -a disk_createds
        local -a disk_rgs
        local -a disk_states
        local -a disk_tag_statuses
        local -a disk_tag_dates

        while IFS= read -r disk; do
            disk_ids+=($(echo "$disk" | jq -r '.Id // ""'))
            disk_names+=($(echo "$disk" | jq -r '.Name // "unknown"'))
            disk_sizes+=($(echo "$disk" | jq -r '.Size // 0'))
            disk_skus+=($(echo "$disk" | jq -r '.Sku // "Unknown"'))
            disk_createds+=($(echo "$disk" | jq -r '.Created // "Unknown"' | cut -d'T' -f1))
            disk_rgs+=($(echo "$disk" | jq -r '.ResourceGroup // "Unknown"'))
            disk_states+=($(echo "$disk" | jq -r '.State // "Unknown"'))

            # Extract tag status information
            local tag_status=$(echo "$disk" | jq -r '.TagStatusDetail.tag_status // "none"')
            local review_date=$(echo "$disk" | jq -r '.TagStatusDetail.review_date // ""')
            disk_tag_statuses+=("$tag_status")
            disk_tag_dates+=("$review_date")
        done < <(echo "$unattached_disks_json" | jq -c '.[]')

        # STEP 2: Query costs in batches of 100 and build cost map
        echo "Querying costs for ${#disk_ids[@]} disk(s) in batches..." >&2
        # Parallel arrays for bash 3.2 compatibility (instead of declare -A)
        local -a cost_keys=()    # Resource IDs
        local -a cost_values=()  # Costs
        local batch_size=100
        local total_batches=$(( (${#disk_ids[@]} + batch_size - 1) / batch_size ))

        for ((batch_num=0; batch_num<total_batches; batch_num++)); do
            local start_idx=$((batch_num * batch_size))
            local end_idx=$(( start_idx + batch_size ))
            [[ $end_idx -gt ${#disk_ids[@]} ]] && end_idx=${#disk_ids[@]}

            # Extract batch of disk IDs
            local -a batch_ids=("${disk_ids[@]:$start_idx:$((end_idx - start_idx))}")

            echo "Processing batch $((batch_num + 1))/$total_batches (${#batch_ids[@]} disks)..." >&2

            # Query batch costs
            local batch_result
            batch_result=$(query_batch_resource_costs "$subscription_id" "$start_date" "$end_date" "${batch_ids[@]}")

            # Parse batch results into parallel arrays
            # Result format: {"properties": {"columns": [...], "rows": [[cost, resource_id, currency], ...]}}
            if echo "$batch_result" | jq -e '.properties.rows | length > 0' > /dev/null 2>&1; then
                while IFS=$'\t' read -r cost resource_id currency; do
                    cost_keys+=("$resource_id")
                    cost_values+=("$cost")
                done < <(echo "$batch_result" | jq -r '.properties.rows[] | @tsv')
            fi

            # Rate limiting between batches (not between individual disks!)
            if [[ $((batch_num + 1)) -lt $total_batches ]]; then
                sleep 3
            fi
        done

        # Sort all disk arrays before displaying (based on sort_by parameter)
        if [[ "$sort_by" == "rg" ]]; then
            echo "Sorting disks by Resource Group, then by size..." >&2
            sort_by_rg_then_size disk_ids disk_names disk_skus disk_createds disk_states disk_tag_statuses disk_tag_dates disk_rgs disk_sizes
        elif [[ "$sort_by" == "date" ]]; then
            echo "Sorting disks by creation date (oldest first)..." >&2
            sort_by_created_date disk_ids disk_names disk_skus disk_rgs disk_states disk_tag_statuses disk_tag_dates disk_sizes disk_createds
        else
            echo "Sorting disks by size..." >&2
            sort_by_size_ascending disk_ids disk_names disk_skus disk_createds disk_rgs disk_states disk_tag_statuses disk_tag_dates disk_sizes
        fi

        # Calculate dynamic column width for Resource Group
        echo "Calculating column widths..." >&2
        local max_rg_len=14  # Minimum width for "Resource Group" header
        for ((i=0; i<${#disk_rgs[@]}; i++)); do
            local rg_len=${#disk_rgs[$i]}
            [[ $rg_len -gt $max_rg_len ]] && max_rg_len=$rg_len
        done

        # STEP 3: Loop through disks and print results using cost map (no API calls!)
        echo "Generating report..." >&2
        echo "" | tee -a "$output_file"

        # Generate separator line of appropriate length
        local rg_separator=$(printf '%0.s-' $(seq 1 "$max_rg_len"))

        # Print header with or without State column (using dynamic RG width)
        if [[ "$include_attached" == "true" ]]; then
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | %-12s\n" "Disk Name" "Size GB" "SKU" "Resource Group" "Created" "State" "Cost ($)" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "----------" "------------" | tee -a "$output_file"
        else
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-12s\n" "Disk Name" "Size GB" "SKU" "Resource Group" "Created" "Cost ($)" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "------------" | tee -a "$output_file"
        fi

        local total_disk_cost=0
        local total_disk_size=0

        for ((i=0; i<${#disk_ids[@]}; i++)); do
            local disk_id="${disk_ids[$i]}"
            local disk_name="${disk_names[$i]}"
            local disk_size="${disk_sizes[$i]}"
            local disk_sku="${disk_skus[$i]}"
            local disk_created="${disk_createds[$i]}"
            local disk_rg="${disk_rgs[$i]}"
            local disk_state="${disk_states[$i]}"
            local tag_status="${disk_tag_statuses[$i]}"
            local tag_date="${disk_tag_dates[$i]}"

            # Lookup cost from parallel arrays (bash 3.2 compatible)
            local disk_cost=$(lookup_cost "$disk_id" cost_keys cost_values)

            # Format cost to 2 decimal places
            disk_cost=$(printf "%.2f" "$disk_cost")

            # Build tag annotation if tag filtering is enabled
            local annotation=""
            if [[ -n "$tag_name" ]]; then
                case "$tag_status" in
                    "pending")
                        annotation="  [Review: $tag_date]"
                        ;;
                    "expired")
                        annotation="  [OVERDUE: $tag_date]"
                        ;;
                    "invalid")
                        annotation="  [INVALID TAG: $tag_date]"
                        ;;
                esac
            fi

            # Print row with or without State column (using dynamic RG width)
            if [[ "$include_attached" == "true" ]]; then
                printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | \$%-11s%s\n" \
                    "${disk_name:0:40}" "$disk_size" "${disk_sku:0:15}" "$disk_rg" "$disk_created" "$disk_state" "$disk_cost" "$annotation" | tee -a "$output_file"
            else
                printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | \$%-11s%s\n" \
                    "${disk_name:0:40}" "$disk_size" "${disk_sku:0:15}" "$disk_rg" "$disk_created" "$disk_cost" "$annotation" | tee -a "$output_file"
            fi

            total_disk_cost=$(echo "$total_disk_cost + ${disk_cost:-0}" | bc -l)
            total_disk_size=$((total_disk_size + ${disk_size:-0}))
        done

        # Print footer with or without State column (using dynamic RG width)
        if [[ "$include_attached" == "true" ]]; then
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "----------" "------------" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-10s | \$%-11.2f\n" \
                "Total Disks" "$total_disk_size GB" "" "" "" "" "$total_disk_cost" | tee -a "$output_file"
        else
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | %-12s\n" "----------------------------------------" "--------" "---------------" "$rg_separator" "----------" "------------" | tee -a "$output_file"
            printf "%-40s | %-8s | %-15s | %-${max_rg_len}s | %-10s | \$%-11.2f\n" \
                "Total Disks" "$total_disk_size GB" "" "" "" "$total_disk_cost" | tee -a "$output_file"
        fi
        echo "" | tee -a "$output_file"

        # Show tag filtering summary if enabled
        if [[ -n "$tag_name" && -n "$disk_tag_filter_stats" ]]; then
            local excluded_count=$(echo "$disk_tag_filter_stats" | jq -r '.stats.excluded_pending // 0' 2>/dev/null || echo "0")
            local invalid_count=$(echo "$disk_tag_filter_stats" | jq -r '.stats.invalid_tags // 0' 2>/dev/null || echo "0")

            if [[ $excluded_count -gt 0 || $invalid_count -gt 0 ]]; then
                echo "TAG FILTERING SUMMARY:" | tee -a "$output_file"
                if [[ $excluded_count -gt 0 ]]; then
                    echo "  - Excluded $excluded_count resource(s) with pending review (future dates)" | tee -a "$output_file"
                fi
                if [[ $invalid_count -gt 0 ]]; then
                    echo "  - WARNING: $invalid_count resource(s) have invalid review date tags" | tee -a "$output_file"
                fi
                echo "" | tee -a "$output_file"
            fi
        fi
    else
        echo "✓ No unattached disks found - excellent!" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
    fi

    # Section 2: Snapshots
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "SECTION 2: ALL SNAPSHOTS (Manual review needed)" | tee -a "$output_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "NOTE: Snapshots don't have 'attached' state. Review each snapshot to determine if:" | tee -a "$output_file"
    echo "  - It's needed for backup/disaster recovery" | tee -a "$output_file"
    echo "  - It's part of automated backup policy" | tee -a "$output_file"
    echo "  - It can be safely deleted" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    local snapshots_raw
    snapshots_raw=$(get_all_snapshots_with_details "$subscription_id" "$resource_group")

    # Apply tag filtering if enabled
    local snapshots_json
    local snapshot_tag_filter_stats=""
    if [[ -n "$tag_name" && -n "$snapshots_raw" ]]; then
        local filtered_result
        filtered_result=$(filter_resources_by_tags \
            "$snapshots_raw" \
            "$tag_name" \
            "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
            "$skip_tagged" \
            "$show_tagged_only" 2>/dev/null)

        snapshots_json=$(echo "$filtered_result" | jq -r '.resources' 2>/dev/null)
        snapshot_tag_filter_stats="$filtered_result"
    else
        snapshots_json="$snapshots_raw"
    fi

    if echo "$snapshots_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        local snapshot_count
        snapshot_count=$(echo "$snapshots_json" | jq '. | length')

        echo "Found $snapshot_count snapshot(s)" | tee -a "$output_file"
        echo "" | tee -a "$output_file"

        # STEP 1: Collect all snapshot IDs and metadata into arrays (show progress before table)
        echo "Collecting snapshot metadata..." >&2
        local -a snap_ids
        local -a snap_names
        local -a snap_sizes
        local -a snap_skus
        local -a snap_createds
        local -a snap_tag_statuses
        local -a snap_tag_dates

        while IFS= read -r snapshot; do
            snap_ids+=($(echo "$snapshot" | jq -r '.Id // ""'))
            snap_names+=($(echo "$snapshot" | jq -r '.Name // "unknown"'))
            snap_sizes+=($(echo "$snapshot" | jq -r '.Size // 0'))
            snap_skus+=($(echo "$snapshot" | jq -r '.Sku // "Unknown"'))
            snap_createds+=($(echo "$snapshot" | jq -r '.Created // "Unknown"' | cut -d'T' -f1))

            # Extract tag status information
            local tag_status=$(echo "$snapshot" | jq -r '.TagStatusDetail.tag_status // "none"')
            local review_date=$(echo "$snapshot" | jq -r '.TagStatusDetail.review_date // ""')
            snap_tag_statuses+=("$tag_status")
            snap_tag_dates+=("$review_date")
        done < <(echo "$snapshots_json" | jq -c '.[]')

        # STEP 2: Query costs in batches of 100 and build cost map
        echo "Querying costs for ${#snap_ids[@]} snapshot(s) in batches..." >&2
        # Parallel arrays for bash 3.2 compatibility (instead of declare -A)
        local -a snap_cost_keys=()    # Snapshot IDs
        local -a snap_cost_values=()  # Costs
        local batch_size=100
        local total_batches=$(( (${#snap_ids[@]} + batch_size - 1) / batch_size ))

        for ((batch_num=0; batch_num<total_batches; batch_num++)); do
            local start_idx=$((batch_num * batch_size))
            local end_idx=$(( start_idx + batch_size ))
            [[ $end_idx -gt ${#snap_ids[@]} ]] && end_idx=${#snap_ids[@]}

            # Extract batch of snapshot IDs
            local -a batch_ids=("${snap_ids[@]:$start_idx:$((end_idx - start_idx))}")

            echo "Processing batch $((batch_num + 1))/$total_batches (${#batch_ids[@]} snapshots)..." >&2

            # Query batch costs
            local batch_result
            batch_result=$(query_batch_resource_costs "$subscription_id" "$start_date" "$end_date" "${batch_ids[@]}")

            # Parse batch results into parallel arrays
            # Result format: {"properties": {"columns": [...], "rows": [[cost, resource_id, currency], ...]}}
            if echo "$batch_result" | jq -e '.properties.rows | length > 0' > /dev/null 2>&1; then
                while IFS=$'\t' read -r cost resource_id currency; do
                    snap_cost_keys+=("$resource_id")
                    snap_cost_values+=("$cost")
                done < <(echo "$batch_result" | jq -r '.properties.rows[] | @tsv')
            fi

            # Rate limiting between batches (not between individual snapshots!)
            if [[ $((batch_num + 1)) -lt $total_batches ]]; then
                sleep 3
            fi
        done

        # Sort all snapshot arrays before displaying (based on sort_by parameter)
        if [[ "$sort_by" == "date" ]]; then
            echo "Sorting snapshots by creation date (oldest first)..." >&2
            sort_by_created_date snap_ids snap_names snap_skus snap_tag_statuses snap_tag_dates snap_sizes snap_createds
        else
            echo "Sorting snapshots by size..." >&2
            sort_by_size_ascending snap_ids snap_names snap_skus snap_createds snap_tag_statuses snap_tag_dates snap_sizes
        fi

        # STEP 3: Loop through snapshots and print results using cost map (no API calls!)
        echo "Generating report..." >&2
        echo "" | tee -a "$output_file"

        # Print table header
        printf "%-60s | %9s | %-12s | %-10s | %8s\n" "Snapshot Name" "Size (GB)" "SKU" "Created" "Cost (\$)" | tee -a "$output_file"
        printf "%-60s | %9s | %-12s | %-10s | %8s\n" "$(printf '%.*s' 60 '------------------------------------------------------------')" "---------" "------------" "----------" "--------" | tee -a "$output_file"

        local total_snapshot_cost=0
        local total_snapshot_size=0

        for ((i=0; i<${#snap_ids[@]}; i++)); do
            local snap_id="${snap_ids[$i]}"
            local snap_name="${snap_names[$i]}"
            local snap_size="${snap_sizes[$i]}"
            local snap_sku="${snap_skus[$i]}"
            local snap_created="${snap_createds[$i]}"
            local tag_status="${snap_tag_statuses[$i]}"
            local tag_date="${snap_tag_dates[$i]}"

            # Lookup cost from parallel arrays (bash 3.2 compatible)
            local snap_cost=$(lookup_cost "$snap_id" snap_cost_keys snap_cost_values)

            # Format cost to 2 decimal places
            snap_cost=$(printf "%.2f" "$snap_cost")

            # Build tag annotation if tag filtering is enabled
            local annotation=""
            if [[ -n "$tag_name" ]]; then
                case "$tag_status" in
                    "pending")
                        annotation="  [Review: $tag_date]"
                        ;;
                    "expired")
                        annotation="  [OVERDUE: $tag_date]"
                        ;;
                    "invalid")
                        annotation="  [INVALID TAG: $tag_date]"
                        ;;
                esac
            fi

            printf "%-60s | %9s | %-12s | %-10s | \$%7.2f%s\n" \
                "${snap_name:0:60}" "$snap_size" "$snap_sku" "$snap_created" "$snap_cost" "$annotation" | tee -a "$output_file"

            total_snapshot_cost=$(echo "$total_snapshot_cost + ${snap_cost:-0}" | bc -l)
            total_snapshot_size=$((total_snapshot_size + ${snap_size:-0}))
        done

        # Print footer separator
        printf "%-60s | %9s | %-12s | %-10s | %8s\n" "$(printf '%.*s' 60 '------------------------------------------------------------')" "---------" "------------" "----------" "--------" | tee -a "$output_file"
        printf "%-60s | %9s | %-12s | %-10s | \$%7.2f\n" \
            "TOTAL SNAPSHOTS" "$total_snapshot_size GB" "" "" "$total_snapshot_cost" | tee -a "$output_file"
        echo "" | tee -a "$output_file"

        # Show tag filtering summary if enabled
        if [[ -n "$tag_name" && -n "$snapshot_tag_filter_stats" ]]; then
            local excluded_count=$(echo "$snapshot_tag_filter_stats" | jq -r '.stats.excluded_pending // 0' 2>/dev/null || echo "0")
            local invalid_count=$(echo "$snapshot_tag_filter_stats" | jq -r '.stats.invalid_tags // 0' 2>/dev/null || echo "0")

            if [[ $excluded_count -gt 0 || $invalid_count -gt 0 ]]; then
                echo "TAG FILTERING SUMMARY:" | tee -a "$output_file"
                if [[ $excluded_count -gt 0 ]]; then
                    echo "  - Excluded $excluded_count snapshot(s) with pending review (future dates)" | tee -a "$output_file"
                fi
                if [[ $invalid_count -gt 0 ]]; then
                    echo "  - WARNING: $invalid_count snapshot(s) have invalid review date tags" | tee -a "$output_file"
                fi
                echo "" | tee -a "$output_file"
            fi
        fi
    else
        echo "No snapshots found in subscription" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
    fi

    # Section 3: Summary and Recommendations
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "SECTION 3: SUMMARY & RECOMMENDATIONS" | tee -a "$output_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    # Check if unattached_disks_json is not empty before using jq
    if [[ -n "$unattached_disks_json" ]] && echo "$unattached_disks_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        local potential_savings
        potential_savings=$(echo "$unattached_disks_json" | jq '. | length')

        echo "IMMEDIATE ACTION ITEMS:" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "1. UNATTACHED DISKS - Safe to delete (after verification)" | tee -a "$output_file"
        echo "   - Count: $potential_savings disk(s)" | tee -a "$output_file"
        printf "   - Potential monthly savings: \$%.2f\n" "$total_disk_cost" | tee -a "$output_file"
        printf "   - Annual savings potential: \$%.2f\n" "$(echo "$total_disk_cost * 12" | bc -l)" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "   ACTION: Review each disk in Azure Portal, verify not needed, then delete" | tee -a "$output_file"
        echo "   COMMAND: az_with_timeout disk delete --name <disk-name> --resource-group <rg-name>" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
    fi

    # Check if snapshots_json is not empty before using jq
    if [[ -n "$snapshots_json" ]] && echo "$snapshots_json" | jq -e '. | length > 0' > /dev/null 2>&1; then
        echo "2. SNAPSHOTS - Manual review required" | tee -a "$output_file"
        echo "   - Count: $(echo "$snapshots_json" | jq '. | length') snapshot(s)" | tee -a "$output_file"
        printf "   - Current monthly cost: \$%.2f\n" "$total_snapshot_cost" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "   REVIEW CRITERIA:" | tee -a "$output_file"
        echo "   - Is this snapshot older than your retention policy?" | tee -a "$output_file"
        echo "   - Is the source disk still in use?" | tee -a "$output_file"
        echo "   - Is this needed for disaster recovery?" | tee -a "$output_file"
        echo "   - Is this part of an automated backup?" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
        echo "   COMMAND: az_with_timeout snapshot delete --name <snapshot-name> --resource-group <rg-name>" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "Report saved to: $output_file" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "⚠️  IMPORTANT: DO NOT delete resources without proper verification!" | tee -a "$output_file"
    echo "    Always verify in Azure Portal and with your team before deletion." | tee -a "$output_file"

    # Calculate combined totals for threshold checking
    local total_combined_cost
    total_combined_cost=$(echo "${total_disk_cost:-0} + ${total_snapshot_cost:-0}" | bc -l)

    # Get disk and snapshot counts
    local total_disk_count=0
    [[ -n "$unattached_disks_json" ]] && total_disk_count=$(echo "$unattached_disks_json" | jq '. | length' 2>/dev/null || echo 0)
    local total_snapshot_count=0
    [[ -n "$snapshots_json" ]] && total_snapshot_count=$(echo "$snapshots_json" | jq '. | length' 2>/dev/null || echo 0)
    local total_combined_count=$((total_disk_count + total_snapshot_count))

    # Check thresholds and determine exit code
    check_thresholds "$total_combined_cost" "$total_combined_count"
    local exit_code=$?

    # Restore stdout for JSON/Zabbix output if it was redirected
    if [[ -n "$text_output_fd" ]]; then
        exec 1>&3  # Restore original stdout from fd 3
        exec 3>&-  # Close fd 3
    fi

    # Output in requested format (JSON, Zabbix, etc.)
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        output_json_summary "unused-resources" "$total_combined_cost" "$total_combined_count" "$total_disk_count" "$total_snapshot_count" "$exit_code"
    elif [[ "$OUTPUT_FORMAT" == "zabbix" ]]; then
        output_zabbix_metric "azure.storage.unused.total_cost_monthly" "$total_combined_cost"
        output_zabbix_metric "azure.storage.unused.total_count" "$total_combined_count"
        output_zabbix_metric "azure.storage.unattached.disks.count" "$total_disk_count"
        output_zabbix_metric "azure.storage.unattached.disks.cost_monthly" "${total_disk_cost:-0}"
        output_zabbix_metric "azure.storage.snapshots.count" "$total_snapshot_count"
        output_zabbix_metric "azure.storage.snapshots.cost_monthly" "${total_snapshot_cost:-0}"
    fi

    return $exit_code
}

# Function to analyze historical costs (6-month analysis)
analyze_historical_costs() {
    local resource_id="$1"
    local subscription_id="$2"
    local months=("2025-03" "2025-04" "2025-05" "2025-06" "2025-07" "2025-08")
    
    echo ""
    echo "=== 6-Month Historical Cost Analysis ==="
    echo "Resource: $(basename "$resource_id")"
    printf "%-12s | %-15s | %-15s | %-15s\\n" "Month" "Storage" "Transactions" "Total"
    echo "-------------|-----------------|-----------------|----------------"
    
    for month in "${months[@]}"; do
        local start_date="${month}-01T00:00:00+00:00"
        local end_date="${month}-31T23:59:59+00:00"
        
        # Special handling for February
        if [[ "$month" == *"-02" ]]; then
            end_date="${month}-28T23:59:59+00:00"
        fi
        
        sleep 2  # Rate limiting
        
        local result=$(az_with_timeout rest --method POST \
          --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
          --body "{
            \"type\": \"ActualCost\",
            \"timeframe\": \"Custom\",
            \"timePeriod\": {
              \"from\": \"$start_date\",
              \"to\": \"$end_date\"
            },
            \"dataset\": {
              \"granularity\": \"None\",
              \"aggregation\": {
                \"totalCost\": {
                  \"name\": \"Cost\",
                  \"function\": \"Sum\"
                }
              },
              \"grouping\": [
                {
                  \"type\": \"Dimension\",
                  \"name\": \"Meter\"
                }
              ],
              \"filter\": {
                \"dimensions\": {
                  \"name\": \"ResourceId\",
                  \"operator\": \"In\",
                  \"values\": [\"$resource_id\"]
                }
              }
            }
          }")
        
        local storage_cost transaction_cost total_cost
        storage_cost=$(echo "$result" | jq -r '.properties.rows[] | select(.[1] | contains("Operations") | not) | .[0]' | awk '{sum += $1} END {printf "%.2f", sum}')
        transaction_cost=$(echo "$result" | jq -r '.properties.rows[] | select(.[1] | contains("Operations")) | .[0]' | awk '{sum += $1} END {printf "%.2f", sum}')
        total_cost=$(echo "$result" | jq -r '.properties.rows[] | .[0]' | awk '{sum += $1} END {printf "%.2f", sum}')
        
        # Handle empty results
        [[ -z "$storage_cost" || "$storage_cost" == "0.00" ]] && storage_cost="0.00"
        [[ -z "$transaction_cost" || "$transaction_cost" == "0.00" ]] && transaction_cost="0.00"
        [[ -z "$total_cost" || "$total_cost" == "0.00" ]] && total_cost="0.00"
        
        printf "%-12s | $%14s | $%14s | $%14s\\n" "$month" "$storage_cost" "$transaction_cost" "$total_cost"
    done
}

# Date validation function
validate_date_range() {
    local start_date="$1"
    local end_date="$2"

    # Convert dates to seconds since epoch for comparison
    local start_epoch end_epoch max_seconds

    if command -v date >/dev/null 2>&1; then
        if date --version 2>/dev/null | grep -q GNU; then
            # GNU date (Linux)
            start_epoch=$(date -d "$start_date" +%s 2>/dev/null) || {
                echo "Error: Invalid START_DATE format: $start_date"
                echo "Expected format: YYYY-MM-DDTHH:MM:SS+00:00"
                return 1
            }
            end_epoch=$(date -d "$end_date" +%s 2>/dev/null) || {
                echo "Error: Invalid END_DATE format: $end_date"
                echo "Expected format: YYYY-MM-DDTHH:MM:SS+00:00"
                return 1
            }
        else
            # BSD date (macOS) - try multiple formats
            local start_clean end_clean
            # Convert +00:00 to +0000 for BSD date compatibility
            start_clean=$(echo "$start_date" | sed 's/+00:00$/+0000/')
            end_clean=$(echo "$end_date" | sed 's/+00:00$/+0000/')

            start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$start_clean" +%s 2>/dev/null) || {
                # Try without timezone
                start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${start_date%+*}" +%s 2>/dev/null) || {
                    echo "Error: Invalid START_DATE format: $start_date"
                    echo "Expected format: YYYY-MM-DDTHH:MM:SS+00:00 or YYYY-MM-DDTHH:MM:SSZ"
                    return 1
                }
            }
            end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$end_clean" +%s 2>/dev/null) || {
                # Try without timezone
                end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${end_date%+*}" +%s 2>/dev/null) || {
                    echo "Error: Invalid END_DATE format: $end_date"
                    echo "Expected format: YYYY-MM-DDTHH:MM:SS+00:00 or YYYY-MM-DDTHH:MM:SSZ"
                    return 1
                }
            }
        fi
    else
        echo "Warning: date command not available, skipping date range validation"
        return 0
    fi

    # Check if end_date is after start_date
    if [[ $end_epoch -le $start_epoch ]]; then
        echo "Error: END_DATE must be after START_DATE"
        return 1
    fi

    # Check if date range exceeds 1 year (365.25 days = 31,557,600 seconds)
    max_seconds=31557600
    local duration=$((end_epoch - start_epoch))

    if [[ $duration -gt $max_seconds ]]; then
        local days=$((duration / 86400))
        echo "Error: Date range exceeds Azure Cost Management API limit of 1 year"
        echo "Your range: $days days (maximum: 365 days)"
        echo "Please reduce the date range or split into multiple queries"
        return 1
    fi

    return 0
}

# Main script logic
main() {
    # Smart argument parsing: detect if using modern flag syntax or legacy positional syntax
    local resource_identifier="${1:-}"
    local subscription_id=""
    local start_date=""
    local end_date=""
    local positional_count=0

    # Check if $2 is a flag (starts with -) or positional parameter
    if [[ -n "${2:-}" && "${2}" != -* ]]; then
        # Legacy positional syntax: command sub_id [start_date end_date [resource_group]]
        subscription_id="${2:-$DEFAULT_SUBSCRIPTION_ID}"

        if [[ -n "${3:-}" && "${3}" != -* && -n "${4:-}" && "${4}" != -* ]]; then
            start_date="${3:-}"
            end_date="${4:-}"
            positional_count=4
        else
            positional_count=2
        fi
    else
        # Modern flag syntax: command [flags]
        subscription_id="$DEFAULT_SUBSCRIPTION_ID"
        positional_count=1
    fi

    # Parse remaining arguments for resource_group and flags
    local include_attached="false"
    local sort_by="size"  # Default: sort by size
    local resource_group=""
    local explicit_config_path=""

    # Phase 3: Multi-subscription variables
    local subscriptions_input=""  # Can be "all", comma-separated list, or empty (use $subscription_id)
    local subscriptions_file=""   # File containing subscription IDs
    local exclude_subscriptions=""  # Comma-separated list of subscriptions to exclude
    local multi_subscription_mode=false

    # Tag-based exclusion variables
    local skip_tagged="false"       # Skip resources with valid future review dates
    local show_tagged_only="false"  # Show only resources with tags (for reporting)

    # Phase 2: Zabbix integration variables
    local zabbix_send=false       # Enable automatic sending to Zabbix
    local zabbix_server=""        # Zabbix server hostname
    local zabbix_port="10051"     # Zabbix server port (default: 10051)
    local zabbix_host=""          # Zabbix host name for metrics
    local zabbix_config_file=""   # Alternative: use zabbix_agentd.conf
    local zabbix_discovery=""     # LLD discovery type: subscriptions|disks|snapshots|resourcegroups

    local cli_warning_threshold=""
    local cli_critical_threshold=""
    local cli_warning_disk_threshold=""
    local cli_critical_disk_threshold=""

    shift $positional_count  # Remove positional args (1 for modern, 4 for legacy)

    # First pass: Extract --config path (must be processed before load_config)
    local temp_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --config requires a path argument"
                    usage
                fi
                explicit_config_path="$2"
                shift 2
                ;;
            *)
                temp_args+=("$1")
                shift
                ;;
        esac
    done

    # Restore arguments for second pass (handle empty array for strict mode)
    if [[ ${#temp_args[@]} -gt 0 ]]; then
        set -- "${temp_args[@]}"
    else
        set --
    fi

    # Load configuration file (if found)
    # This must happen before applying CLI flags so CLI can override config
    if ! load_config "$explicit_config_path"; then
        # load_config failed (explicit file not found or not readable)
        exit $EXIT_CONFIG_ERROR
    fi

    # Apply config values as defaults (CLI flags will override these)
    [[ -n "$CONFIG_RESOURCE_GROUP" ]] && resource_group="$CONFIG_RESOURCE_GROUP"
    if [[ -n "$CONFIG_INCLUDE_ATTACHED" ]]; then
        local include_attached_value
        include_attached_value=$(echo "$CONFIG_INCLUDE_ATTACHED" | tr '[:upper:]' '[:lower:]')
        case "$include_attached_value" in
            true|1|yes)
                include_attached="true"
                ;;
            false|0|no)
                include_attached="false"
                ;;
        esac
    fi
    [[ -n "$CONFIG_SORT_BY" ]] && sort_by="$CONFIG_SORT_BY"
    [[ -n "$CONFIG_VERBOSITY" ]] && VERBOSITY_LEVEL="$CONFIG_VERBOSITY"
    if [[ -n "$CONFIG_OUTPUT_FORMAT" ]]; then
        case "$CONFIG_OUTPUT_FORMAT" in
            text|json|zabbix)
                OUTPUT_FORMAT="$CONFIG_OUTPUT_FORMAT"
                ;;
            *)
                echo "Error: Invalid output format in config: '$CONFIG_OUTPUT_FORMAT'. Must be text, json, or zabbix"
                exit $EXIT_CONFIG_ERROR
                ;;
        esac
    fi

    if [[ -z "$subscriptions_input" && -n "$CONFIG_SUBSCRIPTIONS" ]]; then
        subscriptions_input="$CONFIG_SUBSCRIPTIONS"
        multi_subscription_mode=true
    fi

    # Second pass: Parse CLI flags (these override config file)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --include-attached)
                include_attached="true"
                shift
                ;;
            --sort-by-rg)
                sort_by="rg"
                shift
                ;;
            --sort-by-size)
                sort_by="size"
                shift
                ;;
            --sort-by-date)
                sort_by="date"
                shift
                ;;
            --silent)
                VERBOSITY_LEVEL="silent"
                shift
                ;;
            --quiet)
                VERBOSITY_LEVEL="quiet"
                shift
                ;;
            --verbose|--debug)
                VERBOSITY_LEVEL="verbose"
                shift
                ;;
            --output-format)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --output-format requires an argument (text|json|zabbix)"
                    usage
                fi
                OUTPUT_FORMAT="$2"
                # Validate format
                case "$OUTPUT_FORMAT" in
                    text|json|zabbix)
                        ;;
                    *)
                        echo "Error: Invalid output format '$OUTPUT_FORMAT'. Must be: text, json, or zabbix"
                        exit $EXIT_CONFIG_ERROR
                        ;;
                esac
                shift 2
                ;;
            --days)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --days requires a number"
                    usage
                fi
                if calculate_date_range "days" "$2"; then
                    start_date="$START_DATE"
                    end_date="$END_DATE"
                else
                    exit $EXIT_CONFIG_ERROR
                fi
                shift 2
                ;;
            --last-month)
                if calculate_date_range "last-month"; then
                    start_date="$START_DATE"
                    end_date="$END_DATE"
                else
                    exit $EXIT_CONFIG_ERROR
                fi
                shift
                ;;
            --warning-threshold)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --warning-threshold requires a numeric USD amount"
                    usage
                fi
                if [[ ! "$2" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
                    echo "Error: --warning-threshold must be a positive number"
                    exit $EXIT_CONFIG_ERROR
                fi
                cli_warning_threshold="$2"
                shift 2
                ;;
            --critical-threshold)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --critical-threshold requires a numeric USD amount"
                    usage
                fi
                if [[ ! "$2" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
                    echo "Error: --critical-threshold must be a positive number"
                    exit $EXIT_CONFIG_ERROR
                fi
                cli_critical_threshold="$2"
                shift 2
                ;;
            --warning-disk-count)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --warning-disk-count requires an integer"
                    usage
                fi
                if [[ ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --warning-disk-count must be a whole number"
                    exit $EXIT_CONFIG_ERROR
                fi
                cli_warning_disk_threshold="$2"
                shift 2
                ;;
            --critical-disk-count)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --critical-disk-count requires an integer"
                    usage
                fi
                if [[ ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --critical-disk-count must be a whole number"
                    exit $EXIT_CONFIG_ERROR
                fi
                cli_critical_disk_threshold="$2"
                shift 2
                ;;
            --current-month)
                if calculate_date_range "current-month"; then
                    start_date="$START_DATE"
                    end_date="$END_DATE"
                else
                    exit $EXIT_CONFIG_ERROR
                fi
                shift
                ;;
            --last-week)
                if calculate_date_range "last-week"; then
                    start_date="$START_DATE"
                    end_date="$END_DATE"
                else
                    exit $EXIT_CONFIG_ERROR
                fi
                shift
                ;;
            --yesterday)
                if calculate_date_range "yesterday"; then
                    start_date="$START_DATE"
                    end_date="$END_DATE"
                else
                    exit $EXIT_CONFIG_ERROR
                fi
                shift
                ;;
            --subscriptions)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --subscriptions requires an argument ('all' or comma-separated list)"
                    usage
                fi
                subscriptions_input="$2"
                multi_subscription_mode=true
                shift 2
                ;;
            --subscriptions-file)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --subscriptions-file requires a file path"
                    usage
                fi
                subscriptions_file="$2"
                if [[ ! -f "$subscriptions_file" ]]; then
                    echo "Error: Subscriptions file not found: $subscriptions_file"
                    exit $EXIT_CONFIG_ERROR
                fi
                multi_subscription_mode=true
                shift 2
                ;;
            --exclude-subscriptions)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --exclude-subscriptions requires a comma-separated list"
                    usage
                fi
                exclude_subscriptions="$2"
                shift 2
                ;;
            --zabbix-send)
                zabbix_send=true
                shift
                ;;
            --zabbix-server)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --zabbix-server requires a hostname"
                    usage
                fi
                zabbix_server="$2"
                shift 2
                ;;
            --zabbix-port)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --zabbix-port requires a port number"
                    usage
                fi
                zabbix_port="$2"
                shift 2
                ;;
            --zabbix-host)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --zabbix-host requires a hostname"
                    usage
                fi
                zabbix_host="$2"
                shift 2
                ;;
            --zabbix-config)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --zabbix-config requires a config file path"
                    usage
                fi
                if [[ ! -f "$2" ]]; then
                    echo "Error: Zabbix config file not found: $2"
                    exit $EXIT_CONFIG_ERROR
                fi
                zabbix_config_file="$2"
                shift 2
                ;;
            --zabbix-discovery)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --zabbix-discovery requires a type (subscriptions|disks|snapshots|resourcegroups)"
                    usage
                fi
                zabbix_discovery="$2"
                # Validate discovery type
                case "$zabbix_discovery" in
                    subscriptions|disks|snapshots|resourcegroups)
                        # Valid
                        ;;
                    *)
                        echo "Error: Invalid discovery type '$zabbix_discovery'. Must be: subscriptions, disks, snapshots, or resourcegroups"
                        exit $EXIT_CONFIG_ERROR
                        ;;
                esac
                shift 2
                ;;
            --skip-tagged)
                skip_tagged="true"
                shift
                ;;
            --show-tagged-only)
                show_tagged_only="true"
                shift
                ;;
            --resource-group|-g)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --resource-group requires a resource group name"
                    usage
                fi
                resource_group="$2"
                shift 2
                ;;
            *)
                # If not a flag, treat as resource_group (only if not already set via flag)
                # This maintains backward compatibility with positional parameter
                if [[ -z "$resource_group" && "$1" != "" ]]; then
                    resource_group="$1"
                fi
                shift
                ;;
        esac
    done

    [[ -n "$cli_warning_threshold" ]] && CONFIG_THRESHOLD_WARNING_MONTHLY="$cli_warning_threshold"
    [[ -n "$cli_critical_threshold" ]] && CONFIG_THRESHOLD_CRITICAL_MONTHLY="$cli_critical_threshold"
    [[ -n "$cli_warning_disk_threshold" ]] && CONFIG_THRESHOLD_WARNING_DISK_COUNT="$cli_warning_disk_threshold"
    [[ -n "$cli_critical_disk_threshold" ]] && CONFIG_THRESHOLD_CRITICAL_DISK_COUNT="$cli_critical_disk_threshold"

    if [[ -z "$start_date" && -z "$end_date" && -n "$CONFIG_DATE_RANGE_DAYS" ]]; then
        if [[ "$CONFIG_DATE_RANGE_DAYS" =~ ^[0-9]+$ ]]; then
            if calculate_date_range "days" "$CONFIG_DATE_RANGE_DAYS"; then
                start_date="$START_DATE"
                end_date="$END_DATE"
            else
                exit $EXIT_CONFIG_ERROR
            fi
        else
            echo "Error: date_range_days in config must be an integer"
            exit $EXIT_CONFIG_ERROR
        fi
    fi

    # Handle subscriptions file
    if [[ -n "$subscriptions_file" ]]; then
        # Read subscriptions from file (one per line, skip empty lines and comments)
        subscriptions_input=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            # Strip whitespace
            line=$(echo "$line" | xargs)
            [[ -n "$line" ]] && subscriptions_input="${subscriptions_input}${subscriptions_input:+,}${line}"
        done < "$subscriptions_file"

        if [[ -z "$subscriptions_input" ]]; then
            echo "Error: No valid subscriptions found in file: $subscriptions_file"
            exit $EXIT_CONFIG_ERROR
        fi
    fi

    # Handle empty subscription ID (for single-subscription mode)
    if [[ -z "$subscription_id" && "$multi_subscription_mode" == "false" ]]; then
        subscription_id="$DEFAULT_SUBSCRIPTION_ID"
    fi

    # Check Azure login
    if ! az_with_timeout account show &>/dev/null; then
        echo "Error: Not logged in to Azure. Please run 'az login' first."
        exit $EXIT_CONFIG_ERROR
    fi

    # Set subscription (only for single-subscription mode)
    if [[ "$multi_subscription_mode" == "false" ]]; then
        az_with_timeout account set --subscription "$subscription_id" >/dev/null

        # Validate permissions for single subscription
        log_progress "Validating Azure permissions..."
        if ! validate_azure_permissions "$subscription_id"; then
            echo "Error: Insufficient permissions on subscription: $subscription_id"
            exit $EXIT_CONFIG_ERROR
        fi
    fi

    case "$resource_identifier" in
        "list-disks")
            list_disks "$subscription_id" "$resource_group"
            exit $EXIT_SUCCESS
            ;;
        "list-snapshots")
            list_snapshots "$subscription_id"
            exit $EXIT_SUCCESS
            ;;
        "zabbix-discovery")
            # Handle Zabbix Low-Level Discovery
            if [[ -z "$zabbix_discovery" ]]; then
                echo "Error: --zabbix-discovery flag required with type (subscriptions|disks|snapshots)"
                usage
            fi

            case "$zabbix_discovery" in
                subscriptions)
                    generate_subscriptions_lld
                    ;;
                disks)
                    generate_disks_lld "$subscription_id" "$resource_group"
                    ;;
                snapshots)
                    generate_snapshots_lld "$subscription_id" "$resource_group"
                    ;;
                resourcegroups)
                    generate_resource_groups_lld "$subscription_id"
                    ;;
                *)
                    echo "Error: Invalid discovery type: $zabbix_discovery"
                    exit $EXIT_CONFIG_ERROR
                    ;;
            esac
            exit $EXIT_SUCCESS
            ;;
        "unattached-disks-only")
            if [[ -z "$start_date" || -z "$end_date" ]]; then
                echo "Error: START_DATE and END_DATE required for cost analysis"
                usage
            fi
            if ! validate_date_range "$start_date" "$end_date"; then
                exit $EXIT_CONFIG_ERROR
            fi
            analyze_unattached_disks_only "$subscription_id" "$start_date" "$end_date" "$resource_group" "$include_attached" "$sort_by" "" "$skip_tagged" "$show_tagged_only"
            exit $?
            ;;
        "unused-report")
            if [[ -z "$start_date" || -z "$end_date" ]]; then
                echo "Error: START_DATE and END_DATE required for unused resources report"
                usage
            fi
            if ! validate_date_range "$start_date" "$end_date"; then
                exit $EXIT_CONFIG_ERROR
            fi

            # multi_subscription_mode -> process_multi_subscription; apply Zabbix config defaults if not set via CLI
            [[ -z "$zabbix_server" && -n "${CONFIG_ZABBIX_SERVER:-}" ]] && zabbix_server="$CONFIG_ZABBIX_SERVER"
            [[ -z "$zabbix_port" && -n "${CONFIG_ZABBIX_PORT:-}" ]] && zabbix_port="$CONFIG_ZABBIX_PORT"
            [[ -z "$zabbix_host" && -n "${CONFIG_ZABBIX_HOSTNAME:-}" ]] && zabbix_host="$CONFIG_ZABBIX_HOSTNAME"
            [[ -z "$zabbix_config_file" && -n "${CONFIG_ZABBIX_CONFIG:-}" ]] && zabbix_config_file="$CONFIG_ZABBIX_CONFIG"
            [[ "${CONFIG_ZABBIX_AUTO_SEND:-}" == "true" ]] && zabbix_send=true

            # Check if multi-subscription mode is enabled
            if [[ "$multi_subscription_mode" == "true" ]]; then
                # Multi-subscription analysis
                local report_output
                local exit_code
                report_output=$(process_multi_subscription "$subscriptions_input" "$start_date" "$end_date" "$resource_group" "$include_attached" "$exclude_subscriptions")
                exit_code=$?

                # Output the report
                echo "$report_output"

                # Send to Zabbix if enabled and output format is JSON
                if [[ "$zabbix_send" == "true" && "$OUTPUT_FORMAT" == "json" ]]; then
                    if [[ -n "$zabbix_server" && -n "$zabbix_host" ]]; then
                        log_progress "Sending metrics to Zabbix..."
                        local timestamp=$(date +%s)
                        local batch_file=$(create_zabbix_batch_file "$zabbix_host" "$timestamp" "$report_output")

                        if send_batch_to_zabbix "$zabbix_server" "$zabbix_port" "$batch_file"; then
                            log_progress "Metrics successfully sent to Zabbix"
                        else
                            log_progress "WARNING: Failed to send metrics to Zabbix"
                        fi
                    elif [[ -n "$zabbix_config_file" ]]; then
                        log_progress "Sending metrics to Zabbix using config file..."
                        local timestamp=$(date +%s)
                        local batch_file=$(create_zabbix_batch_file "${zabbix_host:-azure-storage-monitor}" "$timestamp" "$report_output")

                        if send_batch_to_zabbix_with_config "$zabbix_config_file" "$batch_file"; then
                            log_progress "Metrics successfully sent to Zabbix"
                        else
                            log_progress "WARNING: Failed to send metrics to Zabbix"
                        fi
                    else
                        log_progress "ERROR: --zabbix-send requires either (--zabbix-server and --zabbix-host) or --zabbix-config"
                    fi
                fi

                exit $exit_code
            else
                # Single subscription analysis
                generate_unused_resources_report "$subscription_id" "$start_date" "$end_date" "$resource_group" "$include_attached" "$sort_by" "" "$skip_tagged" "$show_tagged_only"
                exit $?
            fi
            ;;
        "all-disks")
            if [[ -z "$start_date" || -z "$end_date" ]]; then
                echo "Error: START_DATE and END_DATE required for cost analysis"
                usage
            fi
            if ! validate_date_range "$start_date" "$end_date"; then
                exit $EXIT_CONFIG_ERROR
            fi
            echo "Getting all managed disks..."
            declare -a disk_ids
            while IFS= read -r line; do
                [[ -n "$line" ]] && disk_ids+=("$line")
            done < <(get_all_disk_resource_ids "$subscription_id" "$resource_group")
            if [[ ${#disk_ids[@]} -eq 0 ]]; then
                echo "=== Multiple Resource Cost Analysis ==="
                echo "No managed disks found for the specified scope."
                exit $EXIT_SUCCESS
            fi
            analyze_multiple_resources "${disk_ids[@]}" "$subscription_id" "$start_date" "$end_date"
            ;;
        "all-snapshots")
            if [[ -z "$start_date" || -z "$end_date" ]]; then
                echo "Error: START_DATE and END_DATE required for cost analysis"
                usage
            fi
            if ! validate_date_range "$start_date" "$end_date"; then
                exit $EXIT_CONFIG_ERROR
            fi
            echo "Getting all snapshots..."
            declare -a snapshot_ids
            while IFS= read -r line; do
                [[ -n "$line" ]] && snapshot_ids+=("$line")
            done < <(get_all_snapshot_resource_ids "$subscription_id" "$resource_group")
            if [[ ${#snapshot_ids[@]} -eq 0 ]]; then
                echo "=== Multiple Resource Cost Analysis ==="
                echo "No snapshots found for the specified scope."
                exit $EXIT_SUCCESS
            fi
            analyze_multiple_resources "${snapshot_ids[@]}" "$subscription_id" "$start_date" "$end_date"
            ;;
        "historical")
            local pg_resource_id
            pg_resource_id=$(construct_disk_resource_id "$DEFAULT_PG_DISK" "$subscription_id" "$DEFAULT_RESOURCE_GROUP")
            analyze_historical_costs "$pg_resource_id" "$subscription_id"
            ;;
        "")
            # Use PostgreSQL default
            local pg_resource_id
            pg_resource_id=$(construct_disk_resource_id "$DEFAULT_PG_DISK" "$subscription_id" "$DEFAULT_RESOURCE_GROUP")
            if [[ -z "$start_date" || -z "$end_date" ]]; then
                echo "Error: START_DATE and END_DATE required for cost analysis"
                usage
            fi
            if ! validate_date_range "$start_date" "$end_date"; then
                exit $EXIT_CONFIG_ERROR
            fi
            echo "=== Single Resource Cost Analysis ==="
            query_resource_costs "$pg_resource_id" "$subscription_id" "$start_date" "$end_date"
            ;;
        *)
            # Handle resource identifier
            local resource_id=""
            
            if [[ "$resource_identifier" =~ ^/subscriptions/ ]]; then
                # Full resource ID provided
                resource_id="$resource_identifier"
            elif [[ "$resource_identifier" =~ ^pvc- ]] || [[ "$resource_identifier" =~ ^snapshot- ]] || [[ ${#resource_identifier} -gt 10 ]]; then
                # Disk or snapshot name provided - construct full resource ID
                if [[ "$resource_identifier" =~ ^snapshot- ]]; then
                    resource_id="/subscriptions/$subscription_id/resourceGroups/$DEFAULT_RESOURCE_GROUP/providers/Microsoft.Compute/snapshots/$resource_identifier"
                else
                    resource_id=$(construct_disk_resource_id "$resource_identifier" "$subscription_id" "$DEFAULT_RESOURCE_GROUP")
                fi
            else
                echo "Error: Invalid resource identifier: $resource_identifier"
                usage
            fi
            
            if [[ -z "$start_date" || -z "$end_date" ]]; then
                echo "Error: START_DATE and END_DATE required for cost analysis"
                usage
            fi
            if ! validate_date_range "$start_date" "$end_date"; then
                exit $EXIT_CONFIG_ERROR
            fi

            echo "=== Single Resource Cost Analysis ==="
            query_resource_costs "$resource_id" "$subscription_id" "$start_date" "$end_date"
            ;;
    esac
}

# Show usage if no arguments
if [[ $# -eq 0 ]]; then
    usage
fi

# Check for required dependencies before execution
# This prevents the script from failing 10 minutes into execution
if ! check_dependencies; then
    exit $EXIT_CONFIG_ERROR
fi

# Run main function
main "$@"
