#!/bin/bash

# OUT OF DATE: I no longer use Ubuntu GUI.
set -e

spatialPrint() {
    echo ""
    echo ""
    echo "$1"
	echo "================================"
}

# To note: the execute() function doesn't handle pipes well
execute () {
	echo "$ $*"
	OUTPUT=$($@ 2>&1)
	if [ $? -ne 0 ]; then
        echo "$OUTPUT"
        echo ""
        echo "Failed to Execute $*" >&2
        exit 1
    fi
}

echo "Proceed if you have run basic.sh, changed directory to the parent folder of this script and gone through this sh file. Also make sure you know how to delete added repositories. Ctrl+C and do so first if not. [ENTER] to continue."
read dump

# IDE Install code editor of your choice
read -p "Download and Install VS Code Insiders / Atom / Sublime. Press q to skip this. Default: Skip Editor installation [v/a/s/q]: " tempvar
tempvar=${tempvar:-q}
if [[ $tempvar = v ]]; then
    curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
    execute sudo apt-get install apt-transport-https -y
    execute sudo apt-get update -y
    execute sudo apt-get install code -y # or code insiders
    execute rm microsoft.gpg
elif [[ $tempvar = a ]]; then
    execute sudo add-apt-repository ppa:webupd8team/atom
    execute sudo apt-get update -y; execute sudo apt-get install atom -y
elif [[ $tempvar = s ]]; then
    wget -q -O - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
    echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
    execute sudo apt-get install apt-transport-https -y
    execute sudo apt-get update -y
    execute sudo apt-get install sublime-text -y
elif [[ $tempvar = q ]]; then
    echo "Skipping this step"
fi

spatialPrint "Tweaks, fonts, themes and extensions"

execute sudo apt-get install gnome-tweaks gnome-shell-extensions chrome-gnome-shell -y # Works for Mozilla, Chromium based, Opera 
echo "GNOME extensions: install GNOME shell extensions browser extension. Alt+F2, r, enter to restart gnome-shell after installing extensions."
echo "Check out Alternate-tab, Caffeine, CPU Power Manager, Steal My Focus and Dash to Dock"

# Dracula theme everything
execute sudo apt-get install dconf-cli -y
git clone https://github.com/dracula/gnome-terminal
cd gnome-terminal && sh ./install.sh && cd ..
touch ~/.themes
git clone https://github.com/dracula/gtk ~/.themes/Dracula
gsettings set org.gnome.desktop.interface gtk-theme "Dracula"
gsettings set org.gnome.desktop.wm.preferences theme "Dracula"
sudo jupyter labextension install @karosc/jupyterlab_dracula

if [[ $(cat /etc/os-release | grep "VERSION_ID" | grep -o -E '[0-9][0-9]' | head -n 1) -lt 19 ]]; then
    sudo add-apt-repository ppa:papirus/papirus
    execute sudo apt-get install papirus-icon-theme -y
    gsettings set org.gnome.desktop.interface icon-theme "Papirus" # modify .desktop files if you don't like icons
fi

! [ -d /usr/share/fonts/ ] && execute mkdir /usr/share/fonts/
execute sudo cp -r ./config_files/fonts /usr/share/fonts/
execute fc-cache - f -v

spatialPrint "GUI programs"
sudo add-apt-repository multiverse -y
sudo add-apt-repository ppa:hluk/copyq -y
wget -qO- http://repo.vivaldi.com/stable/linux_signing_key.pub | sudo apt-key add - # check if the file remains post installation
execute sudo add-apt-repository "deb http://repo.vivaldi.com/stable/deb/ stable main"
sudo add-apt-repository ppa:qbittorrent-team/qbittorrent-stable
execute sudo apt-get update -y

execute sudo apt-get install vivaldi-stable -y # Chromium based browser. Buggy but feature intensive.
execute sudo apt-get install speedcrunch -y # Superior calculator
execute sudo apt-get install gimp -y # Photo editor
execute sudo apt-get install hexchat -y # IRC client
execute sudo apt-get install audacity -y
execute sudo apt-get install steam -y
execute sudo apt-get install copyq -y # Clipboard logger. Super useful.
echo "Change launch shortcut, add frequently typed stuff as pinned items. "
execute sudo apt-get install simplescreenrecorder -y
echo "Refer README to complete simplescreenrecorder setup. Cannot be done from terminal."
# check if latex installs automatically with below command
execute sudo apt-get install qbittorrent -y # The best torrent client

# IMPORTANT: VLC is a snap utility. Comment out if you do not wish to install.
# Go to their site pages for deb package if you do not wish to use snap
# Also check out vlsub and subsync if you install vlc
sudo snap install vlc

echo "Visit and install: "
echo "Master PDF Editor: https://code-industry.net/free-pdf-editor/" # NOT open source
echo "AutomaThemely: https://github.com/C2N14/AutomaThemely" # Change themes automatically at night

echo "Run calibreupdate after restarting. Install monstre icon theme, count pages, find duplicates, goodreads and goodreads sync plugins. Set up."
echo "Installation completed."
echo "MusicBee is the best offline music player created by man. It is only available for Windows. Try the wine...sh file next to install it."
