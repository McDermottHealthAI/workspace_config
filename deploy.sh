#!/usr/bin/env bash
# Deploy this workspace configuration on a fresh Linux machine.
#
# Idempotent: safe to re-run. Existing files are backed up to `<path>.bak.<ts>`
# before being overwritten. Steps that are already done (e.g. starship on PATH,
# tpm cloned) are skipped.
#
# Usage: ./deploy.sh [flags]
#   --skip-apt          don't run `sudo apt-get install ...` steps
#   --skip-fonts        don't download/install the NerdFont
#   --skip-neovim       don't install neovim snap or tree-sitter-cli or nvim config
#   --skip-starship     don't install starship or modify ~/.bashrc
#   --skip-tmux         don't copy tmux config or install tpm
#   --skip-uv           don't install uv
#   --yes               assume yes for any interactive prompt
#   -h, --help          show this help
#
# Requires: bash, curl, git. Sudo is only used for apt.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
TREE_SITTER_VERSION="v0.26.8"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v2.3.3/RobotoMono.zip"

SKIP_APT=0 SKIP_FONTS=0 SKIP_NEOVIM=0 SKIP_STARSHIP=0 SKIP_TMUX=0 SKIP_UV=0 ASSUME_YES=0

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxxx\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-apt)      SKIP_APT=1 ;;
    --skip-fonts)    SKIP_FONTS=1 ;;
    --skip-neovim)   SKIP_NEOVIM=1 ;;
    --skip-starship) SKIP_STARSHIP=1 ;;
    --skip-tmux)     SKIP_TMUX=1 ;;
    --skip-uv)       SKIP_UV=1 ;;
    --yes|-y)        ASSUME_YES=1 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown flag: $1 (try --help)" ;;
  esac
  shift
done

confirm() {
  (( ASSUME_YES == 1 )) && return 0
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

backup_then_copy() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    # Only back up if content would actually change.
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

preflight() {
  [[ "$(uname -s)" == "Linux" ]] || die "this script targets Linux; detected $(uname -s)"
  command -v curl >/dev/null 2>&1 || apt_install curl
  command -v git  >/dev/null 2>&1 || apt_install git
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on PATH; you may need to add it to ~/.bashrc manually" ;;
  esac
}

install_apt_base() {
  apt_install build-essential unzip wget xclip ripgrep
}

install_fonts() {
  (( SKIP_FONTS == 1 )) && { log "skipping fonts"; return 0; }
  local fontdir="$HOME/.local/share/fonts"
  mkdir -p "$fontdir"
  if ls "$fontdir"/RobotoMono*NerdFont*.ttf >/dev/null 2>&1; then
    log "RobotoMono NerdFont already installed"
    return 0
  fi
  log "installing RobotoMono NerdFont"
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  ( cd "$tmp" && curl -LsSfO "$FONT_URL" && unzip -q RobotoMono.zip )
  mv "$tmp"/*.ttf "$fontdir"/
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$fontdir" >/dev/null 2>&1 || true
  fi
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
}

install_neovim() {
  (( SKIP_NEOVIM == 1 )) && { log "skipping neovim"; return 0; }
  if ! command -v snap >/dev/null 2>&1; then
    warn "snap not available; install neovim 0.12+ manually"
  elif ! snap list nvim >/dev/null 2>&1; then
    log "installing neovim via snap (--classic)"
    sudo snap install --classic nvim
  else
    log "neovim snap already installed"
  fi

  local arch; arch="$(uname -m)"
  local asset
  case "$arch" in
    x86_64|amd64)   asset="tree-sitter-linux-x64.gz" ;;
    aarch64|arm64)  asset="tree-sitter-linux-arm64.gz" ;;
    armv7l|armhf)   asset="tree-sitter-linux-arm.gz" ;;
    ppc64le)        asset="tree-sitter-linux-powerpc64.gz" ;;
    *)              die "unsupported arch for tree-sitter-cli: $arch" ;;
  esac

  local ts_bin="$HOME/.local/bin/tree-sitter"
  local need_install=1
  if [[ -x "$ts_bin" ]]; then
    local have; have="$("$ts_bin" --version 2>/dev/null | awk '{print $NF}' || echo 0.0.0)"
    if printf '%s\n%s\n' "0.26.1" "$have" | sort -V -C 2>/dev/null; then
      log "tree-sitter-cli $have already installed"
      need_install=0
    else
      log "tree-sitter-cli $have is too old; upgrading"
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

  warn "launch 'nvim' once to let lazy.nvim install plugins and parsers (this can take a few minutes)"
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
  apt_install tmux
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

main() {
  log "deploying workspace_config from $REPO_DIR"
  preflight
  install_apt_base
  install_fonts
  install_inputrc
  install_starship
  install_neovim
  install_uv
  install_tmux
  log "done. open a new shell to pick up PATH and starship changes."
}

main "$@"
