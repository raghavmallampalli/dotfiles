set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Collect all user inputs at the start
if [ "$ROOT_MODE" = false ]; then
    if [ -z "$HAS_SUDO" ]; then
        read -p "Do you have sudo access? [y/n] " HAS_SUDO
    fi
else
    HAS_SUDO="y"
fi

# FFMPEG
if [[ $HAS_SUDO = y ]]; then
    show_progress "Installing FFMPEG and related tools"
    run_command apt-get install libhdf5-dev exiftool ffmpeg -y
    finish_progress
fi
