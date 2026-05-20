#!/usr/bin/env bash
# install.sh — installs comprehensive-review as a local plugin
# into the Claude Code plugin cache directory.
#
# Usage: install.sh [--version <tag|main>] [--local]
#
#   (no flags)          Install the latest release from GitHub
#   --version <tag>     Install a specific release (e.g. v1.0.0)
#   --version main      Install the development version from the main branch
#   --local             Install from local files (for development / dogfood)
#
# For end users, the recommended install method is:
#   /plugins install comprehensive-review@tag1consulting
#
# This script installs comprehensive-review as a local plugin so that agents
# are registered under the same comprehensive-review: namespace as a marketplace
# install. This is the supported path for local development and testing.

set -euo pipefail

REPO="tag1consulting/claude-comprehensive-review"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
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
      echo ""
      echo "This script installs comprehensive-review as a local Claude Code plugin"
      echo "under ~/.claude/plugins/cache/tag1consulting-local/. Agents are registered"
      echo "under the comprehensive-review: namespace, matching the marketplace install."
      echo ""
      echo "For end users, prefer the marketplace install inside Claude Code:"
      echo "  /plugins install comprehensive-review@tag1consulting"
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if ! command -v claude &>/dev/null; then
  error "Claude Code CLI not found. Install it first: https://claude.ai/code"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  error "jq not found. Required to update plugin registration."
  error "Install from: https://stedolan.github.io/jq/"
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
  error "Run Claude Code at least once before installing this plugin."
  exit 1
fi

if [[ ! -d "$PLUGINS_DIR" ]]; then
  error "Claude plugins directory not found at $PLUGINS_DIR."
  error "Run Claude Code at least once, then install any plugin from the marketplace before using this script."
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
# Determine plugin version string
# ---------------------------------------------------------------------------

if [[ "$LOCAL" == true ]]; then
  # Read version from local plugin.json
  PLUGIN_VERSION=$(jq -r '.version' "$SCRIPT_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo "local")
elif [[ "$REF" =~ ^v[0-9] ]]; then
  PLUGIN_VERSION="${REF#v}"  # strip leading 'v'
else
  PLUGIN_VERSION="$REF"
fi

# Plugin install path: use tag1consulting-local owner to avoid collision with marketplace install
PLUGIN_OWNER="tag1consulting-local"
PLUGIN_NAME="comprehensive-review"
PLUGIN_KEY="comprehensive-review@tag1consulting"
PLUGIN_DIR="$PLUGINS_DIR/cache/$PLUGIN_OWNER/$PLUGIN_NAME/$PLUGIN_VERSION"
INSTALLED_PLUGINS_FILE="$PLUGINS_DIR/installed_plugins.json"

info "Plugin install path: $PLUGIN_DIR"

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
# Install plugin manifest
# ---------------------------------------------------------------------------

install_file ".claude-plugin/plugin.json" "$PLUGIN_DIR/.claude-plugin/plugin.json"
info "Installed manifest → $PLUGIN_DIR/.claude-plugin/plugin.json"

# ---------------------------------------------------------------------------
# Install skill
# ---------------------------------------------------------------------------

install_file "skills/comprehensive-review/SKILL.md" \
  "$PLUGIN_DIR/skills/comprehensive-review/SKILL.md"
install_file "skills/comprehensive-review/HELP.md" \
  "$PLUGIN_DIR/skills/comprehensive-review/HELP.md"
install_file "skills/comprehensive-review/PROVIDERS.md" \
  "$PLUGIN_DIR/skills/comprehensive-review/PROVIDERS.md"
install_file "skills/comprehensive-review/SEVERITY.md" \
  "$PLUGIN_DIR/skills/comprehensive-review/SEVERITY.md"
install_file "skills/comprehensive-review/suppressions.json" \
  "$PLUGIN_DIR/skills/comprehensive-review/suppressions.json"

# Install language profiles
mkdir -p "$PLUGIN_DIR/skills/comprehensive-review/language-profiles"
for profile in go.md python.md typescript.md php.md ruby.md rust.md java.md c++.md shell.md; do
  install_file "skills/comprehensive-review/language-profiles/${profile}" \
    "$PLUGIN_DIR/skills/comprehensive-review/language-profiles/${profile}"
done

info "Installed skill  → $PLUGIN_DIR/skills/comprehensive-review/"

# ---------------------------------------------------------------------------
# Install agents
# ---------------------------------------------------------------------------

mkdir -p "$PLUGIN_DIR/agents"
for agent in pr-summarizer issue-linker security-reviewer architecture-reviewer blind-hunter edge-case-hunter adversarial-general; do
  install_file "agents/${agent}.md" "$PLUGIN_DIR/agents/${agent}.md"
  info "Installed agent  → $PLUGIN_DIR/agents/${agent}.md"
done

# ---------------------------------------------------------------------------
# Install scripts
# ---------------------------------------------------------------------------

mkdir -p "$PLUGIN_DIR/skills/comprehensive-review/scripts"
for script in run-cve-check.sh run-shellcheck.sh run-semgrep.sh run-trufflehog.sh run-ruff.sh run-golangci-lint.sh run-checkov.sh; do
  install_file "skills/comprehensive-review/scripts/${script}" \
    "$PLUGIN_DIR/skills/comprehensive-review/scripts/${script}"
  chmod +x "$PLUGIN_DIR/skills/comprehensive-review/scripts/${script}"
  info "Installed script → $PLUGIN_DIR/skills/comprehensive-review/scripts/${script}"
done

# ---------------------------------------------------------------------------
# Register plugin in installed_plugins.json
# ---------------------------------------------------------------------------

NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

if [[ ! -f "$INSTALLED_PLUGINS_FILE" ]]; then
  error "installed_plugins.json not found at $INSTALLED_PLUGINS_FILE."
  error "Run Claude Code at least once and install any marketplace plugin before using this script."
  exit 1
fi

# Upsert: set the plugin entry to a single-element array with this install.
# Uses jq to idempotently replace any existing entry for PLUGIN_KEY.
UPDATED=$(jq \
  --arg key "$PLUGIN_KEY" \
  --arg path "$PLUGIN_DIR" \
  --arg ver "$PLUGIN_VERSION" \
  --arg now "$NOW" \
  '.plugins[$key] = [{
    "scope": "user",
    "installPath": $path,
    "version": $ver,
    "installedAt": $now,
    "lastUpdated": $now
  }]' \
  "$INSTALLED_PLUGINS_FILE")

echo "$UPDATED" > "$INSTALLED_PLUGINS_FILE"
info "Registered plugin → $INSTALLED_PLUGINS_FILE (key: $PLUGIN_KEY)"

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
if [[ "$LOCAL" == true ]]; then
  info "Installed local version ${BOLD}${PLUGIN_VERSION}${NC} as plugin."
else
  info "Installed: ${BOLD}${REF}${NC}"
fi
echo ""
echo "  Restart Claude Code to activate the plugin, then:"
echo "    /comprehensive-review               # full review, everything local"
echo "    /comprehensive-review --quick       # skip expensive agents, ~75% cheaper"
echo "    /comprehensive-review --local       # review only, no GitHub operations"
echo "    /comprehensive-review --help        # show all flags"
echo ""
warn "NOTE: For end users, the recommended install is inside Claude Code:"
warn "  /plugins install comprehensive-review@tag1consulting"
echo ""
