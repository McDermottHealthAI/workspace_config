#!/usr/bin/env bash
# Deploy this workspace configuration on a fresh Linux or macOS machine.
#
# Idempotent: safe to re-run. Existing files are backed up to `<path>.bak.<ts>`
# before being overwritten. Steps that are already done (e.g. starship on PATH,
# tpm cloned) are skipped.
#
# Usage: ./deploy.sh [flags]
#   --skip-apt          don't run OS package-manager installs (apt on Linux,
#                       Homebrew on macOS)
#   --skip-fonts        don't download/install the NerdFont
#   --skip-neovim       don't install neovim snap or tree-sitter-cli or nvim config
#   --skip-starship     don't install starship or modify ~/.bashrc
#   --skip-tmux         don't copy tmux config or install tpm
#   --skip-uv           don't install uv
#   --skip-claude       don't install Claude Code / gh or configure MCP servers
#   --only-claude       only run the Claude Code setup (skip all other steps)
#   -h, --help          show this help
#
# Requires: bash, curl, git. On Linux, package installs use apt (sudo) and
# neovim uses snap; on macOS they use Homebrew (no sudo). The Claude Code step
# additionally uses Node.js/npm (auto-installed via the OS package manager).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"   # Linux or Darwin (macOS)
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
TREE_SITTER_VERSION="v0.26.8"
TREE_SITTER_MIN_VERSION="0.26.1"
FONT_VERSION="v2.3.3"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/RobotoMono.zip"

SKIP_APT=0 SKIP_FONTS=0 SKIP_NEOVIM=0 SKIP_STARSHIP=0 SKIP_TMUX=0 SKIP_UV=0
SKIP_CLAUDE=0 ONLY_CLAUDE=0

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_RESET=$'\033[0m'
else
  C_BLUE='' C_YELLOW='' C_RED='' C_RESET=''
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
warn() { printf '%s!!!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sxxx%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-apt)      SKIP_APT=1 ;;
    --skip-fonts)    SKIP_FONTS=1 ;;
    --skip-neovim)   SKIP_NEOVIM=1 ;;
    --skip-starship) SKIP_STARSHIP=1 ;;
    --skip-tmux)     SKIP_TMUX=1 ;;
    --skip-uv)       SKIP_UV=1 ;;
    --skip-claude)   SKIP_CLAUDE=1 ;;
    --only-claude)   ONLY_CLAUDE=1 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown flag: $1 (try --help)" ;;
  esac
  shift
done

backup_then_copy() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    # Symlink (e.g., from a stow-managed dotfile tree): preserve it by moving
    # rather than overwriting with cp, which would dereference and stomp it.
    mv "$dst" "${dst}.bak.${TIMESTAMP}"
    log "backed up existing symlink $dst -> ${dst}.bak.${TIMESTAMP}"
  elif [[ -e "$dst" ]]; then
    # Regular file: only back up if content would actually change.
    if ! cmp -s "$src" "$dst" 2>/dev/null; then
      cp -a "$dst" "${dst}.bak.${TIMESTAMP}"
      log "backed up existing $dst -> ${dst}.bak.${TIMESTAMP}"
    fi
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

