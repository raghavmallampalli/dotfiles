#!/bin/bash

# Default values
COPY_AUDIO=false
VIDEO_CODEC="libx265" # Default to H.265

# Help message
usage() {
  echo "Usage: $0 [-c] [-4] file1 [file2 ...]"
  echo "  -c: Copy audio stream without re-encoding."
  echo "  -4: Use H.264 (libx264) instead of H.265 (libx265)."
  exit 1
}

# Parse options
while getopts "c4h" opt;
  do
  case ${opt} in
    c)
      COPY_AUDIO=true
      ;; 
    4)
      VIDEO_CODEC="libx264"
      ;; 
    h)
      usage
      ;; 
    \?)
      usage
      ;; 
  esac
done
shift $((OPTIND -1))

# Check if files are provided
if [ "$#" -eq 0 ]; then
    usage
fi

# Set video quality preset
CRF=23 # Constant Rate Factor (lower is better quality, 23 is a good default)
PRESET="slower" # Encoding speed vs. compression (e.g., ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow)

for file in "$@"; do
    FILENAME=$(basename -- "$file")
    EXTENSION="${FILENAME##*.}"
    FILENAME_NOEXT="${FILENAME%.*}"
    PARENT_DIR=$(dirname -- "$file")
    OUTPUT_DIR="${PARENT_DIR}/encoded"
    mkdir -p "${OUTPUT_DIR}"
    OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME_NOEXT}_${VIDEO_CODEC}.mkv"

    AUDIO_ARGS=""
    if [ "$COPY_AUDIO" = true ]; then
        AUDIO_ARGS="-c:a copy"
    else
        CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$file")
        if [ -z "$CHANNELS" ]; then
            echo "No audio stream found in $file. Copying video only."
            AUDIO_ARGS="-an" # No audio
        elif [ "$CHANNELS" -gt 2 ]; then
            AUDIO_BITRATE="640k"
            AUDIO_ARGS="-c:a aac -b:a ${AUDIO_BITRATE}"
        else
            AUDIO_BITRATE="192k"
            AUDIO_ARGS="-c:a aac -b:a ${AUDIO_BITRATE}"
        fi
    fi

    echo "--------------------------------------------------"
    echo "Input file: $file"
    echo "Output file: $OUTPUT_FILE"
    echo "Video Codec: $VIDEO_CODEC"
    if [ "$COPY_AUDIO" = true ]; then
        echo "Audio: Copying stream"
    elif [ -n "$CHANNELS" ]; then
        echo "Audio: Encoding to AAC at ${AUDIO_BITRATE} (${CHANNELS} channels)"
    fi
    echo "--------------------------------------------------"

    ffmpeg -i "$file" \
           -c:v "${VIDEO_CODEC}" -crf "${CRF}" -preset "${PRESET}" \
           ${AUDIO_ARGS} \
           -c:s copy \
           -map 0 \
           "$OUTPUT_FILE"

    echo "--------------------------------------------------"
    echo "Finished encoding $file"
    echo "--------------------------------------------------"
done

echo "All encoding tasks are complete."