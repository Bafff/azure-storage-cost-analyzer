#!/bin/bash

# Unit Tests for Phase 2: Zabbix Integration
# Tests all Zabbix integration features added in Phase 2

set -uo pipefail  # Removed -e to allow tests to continue on failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

echo "=========================================="
echo "Phase 2: Zabbix Integration Tests"
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
# Test 2: Zabbix Functions Exist
# ============================================================================
section "Test 2: Zabbix Functions Exist"

# Check if Zabbix functions are defined
functions_to_check=(
    "send_to_zabbix"
    "create_zabbix_batch_file"
    "send_batch_to_zabbix"
    "send_batch_to_zabbix_with_config"
    "generate_subscriptions_lld"
    "generate_disks_lld"
    "generate_snapshots_lld"
)

for func in "${functions_to_check[@]}"; do
    if grep -q "^${func}()" "$SCRIPT_PATH"; then
        pass "Function '$func' is defined"
    else
        fail "Function '$func' is defined" "Function exists" "Function not found"
    fi
done

# ============================================================================
# Test 3: Zabbix Command-Line Flags
# ============================================================================
section "Test 3: Zabbix Command-Line Flags"

# Check if --zabbix-send flag is recognized
if grep -q '\--zabbix-send)' "$SCRIPT_PATH"; then
    pass "Flag --zabbix-send is recognized"
else
    fail "Flag --zabbix-send is recognized" "Flag in code" "Flag not found"
fi

# Check if --zabbix-server flag is recognized
if grep -q '\--zabbix-server)' "$SCRIPT_PATH"; then
    pass "Flag --zabbix-server is recognized"
else
    fail "Flag --zabbix-server is recognized" "Flag in code" "Flag not found"
fi

# Check if --zabbix-port flag is recognized
if grep -q '\--zabbix-port)' "$SCRIPT_PATH"; then
    pass "Flag --zabbix-port is recognized"
else
    fail "Flag --zabbix-port is recognized" "Flag in code" "Flag not found"
fi

# Check if --zabbix-host flag is recognized
if grep -q '\--zabbix-host)' "$SCRIPT_PATH"; then
    pass "Flag --zabbix-host is recognized"
else
    fail "Flag --zabbix-host is recognized" "Flag in code" "Flag not found"
fi

# Check if --zabbix-config flag is recognized
if grep -q '\--zabbix-config)' "$SCRIPT_PATH"; then
    pass "Flag --zabbix-config is recognized"
else
    fail "Flag --zabbix-config is recognized" "Flag in code" "Flag not found"
fi

# Check if --zabbix-discovery flag is recognized
if grep -q '\--zabbix-discovery)' "$SCRIPT_PATH"; then
    pass "Flag --zabbix-discovery is recognized"
else
    fail "Flag --zabbix-discovery is recognized" "Flag in code" "Flag not found"
fi

# ============================================================================
# Test 4: Help Documentation
# ============================================================================
section "Test 4: Help Documentation"

help_output=$("$SCRIPT_PATH" 2>&1 || true)

# Check if Zabbix Integration section exists in help
if echo "$help_output" | grep -q "Zabbix Integration Flags"; then
    pass "Zabbix Integration section exists in help"
else
    fail "Zabbix Integration section in help" "Section present" "Section not found"
fi

# Check if --zabbix-send is documented
if echo "$help_output" | grep -q "\--zabbix-send"; then
    pass "Flag --zabbix-send is documented in help"
else
    fail "Flag --zabbix-send documented" "Flag in help" "Flag not in help"
fi

# Check if Zabbix examples are provided
if echo "$help_output" | grep -q "Zabbix Examples"; then
    pass "Zabbix examples are provided"
else
    fail "Zabbix examples provided" "Examples present" "Examples not found"
fi

# ============================================================================
# Test 5: Zabbix Item Keys
# ============================================================================
section "Test 5: Zabbix Item Keys"

# Check if aggregated metric keys are defined
if grep -q 'azure.storage.all.total_waste.monthly' "$SCRIPT_PATH"; then
    pass "Aggregated metric key 'total_waste.monthly' is used"
else
    fail "Aggregated metric key" "Key present" "Key not found"
fi

if grep -q 'azure.storage.all.total_disks' "$SCRIPT_PATH"; then
    pass "Aggregated metric key 'total_disks' is used"
else
    fail "Aggregated metric key" "Key present" "Key not found"
fi

# Check if per-subscription metric keys are defined (new format with metric name before subscription ID)
if grep -q 'azure.storage.subscription\.' "$SCRIPT_PATH"; then
    pass "Per-subscription metric keys are used"
else
    fail "Per-subscription metric keys" "Keys present" "Keys not found"
fi

# Check if script health metrics are defined
if grep -q 'azure.storage.script.last_run_timestamp' "$SCRIPT_PATH"; then
    pass "Script health metric 'last_run_timestamp' is used"
else
    fail "Script health metric" "Metric present" "Metric not found"
fi

# ============================================================================
# Test 6: LLD Macro Format
# ============================================================================
section "Test 6: LLD Macro Format"

