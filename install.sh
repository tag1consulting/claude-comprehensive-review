#!/usr/bin/env bash
# install.sh — installs the comprehensive-review skill and its agents
# into the current user's Claude Code configuration directory.
#
# Usage: install.sh [--version <tag|main>] [--local]
#
#   (no flags)          Install the latest release from GitHub
#   --version <tag>     Install a specific release (e.g. v1.0.0)
#   --version main      Install the development version from the main branch
#   --local             Install from local files (skips GitHub; for development)

set -euo pipefail

REPO="tag1consulting/claude-comprehensive-review"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[install]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}   $*"; }
error() { echo -e "${RED}[error]${NC}  $*" >&2; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

VERSION=""
LOCAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-v)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        error "--version requires an argument (e.g. v1.0.0 or main)"
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --local)
      LOCAL=true
      shift
      ;;
    --help|-h)
      echo "Usage: install.sh [--version <tag|main>] [--local]"
      echo ""
      echo "  (no flags)          Install the latest release from GitHub"
      echo "  --version <tag>     Install a specific release (e.g. v1.0.0)"
      echo "  --version main      Install the development version from main branch"
      echo "  --local             Install from local files (for development)"
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Recommend plugin install
# ---------------------------------------------------------------------------

info ""
info "NOTE: Plugin install is now the recommended method:"
info "  /plugins install comprehensive-review@tag1consulting"
info ""
info "Continuing with legacy file-copy installation..."
info ""

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

if [[ "$LOCAL" == false ]] && ! command -v curl &>/dev/null; then
  error "curl not found. Required to download files from GitHub."
  exit 1
fi

if [[ ! -d "$CLAUDE_DIR" ]]; then
  error "Claude config directory not found at $CLAUDE_DIR."
  error "Run Claude Code at least once before installing this skill."
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the ref (tag or branch) to install from
# ---------------------------------------------------------------------------

REF=""

if [[ "$LOCAL" == true ]]; then
  info "Installing from local files"
elif [[ "$VERSION" == "main" ]]; then
  REF="main"
  info "Installing development version from main branch"
elif [[ -n "$VERSION" ]]; then
  if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    error "Invalid version format: '$VERSION'"
    error "Expected a semver tag (e.g. v1.0.0) or 'main'"
    exit 1
  fi
  REF="$VERSION"
  info "Installing version ${BOLD}$REF${NC}"
else
  # Auto-detect latest release
  info "Checking for latest release..."

  # Try gh CLI first (most reliable when authed)
  LATEST=$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")

  # Fall back to the public GitHub API
  if [[ -z "$LATEST" || "$LATEST" == "null" ]]; then
    LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
      | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
      || echo "")
  fi

  # Discard any extracted value that doesn't look like a semver tag
  if [[ -n "$LATEST" && ! "$LATEST" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    LATEST=""
  fi

  if [[ -n "$LATEST" ]]; then
    REF="$LATEST"
    info "Installing latest release: ${BOLD}$REF${NC}"
  else
    REF="main"
    warn "No releases found. Installing from main branch (development version)."
  fi
fi

# ---------------------------------------------------------------------------
# Helper: install one file from GitHub or local
# ---------------------------------------------------------------------------

install_file() {
  local rel_path="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ "$LOCAL" == true ]]; then
    cp "$SCRIPT_DIR/$rel_path" "$dest"
  else
    local url="https://raw.githubusercontent.com/${REPO}/${REF}/${rel_path}"
    local tmp
    tmp=$(mktemp "${dest}.XXXXXX")
    if ! curl -fsSL "$url" -o "$tmp"; then
      rm -f "$tmp"
      error "Failed to download: $url"
      error "Check that the version '${REF}' exists: https://github.com/${REPO}/releases"
      exit 1
    fi
    mv "$tmp" "$dest"
  fi
}

# ---------------------------------------------------------------------------
# Install skill
# ---------------------------------------------------------------------------

install_file "skills/comprehensive-review/SKILL.md" \
  "$CLAUDE_DIR/skills/comprehensive-review/SKILL.md"
install_file "skills/comprehensive-review/HELP.md" \
  "$CLAUDE_DIR/skills/comprehensive-review/HELP.md"
info "Installed skill  → $CLAUDE_DIR/skills/comprehensive-review/"

# ---------------------------------------------------------------------------
# Install agents
# ---------------------------------------------------------------------------

for agent in pr-summarizer issue-linker security-reviewer architecture-reviewer blind-hunter edge-case-hunter; do
  dest="$CLAUDE_DIR/agents/${agent}.md"
  if [[ -f "$dest" ]]; then
    warn "Agent already exists, overwriting: $dest"
  fi
  install_file "agents/${agent}.md" "$dest"
  info "Installed agent  → $dest"
done

# ---------------------------------------------------------------------------
# Install pr-review-toolkit plugin
# ---------------------------------------------------------------------------

info "Installing pr-review-toolkit plugin..."
if claude --print "/plugins install pr-review-toolkit@claude-plugins-official" &>/dev/null; then
  info "Installed plugin: pr-review-toolkit@claude-plugins-official"
else
  warn "Could not auto-install plugin. Run this manually inside Claude Code:"
  warn "  /plugins install pr-review-toolkit@claude-plugins-official"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
info "Installation complete."
if [[ "$LOCAL" != true ]]; then
  info "Installed: ${BOLD}${REF}${NC}"
fi
echo ""
echo "  Usage:"
echo "    /comprehensive-review               # full review, everything local"
echo "    /comprehensive-review --quick       # skip expensive agents, ~75% cheaper"
echo "    /comprehensive-review --local       # review only, no GitHub operations"
echo "    /comprehensive-review --help        # show all flags"
echo ""
