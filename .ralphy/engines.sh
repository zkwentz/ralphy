#!/usr/bin/env bash

# ============================================
# Engine Abstraction Layer
# Provides common interface for all AI engines
# ============================================

# Check if an engine is available/installed
validate_engine_availability() {
  local engine=$1

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
      return 1
      ;;
  esac
}

# Get list of available engines
get_available_engines() {
  local engines=("claude" "opencode" "cursor" "codex" "qwen" "droid")
  local available=()

  for engine in "${engines[@]}"; do
    if validate_engine_availability "$engine"; then
      available+=("$engine")
    fi
  done

  echo "${available[@]}"
}

# Execute a task with a specific engine
# Returns: 0 on success, non-zero on failure
execute_with_engine() {
  local engine=$1
  local task_description=$2
  local worktree_path=$3
  local output_file=$4

  if ! validate_engine_availability "$engine"; then
    echo "Engine $engine not available" >&2
    return 1
  fi

  cd "$worktree_path" || return 1

  case "$engine" in
    claude)
      claude --dangerously-skip-permissions \
        --output-format stream-json \
        -p "$task_description" > "$output_file" 2>&1
      ;;
    opencode)
      opencode full-auto "$task_description" > "$output_file" 2>&1
      ;;
    cursor)
      agent --force "$task_description" > "$output_file" 2>&1
      ;;
    codex)
      codex "$task_description" > "$output_file" 2>&1
      ;;
    qwen)
      qwen --approval-mode yolo "$task_description" > "$output_file" 2>&1
      ;;
    droid)
      droid exec --auto medium "$task_description" > "$output_file" 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}
