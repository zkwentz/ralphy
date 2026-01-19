#!/bin/bash

# Test suite for Specialization Mode
# Tests the specialization routing logic and fallback behavior

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Helper functions
print_test_header() {
  echo -e "\n${BLUE}================================================${NC}"
  echo -e "${BLUE}TEST: $1${NC}"
  echo -e "${BLUE}================================================${NC}"
}

assert_success() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

assert_equals() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: $3"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗ FAIL${NC}: $3"
    echo -e "  Expected: $2"
    echo -e "  Got: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

assert_contains() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if echo "$1" | grep -q "$2"; then
    echo -e "${GREEN}✓ PASS${NC}: $3"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗ FAIL${NC}: $3"
    echo -e "  Expected to contain: $2"
    echo -e "  In: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

assert_file_exists() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ -f "$1" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: $2"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗ FAIL${NC}: $2"
    echo -e "  File not found: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# Test setup
echo -e "${YELLOW}Setting up test environment...${NC}"

# Create test config directory
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.ralphy"

# Save original directory
ORIGINAL_TEST_DIR=$(pwd)

# Copy modes.sh to test directory
if [[ -f ".ralphy/modes.sh" ]]; then
  cp .ralphy/modes.sh "$TEST_DIR/.ralphy/"
else
  echo -e "${RED}ERROR: .ralphy/modes.sh not found${NC}"
  exit 1
fi

cd "$TEST_DIR"

# Create mock logging functions
log_info() { echo "[INFO] $*"; }
log_success() { echo "[SUCCESS] $*"; }
log_error() { echo "[ERROR] $*"; }
log_warning() { echo "[WARNING] $*"; }

# Export functions
export -f log_info log_success log_error log_warning

# Source the modes.sh file
source .ralphy/modes.sh

echo -e "${GREEN}Test environment ready${NC}"

# ============================================
# TEST 1: Module exists and is valid bash
# ============================================
print_test_header "1. Module existence and syntax validation"

assert_file_exists ".ralphy/modes.sh" "modes.sh exists"

bash -n .ralphy/modes.sh
assert_success "modes.sh has valid bash syntax"

# ============================================
# TEST 2: Specialization functions exist
# ============================================
print_test_header "2. Specialization functions exist"

if declare -f run_specialization_mode > /dev/null; then
  echo -e "${GREEN}✓ PASS${NC}: run_specialization_mode function exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: run_specialization_mode function exists"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if declare -f match_specialization_rule > /dev/null; then
  echo -e "${GREEN}✓ PASS${NC}: match_specialization_rule function exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: match_specialization_rule function exists"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if declare -f get_default_engine > /dev/null; then
  echo -e "${GREEN}✓ PASS${NC}: get_default_engine function exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: get_default_engine function exists"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# ============================================
# TEST 3: Config with specialization rules
# ============================================
print_test_header "3. Config parsing with specialization rules"

# Create test config with rules
cat > .ralphy/config.yaml <<'EOF'
project:
  name: "test-app"
  language: "TypeScript"

engines:
  meta_agent:
    engine: "claude"

  specialization_rules:
    - pattern: "UI|frontend|styling|component|design"
      engines: ["cursor"]
      description: "UI and frontend work"

    - pattern: "refactor|architecture|design pattern|optimize"
      engines: ["claude"]
      description: "Complex reasoning and architecture"

    - pattern: "test|spec|unit test|integration test"
      engines: ["codex"]
      description: "Testing tasks"

    - pattern: "bug fix|fix bug|debug"
      engines: ["opencode"]
      description: "Bug fixes"
EOF

# Check if yq is available
if ! command -v yq &> /dev/null; then
  echo -e "${YELLOW}⚠ SKIP${NC}: yq not installed - config parsing tests skipped"
else
  # Test pattern matching
  result=$(match_specialization_rule "Add UI component for login")
  assert_contains "$result" "cursor" "UI task matches cursor engine"

  result=$(match_specialization_rule "Refactor authentication system")
  assert_contains "$result" "claude" "Refactor task matches claude engine"

  result=$(match_specialization_rule "Add unit tests for auth")
  assert_contains "$result" "codex" "Test task matches codex engine"

  result=$(match_specialization_rule "Fix bug in login flow")
  assert_contains "$result" "opencode" "Bug fix matches opencode engine"
fi

# ============================================
# TEST 4: No matching rules - fallback to default
# ============================================
print_test_header "4. No matching rules - fallback behavior"

# Test with task that doesn't match any pattern
result=$(match_specialization_rule "Implement new feature for data processing")
if [[ -z "$result" ]]; then
  echo -e "${GREEN}✓ PASS${NC}: Non-matching task returns empty string"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: Non-matching task should return empty"
  echo -e "  Got: $result"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test default engine fallback
if command -v yq &> /dev/null; then
  default_engine=$(get_default_engine ".ralphy/config.yaml")
  assert_equals "$default_engine" "claude" "Default engine is claude from config"
fi

# Test with missing config (should use AI_ENGINE env var or claude)
rm -f .ralphy/config.yaml
export AI_ENGINE="opencode"
default_engine=$(get_default_engine ".ralphy/config.yaml")
assert_equals "$default_engine" "opencode" "Falls back to AI_ENGINE environment variable"

# Test with no config and no env var
unset AI_ENGINE
default_engine=$(get_default_engine ".ralphy/config.yaml")
assert_equals "$default_engine" "claude" "Falls back to hardcoded default (claude)"

# ============================================
# TEST 5: Empty config - no rules defined
# ============================================
print_test_header "5. Empty config - no specialization rules"

cat > .ralphy/config.yaml <<'EOF'
project:
  name: "test-app"

engines:
  meta_agent:
    engine: "cursor"
EOF

