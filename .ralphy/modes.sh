#!/usr/bin/env bash

# ============================================
# Ralphy - Multi-Engine Execution Modes
# ============================================
# This module implements different execution modes for multi-engine AI task execution:
# - Specialization Mode: Routes tasks to specialized engines based on pattern matching
# - Consensus Mode: Runs multiple engines and uses meta-agent to select best solution (future)
# - Race Mode: Runs multiple engines in parallel, first success wins (future)
# ============================================

# Relaxed error handling for library mode
set -eo pipefail

# ============================================
# SPECIALIZATION MODE
# ============================================

# Match a task description against specialization rules from config
# Returns: matched engine name or empty string
match_specialization_rule() {
  local task_desc="$1"
  local config_file="${2:-$CONFIG_FILE}"

  # Check if config file exists and has specialization_rules
  if [[ ! -f "$config_file" ]]; then
    log_debug "Config file not found, skipping specialization matching"
    return 0
  fi

  # Check if yq is available for YAML parsing
  if ! command -v yq &>/dev/null; then
    log_debug "yq not available, skipping specialization matching"
    return 0
  fi

  # Check if specialization_rules section exists
  if ! yq eval '.engines.specialization_rules' "$config_file" &>/dev/null; then
    log_debug "No specialization_rules in config"
    return 0
  fi

  # Get number of rules
  local rules_count
  rules_count=$(yq eval '.engines.specialization_rules | length' "$config_file" 2>/dev/null || echo "0")

  if [[ "$rules_count" -eq 0 ]]; then
    log_debug "No specialization rules defined"
    return 0
  fi

  # Iterate through rules and find first match
  local idx=0
  while [[ $idx -lt $rules_count ]]; do
    local pattern
    local engines
    local mode
    local description

    pattern=$(yq eval ".engines.specialization_rules[$idx].pattern" "$config_file" 2>/dev/null || echo "")
    engines=$(yq eval ".engines.specialization_rules[$idx].engines[0]" "$config_file" 2>/dev/null || echo "")
    mode=$(yq eval ".engines.specialization_rules[$idx].mode" "$config_file" 2>/dev/null || echo "")
    description=$(yq eval ".engines.specialization_rules[$idx].description" "$config_file" 2>/dev/null || echo "")

    # Skip if pattern is empty or null
    if [[ -z "$pattern" ]] || [[ "$pattern" == "null" ]]; then
      ((idx++)) || true
      continue
    fi

    # Check if task description matches pattern (case-insensitive)
    if echo "$task_desc" | grep -qiE "$pattern"; then
      log_debug "Matched specialization rule: $description"
      log_debug "Pattern: $pattern -> Engine: $engines"

      # Return the matched engine (first one if multiple)
      if [[ -n "$engines" ]] && [[ "$engines" != "null" ]]; then
        echo "$engines"
        return 0
      fi
    fi

    ((idx++)) || true
  done

  # No match found
  log_debug "No specialization rule matched for task: ${task_desc:0:50}..."
  return 0
}

# Get the best engine for a task using specialization mode
# Returns: engine name or the default engine
get_engine_for_task() {
  local task_desc="$1"
  local default_engine="${2:-$AI_ENGINE}"
  local config_file="${3:-$CONFIG_FILE}"

  # Try to match specialization rule
  local matched_engine
  matched_engine=$(match_specialization_rule "$task_desc" "$config_file")

  # If match found and engine is available, use it
  if [[ -n "$matched_engine" ]] && [[ "$matched_engine" != "null" ]]; then
    # Validate engine is available
    if validate_engine_available "$matched_engine"; then
      echo "$matched_engine"
      return 0
    else
      log_warn "Matched engine '$matched_engine' not available, using default"
    fi
  fi

  # Fall back to default engine
  echo "$default_engine"
  return 0
}

# Validate if an engine is available/installed
validate_engine_available() {
  local engine="$1"

  case "$engine" in
    claude)
      command -v claude &>/dev/null
      ;;
    opencode)
      command -v opencode &>/dev/null
      ;;
    cursor)
      command -v agent &>/dev/null
      ;;
    codex)
      command -v codex &>/dev/null
      ;;
    qwen)
      command -v qwen &>/dev/null
      ;;
    droid)
      command -v droid &>/dev/null
      ;;
    *)
      log_warn "Unknown engine: $engine"
      return 1
      ;;
  esac
}

# Run a task with specialization mode
# This determines the best engine for the task and sets AI_ENGINE accordingly
run_specialization_mode() {
  local task_desc="$1"
  local config_file="${2:-$CONFIG_FILE}"

  # Save original engine
  local original_engine="$AI_ENGINE"

  # Get specialized engine for this task
  local specialized_engine
  specialized_engine=$(get_engine_for_task "$task_desc" "$AI_ENGINE" "$config_file")

  # Update AI_ENGINE if different
  if [[ "$specialized_engine" != "$AI_ENGINE" ]]; then
    log_info "Specialization: Using $specialized_engine for this task (default: $AI_ENGINE)"
    AI_ENGINE="$specialized_engine"
  fi

  # Return success - caller should use the updated AI_ENGINE
  return 0
}

# ============================================
# CONSENSUS MODE (Future Implementation)
# ============================================

run_consensus_mode() {
  log_error "Consensus mode not yet implemented"
  return 1
}

# ============================================
# RACE MODE (Future Implementation)
# ============================================

run_race_mode() {
  log_error "Race mode not yet implemented"
  return 1
}

# ============================================
# MIXED MODE (Future Implementation)
# ============================================

run_mixed_mode() {
  log_error "Mixed mode not yet implemented"
  return 1
}

# ============================================
# HELPER FUNCTIONS
# ============================================

# Get default mode from config
get_default_mode() {
  local config_file="${1:-$CONFIG_FILE}"

  if [[ ! -f "$config_file" ]] || ! command -v yq &>/dev/null; then
    echo "single"
    return 0
  fi

  local mode
  mode=$(yq eval '.engines.default_mode' "$config_file" 2>/dev/null || echo "single")

  if [[ -z "$mode" ]] || [[ "$mode" == "null" ]]; then
    echo "single"
  else
    echo "$mode"
  fi
}

# Log debug message (only if VERBOSE is true)
log_debug() {
  if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo "${DIM}[DEBUG]${RESET} $*" >&2
  fi
}

# Log warning message
log_warn() {
  echo "${YELLOW}[WARN]${RESET} $*" >&2
}

# Log error message
log_error() {
  echo "${RED}[ERROR]${RESET} $*" >&2
}

# Export functions for use in main script
export -f match_specialization_rule
export -f get_engine_for_task
export -f validate_engine_available
export -f run_specialization_mode
export -f run_consensus_mode
export -f run_race_mode
export -f run_mixed_mode
export -f get_default_mode
export -f log_debug
