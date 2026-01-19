# Multi-Agent Engine Plan for Ralphy

## Executive Summary

This plan outlines the architecture and implementation strategy for enabling Ralphy to use multiple AI coding engines simultaneously. The system will support three execution modes (consensus, specialization, race), intelligent task routing, meta-agent conflict resolution, and performance-based learning.

## Current State

Ralphy currently supports 6 AI engines with a simple switch-based selection:
- Claude Code (default)
- OpenCode
- Cursor
- Codex
- Qwen-Code
- Factory Droid

**Current Limitation:** Only one engine can be used per task execution.

## Goals

1. Enable multiple engines to work on the same task simultaneously (consensus/voting)
2. Support intelligent task routing to specialized engines
3. Implement race mode where multiple engines compete
4. Add meta-agent conflict resolution using AI judgment
5. Track engine performance metrics and adapt over time
6. Maintain bash implementation with minimal complexity

## Architecture Overview

### 1. Execution Modes

#### Mode A: Consensus Mode
- **Purpose:** Critical tasks requiring high confidence
- **Behavior:** Run 2+ engines on the same task
- **Resolution:** Meta-agent reviews all solutions and selects/merges the best
- **Use Case:** Complex refactoring, critical bug fixes, architecture changes

#### Mode B: Specialization Mode
- **Purpose:** Efficient task distribution based on engine strengths
- **Behavior:** Route different tasks to different engines based on task type
- **Resolution:** Each engine handles its specialized tasks independently
- **Use Case:** Large PRD with mixed task types (UI + backend + tests)

#### Mode C: Race Mode
- **Purpose:** Speed optimization for straightforward tasks
- **Behavior:** Run multiple engines in parallel, accept first successful completion
- **Resolution:** First engine to pass validation wins
- **Use Case:** Simple bug fixes, formatting, documentation updates

### 2. Configuration Schema

New `.ralphy/config.yaml` structure:

```yaml
project:
  name: "my-app"
  language: "TypeScript"
  framework: "Next.js"

engines:
  # Meta-agent configuration
  meta_agent:
    engine: "claude"  # Which engine resolves conflicts
    prompt_template: "Compare these ${n} solutions and select or merge the best approach. Explain your reasoning."

  # Default mode for task execution
  default_mode: "specialization"  # consensus | specialization | race

  # Available engines and their status
  available:
    - claude
    - opencode
    - cursor
    - codex
    - qwen
    - droid

  # Specialization routing rules
  specialization_rules:
    - pattern: "UI|frontend|styling|component|design"
      engines: ["cursor"]
      description: "UI and frontend work"

    - pattern: "refactor|architecture|design pattern|optimize"
      engines: ["claude"]
      description: "Complex reasoning and architecture"

    - pattern: "test|spec|unit test|integration test"
      engines: ["cursor", "codex"]
      mode: "race"
      description: "Testing tasks (race mode)"

    - pattern: "bug fix|fix bug|debug"
      engines: ["claude", "cursor", "opencode"]
      mode: "consensus"
      min_consensus: 2
      description: "Critical bug fixes"

  # Consensus mode settings
  consensus:
    min_engines: 2
    max_engines: 3
    default_engines: ["claude", "cursor", "opencode"]
    similarity_threshold: 0.8  # How similar solutions must be to skip meta-agent

  # Race mode settings
  race:
    max_parallel: 4
    timeout_multiplier: 1.5  # Allow 50% more time than single engine
    validation_required: true  # Validate before accepting race winner

  # Performance tracking
  metrics:
    enabled: true
    track_success_rate: true
    track_cost: true
    track_duration: true
    adapt_selection: true  # Auto-adjust engine selection based on performance
    min_samples: 10  # Minimum executions before adapting

commands:
  test: "npm test"
  lint: "npm run lint"
  build: "npm run build"

rules:
  - "use server actions not API routes"
  - "follow error pattern in src/utils/errors.ts"

boundaries:
  never_touch:
    - "src/legacy/**"
    - "*.lock"
```

### 3. Task Definition Extensions

#### YAML Task Format with Engine Hints

