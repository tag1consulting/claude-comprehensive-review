#!/usr/bin/env bash
# install.sh — installs comprehensive-review as a Claude Code plugin from a
# published release on GitHub.
#
# Usage: install.sh [--version <tag|main>]
#
#   (no flags)          Install the latest release from GitHub
#   --version <tag>     Install a specific release (e.g. v1.0.0)
#   --version main      Install the development version from the main branch
#
# For most users, the recommended install method is from inside Claude Code:
#   /plugins install comprehensive-review@tag1consulting
#
# This script exists for cases where the marketplace install isn't convenient
# (CI provisioning, scripted setups, pinning to a specific tag). It installs
# under the same cache/tag1consulting/ namespace as the marketplace install,
# so the two are interchangeable.

set -euo pipefail

REPO="tag1consulting/claude-comprehensive-review"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
PLUGINS_DIR="$CLAUDE_DIR/plugins"

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
    --help|-h)
      echo "Usage: install.sh [--version <tag|main>]"
      echo ""
      echo "  (no flags)          Install the latest release from GitHub"
      echo "  --version <tag>     Install a specific release (e.g. v1.0.0)"
      echo "  --version main      Install the development version from main branch"
      echo ""
      echo "Installs comprehensive-review as a Claude Code plugin under"
      echo "~/.claude/plugins/cache/tag1consulting/. Agents are registered under"
      echo "the comprehensive-review: namespace, matching the marketplace install."
      echo ""
      echo "For most users, prefer the marketplace install inside Claude Code:"
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

if ! command -v curl &>/dev/null; then
  error "curl not found. Required to download files from GitHub."
  exit 1
fi

if [[ ! -d "$CLAUDE_DIR" ]]; then
  error "Claude config directory not found at $CLAUDE_DIR."
  error "Run Claude Code at least once before installing this plugin."
  exit 1
fi

if [[ -e "$PLUGINS_DIR" && ! -d "$PLUGINS_DIR" ]]; then
  error "$PLUGINS_DIR exists but is not a directory."
  exit 1
fi

if [[ ! -d "$PLUGINS_DIR" ]]; then
  error "Claude plugins directory not found at $PLUGINS_DIR."
  error "Run Claude Code at least once, then install any plugin from the marketplace before using this script."
  exit 1
fi

INSTALLED_PLUGINS_FILE="$PLUGINS_DIR/installed_plugins.json"

if [[ ! -f "$INSTALLED_PLUGINS_FILE" ]]; then
  echo '{"version":2,"plugins":{}}' > "$INSTALLED_PLUGINS_FILE"
  info "Created $INSTALLED_PLUGINS_FILE (first plugin registration)"
fi

# ---------------------------------------------------------------------------
# Resolve the ref (tag or branch) to install from
# ---------------------------------------------------------------------------

REF=""

if [[ "$VERSION" == "main" ]]; then
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
# Determine plugin version string and install path
# ---------------------------------------------------------------------------

if [[ "$REF" =~ ^v[0-9] ]]; then
  PLUGIN_VERSION="${REF#v}"  # strip leading 'v'
else
  PLUGIN_VERSION="$REF"
fi

PLUGIN_OWNER="tag1consulting"
PLUGIN_NAME="comprehensive-review"
PLUGIN_KEY="comprehensive-review@tag1consulting"
PLUGIN_DIR="$PLUGINS_DIR/cache/$PLUGIN_OWNER/$PLUGIN_NAME/$PLUGIN_VERSION"
info "Plugin install path: $PLUGIN_DIR"

# ---------------------------------------------------------------------------
# Remove stale versioned cache directories
# ---------------------------------------------------------------------------
# Old install runs leave sibling directories (e.g. "1.6.1" from a prior
# install) under the same owner/name path. These cause the /plugins UI to
# load metadata from the wrong directory. Clean them up before installing.

