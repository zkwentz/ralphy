#!/bin/bash

# Consensus Mode Implementation
# Runs multiple engines on the same task and compares results

run_consensus_agent() {
  local task_name="$1"
  local engine="$2"
  local agent_num="$3"
  local output_file="$4"
  local status_file="$5"
  local log_file="$6"

  echo "setting up" > "$status_file"

  # Log setup info
  echo "Consensus Agent $agent_num ($engine) starting for task: $task_name" >> "$log_file"
  echo "ORIGINAL_DIR=$ORIGINAL_DIR" >> "$log_file"
  echo "WORKTREE_BASE=$WORKTREE_BASE" >> "$log_file"
  echo "BASE_BRANCH=$BASE_BRANCH" >> "$log_file"

  # Create isolated worktree for this consensus agent
  local worktree_info
  worktree_info=$(create_agent_worktree "$task_name" "$agent_num" 2>>"$log_file")
  local worktree_dir="${worktree_info%%|*}"
  local branch_name="${worktree_info##*|}"

  echo "Worktree dir: $worktree_dir" >> "$log_file"
  echo "Branch name: $branch_name" >> "$log_file"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "failed" > "$status_file"
    echo "ERROR: Worktree directory does not exist: $worktree_dir" >> "$log_file"
    echo "0 0" > "$output_file"
    return 1
  fi

  echo "running" > "$status_file"

  # Copy PRD file to worktree from original directory
  if [[ "$PRD_SOURCE" == "markdown" ]] || [[ "$PRD_SOURCE" == "yaml" ]]; then
    cp "$ORIGINAL_DIR/$PRD_FILE" "$worktree_dir/" 2>/dev/null || true
  fi

  # Ensure .ralphy/ and progress.txt exist in worktree
  mkdir -p "$worktree_dir/$RALPHY_DIR"
  touch "$worktree_dir/$PROGRESS_FILE"

  # Build prompt for this specific task
  local prompt="You are working on a specific task. Focus ONLY on this task:

TASK: $task_name

Instructions:
1. Implement this specific task completely
2. Write tests if appropriate
3. Update $PROGRESS_FILE with what you did
4. Commit your changes with a descriptive message

Do NOT modify PRD.md or mark tasks complete - that will be handled separately.
Focus only on implementing: $task_name"

  # Temp file for AI output
  local tmpfile
  tmpfile=$(mktemp)

  # Run AI agent in the worktree directory with specified engine
  local result=""
  local success=false
  local retry=0

  while [[ $retry -lt ${MAX_RETRIES:-3} ]]; do
    case "$engine" in
      opencode)
        (
          cd "$worktree_dir"
          OPENCODE_PERMISSION='{"*":"allow"}' opencode run \
            --format json \
            "$prompt"
        ) > "$tmpfile" 2>>"$log_file"
        ;;
      cursor)
        (
          cd "$worktree_dir"
          agent --print --force \
            --output-format stream-json \
            "$prompt"
        ) > "$tmpfile" 2>>"$log_file"
        ;;
      qwen)
        (
          cd "$worktree_dir"
          qwen --output-format stream-json \
            --approval-mode yolo \
            -p "$prompt"
        ) > "$tmpfile" 2>>"$log_file"
        ;;
      droid)
        (
          cd "$worktree_dir"
          droid exec --output-format stream-json \
            --auto medium \
            "$prompt"
        ) > "$tmpfile" 2>>"$log_file"
        ;;
      codex)
        (
          cd "$worktree_dir"
          CODEX_LAST_MESSAGE_FILE="$tmpfile.last"
          rm -f "$CODEX_LAST_MESSAGE_FILE"
          codex exec --full-auto \
            --json \
            --output-last-message "$CODEX_LAST_MESSAGE_FILE" \
            "$prompt"
        ) > "$tmpfile" 2>>"$log_file"
        ;;
      claude|*)
        (
          cd "$worktree_dir"
          claude --dangerously-skip-permissions \
            --verbose \
            -p "$prompt" \
            --output-format stream-json
        ) > "$tmpfile" 2>>"$log_file"
        ;;
    esac

    result=$(cat "$tmpfile" 2>/dev/null || echo "")

    if [[ -n "$result" ]]; then
      local error_msg
      if ! error_msg=$(check_for_errors "$result"); then
        ((retry++)) || true
        echo "API error: $error_msg (attempt $retry/${MAX_RETRIES:-3})" >> "$log_file"
        sleep "${RETRY_DELAY:-5}"
        continue
      fi
      success=true
      break
    fi

    ((retry++)) || true
    echo "Retry $retry/${MAX_RETRIES:-3} after empty response" >> "$log_file"
    sleep "${RETRY_DELAY:-5}"
  done

  rm -f "$tmpfile"

  if [[ "$success" == true ]]; then
    # Parse tokens
    local parsed input_tokens output_tokens
    local CODEX_LAST_MESSAGE_FILE="${tmpfile}.last"
    parsed=$(parse_ai_result "$result")
    local token_data
    token_data=$(echo "$parsed" | sed -n '/^---TOKENS---$/,$p' | tail -3)
    input_tokens=$(echo "$token_data" | sed -n '1p')
    output_tokens=$(echo "$token_data" | sed -n '2p')
    [[ "$input_tokens" =~ ^[0-9]+$ ]] || input_tokens=0
    [[ "$output_tokens" =~ ^[0-9]+$ ]] || output_tokens=0
    rm -f "${tmpfile}.last"

    # Ensure at least one commit exists before marking success
    local commit_count
    commit_count=$(git -C "$worktree_dir" rev-list --count "$BASE_BRANCH"..HEAD 2>/dev/null || echo "0")
    [[ "$commit_count" =~ ^[0-9]+$ ]] || commit_count=0
    if [[ "$commit_count" -eq 0 ]]; then
      echo "ERROR: No new commits created; treating task as failed." >> "$log_file"
      echo "failed" > "$status_file"
      echo "0 0" > "$output_file"
      cleanup_agent_worktree "$worktree_dir" "$branch_name" "$log_file"
      return 1
    fi

    # Store solution for comparison
    mkdir -p "$ORIGINAL_DIR/.ralphy/consensus"
    local solution_dir="$ORIGINAL_DIR/.ralphy/consensus/$(echo "$task_name" | tr ' /' '__')"
    mkdir -p "$solution_dir"

    # Save git diff and commit info
    (
      cd "$worktree_dir"
      git diff "$BASE_BRANCH" > "$solution_dir/${engine}_diff.patch"
      git log "$BASE_BRANCH"..HEAD --format="%H|%s|%b" > "$solution_dir/${engine}_commits.txt"
      git diff "$BASE_BRANCH" --stat > "$solution_dir/${engine}_stats.txt"
    ) 2>>"$log_file"

    # Write success output (include branch name for later retrieval)
    echo "done" > "$status_file"
    echo "$input_tokens $output_tokens $branch_name" > "$output_file"

    # Keep worktree for meta-agent comparison (don't cleanup yet)
    echo "$worktree_dir" > "$solution_dir/${engine}_worktree.txt"

    return 0
  else
    echo "failed" > "$status_file"
    echo "0 0" > "$output_file"
    cleanup_agent_worktree "$worktree_dir" "$branch_name" "$log_file"
    return 1
  fi
}

