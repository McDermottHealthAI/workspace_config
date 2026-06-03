# Configuration Files & Development Setup
This repository details my typical development stack. It is designed for use on remote servers (often without
GUI access) and largely uses terminal based tools. It is current as of 2026-04-21.

The basic stack of tools I use are:
  * Terminal: I'm trying [warp](https://www.warp.dev/) right now.
  * `bash` and [starship](https://starship.rs/) for shell (note warp undoes this, but it is still a good
    configuration for other shells).
  * `Neovim` for editing.
  * Github Copilot integrated into neovim.
  * [Claude Code](https://docs.claude.com/en/docs/claude-code) as my terminal-based AI coding agent,
    with `gh`, web search, and library-docs integrations — see [Claude Code](#claude-code-ai-coding-agent)
    below and [`claude-code.md`](claude-code.md) for the full setup.
  * [uv](https://docs.astral.sh/uv/getting-started/installation/) for python package management.
  * [ripgrep](https://github.com/BurntSushi/ripgrep) for searching files quickly.

On ssh connections I use [tmux](https://github.com/tmux/tmux/wiki) for terminal multiplexing; I don't use this
locally as the warp terminal handles this for me.

# Quickstart: `deploy.sh`
If you just want the whole stack on a fresh Linux machine, clone this repo and run:

```bash
./deploy.sh
```

`deploy.sh` targets **Debian/Ubuntu** (it uses `apt-get`/`dpkg` and optionally `snap`); on other distros run
it with `--skip-apt --skip-neovim` and install those parts via your distro's package manager, then re-run
without the skip flags to handle the dotfile copies. The script is idempotent (safe to re-run) and performs
every step described in the sections below: apt packages, fonts, `~/.inputrc`, starship, neovim +
`tree-sitter-cli`, nvim config, `uv`, tmux + tpm, ripgrep, and [Claude Code](#claude-code-ai-coding-agent)
(`gh` + MCP servers). Each section can be skipped with a flag — see `./deploy.sh --help`. To install just the
Claude Code piece on a machine that already has the rest, run `./deploy.sh --only-claude`. Existing dotfiles
are backed up to `<path>.bak.<timestamp>` before being overwritten. You still need `sudo` for the apt and
snap steps.

# Verifying the install: `check_health.sh`
After deploying (or any time something feels off), run:

```bash
./check_health.sh
```

It checks external tools, version gates (Neovim ≥ 0.12, `tree-sitter-cli` ≥ 0.26.1), font registration,
nvim config files, lazy.nvim plugin state, the nvim-treesitter branch + parser-compile count, and runs a
headless `nvim` to confirm the config loads cleanly and the `material` colorscheme + `mdx` filetype alias
are wired up. It also runs `:checkhealth` but **filters out the known-noisy warnings for this stack**
(unused language providers, optional snacks integrations, terminal-graphics protocol checks, etc.). Pass
`--verbose` for a plugin list and suppressed-line count, or `--raw-checkhealth` to see the full unfiltered
`:checkhealth` output. Exit code is 0 when clean, non-zero on any real failure.

The remainder of this README documents what `deploy.sh` does, step by step, for anyone who prefers to run
the commands manually or needs to debug a failure.

# Migrating an existing install
If you've deployed this repo on a machine before the nvim-treesitter `main`-branch migration (pre-2026-04)
and `nvim` now errors on launch with *"failed to run config for nvim-treesitter"*, follow these steps:

1. Pull the latest config from this repo and re-copy `~/.config/nvim`:
   ```bash
   git pull
   cp -r .config/nvim ~/.config/nvim   # or just re-run ./deploy.sh
   ```
2. Install `tree-sitter-cli` ≥ 0.26.1 (see the [tree-sitter-cli](#tree-sitter-cli) section below, or let
   `deploy.sh` do it).
3. Make sure your `nvim` is 0.12.0 or later (`nvim --version`). The `snap install --classic nvim` channel is
   fine; older apt-packaged builds will need upgrading.
4. Force lazy.nvim to switch `nvim-treesitter` from the archived `master` branch to `main`. The cleanest way:
   ```bash
   rm -rf ~/.local/share/nvim/lazy/nvim-treesitter
   ```
   **Warning:** this discards anything you may have edited or checked out inside that directory. If you
   maintain local patches there, use `git -C ~/.local/share/nvim/lazy/nvim-treesitter checkout main`
   instead. Then launch `nvim` — lazy.nvim will re-clone (or switch) to the pinned `main` branch and the
   new `config` callback will start installing and compiling parsers automatically in the background.
   Budget 20-40 minutes for the full parser set to finish on first run (longer on cold aarch64 boxes).
5. Watch `:messages`, `:Lazy log`, and `:TSLog` for install errors. If a specific parser fails, fix the
   underlying toolchain issue and relaunch `nvim` (or run `:TSInstall <lang>`) to retry just that one.

Background on why this migration was needed is in
[issue #2](https://github.com/McDermottHealthAI/workspace_config/issues/2).

# Curl
Install `curl` via apt:
```
sudo apt-get install curl
```

# Bash Setup
## Patched Font Support
I use a [NerdFont](https://www.nerdfonts.com/#home) on the terminal. In particular,
[RobotoMono](https://github.com/ryanoasis/nerd-fonts/releases/download/v2.3.3/RobotoMono.zip).

To install, simply download the zip file and extract the font files inside to your local user font folder
(e.g., `~/.local/share/fonts/` on linux). You then need to configure your shell to use that font by default:

```
mkdir tmp_fonts
mkdir -p ~/.local/share/fonts
cd tmp_fonts
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.3.3/RobotoMono.zip
unzip RobotoMono.zip
mv *.ttf ~/.local/share/fonts
cd ..
rm -r tmp_fonts
```

You may need to restart things to get this to work. This step is necessary for some packages in `neovim` to work properly.

## InputRC
The only notable change in the bash setup is that I add the following to `~/.inputrc` such that the up-arrow
and down-arrow perform reverse history search given the text currently typed.
```
## arrow up
"\e[A":history-search-backward
## arrow down
"\e[B":history-search-forward
```

Copy the file from this repo to your home directory:
```bash
cp .inputrc ~/.inputrc
```

## Starship
Install starship via the official installer (no sudo required; installs to `~/.local/bin`):

```bash
curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir ~/.local/bin
```

Copy the config into place and enable starship in your shell:

```bash
mkdir -p ~/.config
cp starship.toml ~/.config/starship.toml
echo 'eval "$(starship init bash)"' >> ~/.bashrc
```

I also add some aliases stored in the `~/.bash_aliases` file.

# Neovim
Install neovim via snap:
```
sudo snap install --classic nvim
```

Neovim **0.12.0 or later** is required because `nvim-treesitter` is pinned to its rewritten `main` branch
(see [#2](https://github.com/McDermottHealthAI/workspace_config/issues/2)); the `--classic nvim` snap tracks
the latest stable, which is fine. Verify with `nvim --version` and upgrade if you're on an older build.

For some of the neovim pakages, you'll also need to install `nodejs` and `npm` as well as `gcc`. To do so,
install `build-essential` via apt:
```
sudo apt-get install build-essential
```

Then visit [this page](https://nodejs.org/en/download/) to install the latest version of nodejs and npm.

## tree-sitter-cli
`nvim-treesitter` (on its `main` branch) compiles parsers from source and requires the
[`tree-sitter-cli`](https://github.com/tree-sitter/tree-sitter) binary, **version 0.26.1 or later**, on your
`PATH`. Ubuntu's `apt` package is too old (0.20.x at the time of writing), so install from the upstream
GitHub release instead. On x86_64:

```bash
TS_VER=v0.26.8
curl -LsSf "https://github.com/tree-sitter/tree-sitter/releases/download/${TS_VER}/tree-sitter-linux-x64.gz" \
  | gunzip > ~/.local/bin/tree-sitter
chmod +x ~/.local/bin/tree-sitter
```

On aarch64 (e.g., DGX Spark / Grace), swap `tree-sitter-linux-x64.gz` for `tree-sitter-linux-arm64.gz`. Make
sure `~/.local/bin` is on your `PATH` — most distros include it for interactive bash via `~/.profile`, but
non-login shells or stripped-down setups may need an explicit `export PATH="$HOME/.local/bin:$PATH"` in
`~/.bashrc`. Do **not** install `tree-sitter-cli` via `npm` — the new plugin explicitly rejects the npm
distribution.

Neovim packages are managed by [lazy.nvim](https://github.com/folke/lazy.nvim). The configuration files I use
with `lazy.nvim` are in the `.config/nvim` directory and need to be copied to the local `~/.config/nvim`
directory on your machine:

```bash
mkdir -p ~/.config
cp -r .config/nvim ~/.config/nvim
```

The `config/lazy.lua` file bootstraps lazy.nvim on first launch, so you do not need to install it
separately. Launching `nvim` for the first time will clone lazy.nvim and install all plugins listed in
`plugins.lua`.

Additionally, for clipboard integration, on linux you must have something like `xclip` installed: `sudo apt-get
install xclip`. Otherwise you can remove the line setting the clipboard to `unamedplus` in the `settings.lua`
file.

# `uv` Setup
Run `curl -LsSf https://astral.sh/uv/install.sh | sh`.

# `tmux` Setup (only for remote servers)
My `tmux` configuration is in the `.tmux.conf` file. Copy this file to your home directory on the
remote server:

```bash
cp .tmux.conf ~/.tmux.conf
```

To manage tmux plugins, I use [tpm](https://github.com/tmux-plugins/tpm). Install it via:

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then start tmux and press `prefix + I` (prefix is `C-x` in this config) to fetch plugins.

# Ripgrep Setup
Install `ripgrep` via apt:
```bash
sudo apt-get install ripgrep
```

# Claude Code (AI coding agent)
[Claude Code](https://docs.claude.com/en/docs/claude-code) is Anthropic's terminal-based AI coding
agent. I run it with three integrations that make it dramatically more capable: the `gh` CLI (so it
can manage GitHub for you), a **web search** server (so it can look things up online), and a
**library-docs** server (so it reads real, current documentation instead of guessing). It also runs
in **auto mode**, where routine, safe actions happen without stopping to ask you for permission each
time.

`deploy.sh` can install and configure all of this for you with `./deploy.sh` (or just this part with
`./deploy.sh --only-claude`). Full command-by-command details and the exact settings are in
[`claude-code.md`](claude-code.md).

## What you need to set up yourself, on the web
A few things can't be scripted — they require **you** to create accounts and copy keys from a
website, because they're tied to your personal logins. You only do these once. **No coding
experience is required**; each step is "open a web page, click a few buttons, copy a value." Do
these *before* running the Claude Code part of `deploy.sh`: the script prompts you to paste your
Brave key inline, and reminds you (at the end) of the two browser sign-ins — GitHub and Claude — you
need to finish by hand.

1. **A Claude account (required).** Claude Code needs an Anthropic login.
   * Go to **https://claude.ai** and create an account (or sign in). A paid plan (Pro/Max) or
     API credits is required to actually use Claude Code — see
     https://www.anthropic.com/pricing.
   * That's all you do on the web for this one. The first time you launch `claude` in a terminal it
     will open your browser to finish signing in — just click **Allow**.

2. **A GitHub account + login (required if you use GitHub).** This lets Claude open pull requests,
   read issues, and check CI for you via the `gh` tool.
   * If you don't have one, sign up at **https://github.com/signup**.
   * `deploy.sh` installs the `gh` tool but leaves the login to you (it's a browser step). When it
     reminds you, run `gh auth login`: it prints a short code and opens
     **https://github.com/login/device** — type the code, click **Authorize**, and you're done.

3. **A Brave Search API key (recommended — gives Claude web search).** Free tier is plenty.
   * Go to **https://brave.com/search/api/** and click to get started / sign up.
   * Create a subscription on the **Free** plan (it may ask for a card to verify, but the free tier
     is not charged).
   * Open the **API Keys** page in your Brave dashboard, create a key, and **copy the long string**
     it gives you. Keep it somewhere safe for a moment.
   * Paste it in when `deploy.sh` asks for your Brave API key (or set it later — see
     [`claude-code.md`](claude-code.md)). Treat this key like a password; don't share it or commit
     it to a repo.

4. **Library docs — Context7 (recommended — no account needed).** This one is fully automatic and
   needs **no signup and no key**. `deploy.sh` sets it up for you. It lets Claude pull up-to-date
   documentation for whatever library you're using.

5. **Connected apps like Slack, Gmail, Google Drive, Figma (optional).** These are extra and *not*
   required to code. If you ever want Claude to read your Slack or Gmail, you add them later from
   inside Claude Code, which opens a browser "Allow access?" page for each. See the
   account-level servers note in [`claude-code.md`](claude-code.md).

If you skip the optional items (3–5), Claude Code still works fully for editing code and using
GitHub — you just lose web search and connected apps. You can always add them later by re-running
`./deploy.sh --only-claude`.
