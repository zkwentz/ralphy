#!/usr/bin/env bash

# ============================================
# Ralphy Metrics Module
# Tracks engine performance and enables adaptive selection
# ============================================

# Metrics file location
METRICS_FILE="${RALPHY_DIR:-.ralphy}/metrics.json"

# Ensure metrics file exists with proper structure
init_metrics_file() {
  if [[ ! -f "$METRICS_FILE" ]]; then
    cat > "$METRICS_FILE" << 'EOF'
{
  "version": "1.0",
  "engines": {
    "claude": {
      "total_executions": 0,
      "successful": 0,
      "failed": 0,
      "success_rate": 0.0,
      "avg_duration_ms": 0,
      "total_cost": 0.0,
      "avg_input_tokens": 0,
      "avg_output_tokens": 0,
      "task_patterns": {}
    },
    "opencode": {
      "total_executions": 0,
      "successful": 0,
      "failed": 0,
      "success_rate": 0.0,
      "avg_duration_ms": 0,
      "total_cost": 0.0,
      "avg_input_tokens": 0,
      "avg_output_tokens": 0,
      "task_patterns": {}
    },
    "cursor": {
      "total_executions": 0,
      "successful": 0,
      "failed": 0,
      "success_rate": 0.0,
      "avg_duration_ms": 0,
      "total_cost": 0.0,
      "avg_input_tokens": 0,
      "avg_output_tokens": 0,
      "task_patterns": {}
    },
    "codex": {
      "total_executions": 0,
      "successful": 0,
      "failed": 0,
      "success_rate": 0.0,
      "avg_duration_ms": 0,
      "total_cost": 0.0,
      "avg_input_tokens": 0,
      "avg_output_tokens": 0,
      "task_patterns": {}
    },
    "qwen": {
      "total_executions": 0,
      "successful": 0,
      "failed": 0,
      "success_rate": 0.0,
      "avg_duration_ms": 0,
      "total_cost": 0.0,
      "avg_input_tokens": 0,
      "avg_output_tokens": 0,
      "task_patterns": {}
    },
    "droid": {
      "total_executions": 0,
      "successful": 0,
      "failed": 0,
      "success_rate": 0.0,
      "avg_duration_ms": 0,
      "total_cost": 0.0,
      "avg_input_tokens": 0,
      "avg_output_tokens": 0,
      "task_patterns": {}
    }
  },
  "execution_history": [],
  "consensus_history": [],
  "race_history": []
}
EOF
  fi
}

# Extract task pattern from task description for categorization
extract_task_pattern() {
  local task_desc="$1"

  # Normalize to lowercase for matching
  local normalized=$(echo "$task_desc" | tr '[:upper:]' '[:lower:]')

  # Match against common patterns (order matters - more specific first)
  if echo "$normalized" | grep -qE "refactor|architecture|design pattern|optimize|structure"; then
    echo "refactor_architecture"
  elif echo "$normalized" | grep -qE "ui|frontend|styling|component|design|css|layout"; then
    echo "ui_frontend"
  elif echo "$normalized" | grep -qE "test|spec|unit test|integration test|e2e"; then
    echo "testing"
  elif echo "$normalized" | grep -qE "bug fix|fix bug|debug|error|crash|issue"; then
    echo "bug_fix"
  elif echo "$normalized" | grep -qE "api|endpoint|route|controller|backend"; then
    echo "api_backend"
  elif echo "$normalized" | grep -qE "database|sql|query|migration|schema"; then
    echo "database"
  elif echo "$normalized" | grep -qE "security|auth|authentication|authorization|permission"; then
    echo "security"
  elif echo "$normalized" | grep -qE "performance|speed|slow|optimization"; then
    echo "performance"
  elif echo "$normalized" | grep -qE "documentation|readme|comment|doc"; then
    echo "documentation"
  else
    echo "general"
  fi
}

