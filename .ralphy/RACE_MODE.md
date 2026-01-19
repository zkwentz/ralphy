# Race Mode - All Engines Failure Handling

## Overview

This implementation adds comprehensive failure handling for race mode in Ralphy's multi-agent system. When all engines fail to complete a task successfully, the system provides detailed failure reports, metrics tracking, and actionable fallback strategies.

## What is Race Mode?

Race mode is one of three execution modes in Ralphy's multi-agent system:

- **Consensus Mode**: Multiple engines work on the same task, AI judge picks best solution
- **Specialization Mode**: Auto-route tasks to specialized engines based on task type
- **Race Mode**: Engines compete in parallel, first successful solution wins

Race mode is optimized for speed on straightforward tasks like simple bug fixes, formatting, or documentation updates.

## Features Implemented

### 1. Parallel Engine Execution

- Runs multiple AI engines simultaneously on the same task
- Each engine gets an isolated git worktree to avoid conflicts
- Background process monitoring with PID tracking
- Configurable timeout (default: 5 minutes)

### 2. All-Failures Handling

When all engines fail, the system:

1. **Collects Failure Information**
   - Captures exit codes from each engine
   - Saves last 20 lines of output from each engine
   - Records timestamp and task details

2. **Generates Failure Report**
   - Creates detailed summary at `.ralphy/race/<task-id>/failure-summary.txt`
   - Includes task description, engines attempted, and individual failure details
   - Provides easy reference for debugging

3. **Records Metrics**
   - Saves failure to `.ralphy/metrics.json` for analysis
   - Tracks which engines were attempted
   - Records timestamp and failure status

4. **Presents Fallback Strategies**
   - Strategy 1: Retry with different engines (shows unused available engines)
   - Strategy 2: Switch to consensus mode for meta-agent review
   - Strategy 3: Manual intervention with links to failure logs
   - Strategy 4: Suggestion to break task into smaller subtasks

### 3. Validation System

Before accepting a solution, the system validates:

- Changes are present (not empty)
- Tests pass (if configured and not skipped)
- Lint passes (if configured and not skipped)
- Build succeeds (if configured)

### 4. Cleanup

Automatic cleanup of:
- Git worktrees created for each engine
- Temporary branches (`ralphy/race-*`)
- Process cleanup (killing losing engines)

## File Structure

```
.ralphy/
├── engines.sh           # Engine abstraction layer
├── modes.sh             # Multi-engine execution modes (including race mode)
├── test-race-mode.sh    # Test script for race mode with all failures
├── RACE_MODE.md         # This documentation
├── race/                # Race mode execution artifacts
│   └── <task-id>/
│       ├── <engine>/            # Worktree for each engine
│       ├── <engine>-output.log  # Engine output
│       ├── <engine>-exit-code.txt
│       ├── failure-summary.txt  # Generated on all failures
│       └── winner.txt           # Winner name (on success)
└── metrics.json         # Performance metrics database
```

## Implementation Details

### Bash 3 Compatibility

The implementation uses parallel arrays instead of associative arrays to ensure compatibility with bash 3 (default on macOS):

```bash
local engine_pids=()      # Process IDs
local engine_names=()     # Engine names
local engine_status=()    # Status of each engine
local engine_worktrees=() # Worktree paths
```

### Error Handling Strategy

1. **Engine Unavailable**: Skip and continue with available engines
2. **All Engines Unavailable**: Return error immediately
3. **Timeout**: Break monitoring loop, proceed to failure handling
4. **Individual Engine Failure**: Record status, continue monitoring others
5. **All Engines Failed**: Trigger comprehensive failure handling

### Process Flow

```
Start Race Mode
    ├─> Validate engines available
    ├─> Create worktrees for each engine
    ├─> Start engines in parallel (background processes)
    ├─> Monitor for completion
    │   ├─> Check timeout
    │   ├─> Check each engine process
    │   ├─> Validate successful completions
    │   └─> Kill others when winner found
    └─> Handle results
        ├─> Winner found: Apply solution, record metrics
        └─> All failed: Generate report, present strategies
```

