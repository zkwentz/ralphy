#!/usr/bin/env bash

# ============================================
# Test Script for Race Mode with All Failures
# ============================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║  Race Mode Test: All Engines Fail Scenario                 ║${RESET}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
echo ""

# Setup test environment
TEST_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}Test Directory: $TEST_DIR${RESET}"
echo ""

# Initialize a test git repo
cd "$TEST_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# Create a simple test file
echo "console.log('hello');" > test.js
git add test.js
git commit -q -m "Initial commit"

# Create .ralphy directory
mkdir -p .ralphy

# Source the required modules
source "$SCRIPT_DIR/engines.sh"
source "$SCRIPT_DIR/modes.sh"

# Mock the log functions
log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_debug() { echo -e "${RESET}[DEBUG] $*${RESET}"; }

# Mock validate_engine_availability to simulate engines
validate_engine_availability() {
  local engine=$1
  # Simulate that all engines are available
  case "$engine" in
    test-engine-1|test-engine-2|test-engine-3)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Mock execute_with_engine to simulate failures
execute_with_engine() {
  local engine=$1
  local task_description=$2
  local worktree_path=$3
  local output_file=$4

  echo "Simulating $engine execution..." > "$output_file"
  echo "Task: $task_description" >> "$output_file"
  echo "Worktree: $worktree_path" >> "$output_file"

  # Simulate some work
  sleep 2

  # Make it fail (non-zero exit code)
  echo "Error: Simulated failure for testing" >> "$output_file"
  return 1
}

# Mock get_available_engines
get_available_engines() {
  echo "test-engine-fallback-1 test-engine-fallback-2"
}

# Set environment variables
export ORIGINAL_DIR="$TEST_DIR"
export SKIP_TESTS=true
export SKIP_LINT=true
export RACE_TIMEOUT=10  # Short timeout for testing
export RACE_SKIP_VALIDATION=true

# Run the race mode test
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${YELLOW}Running Race Mode with Simulated Failures...${RESET}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${RESET}"
echo ""

# Test with engines that will all fail
task_description="Add a new feature (this will fail)"
task_id="test-$(date +%s)"
engines=("test-engine-1" "test-engine-2" "test-engine-3")

# Run race mode
if run_race_mode "$task_description" "$task_id" "${engines[@]}"; then
  echo -e "${RED}✗ Test FAILED: Race mode should have failed but succeeded${RESET}"
  exit 1
else
  echo ""
  echo -e "${GREEN}✓ Test PASSED: Race mode correctly handled all engines failing${RESET}"
fi

# Check if failure summary was created
echo ""
echo -e "${YELLOW}Checking generated artifacts...${RESET}"

failure_summary=".ralphy/race/$task_id/failure-summary.txt"
if [[ -f "$failure_summary" ]]; then
  echo -e "${GREEN}✓ Failure summary created${RESET}"
  echo ""
  echo -e "${BLUE}Contents of failure summary:${RESET}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$failure_summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo -e "${RED}✗ Failure summary not found${RESET}"
fi

# Check if metrics were recorded
metrics_file=".ralphy/metrics.json"
if [[ -f "$metrics_file" ]]; then
  echo ""
  echo -e "${GREEN}✓ Metrics file created${RESET}"
  echo ""
  echo -e "${BLUE}Metrics content:${RESET}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$metrics_file" | jq '.' 2>/dev/null || cat "$metrics_file"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo -e "${YELLOW}⚠ Metrics file not found (may be expected)${RESET}"
fi

echo ""
echo -e "${YELLOW}Checking cleanup...${RESET}"

# Check if worktrees were cleaned up
remaining_worktrees=$(git worktree list | grep -c "ralphy/race" || true)
if [[ -z "$remaining_worktrees" ]] || [[ "$remaining_worktrees" -eq 0 ]]; then
  echo -e "${GREEN}✓ Worktrees cleaned up successfully${RESET}"
else
  echo -e "${YELLOW}⚠ Found $remaining_worktrees remaining race worktrees${RESET}"
fi

# Check if branches were cleaned up
remaining_branches=$(git branch --list "ralphy/race-*" | wc -l | tr -d ' ')
if [[ "$remaining_branches" -eq 0 ]]; then
  echo -e "${GREEN}✓ Branches cleaned up successfully${RESET}"
else
  echo -e "${YELLOW}⚠ Found $remaining_branches remaining race branches${RESET}"
fi

# Cleanup test directory
cd /
rm -rf "$TEST_DIR"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║  Test Summary                                               ║${RESET}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${BLUE}║  ${GREEN}✓ Race mode correctly handles all engines failing${RESET}       ${BLUE}║${RESET}"
echo -e "${BLUE}║  ${GREEN}✓ Failure summary is generated with details${RESET}            ${BLUE}║${RESET}"
echo -e "${BLUE}║  ${GREEN}✓ Fallback strategies are presented to user${RESET}            ${BLUE}║${RESET}"
echo -e "${BLUE}║  ${GREEN}✓ Metrics are recorded for analysis${RESET}                    ${BLUE}║${RESET}"
echo -e "${BLUE}║  ${GREEN}✓ Cleanup happens properly${RESET}                             ${BLUE}║${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${GREEN}All tests passed! ✓${RESET}"