# Record a task execution
# Args: engine task_desc success duration_ms input_tokens output_tokens cost
record_execution() {
  local engine="$1"
  local task_desc="$2"
  local success="$3"         # true or false
  local duration_ms="${4:-0}"
  local input_tokens="${5:-0}"
  local output_tokens="${6:-0}"
  local cost="${7:-0.0}"

  # Ensure metrics file exists
  init_metrics_file

  # Ensure jq is available
  if ! command -v jq &>/dev/null; then
    return 0  # Silently skip if jq not available
  fi

  # Extract task pattern
  local pattern=$(extract_task_pattern "$task_desc")

  # Create timestamp
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")

  # Record execution in history
  local temp_file=$(mktemp)
  jq --arg engine "$engine" \
     --arg task "$task_desc" \
     --arg pattern "$pattern" \
     --argjson success "$success" \
     --argjson duration "$duration_ms" \
     --argjson input "$input_tokens" \
     --argjson output "$output_tokens" \
     --arg cost "$cost" \
     --arg timestamp "$timestamp" \
     '.execution_history += [{
       "engine": $engine,
       "task": $task,
       "pattern": $pattern,
       "success": $success,
       "duration_ms": $duration,
       "input_tokens": $input,
       "output_tokens": $output,
       "cost": $cost,
       "timestamp": $timestamp
     }]' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"

  # Update engine-level metrics
  update_engine_metrics "$engine" "$pattern" "$success" "$duration_ms" "$input_tokens" "$output_tokens" "$cost"
}

# Update aggregated engine metrics
update_engine_metrics() {
  local engine="$1"
  local pattern="$2"
  local success="$3"
  local duration_ms="${4:-0}"
  local input_tokens="${5:-0}"
  local output_tokens="${6:-0}"
  local cost="${7:-0.0}"

  if ! command -v jq &>/dev/null; then
    return 0
  fi

  local temp_file=$(mktemp)

  # Complex jq update for engine statistics
  jq --arg engine "$engine" \
     --arg pattern "$pattern" \
     --argjson success "$success" \
     --argjson duration "$duration_ms" \
     --argjson input "$input_tokens" \
     --argjson output "$output_tokens" \
     --arg cost "$cost" \
     '
     # Update overall engine stats
     .engines[$engine].total_executions += 1 |
     if $success then
       .engines[$engine].successful += 1
     else
       .engines[$engine].failed += 1
     end |
     .engines[$engine].success_rate = (
       if .engines[$engine].total_executions > 0 then
         (.engines[$engine].successful / .engines[$engine].total_executions)
       else 0 end
     ) |

     # Update running averages
     .engines[$engine].avg_duration_ms = (
       ((.engines[$engine].avg_duration_ms * (.engines[$engine].total_executions - 1)) + $duration) / .engines[$engine].total_executions
     ) |
     .engines[$engine].avg_input_tokens = (
       ((.engines[$engine].avg_input_tokens * (.engines[$engine].total_executions - 1)) + $input) / .engines[$engine].total_executions
     ) |
     .engines[$engine].avg_output_tokens = (
       ((.engines[$engine].avg_output_tokens * (.engines[$engine].total_executions - 1)) + $output) / .engines[$engine].total_executions
     ) |
     .engines[$engine].total_cost = ((.engines[$engine].total_cost | tonumber) + ($cost | tonumber)) |

     # Update pattern-specific stats
     .engines[$engine].task_patterns[$pattern] = (
       .engines[$engine].task_patterns[$pattern] // {
         "executions": 0,
         "successful": 0,
         "failed": 0,
         "success_rate": 0.0
       }
     ) |
     .engines[$engine].task_patterns[$pattern].executions += 1 |
     if $success then
       .engines[$engine].task_patterns[$pattern].successful += 1
     else
       .engines[$engine].task_patterns[$pattern].failed += 1
     end |
     .engines[$engine].task_patterns[$pattern].success_rate = (
       if .engines[$engine].task_patterns[$pattern].executions > 0 then
         (.engines[$engine].task_patterns[$pattern].successful / .engines[$engine].task_patterns[$pattern].executions)
       else 0 end
     )
     ' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
}

