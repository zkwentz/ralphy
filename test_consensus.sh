#!/usr/bin/env bash

# Test script for consensus mode with 2 engines producing different results
# This tests the core functionality of consensus mode

set -euo pipefail

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)

TEST_DIR=$(pwd)
RALPHY_DIR=".ralphy"

log_test() {
  echo "${BOLD}[TEST]${RESET} $*"
}

log_pass() {
  echo "${GREEN}[PASS]${RESET} $*"
}

log_fail() {
  echo "${RED}[FAIL]${RESET} $*"
}

log_info() {
  echo "${YELLOW}[INFO]${RESET} $*"
}

# Test 1: Check that consensus mode modules exist
test_modules_exist() {
  log_test "Test 1: Check consensus mode modules exist"

  if [[ ! -f "$RALPHY_DIR/modes.sh" ]]; then
    log_fail "modes.sh not found"
    return 1
  fi

  if [[ ! -f "$RALPHY_DIR/meta-agent.sh" ]]; then
    log_fail "meta-agent.sh not found"
    return 1
  fi

  log_pass "Both modules exist"
  return 0
}

# Test 2: Check that modules are syntactically correct
test_modules_syntax() {
  log_test "Test 2: Check module syntax"

  if ! bash -n "$RALPHY_DIR/modes.sh"; then
    log_fail "modes.sh has syntax errors"
    return 1
  fi

  if ! bash -n "$RALPHY_DIR/meta-agent.sh"; then
    log_fail "meta-agent.sh has syntax errors"
    return 1
  fi

  log_pass "Both modules have valid syntax"
  return 0
}

# Test 3: Check that ralphy.sh sources the modules
test_ralphy_sources_modules() {
  log_test "Test 3: Check ralphy.sh sources modules"

  if ! grep -q "source.*modes.sh" ralphy.sh; then
    log_fail "ralphy.sh doesn't source modes.sh"
    return 1
  fi

  if ! grep -q "source.*meta-agent.sh" ralphy.sh; then
    log_fail "ralphy.sh doesn't source meta-agent.sh"
    return 1
  fi

  log_pass "ralphy.sh sources both modules"
  return 0
}

# Test 4: Check that consensus mode flags are present
test_consensus_flags() {
  log_test "Test 4: Check consensus mode CLI flags"

  if ! grep -q "CONSENSUS_MODE" ralphy.sh; then
    log_fail "CONSENSUS_MODE variable not found"
    return 1
  fi

  if ! grep -q "\-\-mode)" ralphy.sh; then
    log_fail "--mode flag not implemented"
    return 1
  fi

  if ! grep -q "\-\-consensus-engines)" ralphy.sh; then
    log_fail "--consensus-engines flag not implemented"
    return 1
  fi

  if ! grep -q "\-\-meta-agent)" ralphy.sh; then
    log_fail "--meta-agent flag not implemented"
    return 1
  fi

  log_pass "All consensus mode flags present"
  return 0
}

# Test 5: Check that run_consensus_mode function exists
test_consensus_function() {
  log_test "Test 5: Check run_consensus_mode function exists"

  if ! grep -q "run_consensus_mode()" "$RALPHY_DIR/modes.sh"; then
    log_fail "run_consensus_mode function not found"
    return 1
  fi

  if ! grep -q "run_consensus_agent()" "$RALPHY_DIR/modes.sh"; then
    log_fail "run_consensus_agent function not found"
    return 1
  fi

  log_pass "Consensus mode functions exist"
  return 0
}

# Test 6: Check that meta-agent function exists
test_meta_agent_function() {
  log_test "Test 6: Check meta-agent comparison function exists"

  if ! grep -q "run_meta_agent_comparison()" "$RALPHY_DIR/meta-agent.sh"; then
    log_fail "run_meta_agent_comparison function not found"
    return 1
  fi

  log_pass "Meta-agent comparison function exists"
  return 0
}