```yaml
tasks:
  - title: "Refactor authentication system"
    completed: false
    mode: "consensus"  # Override default mode
    engines: ["claude", "opencode"]  # Specific engines
    parallel_group: 1

  - title: "Update login button styling"
    completed: false
    mode: "specialization"  # Will use rules to auto-select
    parallel_group: 1

  - title: "Add unit tests for auth"
    completed: false
    mode: "race"
    engines: ["cursor", "codex", "qwen"]
    parallel_group: 2

  - title: "Fix critical security bug"
    completed: false
    mode: "consensus"
    engines: ["claude", "cursor", "opencode"]
    require_meta_review: true  # Force meta-agent even if consensus reached
    parallel_group: 2
```

#### Markdown PRD with Engine Annotations

```markdown
## Tasks

- [x] Refactor authentication system [consensus: claude, opencode]
- [x] Update login button styling [auto]
- [x] Add unit tests for auth [race: cursor, codex, qwen]
- [x] Fix critical security bug [consensus: claude, cursor, opencode | meta-review]
```

### 4. CLI Interface

New command-line flags:

```bash
# Mode selection
./ralphy.sh --mode consensus          # Enable consensus mode for all tasks
./ralphy.sh --mode specialization     # Use specialization rules (default)
./ralphy.sh --mode race              # Race mode for all tasks

# Engine selection for modes
./ralphy.sh --consensus-engines "claude,cursor,opencode"
./ralphy.sh --race-engines "all"
./ralphy.sh --meta-agent claude

# Mixed mode: read mode from task definitions
./ralphy.sh --mixed-mode

# Performance tracking
./ralphy.sh --show-metrics           # Display engine performance stats
./ralphy.sh --reset-metrics          # Clear performance history
./ralphy.sh --no-adapt              # Disable adaptive engine selection

# Existing flags remain compatible
./ralphy.sh --prd PRD.md
./ralphy.sh --parallel --max-parallel 5
./ralphy.sh --branch-per-task --create-pr
```

### 5. Implementation Phases

#### Phase 1: Core Infrastructure (Foundation)

**Files to Create:**
- `.ralphy/engines.sh` - Engine abstraction layer
- `.ralphy/modes.sh` - Mode execution logic
- `.ralphy/meta-agent.sh` - Meta-agent resolver
- `.ralphy/metrics.sh` - Performance tracking

**Files to Modify:**
- `ralphy.sh` - Source new modules, add CLI flags

**Key Functions:**

```bash
# engines.sh
validate_engine_availability()     # Check if engines are installed
get_engine_for_task()             # Apply specialization rules
estimate_task_cost()              # Estimate cost for engine selection

# modes.sh
run_consensus_mode()              # Execute consensus with N engines
run_specialization_mode()         # Route task to specialized engine
run_race_mode()                   # Parallel race with first-success
run_mixed_mode()                  # Read mode from task definition

# meta-agent.sh
prepare_meta_prompt()             # Build comparison prompt
run_meta_agent()                  # Execute meta-agent resolution
parse_meta_decision()             # Extract chosen solution
merge_solutions()                 # Combine multiple solutions if needed

# metrics.sh
record_execution()                # Log engine performance
calculate_success_rate()          # Compute metrics
get_best_engine_for_pattern()     # Adaptive selection
export_metrics_report()           # Generate performance report
```

#### Phase 2: Consensus Mode Implementation

**Workflow:**
1. Task arrives → Check if consensus mode enabled
2. Select N engines (from config or CLI)
3. Create isolated worktrees for each engine
4. Run all engines in parallel on same task
5. Wait for all to complete (or timeout)
6. Compare solutions:
   - If highly similar (>80%) → Auto-accept
   - If different → Invoke meta-agent
7. Meta-agent reviews and selects/merges
8. Apply chosen solution to main branch
9. Record metrics

**Key Considerations:**
- Each engine needs isolated workspace (use git worktrees)
- Solutions stored in `.ralphy/consensus/<task-id>/<engine>/`
- Meta-agent gets read-only access to all solutions
- Conflict handling: meta-agent can merge parts from multiple solutions

#### Phase 3: Specialization Mode Implementation

**Workflow:**
1. Parse task description
2. Match against specialization rules (regex patterns)
3. Select engine(s) based on matches
4. Fallback to default engine if no match
5. Track which rules matched for metrics
6. Execute with selected engine
7. Record pattern → engine → outcome for learning