run_consensus_mode() {
  local task_name="$1"
  local engines_str="${2:-claude,cursor}"  # Default to claude and cursor

  # Split engines string into array
  IFS=',' read -ra ENGINES <<< "$engines_str"
  local num_engines="${#ENGINES[@]}"

  if [[ "$num_engines" -lt 2 ]]; then
    log_error "Consensus mode requires at least 2 engines (provided: $num_engines)"
    return 1
  fi

  log_info "Running ${BOLD}consensus mode${RESET} with ${num_engines} engines: ${ENGINES[*]}"

  # Create temp directory for tracking agents
  local temp_dir="$ORIGINAL_DIR/.ralphy/temp"
  mkdir -p "$temp_dir"

  # Arrays to track agent PIDs and files
  local agent_pids=()
  local output_files=()
  local status_files=()
  local log_files=()
  local branch_names=()

  # Launch all consensus agents in parallel
  local agent_num=1
  for engine in "${ENGINES[@]}"; do
    local output_file="$temp_dir/consensus_agent_${agent_num}_output.txt"
    local status_file="$temp_dir/consensus_agent_${agent_num}_status.txt"
    local log_file="$temp_dir/consensus_agent_${agent_num}_log.txt"

    echo "pending" > "$status_file"
    echo "0 0" > "$output_file"
    > "$log_file"

    # Run agent in background
    run_consensus_agent "$task_name" "$engine" "$agent_num" "$output_file" "$status_file" "$log_file" &
    local pid=$!

    agent_pids+=("$pid")
    output_files+=("$output_file")
    status_files+=("$status_file")
    log_files+=("$log_file")

    log_info "  Launched $engine (agent $agent_num, PID $pid)"
    ((agent_num++))
  done

  # Monitor progress with spinner
  log_info "Waiting for all ${num_engines} consensus agents to complete..."
  local all_done=false
  local check_interval=2

  while [[ "$all_done" == false ]]; do
    all_done=true
    local status_summary=""

    for i in "${!status_files[@]}"; do
      local status=$(cat "${status_files[$i]}" 2>/dev/null || echo "pending")
      status_summary+=" [${ENGINES[$i]}:$status]"

      if [[ "$status" != "done" ]] && [[ "$status" != "failed" ]]; then
        all_done=false
      fi
    done

    if [[ "$all_done" == false ]]; then
      echo -ne "\r  Status:$status_summary"
      sleep "$check_interval"
    fi
  done

  echo ""  # New line after status updates

  # Wait for all agents to complete
  for pid in "${agent_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Collect results
  local successful_engines=()
  local failed_engines=()
  local total_input_tokens=0
  local total_output_tokens=0

  for i in "${!status_files[@]}"; do
    local status=$(cat "${status_files[$i]}" 2>/dev/null || echo "failed")
    local engine="${ENGINES[$i]}"

    if [[ "$status" == "done" ]]; then
      successful_engines+=("$engine")
      local output=$(cat "${output_files[$i]}" 2>/dev/null || echo "0 0")
      local input_tokens=$(echo "$output" | awk '{print $1}')
      local output_tokens=$(echo "$output" | awk '{print $2}')
      local branch_name=$(echo "$output" | awk '{print $3}')

      [[ "$input_tokens" =~ ^[0-9]+$ ]] || input_tokens=0
      [[ "$output_tokens" =~ ^[0-9]+$ ]] || output_tokens=0

      total_input_tokens=$((total_input_tokens + input_tokens))
      total_output_tokens=$((total_output_tokens + output_tokens))
      branch_names+=("$branch_name")

      log_info "  ✓ $engine completed successfully (branch: $branch_name)"
    else
      failed_engines+=("$engine")
      log_error "  ✗ $engine failed"
    fi
  done

  # Check if we have at least 2 successful results to compare
  if [[ "${#successful_engines[@]}" -lt 2 ]]; then
    log_error "Consensus mode failed: only ${#successful_engines[@]} engine(s) succeeded (need at least 2)"
    return 1
  fi

  log_info "Consensus agents completed: ${#successful_engines[@]} succeeded, ${#failed_engines[@]} failed"
  log_info "Total tokens: input=$total_input_tokens, output=$total_output_tokens"

  # Compare solutions using meta-agent
  log_info "Comparing solutions from: ${successful_engines[*]}"

  local solution_dir="$ORIGINAL_DIR/.ralphy/consensus/$(echo "$task_name" | tr ' /' '__')"
  local meta_result
  meta_result=$(run_meta_agent_comparison "$task_name" "$solution_dir" "${successful_engines[@]}")

  local chosen_engine=$(echo "$meta_result" | grep "^CHOSEN:" | cut -d':' -f2 | xargs)
  local reasoning=$(echo "$meta_result" | grep -A100 "^REASONING:" | tail -n +2)

  if [[ -z "$chosen_engine" ]]; then
    log_error "Meta-agent failed to choose a solution"
    return 1
  fi

  log_info "Meta-agent selected: ${BOLD}$chosen_engine${RESET}"
  log_info "Reasoning: $reasoning"

  # Apply the chosen solution
  local chosen_branch=""
  for i in "${!successful_engines[@]}"; do
    if [[ "${successful_engines[$i]}" == "$chosen_engine" ]]; then
      chosen_branch="${branch_names[$i]}"
      break
    fi
  done

  if [[ -z "$chosen_branch" ]]; then
    log_error "Could not find branch for chosen engine: $chosen_engine"
    return 1
  fi

  log_info "Applying solution from branch: $chosen_branch"

  # Merge chosen branch into current branch
  (
    cd "$ORIGINAL_DIR"
    git merge "$chosen_branch" --no-edit -m "Consensus mode: Apply solution from $chosen_engine

Selected by meta-agent from ${#successful_engines[@]} solutions.

Reasoning: $reasoning"
  ) || {
    log_error "Failed to merge chosen solution"
    return 1
  }

  # Cleanup all consensus worktrees
  for engine in "${successful_engines[@]}"; do
    local worktree_file="$solution_dir/${engine}_worktree.txt"
    if [[ -f "$worktree_file" ]]; then
      local worktree_path=$(cat "$worktree_file")
      if [[ -d "$worktree_path" ]]; then
        local branch_to_cleanup=""
        for i in "${!successful_engines[@]}"; do
          if [[ "${successful_engines[$i]}" == "$engine" ]]; then
            branch_to_cleanup="${branch_names[$i]}"
            break
          fi
        done
        if [[ -n "$branch_to_cleanup" ]]; then
          cleanup_agent_worktree "$worktree_path" "$branch_to_cleanup" "${log_files[$i]}"
        fi
      fi
    fi
  done

  log_info "Consensus mode completed successfully"
  return 0
}