## Configuration

### Environment Variables

- `RACE_TIMEOUT`: Timeout in seconds (default: 300)
- `RACE_SKIP_VALIDATION`: Skip validation (default: false)
- `SKIP_TESTS`: Skip running tests during validation
- `SKIP_LINT`: Skip running lint during validation
- `ORIGINAL_DIR`: Original working directory (for worktree operations)

### Config File (.ralphy/config.yaml)

```yaml
engines:
  race:
    max_parallel: 4
    timeout_multiplier: 1.5
    validation_required: true

commands:
  test: "npm test"
  lint: "npm run lint"
  build: "npm run build"
```

## Testing

Run the test script to verify race mode failure handling:

```bash
./.ralphy/test-race-mode.sh
```

The test:
- Creates a temporary git repository
- Simulates multiple engines all failing
- Verifies failure report generation
- Checks metrics recording
- Validates cleanup
- Confirms fallback strategies are presented

## Example Output

When all engines fail, users see:

```
[ERROR] Race mode failure: All engines failed to complete the task successfully
[ERROR] ═══════════════════════════════════════════════════════════
[ERROR] RACE MODE: ALL ENGINES FAILED
[ERROR] ═══════════════════════════════════════════════════════════
[ERROR] Task: Add user authentication
[ERROR] Engines attempted: claude cursor opencode
[ERROR]
[ERROR] Failure summary saved to: .ralphy/race/task-123/failure-summary.txt

Fallback Strategies:
-------------------
1. Retry with different engines: codex qwen droid
   Command: RACE_ENGINES="codex qwen droid" ./ralphy.sh --mode race "Add user authentication"

2. Switch to consensus mode for meta-agent review
   Command: ./ralphy.sh --mode consensus --consensus-engines "claude cursor opencode" "Add user authentication"

3. Manual intervention required
   Review failure logs at: .ralphy/race/task-123/failure-summary.txt
   Review engine outputs at: .ralphy/race/task-123/*-output.log

4. Consider breaking the task into smaller subtasks

[ERROR] Race mode failed. Please review the failure summary and choose a fallback strategy.
```

## Metrics Example

`.ralphy/metrics.json`:

```json
{
  "race_history": [
    {
      "task_id": "task-123",
      "engines": ["claude", "cursor", "opencode"],
      "winner": "none",
      "status": "all_failed",
      "timestamp": "2026-01-19T01:41:58Z"
    }
  ]
}
```

## Future Enhancements

1. **Smart Retry**: Automatically retry with different engines based on failure analysis
2. **Partial Success**: Accept partial solutions if some requirements are met
3. **Cost Optimization**: Early termination if estimated cost exceeds limits
4. **Learning**: Track which engine combinations are most likely to succeed
5. **Parallel Validation**: Validate solutions as they complete, not sequentially
6. **Custom Strategies**: User-defined fallback strategies in config

## Integration with Main Script

To use race mode in `ralphy.sh`:

```bash
# Source the modules
source .ralphy/engines.sh
source .ralphy/modes.sh

# Run race mode
run_race_mode "Add dark mode toggle" "task-123" "claude" "cursor" "opencode"
```

## Troubleshooting

### All engines immediately fail
- Check engine availability with individual commands
- Verify task description is clear and achievable
- Review individual engine logs for specific errors

### Cleanup doesn't complete
- Manually remove worktrees: `git worktree remove <path> --force`
- Delete branches: `git branch -D ralphy/race-*`

### Metrics not recorded
- Ensure jq is installed
- Check write permissions on `.ralphy/metrics.json`
- Verify JSON syntax in metrics file

## References

- Main plan: `MultiAgentPlan.md`
- Engine abstraction: `.ralphy/engines.sh`
- Mode implementations: `.ralphy/modes.sh`
- Test script: `.ralphy/test-race-mode.sh`
