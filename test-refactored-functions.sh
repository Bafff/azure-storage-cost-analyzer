#!/bin/bash
# Test script for refactored analyze_multiple_resources() function

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/azure-storage-cost-analyzer.sh"

# Test configuration
SUBSCRIPTION_ID="03d76f78-4676-4116-b53a-162546996207"
START_DATE="2025-10-06T00:00:00+00:00"
END_DATE="2025-10-13T23:59:59+00:00"
RESOURCE_GROUP="MC_internal-aks-dev-rg_internal-aks-dev_centralus"

echo "=================================="
echo "Testing Refactored Functions"
echo "=================================="
echo ""
echo "Subscription: $SUBSCRIPTION_ID"
echo "Period: $START_DATE to $END_DATE"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Test 1: all-disks command (uses analyze_multiple_resources)
echo "=================================="
echo "Test 1: all-disks command"
echo "=================================="
"$SCRIPT_PATH" all-disks "$SUBSCRIPTION_ID" "$START_DATE" "$END_DATE" "$RESOURCE_GROUP"
echo ""
echo "✅ Test 1 completed"
echo ""

# Test 2: all-snapshots command (uses analyze_multiple_resources)
echo "=================================="
echo "Test 2: all-snapshots command"
echo "=================================="
"$SCRIPT_PATH" all-snapshots "$SUBSCRIPTION_ID" "$START_DATE" "$END_DATE" "$RESOURCE_GROUP"
echo ""
echo "✅ Test 2 completed"
echo ""

# Test 3: unattached-report command (uses analyze_unattached_disks_only)
echo "=================================="
echo "Test 3: unattached-report command"
echo "=================================="
"$SCRIPT_PATH" unattached-report "$SUBSCRIPTION_ID" "$START_DATE" "$END_DATE" "$RESOURCE_GROUP"
echo ""
echo "✅ Test 3 completed"
echo ""

# Test 4: unused-report command (uses generate_unused_resources_report)
echo "=================================="
echo "Test 4: unused-report command"
echo "=================================="
"$SCRIPT_PATH" unused-report "$SUBSCRIPTION_ID" "$START_DATE" "$END_DATE" "$RESOURCE_GROUP"
echo ""
echo "✅ Test 4 completed"
echo ""

echo "=================================="
echo "All Tests Completed Successfully!"
echo "=================================="
