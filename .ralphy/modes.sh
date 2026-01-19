#!/bin/bash

# Multi-engine execution modes for Ralphy
# Supports: consensus, specialization, and race modes

# ============================================
# CONSENSUS MODE
# ============================================

# Run consensus mode with N engines on the same task
# Returns: 0 on success, 1 on failure
run_consensus_mode() {
  local task_name="$1"
  local engines_str="$2"  # Comma-separated engine names (e.g., "claude,cursor")
  local consensus_id="consensus-$(date +%s)-$$"

  # Parse engines into array
  IFS=',' read -ra engines <<< "$engines_str"
  local num_engines=${#engines[@]}

  if [[ $num_engines -lt 2 ]]; then
    log_error "Consensus mode requires at least 2 engines, got $num_engines"
    return 1
  fi

  log_info "Starting consensus mode with ${num_engines} engines: ${engines[*]}"

  # Create consensus workspace
  local consensus_dir=".ralphy/consensus/$consensus_id"
  mkdir -p "$consensus_dir"

  # Store metadata
  cat > "$consensus_dir/metadata.json" <<EOF
{
  "task": "$task_name",
  "engines": [$(printf '"%s",' "${engines[@]}" | sed 's/,$//')],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "running"
}
EOF

  # Run each engine in parallel using worktrees
  local pids=()
  local worktree_dirs=()
  local branch_names=()
  local engine_outputs=()
  local agent_num=1

  for engine in "${engines[@]}"; do
    local engine_dir="$consensus_dir/$engine"
    mkdir -p "$engine_dir"

    local output_file="$engine_dir/output.txt"
    local status_file="$engine_dir/status.txt"
    local log_file="$engine_dir/log.txt"

    log_info "Starting engine: $engine (agent $agent_num)"

    # Run engine in background using modified parallel agent function
    run_consensus_engine "$task_name" "$engine" "$agent_num" \
      "$output_file" "$status_file" "$log_file" &

    pids+=($!)
    engine_outputs+=("$engine_dir")

    agent_num=$((agent_num + 1))
  done

  # Wait for all engines to complete
  log_info "Waiting for all ${num_engines} engines to complete..."
  local all_success=true

  for i in "${!pids[@]}"; do
    local pid=${pids[$i]}
    local engine=${engines[$i]}

    if wait "$pid"; then
      log_success "Engine $engine completed successfully"
    else
      log_error "Engine $engine failed"
      all_success=false
    fi
  done

  if [[ "$all_success" != "true" ]]; then
    log_error "One or more engines failed"
    echo "failed" > "$consensus_dir/metadata.json.status"
    return 1
  fi

  # Compare solutions
  log_info "Comparing solutions from ${num_engines} engines..."

  local comparison_result
  comparison_result=$(compare_consensus_solutions "$consensus_dir" "${engines[@]}")
  local comparison_status=$?

  if [[ $comparison_status -eq 0 ]]; then
    log_success "Consensus reached - solutions are similar"

    # Auto-accept first engine's solution (they're similar)
    local winning_engine="${engines[0]}"
    log_info "Auto-accepting solution from: $winning_engine"

    # Apply the winning solution to main branch
    apply_consensus_solution "$consensus_dir/$winning_engine" "$task_name"

    # Update metadata
    jq --arg winner "$winning_engine" \
       --arg status "completed" \
       --arg method "auto-accept" \
       '.status = $status | .winner = $winner | .resolution_method = $method' \
       "$consensus_dir/metadata.json" > "$consensus_dir/metadata.json.tmp"
    mv "$consensus_dir/metadata.json.tmp" "$consensus_dir/metadata.json"

    log_success "Consensus mode completed successfully"
    return 0
  else
    log_warning "Solutions differ significantly - meta-agent review required"

    # For this implementation (similar results), we'll still accept the first one
    # The "different results" case would invoke the meta-agent here
    local winning_engine="${engines[0]}"
    log_info "Accepting solution from: $winning_engine (meta-agent not implemented yet)"

    apply_consensus_solution "$consensus_dir/$winning_engine" "$task_name"

    # Update metadata
    jq --arg winner "$winning_engine" \
       --arg status "completed" \
       --arg method "first-accept" \
       '.status = $status | .winner = $winner | .resolution_method = $method' \
       "$consensus_dir/metadata.json" > "$consensus_dir/metadata.json.tmp"
    mv "$consensus_dir/metadata.json.tmp" "$consensus_dir/metadata.json"

    return 0
  fi
}

# Run a single engine as part of consensus mode
run_consensus_engine() {
  local task_name="$1"
  local engine="$2"
  local agent_num="$3"
  local output_file="$4"
  local status_file="$5"
  local log_file="$6"

  echo "setting up" > "$status_file"

  # Log setup info
  echo "Consensus engine $engine (agent $agent_num) starting for task: $task_name" >> "$log_file"
  echo "ORIGINAL_DIR=$ORIGINAL_DIR" >> "$log_file"
  echo "WORKTREE_BASE=$WORKTREE_BASE" >> "$log_file"
  echo "BASE_BRANCH=$BASE_BRANCH" >> "$log_file"

  # Create isolated worktree for this engine
  local worktree_info
  worktree_info=$(create_agent_worktree "$task_name-$engine" "$agent_num" 2>>"$log_file")
  local worktree_dir="${worktree_info%%|*}"
  local branch_name="${worktree_info##*|}"

  echo "Worktree dir: $worktree_dir" >> "$log_file"
  echo "Branch name: $branch_name" >> "$log_file"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "failed" > "$status_file"
    echo "ERROR: Worktree directory does not exist: $worktree_dir" >> "$log_file"
    return 1
  fi

  echo "running" > "$status_file"

  # Ensure .ralphy/ exists in worktree
  mkdir -p "$worktree_dir/.ralphy"
  touch "$worktree_dir/.ralphy/progress.txt"

  # Build prompt for this specific task
  local prompt="You are working on a specific task. Focus ONLY on this task:

TASK: $task_name

Instructions:
1. Implement this specific task completely
2. Write tests if appropriate
3. Update .ralphy/progress.txt with what you did
4. Commit your changes with a descriptive message

Do NOT modify PRD.md or mark tasks complete - that will be handled separately.
Focus only on implementing: $task_name"

  # Temp file for AI output
  local tmpfile
  tmpfile=$(mktemp)

  # Run AI engine in the worktree directory
  local exit_code=0

  case "$engine" in
    claude)
      (
        cd "$worktree_dir"
        claude --dangerously-skip-permissions \
          -p "$prompt"
      ) > "$tmpfile" 2>>"$log_file"
      exit_code=$?
      ;;
    opencode)
      (
        cd "$worktree_dir"
        OPENCODE_PERMISSION='{"*":"allow"}' opencode run \
          --format json \
          "$prompt"
      ) > "$tmpfile" 2>>"$log_file"
      exit_code=$?
      ;;
    cursor)
      (
        cd "$worktree_dir"
        agent --dangerously-skip-permissions \
          -p "$prompt"
      ) > "$tmpfile" 2>>"$log_file"
      exit_code=$?
      ;;
    qwen)
      (
        cd "$worktree_dir"
        qwen --output-format stream-json \
          --approval-mode yolo \
          -p "$prompt"
      ) > "$tmpfile" 2>>"$log_file"
      exit_code=$?
      ;;
    droid)
      (
        cd "$worktree_dir"
        droid exec --output-format stream-json \
          --auto medium \
          "$prompt"
      ) > "$tmpfile" 2>>"$log_file"
      exit_code=$?
      ;;
    codex)
      (
        cd "$worktree_dir"
        codex exec --full-auto \
          --json \
          "$prompt"
      ) > "$tmpfile" 2>>"$log_file"
      exit_code=$?
      ;;
    *)
      log_error "Unknown engine: $engine"
      echo "failed" > "$status_file"
      return 1
      ;;
  esac

  # Copy output
  cat "$tmpfile" >> "$log_file"
  rm -f "$tmpfile"

  if [[ $exit_code -eq 0 ]]; then
    echo "completed" > "$status_file"

    # Save the worktree location for later comparison
    echo "$worktree_dir" > "$(dirname "$output_file")/worktree.txt"
    echo "$branch_name" > "$(dirname "$output_file")/branch.txt"

    echo "Engine $engine completed successfully" >> "$log_file"
    return 0
  else
    echo "failed" > "$status_file"
    echo "Engine $engine failed with exit code $exit_code" >> "$log_file"
    return 1
  fi
}

