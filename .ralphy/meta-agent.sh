#!/bin/bash

# Meta-Agent Implementation
# Compares multiple AI solutions and selects the best one

run_meta_agent_comparison() {
  local task_name="$1"
  local solution_dir="$2"
  shift 2
  local engines=("$@")

  local num_solutions="${#engines[@]}"

  if [[ "$num_solutions" -lt 2 ]]; then
    echo "ERROR: Need at least 2 solutions to compare"
    return 1
  fi

  # Build comparison prompt
  local prompt="You are a meta-agent reviewing multiple AI-generated solutions to the same task. Your job is to objectively analyze and select the best solution.

TASK: $task_name

I have received $num_solutions different solutions from different AI engines. Please review each solution carefully.

"

  # Add each solution to the prompt
  local solution_num=1
  for engine in "${engines[@]}"; do
    local diff_file="$solution_dir/${engine}_diff.patch"
    local commits_file="$solution_dir/${engine}_commits.txt"
    local stats_file="$solution_dir/${engine}_stats.txt"

    if [[ ! -f "$diff_file" ]]; then
      echo "ERROR: Missing diff file for $engine"
      continue
    fi

    prompt+="
═══════════════════════════════════════════════════════════════
SOLUTION $solution_num (from $engine):
═══════════════════════════════════════════════════════════════

COMMIT MESSAGES:
$(cat "$commits_file" 2>/dev/null || echo "No commit info available")

CHANGE STATISTICS:
$(cat "$stats_file" 2>/dev/null || echo "No stats available")

CODE CHANGES (diff):
\`\`\`diff
$(cat "$diff_file")
\`\`\`

"
    ((solution_num++))
  done

  prompt+="
═══════════════════════════════════════════════════════════════
ANALYSIS INSTRUCTIONS:
═══════════════════════════════════════════════════════════════

Please analyze each solution based on:

1. **Correctness**: Does it properly implement the requested task?
2. **Code Quality**: Is the code clean, maintainable, and well-structured?
3. **Completeness**: Does it fully address all aspects of the task?
4. **Testing**: Does it include appropriate tests?
5. **Best Practices**: Does it follow coding standards and conventions?
6. **Edge Cases**: Does it handle edge cases and error conditions?
7. **Documentation**: Are changes well-documented (commits, comments)?
8. **Scope**: Does it stay focused on the task without unnecessary changes?

Compare the solutions objectively. The best solution might come from any engine.

IMPORTANT: Provide your decision in this EXACT format:

DECISION: [This should be 'select' - merging is not yet supported]
CHOSEN: [engine name - must be one of: ${engines[*]}]
REASONING:
[Provide a clear, detailed explanation of why you chose this solution. Compare the key differences between the solutions and explain what made the chosen solution superior.]

Make sure to use the EXACT format above. The CHOSEN field must contain only the engine name.
"

  # Run meta-agent (use Claude by default)
  local meta_engine="${META_AGENT_ENGINE:-claude}"
  local tmpfile
  tmpfile=$(mktemp)

  case "$meta_engine" in
    claude|*)
      claude --dangerously-skip-permissions \
        -p "$prompt" \
        --output-format stream-json > "$tmpfile" 2>&1
      ;;
    # Could add other engines here if needed
  esac

  # Parse the meta-agent output
  local result
  result=$(parse_ai_result "$(cat "$tmpfile")")
  rm -f "$tmpfile"

  # Extract decision from result
  local chosen_engine=""
  local reasoning=""

  # Look for the CHOSEN: line in the output
  if echo "$result" | grep -q "^CHOSEN:"; then
    chosen_engine=$(echo "$result" | grep "^CHOSEN:" | head -1 | cut -d':' -f2- | xargs)
  elif echo "$result" | grep -iq "CHOSEN:"; then
    # Case-insensitive search as fallback
    chosen_engine=$(echo "$result" | grep -i "^CHOSEN:" | head -1 | cut -d':' -f2- | xargs)
  fi

  # Extract reasoning
  if echo "$result" | grep -q "^REASONING:"; then
    reasoning=$(echo "$result" | sed -n '/^REASONING:/,${p}' | tail -n +2)
  elif echo "$result" | grep -iq "REASONING:"; then
    reasoning=$(echo "$result" | sed -n '/^[Rr][Ee][Aa][Ss][Oo][Nn][Ii][Nn][Gg]:/,${p}' | tail -n +2)
  fi

  # Validate chosen engine is in the list
  local valid_choice=false
  for engine in "${engines[@]}"; do
    if [[ "$chosen_engine" == "$engine" ]]; then
      valid_choice=true
      break
    fi
  done

  if [[ "$valid_choice" == false ]]; then
    # Try to find engine name in the result text
    for engine in "${engines[@]}"; do
      if echo "$result" | grep -qi "$engine"; then
        chosen_engine="$engine"
        valid_choice=true
        break
      fi
    done
  fi

  # Save meta-agent decision
  local decision_file="$solution_dir/meta-decision.txt"
  cat > "$decision_file" <<EOF
Task: $task_name
Engines Compared: ${engines[*]}
Chosen: $chosen_engine
Valid: $valid_choice

Full Meta-Agent Response:
$result
EOF

  # Return the decision
  if [[ "$valid_choice" == true ]]; then
    echo "CHOSEN:$chosen_engine"
    echo "REASONING:$reasoning"
    return 0
  else
    echo "ERROR: Meta-agent did not provide a valid choice. Response saved to $decision_file"
    # Default to first successful engine as fallback
    echo "CHOSEN:${engines[0]}"
    echo "REASONING:Meta-agent failed to choose; using first available solution (${engines[0]}) as fallback."
    return 1
  fi
}

compare_solution_similarity() {
  local solution1="$1"
  local solution2="$2"

  # Simple similarity check based on diff size
  local size1=$(wc -l < "$solution1" 2>/dev/null || echo "0")
  local size2=$(wc -l < "$solution2" 2>/dev/null || echo "0")

  # If sizes are very different, solutions are different
  if [[ "$size1" -eq 0 ]] || [[ "$size2" -eq 0 ]]; then
    echo "0.0"
    return 0
  fi

  local diff_ratio=$((size1 * 100 / size2))
  if [[ "$diff_ratio" -lt 80 ]] || [[ "$diff_ratio" -gt 120 ]]; then
    echo "0.5"
    return 0
  fi

  # Check for similar content (basic comparison)
  local diff_lines
  diff_lines=$(diff "$solution1" "$solution2" 2>/dev/null | wc -l)

  # Calculate similarity score (0.0 to 1.0)
  local similarity=$((100 - (diff_lines * 100 / size1)))
  if [[ "$similarity" -lt 0 ]]; then
    similarity=0
  fi

  # Convert to decimal
  echo "0.$similarity"
}
