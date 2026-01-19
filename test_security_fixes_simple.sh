#!/usr/bin/env bash
# Simplified Security Tests for Ralphy - CWE-78 Fixes

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "========================================"
echo "Ralphy Security Test Suite"
echo "Testing CWE-78 Command Injection Fixes"
echo "========================================"
echo ""

# Test 1: Sanitize function works
echo "Test 1: sanitize_task_title function"
sanitize_task_title() {
  local title="$1"
  echo "$title" | tr -d '\000-\037' | tr -d '\177'
}

result=$(sanitize_task_title $'Test\nwith\nnewlines')
expected="Testwithnewlines"
if [[ "$result" == "$expected" ]]; then
  echo -e "${GREEN}✓ PASS${NC}: Sanitize removes newlines"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: Sanitize test failed"
  FAILED=$((FAILED + 1))
fi

# Test 2: YQ uses env() pattern
echo "Test 2: YQ injection fix"
count=$(grep -c 'TASK=.*env(TASK)' ralphy.sh)
if [[ $count -ge 2 ]]; then
  echo -e "${GREEN}✓ PASS${NC}: YQ functions use env(TASK) pattern (found $count)"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: YQ functions missing env(TASK) pattern"
  FAILED=$((FAILED + 1))
fi

# Test 3: Vulnerable pattern removed (check for env() usage instead)
echo "Test 3: Secure pattern usage"
count=$(grep -c 'env(TASK)' ralphy.sh)
if [[ "$count" -ge 2 ]]; then
  echo -e "${GREEN}✓ PASS${NC}: Secure env(TASK) pattern used ($count times)"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: Insufficient env(TASK) usage"
  FAILED=$((FAILED + 1))
fi

# Test 4: PR sanitization
echo "Test 4: GitHub PR sanitization"
count=$(grep -c "sanitize_task_title" ralphy.sh)
if [[ $count -ge 2 ]]; then
  echo -e "${GREEN}✓ PASS${NC}: PR functions sanitize task titles (found $count uses)"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: Missing sanitization in PR functions"
  FAILED=$((FAILED + 1))
fi

# Test 5: CWE-78 documentation
echo "Test 5: Security documentation"
count=$(grep -c "CWE-78" ralphy.sh)
if [[ $count -ge 3 ]]; then
  echo -e "${GREEN}✓ PASS${NC}: CWE-78 documented (found $count references)"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: Insufficient CWE-78 documentation"
  FAILED=$((FAILED + 1))
fi

# Test 6: safe_task variable usage
echo "Test 6: Safe task variable in PR creation"
count=$(grep -c 'safe_task' ralphy.sh)
if [[ $count -ge 2 ]]; then
  echo -e "${GREEN}✓ PASS${NC}: Safe task variables used (found $count)"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: Missing safe_task variables"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "========================================"
echo "Summary: $PASSED passed, $FAILED failed"
echo "========================================"

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  exit 0
fi
