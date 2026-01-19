#!/bin/bash

# Meta-agent resolver for Ralphy
# Reviews multiple solutions and selects or merges the best approach

# ============================================
# META-AGENT FUNCTIONS
# ============================================

# Prepare meta-agent prompt comparing N solutions
prepare_meta_prompt() {
  local task_desc="$1"
  shift
  local solution_dirs=("$@")

  local num_solutions=${#solution_dirs[@]}

  # Start building the prompt
  local prompt="You are reviewing ${num_solutions} different solutions to the following task:

TASK: ${task_desc}

"

  # Add each solution to the prompt
  local solution_num=1
  for solution_dir in "${solution_dirs[@]}"; do
    local engine_name=$(basename "$(dirname "$solution_dir")")
    local worktree_file="$solution_dir/worktree.txt"
    local log_file="$solution_dir/log.txt"

    if [[ -f "$worktree_file" ]]; then
      local worktree_dir=$(cat "$worktree_file")

      # Get the diff from this solution
      local diff_output
      diff_output=$(cd "$worktree_dir" && git diff HEAD 2>/dev/null || echo "No changes")

      prompt+="SOLUTION ${solution_num} (from ${engine_name}):
\`\`\`diff
${diff_output}
\`\`\`

"
    fi

    solution_num=$((solution_num + 1))
  done

  # Add instructions
  prompt+="INSTRUCTIONS:
1. Analyze each solution for:
   - Correctness
   - Code quality
   - Adherence to best practices
   - Performance implications
   - Edge case handling

2. Either:
   a) Select the best single solution
   b) Merge the best parts of multiple solutions

3. Provide your decision in this format:
   DECISION: [select|merge]
   CHOSEN: [solution number OR \"merged\"]
   REASONING: [explain your choice]

   If DECISION is \"merge\", provide:
   MERGED_SOLUTION:
   \`\`\`
   [your merged code here]
   \`\`\`

Be objective. The best solution might not be from the most expensive engine."

  echo "$prompt"
}

# Run meta-agent to review and select best solution
run_meta_agent() {
  local task_desc="$1"
  local consensus_dir="$2"
  shift 2
  local engines=("$@")

  log_info "Running meta-agent to review ${#engines[@]} solutions..."

  # Prepare solution directories
  local solution_dirs=()
  for engine in "${engines[@]}"; do
    solution_dirs+=("$consensus_dir/$engine")
  done

  # Build prompt
  local prompt
  prompt=$(prepare_meta_prompt "$task_desc" "${solution_dirs[@]}")

  # Create output file
  local meta_output="$consensus_dir/meta-decision.txt"

  # Run meta-agent (default to Claude)
  local meta_engine="${META_AGENT_ENGINE:-claude}"

  log_info "Using $meta_engine as meta-agent"

  case "$meta_engine" in
    claude)
      echo "$prompt" | claude --dangerously-skip-permissions > "$meta_output" 2>&1
      ;;
    opencode)
      echo "$prompt" | opencode run --format json > "$meta_output" 2>&1
      ;;
    cursor)
      echo "$prompt" | agent --dangerously-skip-permissions > "$meta_output" 2>&1
      ;;
    *)
      log_error "Unknown meta-agent engine: $meta_engine"
      return 1
      ;;
  esac

  if [[ $? -ne 0 ]]; then
    log_error "Meta-agent execution failed"
    return 1
  fi

  log_success "Meta-agent review completed"

  # Parse the decision
  parse_meta_decision "$meta_output" "$consensus_dir" "${engines[@]}"
}

# Parse meta-agent decision and extract the chosen solution
parse_meta_decision() {
  local decision_file="$1"
  local consensus_dir="$2"
  shift 2
  local engines=("$@")

  if [[ ! -f "$decision_file" ]]; then
    log_error "Meta-agent decision file not found: $decision_file"
    return 1
  fi

  # Extract decision type and chosen solution
  local decision=$(grep -i "DECISION:" "$decision_file" | head -1 | sed 's/.*DECISION: *//i')
  local chosen=$(grep -i "CHOSEN:" "$decision_file" | head -1 | sed 's/.*CHOSEN: *//i')
  local reasoning=$(grep -i "REASONING:" "$decision_file" | head -1 | sed 's/.*REASONING: *//i')

  log_info "Meta-agent decision: $decision"
  log_info "Chosen solution: $chosen"
  log_info "Reasoning: $reasoning"

  # Save decision to metadata
  local meta_json="$consensus_dir/meta-decision.json"
  cat > "$meta_json" <<EOF
{
  "decision_type": "$decision",
  "chosen": "$chosen",
  "reasoning": "$reasoning",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  # Return the chosen solution index or "merged"
  echo "$chosen"
}

# Merge multiple solutions (placeholder for future implementation)
merge_solutions() {
  local consensus_dir="$1"
  shift
  local solution_dirs=("$@")

  log_warning "Solution merging not yet implemented"
  log_info "Falling back to first solution"

  # For now, just return the first solution
  echo "${solution_dirs[0]}"
}
