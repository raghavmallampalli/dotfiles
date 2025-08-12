#!/bin/bash

# A script to re-encode video files to H.264 (libx264) or H.265 (libx265) and AAC.

# --- Default Settings ---
INPUT_PATH="."

# Codec choice: 264 (H.264) or 265 (H.265)
CODEC="264"

# CRF (Constant Rate Factor). Lower values mean higher quality and larger files.
# For H.264: 28 is a good default. Range is 0-51.
# For H.265: 22 is a good default. Range is 0-51.
# Use Case                           | 1080p (Full HD) | 4K (Ultra HD) | Description                                                                                                                                                                                                            |
# :--------------------------------- | :-------------- | :------------ | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
# **Archiving / Near-Lossless**      | 16 - 20         | 18 - 22       | For preserving the highest possible quality. These values produce files that are visually indistinguishable from the source for most people. The resulting files will be large but are ideal for master copies or professional use. |
# **High-Quality / Streaming**       | 20 - 24         | 22 - 26       | A good balance for high-quality playback on most devices and for streaming services where quality is a priority. This range offers excellent visual fidelity without the excessive file sizes of archival settings. |
# **General Use / Sharing**          | 24 - 28         | 26 - 30       | Recommended for everyday use, such as sharing videos with friends or uploading to social media. The default CRF of 28 falls within this range and provides a good compromise between quality and file size for most situations. |
# **Low Quality / High Compression** | 28 - 32         | 30 - 34       | Use this range when file size is the primary concern and some loss of quality is acceptable. This is suitable for situations where bandwidth or storage is very limited.                                                    |
# A change of ±6 roughly doubles/halves the bitrate.
# 28 in 264 is about same quality as 22 in 265
CRF_VALUE=28


# Preset affects encoding speed vs. compression efficiency.
# Slower presets create smaller files for the same quality (CRF).
# Options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
PRESET=slow

# Audio Bitrate. 128k is good for stereo. Use 192k for higher quality.
AUDIO_BITRATE=128k

# --- Usage Function ---
usage() {
    echo "Usage: $0 [-i input_path] [-c crf_value] [-p preset] [-a audio_bitrate] [-x codec] [-h]"
    echo "  -i input_path     Directory containing MP4 files (default: current directory)"
    echo "  -c crf_value      CRF value for quality (default: 28 for H.264, 22 for H.265)"
    echo "  -p preset         Encoding preset (default: slow)"
    echo "  -a audio_bitrate  Audio bitrate (default: 128k)"
    echo "  -x codec          Codec choice: 264 for H.264, 265 for H.265 (default: 264)"
    echo "  -h                Show this help message"
    echo ""
    echo "Example: $0 -i /path/to/videos -c 25 -p medium -x 265"
    exit 1
}

# --- Parse Command Line Arguments ---
while getopts "i:c:p:a:x:h" opt; do
    case $opt in
        i) INPUT_PATH="$OPTARG" ;;
        c) CRF_VALUE="$OPTARG" ;;
        p) PRESET="$OPTARG" ;;
        a) AUDIO_BITRATE="$OPTARG" ;;
        x) CODEC="$OPTARG" ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
    esac
done

# --- Validation ---
if [ ! -d "$INPUT_PATH" ]; then
    echo "Error: Input path '$INPUT_PATH' does not exist or is not a directory."
    exit 1
fi

# Validate codec choice
if [ "$CODEC" != "264" ] && [ "$CODEC" != "265" ]; then
    echo "Error: Invalid codec choice '$CODEC'. Use 264 for H.264 or 265 for H.265."
    exit 1
fi

# Check if there are any MP4 files in the specified path
if ! ls "$INPUT_PATH"/*.mp4 >/dev/null 2>&1; then
    echo "Error: No MP4 files found in '$INPUT_PATH'"
    exit 1
fi

echo "Processing MP4 files in: $INPUT_PATH"
echo "Codec: H.$CODEC, CRF: $CRF_VALUE, Preset: $PRESET, Audio: $AUDIO_BITRATE"
echo ""

# Find all .mp4 files in the specified directory
for file in "$INPUT_PATH"/*.mp4; do
    # Skip if no mp4 files are found
    [ -e "$file" ] || continue

    # Get just the filename without the path
    filename=$(basename "$file")
    
    # Create encoded subfolder if it doesn't exist
    encoded_dir="$INPUT_PATH/encoded"
    mkdir -p "$encoded_dir"
    
    # Define the output filename (save in the encoded subfolder)
    output="$encoded_dir/$(basename "${file%.*}_${PRESET}_h${CODEC}.mp4")"

    echo "----------------------------------------------------"
    echo "Encoding '$filename' -> '$(basename "$output")'"
    echo "Codec: H.$CODEC, CRF: $CRF_VALUE, Preset: $PRESET, Audio: $AUDIO_BITRATE"
    echo "----------------------------------------------------"

    # The ffmpeg command
    if [ "$CODEC" = "264" ]; then
        ffmpeg -i "$file" \
               -c:v libx264 \
               -crf "$CRF_VALUE" \
               -preset "$PRESET" \
               -c:a aac \
               -b:a "$AUDIO_BITRATE" \
               "$output"
    else
        ffmpeg -i "$file" \
               -c:v libx265 \
               -crf "$CRF_VALUE" \
               -preset "$PRESET" \
               -c:a aac \
               -b:a "$AUDIO_BITRATE" \
               "$output"
    fi

    echo "Finished encoding '$(basename "$output")'."
    echo ""
done

echo "All files have been processed."
