#!/bin/bash

LOG_FILE="install_test.log"

echo "Starting Docker verification test..." | tee "$LOG_FILE"

# Build the docker image
echo "Building Docker image..." | tee -a "$LOG_FILE"
if docker build -t dotfiles-test . >> "$LOG_FILE" 2>&1; then
    echo "Docker build successful." | tee -a "$LOG_FILE"
else
    echo "Docker build failed. Check $LOG_FILE for details." | tee -a "$LOG_FILE"
    exit 1
fi

# Run the container and verify installed tools
echo "Running verification tests..." | tee -a "$LOG_FILE"
# We run simple version checks to ensure tools are installed and in PATH
if docker run --rm dotfiles-test zsh -c "
    echo 'Checking zsh...' && zsh --version && 
    echo 'Checking gh...' && gh --version && 
    echo 'Checking fzf...' && fzf --version && 
    echo 'Checking bat...' && bat --version && 
    echo 'Checking zoxide...' && zoxide --version &&
    echo 'Checking .zshrc...' && ls -la ~/.zshrc
" >> "$LOG_FILE" 2>&1; then
    echo "Verification tests completed successfully." | tee -a "$LOG_FILE"
else
    echo "Verification tests failed. Check $LOG_FILE for details." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Verification complete." | tee -a "$LOG_FILE"