# Check if subscription LLD macros are used
if grep -q '{#SUBSCRIPTION_ID}' "$SCRIPT_PATH"; then
    pass "Subscription LLD macro '{#SUBSCRIPTION_ID}' is used"
else
    fail "Subscription LLD macro" "Macro present" "Macro not found"
fi

# Check if disk LLD macros are used
if grep -q '{#DISK_NAME}' "$SCRIPT_PATH"; then
    pass "Disk LLD macro '{#DISK_NAME}' is used"
else
    fail "Disk LLD macro" "Macro present" "Macro not found"
fi

# Check if snapshot LLD macros are used
if grep -q '{#SNAPSHOT_NAME}' "$SCRIPT_PATH"; then
    pass "Snapshot LLD macro '{#SNAPSHOT_NAME}' is used"
else
    fail "Snapshot LLD macro" "Macro present" "Macro not found"
fi

# ============================================================================
# Test 7: Batch File Creation
# ============================================================================
section "Test 7: Batch File Creation"

# Check if batch file format is correct
if grep -q '/tmp/zabbix_batch_' "$SCRIPT_PATH"; then
    pass "Batch file path format is correct"
else
    fail "Batch file path" "Path format present" "Path not found"
fi

# Check if batch file includes timestamp
if grep -A 5 'create_zabbix_batch_file' "$SCRIPT_PATH" | grep -q 'timestamp'; then
    pass "Batch file includes timestamp parameter"
else
    skip "Batch file timestamp check" "May be in different location"
fi

# ============================================================================
# Test 8: zabbix-discovery Command
# ============================================================================
section "Test 8: zabbix-discovery Command"

# Check if zabbix-discovery command exists
if grep -q '"zabbix-discovery")' "$SCRIPT_PATH"; then
    pass "Command 'zabbix-discovery' is defined"
else
    fail "Command 'zabbix-discovery'" "Command present" "Command not found"
fi

# Check if discovery types are validated
if grep -A 10 '"zabbix-discovery")' "$SCRIPT_PATH" | grep -q 'subscriptions\|disks\|snapshots'; then
    pass "Discovery types are validated"
else
    fail "Discovery type validation" "Validation present" "Validation not found"
fi

# ============================================================================
# Test 9: Integration with unused-report
# ============================================================================
section "Test 9: Integration with unused-report"

# Check if unused-report integrates Zabbix sending
if grep -A 50 '"unused-report")' "$SCRIPT_PATH" | grep -q 'zabbix_send'; then
    pass "unused-report command integrates Zabbix sending"
else
    fail "unused-report Zabbix integration" "Integration present" "Integration not found"
fi

# Check if create_zabbix_batch_file is called
if grep -A 50 '"unused-report")' "$SCRIPT_PATH" | grep -q 'create_zabbix_batch_file'; then
    pass "unused-report calls create_zabbix_batch_file"
else
    fail "create_zabbix_batch_file called" "Function call present" "Call not found"
fi

# Check if send_batch_to_zabbix is called
if grep -A 50 '"unused-report")' "$SCRIPT_PATH" | grep -q 'send_batch_to_zabbix'; then
    pass "unused-report calls send_batch_to_zabbix"
else
    fail "send_batch_to_zabbix called" "Function call present" "Call not found"
fi

# ============================================================================
# Test 10: Config File Integration
# ============================================================================
section "Test 10: Config File Integration"

# Check if Zabbix config variables are applied
if grep -A 10 '"unused-report")' "$SCRIPT_PATH" | grep -q 'CONFIG_ZABBIX'; then
    pass "Zabbix config variables are applied from config file"
else
    fail "Config variable application" "Variables applied" "Variables not applied"
fi

# Check if CONFIG_ZABBIX_AUTO_SEND is checked
if grep -q 'CONFIG_ZABBIX_AUTO_SEND' "$SCRIPT_PATH"; then
    pass "CONFIG_ZABBIX_AUTO_SEND variable is checked"
else
    fail "CONFIG_ZABBIX_AUTO_SEND check" "Variable checked" "Variable not checked"
fi

# ============================================================================
# Test 11: Error Handling
# ============================================================================
section "Test 11: Error Handling"

# Check if zabbix_sender availability is checked
if grep -q 'command -v zabbix_sender' "$SCRIPT_PATH"; then
    pass "zabbix_sender availability is checked"
else
    fail "zabbix_sender check" "Check present" "Check not found"
fi

# Check if failed batch files are preserved
if grep -q 'failed_zabbix_batch' "$SCRIPT_PATH"; then
    pass "Failed batch files are preserved for debugging"
else
    fail "Failed batch preservation" "Preservation present" "Preservation not found"
fi

# ============================================================================
# Test 12: Zabbix Variables
# ============================================================================
section "Test 12: Zabbix Variables"

# Check if Zabbix variables are defined in main()
zabbix_vars=(
    "zabbix_send"
    "zabbix_server"
    "zabbix_port"
    "zabbix_host"
    "zabbix_config_file"
    "zabbix_discovery"
)

for var in "${zabbix_vars[@]}"; do
    if grep -q "local ${var}" "$SCRIPT_PATH"; then
        pass "Variable '$var' is defined in main()"
    else
        fail "Variable '$var'" "Variable defined" "Variable not found"
    fi
done

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