**Rule Matching Logic:**
```bash
match_specialization_rule() {
  local task_desc=$1
  local matched_rule=""
  local matched_engines=""

  # Iterate through rules in config
  while read -r rule; do
    pattern=$(echo "$rule" | jq -r '.pattern')
    engines=$(echo "$rule" | jq -r '.engines[]')

    if echo "$task_desc" | grep -iE "$pattern"; then
      matched_rule="$pattern"
      matched_engines="$engines"
      break
    fi
  done

  echo "$matched_engines"
}
```

#### Phase 4: Race Mode Implementation

**Workflow:**
1. Task arrives → Select N engines for race
2. Create worktree per engine
3. Start all engines simultaneously
4. Monitor for first completion
5. Validate solution (run tests/lint)
6. If valid → Accept, kill other engines
7. If invalid → Wait for next completion
8. Record winner and timing metrics

**Optimization:**
- Use background processes with PID tracking
- Implement timeout (1.5x expected duration)
- Resource limits to prevent system overload
- Graceful shutdown of losing engines

#### Phase 5: Meta-Agent Resolver

**Meta-Agent Prompt Template:**
```
You are reviewing ${n} different solutions to the following task:

TASK: ${task_description}

SOLUTION 1 (from ${engine1}):
${solution1}

SOLUTION 2 (from ${engine2}):
${solution2}

[... more solutions ...]

INSTRUCTIONS:
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
   CHOSEN: [solution number OR "merged"]
   REASONING: [explain your choice]

   If DECISION is "merge", provide:
   MERGED_SOLUTION:
   ```
   [your merged code here]
   ```

Be objective. The best solution might not be from the most expensive engine.
```

**Implementation:**
```bash
run_meta_agent() {
  local task_desc=$1
  shift
  local solutions=("$@")  # Array of solution paths

  local meta_engine="${META_AGENT_ENGINE:-claude}"
  local prompt=$(prepare_meta_prompt "$task_desc" "${solutions[@]}")
  local output_file=".ralphy/meta-agent-decision.json"

  # Run meta-agent
  case "$meta_engine" in
    claude)
      claude --dangerously-skip-permissions \
        --output-format stream-json \
        -p "$prompt" > "$output_file" 2>&1
      ;;
    # ... other engines
  esac

  # Parse decision
  parse_meta_decision "$output_file"
}
```

#### Phase 6: Performance Metrics & Learning

**Metrics Database:** `.ralphy/metrics.json`

```json
{
  "engines": {
    "claude": {
      "total_executions": 45,
      "successful": 42,
      "failed": 3,
      "success_rate": 0.933,
      "avg_duration_ms": 12500,
      "total_cost": 2.45,
      "avg_input_tokens": 2500,
      "avg_output_tokens": 1200,
      "task_patterns": {
        "refactor|architecture": {
          "executions": 15,
          "success_rate": 0.95
        },
        "UI|frontend": {
          "executions": 5,
          "success_rate": 0.80
        }
      }
    },
    "cursor": {
      "total_executions": 38,
      "successful": 35,
      "failed": 3,
      "success_rate": 0.921,
      "avg_duration_ms": 8200,
      "task_patterns": {
        "UI|frontend": {
          "executions": 20,
          "success_rate": 0.95
        }
      }
    }
  },
  "consensus_history": [
    {
      "task_id": "abc123",
      "engines": ["claude", "cursor", "opencode"],
      "winner": "claude",
      "meta_agent_used": true,
      "timestamp": "2026-01-18T20:00:00Z"
    }
  ],
  "race_history": [
    {
      "task_id": "def456",
      "engines": ["cursor", "codex", "qwen"],
      "winner": "cursor",
      "win_time_ms": 5200,
      "timestamp": "2026-01-18T20:05:00Z"
    }
  ]
}
```

**Adaptive Selection:**
```bash
get_best_engine_for_pattern() {
  local pattern=$1
  local min_samples=10

  # Query metrics for pattern match
  local best_engine=$(jq -r --arg pattern "$pattern" '
    .engines
    | to_entries
    | map({
        engine: .key,
        success_rate: .value.task_patterns[$pattern].success_rate // 0,
        executions: .value.task_patterns[$pattern].executions // 0
      })
    | map(select(.executions >= '"$min_samples"'))
    | sort_by(-.success_rate)
    | .[0].engine // "claude"
  ' .ralphy/metrics.json)

  echo "$best_engine"
}
```

### 6. Validation & Quality Gates

Each solution (regardless of mode) must pass:

