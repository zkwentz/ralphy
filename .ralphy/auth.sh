#!/usr/bin/env bash

# ============================================
# Ralphy Authentication & Permission Module
# ============================================
# Handles engine-specific authentication, permission delegation,
# and command construction for all supported AI engines.
#
# Supported Engines:
# - Claude Code
# - OpenCode
# - Cursor Agent
# - Codex
# - Qwen-Code
# - Factory Droid
# ============================================

# Note: We don't use 'set -u' here because we check for unset variables explicitly
set -eo pipefail

# ============================================
# ENGINE CONFIGURATIONS
# ============================================

# Get authentication flags for a specific engine
# Usage: get_engine_auth_flags <engine_name>
get_engine_auth_flags() {
    local engine=$1

    case "$engine" in
        claude)
            echo "--dangerously-skip-permissions --verbose --output-format stream-json"
            ;;
        opencode)
            echo "--format json"
            ;;
        cursor)
            echo "--dangerously-skip-permissions --print --force --output-format stream-json"
            ;;
        qwen)
            echo "--output-format stream-json --approval-mode yolo"
            ;;
        droid)
            echo "--output-format stream-json --auto medium"
            ;;
        codex)
            echo "--full-auto --json"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get environment variables required for a specific engine
# Usage: get_engine_env_vars <engine_name>
get_engine_env_vars() {
    local engine=$1

    case "$engine" in
        opencode)
            echo "OPENCODE_PERMISSION"
            ;;
        codex)
            echo "CODEX_LAST_MESSAGE_FILE"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if engine requires cleanup after execution
# Usage: engine_requires_cleanup <engine_name>
engine_requires_cleanup() {
    local engine=$1

    case "$engine" in
        codex)
            return 0  # true
            ;;
        *)
            return 1  # false
            ;;
    esac
}

# Setup environment variables for engine authentication
# Usage: setup_engine_auth <engine_name> <output_file>
setup_engine_auth() {
    local engine=$1
    local output_file=$2

    case "$engine" in
        opencode)
            # Set OpenCode permission environment variable
            export OPENCODE_PERMISSION='{"*":"allow"}'
            ;;
        codex)
            # Create last message file for Codex
            export CODEX_LAST_MESSAGE_FILE="${output_file}.last"
            rm -f "$CODEX_LAST_MESSAGE_FILE"
            ;;
        *)
            # No special environment setup needed
            ;;
    esac
}

# Cleanup engine authentication artifacts
# Usage: cleanup_engine_auth <engine_name> <output_file>
cleanup_engine_auth() {
    local engine=$1
    local output_file=$2

    case "$engine" in
        opencode)
            # Clean up OpenCode environment
            unset OPENCODE_PERMISSION 2>/dev/null || true
            ;;
        codex)
            # Clean up Codex last message file
            if [[ -n "${CODEX_LAST_MESSAGE_FILE:-}" ]]; then
                rm -f "$CODEX_LAST_MESSAGE_FILE"
                unset CODEX_LAST_MESSAGE_FILE
            fi
            ;;
        *)
            # No cleanup needed
            ;;
    esac
}

# ============================================
# COMMAND CONSTRUCTION
# ============================================

# Build the complete command for an engine with authentication
# Usage: build_engine_command <engine_name> <prompt> <output_file>
build_engine_command() {
    local engine=$1
    local prompt=$2
    local output_file=$3

    # Setup authentication environment
    setup_engine_auth "$engine" "$output_file"

    # Get engine-specific flags
    local auth_flags
    auth_flags=$(get_engine_auth_flags "$engine")

    # Build the command based on engine
    case "$engine" in
        opencode)
            echo "opencode run $auth_flags \"$prompt\""
            ;;
        cursor)
            echo "agent $auth_flags \"$prompt\""
            ;;
        qwen)
            echo "qwen $auth_flags -p \"$prompt\""
            ;;
        droid)
            echo "droid exec $auth_flags \"$prompt\""
            ;;
        codex)
            echo "codex exec $auth_flags --output-last-message \"$CODEX_LAST_MESSAGE_FILE\" \"$prompt\""
            ;;
        claude|*)
            # Default to Claude Code
            echo "claude $auth_flags -p \"$prompt\""
            ;;
    esac
}

