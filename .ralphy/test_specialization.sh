#!/usr/bin/env bash

# ============================================
# Test Script for Specialization Mode
# ============================================
# This script tests the specialization mode functionality
# without requiring actual AI engines to be installed

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_start() {
  echo -e "${BLUE}[TEST]${RESET} $1"
}

test_pass() {
  echo -e "${GREEN}[PASS]${RESET} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
  echo -e "${RED}[FAIL]${RESET} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Setup test environment
setup_test_env() {
  export RALPHY_DIR=".ralphy"
  export CONFIG_FILE="$RALPHY_DIR/config.yaml"
  export VERBOSE=true
  export AI_ENGINE="claude"

  # Source the modes.sh module
  if [[ -f "$RALPHY_DIR/modes.sh" ]]; then
    source "$RALPHY_DIR/modes.sh"
  else
    echo -e "${RED}ERROR: modes.sh not found!${RESET}"
    exit 1
  fi

  # Source utility functions from ralphy.sh if needed
  export RED="" GREEN="" YELLOW="" BLUE="" RESET="" BOLD="" DIM=""
}

# Test 1: Match UI/frontend patterns
test_ui_matching() {
  test_start "UI pattern matching"

  local result
  result=$(match_specialization_rule "Add a login button to the header" "$CONFIG_FILE")

  if [[ "$result" == "cursor" ]]; then
    test_pass "Correctly matched UI task to cursor engine"
  else
    test_fail "Expected 'cursor' but got '$result'"
  fi
}

# Test 2: Match refactoring patterns
test_refactor_matching() {
  test_start "Refactoring pattern matching"

  local result
  result=$(match_specialization_rule "Refactor the authentication system" "$CONFIG_FILE")

  if [[ "$result" == "claude" ]]; then
    test_pass "Correctly matched refactoring task to claude engine"
  else
    test_fail "Expected 'claude' but got '$result'"
  fi
}

# Test 3: Match test patterns
test_test_matching() {
  test_start "Test pattern matching"

  local result
  result=$(match_specialization_rule "Write unit tests for the API" "$CONFIG_FILE")

  if [[ "$result" == "cursor" ]]; then
    test_pass "Correctly matched test task to cursor engine"
  else
    test_fail "Expected 'cursor' but got '$result'"
  fi
}

# Test 4: Match bug fix patterns
test_bugfix_matching() {
  test_start "Bug fix pattern matching"

  local result
  result=$(match_specialization_rule "Fix the login bug in authentication" "$CONFIG_FILE")

  if [[ "$result" == "claude" ]]; then
    test_pass "Correctly matched bug fix to claude engine"
  else
    test_fail "Expected 'claude' but got '$result'"
  fi
}

# Test 5: No match returns empty
test_no_match() {
  test_start "No match scenario"

  local result
  result=$(match_specialization_rule "Something completely unrelated xyz123" "$CONFIG_FILE")

  if [[ -z "$result" ]]; then
    test_pass "Correctly returned empty for unmatched pattern"
  else
    test_fail "Expected empty but got '$result'"
  fi
}

# Test 6: get_engine_for_task with match
test_get_engine_with_match() {
  test_start "get_engine_for_task with match"

  local result
  result=$(get_engine_for_task "Add a component to the UI" "claude" "$CONFIG_FILE")

  # Note: This might return claude if cursor is not available, which is correct behavior
  if [[ "$result" == "cursor" ]] || [[ "$result" == "claude" ]]; then
    test_pass "Got engine: $result"
  else
    test_fail "Expected 'cursor' or 'claude' but got '$result'"
  fi
}

# Test 7: get_engine_for_task without match uses default
test_get_engine_no_match() {
  test_start "get_engine_for_task without match uses default"

  local result
  result=$(get_engine_for_task "Something random xyz789" "opencode" "$CONFIG_FILE")

  if [[ "$result" == "opencode" ]]; then
    test_pass "Correctly used default engine"
  else
    test_fail "Expected 'opencode' but got '$result'"
  fi
}

# Test 8: Case-insensitive matching
test_case_insensitive() {
  test_start "Case-insensitive pattern matching"

  local result
  result=$(match_specialization_rule "FIX THE BUG in the system" "$CONFIG_FILE")

  if [[ "$result" == "claude" ]]; then
    test_pass "Case-insensitive matching works"
  else
    test_fail "Expected 'claude' but got '$result'"
  fi
}

# Test 9: API pattern matching
test_api_matching() {
  test_start "API pattern matching"

  local result
  result=$(match_specialization_rule "Create a new REST API endpoint" "$CONFIG_FILE")

  if [[ "$result" == "claude" ]]; then
    test_pass "Correctly matched API task to claude engine"
  else
    test_fail "Expected 'claude' but got '$result'"
  fi
}

# Test 10: Database pattern matching
test_database_matching() {
  test_start "Database pattern matching"

  local result
  result=$(match_specialization_rule "Add a new database migration" "$CONFIG_FILE")

  if [[ "$result" == "claude" ]]; then
    test_pass "Correctly matched database task to claude engine"
  else
    test_fail "Expected 'claude' but got '$result'"
  fi
}

# Run all tests
main() {
  echo ""
  echo "============================================"
  echo "Testing Specialization Mode"
  echo "============================================"
  echo ""

  setup_test_env

  # Check if config file exists
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}ERROR: Config file not found at $CONFIG_FILE${RESET}"
    echo "Run './ralphy.sh --init' first to create config"
    exit 1
  fi

  # Run all tests
  test_ui_matching
  test_refactor_matching
  test_test_matching
  test_bugfix_matching
  test_no_match
  test_get_engine_with_match
  test_get_engine_no_match
  test_case_insensitive
  test_api_matching
  test_database_matching

  # Summary
  echo ""
  echo "============================================"
  echo "Test Results"
  echo "============================================"
  echo -e "${GREEN}Passed: $TESTS_PASSED${RESET}"
  echo -e "${RED}Failed: $TESTS_FAILED${RESET}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${RESET}"
    exit 0
  else
    echo -e "${RED}Some tests failed.${RESET}"
    exit 1
  fi
}

main "$@"
