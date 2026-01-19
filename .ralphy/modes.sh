#!/usr/bin/env bash

# ============================================
# Multi-Engine Execution Modes
# Implements: consensus, specialization, race
# ============================================

# Source the engines module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/engines.sh"

# Race mode: run multiple engines in parallel, first successful completion wins
# If all engines fail, handle gracefully with fallback strategies
run_race_mode() {
  local task_description=$1
  local task_id=$2
  shift 2
  local engines=("$@")

  if [[ ${#engines[@]} -eq 0 ]]; then
    log_error "Race mode requires at least one engine"
    return 1
  fi

  log_info "Starting race mode with engines: ${engines[*]}"

  # Create race directory for this task
  local race_dir=".ralphy/race/$task_id"
  mkdir -p "$race_dir"

  # Track PIDs and engine statuses using parallel arrays (bash 3 compatible)
  local engine_pids=()
  local engine_names=()
  local engine_status=()
  local engine_worktrees=()
  local winner=""
  local all_failed=true

  # Start all engines in parallel
  local idx=0
  for engine in "${engines[@]}"; do
    if ! validate_engine_availability "$engine"; then
      log_warn "Engine $engine not available, skipping"
      continue
    fi

    # Create isolated worktree for this engine
    local worktree_path="$race_dir/$engine"
    local branch_name="ralphy/race-$task_id-$engine"
    local output_file="$race_dir/$engine-output.log"

    # Create git worktree
    if ! git worktree add -b "$branch_name" "$worktree_path" HEAD 2>/dev/null; then
      log_warn "Failed to create worktree for $engine, trying with existing branch"
      git worktree add "$worktree_path" "$branch_name" 2>/dev/null || {
        log_error "Failed to create worktree for $engine"
        continue
      }
    fi

    # Execute engine in background
    log_debug "Starting $engine in background (worktree: $worktree_path)"
    (
      execute_with_engine "$engine" "$task_description" "$worktree_path" "$output_file"
      exit_code=$?
      echo "$exit_code" > "$race_dir/$engine-exit-code.txt"
      exit $exit_code
    ) &

    # Store in parallel arrays
    engine_names[$idx]="$engine"
    engine_pids[$idx]=$!
    engine_status[$idx]="running"
    engine_worktrees[$idx]="$worktree_path"
    idx=$((idx + 1))
  done

  if [[ ${#engine_pids[@]} -eq 0 ]]; then
    log_error "No engines could be started"
    cleanup_race_worktrees "$race_dir"
    return 1
  fi

  # Monitor engines for completion
  local timeout=${RACE_TIMEOUT:-300}  # 5 minutes default
  local start_time=$(date +%s)

  log_info "Waiting for first successful completion (timeout: ${timeout}s)..."

  while [[ -z "$winner" ]]; do
    # Check timeout
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    if [[ $elapsed -ge $timeout ]]; then
      log_warn "Race mode timeout reached (${timeout}s)"
      break
    fi

    # Check each running engine
    for i in "${!engine_pids[@]}"; do
      local engine="${engine_names[$i]}"
      local pid="${engine_pids[$i]}"
      local status="${engine_status[$i]}"

      if [[ "$status" != "running" ]]; then
        continue
      fi

      # Check if process is still running
      if ! kill -0 "$pid" 2>/dev/null; then
        # Process finished, check exit code
        local exit_code_file="$race_dir/$engine-exit-code.txt"
        if [[ -f "$exit_code_file" ]]; then
          local exit_code=$(cat "$exit_code_file")

          if [[ $exit_code -eq 0 ]]; then
            # Engine succeeded! Validate the solution
            if validate_race_solution "${engine_worktrees[$i]}" "$engine"; then
              winner="$engine"
              all_failed=false
              log_success "🏆 Engine $engine won the race!"

              # Kill other engines
              for j in "${!engine_pids[@]}"; do
                if [[ $j -ne $i ]] && [[ "${engine_status[$j]}" == "running" ]]; then
                  local other_pid="${engine_pids[$j]}"
                  local other_engine="${engine_names[$j]}"
                  kill "$other_pid" 2>/dev/null || true
                  engine_status[$j]="killed"
                  log_debug "Stopped $other_engine (PID: $other_pid)"
                fi
              done

              break
            else
              log_warn "Engine $engine completed but failed validation"
              engine_status[$i]="failed_validation"
            fi
          else
            log_warn "Engine $engine failed with exit code: $exit_code"
            engine_status[$i]="failed"
          fi
        else
          engine_status[$i]="failed"
        fi
      fi
    done

    # Check if all engines have finished
    local all_done=true
    for i in "${!engine_status[@]}"; do
      if [[ "${engine_status[$i]}" == "running" ]]; then
        all_done=false
        break
      fi
    done

    if [[ "$all_done" == true ]] && [[ -z "$winner" ]]; then
      log_warn "All engines have finished but none succeeded"
      break
    fi

    sleep 1
  done

  # Handle results
  if [[ -n "$winner" ]]; then
    # Find winner's worktree
    local winner_worktree=""
    for i in "${!engine_names[@]}"; do
      if [[ "${engine_names[$i]}" == "$winner" ]]; then
        winner_worktree="${engine_worktrees[$i]}"
        break
      fi
    done

    # Apply winning solution
    log_info "Applying solution from $winner"
    apply_race_winner "$winner_worktree" "$task_id"

    # Record metrics
    echo "$winner" > "$race_dir/winner.txt"
    record_race_result "$task_id" "$winner" "success" "${engines[@]}"

    cleanup_race_worktrees "$race_dir"
    return 0
  else
    # ALL ENGINES FAILED - Handle gracefully
    log_error "Race mode failure: All engines failed to complete the task successfully"
    handle_all_race_failures "$task_id" "$task_description" "$race_dir" "${engines[@]}"

    cleanup_race_worktrees "$race_dir"
    return 1
  fi
}

# Validate a race solution (run tests, lint, etc.)
validate_race_solution() {
  local worktree_path=$1
  local engine=$2

  log_debug "Validating solution from $engine"

  cd "$worktree_path" || return 1

  # Check if there are any changes
  if ! git diff --quiet HEAD; then
    log_debug "Solution has changes, proceeding with validation"
  else
    log_warn "No changes detected in $engine solution"
    return 1
  fi

  # Run validation commands if configured
  if [[ -f ".ralphy/config.yaml" ]]; then
    # Skip validation if RACE_SKIP_VALIDATION is set
    if [[ "${RACE_SKIP_VALIDATION:-false}" == "true" ]]; then
      log_debug "Skipping validation (RACE_SKIP_VALIDATION=true)"
      return 0
    fi

    # Run tests if configured
    local test_cmd
    test_cmd=$(yq eval '.commands.test // ""' .ralphy/config.yaml 2>/dev/null || echo "")
    if [[ -n "$test_cmd" ]] && [[ "${SKIP_TESTS:-false}" != "true" ]]; then
      log_debug "Running tests: $test_cmd"
      if ! eval "$test_cmd" &>/dev/null; then
        log_warn "Tests failed for $engine solution"
        return 1
      fi
    fi

    # Run lint if configured
    local lint_cmd
    lint_cmd=$(yq eval '.commands.lint // ""' .ralphy/config.yaml 2>/dev/null || echo "")
    if [[ -n "$lint_cmd" ]] && [[ "${SKIP_LINT:-false}" != "true" ]]; then
      log_debug "Running lint: $lint_cmd"
      if ! eval "$lint_cmd" &>/dev/null; then
        log_warn "Lint failed for $engine solution"
        return 1
      fi
    fi
  fi

  return 0
}

# Apply the winning solution from race mode
apply_race_winner() {
  local winner_worktree=$1
  local task_id=$2

  cd "$winner_worktree" || return 1

  # Get the changes
  local changes
  changes=$(git diff HEAD)

  if [[ -z "$changes" ]]; then
    log_warn "No changes to apply from winner"
    return 1
  fi

  # Apply changes to original working directory
  cd "$ORIGINAL_DIR" || return 1

  # Create patch and apply
  echo "$changes" | git apply -

  log_success "Applied changes from race winner"
  return 0
}

# Handle scenario where all engines fail in race mode
handle_all_race_failures() {
  local task_id=$1
  local task_description=$2
  local race_dir=$3
  shift 3
  local engines=("$@")

  log_error "═══════════════════════════════════════════════════════════"
  log_error "RACE MODE: ALL ENGINES FAILED"
  log_error "═══════════════════════════════════════════════════════════"
  log_error "Task: $task_description"
  log_error "Engines attempted: ${engines[*]}"
  log_error ""

  # Collect failure information
  local failure_summary="$race_dir/failure-summary.txt"
  {
    echo "Race Mode Failure Report"
    echo "========================"
    echo "Task ID: $task_id"
    echo "Task: $task_description"
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "Engines Attempted:"
    for engine in "${engines[@]}"; do
      echo "  - $engine"
    done
    echo ""
    echo "Failure Details:"
    echo ""
  } > "$failure_summary"

  # Collect failure details from each engine
  for engine in "${engines[@]}"; do
    local output_file="$race_dir/$engine-output.log"
    local exit_code_file="$race_dir/$engine-exit-code.txt"

    {
      echo "Engine: $engine"
      echo "---------------"

      if [[ -f "$exit_code_file" ]]; then
        echo "Exit Code: $(cat "$exit_code_file")"
      else
        echo "Exit Code: Unknown (process may have been killed)"
      fi

      if [[ -f "$output_file" ]]; then
        echo "Last 20 lines of output:"
        tail -n 20 "$output_file"
      else
        echo "No output file found"
      fi

      echo ""
      echo ""
    } >> "$failure_summary"
  done

  # Display summary
  log_error "Failure summary saved to: $failure_summary"

  # Record metrics
  record_race_result "$task_id" "none" "all_failed" "${engines[@]}"

  # Fallback strategies
  log_info ""
  log_info "Fallback Strategies:"
  log_info "-------------------"

  # Strategy 1: Retry with different engines
  local all_engines
  all_engines=$(get_available_engines)
  local unused_engines=()

  for available_engine in $all_engines; do
    local is_used=false
    for used_engine in "${engines[@]}"; do
      if [[ "$available_engine" == "$used_engine" ]]; then
        is_used=true
        break
      fi
    done

    if [[ "$is_used" == false ]]; then
      unused_engines+=("$available_engine")
    fi
  done

  if [[ ${#unused_engines[@]} -gt 0 ]]; then
    log_info "1. Retry with different engines: ${unused_engines[*]}"
    echo "   Command: RACE_ENGINES=\"${unused_engines[*]}\" ./ralphy.sh --mode race \"$task_description\""
  else
    log_info "1. All available engines were already attempted"
  fi

  # Strategy 2: Switch to consensus mode
  log_info "2. Switch to consensus mode for meta-agent review"
  echo "   Command: ./ralphy.sh --mode consensus --consensus-engines \"${engines[*]}\" \"$task_description\""

  # Strategy 3: Manual intervention
  log_info "3. Manual intervention required"
  echo "   Review failure logs at: $failure_summary"
  echo "   Review engine outputs at: $race_dir/*-output.log"

  # Strategy 4: Simplify task
  log_info "4. Consider breaking the task into smaller subtasks"

  log_info ""
  log_error "Race mode failed. Please review the failure summary and choose a fallback strategy."

  return 1
}

# Cleanup race worktrees
cleanup_race_worktrees() {
  local race_dir=$1

  log_debug "Cleaning up race worktrees"

  # Find and remove all worktrees in the race directory
  if [[ -d "$race_dir" ]]; then
    for worktree in "$race_dir"/*; do
      if [[ -d "$worktree/.git" ]] || [[ -f "$worktree/.git" ]]; then
        log_debug "Removing worktree: $worktree"
        git worktree remove "$worktree" --force 2>/dev/null || true
      fi
    done
  fi

  # Clean up branches
  local branches
  branches=$(git branch --list "ralphy/race-*" 2>/dev/null || true)
  if [[ -n "$branches" ]]; then
    echo "$branches" | while read -r branch; do
      local branch_name
      branch_name=$(echo "$branch" | sed 's/^[* ]*//')
      log_debug "Removing branch: $branch_name"
      git branch -D "$branch_name" 2>/dev/null || true
    done
  fi
}

# Record race mode result for metrics
record_race_result() {
  local task_id=$1
  local winner=$2
  local status=$3
  shift 3
  local engines=("$@")

  local metrics_file=".ralphy/metrics.json"

  # Initialize metrics file if it doesn't exist
  if [[ ! -f "$metrics_file" ]]; then
    echo '{"race_history": []}' > "$metrics_file"
  fi

  # Create race entry
  local race_entry
  race_entry=$(jq -n \
    --arg task_id "$task_id" \
    --arg winner "$winner" \
    --arg status "$status" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson engines "$(printf '%s\n' "${engines[@]}" | jq -R . | jq -s .)" \
    '{
      task_id: $task_id,
      engines: $engines,
      winner: $winner,
      status: $status,
      timestamp: $timestamp
    }')

  # Append to race history
  local updated_metrics
  updated_metrics=$(jq --argjson entry "$race_entry" '.race_history += [$entry]' "$metrics_file")
  echo "$updated_metrics" > "$metrics_file"

  log_debug "Recorded race result: $status (winner: $winner)"
}
