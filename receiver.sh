#!/bin/bash

# This script receives the MJPEG stream on port 5000,
# and serves it over HTTP on port 8080.

PORT="8080"
BOUNDARY="--boundary"

# --- CHECK FOR NCAT ---
if ! command -v ncat &> /dev/null; then
    echo -e "\033[0;31mError: 'ncat' command not found.\033[0m"
    echo "This script now uses 'ncat' as it's more reliable on macOS."
    echo "Please install it by running:"
    echo -e "\033[0;32mbrew install nmap\033[0m"
    exit 1
fi

echo "Starting web receiver on http://0.0.0.0:$PORT"
echo "Waiting for stream on UDP port 5000..."
echo "Open index.html in your browser to start."

# This block pipes the HTTP header and the GStreamer output
# to ncat, which acts as the web server.
{
    # Print the HTTP header
    printf "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=%s\r\n\r\n" "$BOUNDARY"
    
    # This message goes to stderr (your console)
    echo -e "\n-----------------------------------------------------" >&2
    echo -e "ncat is listening. GStreamer is now active." >&2
    echo -e "Waiting for MJPEG stream from Pi on UDP port 5000..." >&2
    echo -e "You will see GStreamer logs below when it connects." >&2
    echo -e "-----------------------------------------------------\n" >&2

    # Start the GStreamer pipeline
    gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp, encoding-name=JPEG, payload=96" \
        ! rtpjpegdepay \
        ! multipartmux boundary="$BOUNDARY" \
        ! fdsink fd=1
} | ncat -l "$PORT" # --- UPDATED: Using ncat instead of nc ---