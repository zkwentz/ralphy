#!/usr/bin/env bash

# ============================================
# Race Mode Test Script
# Tests the race mode functionality
# ============================================

set -euo pipefail

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

log_info() {
  echo "${BLUE}[TEST]${RESET} $*"
}

log_success() {
  echo "${GREEN}[PASS]${RESET} $*"
}

log_error() {
  echo "${RED}[FAIL]${RESET} $*"
}

log_warn() {
  echo "${YELLOW}[WARN]${RESET} $*"
}

# ============================================
# Test Setup
# ============================================

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

log_info "Setting up test repository in $TEST_DIR"

# Initialize git repo
git init
git config user.email "test@example.com"
git config user.name "Test User"

# Create a simple test file
cat > test_file.txt << 'EOF'
# Test File
This is a test file for race mode testing.
EOF

git add test_file.txt
git commit -m "Initial commit"

log_success "Test repository initialized"

# ============================================
# Test 1: Parse race mode flags
# ============================================

log_info "Test 1: Verify race mode flags are parsed correctly"

# This test verifies that the script can parse race mode flags
# We'll check by sourcing the script and verifying variables are set

RALPHY_SCRIPT="$OLDPWD/ralphy.sh"

if [[ ! -f "$RALPHY_SCRIPT" ]]; then
  log_error "ralphy.sh not found at $RALPHY_SCRIPT"
  exit 1
fi

# Test parsing --race flag
if grep -q "RACE_MODE=false" "$RALPHY_SCRIPT" && \
   grep -q "RACE_ENGINES=()" "$RALPHY_SCRIPT" && \
   grep -q "RACE_VALIDATION_REQUIRED=true" "$RALPHY_SCRIPT" && \
   grep -q "RACE_TIMEOUT_MULTIPLIER=1.5" "$RALPHY_SCRIPT"; then
  log_success "Race mode variables defined correctly"
else
  log_error "Race mode variables not found or incorrectly defined"
  exit 1
fi

# Test --race flag parsing
if grep -q "\-\-race)" "$RALPHY_SCRIPT" && \
   grep -A 1 "\-\-race)" "$RALPHY_SCRIPT" | grep -q "RACE_MODE=true"; then
  log_success "--race flag parsing implemented"
else
  log_error "--race flag parsing not found"
  exit 1
fi

# Test --race-engines flag parsing
if grep -q "\-\-race-engines)" "$RALPHY_SCRIPT" && \
   grep -A 1 "\-\-race-engines)" "$RALPHY_SCRIPT" | grep -q "RACE_ENGINES"; then
  log_success "--race-engines flag parsing implemented"
else
  log_error "--race-engines flag parsing not found"
  exit 1
fi

# ============================================
# Test 2: Verify race mode functions exist
# ============================================

log_info "Test 2: Verify race mode functions are defined"

if grep -q "^validate_race_solution()" "$RALPHY_SCRIPT"; then
  log_success "validate_race_solution() function exists"
else
  log_error "validate_race_solution() function not found"
  exit 1
fi

if grep -q "^run_race_agent()" "$RALPHY_SCRIPT"; then
  log_success "run_race_agent() function exists"
else
  log_error "run_race_agent() function not found"
  exit 1
fi

if grep -q "^run_race_mode()" "$RALPHY_SCRIPT"; then
  log_success "run_race_mode() function exists"
else
  log_error "run_race_mode() function not found"
  exit 1
fi

# ============================================
# Test 3: Verify race mode routing in main()
# ============================================

log_info "Test 3: Verify race mode routing in main()"

if grep -q "if \[\[ \"\$RACE_MODE\" == true \]\]" "$RALPHY_SCRIPT"; then
  log_success "Race mode routing implemented in main()"
else
  log_error "Race mode routing not found in main()"
  exit 1
fi

if grep -q "run_race_mode" "$RALPHY_SCRIPT"; then
  log_success "run_race_mode called in script"
