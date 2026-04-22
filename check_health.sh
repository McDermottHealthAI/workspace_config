#!/usr/bin/env bash
# check_health.sh — verify the workspace_config stack installs + runs correctly.
#
# Usage: ./check_health.sh [flags]
#   -v, --verbose          show informational notes (per-plugin list, full allowlist hits)
#   -r, --raw-checkhealth  run nvim's `:checkhealth` and print it unfiltered
#   -h, --help             show this help
#
# Exit 0 if nothing fails outright; non-zero if any required check fails.
# Warnings are counted but do not fail the run.

set -euo pipefail

VERBOSE=0
RAW=0
FAILS=0
WARNS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)         VERBOSE=1 ;;
    -r|--raw-checkhealth) RAW=1 ;;
    -h|--help)            sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                    printf 'unknown flag: %s (try --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m' C_WARN=$'\033[1;33m' C_ERR=$'\033[1;31m'
  C_DIM=$'\033[2m'   C_HDR=$'\033[1;36m'   C_RESET=$'\033[0m'
else
  C_OK='' C_WARN='' C_ERR='' C_DIM='' C_HDR='' C_RESET=''
fi

pass()    { printf '  %sok%s %s\n' "$C_OK"   "$C_RESET" "$*"; }
warn()    { printf '  %s!!%s %s\n' "$C_WARN" "$C_RESET" "$*"; WARNS=$((WARNS+1)); }
fail()    { printf '  %sxx%s %s\n' "$C_ERR"  "$C_RESET" "$*"; FAILS=$((FAILS+1)); }
note()    { (( VERBOSE == 1 )) && printf '  %s..%s %s\n' "$C_DIM" "$C_RESET" "$*" || true; }
section() { printf '\n%s== %s ==%s\n' "$C_HDR" "$*" "$C_RESET"; }

# -------- raw mode: bypass everything below, just dump full :checkhealth --------
if (( RAW == 1 )); then
  tmpf="$(mktemp)"
  trap 'rm -f "$tmpf"' EXIT
  command -v nvim >/dev/null 2>&1 || { printf 'nvim not on PATH\n' >&2; exit 1; }
  nvim --headless -c 'checkhealth' -c "write! $tmpf" -c 'qa!' >/dev/null 2>&1 || true
  cat "$tmpf"
  exit 0
fi

# -------- tools --------
section "External tools"
req() { command -v "$1" >/dev/null 2>&1 && pass "$1 ($(command -v "$1"))" || fail "$1 missing"; }
opt() { command -v "$1" >/dev/null 2>&1 && pass "$1 ($(command -v "$1"))" || warn "$1 missing (optional)"; }
req nvim; req git; req curl; req bash
opt starship; opt tree-sitter; opt uv; opt rg; opt tmux; opt fc-list

# -------- versions --------
section "Versions"
sv_ge() { printf '%s\n%s\n' "$1" "$2" | sort -V -C 2>/dev/null; }  # true iff $2 >= $1

if command -v nvim >/dev/null 2>&1; then
  ver="$(nvim --version | awk 'NR==1{print $NF}' | sed 's/^v//')"
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && sv_ge 0.12.0 "$ver"; then
    pass "nvim $ver >= 0.12.0"
  else
    fail "nvim $ver < 0.12.0 (required for nvim-treesitter main branch)"
  fi
fi