apt_install() {
  (( SKIP_APT == 1 )) && { warn "skipping apt install: $*"; return 0; }
  local missing=()
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done
  if (( ${#missing[@]} == 0 )); then
    log "apt packages already installed: $*"
    return 0
  fi
  log "installing via apt: ${missing[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y "${missing[@]}"
}

brew_install() {
  (( SKIP_APT == 1 )) && { warn "skipping brew install: $*"; return 0; }
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not found; cannot install: $*. Install it from https://brew.sh and re-run."
    return 0
  fi
  local missing=()
  for pkg in "$@"; do
    brew list --formula "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if (( ${#missing[@]} == 0 )); then
    log "brew packages already installed: $*"
    return 0
  fi
  log "installing via brew: ${missing[*]}"
  brew install "${missing[@]}"
}

# OS-agnostic package install: apt on Linux, Homebrew on macOS. Package names are
# assumed identical across the two (true for the formulas this script uses:
# ripgrep, tmux, gh, neovim, node). Callers needing per-OS names branch on $OS.
pkg_install() {
  if [[ "$OS" == Darwin ]]; then
    brew_install "$@"
  else
    apt_install "$@"
  fi
}

preflight() {
  case "$OS" in
    Linux)
      if (( SKIP_APT == 1 )); then
        # apt steps are off, so any required dep that's missing won't be auto-installed —
        # fail loudly here instead of crashing later in an unrelated step.
        command -v curl >/dev/null 2>&1 || die "--skip-apt was set but 'curl' is missing; install it manually first"
        command -v git  >/dev/null 2>&1 || die "--skip-apt was set but 'git' is missing; install it manually first"
      else
        command -v apt-get >/dev/null 2>&1 || die "'apt-get' not found; this script targets Debian/Ubuntu on Linux. Re-run with --skip-apt --skip-neovim and install those parts via your distro's package manager."
        command -v curl >/dev/null 2>&1 || apt_install curl
        command -v git  >/dev/null 2>&1 || apt_install git
      fi
      ;;
    Darwin)
      # macOS ships curl; git comes with the Xcode Command Line Tools. Homebrew
      # is the package manager — warn (don't die) if absent so the dotfile copies
      # and curl-based installers (starship, uv) still run.
      command -v git  >/dev/null 2>&1 || die "'git' not found; install the Xcode Command Line Tools first: xcode-select --install"
      command -v curl >/dev/null 2>&1 || die "'curl' not found (unexpected on macOS)"
      if (( SKIP_APT == 0 )) && ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found; package installs (ripgrep, tmux, neovim, gh, node) will be skipped. Install it from https://brew.sh and re-run. Dotfile copies and curl-based installers will still run."
      fi
      ;;
    *)
      die "this script supports Linux and macOS; detected $OS"
      ;;
  esac
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on PATH; you may need to add it to your shell rc (~/.bashrc or ~/.zshrc) manually" ;;
  esac
}

install_base_packages() {
  if [[ "$OS" == Darwin ]]; then
    # macOS: compilers come from the Xcode Command Line Tools (not a brew
    # formula); unzip is built in; clipboard works natively in nvim (pbcopy), so
    # no xclip. Just ripgrep via brew.
    if ! xcode-select -p >/dev/null 2>&1; then
      warn "Xcode Command Line Tools not detected; if compiles fail run: xcode-select --install"
    fi
    brew_install ripgrep
  else
    apt_install build-essential unzip wget xclip ripgrep
  fi
}

