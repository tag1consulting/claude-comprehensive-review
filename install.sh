#!/usr/bin/env bash
# install.sh — installs the comprehensive-review skill and its agents
# into the current user's Claude Code configuration directory.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

info()    { echo -e "${GREEN}[install]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}   $*"; }
error()   { echo -e "${RED}[error]${NC}  $*" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if ! command -v claude &>/dev/null; then
  error "Claude Code CLI not found. Install it first: https://claude.ai/code"
  exit 1
fi

if ! command -v gh &>/dev/null; then
  warn "gh CLI not found. The skill requires it to create/comment on pull requests."
  warn "Install from: https://cli.github.com/"
  warn "Continuing install — but GitHub operations will fail until gh is available."
fi

if ! command -v git &>/dev/null; then
  error "git not found. The skill requires git to analyze diffs."
  exit 1
fi

if [[ ! -d "$CLAUDE_DIR" ]]; then
  error "Claude config directory not found at $CLAUDE_DIR."
  error "Run Claude Code at least once before installing this skill."
  exit 1
fi

# ---------------------------------------------------------------------------
# Install skill
# ---------------------------------------------------------------------------

SKILL_DEST="$CLAUDE_DIR/skills/comprehensive-review"

mkdir -p "$SKILL_DEST"
cp "$SCRIPT_DIR/skills/comprehensive-review/SKILL.md" "$SKILL_DEST/SKILL.md"
info "Installed skill → $SKILL_DEST/SKILL.md"

# ---------------------------------------------------------------------------
# Install agents
# ---------------------------------------------------------------------------

AGENTS_DEST="$CLAUDE_DIR/agents"
mkdir -p "$AGENTS_DEST"

for agent in pr-summarizer issue-linker security-reviewer architecture-reviewer; do
  src="$SCRIPT_DIR/agents/${agent}.md"
  dest="$AGENTS_DEST/${agent}.md"
  if [[ -f "$dest" ]]; then
    warn "Agent already exists, overwriting: $dest"
  fi
  cp "$src" "$dest"
  info "Installed agent  → $dest"
done

# ---------------------------------------------------------------------------
# Post-install notes
# ---------------------------------------------------------------------------

echo ""
info "Installation complete."
echo ""
echo "  REQUIRED: Enable the pr-review-toolkit plugin in Claude Code:"
echo "    /plugins install pr-review-toolkit@claude-plugins-official"
echo ""
echo "  Usage:"
echo "    /comprehensive-review               # full review, creates/updates PR"
echo "    /comprehensive-review --quick       # skip issue discovery, no diagrams"
echo "    /comprehensive-review --local       # review only, no GitHub operations"
echo "    /comprehensive-review --help        # show all flags"
echo ""
