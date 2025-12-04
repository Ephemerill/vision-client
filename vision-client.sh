#!/bin/bash

# ==========================================
# VISION CLIENT - TRANSMITTER (Pi Side)
# Optimized for Low Latency Computer Vision
# ==========================================

# --- CONFIGURATION ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
GIT_BRANCH="main"

# Process Management
SERVER_PID_FILE="/tmp/mediamtx.pid"
STREAM_PID_FILE="/tmp/ffmpeg_stream.pid"
SERVER_LOG_FILE="/tmp/mediamtx.log"
STREAM_LOG_FILE="/tmp/ffmpeg_stream.log"

# mediamtx Server (The RTSP Broker)
MEDIAMTX_CONFIG_FILE="${SCRIPT_DIR}/mediamtx.yml"
MEDIAMTX_BINARY="${SCRIPT_DIR}/mediamtx"
RTSP_PORT="8554"
HLS_PORT="8888"
WEBRTC_PORT="8889"
MEDIAMTX_URL="https://github.com/bluenviron/mediamtx/releases/download/v1.15.3/mediamtx_v1.15.3_linux_arm64.tar.gz"

# ffmpeg Stream Client (The Camera Feeder)
VIDEO_DEVICE="/dev/video0"
RESOLUTION="1280x720"     # Lowered for Tailscale/VPN latency stability
FPS=30
BITRATE="3000k"          # 2Mbps is sufficient for 480p CV
STREAM_NAME="cam"
PUBLISH_USER="admin"
PUBLISH_PASS="mysecretpassword"
RTSP_URL="rtsp://${PUBLISH_USER}:${PUBLISH_PASS}@localhost:${RTSP_PORT}/${STREAM_NAME}"

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- ASCII ART HEADER ---
show_header() {
    tput rmam
    clear
    echo -e "${CYAN}"
    echo '$$\    $$\ $$\           $$\                            $$$$$$\  $$\ $$\                      $$\  '
    echo '$$ |   $$ |\__|          \__|                          $$  __$$\ $$ |\__|                     $$ |'
    echo '$$ |   $$ |$$\  $$$$$$$\ $$\  $$$$$$\  $$$$$$$\        $$ /  \__|$$ |$$\  $$$$$$\  $$$$$$$\ $$$$$$\  '
    echo '\$$\  $$  |$$ |$$  _____|$$ |$$  __$$\ $$  __$$\       $$ |      $$ |$$ |$$  __$$\ $$  __$$\\_$$  _| '
    echo ' \$$\$$  / $$ |\$$$$$$\  $$ |$$ /  $$ |$$ |  $$ |      $$ |      $$ |$$ |$$$$$$$$ |$$ |  $$ | $$ |       ⠀⠀⠀⠀⢀⣴á⣶⡄⠀⠀⠀⠀'
    echo '  \$$$  /  $$ | \____$$\ $$ |$$ |  $$ |$$ |  $$ |      $$ |  $$\ $$ |$$ |$$   ____|$$ |  $$ | $$ |$$\    ⢀⣴⣧⠀⠸⣿⣀⣸⡇⠀⢨⡦⣄'
    echo '   \$  /   $$ |$$$$$$$  |$$ |\$$$$$$  |$$ |  $$ |      \$$$$$$  |$$ |$$ |\$$$$$$$\ $$ |  $$ | \$$$$  |   ⠘⣿⣿⣄⠀⠈⠛⠉⠀⣠⣾⡿⠋'
    echo '    \_/    \__|\_______/ \__| \______/ \__|  \__|       \______/ \__|\__| \_______|\__|  \__|  \____/    ⠀⠀⠈⠛⠿⠶⣶⡶⠿⠟⠉'
    echo ""
    tput smam
    echo -e "  ${PURPLE}Vision Transmitter v2.0 (Low-Latency Mode)${NC}"
    echo -e "  ${PURPLE}Resolution: ${RESOLUTION} | Keyframe Interval: 5 (Fast Repair)${NC}"
    echo ""
}

