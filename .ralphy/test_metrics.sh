#!/usr/bin/env bash

# ============================================
# Ralphy Metrics Module - Test Suite
# ============================================

set -euo pipefail

RALPHY_DIR=".ralphy"
METRICS_FILE="$RALPHY_DIR/metrics.json"
TEST_METRICS_FILE="$RALPHY_DIR/metrics.test.json"

# Colors for test output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Source the metrics module
if [[ -f "$RALPHY_DIR/metrics.sh" ]]; then
  source "$RALPHY_DIR/metrics.sh"
else
  echo "Error: metrics.sh not found"
  exit 1
fi

# Backup existing metrics if they exist
if [[ -f "$METRICS_FILE" ]]; then
  cp "$METRICS_FILE" "$METRICS_FILE.backup"
fi

# Override metrics file for testing
METRICS_FILE="$TEST_METRICS_FILE"

# Test counter
tests_run=0
tests_passed=0
tests_failed=0

# Test helper functions
test_start() {
  echo -n "Testing: $1... "
  ((tests_run++)) || true
}

test_pass() {
  echo -e "${GREEN}PASS${RESET}"
  ((tests_passed++)) || true
}

test_fail() {
  echo -e "${RED}FAIL${RESET}"
  if [[ -n "${1:-}" ]]; then
    echo "  Reason: $1"
  fi
  ((tests_failed++)) || true
}

# Clean up test metrics file
cleanup_test() {
  rm -f "$TEST_METRICS_FILE"

  # Restore backup if exists
  if [[ -f "$METRICS_FILE.backup" ]]; then
    mv "$METRICS_FILE.backup" "$(dirname "$METRICS_FILE")/metrics.json"
  fi
}

trap cleanup_test EXIT

echo "============================================"
echo "Ralphy Metrics Module - Test Suite"
echo "============================================"
echo ""

# Test 1: Initialize metrics file
test_start "init_metrics_file"
init_metrics_file
if [[ -f "$TEST_METRICS_FILE" ]]; then
  test_pass
else
  test_fail "Metrics file not created"
fi

# Test 2: Validate JSON structure
test_start "JSON structure validation"
if command -v jq &>/dev/null; then
  if jq empty "$TEST_METRICS_FILE" 2>/dev/null; then
    # Check for required fields
    if jq -e '.engines.claude' "$TEST_METRICS_FILE" >/dev/null && \
       jq -e '.execution_history' "$TEST_METRICS_FILE" >/dev/null; then
      test_pass
    else
      test_fail "Missing required fields"
    fi
  else
    test_fail "Invalid JSON"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 3: Extract task pattern
test_start "extract_task_pattern - UI task"
pattern=$(extract_task_pattern "Update the login button styling")
if [[ "$pattern" == "ui_frontend" ]]; then
  test_pass
else
  test_fail "Expected 'ui_frontend', got '$pattern'"
fi

# Test 4: Extract task pattern - Bug fix
test_start "extract_task_pattern - Bug fix"
pattern=$(extract_task_pattern "Fix the calculation error in checkout")
if [[ "$pattern" == "bug_fix" ]]; then
  test_pass
else
  test_fail "Expected 'bug_fix', got '$pattern'"
fi

# Test 5: Extract task pattern - Testing
test_start "extract_task_pattern - Testing"
pattern=$(extract_task_pattern "Add unit tests for login")
if [[ "$pattern" == "testing" ]]; then
  test_pass
else
  test_fail "Expected 'testing', got '$pattern'"
fi

# Test 6: Record execution
test_start "record_execution - Success"
record_execution "claude" "Test task" true 5000 1000 500 "0.0225"
if command -v jq &>/dev/null; then
  count=$(jq '.execution_history | length' "$TEST_METRICS_FILE")
  if [[ "$count" -eq 1 ]]; then
    test_pass
  else
    test_fail "Expected 1 execution, got $count"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 7: Engine metrics update