1. **Syntax Check:** Language-specific linting
2. **Test Suite:** Run configured tests
3. **Build Verification:** Ensure project builds
4. **Diff Review:** Changes are reasonable in scope

```bash
validate_solution() {
  local worktree_path=$1
  local original_dir=$(pwd)

  cd "$worktree_path"

  # Run validation commands from config
  if [[ -n "$TEST_COMMAND" ]] && [[ "$NO_TESTS" != "true" ]]; then
    eval "$TEST_COMMAND" || return 1
  fi

  if [[ -n "$LINT_COMMAND" ]] && [[ "$NO_LINT" != "true" ]]; then
    eval "$LINT_COMMAND" || return 1
  fi

  if [[ -n "$BUILD_COMMAND" ]]; then
    eval "$BUILD_COMMAND" || return 1
  fi

  cd "$original_dir"
  return 0
}
```

### 7. File Structure

```
my-ralphy/
├── ralphy.sh                          # Main orchestrator (modified)
├── .ralphy/
│   ├── config.yaml                    # Enhanced config with engine settings
│   ├── engines.sh                     # NEW: Engine abstraction layer
│   ├── modes.sh                       # NEW: Mode execution logic
│   ├── meta-agent.sh                  # NEW: Meta-agent resolver
│   ├── metrics.sh                     # NEW: Performance tracking
│   ├── metrics.json                   # NEW: Metrics database
│   ├── consensus/                     # NEW: Consensus mode workspaces
│   │   └── <task-id>/
│   │       ├── claude/
│   │       ├── cursor/
│   │       └── meta-decision.json
│   └── race/                          # NEW: Race mode tracking
│       └── <task-id>/
│           ├── claude/
│           ├── cursor/
│           └── winner.txt
├── MultiAgentPlan.md                  # This document
└── README.md                          # Updated with new features
```

### 8. Error Handling & Edge Cases

#### All Engines Fail in Consensus Mode
- **Strategy:** Retry with different engine combination
- **Fallback:** Manual intervention prompt
- **Metric:** Record as consensus failure

#### Meta-Agent Provides Invalid Decision
- **Strategy:** Re-run meta-agent with more explicit instructions
- **Fallback:** Present all solutions to user for manual selection
- **Limit:** Max 2 meta-agent retries

#### Race Mode: All Engines Fail Validation
- **Strategy:** Sequentially retry failed solutions with fixes
- **Fallback:** Switch to consensus mode
- **Metric:** Record race mode failure

#### Specialization Rule Conflicts
- **Strategy:** Use first matching rule
- **Config Validation:** Warn on overlapping patterns during init
- **Override:** Task-level engine specification wins

#### Resource Exhaustion (Too Many Parallel Engines)
- **Strategy:** Implement queue system with max parallel limit
- **Config:** `max_concurrent_engines: 6` in config
- **Monitoring:** Track system resources, throttle if needed

### 9. Cost Management

Running multiple engines increases costs. Strategies:

1. **Cost Estimation:**
   ```bash
   estimate_mode_cost() {
     case "$mode" in
       consensus)
         # Multiply single-engine cost by N engines + meta-agent
         cost=$((single_cost * consensus_engines + meta_cost))
         ;;
       race)
         # Worst case: all engines run full duration
         cost=$((single_cost * race_engines))
         # Best case: only winner's cost + small overhead
         ;;
     esac
   }
   ```

2. **Cost Limits:**
   ```yaml
   cost_controls:
     max_per_task: 5.00       # USD
     max_per_session: 50.00   # USD
     warn_threshold: 0.75     # Warn at 75% of limit
   ```

3. **Smart Mode Selection:**
   - Simple tasks → Race mode (likely early termination)
   - Medium tasks → Specialization (single engine)
   - Critical tasks → Consensus (pay for confidence)

### 10. Testing Strategy

#### Unit Tests (bash_unit or bats)
- Test rule matching logic
- Test metrics calculations
- Test meta-agent prompt generation
- Test mode selection logic

#### Integration Tests
- Mock engine outputs
- Test consensus workflow end-to-end
- Test race mode with simulated engines
- Test metrics persistence

#### Manual Testing Checklist
- [x] Consensus mode with 2 engines (similar results)
- [x] Consensus mode with 2 engines (different results)
- [x] Specialization with matching rules
- [x] Specialization with no matching rules
- [x] Race mode with early winner
- [x] Race mode with all failures
- [x] Meta-agent decision parsing
- [x] Metrics recording and adaptive selection
- [x] Cost limit enforcement
- [x] Validation gate failures

