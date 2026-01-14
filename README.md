# dotfiles
These are the scripts I use to set up my Linux environment. They install tools for Web development and ML and work with:
- Ubuntu 18.04, 20.04, 22.04, 24.04
- Arch Linux

These scripts are largely inspired by https://github.com/rsnk96/Ubuntu-Setup-Scripts. Some of the code is taken directly from there. 
For a list of useful commands and tips, check out [help](Help.md)

I like to see icons on my terminal. Make sure to install and use a NerdFont for your terminal emulator if you want the icons to show up. I use [FircaCode](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip)

## Testing on Docker
If you want to test this setup on Docker, a `Dockerfile` is provided. It supports both Ubuntu and Arch Linux base images.

### Build the Docker image:
For Ubuntu (default):
```bash
docker build -t dotfiles-test-ubuntu .
```

For Arch Linux:
```bash
docker build --build-arg BASE_IMAGE=archlinux:latest -t dotfiles-test-arch .
```

### Run the container:
```bash
docker run -it --name dotfiles-test dotfiles-test-ubuntu
# or
docker run -it --name dotfiles-test dotfiles-test-arch
```

### Automated Verification
You can also run the automated test script which builds the images and runs the installation scripts for both Ubuntu and Arch:
```bash
./test_install.sh
```
Check `install_test.log` for the output.

## Setup scripts
1. `install.sh`: Installs packages and tools.
2. `setup.sh`: Configures dotfiles and shell.
3. `dev.sh`: Programming languages and environments.
4. `extras.sh`: General tools. Includes my preferred desktop environment set-up on Arch.

> IMPORTANT: `extras.sh` is only kept up to date for Arch, which is my primary OS.
Run them in order:
```bash
./install.sh
./setup.sh
```

> IMPORTANT: `bash` shell is replaced by a `zsh+Oh-My-Zsh` configuration.

### Dotfiles Management (Stow)
We use [GNU Stow](https://www.gnu.org/software/stow/) to manage dotfiles.
- **Install**: `setup.sh` runs `stow` to link configurations to your home directory.
- **Move Repo**: If you move this repository, the symlinks will break. To fix them, run:
  ```bash
  stow -R -d dotfiles -t $HOME zsh tmux nvim yazi neovim ...
  ```
within the directory of the repository.

# Scripts
Functionality that I tend to reuse. They will be avaiable on PATH after a standard installation.
eg. video encoding
