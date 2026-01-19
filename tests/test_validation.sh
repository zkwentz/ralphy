#!/usr/bin/env bash

# ============================================
# Ralphy - Validation Module Tests
# Tests for .ralphy/validation.sh
# ============================================

set -euo pipefail

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load validation module
source "$PROJECT_ROOT/.ralphy/validation.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test utilities
assert_equals() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$expected" == "$actual" ]]; then
    echo "✓ PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo "✗ FAIL: $test_name"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

assert_success() {
  local command="$1"
  local test_name="$2"

  TESTS_RUN=$((TESTS_RUN + 1))

  if eval "$command" >/dev/null 2>&1; then
    echo "✓ PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo "✗ FAIL: $test_name (command failed: $command)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

assert_failure() {
  local command="$1"
  local test_name="$2"

  TESTS_RUN=$((TESTS_RUN + 1))

  if eval "$command" >/dev/null 2>&1; then
    echo "✗ FAIL: $test_name (command succeeded but should have failed: $command)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  else
    echo "✓ PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  fi
}

# ============================================
# TEST: Validation Result Messages
# ============================================

test_validation_result_messages() {
  echo ""
  echo "=== Testing Validation Result Messages ==="

  assert_equals "Validation passed" "$(get_validation_result_message 0)" "Success message"
  assert_equals "Tests failed" "$(get_validation_result_message 1)" "Tests failed message"
  assert_equals "Linting failed" "$(get_validation_result_message 2)" "Lint failed message"
  assert_equals "Build failed" "$(get_validation_result_message 3)" "Build failed message"
  assert_equals "Diff check failed (too large or forbidden files)" "$(get_validation_result_message 4)" "Diff failed message"
  assert_equals "Validation timed out" "$(get_validation_result_message 5)" "Timeout message"
}

# ============================================
# TEST: Test Gate
# ============================================

test_test_gate() {
  echo ""
  echo "=== Testing Test Gate ==="

  # Test: Empty command should skip
  assert_success "run_test_gate '' 60" "Empty test command skips"

  # Test: Successful command
  assert_success "run_test_gate 'echo test passed' 60" "Successful test command"

  # Test: Failed command
  assert_failure "run_test_gate 'exit 1' 60" "Failed test command"

  # Test: Timeout (only if timeout command available)
  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    assert_failure "run_test_gate 'sleep 10' 1" "Test timeout"
  else
    echo "⊘ SKIP: Test timeout (timeout command not available)"
  fi
}

# ============================================
# TEST: Lint Gate
# ============================================

test_lint_gate() {
  echo ""
  echo "=== Testing Lint Gate ==="

  # Test: Empty command should skip
  assert_success "run_lint_gate '' 60" "Empty lint command skips"

  # Test: Successful command
  assert_success "run_lint_gate 'echo lint passed' 60" "Successful lint command"

  # Test: Failed command
  assert_failure "run_lint_gate 'exit 1' 60" "Failed lint command"

  # Test: Timeout (only if timeout command available)
  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    assert_failure "run_lint_gate 'sleep 10' 1" "Lint timeout"
  else
    echo "⊘ SKIP: Lint timeout (timeout command not available)"
  fi
}

# ============================================
# TEST: Build Gate
# ============================================

test_build_gate() {
  echo ""
  echo "=== Testing Build Gate ==="

  # Test: Empty command should skip
  assert_success "run_build_gate '' 60" "Empty build command skips"

  # Test: Successful command
  assert_success "run_build_gate 'echo build passed' 60" "Successful build command"

  # Test: Failed command
  assert_failure "run_build_gate 'exit 1' 60" "Failed build command"

  # Test: Timeout (only if timeout command available)
  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    assert_failure "run_build_gate 'sleep 10' 1" "Build timeout"
  else
    echo "⊘ SKIP: Build timeout (timeout command not available)"
  fi
}

# ============================================
# TEST: Diff Gate with Mock Worktree
# ============================================

test_diff_gate() {
  echo ""
  echo "=== Testing Diff Gate ==="

  # Create a temporary git repo for testing
  local test_repo
  test_repo=$(mktemp -d)

  (
    cd "$test_repo"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "initial" > file.txt
    git add .
    git commit -q -m "Initial commit"
    git branch -M main

    # Create a small change
    echo "change" > file.txt

    # Test: Small diff should pass
    TESTS_RUN=$((TESTS_RUN + 1))
    if run_diff_gate "$test_repo" "main" 100 5000 >/dev/null 2>&1; then
      echo "✓ PASS: Small diff passes"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo "✗ FAIL: Small diff should pass"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Create too many files
    for i in {1..110}; do
      echo "file $i" > "file$i.txt"
    done

    # Test: Too many files should fail
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! run_diff_gate "$test_repo" "main" 100 5000 >/dev/null 2>&1; then
      echo "✓ PASS: Too many files fails"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo "✗ FAIL: Too many files should fail"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  )

  # Cleanup
  rm -rf "$test_repo"
}

# ============================================
# TEST: Validation Report Generation
# ============================================

test_validation_report() {
  echo ""
  echo "=== Testing Validation Report Generation ==="

  local report
  report=$(generate_validation_report "/tmp/test" 0 "claude" "task-123")

  # Check if report is valid JSON
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$report" | jq . >/dev/null 2>&1; then
    echo "✓ PASS: Report is valid JSON"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Report is not valid JSON"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  # Check if report contains expected fields
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$report" | jq -e '.task_id' >/dev/null 2>&1; then
    echo "✓ PASS: Report contains task_id"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Report missing task_id"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$report" | jq -e '.engine' >/dev/null 2>&1; then
    echo "✓ PASS: Report contains engine"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Report missing engine"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$report" | jq -e '.result_code' >/dev/null 2>&1; then
    echo "✓ PASS: Report contains result_code"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Report missing result_code"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================
# TEST: Full Validation with Mock Worktree
# ============================================

test_full_validation() {
  echo ""
  echo "=== Testing Full Validation ==="

  # Create a temporary git repo for testing
  local test_repo
  test_repo=$(mktemp -d)

  (
    cd "$test_repo"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "initial" > file.txt
    git add .
    git commit -q -m "Initial commit"
    git branch -M main

    # Create a small change
    echo "change" > file.txt
  )

  # Test: Validation with all gates passing
  TESTS_RUN=$((TESTS_RUN + 1))
  VALIDATION_CHECK_DIFF=true
  VALIDATION_RUN_LINT=true
  VALIDATION_RUN_TESTS=true
  VALIDATION_RUN_BUILD=false

  if validate_solution "$test_repo" "echo test ok" "echo lint ok" "" "main" >/dev/null 2>&1; then
    echo "✓ PASS: Full validation with passing gates"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Full validation should pass"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  # Test: Validation with failing test
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! validate_solution "$test_repo" "exit 1" "echo lint ok" "" "main" >/dev/null 2>&1; then
    echo "✓ PASS: Validation fails on failing test"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Validation should fail on failing test"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  # Test: Validation with failing lint
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! validate_solution "$test_repo" "echo test ok" "exit 1" "" "main" >/dev/null 2>&1; then
    echo "✓ PASS: Validation fails on failing lint"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Validation should fail on failing lint"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  # Cleanup
  rm -rf "$test_repo"
}

# ============================================
# RUN ALL TESTS
# ============================================

run_all_tests() {
  echo "========================================"
  echo "Running Validation Module Tests"
  echo "========================================"

  test_validation_result_messages
  test_test_gate
  test_lint_gate
  test_build_gate
  test_diff_gate
  test_validation_report
  test_full_validation

  echo ""
  echo "========================================"
  echo "Test Results"
  echo "========================================"
  echo "Total:  $TESTS_RUN"
  echo "Passed: $TESTS_PASSED"
  echo "Failed: $TESTS_FAILED"
  echo "========================================"

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    return 0
  else
    echo "✗ Some tests failed"
    return 1
  fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all_tests
fi
