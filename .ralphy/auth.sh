#!/bin/bash

# Auth Module for Ralphy
# Provides authentication and authorization functionality

# Global variables
AUTH_USERS_FILE="${AUTH_USERS_FILE:-.ralphy/users.json}"
AUTH_SESSION_TIMEOUT="${AUTH_SESSION_TIMEOUT:-3600}"
AUTH_TOKEN_LENGTH="${AUTH_TOKEN_LENGTH:-32}"

# Initialize auth storage
init_auth() {
  local users_file=$1
  if [[ ! -f "$users_file" ]]; then
    echo '{"users": {}, "sessions": {}}' > "$users_file"
  fi
}

# Hash a password (using sha256)
hash_password() {
  local password=$1
  echo -n "$password" | sha256sum | awk '{print $1}'
}

# Create a new user
create_user() {
  local username=$1
  local password=$2
  local users_file="${3:-$AUTH_USERS_FILE}"

  if [[ -z "$username" ]] || [[ -z "$password" ]]; then
    echo "Error: Username and password required" >&2
    return 1
  fi

  # Check if user already exists
  if user_exists "$username" "$users_file"; then
    echo "Error: User '$username' already exists" >&2
    return 1
  fi

  # Hash the password
  local hashed_password=$(hash_password "$password")

  # Add user to storage
  local temp_file=$(mktemp)
  jq --arg username "$username" \
     --arg password "$hashed_password" \
     '.users[$username] = {"password": $password, "created_at": now, "active": true}' \
     "$users_file" > "$temp_file" && mv "$temp_file" "$users_file"

  echo "User '$username' created successfully"
  return 0
}

# Check if user exists
user_exists() {
  local username=$1
  local users_file="${2:-$AUTH_USERS_FILE}"

  if [[ ! -f "$users_file" ]]; then
    return 1
  fi

  local exists=$(jq -r --arg username "$username" \
    '.users[$username] // empty' "$users_file")

  [[ -n "$exists" ]]
}

# Authenticate user and return session token
authenticate() {
  local username=$1
  local password=$2
  local users_file="${3:-$AUTH_USERS_FILE}"

  if [[ -z "$username" ]] || [[ -z "$password" ]]; then
    echo "Error: Username and password required" >&2
    return 1
  fi

  # Check if user exists
  if ! user_exists "$username" "$users_file"; then
    echo "Error: Invalid credentials" >&2
    return 1
  fi

  # Verify password
  local hashed_password=$(hash_password "$password")
  local stored_password=$(jq -r --arg username "$username" \
    '.users[$username].password' "$users_file")

  if [[ "$hashed_password" != "$stored_password" ]]; then
    echo "Error: Invalid credentials" >&2
    return 1
  fi

  # Check if user is active
  local is_active=$(jq -r --arg username "$username" \
    '.users[$username].active' "$users_file")

  if [[ "$is_active" != "true" ]]; then
    echo "Error: User account is inactive" >&2
    return 1
  fi

  # Generate session token
  local token=$(generate_token)
  local expires_at=$(($(date +%s) + AUTH_SESSION_TIMEOUT))

  # Store session
  local temp_file=$(mktemp)
  jq --arg token "$token" \
     --arg username "$username" \
     --arg expires_at "$expires_at" \
     '.sessions[$token] = {"username": $username, "expires_at": ($expires_at | tonumber), "created_at": now}' \
     "$users_file" > "$temp_file" && mv "$temp_file" "$users_file"

  echo "$token"
  return 0
}

# Generate a random token
generate_token() {
  if command -v openssl &> /dev/null; then
    openssl rand -hex "$((AUTH_TOKEN_LENGTH / 2))"
  else
    # Fallback to /dev/urandom
    cat /dev/urandom | LC_ALL=C tr -dc 'a-f0-9' | fold -w "$AUTH_TOKEN_LENGTH" | head -n 1
  fi
}

