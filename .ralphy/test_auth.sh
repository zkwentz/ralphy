#!/usr/bin/env bash

# ============================================
# Authentication Module Test Suite
# ============================================
# Tests for .ralphy/auth.sh module
# Run this to verify authentication module works correctly

set -eo pipefail

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Source the authentication module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_MODULE="$SCRIPT_DIR/auth.sh"

if [[ ! -f "$AUTH_MODULE" ]]; then
    echo -e "${RED}ERROR: Authentication module not found at $AUTH_MODULE${RESET}"
    exit 1
fi

# shellcheck source=auth.sh
source "$AUTH_MODULE"

# ============================================
# TEST UTILITIES
# ============================================

print_test_header() {
    echo -e "\n${BLUE}========================================${RESET}"
    echo -e "${BLUE}$1${RESET}"
    echo -e "${BLUE}========================================${RESET}"
}

print_test() {
    echo -e "${YELLOW}TEST: $1${RESET}"
    ((TESTS_RUN++))
}

pass() {
    echo -e "${GREEN}✓ PASS${RESET}"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL: $1${RESET}"
    ((TESTS_FAILED++))
}

# ============================================
# TESTS
# ============================================

echo -e "${BLUE}╔════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║  Ralphy Authentication Module Tests   ║${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════╝${RESET}"

print_test_header "Engine Validation Tests"

# Test valid engines
for engine in claude opencode cursor qwen droid codex; do
    print_test "validate_engine accepts '$engine'"
    if validate_engine "$engine" 2>/dev/null; then
        pass
    else
        fail "Should accept valid engine: $engine"
    fi
done

# Test invalid engine
print_test "validate_engine rejects 'invalid_engine'"
if validate_engine "invalid_engine" 2>/dev/null; then
    fail "Should reject invalid engine"
else
    pass
fi

print_test_header "Engine Auth Flags Tests"

for engine in claude opencode cursor qwen droid codex; do
    print_test "get_engine_auth_flags returns flags for $engine"
    flags=$(get_engine_auth_flags "$engine")
    if [[ -n "$flags" ]]; then
        pass
    else
        fail "$engine should have auth flags"
    fi
done

print_test_header "Engine Cleanup Requirements Tests"

print_test "codex requires cleanup"
if engine_requires_cleanup "codex" 2>/dev/null; then
    pass
else
    fail "Codex should require cleanup"
fi

print_test "claude does not require cleanup"
if engine_requires_cleanup "claude" 2>/dev/null; then
    fail "Claude should not require cleanup"
else
    pass
fi

print_test_header "Engine Command Building Tests"

prompt="test prompt"
output_file="/tmp/test_output.txt"

for engine in claude opencode cursor qwen droid codex; do
    print_test "build_engine_command generates command for $engine"
    cmd=$(build_engine_command "$engine" "$prompt" "$output_file" 2>/dev/null)
    if [[ -n "$cmd" ]]; then
        pass
    else
        fail "$engine command should not be empty"
    fi
    # Cleanup after building
    cleanup_engine_auth "$engine" "$output_file" 2>/dev/null || true
done

print_test_header "Auth Setup/Cleanup Tests"

output_file="/tmp/test_output.txt"

print_test "setup_engine_auth configures opencode environment"
setup_engine_auth "opencode" "$output_file" 2>/dev/null
if [[ -n "${OPENCODE_PERMISSION:-}" ]]; then
    pass
    cleanup_engine_auth "opencode" "$output_file" 2>/dev/null || true
else
    fail "OPENCODE_PERMISSION should be set"
fi

print_test "cleanup_engine_auth removes opencode environment"
setup_engine_auth "opencode" "$output_file" 2>/dev/null
cleanup_engine_auth "opencode" "$output_file" 2>/dev/null
if [[ -z "${OPENCODE_PERMISSION:-}" ]]; then
    pass
else
    fail "OPENCODE_PERMISSION should be unset"
fi

print_test "setup_engine_auth configures codex environment"
setup_engine_auth "codex" "$output_file" 2>/dev/null
if [[ -n "${CODEX_LAST_MESSAGE_FILE:-}" ]]; then
    pass
    cleanup_engine_auth "codex" "$output_file" 2>/dev/null || true
else
    fail "CODEX_LAST_MESSAGE_FILE should be set"
fi

print_test_header "Supported Engines List Test"

print_test "get_supported_engines returns list of engines"
engines=$(get_supported_engines)
if [[ -n "$engines" ]]; then
    pass
else
    fail "Should return list of supported engines"
fi

print_test "get_supported_engines includes all 6 engines"
count=$(echo "$engines" | wc -w | tr -d ' ')
if [[ "$count" -eq 6 ]]; then
    pass
else
    fail "Should return 6 engines, got $count"
fi

print_test_header "Engine Permission Info Tests"

for engine in claude opencode cursor qwen droid codex; do
    print_test "get_engine_permission_info returns info for $engine"
    info=$(get_engine_permission_info "$engine")
    if [[ -n "$info" ]] && [[ "$info" != "Unknown engine" ]]; then
        pass
    else
        fail "Should return permission info for $engine"
    fi
done

# ============================================
# PRINT RESULTS
# ============================================

echo -e "\n${BLUE}========================================${RESET}"
echo -e "${BLUE}TEST RESULTS${RESET}"
echo -e "${BLUE}========================================${RESET}"
echo -e "Tests run:    ${TESTS_RUN}"
echo -e "${GREEN}Tests passed: ${TESTS_PASSED}${RESET}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Tests failed: ${TESTS_FAILED}${RESET}"
else
    echo -e "${GREEN}Tests failed: ${TESTS_FAILED}${RESET}"
fi

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}✓ All tests passed!${RESET}"
    exit 0
else
    echo -e "\n${RED}✗ Some tests failed${RESET}"
    exit 1
fi
