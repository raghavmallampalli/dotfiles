# dotfiles
These are the scripts I use to set up my Linux environment: CLI and dev tools for web development and ML, my dotfiles, and my desktop.

| | Ubuntu / Debian | Fedora | Arch | No sudo (e.g. compute clusters) |
|---|---|---|---|---|
| CLI tools + dotfiles (`install_cli.sh`, `setup.sh`) | ✅ | ✅ | ✅ | ✅ |
| Desktop (`install_desktop.sh`) | — | ✅ | — | — |

I only maintain one desktop at a time, currently Fedora with niri + DankMaterialShell.

These scripts are largely inspired by https://github.com/rsnk96/Ubuntu-Setup-Scripts. Some of the code is taken directly from there. 
For a list of useful commands and tips, check out [help](Help.md)

I like to see icons on my terminal. Make sure to install and use a NerdFont for your terminal emulator if you want the icons to show up. I use [FircaCode](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip)

## Testing on Docker
If you want to test this setup on Docker, a `Dockerfile` is provided. It supports Ubuntu, Fedora and Arch Linux base images.

### Build the Docker image:
For Ubuntu (default):
```bash
docker build -t dotfiles-test-ubuntu .
```

For Arch Linux:
```bash
docker build --build-arg BASE_IMAGE=archlinux:latest -t dotfiles-test-arch .
```

For Fedora:
```bash
docker build --build-arg BASE_IMAGE=fedora:latest -t dotfiles-test-fedora .
```

### Run the container:
```bash
docker run -it --name dotfiles-test dotfiles-test-ubuntu
# or
docker run -it --name dotfiles-test dotfiles-test-arch
```
The images cover the CLI scripts only; `install_desktop.sh` needs a real Fedora machine.

### Automated Verification
You can also run the automated test script which builds the images and runs the installation scripts for Ubuntu, Fedora and Arch:
```bash
./test_install.sh
```
Check `install_test.log` for the output.

## Setup scripts

- `install_cli.sh`: shell, CLI, monitoring and dev tools. Everything it can comes from [mise](https://mise.jdx.dev) (Python CLIs through uv), installed into `$HOME`, so it works without sudo. With sudo it also installs the few tools mise can't provide (zsh, ssh, ...) via apt, dnf or pacman. It ends with a report of anything missing. The tool list is `dotfiles/mise/.config/mise/config.toml`.
- `setup.sh`: links the dotfiles (chezmoi), sets up zsh, oh-my-zsh, tmux plugins, SSH key and GitHub login. Without zsh, it loads mise from `.bashrc` instead.
- `install_desktop.sh` (**Fedora only**): niri + DankMaterialShell, apps, services, snapper snapshots around dnf, hibernation. Run it first on a new desktop.

**New server or cluster** (no sudo):
```bash
./install_cli.sh --sudo-access no
./setup.sh --sudo-access no
```
If downloads hit GitHub rate limits, set `GITHUB_TOKEN` first.

**New Fedora desktop:**
```bash
./install_desktop.sh
./install_cli.sh --sudo-access yes
./setup.sh
./install_desktop.sh   # second run builds iio-niri, which needs cargo from install_cli.sh
```

Update all CLI tools later with `mise up` (desktops also run it weekly on a timer).

> IMPORTANT: `bash` shell is replaced by a `zsh+Oh-My-Zsh` configuration.

### Dotfiles management (chezmoi)
[chezmoi](https://www.chezmoi.io) uses this repo as its source (`.chezmoiroot` points it at `home/`). Each entry in `home/` is a symlink from `$HOME` into `dotfiles/`, so it behaves like stow: editing a config in `$HOME` edits the repo, and new files in a linked directory (e.g. `~/.config/niri`) land in the repo too.
- **Add a config**: put it under `dotfiles/<app>/`, add a matching `symlink_` entry in `home/`, then run `chezmoi apply`.
- **Move the repo**: update `sourceDir` in `~/.config/chezmoi/chezmoi.toml`, then run `chezmoi apply --force`.

## TODO

- Bring the Ghostty config (`~/.config/ghostty/config`) into the repo and link it with chezmoi. Before that, set it up properly: Catppuccin Mocha theme (Ghostty ships Catppuccin themes) and useful convenience settings. It already uses `font-family = FiraCode Nerd Font` from `fonts/`.
- Add a custom DankMaterialShell top-right bar tile backed by a script or Bash command. DMS supports custom bar widgets through QML plugins in `~/.config/DankMaterialShell/plugins/`; implement this after the relevant configuration is backed up and managed through chezmoi.

# Scripts
Functionality that I tend to reuse. They're available on PATH after a standard installation.
eg. video encoding

## Local Overrides
You can create a `.env_vars.local` file in `~/.config/zsh/` (or `dotfiles/zsh/.config/zsh/.env_vars.local` in the repository) to override environment variables specific to your local machine. This file is ignored by git.
For example, you can set `export TMUX_AUTO_ATTACH=true` to automatically attach to a tmux session when opening a terminal.