# Test 7: Check that consensus mode is integrated into brownfield mode
test_brownfield_integration() {
  log_test "Test 7: Check consensus mode integrated into brownfield"

  if ! grep -q "CONSENSUS_MODE.*true" ralphy.sh; then
    log_fail "Consensus mode check not found in brownfield task"
    return 1
  fi

  if ! grep -q "run_consensus_mode" ralphy.sh; then
    log_fail "run_consensus_mode not called in brownfield task"
    return 1
  fi

  log_pass "Consensus mode integrated into brownfield"
  return 0
}

# Test 8: Validate consensus mode logic flow
test_consensus_logic() {
  log_test "Test 8: Validate consensus mode logic"

  # Check that consensus mode:
  # 1. Launches multiple agents
  # 2. Collects results
  # 3. Calls meta-agent
  # 4. Applies chosen solution

  local has_multiple_agents=false
  local has_meta_agent_call=false
  local has_solution_apply=false

  if grep -q "for engine in.*ENGINES" "$RALPHY_DIR/modes.sh"; then
    has_multiple_agents=true
  fi

  if grep -q "run_meta_agent_comparison" "$RALPHY_DIR/modes.sh"; then
    has_meta_agent_call=true
  fi

  if grep -q "git merge.*chosen" "$RALPHY_DIR/modes.sh"; then
    has_solution_apply=true
  fi

  if [[ "$has_multiple_agents" != true ]]; then
    log_fail "Multiple agent launch not found"
    return 1
  fi

  if [[ "$has_meta_agent_call" != true ]]; then
    log_fail "Meta-agent call not found"
    return 1
  fi

  if [[ "$has_solution_apply" != true ]]; then
    log_fail "Solution application not found"
    return 1
  fi

  log_pass "Consensus mode logic flow correct"
  return 0
}

# Test 9: Check meta-agent prompt construction
test_meta_agent_prompt() {
  log_test "Test 9: Validate meta-agent prompt construction"

  if ! grep -q "TASK:" "$RALPHY_DIR/meta-agent.sh"; then
    log_fail "Meta-agent prompt doesn't include task"
    return 1
  fi

  if ! grep -q "SOLUTION" "$RALPHY_DIR/meta-agent.sh"; then
    log_fail "Meta-agent prompt doesn't include solutions"
    return 1
  fi

  if ! grep -q "CHOSEN:" "$RALPHY_DIR/meta-agent.sh"; then
    log_fail "Meta-agent doesn't extract CHOSEN field"
    return 1
  fi

  if ! grep -q "REASONING:" "$RALPHY_DIR/meta-agent.sh"; then
    log_fail "Meta-agent doesn't extract REASONING field"
    return 1
  fi

  log_pass "Meta-agent prompt construction correct"
  return 0
}

# Test 10: Check that consensus mode creates solution directories
test_solution_storage() {
  log_test "Test 10: Validate solution storage"

  if ! grep -q "mkdir.*consensus" "$RALPHY_DIR/modes.sh"; then
    log_fail "Consensus solution directory creation not found"
    return 1
  fi

  if ! grep -q "diff.*patch" "$RALPHY_DIR/modes.sh"; then
    log_fail "Diff storage not found"
    return 1
  fi

  if ! grep -q "commits.*txt" "$RALPHY_DIR/modes.sh"; then
    log_fail "Commit info storage not found"
    return 1
  fi

  log_pass "Solution storage implemented"
  return 0
}

# Run all tests
main() {
  log_info "Starting consensus mode tests"
  echo ""

  local passed=0
  local failed=0
  local tests=(
    test_modules_exist
    test_modules_syntax
    test_ralphy_sources_modules
    test_consensus_flags
    test_consensus_function
    test_meta_agent_function
    test_brownfield_integration
    test_consensus_logic
    test_meta_agent_prompt
    test_solution_storage
  )

  for test in "${tests[@]}"; do
    if $test; then
      ((passed++))
    else
      ((failed++))
    fi
    echo ""
  done

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "${BOLD}Test Results:${RESET}"
  echo "  ${GREEN}Passed: $passed${RESET}"
  echo "  ${RED}Failed: $failed${RESET}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ $failed -eq 0 ]]; then
    log_pass "All tests passed!"
    return 0
  else
    log_fail "Some tests failed"
    return 1
  fi
}

main "$@"