test_start "Engine metrics - Execution count"
if command -v jq &>/dev/null; then
  exec_count=$(jq '.engines.claude.total_executions' "$TEST_METRICS_FILE")
  if [[ "$exec_count" -eq 1 ]]; then
    test_pass
  else
    test_fail "Expected 1 execution, got $exec_count"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 8: Success rate calculation
test_start "Engine metrics - Success rate"
if command -v jq &>/dev/null; then
  success_rate=$(jq '.engines.claude.success_rate' "$TEST_METRICS_FILE")
  if [[ "$success_rate" == "1" ]]; then
    test_pass
  else
    test_fail "Expected success_rate=1, got $success_rate"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 9: Record failure
test_start "record_execution - Failure"
record_execution "claude" "Failed task" false 3000 500 200 "0.01"
if command -v jq &>/dev/null; then
  failed_count=$(jq '.engines.claude.failed' "$TEST_METRICS_FILE")
  if [[ "$failed_count" -eq 1 ]]; then
    test_pass
  else
    test_fail "Expected 1 failure, got $failed_count"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 10: Success rate after mixed results
test_start "Engine metrics - Success rate after failure"
if command -v jq &>/dev/null; then
  success_rate=$(jq '.engines.claude.success_rate' "$TEST_METRICS_FILE")
  # 1 success, 1 failure = 0.5
  if [[ "$success_rate" == "0.5" ]]; then
    test_pass
  else
    test_fail "Expected success_rate=0.5, got $success_rate"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 11: Pattern-specific metrics
test_start "Pattern-specific metrics"
record_execution "claude" "Fix UI bug" true 4000 800 400 "0.018"
if command -v jq &>/dev/null; then
  ui_executions=$(jq '.engines.claude.task_patterns.ui_frontend.executions' "$TEST_METRICS_FILE")
  if [[ "$ui_executions" -ge 1 ]]; then
    test_pass
  else
    test_fail "Expected UI pattern executions >= 1, got $ui_executions"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 12: Get best engine (not enough samples)
test_start "get_best_engine_for_pattern - Insufficient samples"
best=$(get_best_engine_for_pattern "Add a new feature" 10)
if [[ -z "$best" ]]; then
  test_pass
else
  test_fail "Expected empty result with insufficient samples"
fi

# Test 13: Multiple engines for comparison
test_start "Multiple engines - Cursor"
record_execution "cursor" "Fix UI styling" true 3000 900 450 "0.02"
record_execution "cursor" "Update button color" true 2500 850 420 "0.019"
record_execution "cursor" "Fix layout issue" true 3200 920 460 "0.021"
if command -v jq &>/dev/null; then
  cursor_executions=$(jq '.engines.cursor.total_executions' "$TEST_METRICS_FILE")
  if [[ "$cursor_executions" -eq 3 ]]; then
    test_pass
  else
    test_fail "Expected 3 Cursor executions, got $cursor_executions"
  fi
else
  test_pass # Skip if jq not available
fi

# Test 14: Reset metrics
test_start "reset_metrics"
reset_metrics >/dev/null 2>&1
if command -v jq &>/dev/null; then
  history_count=$(jq '.execution_history | length' "$TEST_METRICS_FILE")
  if [[ "$history_count" -eq 0 ]]; then
    test_pass
  else
    test_fail "Expected empty history after reset, got $history_count items"
  fi
else
  test_pass # Skip if jq not available
fi

# Summary
echo ""
echo "============================================"
echo "Test Results"
echo "============================================"
echo "Total tests:  $tests_run"
echo -e "Passed:       ${GREEN}$tests_passed${RESET}"
if [[ $tests_failed -gt 0 ]]; then
  echo -e "Failed:       ${RED}$tests_failed${RESET}"
else
  echo "Failed:       $tests_failed"
fi
echo ""

if [[ $tests_failed -eq 0 ]]; then
  echo -e "${GREEN}All tests passed!${RESET}"
  exit 0
else
  echo -e "${RED}Some tests failed.${RESET}"
  exit 1
fi