# Execute engine command with authentication
# Usage: execute_engine_command <engine_name> <prompt> <output_file>
# Sets global ai_pid variable for background process tracking
execute_engine_command() {
    local engine=$1
    local prompt=$2
    local output_file=$3

    # Setup authentication environment
    setup_engine_auth "$engine" "$output_file"

    # Get engine-specific flags
    local auth_flags
    auth_flags=$(get_engine_auth_flags "$engine")

    # Execute engine-specific command in background
    case "$engine" in
        opencode)
            OPENCODE_PERMISSION='{"*":"allow"}' \
                opencode run $auth_flags "$prompt" > "$output_file" 2>&1 &
            ;;
        cursor)
            agent $auth_flags "$prompt" > "$output_file" 2>&1 &
            ;;
        qwen)
            qwen $auth_flags -p "$prompt" > "$output_file" 2>&1 &
            ;;
        droid)
            droid exec $auth_flags "$prompt" > "$output_file" 2>&1 &
            ;;
        codex)
            codex exec $auth_flags \
                --output-last-message "$CODEX_LAST_MESSAGE_FILE" \
                "$prompt" > "$output_file" 2>&1 &
            ;;
        claude|*)
            claude $auth_flags -p "$prompt" > "$output_file" 2>&1 &
            ;;
    esac

    # Store background process ID
    ai_pid=$!
}

# ============================================
# VALIDATION & UTILITIES
# ============================================

# Validate that an engine is supported
# Usage: validate_engine <engine_name>
validate_engine() {
    local engine=$1
    local supported_engines=("claude" "opencode" "cursor" "qwen" "droid" "codex")

    for supported in "${supported_engines[@]}"; do
        if [[ "$engine" == "$supported" ]]; then
            return 0
        fi
    done

    return 1
}

# Get list of all supported engines
# Usage: get_supported_engines
get_supported_engines() {
    echo "claude opencode cursor qwen droid codex"
}

# Get engine-specific permission description
# Usage: get_engine_permission_info <engine_name>
get_engine_permission_info() {
    local engine=$1

    case "$engine" in
        claude)
            echo "Autonomous mode with --dangerously-skip-permissions flag"
            ;;
        opencode)
            echo "Wildcard allow permission via OPENCODE_PERMISSION environment variable"
            ;;
        cursor)
            echo "Force mode with --dangerously-skip-permissions and --force flags"
            ;;
        qwen)
            echo "YOLO approval mode with --approval-mode yolo flag"
            ;;
        droid)
            echo "Medium autonomy level with --auto medium flag"
            ;;
        codex)
            echo "Full autonomous mode with --full-auto flag"
            ;;
        *)
            echo "Unknown engine"
            ;;
    esac
}

# ============================================
# TESTING & DEBUGGING
# ============================================

# Test engine authentication setup (dry-run mode)
# Usage: test_engine_auth <engine_name>
test_engine_auth() {
    local engine=$1

    if ! validate_engine "$engine"; then
        echo "ERROR: Unsupported engine: $engine" >&2
        return 1
    fi

    echo "Testing authentication for engine: $engine"
    echo "  Flags: $(get_engine_auth_flags "$engine")"
    echo "  Environment: $(get_engine_env_vars "$engine")"
    echo "  Permission: $(get_engine_permission_info "$engine")"
    echo "  Requires cleanup: $(engine_requires_cleanup "$engine" && echo "yes" || echo "no")"

    # Build sample command
    local sample_cmd
    sample_cmd=$(build_engine_command "$engine" "test prompt" "/tmp/test.txt")
    echo "  Sample command: $sample_cmd"

    return 0
}

# Functions are available after sourcing this file
# No need to export them in modern bash