# Get best engine for a task pattern based on historical performance
# Args: task_desc [min_samples]
# Returns: engine name or empty string
get_best_engine_for_pattern() {
  local task_desc="$1"
  local min_samples="${2:-5}"  # Default: require at least 5 samples

  if ! command -v jq &>/dev/null; then
    echo ""  # Return empty if jq not available
    return 0
  fi

  # Ensure metrics file exists
  init_metrics_file

  # Extract pattern from task
  local pattern=$(extract_task_pattern "$task_desc")

  # Query metrics for best engine for this pattern
  local best_engine=$(jq -r --arg pattern "$pattern" --argjson min "$min_samples" '
    .engines
    | to_entries
    | map({
        engine: .key,
        success_rate: (.value.task_patterns[$pattern].success_rate // 0),
        executions: (.value.task_patterns[$pattern].executions // 0)
      })
    | map(select(.executions >= $min))
    | sort_by(-.success_rate)
    | .[0].engine // ""
  ' "$METRICS_FILE" 2>/dev/null || echo "")

  echo "$best_engine"
}

# Get overall best engine (highest success rate with minimum samples)
get_overall_best_engine() {
  local min_samples="${1:-10}"

  if ! command -v jq &>/dev/null; then
    echo ""
    return 0
  fi

  init_metrics_file

  local best_engine=$(jq -r --argjson min "$min_samples" '
    .engines
    | to_entries
    | map({
        engine: .key,
        success_rate: .value.success_rate,
        executions: .value.total_executions
      })
    | map(select(.executions >= $min))
    | sort_by(-.success_rate)
    | .[0].engine // ""
  ' "$METRICS_FILE" 2>/dev/null || echo "")

  echo "$best_engine"
}

# Display metrics report
show_metrics_report() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for metrics reporting"
    return 1
  fi

  init_metrics_file

  echo ""
  echo "════════════════════════════════════════════════════"
  echo "  Ralphy Engine Performance Metrics"
  echo "════════════════════════════════════════════════════"
  echo ""

  # Overall engine statistics
  echo "Overall Engine Performance:"
  echo "────────────────────────────────────────────────────"
  printf "%-12s %10s %10s %10s %12s %10s\n" "Engine" "Executions" "Success" "Failed" "Success Rate" "Avg Cost"
  echo "────────────────────────────────────────────────────"

  jq -r '
    .engines
    | to_entries
    | sort_by(-.value.total_executions)
    | .[]
    | [
        .key,
        .value.total_executions,
        .value.successful,
        .value.failed,
        ((.value.success_rate * 100) | tostring | .[0:5]) + "%",
        ("$" + ((.value.total_cost / (if .value.total_executions > 0 then .value.total_executions else 1 end)) | tostring | .[0:6]))
      ]
    | @tsv
  ' "$METRICS_FILE" | while IFS=$'\t' read -r engine exec succ fail rate cost; do
    printf "%-12s %10s %10s %10s %12s %10s\n" "$engine" "$exec" "$succ" "$fail" "$rate" "$cost"
  done

  echo ""
  echo "Pattern-Specific Performance (Top Patterns by Volume):"
  echo "────────────────────────────────────────────────────"

  # Get top patterns across all engines
  local patterns=$(jq -r '
    [.engines[].task_patterns | keys[]] | unique | .[]
  ' "$METRICS_FILE" 2>/dev/null)

  for pattern in $patterns; do
    echo ""
    echo "Pattern: $pattern"
    printf "  %-12s %10s %12s\n" "Engine" "Executions" "Success Rate"
    echo "  ────────────────────────────────────────────────"

    jq -r --arg pattern "$pattern" '
      .engines
      | to_entries
      | map(select(.value.task_patterns[$pattern]))
      | sort_by(-.value.task_patterns[$pattern].success_rate)
      | .[]
      | [
          .key,
          .value.task_patterns[$pattern].executions,
          ((.value.task_patterns[$pattern].success_rate * 100) | tostring | .[0:5]) + "%"
        ]
      | @tsv
    ' "$METRICS_FILE" 2>/dev/null | while IFS=$'\t' read -r engine exec rate; do
      printf "  %-12s %10s %12s\n" "$engine" "$exec" "$rate"
    done
  done

  # Recent execution history
  echo ""
  echo ""
  echo "Recent Executions (Last 10):"
  echo "────────────────────────────────────────────────────"
  printf "%-12s %-20s %-10s %-15s\n" "Engine" "Pattern" "Success" "Task"
  echo "────────────────────────────────────────────────────"

  jq -r '
    .execution_history
    | .[-10:]
    | reverse
    | .[]
    | [
        .engine,
        .pattern,
        (if .success then "✓" else "✗" end),
        (.task | .[0:40])
      ]
    | @tsv
  ' "$METRICS_FILE" 2>/dev/null | while IFS=$'\t' read -r engine pattern success task; do
    printf "%-12s %-20s %-10s %-15s\n" "$engine" "$pattern" "$success" "$task"
  done

  echo ""
  echo "════════════════════════════════════════════════════"
  echo ""
}

# Reset all metrics
reset_metrics() {
  if [[ -f "$METRICS_FILE" ]]; then
    rm -f "$METRICS_FILE"
    init_metrics_file
    echo "Metrics reset successfully"
  else
    echo "No metrics to reset"
  fi
}

# Export metrics to a JSON report file
export_metrics_report() {
  local output_file="${1:-.ralphy/metrics-report.json}"

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for exporting metrics"
    return 1
  fi

  init_metrics_file

  # Create enhanced report with calculated insights
  jq '
    {
      "generated_at": (now | todate),
      "summary": {
        "total_executions": ([.engines[].total_executions] | add),
        "total_successful": ([.engines[].successful] | add),
        "total_failed": ([.engines[].failed] | add),
        "overall_success_rate": (
          ([.engines[].successful] | add) /
          (([.engines[].total_executions] | add) // 1)
        ),
        "total_cost": ([.engines[].total_cost] | add)
      },
      "engines": .engines,
      "best_engine_overall": (
        .engines
        | to_entries
        | map(select(.value.total_executions >= 5))
        | sort_by(-.value.success_rate)
        | .[0].key // "N/A"
      ),
      "best_engines_by_pattern": (
        [.engines[].task_patterns | keys[]] | unique | map(. as $pattern | {
          pattern: $pattern,
          best_engine: (
            $ENV.engines
            | to_entries
            | map(select(.value.task_patterns[$pattern].executions >= 3))
            | sort_by(-.value.task_patterns[$pattern].success_rate)
            | .[0].key // "N/A"
          )
        })
      ),
      "execution_history": .execution_history[-50:],
      "consensus_history": .consensus_history,
      "race_history": .race_history
    }
  ' "$METRICS_FILE" > "$output_file"

  echo "Metrics exported to: $output_file"
}

# Record consensus mode execution
# Args: task_id engines winner meta_agent_used
record_consensus_execution() {
  local task_id="$1"
  local engines="$2"  # Comma-separated list
  local winner="$3"
  local meta_agent_used="$4"

  if ! command -v jq &>/dev/null; then
    return 0
  fi

  init_metrics_file

  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  local temp_file=$(mktemp)

  jq --arg task_id "$task_id" \
     --arg engines "$engines" \
     --arg winner "$winner" \
     --argjson meta "$meta_agent_used" \
     --arg timestamp "$timestamp" \
     '.consensus_history += [{
       "task_id": $task_id,
       "engines": ($engines | split(",")),
       "winner": $winner,
       "meta_agent_used": $meta,
       "timestamp": $timestamp
     }]' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
}

# Record race mode execution
# Args: task_id engines winner win_time_ms
record_race_execution() {
  local task_id="$1"
  local engines="$2"  # Comma-separated list
  local winner="$3"
  local win_time_ms="$4"

  if ! command -v jq &>/dev/null; then
    return 0
  fi

  init_metrics_file

  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  local temp_file=$(mktemp)

  jq --arg task_id "$task_id" \
     --arg engines "$engines" \
     --arg winner "$winner" \
     --argjson win_time "$win_time_ms" \
     --arg timestamp "$timestamp" \
     '.race_history += [{
       "task_id": $task_id,
       "engines": ($engines | split(",")),
       "winner": $winner,
       "win_time_ms": $win_time,
       "timestamp": $timestamp
     }]' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
}
