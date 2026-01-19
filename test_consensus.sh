#!/bin/bash

# Test script for consensus mode with 2 engines (similar results)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}================================${RESET}"
echo -e "${BLUE}Consensus Mode Test Suite${RESET}"
echo -e "${BLUE}================================${RESET}"
echo ""

# Test 1: Check if modules exist
echo -e "${YELLOW}Test 1: Checking if modules exist...${RESET}"
if [[ -f ".ralphy/modes.sh" ]]; then
  echo -e "${GREEN}✓ .ralphy/modes.sh exists${RESET}"
else
  echo -e "${RED}✗ .ralphy/modes.sh missing${RESET}"
  exit 1
fi

if [[ -f ".ralphy/meta-agent.sh" ]]; then
  echo -e "${GREEN}✓ .ralphy/meta-agent.sh exists${RESET}"
else
  echo -e "${RED}✗ .ralphy/meta-agent.sh missing${RESET}"
  exit 1
fi
echo ""

# Test 2: Check if modules are sourceable (syntax check)
echo -e "${YELLOW}Test 2: Checking module syntax...${RESET}"
if bash -n .ralphy/modes.sh; then
  echo -e "${GREEN}✓ .ralphy/modes.sh has valid syntax${RESET}"
else
  echo -e "${RED}✗ .ralphy/modes.sh has syntax errors${RESET}"
  exit 1
fi

if bash -n .ralphy/meta-agent.sh; then
  echo -e "${GREEN}✓ .ralphy/meta-agent.sh has valid syntax${RESET}"
else
  echo -e "${RED}✗ .ralphy/meta-agent.sh has syntax errors${RESET}"
  exit 1
fi
echo ""

# Test 3: Check if ralphy.sh has valid syntax
echo -e "${YELLOW}Test 3: Checking ralphy.sh syntax...${RESET}"
if bash -n ralphy.sh; then
  echo -e "${GREEN}✓ ralphy.sh has valid syntax${RESET}"
else
  echo -e "${RED}✗ ralphy.sh has syntax errors${RESET}"
  exit 1
fi
echo ""

# Test 4: Check if consensus mode CLI flags are recognized
echo -e "${YELLOW}Test 4: Checking CLI flags...${RESET}"
if ./ralphy.sh --help 2>&1 | grep -q "MULTI-ENGINE OPTIONS"; then
  echo -e "${GREEN}✓ Multi-engine options appear in help${RESET}"
else
  echo -e "${RED}✗ Multi-engine options not in help${RESET}"
  exit 1
fi

if ./ralphy.sh --help 2>&1 | grep -q "consensus-engines"; then
  echo -e "${GREEN}✓ --consensus-engines flag documented${RESET}"
else
  echo -e "${RED}✗ --consensus-engines flag not documented${RESET}"
  exit 1
fi
echo ""

# Test 5: Check if functions are defined
echo -e "${YELLOW}Test 5: Checking if functions are defined...${RESET}"

# Source the modules manually to check functions
source .ralphy/modes.sh 2>/dev/null || true
source .ralphy/meta-agent.sh 2>/dev/null || true

if declare -f run_consensus_mode > /dev/null; then
  echo -e "${GREEN}✓ run_consensus_mode function defined${RESET}"
else
  echo -e "${RED}✗ run_consensus_mode function not defined${RESET}"
  exit 1
fi

if declare -f compare_consensus_solutions > /dev/null; then
  echo -e "${GREEN}✓ compare_consensus_solutions function defined${RESET}"
else
  echo -e "${RED}✗ compare_consensus_solutions function not defined${RESET}"
  exit 1
fi

if declare -f prepare_meta_prompt > /dev/null; then
  echo -e "${GREEN}✓ prepare_meta_prompt function defined${RESET}"
else
  echo -e "${RED}✗ prepare_meta_prompt function not defined${RESET}"
  exit 1
fi
echo ""

# Test 6: Check consensus directory structure
echo -e "${YELLOW}Test 6: Testing consensus directory creation...${RESET}"
if [[ -d ".ralphy/consensus" ]]; then
  echo -e "${YELLOW}  .ralphy/consensus already exists (from previous run)${RESET}"
else
  echo -e "${GREEN}✓ .ralphy/consensus will be created on first run${RESET}"
fi
echo ""

# Summary
echo -e "${GREEN}================================${RESET}"
echo -e "${GREEN}All basic tests passed!${RESET}"
echo -e "${GREEN}================================${RESET}"
echo ""
echo -e "${BLUE}Consensus mode features:${RESET}"
echo "  - CLI flags for --mode consensus and --consensus-engines"
echo "  - Support for running 2+ engines in parallel on same task"
echo "  - Solution comparison to detect similar results"
echo "  - Auto-acceptance when solutions are similar (>80% similarity)"
echo "  - Git worktree isolation for each engine"
echo "  - Meta-agent integration (for future different-results case)"
echo ""
echo -e "${YELLOW}Next steps to test consensus mode:${RESET}"
echo "  1. Run: ./ralphy.sh \"add a test function\" --consensus-engines \"claude,cursor\""
echo "  2. Check .ralphy/consensus/ for execution logs"
echo "  3. Verify that solutions are compared and merged"
echo ""
