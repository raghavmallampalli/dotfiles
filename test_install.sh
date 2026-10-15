#!/bin/bash

# Runs install_cli.sh + setup.sh in fresh containers and checks the results.
# A GitHub token avoids rate limits on mise's downloads; it's passed at runtime, never
# stored in an image. Taken from $GITHUB_TOKEN, or from the GitHub CLI if logged in.

LOG_FILE="install_test.log"
echo "Starting Docker verification tests..." | tee "$LOG_FILE"

TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"

CHECKS="
    mise --version && gh --version && chezmoi --version && fzf --version && bat --version &&
    zoxide --version && yazi --version && duckdb --version && tmux -V && nvim --version &&
    uv --version && rich --version && ls -la ~/.zshenv ~/.config/zsh/.zshrc
"

# run_test <base image> <tag> <sudo|nosudo>
run_test() {
    local base_image=$1
    local tag_name=$2
    local mode=$3

    echo "----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "Testing $base_image ($mode)" | tee -a "$LOG_FILE"
    echo "----------------------------------------------------------------" | tee -a "$LOG_FILE"

    if ! docker build --target base --build-arg BASE_IMAGE="$base_image" -t "$tag_name" . >>"$LOG_FILE" 2>&1; then
        echo "Docker build failed for $base_image. Check $LOG_FILE for details." | tee -a "$LOG_FILE"
        return 1
    fi

    local script
    if [ "$mode" = "sudo" ]; then
        # Root in the container, so the package manager steps run
        script="./install_cli.sh --sudo-access yes &&
            ./setup.sh --local-time n --github-login n --zsh-default y --sudo-access yes &&
            zsh -ic '$CHECKS'"
    else
        # A regular user without sudo, like on a shared server. curl and git are
        # preinstalled there, so add them as root first; zsh is deliberately left out.
        script="apt-get update -qq && apt-get install -y -qq curl git ca-certificates openssh-client >/dev/null &&
            useradd -m tester && cp -r /root/dotfiles /home/tester/dotfiles && chown -R tester /home/tester/dotfiles &&
            su tester -c 'cd ~/dotfiles && export HOME=/home/tester BACKUP_DIR=/tmp &&
                ./install_cli.sh --sudo-access no &&
                ./setup.sh --local-time n --github-login n --zsh-default n --sudo-access no &&
                bash -ic \"${CHECKS//\'/}\"'"
    fi

    if docker run --rm -e MISE_GITHUB_TOKEN="$TOKEN" "$tag_name" bash -c "$script" >>"$LOG_FILE" 2>&1; then
        echo "Tests passed for $base_image ($mode)." | tee -a "$LOG_FILE"
    else
        echo "Tests failed for $base_image ($mode). Check $LOG_FILE for details." | tee -a "$LOG_FILE"
        return 1
    fi
}

FAILED=0
run_test "ubuntu:24.04" "dotfiles-test-ubuntu" sudo || FAILED=1
run_test "ubuntu:24.04" "dotfiles-test-ubuntu" nosudo || FAILED=1
run_test "fedora:latest" "dotfiles-test-fedora" sudo || FAILED=1
run_test "archlinux:latest" "dotfiles-test-arch" sudo || FAILED=1

echo "----------------------------------------------------------------" | tee -a "$LOG_FILE"
if [ $FAILED -eq 0 ]; then
    echo "All tests passed successfully!" | tee -a "$LOG_FILE"
else
    echo "Some tests failed." | tee -a "$LOG_FILE"
    exit 1
fi
