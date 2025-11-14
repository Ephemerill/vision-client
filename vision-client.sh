#!/bin/bash

# --- CONFIGURATION ---
PID_FILE="/tmp/streamer.pid"
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
    echo "  ${PURPLE}Tailscale Webcam Streamer v2.6 (gphoto2)${NC}"
    echo ""
}

# --- FUNCTIONS ---

# 1. Install Dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing dependencies (git, gstreamer, gphoto2)...${NC}"
    echo "This may take a few minutes."
    
    sudo apt-get update
    # --- UPDATED: Added gphoto2 and libgphoto2-6 ---
    sudo apt-get install -y git gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav gphoto2 libgphoto2-6
    
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

    echo -e "${GREEN}Starting stream from gphoto2 (EOS Camera) to $SERVER_IP:$PORT...${NC}"
    echo -e "${CYAN}This is now an ultra-lightweight stream! No software encoding.${NC}"

    # --- UPDATED: gphoto2 pipeline ---
    # This pipes the camera's native H.264 stream directly to GStreamer.
    # - gphoto2: Captures the movie stream and sends to stdout.
    # - fdsrc: GStreamer element that reads from a file descriptor (fd=0 is stdin).
    # - h264parse: Parses the H.264 stream for network transmission.
    # - rtph264pay: Packages the H.264 video into RTP packets.
    # - udpsink: Sends the packets to the server.
    nohup bash -c "gphoto2 --stdout --capture-movie | \
        gst-launch-1.0 -q fdsrc fd=0 \
        ! h264parse \
        ! rtph264pay config-interval=1 pt=96 \
        ! udpsink host=$SERVER_IP port=$PORT" > /tmp/streamer.log 2>&1 &
    
    # Save the PID of the background process
    echo $! > "$PID_FILE"
    
    sleep 2 # Give it a moment to start
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
        echo -e "${RED}Error: This script is not in a git repository.${NC}"
        return 1
    fi

    echo "Creating temporary updater stub..."
    cat << EOF > ./updater.sh
#!/bin/bash
echo "Fetching updates from git..."
git fetch --all
git reset --hard origin/$GIT_BRANCH
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: 'git reset' failed. Update aborted.${NC}"
    rm -- "\$0"
    exit 1
fi
echo "Update successful."
echo "Relaunching $SCRIPT_NAME..."
chmod +x "$SCRIPT_NAME"
rm -- "\$0"
exec "./$SCRIPT_NAME"
EOF
    chmod +x ./updater.sh
    echo -e "${GREEN}Handing over to updater. The script will now restart...${NC}"
    exec ./updater.sh
}

# --- UPDATED: Now uses gphoto2 ---
# 5. Check Camera
check_camera() {
    if ! command -v gphoto2 &> /dev/null; then
        echo -e "${RED}'gphoto2' not found. Run 'Install/Update Dependencies' first.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Checking for gphoto2-compatible cameras...${NC}"
    
    if gphoto2 --auto-detect | grep -q "Canon"; then
        echo -e "${GREEN}Success! Found the following camera(s):${NC}"
        gphoto2 --auto-detect
    else
        echo -e "${RED}Error: No gphoto2 cameras found.${NC}"
        echo "Please ensure your EOS camera is plugged in and set to movie mode."
    fi
}


# --- MAIN MENU (Re-numbered) ---
while true; do
    show_header
    echo -e "${GREEN}1.${NC} Install/Update Dependencies"
    echo -e "${GREEN}2.${NC} Start Stream"
    echo -e "${GREEN}3.${NC} Stop Stream"
    echo -e "${CYAN}4.${NC} Check Camera (gphoto2)"
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
        4)
            check_camera
            ;;
        5)
            self_update
            ;;
        6)
            echo "Exiting."
            stop_stream
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    ac
    echo ""
    echo "Press Enter to return to the menu..."
    read -r
done