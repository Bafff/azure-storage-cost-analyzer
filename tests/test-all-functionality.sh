#!/bin/bash
# Automated tests for Azure Storage Cost Analysis script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/azure-storage-cost-analyzer.sh"

# Test configuration
TEST_SUBSCRIPTION="2f929c0a-d1f4-480c-a610-f75d1862fd53"
TEST_START_DATE="2025-10-06T00:00:00+00:00"
TEST_END_DATE="2025-10-13T23:59:59+00:00"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_pattern="$3"

    echo -e "${YELLOW}Testing:${NC} $test_name"
    echo "Command: $command"

    if output=$(eval "$command" 2>&1); then
        if echo "$output" | grep -q "$expected_pattern"; then
            echo -e "${GREEN}✓ PASSED${NC}"
            ((TESTS_PASSED++))
            return 0
        else
            echo -e "${RED}✗ FAILED${NC} - Expected pattern not found: $expected_pattern"
            echo "Output: $output"
            ((TESTS_FAILED++))
            return 1
        fi
    else
        echo -e "${RED}✗ FAILED${NC} - Command failed"
        ((TESTS_FAILED++))
        return 1
    fi
    echo ""
}

echo "========================================"
echo "Azure Storage Cost Analysis - Test Suite"
echo "========================================"
echo "Subscription: $TEST_SUBSCRIPTION"
echo "Period: $TEST_START_DATE to $TEST_END_DATE"
echo ""

# Test 1: List disks (no cost analysis)
run_test "List all disks" \
    "'$SCRIPT_PATH' list-disks '$TEST_SUBSCRIPTION'" \
    "All Managed Disks in Subscription"

# Test 2: List snapshots (no cost analysis)
run_test "List all snapshots" \
    "'$SCRIPT_PATH' list-snapshots '$TEST_SUBSCRIPTION'" \
    "All Snapshots in Subscription"

# Test 3: Unattached disks only (no snapshots)
run_test "Unattached disks only" \
    "'$SCRIPT_PATH' unattached-disks-only '$TEST_SUBSCRIPTION' '$TEST_START_DATE' '$TEST_END_DATE'" \
    "UNATTACHED DISKS COST ANALYSIS"

# Test 4: All disks analysis
run_test "All disks analysis" \
    "'$SCRIPT_PATH' all-disks '$TEST_SUBSCRIPTION' '$TEST_START_DATE' '$TEST_END_DATE'" \
    "Multiple Resource Cost Analysis"

# Test 5: All snapshots analysis
run_test "All snapshots analysis" \
    "'$SCRIPT_PATH' all-snapshots '$TEST_SUBSCRIPTION' '$TEST_START_DATE' '$TEST_END_DATE'" \
    "Multiple Resource Cost Analysis"

# Test 6: Unused resources report (unattached disks + all snapshots)
run_test "Unused resources report" \
    "'$SCRIPT_PATH' unused-report '$TEST_SUBSCRIPTION' '$TEST_START_DATE' '$TEST_END_DATE'" \
    "AZURE UNUSED RESOURCES COST ANALYSIS REPORT"

# Test 7: Include attached disks (--include-attached flag)
run_test "Include attached disks flag" \
    "'$SCRIPT_PATH' unused-report '$TEST_SUBSCRIPTION' '$TEST_START_DATE' '$TEST_END_DATE' '' --include-attached" \
    "attached and unattached"

# Test 8: Resource group filtering
# Note: This test assumes at least one resource group exists
echo -e "${YELLOW}Testing:${NC} Resource group filtering"
# Get first resource group from subscription
FIRST_RG=$(az group list --subscription "$TEST_SUBSCRIPTION" --query '[0].name' -o tsv 2>/dev/null || echo "")
if [[ -n "$FIRST_RG" ]]; then
    run_test "Resource group filtering" \
        "'$SCRIPT_PATH' all-disks '$TEST_SUBSCRIPTION' '$TEST_START_DATE' '$TEST_END_DATE' '$FIRST_RG'" \
        "Multiple Resource Cost Analysis"
else
    echo -e "${YELLOW}⊘ SKIPPED${NC} - No resource groups found"
fi

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
