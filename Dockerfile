# Use Ubuntu 22.04 as base image
FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Update package list and install essential packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    sudo \
    && rm -rf /var/lib/apt/lists/*

    
# Copy the dotfiles project to the container
COPY . /root/dotfiles/

# Set working directory to root's home
WORKDIR /root/dotfiles
    
# Set environment variables for the script
ENV HOME=/root
ENV BACKUP_DIR=/tmp

# Make the scripts executable
RUN chmod +x /root/dotfiles/cli.sh /root/dotfiles/common.sh

# Change to the dotfiles directory
WORKDIR /root/dotfiles

RUN ls -la

# Run the cli.sh script with command-line arguments for non-interactive setup
RUN ./cli.sh \
    --sudo-access y \
    --replace-dotfiles y \
    --soft-link n \
    --local-time n \
    --github-login n \
    --package-install y \
    --zsh-default y \
    --tmux-config n

# Set zsh as the default shell for the container
RUN chsh -s /usr/bin/zsh root

# Set the default command to start zsh
CMD ["/usr/bin/zsh"]
