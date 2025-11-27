# Accept base image as argument (default to ubuntu:24.04)
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install essential packages depending on the OS
RUN if [ -f /etc/os-release ]; then \
    . /etc/os-release; \
    if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then \
        apt-get update && apt-get install -y curl wget git sudo unzip && rm -rf /var/lib/apt/lists/*; \
    elif [ "$ID" = "arch" ] || [ "$ID" = "archarm" ]; then \
        pacman -Sy --noconfirm curl wget git sudo unzip; \
    fi \
    fi

# Copy the dotfiles project to the container
COPY . /root/dotfiles/

# Set working directory to root's home
WORKDIR /root/dotfiles

# Set environment variables for the script
ENV HOME=/root
ENV BACKUP_DIR=/tmp

# Make the scripts executable
RUN chmod +x /root/dotfiles/install.sh /root/dotfiles/setup.sh /root/dotfiles/common.sh

# Run the install.sh script
# We pass --sudo-access y and --binaries-install n (default)
# The script itself will handle OS detection.
RUN ./install.sh \
    --sudo-access y \
    --binaries-install n

# Run the setup.sh script
RUN ./setup.sh \
    --replace-dotfiles y \
    --link n \
    --local-time n \
    --github-login n \
    --zsh-default y \
    --tmux-config y

# Set zsh as the default shell for the container
RUN chsh -s /usr/bin/zsh root

# Set the default command to start zsh
CMD ["/usr/bin/zsh"]
