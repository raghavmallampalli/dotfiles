# dotfiles
These are the scripts I use to set up my Ubuntu. They install tools for Web development and ML and work with Ubuntu 18.04, 20.04, 22.04 and WSL2 Ubuntu.

These scripts are largely inspired by https://github.com/rsnk96/Ubuntu-Setup-Scripts. Some of the code is taken directly from there. 
For a list of useful commands and tips, check out [help](Help.md)

I like to see icons on my terminal. Make sure to install and use a NerdFont for your terminal emulator if you want the icons to show up. I use [FircaCode](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip)

## Testing on a docker
If you want to test this setup on a docker, a sample dockerfile is provided. 

### Build the Docker image:
```bash
docker build -t dotfiles-test .
```

### Run the container:
```bash
docker run -it --name dotfiles-test dotfiles-test
```

### Automated Verification
You can also run the automated test script which builds the image and runs the installation scripts:
```bash
./test_install.sh
```
Check `install_test.log` for the output.

## Setup scripts
### cli
Basic setup of Ubuntu. It installs some essential packages and their dependencies. It also installs some useful command line utilites.

> **Note**: The setup is split into two scripts:
> 1. `install.sh`: Installs packages and tools.
> 2. `setup.sh`: Configures dotfiles and shell.

Run them in order:
```bash
./install.sh
./setup.sh
```

> IMPORTANT: `bash` shell is replaced by a `zsh+Oh-My-Zsh` configuration.

### dev
Programming languages, virtual environments, useful dev tools

### extras
Generally useful CLI tools.

### gui
OUT OF DATE
GUI programs I use frequently use. A number of repositories are added. Installs a IDE of your choice (Sublime/Atom/VS Code).

# One off scripts
Functionality that I tend to reuse.
eg. video encoding
