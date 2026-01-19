#!/usr/bin/env bash

# ============================================
# Ralphy - Validation Gate Module
# Handles validation of solutions (test/lint/build)
# Used by multi-engine modes (consensus, race, specialization)
# ============================================

set -euo pipefail

# ============================================
# VALIDATION CONFIGURATION
# ============================================

# Default validation settings
VALIDATION_MAX_RETRIES="${VALIDATION_MAX_RETRIES:-2}"
VALIDATION_RETRY_DELAY="${VALIDATION_RETRY_DELAY:-3}"
VALIDATION_TIMEOUT="${VALIDATION_TIMEOUT:-600}"  # 10 minutes default

# Validation gates (can be disabled via flags)
VALIDATION_RUN_TESTS="${VALIDATION_RUN_TESTS:-true}"
VALIDATION_RUN_LINT="${VALIDATION_RUN_LINT:-true}"
VALIDATION_RUN_BUILD="${VALIDATION_RUN_BUILD:-false}"
VALIDATION_CHECK_DIFF="${VALIDATION_CHECK_DIFF:-true}"

# ============================================
# VALIDATION RESULT CODES
# ============================================

readonly VALIDATION_SUCCESS=0
readonly VALIDATION_TESTS_FAILED=1
readonly VALIDATION_LINT_FAILED=2
readonly VALIDATION_BUILD_FAILED=3
readonly VALIDATION_DIFF_FAILED=4
readonly VALIDATION_TIMEOUT_EXCEEDED=5
readonly VALIDATION_UNKNOWN_ERROR=99

# ============================================
# UTILITY FUNCTIONS
# ============================================

validation_log_info() {
  echo "[VALIDATION INFO] $*" >&2
}

validation_log_success() {
  echo "[VALIDATION OK] $*" >&2
}

validation_log_warn() {
  echo "[VALIDATION WARN] $*" >&2
}

validation_log_error() {
  echo "[VALIDATION ERROR] $*" >&2
}

# ============================================
# VALIDATION GATE FUNCTIONS
# ============================================

# Cross-platform timeout wrapper
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local command="$@"

  # Check if timeout command is available
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" bash -c "$command"
    return $?
  elif command -v gtimeout >/dev/null 2>&1; then
    # macOS with coreutils installed
    gtimeout "$timeout_seconds" bash -c "$command"
    return $?
  else
    # Fallback: run without timeout (not ideal but functional)
    bash -c "$command"
    return $?
  fi
}

# Run tests with timeout
run_test_gate() {
  local test_command="$1"
  local timeout_seconds="$2"

  if [[ -z "$test_command" ]]; then
    validation_log_info "No test command configured, skipping tests"
    return 0
  fi

  validation_log_info "Running tests: $test_command"

  if run_with_timeout "$timeout_seconds" "$test_command" 2>&1; then
    validation_log_success "Tests passed"
    return 0
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      validation_log_error "Tests timed out after ${timeout_seconds}s"
      return $VALIDATION_TIMEOUT_EXCEEDED
    else
      validation_log_error "Tests failed with exit code $exit_code"
      return $VALIDATION_TESTS_FAILED
    fi
  fi
}

# Run linting with timeout
run_lint_gate() {
  local lint_command="$1"
  local timeout_seconds="$2"

  if [[ -z "$lint_command" ]]; then
    validation_log_info "No lint command configured, skipping linting"
    return 0
  fi

  validation_log_info "Running linting: $lint_command"

  if run_with_timeout "$timeout_seconds" "$lint_command" 2>&1; then
    validation_log_success "Linting passed"
    return 0
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      validation_log_error "Linting timed out after ${timeout_seconds}s"
      return $VALIDATION_TIMEOUT_EXCEEDED
    else
      validation_log_error "Linting failed with exit code $exit_code"
      return $VALIDATION_LINT_FAILED
    fi
  fi
}

# Run build with timeout
run_build_gate() {
  local build_command="$1"
  local timeout_seconds="$2"

  if [[ -z "$build_command" ]]; then
    validation_log_info "No build command configured, skipping build"
    return 0
  fi

  validation_log_info "Running build: $build_command"

  if run_with_timeout "$timeout_seconds" "$build_command" 2>&1; then
    validation_log_success "Build passed"
    return 0
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      validation_log_error "Build timed out after ${timeout_seconds}s"
      return $VALIDATION_TIMEOUT_EXCEEDED
    else
      validation_log_error "Build failed with exit code $exit_code"
      return $VALIDATION_BUILD_FAILED
    fi
  fi
}

