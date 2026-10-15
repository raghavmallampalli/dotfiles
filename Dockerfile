# Accept base image as argument (default to ubuntu:24.04)
ARG BASE_IMAGE=ubuntu:24.04

# "base": the repo copied in, nothing installed. test_install.sh runs the scripts in a
# container from this stage, so a GitHub token can be passed at runtime instead of being
# baked into the image.
FROM ${BASE_IMAGE} AS base

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV HOME=/root
ENV BACKUP_DIR=/tmp

# Copy the dotfiles project to the container
COPY . /root/dotfiles/
WORKDIR /root/dotfiles
RUN chmod +x /root/dotfiles/install_cli.sh /root/dotfiles/setup.sh

# "full" (default): everything installed, for poking around with `docker run -it`
FROM base AS full

# We're root in the container so --sudo-access is moot, but pass it for non-interactive builds
RUN ./install_cli.sh --sudo-access yes

RUN ./setup.sh \
    --local-time n \
    --github-login n \
    --zsh-default y \
    --sudo-access yes

# Start zsh by default
CMD ["zsh"]