# Validate a session token
validate_token() {
  local token=$1
  local users_file="${2:-$AUTH_USERS_FILE}"

  if [[ -z "$token" ]]; then
    echo "Error: Token required" >&2
    return 1
  fi

  if [[ ! -f "$users_file" ]]; then
    echo "Error: Auth storage not found" >&2
    return 1
  fi

  # Get session info
  local session=$(jq -r --arg token "$token" \
    '.sessions[$token] // empty' "$users_file")

  if [[ -z "$session" ]]; then
    echo "Error: Invalid token" >&2
    return 1
  fi

  # Check expiration
  local expires_at=$(echo "$session" | jq -r '.expires_at')
  local current_time=$(date +%s)

  if [[ "$current_time" -gt "$expires_at" ]]; then
    echo "Error: Token expired" >&2
    return 1
  fi

  # Return username
  echo "$session" | jq -r '.username'
  return 0
}

# Revoke a session token (logout)
revoke_token() {
  local token=$1
  local users_file="${2:-$AUTH_USERS_FILE}"

  if [[ -z "$token" ]]; then
    echo "Error: Token required" >&2
    return 1
  fi

  # Check if token exists
  local exists=$(jq -r --arg token "$token" \
    '.sessions[$token] // empty' "$users_file")

  if [[ -z "$exists" ]]; then
    echo "Error: Invalid token" >&2
    return 1
  fi

  # Remove session
  local temp_file=$(mktemp)
  jq --arg token "$token" \
     'del(.sessions[$token])' \
     "$users_file" > "$temp_file" && mv "$temp_file" "$users_file"

  echo "Token revoked successfully"
  return 0
}

# Deactivate a user account
deactivate_user() {
  local username=$1
  local users_file="${2:-$AUTH_USERS_FILE}"

  if [[ -z "$username" ]]; then
    echo "Error: Username required" >&2
    return 1
  fi

  if ! user_exists "$username" "$users_file"; then
    echo "Error: User '$username' not found" >&2
    return 1
  fi

  # Update user status
  local temp_file=$(mktemp)
  jq --arg username "$username" \
     '.users[$username].active = false' \
     "$users_file" > "$temp_file" && mv "$temp_file" "$users_file"

  echo "User '$username' deactivated successfully"
  return 0
}

# Activate a user account
activate_user() {
  local username=$1
  local users_file="${2:-$AUTH_USERS_FILE}"

  if [[ -z "$username" ]]; then
    echo "Error: Username required" >&2
    return 1
  fi

  if ! user_exists "$username" "$users_file"; then
    echo "Error: User '$username' not found" >&2
    return 1
  fi

  # Update user status
  local temp_file=$(mktemp)
  jq --arg username "$username" \
     '.users[$username].active = true' \
     "$users_file" > "$temp_file" && mv "$temp_file" "$users_file"

  echo "User '$username' activated successfully"
  return 0
}

# Clean up expired sessions
cleanup_expired_sessions() {
  local users_file="${1:-$AUTH_USERS_FILE}"
  local current_time=$(date +%s)

  if [[ ! -f "$users_file" ]]; then
    return 0
  fi

  local temp_file=$(mktemp)
  jq --arg current_time "$current_time" \
     '.sessions |= with_entries(select(.value.expires_at > ($current_time | tonumber)))' \
     "$users_file" > "$temp_file" && mv "$temp_file" "$users_file"

  return 0
}

# Get user info (without sensitive data)
get_user_info() {
  local username=$1
  local users_file="${2:-$AUTH_USERS_FILE}"

  if [[ -z "$username" ]]; then
    echo "Error: Username required" >&2
    return 1
  fi

  if ! user_exists "$username" "$users_file"; then
    echo "Error: User '$username' not found" >&2
    return 1
  fi

  jq -r --arg username "$username" \
    '.users[$username] | {created_at, active}' \
    "$users_file"

  return 0
}

# List all active sessions for a user
list_user_sessions() {
  local username=$1
  local users_file="${2:-$AUTH_USERS_FILE}"

  if [[ -z "$username" ]]; then
    echo "Error: Username required" >&2
    return 1
  fi

  if [[ ! -f "$users_file" ]]; then
    echo "[]"
    return 0
  fi

  jq -r --arg username "$username" \
    '[.sessions | to_entries[] | select(.value.username == $username) | {token: .key, created_at: .value.created_at, expires_at: .value.expires_at}]' \
    "$users_file"

  return 0
}