PLUGIN_PARENT="$PLUGINS_DIR/cache/$PLUGIN_OWNER/$PLUGIN_NAME"
if [[ -d "$PLUGIN_PARENT" ]]; then
  for stale_dir in "$PLUGIN_PARENT"/*/; do
    [[ -d "$stale_dir" ]] || continue
    stale_ver=$(basename "$stale_dir")
    if [[ "$stale_ver" != "$PLUGIN_VERSION" ]]; then
      rm -rf "$stale_dir"
      info "Removed stale plugin cache → $stale_dir"
    fi
  done
fi

# Remove the legacy tag1consulting-local namespace if present. Earlier
# versions of this script installed there; the directory now only causes
# confusion in /plugins listings.
LEGACY_LOCAL_OWNER="$PLUGINS_DIR/cache/tag1consulting-local"
if [[ -d "$LEGACY_LOCAL_OWNER" ]]; then
  rm -rf "$LEGACY_LOCAL_OWNER"
  info "Removed legacy local-namespace cache → $LEGACY_LOCAL_OWNER"
fi

# ---------------------------------------------------------------------------
# Remove legacy flat-path install (pre-v1.6.1)
# ---------------------------------------------------------------------------
# Prior versions of install.sh copied agents flat into ~/.claude/agents/ and
# the skill into ~/.claude/skills/comprehensive-review/. These bare-name agent
# files conflict with the plugin-namespaced registration and must be removed.

LEGACY_SKILL_DIR="$CLAUDE_DIR/skills/comprehensive-review"
LEGACY_AGENTS_DIR="$CLAUDE_DIR/agents"

if [[ -f "$LEGACY_SKILL_DIR/SKILL.md" ]]; then
  rm -rf "$LEGACY_SKILL_DIR"
  info "Removed legacy skill directory → $LEGACY_SKILL_DIR"
fi

for agent in pr-summarizer issue-linker security-reviewer architecture-reviewer blind-hunter edge-case-hunter adversarial-general; do
  legacy_agent="$LEGACY_AGENTS_DIR/${agent}.md"
  if [[ -f "$legacy_agent" ]]; then
    rm -f "$legacy_agent"
    info "Removed legacy agent file  → $legacy_agent"
  fi
done

# ---------------------------------------------------------------------------
# Helper: download one file from GitHub
# ---------------------------------------------------------------------------

install_file() {
  local rel_path="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
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
PROFILES=$(curl -fsSL "https://api.github.com/repos/${REPO}/contents/skills/comprehensive-review/language-profiles?ref=${REF}" 2>/dev/null \
  | jq -r '.[] | select(.name | endswith(".md")) | .name' 2>/dev/null || echo "")
if [[ -z "$PROFILES" ]]; then
  # Fallback: hardcoded baseline list
  PROFILES="go.md python.md typescript.md javascript.md php.md ruby.md rust.md java.md c++.md shell.md csharp.md kotlin.md swift.md scala.md lua.md perl.md sql.md terraform.md yaml.md"
fi
for profile in $PROFILES; do
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
  "$INSTALLED_PLUGINS_FILE") || { error "Failed to parse installed_plugins.json (jq error)"; exit 1; }

_tmp_plugins=$(mktemp "${INSTALLED_PLUGINS_FILE}.XXXXXX")
echo "$UPDATED" > "$_tmp_plugins" && mv "$_tmp_plugins" "$INSTALLED_PLUGINS_FILE"
info "Registered plugin → $INSTALLED_PLUGINS_FILE (key: $PLUGIN_KEY)"

# ---------------------------------------------------------------------------
# Enable plugin in settings.json
# ---------------------------------------------------------------------------
# Claude Code will not load a plugin unless it appears in enabledPlugins.
# installed_plugins.json is a registry; settings.json is the on/off switch.

SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  SETTINGS_UPDATED=$(jq --arg key "$PLUGIN_KEY" '.enabledPlugins[$key] = true' "$SETTINGS_FILE") \
    || { warn "Could not update enabledPlugins in settings.json (jq error) — enable the plugin manually inside Claude Code."; }
  if [[ -n "$SETTINGS_UPDATED" ]]; then
    _tmp_settings=$(mktemp "${SETTINGS_FILE}.XXXXXX")
    echo "$SETTINGS_UPDATED" > "$_tmp_settings" && mv "$_tmp_settings" "$SETTINGS_FILE"
    info "Enabled plugin   → $SETTINGS_FILE (key: $PLUGIN_KEY)"
  fi
else
  warn "settings.json not found at $SETTINGS_FILE — plugin registered but may not be enabled."
  warn "Enable manually inside Claude Code: /plugins enable comprehensive-review@tag1consulting"
fi

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
info "Installed: ${BOLD}${REF}${NC}"
echo ""
echo "  Restart Claude Code to activate the plugin, then:"
echo "    /comprehensive-review               # full review"
echo "    /comprehensive-review --quick       # skip expensive agents, ~75% cheaper"
echo "    /comprehensive-review --no-post     # review only, no remote operations"
echo "    /comprehensive-review --help        # show all flags"
echo ""
warn "NOTE: For most users, the recommended install is inside Claude Code:"
warn "  /plugins install comprehensive-review@tag1consulting"
echo ""
