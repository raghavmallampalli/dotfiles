#!/bin/bash

LOG_FILE="install_test.log"
echo "Starting Docker verification tests..." | tee "$LOG_FILE"

run_test() {
    local base_image=$1
    local tag_name=$2
    
    echo "----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "Testing with Base Image: $base_image" | tee -a "$LOG_FILE"
    echo "----------------------------------------------------------------" | tee -a "$LOG_FILE"

    # Build the docker image
    echo "Building Docker image ($tag_name)..." | tee -a "$LOG_FILE"
    if docker build --build-arg BASE_IMAGE="$base_image" -t "$tag_name" . >> "$LOG_FILE" 2>&1; then
        echo "Docker build successful for $base_image." | tee -a "$LOG_FILE"
    else
        echo "Docker build failed for $base_image. Check $LOG_FILE for details." | tee -a "$LOG_FILE"
        return 1
    fi

    # Run the container and verify installed tools
    echo "Running verification tests..." | tee -a "$LOG_FILE"
    # We run simple version checks to ensure tools are installed and in PATH
    if docker run --rm "$tag_name" zsh -ic "
        echo 'Checking zsh...' && zsh --version && 
        echo 'Checking gh...' && gh --version && 
        echo 'Checking fzf...' && fzf --version && 
        echo 'Checking bat...' && bat --version && 
        echo 'Checking zoxide...' && zoxide --version &&
        echo 'Checking .zshrc...' && ls -la ~/.zshrc
    " >> "$LOG_FILE" 2>&1; then
        echo "Verification tests passed for $base_image." | tee -a "$LOG_FILE"
    else
        echo "Verification tests failed for $base_image. Check $LOG_FILE for details." | tee -a "$LOG_FILE"
        return 1
    fi
    
    return 0
}

# Run tests for Ubuntu
run_test "ubuntu:24.04" "dotfiles-test-ubuntu"
UBUNTU_RESULT=$?

# Run tests for Arch
run_test "archlinux:latest" "dotfiles-test-arch"
ARCH_RESULT=$?

echo "----------------------------------------------------------------" | tee -a "$LOG_FILE"
if [ $UBUNTU_RESULT -eq 0 ] && [ $ARCH_RESULT -eq 0 ]; then
    echo "All tests passed successfully!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "Some tests failed." | tee -a "$LOG_FILE"
    exit 1
fi
