# Configuration Files & Development Setup
This repository details my typical development stack. It is designed for use on remote servers (often without
GUI access) and largely uses terminal based tools. It is current as of 2026-04-21.

The basic stack of tools I use are:
  * Terminal: I'm trying [warp](https://www.warp.dev/) right now.
  * `bash` and [starship](https://starship.rs/) for shell (note warp undoes this, but it is still a good
    configuration for other shells).
  * `Neovim` for editing.
  * Github Copilot integrated into neovim.
  * [uv](https://docs.astral.sh/uv/getting-started/installation/) for python package management.
  * [ripgrep](https://github.com/BurntSushi/ripgrep) for searching files quickly.

On ssh connections I use [tmux](https://github.com/tmux/tmux/wiki) for terminal multiplexing; I don't use this
locally as the warp terminal handles this for me.

# Quickstart: `deploy.sh`
If you just want the whole stack on a fresh Linux machine, clone this repo and run:

```bash
./deploy.sh
```

The script is idempotent (safe to re-run) and performs every step described in the sections below:
apt packages, fonts, `~/.inputrc`, starship, neovim + `tree-sitter-cli`, nvim config, `uv`, tmux + tpm, and
ripgrep. Each section can be skipped with a flag — see `./deploy.sh --help`. Existing dotfiles are backed up
to `<path>.bak.<timestamp>` before being overwritten. You still need `sudo` for the apt and snap steps.

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
   new `config` callback will kick off `:TSInstall all` asynchronously. Budget 20-40 minutes for the full
   parser set to compile on first run (longer on cold aarch64 boxes). Watch progress with `:Lazy log` and
   `:TSLog`.
5. Watch `:messages` and `:Lazy log` for install errors. If a specific parser fails, `:TSInstall <lang>`
   retries just that one.

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
sure `~/.local/bin` is on your `PATH` (starship's installer above already puts things there). Do **not**
install `tree-sitter-cli` via `npm` — the new plugin explicitly rejects the npm distribution.

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
