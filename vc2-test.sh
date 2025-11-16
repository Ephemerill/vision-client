#!/bin/bash

# This script starts ffmpeg to capture, encode, and push
# the video stream to the local mediamtx server.

# --- Configuration ---
# This is the path to your camera (from Step 3 in the README).
VIDEO_DEVICE="/dev/video0"

# This must match the RTSP server port in mediamtx.yml
RTSP_PORT="8554"

# This must match the path name in mediamtx.yml
STREAM_NAME="cam"

# These must match the publishUser and publishPass in mediamtx.yml
PUBLISH_USER="admin"
PUBLISH_PASS="mysecretpassword"

# --- Advanced ---
# H.264 bitrate. 4M = 4000k.
# Adjust 2M (2000k) for lower bandwidth, or 8M (8000k) for higher quality.
BITRATE="4000k"

# The target URL for the RTSP server
RTSP_URL="rtsp://${PUBLISH_USER}:${PUBLISH_PASS}@localhost:${RTSP_PORT}/${STREAM_NAME}"

echo "Starting stream from ${VIDEO_DEVICE}..."
echo "Target: ${RTSP_URL}"

# The ffmpeg command
# This will run forever until you stop it (Ctrl+C)
ffmpeg \
    -f v4l2 \
    -i ${VIDEO_DEVICE} \
    -c:v h264_v4l2m2m \
    -b:v ${BITRATE} \
    -f rtsp \
    -rtsp_transport tcp \
    ${RTSP_URL}

echo "Stream stopped."