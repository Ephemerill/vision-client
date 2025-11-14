#!/bin/bash

# --- CONFIGURATION ---
# This is the PID file to track the running stream
PID_FILE="/tmp/streamer.pid"
# If your repo's main branch is 'master', change this:
GIT_BRANCH="main"

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- ASCII ART ---
show_header() {
    clear
    echo -e "${CYAN}"
    echo "    ___   __   __      __     ___  __  "
    echo "   / _ \ / /_ / /__ __/ /_   / _ \/ /__"
    echo "  / ___// __// / -_) / __/  / ___/ / -_)"
    echo " /_/   \__//_/\__/\__\__/  /_/  /_/\__/"
    echo "  ${PURPLE}Tailscale Webcam Streamer v2.2 (Camera Check)${NC}"
    echo ""
}

# --- FUNCTIONS ---

# 1. Install Dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing dependencies (git, gstreamer)...${NC}"
    echo "This may take a few minutes."
    
    sudo apt-get update
    # Removed 'gstreamer1.0-omx-rpi' which is for RPi OS
    sudo apt-get install -y git gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Dependencies installed successfully.${NC}"
    else
        echo -e "${RED}Error: Dependency installation failed.${NC}"
    fi
}

# 2. Start Stream
start_stream() {
    if [ -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Stream is already running (PID $(cat $PID_FILE)).${NC}"
        echo "Please stop it first."
        return 1
    fi

    echo -e "${YELLOW}Enter your server's Tailscale IP address:${NC}"
    read -r SERVER_IP

    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}No IP address entered. Aborting.${NC}"
        return 1
    fi

    # --- Stream Configuration ---
    PORT="5000"
    WIDTH=1920
    HEIGHT=1080
    FRAMERATE=30
    BITRATE=6000000 # 6 Mbps

    echo -e "${GREEN}Starting stream to $SERVER_IP:$PORT...${NC}"
    echo "Settings: ${WIDTH}x${HEIGHT} @ ${FRAMERATE}fps, Bitrate: $BITRATE"

    # GStreamer Pipeline for Ubuntu on Pi (v4l2h264enc)
    nohup gst-launch-1.0 v4l2src device=/dev/video0 \
        ! "video/x-raw,width=$WIDTH,height=$HEIGHT,framerate=${FRAMERATE}/1" \
        ! videoconvert \
        ! v4l2h264enc extra-controls="controls,video_bitrate=$BITRATE;" \
        ! "video/x-h264,profile=high" \
        ! h264parse \
        ! rtph264pay config-interval=1 pt=96 \
        ! udpsink host="$SERVER_IP" port=$PORT > /tmp/streamer.log 2>&1 &
    
    # Save the PID of the background process
    echo $! > "$PID_FILE"
    
    sleep 1
    if ps -p $(cat $PID_FILE) > /dev/null; then
        echo -e "${GREEN}Stream started successfully! (PID $(cat $PID_FILE))${NC}"
        echo "Log available at /tmp/streamer.log"
    else
        echo -e "${RED}Error: Stream failed to start. Check log for details:${NC}"
        cat /tmp/streamer.log
        rm -f "$PID_FILE"
    fi
}

# 3. Stop Stream
stop_stream() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Stream is not running.${NC}"
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    echo "Stopping stream (PID $pid)..."
    
    # Kill the process
    if kill "$pid" 2>/dev/null; then
        rm -f "$PID_FILE"
        echo -e "${GREEN}Stream stopped.${NC}"
    else
        echo -e "${RED}Error: Could not kill process $pid.${NC}"
        echo "It may have already stopped. Removing stale PID file."
        rm -f "$PID_FILE"
    fi
}

# 4. Self-Update
self_update() {
    echo -e "${YELLOW}Attempting to self-update...${NC}"

    local SCRIPT_NAME
    SCRIPT_NAME=$(basename "$0")
    
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo -e "${RED}Error: This script is not inside a git repository.${NC}"
        echo "Please clone the repository first to enable updates."
        return 1
    fi

    echo "Creating temporary updater stub..."
    
    # Create the updater stub
    cat << EOF > ./updater.sh
#!/bin/bash
echo "Fetching updates from git..."
git fetch --all
git reset --hard origin/$GIT_BRANCH

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: 'git reset' failed. Update aborted.${NC}"
    echo "You may need to resolve conflicts manually."
    rm -- "\$0" # Delete self (the updater)
    exit 1
fi

echo "Update successful."
echo "Relaunching $SCRIPT_NAME..."
chmod +x "$SCRIPT_NAME"

# Delete this updater script and exec the new main script
rm -- "\$0"
exec "./$SCRIPT_NAME"
EOF

    # Make the updater executable
    chmod +x ./updater.sh

    echo -e "${GREEN}Handing over to updater. The script will now restart...${NC}"
    
    # Execute the updater and exit this script
    exec ./updater.sh
}

# --- NEW FUNCTION ---
# 5. Check Camera
check_camera() {
    echo -e "${YELLOW}Checking for connected cameras...${NC}"
    
    # Check if any /dev/video* devices exist
    if ls /dev/video* 1> /dev/null 2>&1; then
        echo -e "${GREEN}Success! Found the following camera(s):${NC}"
        # List all video devices
        ls -l /dev/video*
    else
        echo -e "${RED}Error: No cameras found.${NC}"
        echo "Please ensure your webcam is plugged in."
    fi
}


# --- MAIN MENU ---
while true; do
    show_header
    echo -e "${GREEN}1.${NC} Install/Update Dependencies"
    echo -e "${GREEN}2.${NC} Start Stream"
    echo -e "${GREEN}3.${NC} Stop Stream"
    echo -e "${CYAN}4.${NC} Check Camera"
    echo -e "${YELLOW}5.${NC} Update This Script (from GitHub)"
    echo -e "${RED}6.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Choose an option [1-6]:${NC}"
    read -r choice

    case $choice in
        1)
            install_dependencies
            ;;
        2)
            start_stream
            ;;
        3)
            stop_stream
            ;;
        4 | 4) # Renumbered from 4 to 5
            check_camera
            ;;
        5 | 5) # Renumbered from 4 to 5
            self_update
            ;;
        6 | 6) # Renumbered from 5 to 6
            echo "Exiting."
            stop_stream # Ensure stream is stopped on exit
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    esac
    echo ""
    echo "Press Enter to return to the menu..."
    read -r
done