# --- PROCESS STATUS CHECK ---
check_status() {
    if [ -f "$SERVER_PID_FILE" ] && ps -p $(cat "$SERVER_PID_FILE") > /dev/null; then
        SERVER_STATUS="${GREEN}RUNNING (PID $(cat "$SERVER_PID_FILE"))${NC}"
    else
        SERVER_STATUS="${RED}STOPPED${NC}"
    fi

    if [ -f "$STREAM_PID_FILE" ] && ps -p $(cat "$STREAM_PID_FILE") > /dev/null; then
        STREAM_STATUS="${GREEN}RUNNING (PID $(cat "$STREAM_PID_FILE"))${NC}"
    else
        STREAM_STATUS="${RED}STOPPED${NC}"
    fi
}

# --- FUNCTIONS ---

# 1. Install Dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing system dependencies...${NC}"
    sudo apt-get update
    sudo apt-get install -y git ffmpeg v4l-utils wget
    echo -e "${GREEN}System packages installed.${NC}"
    echo ""
    
    echo -e "${YELLOW}Downloading mediamtx server...${NC}"
    wget -O "${SCRIPT_DIR}/mediamtx.tar.gz" "$MEDIAMTX_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Download failed. Check URL or network.${NC}"
        return 1
    fi
    tar -xzvf "${SCRIPT_DIR}/mediamtx.tar.gz" -C "$SCRIPT_DIR" mediamtx mediamtx.yml
    # Backup default config if we haven't already
    if [ ! -f "${SCRIPT_DIR}/mediamtx.yml.default" ]; then
        mv "${SCRIPT_DIR}/mediamtx.yml" "${SCRIPT_DIR}/mediamtx.yml.default"
    fi
    rm "${SCRIPT_DIR}/mediamtx.tar.gz"
    chmod +x "$MEDIAMTX_BINARY"
    echo -e "${GREEN}mediamtx binary installed to ${MEDIAMTX_BINARY}${NC}"
    
    echo -e "${YELLOW}Creating optimized configuration file...${NC}"
    cat << EOF > "$MEDIAMTX_CONFIG_FILE"
httpProtocol:
  cors:
    - '*'
rtspPort: ${RTSP_PORT}
hlsPort: ${HLS_PORT}
webrtcPort: ${WEBRTC_PORT}
paths:
  ${STREAM_NAME}:
    publishUser: ${PUBLISH_USER}
    publishPass: ${PUBLISH_PASS}
    sourceOnDemand: no
EOF
    echo -e "${GREEN}Configuration file created!${NC}"
}

# 2. Start Server
start_server() {
    if [ -f "$SERVER_PID_FILE" ] && ps -p $(cat "$SERVER_PID_FILE") > /dev/null; then
        echo -e "${YELLOW}Server is already running.${NC}"
        return 1
    fi

    if [ ! -f "$MEDIAMTX_BINARY" ]; then
        echo -e "${RED}Error: 'mediamtx' binary not found. Run Install Dependencies.${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Starting mediamtx server...${NC}"
    nohup "$MEDIAMTX_BINARY" "$MEDIAMTX_CONFIG_FILE" > "$SERVER_LOG_FILE" 2>&1 &
    echo $! > "$SERVER_PID_FILE"
    
    sleep 1
    if ps -p $(cat $SERVER_PID_FILE) > /dev/null; then
        echo -e "${GREEN}Server started successfully!${NC}"
    else
        echo -e "${RED}Error: Server failed to start. Check log:${NC}"
        cat "$SERVER_LOG_FILE"
        rm -f "$SERVER_PID_FILE"
    fi
}

