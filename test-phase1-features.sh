#!/bin/bash
# Phase 1 Feature Tests - Simple and Fast

cd "$(dirname "${BASH_SOURCE[0]}")"
SCRIPT=./azure-storage-cost-analysis-enhanced.sh
EXAMPLE_CONFIG=./azure-storage-monitor.conf.example
PASSED=0
FAILED=0

echo "============================================"
echo "Phase 1 Feature Tests"
echo "============================================"
echo ""

# Test function
t() {
    echo -n "Test $((PASSED + FAILED + 1)): $1... "
    if eval "$2" &>/dev/null; then
        echo "✓ PASS"
        ((PASSED++))
    else
        echo "✗ FAIL"
        ((FAILED++))
    fi
}

# Run tests
t "Config parsing function" "grep -q '^parse_config_file()' $SCRIPT"
t "Config variables" "grep -q 'CONFIG_OUTPUT_FORMAT=' $SCRIPT"
t "Exit codes" "grep -q 'EXIT_SUCCESS=0' $SCRIPT"
t "Threshold function" "grep -q '^check_thresholds()' $SCRIPT"
t "log_info function" "grep -q '^log_info()' $SCRIPT"
t "log_verbose function" "grep -q '^log_verbose()' $SCRIPT"
t "log_progress function" "grep -q '^log_progress()' $SCRIPT"
t "JSON output" "grep -q '^output_json_summary()' $SCRIPT"
t "Zabbix output" "grep -q '^output_zabbix_metric()' $SCRIPT"
t "Date calculation" "grep -q '^calculate_date_range()' $SCRIPT"
t "Flag --config" "grep -q '\-\-config' $SCRIPT"
t "Flag --output-format" "grep -q '\-\-output-format' $SCRIPT"
t "Flag --silent" "grep -q '\-\-silent' $SCRIPT"
t "Flag --days" "grep -q '\-\-days' $SCRIPT"
t "Flag --last-month" "grep -q '\-\-last-month' $SCRIPT"
t "Usage function" "grep -q '^usage()' $SCRIPT"
t "Bash syntax" "bash -n $SCRIPT"
t "Example config" "test -f $EXAMPLE_CONFIG"
t "Config [azure] section" "grep -q '\[azure\]' $EXAMPLE_CONFIG"
t "Config [output] section" "grep -q '\[output\]' $EXAMPLE_CONFIG"
t "Config loading in main" "grep -q 'load_config' $SCRIPT"
t "Threshold checking used" "grep -q 'check_thresholds' $SCRIPT"
t "JSON output used" "grep -q 'output_json_summary' $SCRIPT"
t "Date calc used" "grep -q 'calculate_date_range' $SCRIPT"

# Summary
echo ""
echo "============================================"
TOTAL=$((PASSED + FAILED))
echo "Total: $TOTAL | Passed: $PASSED | Failed: $FAILED"
echo "============================================"
[[ $FAILED -eq 0 ]] && echo "✓ All tests passed!" || echo "✗ Some tests failed"
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
