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

## Setup scripts
### cli
Basic setup of Ubuntu. It installs some essential packages and their dependencies. It also installs some useful command line utilites.

> IMPORTANT: `bash` shell is replaced by a `zsh+Oh-My-Zsh` configuration.

### dev
Programming languages, virtual environments, useful dev tools

### gui
OUT OF DATE
GUI programs I use frequently use. A number of repositories are added. Installs a IDE of your choice (Sublime/Atom/VS Code).

## Guides
### Add a quake mode shortcut to windows terminal
Add this to your actions section of windows terminal settings json file (Ctrl+Shift+,)
```json
{
    "command": 
    {
        "action": "globalSummon",
        "desktop": "toCurrent",
        "monitor": "any",
        "toggleVisibility": true
    },
    "id": "User.globalSummon",
    "keys": "win+esc"
},
```
### Keep reconnecting to an ssh instance
Use this command to auto reconnect to ssh instance whenever the connection is broken.

```bash
autossh -M 20000 SSH_CONFIG_NAME -t 'tmux has-session -t General 2>/dev/null && tmux attach -t General || tmux'
```

You can kill this automatic reconnection using:

```bash
pkill -f "autossh.*SSH_CONFIG_NAME"
```

### Switching the remote to SSH authentication

```bash
git remote set-url origin git@github.com:raghavmallampalli/dotfiles.git
```

# One off scripts
Functionality that I tend to reuse.
eg. video encoding
