#!/bin/bash

# This script receives the H.264 stream on port 5000,
# decodes it, re-encodes it as MJPEG,
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

echo "Starting PERSISTENT H.264 -> MJPEG transcoding receiver on http://0.0.0.0:$PORT"

# --- NEW: Wrap in a while true loop ---
while true
do
    echo "Waiting for new client connection on port $PORT..." >&2
    
    # This block pipes the HTTP header and the GStreamer output
    # to ncat, which acts as the web server.
    {
        # Print the HTTP header
        printf "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=%s\r\n\r\n" "$BOUNDARY"
        
        # This message goes to stderr (your console)
        echo -e "\n-----------------------------------------------------" >&2
        echo -e "Client connected! GStreamer is now active." >&2
        echo -e "Waiting for H.264 stream from Pi on UDP port 5000..." >&2
        echo -e "You will see GStreamer logs below when it connects." >&2
        echo -e "-----------------------------------------------------\n" >&2

        # --- UPDATED GStreamer Pipeline ---
        # Receives H.264, decodes it, re-encodes as MJPEG, and serves it.
        gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp, encoding-name=H264, payload=96" \
            ! rtph264depay \
            ! h264parse \
            ! avdec_h264 \
            ! videoconvert \
            ! jpegenc quality=90 \
            ! multipartmux boundary="$BOUNDARY" \
            ! fdsink fd=1
            
    } | ncat -l "$PORT" # ncat will exit when the client disconnects

    echo "Client disconnected (Broken pipe is normal). GStreamer stopped." >&2
    echo "Looping to wait for next client." >&2
    sleep 1 #
done