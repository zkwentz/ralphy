#!/usr/bin/env bash

# ============================================
# Meta-Agent Decision Resolution
# ============================================
# Functions for meta-agent conflict resolution and decision parsing
# Part of Ralphy's multi-agent engine system

# Note: We don't use 'set -euo pipefail' globally here to allow
# more flexible regex matching and error handling within functions

# ============================================
# DECISION PARSING
# ============================================

# Parse meta-agent decision from output
# Expected format:
#   DECISION: [select|merge]
#   CHOSEN: [solution number OR "merged"]
#   REASONING: [explain your choice]
#
#   If DECISION is "merge", also expect:
#   MERGED_SOLUTION:
#   ```
#   [merged code]
#   ```
#
# Args:
#   $1 - Path to meta-agent output file
#
# Returns:
#   Echoes JSON object with parsed decision:
#   {
#     "decision": "select|merge",
#     "chosen": "1|2|merged",
#     "reasoning": "explanation text",
#     "merged_solution": "code content (if merge)"
#   }
#
# Exit codes:
#   0 - Success
#   1 - File not found or invalid format
parse_meta_decision() {
  local output_file="$1"

  if [[ ! -f "$output_file" ]]; then
    echo "{\"error\": \"Output file not found: $output_file\"}" >&2
    return 1
  fi

  local decision=""
  local chosen=""
  local reasoning=""
  local merged_solution=""
  local in_merged_block=false
  local in_code_block=false
  local code_buffer=""
  local reading_reasoning=false

  # Helper function to trim whitespace without xargs (to avoid quote issues)
  trim() {
    local var="$1"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
  }

  # Read file line by line
  while IFS= read -r line; do
    # Extract DECISION field
    if [[ "$line" =~ ^[[:space:]]*DECISION:[[:space:]]*(.+)$ ]]; then
      local matched="${BASH_REMATCH[1]:-}"
      decision=$(trim "$matched")
      decision=$(echo "$decision" | tr '[:upper:]' '[:lower:]')  # lowercase
      reading_reasoning=false
      continue
    fi

    # Extract CHOSEN field
    if [[ "$line" =~ ^[[:space:]]*CHOSEN:[[:space:]]*(.+)$ ]]; then
      local matched="${BASH_REMATCH[1]:-}"
      chosen=$(trim "$matched")
      # Extract just the number or "merged"
      if [[ "$chosen" =~ ([0-9]+|merged) ]]; then
        chosen="${BASH_REMATCH[1]:-}"
      fi
      reading_reasoning=false
      continue
    fi

    # Extract REASONING field (may be multiline)
    if [[ "$line" =~ ^[[:space:]]*REASONING:[[:space:]]*(.+)$ ]]; then
      local matched="${BASH_REMATCH[1]:-}"
      reasoning=$(trim "$matched")
      reading_reasoning=true
      continue
    fi

    # Detect MERGED_SOLUTION section
    if [[ "$line" =~ ^[[:space:]]*MERGED_SOLUTION:[[:space:]]*$ ]]; then
      in_merged_block=true
      reading_reasoning=false
      continue
    fi

    # Continue reading reasoning if we're in that section
    if [[ "$reading_reasoning" == true ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
      # Stop if we hit another field marker
      if [[ "$line" =~ ^[[:space:]]*(DECISION|CHOSEN|MERGED_SOLUTION): ]]; then
        reading_reasoning=false
      else
        # Append to reasoning
        if [[ -n "$reasoning" ]]; then
          reasoning+=" "
        fi
        reasoning+=$(trim "$line")
      fi
    fi

    # Handle merged solution code block
    if [[ "$in_merged_block" == true ]]; then
      # Start of code block
      if [[ "$line" =~ ^[[:space:]]*\`\`\`[[:space:]]*[a-z]* ]]; then
        if [[ "$in_code_block" == false ]]; then
          in_code_block=true
          code_buffer=""
        else
          # End of code block (closing backticks)
          in_code_block=false
          merged_solution="$code_buffer"
          in_merged_block=false
        fi
        continue
      fi

      # Collect code lines
      if [[ "$in_code_block" == true ]]; then
        if [[ -n "$code_buffer" ]]; then
          code_buffer+=$'\n'
        fi
        code_buffer+="$line"
      fi
    fi

  done < "$output_file"

  # Validate required fields
  if [[ -z "$decision" ]]; then
    echo "{\"error\": \"Missing DECISION field in meta-agent output\"}" >&2
    return 1
  fi

  if [[ -z "$chosen" ]]; then
    echo "{\"error\": \"Missing CHOSEN field in meta-agent output\"}" >&2
    return 1
  fi

  # Validate decision type
  if [[ "$decision" != "select" && "$decision" != "merge" ]]; then
    echo "{\"error\": \"Invalid DECISION value: $decision (must be 'select' or 'merge')\"}" >&2
    return 1
  fi

  # If decision is merge, ensure we have merged solution
  if [[ "$decision" == "merge" && -z "$merged_solution" ]]; then
    echo "{\"error\": \"DECISION is 'merge' but no MERGED_SOLUTION found\"}" >&2
    return 1
  fi

  # Build JSON output using printf and simple string replacement
  # Escape special characters for JSON
  escape_json() {
    local str="$1"
    # Escape backslashes and quotes
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    # Replace newlines with \n (literal backslash-n)
    str="${str//$'\n'/\\n}"
    printf '%s' "$str"
  }

  local escaped_reasoning
  local escaped_solution

  escaped_reasoning=$(escape_json "$reasoning")

  local json_output="{"
  json_output+="\"decision\": \"$decision\""
  json_output+=", \"chosen\": \"$chosen\""
  json_output+=", \"reasoning\": \"$escaped_reasoning\""

  # Add merged solution if present
  if [[ -n "$merged_solution" ]]; then
    escaped_solution=$(escape_json "$merged_solution")
    json_output+=", \"merged_solution\": \"$escaped_solution\""
  fi

  json_output+="}"

  echo "$json_output"
  return 0
}

# ============================================
# PROMPT PREPARATION
# ============================================

# Prepare meta-agent prompt comparing multiple solutions
# Args:
#   $1 - Task description
#   $@ - Array of solution directory paths
#
# Returns:
#   Echoes formatted prompt string
prepare_meta_prompt() {
  local task_desc="$1"
  shift
  local solutions=("$@")
  local n=${#solutions[@]}

  local prompt="You are reviewing $n different solutions to the following task:

TASK: $task_desc

"

  # Add each solution
  local i=1
  for solution_dir in "${solutions[@]}"; do
    local engine_name=$(basename "$solution_dir")
    prompt+="SOLUTION $i (from $engine_name):
"

    # Read solution files (git diff or changed files)
    if [[ -d "$solution_dir" ]]; then
      # Get git diff for this worktree
      local diff_output
      if diff_output=$(cd "$solution_dir" && git diff HEAD 2>/dev/null); then
        if [[ -n "$diff_output" ]]; then
          prompt+="$diff_output
"
        else
          prompt+="(No changes detected)
"
        fi
      else
        prompt+="(Error reading solution)
"
      fi
    fi

    prompt+="

"
    ((i++))
  done

  # Add instructions
  prompt+="INSTRUCTIONS:
1. Analyze each solution for:
   - Correctness
   - Code quality
   - Adherence to project rules
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

# ============================================
# META-AGENT EXECUTION
# ============================================

# Run meta-agent to resolve conflicts between solutions
# Args:
#   $1 - Task description
#   $@ - Array of solution directory paths
#
# Returns:
#   Echoes path to decision file
#   Exit code 0 on success, 1 on failure
run_meta_agent() {
  local task_desc="$1"
  shift
  local solutions=("$@")

  local meta_engine="${META_AGENT_ENGINE:-claude}"
  local output_file=".ralphy/meta-agent-decision.json"
  local prompt

  # Prepare prompt
  prompt=$(prepare_meta_prompt "$task_desc" "${solutions[@]}")

  # Create output directory if needed
  mkdir -p "$(dirname "$output_file")"

  # Run meta-agent based on engine type
  case "$meta_engine" in
    claude)
      if command -v claude &>/dev/null; then
        echo "$prompt" | claude --dangerously-skip-permissions \
          --output-format stream-json \
          > "$output_file" 2>&1
      else
        echo "{\"error\": \"Claude CLI not found\"}" > "$output_file"
        return 1
      fi
      ;;

    opencode)
      if command -v opencode &>/dev/null; then
        echo "$prompt" | opencode --output-format stream-json \
          > "$output_file" 2>&1
      else
        echo "{\"error\": \"OpenCode CLI not found\"}" > "$output_file"
        return 1
      fi
      ;;

    cursor)
      if command -v cursor &>/dev/null; then
        echo "$prompt" | cursor --output-format stream-json \
          > "$output_file" 2>&1
      else
        echo "{\"error\": \"Cursor CLI not found\"}" > "$output_file"
        return 1
      fi
      ;;

    *)
      echo "{\"error\": \"Unknown meta-agent engine: $meta_engine\"}" > "$output_file"
      return 1
      ;;
  esac

  # Parse and validate decision
  local decision_json
  if decision_json=$(parse_meta_decision "$output_file"); then
    echo "$decision_json" > "$output_file"
    echo "$output_file"
    return 0
  else
    return 1
  fi
}

# ============================================
# SOLUTION MERGING
# ============================================

# Apply merged solution to target directory
# Args:
#   $1 - Merged solution code
#   $2 - Target directory
#
# Returns:
#   Exit code 0 on success, 1 on failure
merge_solutions() {
  local merged_solution="$1"
  local target_dir="$2"

  # This is a placeholder for solution merging logic
  # In practice, this would:
  # 1. Parse file paths from diff/code blocks
  # 2. Apply changes to target directory
  # 3. Validate the merged result

  # For now, just log the action
  echo "Applying merged solution to $target_dir"

  # TODO: Implement actual merge logic
  # This might involve:
  # - Creating/updating files
  # - Running git apply with patches
  # - Handling conflicts

  return 0
}

# Export functions for use in ralphy.sh
export -f parse_meta_decision
export -f prepare_meta_prompt
export -f run_meta_agent
export -f merge_solutions
