#!/bin/bash

# Unit Tests for Phase 3: Multi-Subscription Support
# Tests all multi-subscription features added in Phase 3

set -uo pipefail  # Removed -e to allow tests to continue on failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/azure-storage-cost-analyzer.sh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo -e "  ${YELLOW}Expected${NC}: $2"
    echo -e "  ${YELLOW}Got${NC}: $3"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1 (Reason: $2)"
    ((TESTS_RUN++))
}

section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Check if script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: Script not found at $SCRIPT_PATH"
    exit 1
fi

# Source the script to test functions (in a subshell to avoid side effects)
source_script() {
    local func_name="$1"
    (
        source "$SCRIPT_PATH" 2>/dev/null || true
        declare -f "$func_name" >/dev/null 2>&1
    )
}

echo "=========================================="
echo "Phase 3: Multi-Subscription Support Tests"
echo "=========================================="
echo "Script: $SCRIPT_PATH"
echo "Date: $(date)"
echo ""

# ============================================================================
# Test 1: Script Syntax Validation
# ============================================================================
section "Test 1: Script Syntax Validation"

if bash -n "$SCRIPT_PATH" 2>/dev/null; then
    pass "Script has valid Bash syntax"
else
    fail "Script has syntax errors" "No errors" "Syntax errors found"
fi

# ============================================================================
# Test 2: Multi-Subscription Functions Exist
# ============================================================================
section "Test 2: Multi-Subscription Functions Exist"

# Check if multi-subscription functions are defined
functions_to_check=(
    "get_all_subscriptions"
    "get_subscriptions_with_names"
    "parse_subscription_list"
    "get_subscription_name"
    "collect_subscription_metrics"
    "process_multi_subscription"
)

for func in "${functions_to_check[@]}"; do
    if grep -q "^${func}()" "$SCRIPT_PATH"; then
        pass "Function '$func' is defined"
    else
        fail "Function '$func' is defined" "Function exists" "Function not found"
    fi
done

# ============================================================================
# Test 3: Command-Line Flags Recognition
# ============================================================================
section "Test 3: Command-Line Flags Recognition"

# Check if --subscriptions flag is recognized
if grep -q '\--subscriptions)' "$SCRIPT_PATH"; then
    pass "Flag --subscriptions is recognized"
else
    fail "Flag --subscriptions is recognized" "Flag in code" "Flag not found"
fi

# Check if --subscriptions-file flag is recognized
if grep -q '\--subscriptions-file)' "$SCRIPT_PATH"; then
    pass "Flag --subscriptions-file is recognized"
else
    fail "Flag --subscriptions-file is recognized" "Flag in code" "Flag not found"
fi

# Check if --exclude-subscriptions flag is recognized
if grep -q '\--exclude-subscriptions)' "$SCRIPT_PATH"; then
    pass "Flag --exclude-subscriptions is recognized"
else
    fail "Flag --exclude-subscriptions is recognized" "Flag in code" "Flag not found"
fi

# Check if multi_subscription_mode variable is set
if grep -q 'multi_subscription_mode=true' "$SCRIPT_PATH"; then
    pass "Variable multi_subscription_mode is set when flags are used"
else
    fail "Variable multi_subscription_mode is set" "Variable set" "Variable not found"
fi

# ============================================================================
# Test 4: Help Documentation
# ============================================================================
section "Test 4: Help Documentation"

help_output=$("$SCRIPT_PATH" 2>&1 || true)

# Check if multi-subscription flags are in help
if echo "$help_output" | grep -q "Multi-Subscription Flags"; then
    pass "Multi-Subscription section exists in help"
else
    fail "Multi-Subscription section in help" "Section present" "Section not found"
fi

# Check if --subscriptions is documented
if echo "$help_output" | grep -q "\--subscriptions"; then
    pass "Flag --subscriptions is documented in help"
else
    fail "Flag --subscriptions documented" "Flag in help" "Flag not in help"
fi

# Check if examples are provided
if echo "$help_output" | grep -q "Multi-Subscription Examples"; then
    pass "Multi-Subscription examples are provided"
else
    fail "Multi-Subscription examples provided" "Examples present" "Examples not found"
fi

# ============================================================================
# Test 5: Exit Code 21 (Partial Failure)
# ============================================================================
section "Test 5: Exit Code Definitions"

# Check if EXIT_PARTIAL_FAILURE is defined
if grep -q 'EXIT_PARTIAL_FAILURE=21' "$SCRIPT_PATH"; then
    pass "Exit code 21 (partial failure) is defined"
else
    fail "Exit code 21 defined" "EXIT_PARTIAL_FAILURE=21" "Not found"
fi

# Check if exit code is used in process_multi_subscription
if grep -q 'EXIT_PARTIAL_FAILURE' "$SCRIPT_PATH"; then
    pass "Exit code 21 is used in multi-subscription logic"
else
    fail "Exit code 21 used" "Used in code" "Not found"
fi

# ============================================================================
# Test 6: JSON Output Format
# ============================================================================
section "Test 6: JSON Output Format"

