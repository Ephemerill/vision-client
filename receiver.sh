#!/bin/bash

# This script receives the H.264 stream on port 5000,
# decodes it, re-encodes it as Motion JPEG (MJPEG),
# and serves it over HTTP on port 8080.

PORT="8080"
BOUNDARY="--boundary"

echo "Starting web receiver on http://0.0.0.0:$PORT"
echo "Waiting for stream on UDP port 5000..."
echo "Open index.html in your browser to start."

# This command is wrapped by netcat (nc).
# 1. We first print the HTTP headers for an MJPEG stream.
# 2. Then, we launch GStreamer.
#    - udpsrc: Receives the raw UDP packets
#    - rtph264depay: Extracts H.264 video from RTP
#    - avdec_h264: Decodes the H.264 video
#    - videoconvert: Converts the color space
#    - jpegenc: Encodes each frame as a JPEG
#    - multipartmux: Packages the JPEGs into an MJPEG stream
#    - fdsink: Pipes the stream to stdout, which netcat serves
{
    printf "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=%s\r\n\r\n" "$BOUNDARY"
    
    # --- NEW MESSAGE ---
    # This message goes to stderr (>&2) so it appears on the console
    # and doesn't get piped to the browser.
    echo -e "\n-----------------------------------------------------" >&2
    echo -e "Browser connected. GStreamer is now active." >&2
    echo -e "Waiting for stream from Pi on UDP port 5000..." >&2
    echo -e "You will see GStreamer logs below when it connects." >&2
    echo -e "-----------------------------------------------------\n" >&2

    # --- UPDATED: Removed -q (quiet) flag ---
    # GStreamer will now print status messages to stderr (your terminal)
    gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp, encoding-name=H264, payload=96" \
        ! rtph264depay \
        ! avdec_h264 \
        ! videoconvert \
        ! jpegenc \
        ! multipartmux boundary="$BOUNDARY" \
        ! fdsink fd=1
} | nc -l "$PORT"