# 3. Stop Server
stop_server() {
    if [ ! -f "$SERVER_PID_FILE" ]; then return 0; fi
    local pid=$(cat "$SERVER_PID_FILE")
    echo -e "${YELLOW}Stopping mediamtx server (PID $pid)...${NC}"
    if kill -TERM "$pid" 2>/dev/null; then
        rm -f "$SERVER_PID_FILE"
        echo -e "${GREEN}Server stopped.${NC}"
    else
        rm -f "$SERVER_PID_FILE"
        echo -e "${RED}Could not kill process, removing lock file.${NC}"
    fi
}

# 4. Start Stream (THE CRITICAL PART)
start_stream() {
    if [ -f "$STREAM_PID_FILE" ] && ps -p $(cat "$STREAM_PID_FILE") > /dev/null; then
        echo -e "${YELLOW}Stream is already running.${NC}"
        return 1
    fi

    if [ ! -f "$SERVER_PID_FILE" ] || ! ps -p $(cat "$SERVER_PID_FILE") > /dev/null; then
        echo -e "${RED}Error: mediamtx server is not running. Start it first.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Starting ffmpeg stream...${NC}"
    echo -e "${CYAN}Source: ${VIDEO_DEVICE} | Res: ${RESOLUTION} | GOP: 5 (Fast Recovery)${NC}"
    
    # --- FFMPEG LATENCY OPTIMIZATIONS ---
    # -video_size: Lowered to 640x480 for stability over VPN/Wifi
    # -g 5: Keyframe sent every 5 frames (approx 6 times a second). 
    #       This fixes "Gray Smear" artifacts instantly.
    # -bufsize 0: Tells ffmpeg NOT to buffer data, send immediately.
    # -tune zerolatency: Optimization flag for h264.
    
    local FFMPEG_CMD="ffmpeg \
        -f v4l2 \
        -video_size ${RESOLUTION} \
        -framerate ${FPS} \
        -i ${VIDEO_DEVICE} \
        -c:v h264_v4l2m2m \
        -b:v ${BITRATE} \
        -maxrate ${BITRATE} \
        -bufsize 0 \
        -g 5 \
        -keyint_min 5 \
        -preset ultrafast \
        -tune zerolatency \
        -f rtsp \
        -rtsp_transport tcp \
        ${RTSP_URL}"

    # Log the command for debug
    echo "Running: $FFMPEG_CMD" >> "$STREAM_LOG_FILE"

    nohup bash -c "$FFMPEG_CMD" >> "$STREAM_LOG_FILE" 2>&1 &
    echo $! > "$STREAM_PID_FILE"
    
    sleep 2 
    if ps -p $(cat $STREAM_PID_FILE) > /dev/null; then
        echo -e "${GREEN}Stream started successfully!${NC}"
    else
        echo -e "${RED}Error: Stream failed to start. Check log:${NC}"
        cat "$STREAM_LOG_FILE"
        rm -f "$STREAM_PID_FILE"
    fi
}

# 5. Stop Stream
stop_stream() {
    if [ ! -f "$STREAM_PID_FILE" ]; then return 0; fi
    local pid=$(cat "$STREAM_PID_FILE")
    echo -e "${YELLOW}Stopping ffmpeg stream (PID $pid)...${NC}"
    if kill -TERM "$pid" 2>/dev/null; then
        rm -f "$STREAM_PID_FILE"
        echo -e "${GREEN}Stream stopped.${NC}"
    else
        rm -f "$STREAM_PID_FILE"
    fi
}

# 6. View Stream Log
view_stream_log() {
    if [ ! -f "$STREAM_LOG_FILE" ]; then echo -e "${RED}No log found.${NC}"; return 1; fi
    echo -e "${YELLOW}Showing live ffmpeg log (Press Ctrl+C to exit)...${NC}"
    tail -f -n 50 "$STREAM_LOG_FILE"
}