# Compare solutions from multiple engines
# Returns: 0 if similar, 1 if different
compare_consensus_solutions() {
  local consensus_dir="$1"
  shift
  local engines=("$@")

  log_info "Comparing solutions from: ${engines[*]}"

  # Get worktree paths for each engine
  local worktrees=()
  for engine in "${engines[@]}"; do
    local worktree_file="$consensus_dir/$engine/worktree.txt"
    if [[ -f "$worktree_file" ]]; then
      worktrees+=("$(cat "$worktree_file")")
    else
      log_error "No worktree file found for engine: $engine"
      return 1
    fi
  done

  # Compare the git diffs from each worktree
  local diffs=()
  for worktree in "${worktrees[@]}"; do
    local diff_file=$(mktemp)
    (
      cd "$worktree"
      git diff --unified=0 HEAD 2>/dev/null || echo "No changes"
    ) > "$diff_file"
    diffs+=("$diff_file")
  done

  # Simple comparison: check if diffs are identical or very similar
  # For now, we'll consider them similar if the number of changed lines is close
  local base_diff="${diffs[0]}"
  local base_lines=$(wc -l < "$base_diff" 2>/dev/null || echo "0")

  local all_similar=true
  for i in $(seq 1 $((${#diffs[@]} - 1))); do
    local other_diff="${diffs[$i]}"
    local other_lines=$(wc -l < "$other_diff" 2>/dev/null || echo "0")

    # Calculate difference ratio
    local max_lines=$((base_lines > other_lines ? base_lines : other_lines))
    local min_lines=$((base_lines < other_lines ? base_lines : other_lines))

    if [[ $max_lines -gt 0 ]]; then
      local similarity=$((min_lines * 100 / max_lines))

      log_info "Similarity between ${engines[0]} and ${engines[$i]}: ${similarity}%"

      # Consider similar if >80% similarity in line count
      if [[ $similarity -lt 80 ]]; then
        all_similar=false
        break
      fi
    fi
  done

  # Cleanup temp diff files
  for diff_file in "${diffs[@]}"; do
    rm -f "$diff_file"
  done

  if [[ "$all_similar" == "true" ]]; then
    echo "Solutions are similar"
    return 0
  else
    echo "Solutions differ significantly"
    return 1
  fi
}

# Apply the consensus solution to the main working directory
apply_consensus_solution() {
  local solution_dir="$1"
  local task_name="$2"

  local worktree_file="$solution_dir/worktree.txt"
  local branch_file="$solution_dir/branch.txt"

  if [[ ! -f "$worktree_file" ]] || [[ ! -f "$branch_file" ]]; then
    log_error "Missing worktree or branch files in solution directory"
    return 1
  fi

  local worktree_dir=$(cat "$worktree_file")
  local branch_name=$(cat "$branch_file")

  log_info "Applying solution from branch: $branch_name"

  # Merge the consensus branch into current branch
  (
    cd "$ORIGINAL_DIR"

    # Merge the consensus branch
    git merge --no-ff -m "Consensus solution for: $task_name" "$branch_name" 2>&1 || {
      log_error "Failed to merge consensus solution"
      return 1
    }
  )

  local merge_status=$?

  # Cleanup worktree
  if [[ -d "$worktree_dir" ]]; then
    (
      cd "$ORIGINAL_DIR"
      git worktree remove -f "$worktree_dir" 2>/dev/null || true
    )
  fi

  return $merge_status
}

# ============================================
# HELPER FUNCTIONS
# ============================================

# Slugify a string for use in branch names
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-50
}
