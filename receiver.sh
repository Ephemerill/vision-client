#!/bin/bash

# This script receives the H.264 stream on port 5000,
# decodes it, re-encodes it as Motion JPEG (MJPEG),
# and serves it over HTTP on port 8080.

PORT="8080"
BOUNDARY="--boundary"

echo "Starting web receiver on http://0.0.0.0:$PORT"
echo "Waiting for stream on UDP port 5000..."

# This command is wrapped by netcat (nc).
# 1. We first print the HTTP headers for an MJPEG stream.
# 2. Then, we launch GStreamer.
#    - udpsrc: Receives the raw UDP packets
#    - rtph264depay: Extracts H.264 video from RTP
#    - avdec_h264: Decodes the H.264 video (software decoder, works on Mac/Linux)
#    - videoconvert: Converts the color space
#    - jpegenc: Encodes each frame as a JPEG
#    - multipartmux: Packages the JPEGs into an MJPEG stream
#    - fdsink: Pipes the stream to stdout, which netcat serves
{
    printf "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=%s\r\n\r\n" "$BOUNDARY"
    
    gst-launch-1.0 -q udpsrc port=5000 caps="application/x-rtp, encoding-name=H264, payload=96" \
        ! rtph264depay \
        ! avdec_h264 \
        ! videoconvert \
        ! jpegenc \
        ! multipartmux boundary="$BOUNDARY" \
        ! fdsink fd=1
} | nc -l "$PORT"