if command -v tree-sitter >/dev/null 2>&1; then
  tsv="$(tree-sitter --version 2>/dev/null | awk 'NR==1{print $NF}' | sed 's/^v//')"
  if [[ "$tsv" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if sv_ge 0.26.1 "$tsv"; then
      pass "tree-sitter-cli $tsv >= 0.26.1"
    else
      fail "tree-sitter-cli $tsv < 0.26.1"
    fi
  else
    warn "tree-sitter-cli --version output unparseable: '$tsv'"
  fi
fi

# -------- fonts --------
section "Fonts"
if command -v fc-list >/dev/null 2>&1; then
  hits="$(fc-list 2>/dev/null | grep -ic 'roboto mono.*nerd font' || true)"
  if (( hits > 0 )); then
    pass "RobotoMono Nerd Font: $hits variant(s) registered with fontconfig"
  else
    warn "RobotoMono Nerd Font not found in fontconfig — icons in lualine/bufferline may render as boxes"
  fi
else
  note "fc-list not available; skipping font check"
fi

# -------- nvim config files --------
section "Neovim config files"
for f in init.lua lua/settings.lua lua/keymaps.lua lua/plugins.lua lua/config/lazy.lua; do
  if [[ -f "$HOME/.config/nvim/$f" ]]; then
    pass "~/.config/nvim/$f"
  else
    fail "~/.config/nvim/$f missing"
  fi
done

# -------- lazy plugins --------
section "Lazy.nvim plugins"
lazy_dir="$HOME/.local/share/nvim/lazy"
if [[ ! -d "$lazy_dir" ]]; then
  fail "$lazy_dir missing — launch nvim at least once to bootstrap lazy.nvim"
else
  plugins_total="$(find "$lazy_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  pass "$plugins_total plugin directories under $lazy_dir"
  if (( VERBOSE == 1 )); then
    find "$lazy_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | while read -r p; do
      note "$p"
    done
  fi
fi

# -------- nvim-treesitter branch + parsers --------
section "nvim-treesitter"
ts_dir="$lazy_dir/nvim-treesitter"
if [[ ! -d "$ts_dir/.git" ]]; then
  fail "$ts_dir missing — lazy.nvim hasn't cloned nvim-treesitter yet"
else
  head_sha="$(git -C "$ts_dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
  if git -C "$ts_dir" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    pass "HEAD $head_sha is reachable from origin/main"
  elif git -C "$ts_dir" merge-base --is-ancestor HEAD origin/master 2>/dev/null; then
    fail "HEAD $head_sha is on archived origin/master — run: rm -rf $ts_dir && nvim"
  else
    warn "HEAD $head_sha not reachable from origin/main or origin/master"
  fi
fi

parser_dir="$HOME/.local/share/nvim/site/parser"
if [[ -d "$parser_dir" ]]; then
  pc="$(find "$parser_dir" -maxdepth 1 -type f -name '*.so' 2>/dev/null | wc -l)"
  if (( pc >= 150 )); then
    pass "$pc compiled treesitter parsers under $parser_dir"
  elif (( pc > 0 )); then
    warn "only $pc parsers compiled so far (full set is ~200) — compile may still be in progress; run nvim and watch :TSLog"
  else
    warn "$parser_dir is empty — launch nvim to kick off parser install"
  fi
else
  warn "$parser_dir missing — launch nvim to kick off parser install"
fi

# -------- headless smoke: load config, inspect plugin state --------
section "Headless smoke test"
if ! command -v nvim >/dev/null 2>&1; then
  note "nvim missing; skipping smoke"
else
  probe="$(mktemp)"
  trap 'rm -f "$probe"' EXIT
  export CHECK_PROBE="$probe"
  # Run one nvim process that loads the full user config, then writes a tiny
  # KEY=VALUE report to $CHECK_PROBE. Stderr is suppressed because lazy.nvim's
  # notifier leaks into it during boot and we only want our own output.
  nvim --headless -c '
lua vim.defer_fn(function()
  local p = os.getenv("CHECK_PROBE")
  local f = io.open(p, "w")
  if not f then vim.cmd("qa!") end
  local function kv(k, v) f:write(k.."="..tostring(v).."\n") end
  local ok_lazy, lazy = pcall(require, "lazy")
  kv("lazy_ok", ok_lazy)
  if ok_lazy then
    local plugins = lazy.plugins() or {}
    kv("plugin_count", #plugins)
    local loaded = 0
    for _, pl in ipairs(plugins) do if pl._.loaded then loaded = loaded + 1 end end
    kv("plugin_loaded", loaded)
  end
  kv("colorscheme", vim.g.colors_name or "")
  kv("ts_require_ok", (pcall(require, "nvim-treesitter")))
  kv("mdx_lang", (vim.treesitter.language.get_lang and vim.treesitter.language.get_lang("mdx")) or "")
  f:close()
  vim.cmd("qa!")
end, 500)' 2>/dev/null || true

  if [[ ! -s "$probe" ]]; then
    fail "headless nvim run produced no probe output — config likely errored on load (try: nvim and look at :messages)"
  else
    # Parse the key=value report
    lazy_ok=$(grep '^lazy_ok=' "$probe" | cut -d= -f2-)
    plugin_count=$(grep '^plugin_count=' "$probe" | cut -d= -f2-)
    plugin_loaded=$(grep '^plugin_loaded=' "$probe" | cut -d= -f2-)
    colorscheme=$(grep '^colorscheme=' "$probe" | cut -d= -f2-)
    ts_require_ok=$(grep '^ts_require_ok=' "$probe" | cut -d= -f2-)
    mdx_lang=$(grep '^mdx_lang=' "$probe" | cut -d= -f2-)

    [[ "$lazy_ok" == "true" ]] && pass "lazy.nvim loads" || fail "lazy.nvim failed to require (lazy_ok=$lazy_ok)"
    if [[ -n "$plugin_count" ]]; then
      pass "lazy knows about $plugin_count plugins (${plugin_loaded:-?} loaded at boot)"
    fi
    [[ "$ts_require_ok" == "true" ]] && pass "require('nvim-treesitter') succeeds (new main-branch API)" \
                                     || fail "require('nvim-treesitter') failed — is lazy on the right branch?"
    if [[ "$colorscheme" == "material" ]]; then
      pass "colorscheme set to 'material'"
    elif [[ -n "$colorscheme" ]]; then
      warn "colorscheme is '$colorscheme', expected 'material'"
    else
      warn "no colorscheme set (material.nvim didn't fire?)"
    fi
    if [[ "$mdx_lang" == "markdown" ]]; then
      pass "mdx filetype registers against the markdown treesitter parser"
    else
      warn "mdx treesitter language alias returned '${mdx_lang:-<nil>}' (expected 'markdown')"
    fi
  fi
fi

# -------- triaged :checkhealth --------
section "Triaged :checkhealth"
tmph="$(mktemp)"
trap 'rm -f "$tmph"' EXIT
if ! command -v nvim >/dev/null 2>&1; then
  note "nvim missing; skipping checkhealth"
else
  nvim --headless -c 'checkhealth' -c "write! $tmph" -c 'qa!' >/dev/null 2>&1 || true
  # Allowlist: patterns we know are noise for this stack and suppress by default.
  # Each regex matches a line fragment on a :checkhealth WARNING/ERROR line.
  # Grouped by origin so additions are easy.
  allow='luarocks|hererocks|version `5\.1`'                      # optional luarocks stack
  allow+='|Go: not avail|cargo: not avail|composer: not avail'   # treesitter parser-build tools
  allow+='|Composer: not avail|PHP: not avail|javac: not avail'
  allow+='|julia: not avail|pip: not avail|r: not avail'
  allow+='|Nvim [0-9.]+ is available'                            # informational upgrade notice
  allow+='|"neovim" npm|Missing "neovim" npm'                    # node provider (unused)
  allow+='|Neovim::Ext|No usable perl'                           # perl provider (unused)
  allow+='|import neovim|Could not load Python'                  # python provider (unused)
  allow+='|neovim-ruby-host'                                     # ruby provider (unused)
  allow+='|kitty|wezterm|ghostty'                                # snacks image deps
  allow+='|None of the tools found|`fd`'                         # snacks picker deps (picker disabled)
  allow+='|mmdc|Mermaid'                                         # snacks mermaid rendering
  allow+='|lazygit|which-key'                                    # optional integrations
  allow+='|SQLite3'                                              # snacks history backend
  allow+='|Snacks\.'                                             # snacks opt-in UIs
  allow+='|setup \{disabled\}|setup did not run'                 # disabled snacks modules
  allow+='|Missing Treesitter languages|Image rendering'         # snacks image

  # Pull out filtered lines into an array so fail/warn run in the main shell
  # (piping into `while read` puts the loop body in a subshell, so FAILS/WARNS
  # updates wouldn't propagate).
  mapfile -t offenders < <(grep -E '^- (❌ ERROR|⚠️ WARNING)' "$tmph" | grep -vE "$allow" || true)

  if (( ${#offenders[@]} == 0 )); then
    pass "no un-allowlisted errors/warnings in :checkhealth"
  else
    for line in "${offenders[@]}"; do
      if [[ "$line" == *'❌'* ]]; then
        fail "${line#- ❌ ERROR }"
      else
        warn "${line#- ⚠️ WARNING }"
      fi
    done
  fi

  if (( VERBOSE == 1 )); then
    suppressed="$(grep -E '^- (❌ ERROR|⚠️ WARNING)' "$tmph" | grep -cE "$allow" || true)"
    note "$suppressed checkhealth lines suppressed by allowlist (run with --raw-checkhealth for full output)"
  fi
fi

# -------- summary --------
printf '\n'
if (( FAILS == 0 )); then
  printf '%s== summary ==%s stack looks healthy (%d failures, %d warnings)\n' "$C_HDR" "$C_RESET" "$FAILS" "$WARNS"
  exit 0
else
  printf '%s== summary ==%s %d failures, %d warnings — see entries marked xx above\n' "$C_HDR" "$C_RESET" "$FAILS" "$WARNS"
  exit 1
fi