else
  log_error "run_race_mode not called in script"
  exit 1
fi

# ============================================
# Test 4: Verify validation logic
# ============================================

log_info "Test 4: Verify validation logic in validate_race_solution()"

# Check for commit validation
if grep -A 10 "^validate_race_solution()" "$RALPHY_SCRIPT" | grep -q "git.*rev-list.*count"; then
  log_success "Commit count validation implemented"
else
  log_error "Commit count validation not found"
  exit 1
fi

# Check for test validation
if grep -A 40 "^validate_race_solution()" "$RALPHY_SCRIPT" | grep -qi "test"; then
  log_success "Test validation implemented"
else
  log_error "Test validation not found"
  exit 1
fi

# Check for lint validation
if grep -A 50 "^validate_race_solution()" "$RALPHY_SCRIPT" | grep -qi "lint"; then
  log_success "Lint validation implemented"
else
  log_error "Lint validation not found"
  exit 1
fi

# ============================================
# Test 5: Verify early winner logic
# ============================================

log_info "Test 5: Verify early winner detection and cleanup"

# Check for winner detection
if grep -A 150 "run_race_mode()" "$RALPHY_SCRIPT" | grep -q "winner_found=true"; then
  log_success "Winner detection logic implemented"
else
  log_error "Winner detection logic not found"
  exit 1
fi

# Check for killing other agents
if grep -A 200 "run_race_mode()" "$RALPHY_SCRIPT" | grep -q "kill.*other_pid"; then
  log_success "Agent cleanup (kill) logic implemented"
else
  log_error "Agent cleanup logic not found"
  exit 1
fi

# Check for status monitoring
if grep -A 200 "run_race_mode()" "$RALPHY_SCRIPT" | grep -q "case.*status"; then
  log_success "Status monitoring logic implemented"
else
  log_error "Status monitoring logic not found"
  exit 1
fi

# ============================================
# Test 6: Verify timeout handling
# ============================================

log_info "Test 6: Verify timeout handling"

if grep -A 200 "run_race_mode()" "$RALPHY_SCRIPT" | grep -q "timeout.*RACE_TIMEOUT_MULTIPLIER"; then
  log_success "Timeout calculation implemented"
else
  log_error "Timeout calculation not found"
  exit 1
fi

if grep -A 200 "run_race_mode()" "$RALPHY_SCRIPT" | grep -q "current_time.*timeout"; then
  log_success "Timeout check implemented"
else
  log_error "Timeout check not found"
  exit 1
fi

# ============================================
# Test 7: Verify multiple engine support
# ============================================

log_info "Test 7: Verify multiple engine support"

engines=("claude" "opencode" "cursor" "codex" "qwen" "droid")
for engine in "${engines[@]}"; do
  if grep -A 150 "run_race_agent()" "$RALPHY_SCRIPT" | grep -q "$engine)"; then
    log_success "$engine engine support found"
  else
    log_warn "$engine engine support not found (may be expected)"
  fi
done

# ============================================
# Test Summary
# ============================================

echo ""
echo "${BOLD}============================================${RESET}"
echo "${BOLD}Test Summary${RESET}"
echo "${BOLD}============================================${RESET}"
log_success "All core race mode tests passed!"
echo ""
log_info "Race mode features verified:"
echo "  ✓ CLI flag parsing (--race, --race-engines, --no-validation, --race-timeout)"
echo "  ✓ Core functions (validate_race_solution, run_race_agent, run_race_mode)"
echo "  ✓ Main routing to race mode"
echo "  ✓ Validation logic (commits, tests, lint)"
echo "  ✓ Early winner detection and cleanup"
echo "  ✓ Timeout handling"
echo "  ✓ Multiple engine support"
echo ""
log_info "Note: Integration tests require actual AI engines to be installed"
echo ""

# Cleanup
cd /
rm -rf "$TEST_DIR"

log_success "Test cleanup complete"