### 11. Migration Path

For existing Ralphy users:

1. **Backwards Compatibility:** All existing flags work as before
2. **Opt-in:** Multi-engine modes require explicit flags or config
3. **Default Behavior:** Single-engine mode (current) remains default
4. **Config Migration:**
   ```bash
   ./ralphy.sh --init-multi-engine  # Generate new config structure
   ./ralphy.sh --migrate-config     # Migrate old config to new format
   ```

### 12. Documentation Updates

#### README.md Additions

```markdown
## Multi-Engine Modes

Run multiple AI engines simultaneously for better results:

### Consensus Mode
Multiple engines work on same task, AI judge picks best solution:
```bash
./ralphy.sh --mode consensus --consensus-engines "claude,cursor,opencode"
```

### Specialization Mode
Auto-route tasks to specialized engines:
```bash
./ralphy.sh --mode specialization  # Uses rules in .ralphy/config.yaml
```

### Race Mode
Engines compete, first successful solution wins:
```bash
./ralphy.sh --mode race --race-engines "all"
```

### Performance Tracking
View engine performance metrics:
```bash
./ralphy.sh --show-metrics
```

System learns over time and adapts engine selection.
```

### 13. Success Metrics

Measure multi-engine implementation success:

1. **Quality Improvement:**
   - % of consensus tasks where meta-agent selects better solution
   - % reduction in bugs after consensus mode deployment

2. **Performance:**
   - Average task completion time (race mode vs single)
   - Cost efficiency (specialization mode)

3. **Adaptation:**
   - % of tasks using adaptive engine selection
   - Improvement in success rate over time per engine

4. **User Adoption:**
   - % of users enabling multi-engine modes
   - Mode distribution (consensus vs specialization vs race)

### 14. Future Enhancements (Post-MVP)

- **Hybrid Solutions:** Meta-agent merges best parts of multiple solutions
- **Learning Engine Strengths:** ML model to predict best engine per task
- **Real-time Monitoring:** Web dashboard showing engine execution status
- **A/B Testing:** Automatically compare engine outputs on subset of tasks
- **Custom Plugins:** User-defined engine adapters
- **Cloud Mode:** Distribute engine execution across cloud instances
- **Solution Ranking:** Multiple solutions presented with confidence scores

## Implementation Timeline

Assuming balanced approach with good code quality:

**Phase 1 (Foundation):** Core infrastructure and module structure
- Create new bash modules
- Add CLI flags
- Update config schema

**Phase 2 (Consensus):** Consensus mode end-to-end
- Worktree isolation
- Parallel execution
- Basic meta-agent

**Phase 3 (Specialization):** Specialization mode
- Rule matching
- Pattern detection
- Adaptive selection

**Phase 4 (Race):** Race mode
- Parallel execution
- First-success logic
- Cleanup

**Phase 5 (Meta-Agent):** Enhanced meta-agent
- Sophisticated prompt templates
- Decision parsing
- Solution merging

**Phase 6 (Metrics):** Performance tracking
- Metrics persistence
- Analytics
- Adaptive learning

**Phase 7 (Polish):** Documentation, testing, refinement
- Unit tests
- Integration tests
- Documentation
- User guides

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Meta-agent makes poor decisions | High | Allow manual override, track decisions, improve prompts |
| Excessive costs from running multiple engines | High | Implement cost limits, smart mode selection, user warnings |
| Engine conflicts/race conditions | Medium | Isolated worktrees, proper locking, cleanup |
| Complexity increases maintenance burden | Medium | Good abstractions, comprehensive docs, tests |
| Users confused by multiple modes | Low | Sane defaults, clear examples, progressive disclosure |
| Performance degradation | Low | Parallel execution, timeouts, resource monitoring |

## Conclusion

This multi-agent architecture transforms Ralphy from a single-engine orchestrator into an intelligent multi-engine system that can:

1. **Leverage engine strengths** through specialization
2. **Increase confidence** through consensus
3. **Optimize speed** through racing
4. **Improve over time** through learning
5. **Manage costs** through smart selection

The bash-based implementation keeps the barrier to entry low while adding powerful capabilities. The modular design allows incremental implementation and easy maintenance.

**Key Principle:** Start simple, add complexity only where it provides clear value.
