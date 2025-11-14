#!/bin/bash

# This script receives the MJPEG stream on port 5000,
# and serves it over HTTP on port 8080.

PORT="8080"
BOUNDARY="--boundary"

echo "Starting web receiver on http://0.0.0.0:$PORT"
echo "Waiting for stream on UDP port 5000..."
echo "Open index.html in your browser to start."

{
    printf "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=%s\r\n\r\n" "$BOUNDARY"
    
    echo -e "\n-----------------------------------------------------" >&2
    echo -e "Browser connected. GStreamer is now active." >&2
    echo -e "Waiting for MJPEG stream from Pi on UDP port 5000..." >&2
    echo -e "You will see GStreamer logs below when it connects." >&2
    echo -e "-----------------------------------------------------\n" >&2

    # --- UPDATED: MJPEG Receive Pipeline ---
    # This is much lighter. It just receives JPEG, depayloads it,
    # and muxes it for the web. No decoding/re-encoding.
    gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp, encoding-name=JPEG, payload=26" \
        ! rtpjpegdepay \
        ! multipartmux boundary="$BOUNDARY" \
        ! fdsink fd=1
} | nc -l "$PORT"