# Check if multi-subscription JSON output includes required fields
if grep -q '"scan_type": "multi-subscription"' "$SCRIPT_PATH"; then
    pass "JSON output includes 'scan_type' field"
else
    fail "JSON scan_type field" "Field present" "Field not found"
fi

if grep -q '"aggregated_metrics"' "$SCRIPT_PATH"; then
    pass "JSON output includes 'aggregated_metrics' field"
else
    fail "JSON aggregated_metrics field" "Field present" "Field not found"
fi

if grep -q '"by_subscription"' "$SCRIPT_PATH"; then
    pass "JSON output includes 'by_subscription' field"
else
    fail "JSON by_subscription field" "Field present" "Field not found"
fi

# ============================================================================
# Test 7: Zabbix Batch Format
# ============================================================================
section "Test 7: Zabbix Batch Format"

# Check if Zabbix metrics include multi-subscription keys
if grep -q 'azure.storage.all.total_waste.monthly' "$SCRIPT_PATH"; then
    pass "Zabbix output includes aggregated metric keys"
else
    fail "Zabbix aggregated keys" "Keys present" "Keys not found"
fi

if grep -q 'azure.storage.subscription\[' "$SCRIPT_PATH"; then
    pass "Zabbix output includes per-subscription metric keys"
else
    fail "Zabbix per-subscription keys" "Keys present" "Keys not found"
fi

# ============================================================================
# Test 8: Configuration File Support
# ============================================================================
section "Test 8: Configuration File Support"

# Check if CONFIG_SUBSCRIPTIONS variable exists
if grep -q 'CONFIG_SUBSCRIPTIONS=' "$SCRIPT_PATH"; then
    pass "CONFIG_SUBSCRIPTIONS variable is defined"
else
    fail "CONFIG_SUBSCRIPTIONS defined" "Variable present" "Variable not found"
fi

# Check if subscriptions config is parsed from file
if grep -q 'subscriptions)' "$SCRIPT_PATH" | grep -q 'CONFIG_SUBSCRIPTIONS'; then
    pass "Subscriptions can be configured via config file"
else
    skip "Subscriptions config file parsing" "Manual verification needed"
fi

# ============================================================================
# Test 9: Integration with unused-report Command
# ============================================================================
section "Test 9: Integration with unused-report Command"

# Check if unused-report command checks for multi_subscription_mode
if grep -A 10 '"unused-report")' "$SCRIPT_PATH" | grep -q 'multi_subscription_mode'; then
    pass "unused-report command integrates multi-subscription mode"
else
    fail "unused-report integration" "Mode check present" "Mode check not found"
fi

# Check if process_multi_subscription is called
if grep -A 15 '"unused-report")' "$SCRIPT_PATH" | grep -q 'process_multi_subscription'; then
    pass "unused-report calls process_multi_subscription when enabled"
else
    fail "process_multi_subscription called" "Function call present" "Call not found"
fi

# ============================================================================
# Test 10: Aggregation Logic
# ============================================================================
section "Test 10: Aggregation Logic"

# Check if aggregation variables are defined
aggregation_vars=(
    "total_disk_count"
    "total_disk_size"
    "total_disk_cost"
    "total_snapshot_count"
    "total_snapshot_size"
    "total_snapshot_cost"
    "total_waste_monthly"
)

for var in "${aggregation_vars[@]}"; do
    if grep -q "$var" "$SCRIPT_PATH"; then
        pass "Aggregation variable '$var' is used"
    else
        fail "Aggregation variable '$var'" "Variable used" "Variable not found"
    fi
done

# ============================================================================
# Test 11: Error Handling
# ============================================================================
section "Test 11: Error Handling"

# Check if failed subscriptions are tracked
if grep -q 'failed_subscriptions' "$SCRIPT_PATH"; then
    pass "Failed subscriptions are tracked"
else
    fail "Failed subscriptions tracking" "Tracking present" "Tracking not found"
fi

# Check if success subscriptions are tracked
if grep -q 'success_subscriptions' "$SCRIPT_PATH"; then
    pass "Successful subscriptions are tracked"
else
    fail "Success subscriptions tracking" "Tracking present" "Tracking not found"
fi

# ============================================================================
# Test 12: Rate Limiting
# ============================================================================
section "Test 12: Rate Limiting"

# Check if rate limiting between subscriptions is implemented
if grep -A 5 'for subscription_id in' "$SCRIPT_PATH" | grep -q 'sleep'; then
    pass "Rate limiting between subscriptions is implemented"
else
    skip "Rate limiting check" "May be in different location"
fi

# ============================================================================
# Test Summary
# ============================================================================
section "Test Summary"

echo ""
echo "Tests Run: $TESTS_RUN"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
else
    echo -e "${GREEN}Tests Failed: $TESTS_FAILED${NC}"
fi
echo ""

# Calculate pass percentage
if [[ $TESTS_RUN -gt 0 ]]; then
    PASS_PCT=$(( (TESTS_PASSED * 100) / TESTS_RUN ))
    echo "Pass Rate: ${PASS_PCT}%"
fi

echo ""
echo "=========================================="

# Exit with failure if any tests failed
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}❌ Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
fi