# 7. View Server Log
view_server_log() {
    if [ ! -f "$SERVER_LOG_FILE" ]; then echo -e "${RED}No log found.${NC}"; return 1; fi
    echo -e "${YELLOW}Showing live mediamtx log (Press Ctrl+C to exit)...${NC}"
    tail -f -n 50 "$SERVER_LOG_FILE"
}

# 8. Check Camera
check_camera() {
    if ! command -v v4l2-ctl &> /dev/null; then echo -e "${RED}Missing v4l-utils.${NC}"; return 1; fi
    echo -e "${YELLOW}Checking for V4L2 devices...${NC}"
    v4l2-ctl --list-devices
}

# 9. List Formats
list_camera_formats() {
    v4l2-ctl --list-formats-ext -d "$VIDEO_DEVICE"
}

# 12. Check System Health
check_system_health() {
    echo -e "${YELLOW}Checking Pi Health (Voltage/Temp)...${NC}"
    if command -v vcgencmd &> /dev/null; then
        TEMP=$(vcgencmd measure_temp)
        VOLT=$(vcgencmd measure_volts)
        THROTTLED=$(vcgencmd get_throttled)
        
        echo -e "Temperature: ${CYAN}$TEMP${NC}"
        echo -e "Voltage:     ${CYAN}$VOLT${NC}"
        
        if [[ "$THROTTLED" == *"throttled=0x0"* ]]; then
            echo -e "Status:      ${GREEN}OK (Power supply is good)${NC}"
        else
            echo -e "Status:      ${RED}WARNING! Throttling detected ($THROTTLED)${NC}"
            echo -e "${RED}Power supply may be undervolting.${NC}"
        fi
    else
        echo -e "${RED}Error: 'vcgencmd' not found. Is this a Raspberry Pi?${NC}"
    fi
}

# 10. Self Update
self_update() {
    echo -e "${YELLOW}Updating...${NC}"
    local SCRIPT_NAME=$(basename "$0")
    # Simple git pull mechanism
    git pull origin "$GIT_BRANCH"
    echo -e "${GREEN}Update complete. Please restart script.${NC}"
    exit 0
}

# --- MAIN MENU ---
while true; do
    check_status
    show_header
    echo -e "  Server Status: $SERVER_STATUS"
    echo -e "  Stream Status: $STREAM_STATUS"
    echo ""
    echo -e "${CYAN}--- PROCESS ---${NC}"
    echo -e "  ${GREEN}1.${NC} Start Server (mediamtx)"
    echo -e "  ${RED}2.${NC} Stop Server (mediamtx)"
    echo -e "  ${GREEN}3.${NC} Start Stream (ffmpeg)"
    echo -e "  ${RED}4.${NC} Stop Stream (ffmpeg)"
    echo -e "${CYAN}--- DEBUG ---${NC}"
    echo -e "  ${YELLOW}5.${NC} View Stream Log (FPS)"
    echo -e "  ${YELLOW}6.${NC} View Server Log"
    echo -e "  ${PURPLE}7.${NC} Check Camera (V4L2)"
    echo -e "  ${PURPLE}8.${NC} List Camera Formats"
    echo -e "${CYAN}--- SYSTEM ---${NC}"
    echo -e "  ${BLUE}9.${NC} Install Dependencies"
    echo -e "  ${BLUE}10.${NC} Update Script"
    echo -e "  ${BLUE}12.${NC} Check System Health (Voltage/Temp)"
    echo -e "  ${RED}11.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Choose an option:${NC}"
    read -r choice
    
    case $choice in
        1) start_server ;;
        2) stop_server ;;
        3) start_stream ;;
        4) stop_stream ;;
        5) view_stream_log ;;
        6) view_server_log ;;
        7) check_camera ;;
        8) list_camera_formats ;;
        9) install_dependencies ;;
        10) self_update ;;
        12) check_system_health ;;
        11) stop_stream; stop_server; exit 0 ;;
        *) echo -e "${RED}Invalid.${NC}" ;;
    esac
    echo "Press Enter..."
    read -r
done