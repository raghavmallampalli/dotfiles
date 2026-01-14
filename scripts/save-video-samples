#!/bin/bash

# --- Configuration ---
# Default values
INPUT_VIDEO=""
CLIP_DURATION="00:00:10" # 10 seconds
OUTPUT_PATH="." # Default to current working directory

# Function to get video duration in seconds
get_video_duration() {
  local video_file="$1"
  local duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$video_file" 2>/dev/null)
  if [ -z "$duration" ] || [ "$duration" = "N/A" ]; then
    echo "Error: Could not determine video duration for '$video_file'" >&2
    exit 1
  fi
  # Convert decimal to integer by truncating (removing decimal part)
  local duration_int=${duration%.*}
  echo "$duration_int"
}

# Function to convert seconds to HH:MM:SS format
seconds_to_timestamp() {
  local seconds=$1
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local secs=$((seconds % 60))
  printf "%02d:%02d:%02d" $hours $minutes $secs
}

# Function to calculate evenly spaced start times
calculate_start_times() {
  local video_duration=$1
  local num_clips=5
  local clip_duration_seconds=10  # 10 seconds per clip
  
  # Check if video is long enough for 5 clips
  local total_needed=$((num_clips * clip_duration_seconds))
  if [ $video_duration -lt $total_needed ]; then
    echo "Error: Video duration ($video_duration seconds) is too short for 5 clips of 10 seconds each." >&2
    echo "Minimum required duration: $total_needed seconds" >&2
    exit 1
  fi
  
  # Calculate available time for spacing (subtract total clip duration)
  local available_time=$((video_duration - total_needed))
  local spacing=$((available_time / (num_clips - 1)))
  
  # Generate evenly spaced start times
  local start_times=()
  for ((i=0; i<num_clips; i++)); do
    local start_seconds=$((i * spacing))
    start_times+=("$(seconds_to_timestamp $start_seconds)")
  done
  
  echo "${start_times[@]}"
}

# Function to display usage information
show_usage() {
  echo "Usage: $0 -i <input_video> [options]"
  echo ""
  echo "Options:"
  echo "  -i <input_video>    Input video file (required)"
  echo "  -o <output_path>    Output directory for samples (default: current directory)"
  echo "  -h                  Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 -i your_video.mp4"
  echo "  $0 -i your_video.mp4 -o /path/to/output"
  echo ""
  echo "This script creates 5 lossless sample clips from the specified video file."
  echo "Start times are automatically calculated to be evenly spaced across the video."
}

# Parse command line arguments
while getopts "i:o:h" opt; do
  case $opt in
    i)
      INPUT_VIDEO="$OPTARG"
      ;;
    o)
      OUTPUT_PATH="$OPTARG"
      ;;
    h)
      show_usage
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      show_usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      show_usage
      exit 1
      ;;
  esac
done

# Check if input video was provided
if [ -z "$INPUT_VIDEO" ]; then
  echo "Error: Input video file is required."
  echo ""
  show_usage
  exit 1
fi

# --- Script Logic ---
# Check if the input file exists
if [ ! -f "$INPUT_VIDEO" ]; then
  echo "Error: Input file '$INPUT_VIDEO' not found."
  exit 1
fi

# Check if output directory exists, create if it doesn't
if [ ! -d "$OUTPUT_PATH" ]; then
  echo "Creating output directory: $OUTPUT_PATH"
  mkdir -p "$OUTPUT_PATH"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create output directory '$OUTPUT_PATH'"
    exit 1
  fi
fi

# Get video duration and check minimum length
echo "Analyzing video duration..."
VIDEO_DURATION_SECONDS=$(get_video_duration "$INPUT_VIDEO")
VIDEO_DURATION_FORMATTED=$(seconds_to_timestamp $VIDEO_DURATION_SECONDS)

echo "Video duration: $VIDEO_DURATION_FORMATTED ($VIDEO_DURATION_SECONDS seconds)"

# Check if video is shorter than 50 seconds
if [ $VIDEO_DURATION_SECONDS -lt 50 ]; then
  echo "Error: Video is too short. Duration: $VIDEO_DURATION_SECONDS seconds, minimum required: 50 seconds" >&2
  exit 1
fi

# Calculate evenly spaced start times
echo "Calculating evenly spaced start times..."
START_TIMES=($(calculate_start_times $VIDEO_DURATION_SECONDS))

echo "Start times: ${START_TIMES[*]}"
echo ""

echo "Creating 5 lossless samples from '$INPUT_VIDEO'..."
echo ""

# Loop through the start times array
for i in "${!START_TIMES[@]}"; do
  start_time=${START_TIMES[$i]}
  clip_number=$((i+1))
  output_file="$OUTPUT_PATH/sample_${clip_number}.mp4"

  echo "-> Creating Clip $clip_number: '$output_file' (starts at $start_time)"

  # The ffmpeg command for lossless snipping
  ffmpeg -ss "$start_time" -i "$INPUT_VIDEO" -t "$CLIP_DURATION" -c copy "$output_file" -y

done

echo ""
echo "✅ All 5 sample clips have been created in: $OUTPUT_PATH"