# Check if diff is reasonable (not too large, doesn't touch forbidden files)
run_diff_gate() {
  local worktree_path="$1"
  local base_branch="${2:-main}"
  local max_files="${3:-100}"
  local max_lines="${4:-5000}"

  validation_log_info "Checking diff against $base_branch"

  # Get list of changed files
  local changed_files
  changed_files=$(cd "$worktree_path" && git diff --name-only "$base_branch" 2>&1) || {
    validation_log_error "Failed to get diff"
    return $VALIDATION_DIFF_FAILED
  }

  local file_count
  file_count=$(echo "$changed_files" | wc -l | tr -d ' ')

  if [[ $file_count -gt $max_files ]]; then
    validation_log_error "Too many files changed: $file_count (max: $max_files)"
    return $VALIDATION_DIFF_FAILED
  fi

  # Get total lines changed
  local lines_changed
  lines_changed=$(cd "$worktree_path" && git diff --shortstat "$base_branch" 2>&1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{sum+=$1} END {print sum}') || lines_changed=0

  if [[ $lines_changed -gt $max_lines ]]; then
    validation_log_error "Too many lines changed: $lines_changed (max: $max_lines)"
    return $VALIDATION_DIFF_FAILED
  fi

  # Check for forbidden files (if config exists)
  local config_file="$worktree_path/.ralphy/config.yaml"
  if [[ -f "$config_file" ]]; then
    local forbidden_patterns
    forbidden_patterns=$(yq -r '.boundaries.never_touch[]? // empty' "$config_file" 2>/dev/null || echo "")

    if [[ -n "$forbidden_patterns" ]]; then
      while IFS= read -r pattern; do
        if echo "$changed_files" | grep -qE "$pattern"; then
          validation_log_error "Changes touch forbidden files matching: $pattern"
          return $VALIDATION_DIFF_FAILED
        fi
      done <<< "$forbidden_patterns"
    fi
  fi

  validation_log_success "Diff is reasonable: $file_count files, ~$lines_changed lines"
  return 0
}

# ============================================
# MAIN VALIDATION FUNCTION
# ============================================

# Validate a solution in a given worktree
# Args:
#   $1 - worktree_path: Path to the worktree to validate
#   $2 - test_command: Test command to run (optional)
#   $3 - lint_command: Lint command to run (optional)
#   $4 - build_command: Build command to run (optional)
#   $5 - base_branch: Base branch for diff check (optional, default: main)
# Returns:
#   0 - Validation passed
#   1+ - Validation failed (see VALIDATION_* codes above)
validate_solution() {
  local worktree_path="$1"
  local test_command="${2:-}"
  local lint_command="${3:-}"
  local build_command="${4:-}"
  local base_branch="${5:-main}"

  local original_dir
  original_dir=$(pwd)

  validation_log_info "Validating solution in: $worktree_path"

  # Check if worktree exists
  if [[ ! -d "$worktree_path" ]]; then
    validation_log_error "Worktree path does not exist: $worktree_path"
    return $VALIDATION_UNKNOWN_ERROR
  fi

  # Change to worktree directory
  cd "$worktree_path" || {
    validation_log_error "Failed to cd to worktree: $worktree_path"
    cd "$original_dir"
    return $VALIDATION_UNKNOWN_ERROR
  }

  local validation_result=$VALIDATION_SUCCESS

  # Gate 1: Diff Check (run first as it's fast)
  if [[ "$VALIDATION_CHECK_DIFF" == "true" ]]; then
    if ! run_diff_gate "$worktree_path" "$base_branch"; then
      validation_result=$VALIDATION_DIFF_FAILED
      cd "$original_dir"
      return $validation_result
    fi
  fi

  # Gate 2: Linting (fast, catches syntax errors)
  if [[ "$VALIDATION_RUN_LINT" == "true" ]]; then
    if ! run_lint_gate "$lint_command" "$VALIDATION_TIMEOUT"; then
      validation_result=$VALIDATION_LINT_FAILED
      cd "$original_dir"
      return $validation_result
    fi
  fi

  # Gate 3: Tests (slower, but critical)
  if [[ "$VALIDATION_RUN_TESTS" == "true" ]]; then
    if ! run_test_gate "$test_command" "$VALIDATION_TIMEOUT"; then
      validation_result=$VALIDATION_TESTS_FAILED
      cd "$original_dir"
      return $validation_result
    fi
  fi

  # Gate 4: Build (slowest, optional)
  if [[ "$VALIDATION_RUN_BUILD" == "true" ]]; then
    if ! run_build_gate "$build_command" "$VALIDATION_TIMEOUT"; then
      validation_result=$VALIDATION_BUILD_FAILED
      cd "$original_dir"
      return $validation_result
    fi
  fi

  cd "$original_dir"

  validation_log_success "All validation gates passed for: $worktree_path"
  return $VALIDATION_SUCCESS
}

# ============================================
# VALIDATION WITH RETRY
# ============================================

# Validate a solution with retry logic
# Args: Same as validate_solution, plus retry parameters
# Returns: Same as validate_solution
validate_solution_with_retry() {
  local worktree_path="$1"
  local test_command="${2:-}"
  local lint_command="${3:-}"
  local build_command="${4:-}"
  local base_branch="${5:-main}"
  local max_retries="${6:-$VALIDATION_MAX_RETRIES}"
  local retry_delay="${7:-$VALIDATION_RETRY_DELAY}"

  local attempt=0
  local result

  while [[ $attempt -le $max_retries ]]; do
    if [[ $attempt -gt 0 ]]; then
      validation_log_info "Retry attempt $attempt of $max_retries"
      sleep "$retry_delay"
    fi

    validate_solution "$worktree_path" "$test_command" "$lint_command" "$build_command" "$base_branch"
    result=$?

    if [[ $result -eq $VALIDATION_SUCCESS ]]; then
      return $VALIDATION_SUCCESS
    fi

    # Don't retry on timeout or diff failures
    if [[ $result -eq $VALIDATION_TIMEOUT_EXCEEDED ]] || [[ $result -eq $VALIDATION_DIFF_FAILED ]]; then
      validation_log_error "Non-retriable validation failure (code: $result)"
      return $result
    fi

    attempt=$((attempt + 1))
  done

  validation_log_error "Validation failed after $max_retries retries"
  return $result
}

# ============================================
# VALIDATION REPORTING
# ============================================

# Get human-readable validation result message
get_validation_result_message() {
  local result_code="$1"

  case "$result_code" in
    $VALIDATION_SUCCESS)
      echo "Validation passed"
      ;;
    $VALIDATION_TESTS_FAILED)
      echo "Tests failed"
      ;;
    $VALIDATION_LINT_FAILED)
      echo "Linting failed"
      ;;
    $VALIDATION_BUILD_FAILED)
      echo "Build failed"
      ;;
    $VALIDATION_DIFF_FAILED)
      echo "Diff check failed (too large or forbidden files)"
      ;;
    $VALIDATION_TIMEOUT_EXCEEDED)
      echo "Validation timed out"
      ;;
    *)
      echo "Unknown validation error (code: $result_code)"
      ;;
  esac
}