if command -v yq &> /dev/null; then
  result=$(match_specialization_rule "Any task description")
  if [[ -z "$result" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: Empty rules config returns no match"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗ FAIL${NC}: Empty rules config should return no match"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  default_engine=$(get_default_engine ".ralphy/config.yaml")
  assert_equals "$default_engine" "cursor" "Reads default engine from meta_agent config"
fi

# ============================================
# TEST 6: Missing config file
# ============================================
print_test_header "6. Missing config file handling"

rm -f .ralphy/config.yaml

result=$(match_specialization_rule "Some task")
if [[ -z "$result" ]]; then
  echo -e "${GREEN}✓ PASS${NC}: Missing config returns no match"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}✗ FAIL${NC}: Missing config should return no match"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

default_engine=$(get_default_engine ".ralphy/config.yaml")
assert_equals "$default_engine" "claude" "Missing config uses hardcoded default"

# ============================================
# TEST 7: Case-insensitive pattern matching
# ============================================
print_test_header "7. Case-insensitive pattern matching"

cat > .ralphy/config.yaml <<'EOF'
engines:
  specialization_rules:
    - pattern: "UI|frontend"
      engines: ["cursor"]
EOF

if command -v yq &> /dev/null; then
  result=$(match_specialization_rule "Update UI component")
  assert_contains "$result" "cursor" "Uppercase UI matches"

  result=$(match_specialization_rule "Update ui component")
  assert_contains "$result" "cursor" "Lowercase ui matches"

  result=$(match_specialization_rule "Frontend work needed")
  assert_contains "$result" "cursor" "Capitalized Frontend matches"
fi

# ============================================
# TEST 8: Metadata tracking for specialization
# ============================================
print_test_header "8. Metadata storage structure"

# Mock run_single_engine_task to avoid actual execution
run_single_engine_task() {
  local task_name="$1"
  local engine="$2"
  local spec_dir="$3"
  echo "Mock execution: $engine on '$task_name'" > "$spec_dir/execution.log"
  return 0
}

export -f run_single_engine_task

# Create a config with rules
cat > .ralphy/config.yaml <<'EOF'
engines:
  meta_agent:
    engine: "claude"
  specialization_rules:
    - pattern: "test"
      engines: ["codex"]
EOF

# Run specialization mode (should match and use codex)
if command -v yq &> /dev/null && command -v jq &> /dev/null; then
  run_specialization_mode "Add test for authentication" ".ralphy/config.yaml" > /dev/null 2>&1 || true

  # Find the most recent specialization directory
  spec_dir=$(find .ralphy/specialization -type d -name "spec-*" 2>/dev/null | sort -r | head -1)

  if [[ -n "$spec_dir" ]]; then
    assert_file_exists "$spec_dir/metadata.json" "Specialization metadata created"

    selected_engine=$(jq -r '.selected_engine' "$spec_dir/metadata.json" 2>/dev/null)
    assert_equals "$selected_engine" "codex" "Correct engine selected (codex for test)"

    matched_pattern=$(jq -r '.matched_pattern' "$spec_dir/metadata.json" 2>/dev/null)
    assert_contains "$matched_pattern" "test" "Pattern tracked in metadata"
  fi
fi

# ============================================
# TEST 9: No match scenario with metadata
# ============================================
print_test_header "9. No matching rules scenario - full flow"

cat > .ralphy/config.yaml <<'EOF'
engines:
  meta_agent:
    engine: "claude"
  specialization_rules:
    - pattern: "UI|frontend"
      engines: ["cursor"]
    - pattern: "test"
      engines: ["codex"]
EOF

if command -v yq &> /dev/null && command -v jq &> /dev/null; then
  # Task that doesn't match any rule
  run_specialization_mode "Implement data processing pipeline" ".ralphy/config.yaml" > /dev/null 2>&1 || true

  # Find the most recent specialization directory
  spec_dir=$(find .ralphy/specialization -type d -name "spec-*" 2>/dev/null | sort -r | head -1)

  if [[ -n "$spec_dir" ]]; then
    selected_engine=$(jq -r '.selected_engine' "$spec_dir/metadata.json" 2>/dev/null)
    assert_equals "$selected_engine" "claude" "Falls back to default engine (claude)"

    matched_pattern=$(jq -r '.matched_pattern' "$spec_dir/metadata.json" 2>/dev/null)
    assert_contains "$matched_pattern" "no match" "Metadata shows no match"
  fi
fi

# ============================================
# TEST 10: First matching rule wins
# ============================================
print_test_header "10. First matching rule precedence"

cat > .ralphy/config.yaml <<'EOF'
engines:
  specialization_rules:
    - pattern: "authentication"
      engines: ["cursor"]
    - pattern: "auth"
      engines: ["claude"]
EOF

if command -v yq &> /dev/null; then
  # Should match first rule (authentication) not second (auth)
  result=$(match_specialization_rule "Fix authentication bug")
  assert_contains "$result" "cursor" "First matching rule (authentication→cursor) wins"

  # Should only match second rule
  result=$(match_specialization_rule "Add auth middleware")
  # This could match both, but first rule should win if both match
  # In this case, "auth" is in "authentication" so we need a non-overlapping test

  result=$(match_specialization_rule "OAuth integration")
  assert_contains "$result" "claude" "Second rule matches when first doesn't"
fi

# ============================================
# SUMMARY
# ============================================
echo -e "\n${BLUE}================================================${NC}"
echo -e "${BLUE}TEST SUMMARY${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "Total tests: $TESTS_TOTAL"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
else
  echo -e "Failed: $TESTS_FAILED"
fi

# Cleanup
cd "$ORIGINAL_TEST_DIR"
rm -rf "$TEST_DIR"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "\n${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  echo -e "\n${RED}✗ Some tests failed${NC}"
  exit 1
fi
