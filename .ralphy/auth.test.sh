#!/bin/bash

# Unit tests for auth.sh module
# Uses bash-based testing pattern

# Source the auth module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_TEMP_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Setup test environment
setup() {
  TEST_TEMP_DIR=$(mktemp -d)
  AUTH_USERS_FILE="$TEST_TEMP_DIR/users.json"
  export AUTH_USERS_FILE
  init_auth "$AUTH_USERS_FILE"
}

# Teardown test environment
teardown() {
  if [[ -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Assert functions
assert_equals() {
  local expected=$1
  local actual=$2
  local message=${3:-"Assertion failed"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo "  Expected: '$expected'"
    echo "  Actual:   '$actual'"
    return 1
  fi
}

assert_success() {
  local command_output=$1
  local message=${2:-"Command should succeed"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ $command_output -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message (exit code: $command_output)"
    return 1
  fi
}

assert_failure() {
  local command_output=$1
  local message=${2:-"Command should fail"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ $command_output -ne 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message (expected failure but got success)"
    return 1
  fi
}

assert_not_empty() {
  local value=$1
  local message=${2:-"Value should not be empty"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ -n "$value" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message (value is empty)"
    return 1
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=${3:-"String should contain substring"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$haystack" == *"$needle"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo "  Haystack: '$haystack'"
    echo "  Needle:   '$needle'"
    return 1
  fi
}

# Test: init_auth creates users file
test_init_auth() {
  echo -e "\n${YELLOW}Test: init_auth${NC}"
  local temp_file="$TEST_TEMP_DIR/test_init.json"

  init_auth "$temp_file"
  [[ -f "$temp_file" ]]
  assert_success $? "Should create users file"

  local content=$(cat "$temp_file")
  assert_contains "$content" '"users"' "Should contain users key"
  assert_contains "$content" '"sessions"' "Should contain sessions key"
}

# Test: hash_password generates consistent hash
test_hash_password() {
  echo -e "\n${YELLOW}Test: hash_password${NC}"

  local hash1=$(hash_password "test123")
  local hash2=$(hash_password "test123")

  assert_equals "$hash1" "$hash2" "Should generate consistent hash for same password"
  assert_not_empty "$hash1" "Hash should not be empty"

  local hash3=$(hash_password "different")
  [[ "$hash1" != "$hash3" ]]
  assert_success $? "Different passwords should generate different hashes"
}

# Test: create_user with valid credentials
test_create_user_success() {
  echo -e "\n${YELLOW}Test: create_user (success)${NC}"

  local output=$(create_user "testuser" "password123" 2>&1)
  assert_success $? "Should create user successfully"
  assert_contains "$output" "created successfully" "Should return success message"

  user_exists "testuser"
  assert_success $? "User should exist after creation"
}

# Test: create_user with missing username
test_create_user_missing_username() {
  echo -e "\n${YELLOW}Test: create_user (missing username)${NC}"

  create_user "" "password123" 2>/dev/null
  assert_failure $? "Should fail with missing username"
}

# Test: create_user with missing password
test_create_user_missing_password() {
  echo -e "\n${YELLOW}Test: create_user (missing password)${NC}"

  create_user "testuser" "" 2>/dev/null
  assert_failure $? "Should fail with missing password"
}

# Test: create_user with duplicate username
test_create_user_duplicate() {
  echo -e "\n${YELLOW}Test: create_user (duplicate)${NC}"

  create_user "testuser" "password123" >/dev/null 2>&1
  create_user "testuser" "password456" 2>/dev/null
  assert_failure $? "Should fail when creating duplicate user"
}

# Test: user_exists returns correct result
test_user_exists() {
  echo -e "\n${YELLOW}Test: user_exists${NC}"

  user_exists "nonexistent"
  assert_failure $? "Should return false for non-existent user"

  create_user "existinguser" "password123" >/dev/null 2>&1
  user_exists "existinguser"
  assert_success $? "Should return true for existing user"
}

# Test: authenticate with valid credentials
test_authenticate_success() {
  echo -e "\n${YELLOW}Test: authenticate (success)${NC}"

  create_user "authuser" "password123" >/dev/null 2>&1

  local token=$(authenticate "authuser" "password123" 2>&1)
  local auth_result=$?

  assert_success $auth_result "Should authenticate successfully"
  assert_not_empty "$token" "Should return session token"

  # Token should be hex string of specified length
  [[ ${#token} -eq $AUTH_TOKEN_LENGTH ]]
  assert_success $? "Token should have correct length"
}

# Test: authenticate with invalid username
test_authenticate_invalid_username() {
  echo -e "\n${YELLOW}Test: authenticate (invalid username)${NC}"

  authenticate "nonexistent" "password123" 2>/dev/null
  assert_failure $? "Should fail with invalid username"
}

# Test: authenticate with invalid password
test_authenticate_invalid_password() {
  echo -e "\n${YELLOW}Test: authenticate (invalid password)${NC}"

  create_user "authuser" "password123" >/dev/null 2>&1
  authenticate "authuser" "wrongpassword" 2>/dev/null
  assert_failure $? "Should fail with invalid password"
}

# Test: authenticate with inactive user
test_authenticate_inactive_user() {
  echo -e "\n${YELLOW}Test: authenticate (inactive user)${NC}"

  create_user "inactiveuser" "password123" >/dev/null 2>&1
  deactivate_user "inactiveuser" >/dev/null 2>&1

  authenticate "inactiveuser" "password123" 2>/dev/null
  assert_failure $? "Should fail with inactive user"
}

# Test: validate_token with valid token
test_validate_token_success() {
  echo -e "\n${YELLOW}Test: validate_token (success)${NC}"

  create_user "validuser" "password123" >/dev/null 2>&1
  local token=$(authenticate "validuser" "password123" 2>&1 | grep -v "Error")

  local username=$(validate_token "$token" 2>&1 | grep -v "Error")
  local validate_result=$?

  assert_success $validate_result "Should validate token successfully"
  assert_equals "validuser" "$username" "Should return correct username"
}

# Test: validate_token with invalid token
test_validate_token_invalid() {
  echo -e "\n${YELLOW}Test: validate_token (invalid)${NC}"

  validate_token "invalidtoken123" 2>/dev/null
  assert_failure $? "Should fail with invalid token"
}

# Test: validate_token with empty token
test_validate_token_empty() {
  echo -e "\n${YELLOW}Test: validate_token (empty)${NC}"

  validate_token "" 2>/dev/null
  assert_failure $? "Should fail with empty token"
}

# Test: validate_token with expired token
test_validate_token_expired() {
  echo -e "\n${YELLOW}Test: validate_token (expired)${NC}"

  # Set very short timeout
  AUTH_SESSION_TIMEOUT=1
  export AUTH_SESSION_TIMEOUT

  create_user "expireuser" "password123" >/dev/null 2>&1
  local token=$(authenticate "expireuser" "password123" 2>&1 | grep -v "Error")

  # Wait for token to expire
  sleep 2

  validate_token "$token" 2>/dev/null
  assert_failure $? "Should fail with expired token"

  # Reset timeout
  AUTH_SESSION_TIMEOUT=3600
  export AUTH_SESSION_TIMEOUT
}

# Test: revoke_token
test_revoke_token() {
  echo -e "\n${YELLOW}Test: revoke_token${NC}"

  create_user "revokeuser" "password123" >/dev/null 2>&1
  local token=$(authenticate "revokeuser" "password123" 2>&1 | grep -v "Error")

  # Token should be valid before revocation
  validate_token "$token" >/dev/null 2>&1
  assert_success $? "Token should be valid before revocation"

  # Revoke token
  revoke_token "$token" >/dev/null 2>&1
  assert_success $? "Should revoke token successfully"

  # Token should be invalid after revocation
  validate_token "$token" 2>/dev/null
  assert_failure $? "Token should be invalid after revocation"
}

# Test: revoke_token with invalid token
test_revoke_token_invalid() {
  echo -e "\n${YELLOW}Test: revoke_token (invalid)${NC}"

  revoke_token "invalidtoken123" 2>/dev/null
  assert_failure $? "Should fail when revoking invalid token"
}

# Test: deactivate_user
test_deactivate_user() {
  echo -e "\n${YELLOW}Test: deactivate_user${NC}"

  create_user "deactivateuser" "password123" >/dev/null 2>&1

  # User should be active initially
  local is_active=$(jq -r '.users.deactivateuser.active' "$AUTH_USERS_FILE")
  assert_equals "true" "$is_active" "User should be active initially"

  # Deactivate user
  deactivate_user "deactivateuser" >/dev/null 2>&1
  assert_success $? "Should deactivate user successfully"

  # User should be inactive now
  is_active=$(jq -r '.users.deactivateuser.active' "$AUTH_USERS_FILE")
  assert_equals "false" "$is_active" "User should be inactive after deactivation"
}

# Test: activate_user
test_activate_user() {
  echo -e "\n${YELLOW}Test: activate_user${NC}"

  create_user "activateuser" "password123" >/dev/null 2>&1
  deactivate_user "activateuser" >/dev/null 2>&1

  # User should be inactive
  local is_active=$(jq -r '.users.activateuser.active' "$AUTH_USERS_FILE")
  assert_equals "false" "$is_active" "User should be inactive initially"

  # Activate user
  activate_user "activateuser" >/dev/null 2>&1
  assert_success $? "Should activate user successfully"

  # User should be active now
  is_active=$(jq -r '.users.activateuser.active' "$AUTH_USERS_FILE")
  assert_equals "true" "$is_active" "User should be active after activation"
}

# Test: cleanup_expired_sessions
test_cleanup_expired_sessions() {
  echo -e "\n${YELLOW}Test: cleanup_expired_sessions${NC}"

  # Set very short timeout
  AUTH_SESSION_TIMEOUT=1
  export AUTH_SESSION_TIMEOUT

  create_user "cleanupuser1" "password123" >/dev/null 2>&1
  create_user "cleanupuser2" "password456" >/dev/null 2>&1

  local token1=$(authenticate "cleanupuser1" "password123" 2>&1 | grep -v "Error")
  sleep 2
  local token2=$(authenticate "cleanupuser2" "password456" 2>&1 | grep -v "Error")

  # Clean up expired sessions
  cleanup_expired_sessions
  assert_success $? "Should cleanup expired sessions successfully"

  # Token1 should be gone, token2 should remain
  validate_token "$token1" 2>/dev/null
  assert_failure $? "Expired token should be removed"

  validate_token "$token2" >/dev/null 2>&1
  assert_success $? "Valid token should remain"

  # Reset timeout
  AUTH_SESSION_TIMEOUT=3600
  export AUTH_SESSION_TIMEOUT
}

# Test: get_user_info
test_get_user_info() {
  echo -e "\n${YELLOW}Test: get_user_info${NC}"

  create_user "infouser" "password123" >/dev/null 2>&1

  local info=$(get_user_info "infouser" 2>&1 | grep -v "Error")
  assert_success $? "Should get user info successfully"

  assert_contains "$info" '"active"' "Should contain active status"
  assert_contains "$info" '"created_at"' "Should contain creation timestamp"

  # Should not contain sensitive data
  [[ "$info" != *"password"* ]]
  assert_success $? "Should not expose password"
}

# Test: get_user_info for non-existent user
test_get_user_info_nonexistent() {
  echo -e "\n${YELLOW}Test: get_user_info (non-existent)${NC}"

  get_user_info "nonexistent" 2>/dev/null
  assert_failure $? "Should fail for non-existent user"
}

# Test: list_user_sessions
test_list_user_sessions() {
  echo -e "\n${YELLOW}Test: list_user_sessions${NC}"

  create_user "sessionuser" "password123" >/dev/null 2>&1

  # Create multiple sessions
  local token1=$(authenticate "sessionuser" "password123" 2>&1 | grep -v "Error")
  local token2=$(authenticate "sessionuser" "password123" 2>&1 | grep -v "Error")

  local sessions=$(list_user_sessions "sessionuser" 2>&1 | grep -v "Error")
  assert_success $? "Should list sessions successfully"

  assert_contains "$sessions" "$token1" "Should contain first token"
  assert_contains "$sessions" "$token2" "Should contain second token"
  assert_contains "$sessions" '"created_at"' "Should contain creation timestamp"
  assert_contains "$sessions" '"expires_at"' "Should contain expiration timestamp"
}

# Test: generate_token produces unique tokens
test_generate_token_unique() {
  echo -e "\n${YELLOW}Test: generate_token (uniqueness)${NC}"

  local token1=$(generate_token)
  local token2=$(generate_token)

  assert_not_empty "$token1" "First token should not be empty"
  assert_not_empty "$token2" "Second token should not be empty"

  [[ "$token1" != "$token2" ]]
  assert_success $? "Tokens should be unique"
}

# Test: Race condition - multiple concurrent authentications
test_concurrent_authentications() {
  echo -e "\n${YELLOW}Test: concurrent authentications (race condition)${NC}"

  create_user "raceuser" "password123" >/dev/null 2>&1

  # Simulate concurrent authentication attempts
  local token1=$(authenticate "raceuser" "password123" 2>&1 | grep -v "Error") &
  local pid1=$!
  local token2=$(authenticate "raceuser" "password123" 2>&1 | grep -v "Error") &
  local pid2=$!
  local token3=$(authenticate "raceuser" "password123" 2>&1 | grep -v "Error") &
  local pid3=$!

  wait $pid1 $pid2 $pid3

  # All authentications should succeed
  local sessions=$(list_user_sessions "raceuser" 2>&1 | grep -v "Error")
  local session_count=$(echo "$sessions" | jq 'length')

  [[ $session_count -ge 1 ]]
  assert_success $? "Should handle concurrent authentications without data corruption"
}

# Test: Special characters in password
test_special_characters_password() {
  echo -e "\n${YELLOW}Test: special characters in password${NC}"

  local special_password='p@ss$w0rd!#%&*()[]{}|<>?/'
  create_user "specialuser" "$special_password" >/dev/null 2>&1
  assert_success $? "Should create user with special characters in password"

  local token=$(authenticate "specialuser" "$special_password" 2>&1 | grep -v "Error")
  [[ -n "$token" && "$token" != *"Error"* ]]
  assert_success $? "Should authenticate with special characters in password"
}

# Test: Long username
test_long_username() {
  echo -e "\n${YELLOW}Test: long username${NC}"

  local long_username="user_with_very_long_username_that_should_still_work_correctly_123456789"
  create_user "$long_username" "password123" >/dev/null 2>&1
  assert_success $? "Should create user with long username"

  user_exists "$long_username"
  assert_success $? "Should find user with long username"
}

# Run all tests
run_all_tests() {
  echo -e "${YELLOW}========================================${NC}"
  echo -e "${YELLOW}Running Auth Module Unit Tests${NC}"
  echo -e "${YELLOW}========================================${NC}"

  setup

  # Initialization tests
  test_init_auth
  test_hash_password

  # User creation tests
  test_create_user_success
  test_create_user_missing_username
  test_create_user_missing_password
  test_create_user_duplicate
  test_user_exists

  # Authentication tests
  test_authenticate_success
  test_authenticate_invalid_username
  test_authenticate_invalid_password
  test_authenticate_inactive_user

  # Token validation tests
  test_validate_token_success
  test_validate_token_invalid
  test_validate_token_empty
  test_validate_token_expired

  # Token revocation tests
  test_revoke_token
  test_revoke_token_invalid

  # User management tests
  test_deactivate_user
  test_activate_user

  # Session management tests
  test_cleanup_expired_sessions
  test_get_user_info
  test_get_user_info_nonexistent
  test_list_user_sessions

  # Token generation tests
  test_generate_token_unique

  # Race condition tests
  test_concurrent_authentications

  # Edge case tests
  test_special_characters_password
  test_long_username

  teardown

  # Print summary
  echo -e "\n${YELLOW}========================================${NC}"
  echo -e "${YELLOW}Test Summary${NC}"
  echo -e "${YELLOW}========================================${NC}"
  echo -e "Total tests:  $TESTS_RUN"
  echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
  else
    echo -e "Failed:       $TESTS_FAILED"
  fi

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed! ✓${NC}"
    return 0
  else
    echo -e "\n${RED}Some tests failed! ✗${NC}"
    return 1
  fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all_tests
  exit $?
fi