# Generate validation report JSON
generate_validation_report() {
  local worktree_path="$1"
  local result_code="$2"
  local engine_name="${3:-unknown}"
  local task_id="${4:-unknown}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat <<EOF
{
  "task_id": "$task_id",
  "engine": "$engine_name",
  "worktree_path": "$worktree_path",
  "result_code": $result_code,
  "result_message": "$(get_validation_result_message "$result_code")",
  "timestamp": "$timestamp",
  "validation_gates": {
    "diff": $([ "$VALIDATION_CHECK_DIFF" == "true" ] && echo "true" || echo "false"),
    "lint": $([ "$VALIDATION_RUN_LINT" == "true" ] && echo "true" || echo "false"),
    "tests": $([ "$VALIDATION_RUN_TESTS" == "true" ] && echo "true" || echo "false"),
    "build": $([ "$VALIDATION_RUN_BUILD" == "true" ] && echo "true" || echo "false")
  }
}
EOF
}

# ============================================
# LOAD VALIDATION COMMANDS FROM CONFIG
# ============================================

# Load test/lint/build commands from .ralphy/config.yaml
load_validation_commands() {
  local config_file="${1:-.ralphy/config.yaml}"

  if [[ ! -f "$config_file" ]]; then
    validation_log_warn "Config file not found: $config_file"
    return 1
  fi

  # Export commands for use in validation
  export VALIDATION_TEST_CMD
  export VALIDATION_LINT_CMD
  export VALIDATION_BUILD_CMD

  VALIDATION_TEST_CMD=$(yq -r '.commands.test // ""' "$config_file" 2>/dev/null || echo "")
  VALIDATION_LINT_CMD=$(yq -r '.commands.lint // ""' "$config_file" 2>/dev/null || echo "")
  VALIDATION_BUILD_CMD=$(yq -r '.commands.build // ""' "$config_file" 2>/dev/null || echo "")

  validation_log_info "Loaded validation commands from config:"
  [[ -n "$VALIDATION_TEST_CMD" ]] && validation_log_info "  Test:  $VALIDATION_TEST_CMD"
  [[ -n "$VALIDATION_LINT_CMD" ]] && validation_log_info "  Lint:  $VALIDATION_LINT_CMD"
  [[ -n "$VALIDATION_BUILD_CMD" ]] && validation_log_info "  Build: $VALIDATION_BUILD_CMD"

  return 0
}

# ============================================
# VALIDATION GATE EXPORT
# ============================================

# Export validation functions for use in other scripts
export -f validate_solution
export -f validate_solution_with_retry
export -f get_validation_result_message
export -f generate_validation_report
export -f load_validation_commands
export -f run_test_gate
export -f run_lint_gate
export -f run_build_gate
export -f run_diff_gate
