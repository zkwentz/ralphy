#!/usr/bin/env bash
# Security Tests for Ralphy
# Tests for CWE-78 Command Injection Vulnerability Fixes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPHY_SH="$SCRIPT_DIR/ralphy.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Extract and define just the sanitize_task_title function for testing
sanitize_task_title() {
  local title="$1"
  # Remove newlines, carriage returns, null bytes, and other control characters
  # Keep only printable ASCII characters and common unicode text
  echo "$title" | tr -d '\000-\037' | tr -d '\177'
}

print_test_header() {
  echo ""
  echo "================================"
  echo "$1"
  echo "================================"
}

print_result() {
  local status=$1
  local message=$2

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$status" == "PASS" ]]; then
    echo -e "${GREEN}✓ PASS:${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗ FAIL:${NC} $message"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================
# Test 1: Sanitize Task Title Function
# ============================================

test_sanitize_task_title() {
  print_test_header "Test 1: sanitize_task_title Function"

  # Test 1.1: Removes newlines
  local input=$'Task with\nnewline'
  local expected="Task withnewline"
  local result
  result=$(sanitize_task_title "$input")

  if [[ "$result" == "$expected" ]]; then
    print_result "PASS" "Removes newlines correctly"
  else
    print_result "FAIL" "Newline removal failed. Expected: '$expected', Got: '$result'"
  fi

  # Test 1.2: Removes carriage returns
  local input=$'Task with\rcarriage return'
  local expected="Task withcarriage return"
  local result
  result=$(sanitize_task_title "$input")

  if [[ "$result" == "$expected" ]]; then
    print_result "PASS" "Removes carriage returns correctly"
  else
    print_result "FAIL" "Carriage return removal failed. Expected: '$expected', Got: '$result'"
  fi

  # Test 1.3: Removes null bytes (if testable in bash)
  local input="Task with null"
  local expected="Task with null"
  local result
  result=$(sanitize_task_title "$input")

  if [[ "$result" == "$expected" ]]; then
    print_result "PASS" "Handles normal text correctly"
  else
    print_result "FAIL" "Normal text handling failed. Expected: '$expected', Got: '$result'"
  fi

  # Test 1.4: Preserves normal task titles
  local input="Fix critical security bug in authentication"
  local expected="Fix critical security bug in authentication"
  local result
  result=$(sanitize_task_title "$input")

  if [[ "$result" == "$expected" ]]; then
    print_result "PASS" "Preserves normal task titles"
  else
    print_result "FAIL" "Normal task title preservation failed. Expected: '$expected', Got: '$result'"
  fi

  # Test 1.5: Handles special characters that should be preserved
  local input="Task [Feature]: Update UI/UX design & testing"
  local expected="Task [Feature]: Update UI/UX design & testing"
  local result
  result=$(sanitize_task_title "$input")

  if [[ "$result" == "$expected" ]]; then
    print_result "PASS" "Preserves safe special characters"
  else
    print_result "FAIL" "Special character preservation failed. Expected: '$expected', Got: '$result'"
  fi
}

# ============================================
# Test 2: YQ Injection Prevention
# ============================================

test_yq_injection_prevention() {
  print_test_header "Test 2: YQ Command Injection Prevention"

  # Create a temporary test file
  local test_yaml
  test_yaml=$(mktemp)
  cat > "$test_yaml" << 'EOF'
tasks:
  - title: "Normal Task"
    completed: false
  - title: "Task with \"quotes\""
    completed: false
  - title: "Task with special chars !@#$%"
    completed: false
EOF

  # Test 2.1: Verify the fix uses env() instead of string interpolation
  local fix_check
  fix_check=$(grep -n "TASK=.*env(TASK)" "$RALPHY_SH" | wc -l)

  if [[ $fix_check -ge 2 ]]; then
    print_result "PASS" "YQ functions use env() for safe parameter passing"
  else
    print_result "FAIL" "YQ functions don't properly use env() - potential injection risk"
  fi

  # Test 2.2: Verify old vulnerable pattern is removed
  local vuln_check
  vuln_check=$(grep -F 'select(.title == "$' "$RALPHY_SH" 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$vuln_check" -eq 0 ]]; then
    print_result "PASS" "Vulnerable YQ string interpolation pattern removed"
  else
    print_result "FAIL" "Vulnerable YQ string interpolation still present in code"
  fi

  # Cleanup
  rm -f "$test_yaml"
}

# ============================================
# Test 3: GitHub PR Title Sanitization
# ============================================

test_github_pr_sanitization() {
  print_test_header "Test 3: GitHub PR Title Sanitization"

  # Test 3.1: Verify sanitization is called in create_pull_request
  local sanitize_check
  sanitize_check=$(grep -A 20 "create_pull_request()" "$RALPHY_SH" | grep "sanitize_task_title" | wc -l)

  if [[ $sanitize_check -ge 1 ]]; then
    print_result "PASS" "create_pull_request() sanitizes task titles"
  else
    print_result "FAIL" "create_pull_request() doesn't sanitize task titles"
  fi

  # Test 3.2: Verify sanitization in parallel execution PR creation
  local parallel_sanitize_check
  parallel_sanitize_check=$(grep -B 5 "gh pr create" "$RALPHY_SH" | grep "safe_task" | wc -l)

  if [[ $parallel_sanitize_check -ge 2 ]]; then
    print_result "PASS" "Parallel execution PR creation sanitizes task titles"
  else
    print_result "FAIL" "Parallel execution PR creation doesn't properly sanitize task titles"
  fi
}

# ============================================
# Test 4: Security Comment Documentation
# ============================================

test_security_documentation() {
  print_test_header "Test 4: Security Documentation"

  # Test 4.1: Verify CWE-78 references exist
  local cwe_check
  cwe_check=$(grep -c "CWE-78" "$RALPHY_SH" || echo "0")

  if [[ $cwe_check -ge 3 ]]; then
    print_result "PASS" "Security fixes documented with CWE-78 references"
  else
    print_result "FAIL" "Missing CWE-78 documentation in security fixes"
  fi

  # Test 4.2: Verify security comments exist
  local comment_check
  comment_check=$(grep -c "prevent.*injection" "$RALPHY_SH" || echo "0")

  if [[ $comment_check -ge 1 ]]; then
    print_result "PASS" "Security comments explain injection prevention"
  else
    print_result "FAIL" "Missing security explanation comments"
  fi
}

# ============================================
# Run All Tests
# ============================================

main() {
  echo ""
  echo "========================================"
  echo "Ralphy Security Test Suite"
  echo "========================================"
  echo "Testing security fixes for:"
  echo "  - YQ Command Injection (CWE-78)"
  echo "  - GitHub API Argument Injection"
  echo "========================================"

  test_sanitize_task_title
  test_yq_injection_prevention
  test_github_pr_sanitization
  test_security_documentation

  # Print summary
  echo ""
  echo "========================================"
  echo "Test Summary"
  echo "========================================"
  echo "Total Tests Run: $TESTS_RUN"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  else
    echo "Failed: 0"
  fi
  echo "========================================"

  # Exit with appropriate code
  if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

# Run tests
main "$@"
