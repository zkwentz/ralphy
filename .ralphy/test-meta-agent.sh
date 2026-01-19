#!/usr/bin/env bash

# ============================================
# Meta-Agent Decision Parsing Tests
# ============================================
# Test suite for parse_meta_decision function

# Make sure we're running in bash
if [ -z "$BASH_VERSION" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

# Source the meta-agent module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/meta-agent.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# TEST UTILITIES
# ============================================

print_test_header() {
  echo ""
  echo "======================================"
  echo "TEST: $1"
  echo "======================================"
}

assert_success() {
  local test_name="$1"
  local actual_exit_code="$2"
  ((TESTS_RUN++))

  if [[ "$actual_exit_code" -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} $test_name: PASSED"
    ((TESTS_PASSED++))
    return 0
  else
    echo -e "${RED}✗${NC} $test_name: FAILED (expected exit code 0, got $actual_exit_code)"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_failure() {
  local test_name="$1"
  local actual_exit_code="$2"
  ((TESTS_RUN++))

  if [[ "$actual_exit_code" -ne 0 ]]; then
    echo -e "${GREEN}✓${NC} $test_name: PASSED (correctly failed)"
    ((TESTS_PASSED++))
    return 0
  else
    echo -e "${RED}✗${NC} $test_name: FAILED (expected failure, got success)"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_contains() {
  local test_name="$1"
  local haystack="$2"
  local needle="$3"
  ((TESTS_RUN++))

  if echo "$haystack" | grep -q "$needle"; then
    echo -e "${GREEN}✓${NC} $test_name: PASSED"
    ((TESTS_PASSED++))
    return 0
  else
    echo -e "${RED}✗${NC} $test_name: FAILED"
    echo "  Expected to find: $needle"
    echo "  In: $haystack"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_json_field() {
  local test_name="$1"
  local json="$2"
  local field="$3"
  local expected_value="$4"
  ((TESTS_RUN++))

  local actual_value
  actual_value=$(echo "$json" | grep -o "\"$field\": *\"[^\"]*\"" | sed "s/\"$field\": *\"\([^\"]*\)\"/\1/")

  if [[ "$actual_value" == "$expected_value" ]]; then
    echo -e "${GREEN}✓${NC} $test_name: PASSED"
    ((TESTS_PASSED++))
    return 0
  else
    echo -e "${RED}✗${NC} $test_name: FAILED"
    echo "  Field: $field"
    echo "  Expected: $expected_value"
    echo "  Actual: $actual_value"
    ((TESTS_FAILED++))
    return 1
  fi
}

# ============================================
# TEST CASES
# ============================================

test_parse_select_decision() {
  print_test_header "Parse SELECT decision"

  local test_file="/tmp/test_meta_select_$$.txt"
  cat > "$test_file" << 'EOF'
After analyzing both solutions, here's my assessment:

DECISION: select
CHOSEN: 1
REASONING: Solution 1 provides better error handling and follows the project's established patterns more closely.

Both solutions accomplish the task, but solution 1 is more maintainable.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file") || exit_code=$?

  assert_success "Parse returns success" "$exit_code"
  assert_json_field "Decision field is 'select'" "$result" "decision" "select"
  assert_json_field "Chosen field is '1'" "$result" "chosen" "1"
  assert_contains "Reasoning is present" "$result" "better error handling"

  rm -f "$test_file"
}

test_parse_merge_decision() {
  print_test_header "Parse MERGE decision"

  local test_file="/tmp/test_meta_merge_$$.txt"
  cat > "$test_file" << 'EOF'
I recommend merging the best aspects of both solutions.

DECISION: merge
CHOSEN: merged
REASONING: Solution 1 has better structure, but solution 2 has superior error handling. Combining them provides the best result.

MERGED_SOLUTION:
```javascript
function processData(input) {
  if (!input) {
    throw new Error('Input required');
  }
  return input.map(item => item.value);
}
```

This merged solution takes the structure from solution 1 and error handling from solution 2.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file") || exit_code=$?

  assert_success "Parse returns success" "$exit_code"
  assert_json_field "Decision field is 'merge'" "$result" "decision" "merge"
  assert_json_field "Chosen field is 'merged'" "$result" "chosen" "merged"
  assert_contains "Merged solution is present" "$result" "function processData"
  assert_contains "Merged solution has code" "$result" "throw new Error"

  rm -f "$test_file"
}

test_parse_missing_decision() {
  print_test_header "Handle missing DECISION field"

  local test_file="/tmp/test_meta_missing_$$.txt"
  cat > "$test_file" << 'EOF'
CHOSEN: 1
REASONING: This is the best solution.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file" 2>&1) || exit_code=$?

  assert_failure "Parse fails correctly" "$exit_code"
  assert_contains "Error message mentions missing DECISION" "$result" "Missing DECISION"

  rm -f "$test_file"
}

test_parse_missing_chosen() {
  print_test_header "Handle missing CHOSEN field"

  local test_file="/tmp/test_meta_missing_chosen_$$.txt"
  cat > "$test_file" << 'EOF'
DECISION: select
REASONING: This is the best solution.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file" 2>&1) || exit_code=$?

  assert_failure "Parse fails correctly" "$exit_code"
  assert_contains "Error message mentions missing CHOSEN" "$result" "Missing CHOSEN"

  rm -f "$test_file"
}

test_parse_invalid_decision_value() {
  print_test_header "Handle invalid DECISION value"

  local test_file="/tmp/test_meta_invalid_$$.txt"
  cat > "$test_file" << 'EOF'
DECISION: reject
CHOSEN: none
REASONING: None of the solutions are acceptable.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file" 2>&1) || exit_code=$?

  assert_failure "Parse fails correctly" "$exit_code"
  assert_contains "Error message mentions invalid DECISION" "$result" "Invalid DECISION"

  rm -f "$test_file"
}

test_parse_merge_without_solution() {
  print_test_header "Handle MERGE without MERGED_SOLUTION"

  local test_file="/tmp/test_meta_merge_nosol_$$.txt"
  cat > "$test_file" << 'EOF'
DECISION: merge
CHOSEN: merged
REASONING: I will merge the solutions but provide no code.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file" 2>&1) || exit_code=$?

  assert_failure "Parse fails correctly" "$exit_code"
  assert_contains "Error message mentions missing MERGED_SOLUTION" "$result" "no MERGED_SOLUTION"

  rm -f "$test_file"
}

test_parse_case_insensitive() {
  print_test_header "Parse with different case variations"

  local test_file="/tmp/test_meta_case_$$.txt"
  cat > "$test_file" << 'EOF'
DECISION: SELECT
CHOSEN: 2
REASONING: Solution 2 is better.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file") || exit_code=$?

  assert_success "Parse returns success" "$exit_code"
  assert_json_field "Decision is normalized to lowercase" "$result" "decision" "select"

  rm -f "$test_file"
}

test_parse_with_extra_whitespace() {
  print_test_header "Parse with extra whitespace"

  local test_file="/tmp/test_meta_whitespace_$$.txt"
  cat > "$test_file" << 'EOF'
   DECISION:    select
   CHOSEN:   1
   REASONING:   This has extra spaces
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file") || exit_code=$?

  assert_success "Parse returns success" "$exit_code"
  assert_json_field "Decision is trimmed" "$result" "decision" "select"
  assert_json_field "Chosen is trimmed" "$result" "chosen" "1"

  rm -f "$test_file"
}

test_parse_multiline_reasoning() {
  print_test_header "Parse multiline reasoning"

  local test_file="/tmp/test_meta_multiline_$$.txt"
  cat > "$test_file" << 'EOF'
DECISION: select
CHOSEN: 1
REASONING: This is a long explanation that spans multiple lines and includes various details about why this solution is better than the alternatives.

Additional context here.
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file") || exit_code=$?

  assert_success "Parse returns success" "$exit_code"
  # Just verify reasoning field exists
  assert_contains "Reasoning contains content" "$result" "long explanation"

  rm -f "$test_file"
}

test_parse_code_block_with_language() {
  print_test_header "Parse code block with language specifier"

  local test_file="/tmp/test_meta_lang_$$.txt"
  cat > "$test_file" << 'EOF'
DECISION: merge
CHOSEN: merged
REASONING: Combining both solutions.

MERGED_SOLUTION:
```typescript
interface User {
  id: number;
  name: string;
}
```
EOF

  local result
  local exit_code=0
  result=$(parse_meta_decision "$test_file") || exit_code=$?

  assert_success "Parse returns success" "$exit_code"
  assert_contains "Merged solution includes interface" "$result" "interface User"

  rm -f "$test_file"
}

test_parse_file_not_found() {
  print_test_header "Handle non-existent file"

  local result
  local exit_code=0
  result=$(parse_meta_decision "/tmp/nonexistent_file_$$.txt" 2>&1) || exit_code=$?

  assert_failure "Parse fails correctly" "$exit_code"
  assert_contains "Error message mentions file not found" "$result" "not found"
}

test_prepare_meta_prompt() {
  print_test_header "Prepare meta-agent prompt"

  local task_desc="Fix authentication bug"
  local prompt

  # Create mock solution directories
  mkdir -p /tmp/test_solutions_$$/claude
  mkdir -p /tmp/test_solutions_$$/cursor

  prompt=$(prepare_meta_prompt "$task_desc" "/tmp/test_solutions_$$/claude" "/tmp/test_solutions_$$/cursor")

  assert_contains "Prompt includes task description" "$prompt" "Fix authentication bug"
  assert_contains "Prompt includes solution count" "$prompt" "2 different solutions"
  assert_contains "Prompt includes decision format" "$prompt" "DECISION:"
  assert_contains "Prompt includes instructions" "$prompt" "INSTRUCTIONS:"

  rm -rf /tmp/test_solutions_$$
}

# ============================================
# RUN ALL TESTS
# ============================================

echo ""
echo "======================================"
echo "Meta-Agent Decision Parsing Test Suite"
echo "======================================"
echo ""

test_parse_select_decision
test_parse_merge_decision
test_parse_missing_decision
test_parse_missing_chosen
test_parse_invalid_decision_value
test_parse_merge_without_solution
test_parse_case_insensitive
test_parse_with_extra_whitespace
test_parse_multiline_reasoning
test_parse_code_block_with_language
test_parse_file_not_found
test_prepare_meta_prompt

# Print summary
echo ""
echo "======================================"
echo "TEST SUMMARY"
echo "======================================"
echo "Total tests run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  echo ""
  exit 1
else
  echo "Failed: 0"
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