install_fonts() {
  (( SKIP_FONTS == 1 )) && { log "skipping fonts"; return 0; }
  # macOS reads user fonts from ~/Library/Fonts; Linux from ~/.local/share/fonts.
  local fontdir
  if [[ "$OS" == Darwin ]]; then fontdir="$HOME/Library/Fonts"; else fontdir="$HOME/.local/share/fonts"; fi
  # Version-pinned sentinel. The archive ships files like
  # `Roboto Mono Bold Nerd Font Complete.ttf` (with spaces), which makes
  # glob-based idempotency checks fragile; a sentinel sidesteps that and
  # also lets us detect when we need to refresh for a new FONT_VERSION.
  local sentinel="$fontdir/.robotomono-nerdfont-${FONT_VERSION}.installed"
  mkdir -p "$fontdir"
  if [[ -f "$sentinel" ]]; then
    log "RobotoMono NerdFont ${FONT_VERSION} already installed"
    return 0
  fi
  log "installing RobotoMono NerdFont ${FONT_VERSION}"
  local tmp; tmp="$(mktemp -d)"
  # Don't use `trap ... RETURN` for cleanup: bash's RETURN trap is shell-global,
  # not function-scoped, so it would fire on every later function return with
  # $tmp out of scope and trip `set -u`. Clean up inline; /tmp leaks on the
  # curl/unzip failure path are self-cleaning via systemd-tmpfiles.
  ( cd "$tmp" && curl -LsSfO "$FONT_URL" && unzip -q RobotoMono.zip )
  mv "$tmp"/*.ttf "$fontdir"/
  rm -rf "$tmp"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$fontdir" >/dev/null 2>&1 || true
  fi
  touch "$sentinel"
}

install_inputrc() {
  backup_then_copy "$REPO_DIR/.inputrc" "$HOME/.inputrc"
  log "installed ~/.inputrc"
}

install_starship() {
  (( SKIP_STARSHIP == 1 )) && { log "skipping starship"; return 0; }
  if ! command -v starship >/dev/null 2>&1; then
    log "installing starship to ~/.local/bin"
    curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
  else
    log "starship already on PATH"
  fi
  backup_then_copy "$REPO_DIR/starship.toml" "$HOME/.config/starship.toml"
  if ! grep -Fq 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
    log "enabling starship in ~/.bashrc"
    printf '\n# starship prompt\neval "$(starship init bash)"\n' >> "$HOME/.bashrc"
  else
    log "starship already wired into ~/.bashrc"
  fi
  if [[ "$OS" == Darwin ]]; then
    warn "wired starship into ~/.bashrc; macOS defaults to zsh — if you use zsh, add 'eval \"\$(starship init zsh)\"' to ~/.zshrc instead"
  fi
}

install_neovim() {
  (( SKIP_NEOVIM == 1 )) && { log "skipping neovim"; return 0; }
  if [[ "$OS" == Darwin ]]; then
    if command -v nvim >/dev/null 2>&1; then
      log "neovim already installed ($(nvim --version | head -1))"
    else
      log "installing neovim via brew"
      brew_install neovim
    fi
  elif ! command -v snap >/dev/null 2>&1; then
    warn "snap not available; install neovim 0.12+ manually"
  elif ! snap list nvim >/dev/null 2>&1; then
    log "installing neovim via snap (--classic)"
    sudo snap install --classic nvim
  else
    log "neovim snap already installed"
  fi

  local arch; arch="$(uname -m)"
  local asset
  case "$OS-$arch" in
    Linux-x86_64|Linux-amd64)   asset="tree-sitter-linux-x64.gz" ;;
    Linux-aarch64|Linux-arm64)  asset="tree-sitter-linux-arm64.gz" ;;
    Linux-armv7l|Linux-armhf)   asset="tree-sitter-linux-arm.gz" ;;
    Linux-ppc64le)              asset="tree-sitter-linux-powerpc64.gz" ;;
    Darwin-x86_64)              asset="tree-sitter-macos-x64.gz" ;;
    Darwin-arm64)               asset="tree-sitter-macos-arm64.gz" ;;
    *)                          die "unsupported OS/arch for tree-sitter-cli: $OS/$arch" ;;
  esac

  local ts_bin="$HOME/.local/bin/tree-sitter"
  local need_install=1
  if [[ -x "$ts_bin" ]]; then
    # Output format across versions is "tree-sitter X.Y.Z" on stdout line 1.
    # Pull the last token of line 1 and strip a leading `v` if some future
    # release adds one. Validate the shape before comparing.
    local have
    have="$("$ts_bin" --version 2>/dev/null | awk 'NR==1{print $NF}' | sed 's/^v//')"
    if [[ "$have" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      if printf '%s\n%s\n' "$TREE_SITTER_MIN_VERSION" "$have" | sort -V -C 2>/dev/null; then
        log "tree-sitter-cli $have already installed"
        need_install=0
      else
        log "tree-sitter-cli $have is older than $TREE_SITTER_MIN_VERSION; upgrading"
      fi
    else
      warn "tree-sitter-cli present at $ts_bin but --version output is unparseable; reinstalling"
    fi
  fi
  if (( need_install == 1 )); then
    log "installing tree-sitter-cli $TREE_SITTER_VERSION ($arch)"
    curl -LsSf "https://github.com/tree-sitter/tree-sitter/releases/download/${TREE_SITTER_VERSION}/${asset}" \
      | gunzip > "$ts_bin"
    chmod +x "$ts_bin"
  fi

  log "installing nvim config to ~/.config/nvim"
  mkdir -p "$HOME/.config"
  if [[ -d "$HOME/.config/nvim" ]]; then
    if diff -rq "$REPO_DIR/.config/nvim" "$HOME/.config/nvim" >/dev/null 2>&1; then
      log "~/.config/nvim already matches repo"
    else
      local bak="$HOME/.config/nvim.bak.${TIMESTAMP}"
      mv "$HOME/.config/nvim" "$bak"
      log "backed up existing ~/.config/nvim -> $bak"
      cp -r "$REPO_DIR/.config/nvim" "$HOME/.config/nvim"
    fi
  else
    cp -r "$REPO_DIR/.config/nvim" "$HOME/.config/nvim"
  fi

  warn "launch 'nvim' once to let lazy.nvim install plugins; nvim-treesitter will then compile all parsers in the background — budget 20-40 minutes on first run (cold aarch64 hosts fall on the higher end). Watch progress with ':Lazy log' and ':TSLog'."
}

install_uv() {
  (( SKIP_UV == 1 )) && { log "skipping uv"; return 0; }
  if command -v uv >/dev/null 2>&1; then
    log "uv already installed ($(uv --version))"
    return 0
  fi
  log "installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_tmux() {
  (( SKIP_TMUX == 1 )) && { log "skipping tmux"; return 0; }
  pkg_install tmux
  backup_then_copy "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir/.git" ]]; then
    log "tpm already cloned"
  else
    log "cloning tpm"
    git clone --quiet https://github.com/tmux-plugins/tpm "$tpm_dir"
  fi
  warn "inside tmux, press 'prefix + I' (prefix is C-x) to fetch plugins"
}

# --- Claude Code -------------------------------------------------------------

# True if `claude mcp list` already reports a server named "$1".
claude_mcp_present() {
  claude mcp list 2>/dev/null | grep -q "^$1:"
}

install_gh() {
  if command -v gh >/dev/null 2>&1; then
    log "gh (GitHub CLI) already installed ($(gh --version 2>/dev/null | head -1))"
    return 0
  fi
  if (( SKIP_APT == 1 )); then
    warn "gh not installed and package installs skipped; install GitHub CLI manually: https://github.com/cli/cli#installation"
    return 0
  fi
  if [[ "$OS" == Darwin ]]; then
    brew_install gh
    command -v gh >/dev/null 2>&1 || warn "could not install gh via brew; see https://github.com/cli/cli#installation"
    return 0
  fi
  log "installing gh (GitHub CLI) via apt"
  sudo apt-get update -qq
  if ! sudo apt-get install -y gh; then
    warn "apt could not install 'gh'. Install it from the official repo: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
  fi
}

# Major version of `node` on PATH, or empty string if node is absent/unparseable.
node_major() {
  command -v node >/dev/null 2>&1 || { printf ''; return; }
  node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1 | grep -E '^[0-9]+$' || printf ''
}

ensure_node() {
  local major; major="$(node_major)"
  if [[ -n "$major" ]] && (( major >= 18 )); then
    log "node $(node --version) already installed"
    return 0
  fi
  if [[ -n "$major" ]]; then
    warn "node $(node --version) is older than v18 (Claude Code needs >=18); install a newer Node from https://nodejs.org or via nvm, then re-run ./deploy.sh --only-claude"
    return 0
  fi
  if (( SKIP_APT == 1 )); then
    warn "node/npm missing and package installs skipped; install Node.js >=18 manually (https://nodejs.org), then re-run ./deploy.sh --only-claude"
    return 0
  fi
  if [[ "$OS" == Darwin ]]; then
    brew_install node            # Homebrew's node formula is current (>=18)
  else
    apt_install nodejs npm
  fi
  major="$(node_major)"
  if [[ -z "$major" ]] || (( major < 18 )); then
    warn "installed node $(node --version 2>/dev/null || echo '?'), which is older than v18; Claude Code may fail to install or run. Install a newer Node from https://nodejs.org or via nvm, then re-run ./deploy.sh --only-claude"
  fi
}

configure_mcp() {
  command -v claude >/dev/null 2>&1 || return 0

  # Library docs (no API key needed).
  if claude_mcp_present context7; then
    log "context7 MCP already configured"
  else
    log "adding context7 MCP (library docs)"
    claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp \
      || warn "failed to add context7 MCP; add it later with: claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp"
  fi

  # Web search (needs a Brave Search API key).
  if claude_mcp_present brave-search; then
    log "brave-search MCP already configured"
    return 0
  fi
  local key="${BRAVE_API_KEY:-}"
  if [[ -z "$key" && -t 0 ]]; then
    printf 'Enter your Brave Search API key for web search (blank to skip): '
    read -r key || key=""
  fi
  if [[ -n "$key" ]]; then
    log "adding brave-search MCP (web search)"
    claude mcp add brave-search --scope user -e BRAVE_API_KEY="$key" \
      -- npx -y @modelcontextprotocol/server-brave-search \
      || warn "failed to add brave-search MCP; add it later (see claude-code.md)"
  else
    warn "no Brave API key provided; skipping web-search MCP. Add it later with: claude mcp add brave-search --scope user -e BRAVE_API_KEY=your-key -- npx -y @modelcontextprotocol/server-brave-search"
  fi
}

install_claude() {
  (( SKIP_CLAUDE == 1 )) && { log "skipping Claude Code"; return 0; }

  install_gh
  ensure_node

  if command -v claude >/dev/null 2>&1; then
    log "Claude Code already installed ($(claude --version 2>/dev/null || echo present))"
  elif command -v npm >/dev/null 2>&1; then
    log "installing Claude Code via npm (-g)"
    if ! npm install -g @anthropic-ai/claude-code; then
      warn "global npm install failed (often a permissions issue). Retry with 'sudo npm install -g @anthropic-ai/claude-code', or configure a user-writable npm prefix, then re-run ./deploy.sh --only-claude"
    fi
  else
    warn "npm not available; cannot install Claude Code. Install Node.js >=18 and re-run ./deploy.sh --only-claude"
  fi

  # Global defaults (auto mode + permission allow/deny). Non-destructive: never
  # clobber an existing settings.json, which the user may have customized.
  local settings="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"
  if [[ -e "$settings" ]]; then
    warn "~/.claude/settings.json already exists; leaving it untouched. Compare against claude/settings.json in this repo for the recommended auto-mode + permissions config."
  else
    cp "$REPO_DIR/claude/settings.json" "$settings"
    log "installed ~/.claude/settings.json (auto mode + permission allow/deny lists)"
  fi

  configure_mcp

  if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
    warn "GitHub not authenticated yet — run 'gh auth login' (browser device-code flow)"
  fi
  warn "finish setup by running 'claude' once and signing in when the browser opens. See claude-code.md and the README 'Claude Code' section for the web accounts/keys you need."
}

main() {
  log "deploying workspace_config from $REPO_DIR"
  preflight
  if (( ONLY_CLAUDE == 0 )); then
    install_base_packages
    install_fonts
    install_inputrc
    install_starship
    install_neovim
    install_uv
    install_tmux
  else
    log "--only-claude: skipping all non-Claude steps"
  fi
  install_claude
  log "done. open a new shell to pick up PATH and starship changes."
}

main "$@"
