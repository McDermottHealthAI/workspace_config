# Configuration Files & Development Setup
This repository details my typical development stack. It is designed for use on remote servers (often without
GUI access) and largely uses terminal based tools. It is current as of 4/19/2023.

The basic stack of tools I use are:
  * Terminal: I'm trying [warp](https://www.warp.dev/) right now.
  * `bash` and [starship](https://starship.rs/) for shell (note warp undoes this, but it is still a good
    configuration for other shells).
  * `Neovim` for editing.
  * Github Copilot integrated into neovim.
  * [uv](https://docs.astral.sh/uv/getting-started/installation/) for python package management.

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
The only notable change in the bash setup is that I add the following to my `.inputrc` such that the up-arrow
and down-arrow perform reverse history search given the text currently typed.
```
## arrow up
"\e[A":history-search-backward
## arrow down
"\e[B":history-search-forward
```

## Starship
After installing starship and moving `starship.toml` to `.config/`, you also need to enable it. Add this to
your `~/.bashrc` or equivalent:

```bash
eval "$(starship init bash)"
```

I also add some aliases stored in the `~/.bash_aliases` file.

# Neovim
Install neovim via snap:
```
sudo snap install --classic nvim
```

For some of the neovim pakages, you'll also need to install `nodejs` and `npm` as well as `gcc`. To do so,
install `build-essential` via apt:
```
sudo apt-get install build-essential
```

Then visit [this page](https://nodejs.org/en/download/) to install the latest version of nodejs and npm.

Neovim packages are managed by [lazy.nvim](https://github.com/folke/lazy.nvim). The configuration files I use
with `lazy.nvm` are in the `.config/nvim` directory and need to be copied to the local `.config/nvim`
directory on your machine.

To install lazy.nvim, follow the instructions here: https://lazy.folke.io/installation

Additionally, for clipboard integration, on linux you must have something like `xclip` installed: `sudo apt-get
install xclip`. Otherwise you can remove the line setting the clipboard to `unamedplus` in the `settings.lua`
file.

# `uv` Setup
Run `curl -LsSf https://astral.sh/uv/install.sh | sh`.
