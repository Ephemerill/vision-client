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
    tput rmam
    clear
    echo -e "${CYAN}"
    echo '$$\    $$\ $$\           $$\                            $$$$$$\  $$\ $$\                      $$\  '
    echo '$$ |   $$ |\__|          \__|                          $$  __$$\ $$ |\__|                     $$ |'
    echo '$$ |   $$ |$$\  $$$$$$$\ $$\  $$$$$$\  $$$$$$$\        $$ /  \__|$$ |$$\  $$$$$$\  $$$$$$$\ $$$$$$\  '
    echo '\$$\  $$  |$$ |$$  _____|$$ |$$  __$$\ $$  __$$\       $$ |      $$ |$$ |$$  __$$\ $$  __$$\\_$$  _| '
    echo ' \$$\$$  / $$ |\$$$$$$\  $$ |$$ /  $$ |$$ |  $$ |      $$ |      $$ |$$ |$$$$$$$$ |$$ |  $$ | $$ |       ⠀⠀⠀⠀⢀⣴⠶⣶⡄⠀⠀⠀⠀'
    echo '  \$$$  /  $$ | \____$$\ $$ |$$ |  $$ |$$ |  $$ |      $$ |  $$\ $$ |$$ |$$   ____|$$ |  $$ | $$ |$$\    ⢀⣴⣧⠀⠸⣿⣀⣸⡇⠀⢨⡦⣄'
    echo '   \$  /   $$ |$$$$$$$  |$$ |\$$$$$$  |$$ |  $$ |      \$$$$$$  |$$ |$$ |\$$$$$$$\ $$ |  $$ | \$$$$  |   ⠘⣿⣿⣄⠀⠈⠛⠉⠀⣠⣾⡿⠋'
    echo '    \_/    \__|\_______/ \__| \______/ \__|  \__|       \______/ \__|\__| \_______|\__|  \__|  \____/    ⠀⠀⠈⠛⠿⠶⣶⡶⠿⠟⠉'
    echo ""
    tput smam
    echo -e "  ${PURPLE}Big Brother Vision Client v0.15 (Optimized)${NC}"
    echo ""
}

# --- FUNCTIONS ---

# 1. Install Dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    echo "This may take a few minutes."
    
    sudo apt-get update
    # netcat-traditional is for the handshake test
    # gstreamer1.0-plugins-bad is for 'avdec_mjpeg' (fast MJPEG decoder)
    # gstreamer1.0-v4l2-utils provides the 'v4l2h264enc' hardware encoder
    sudo apt-get install -y git gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-v4l2-utils \
        gphoto2 libgphoto2-6 netcat-traditional
    
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
    
    # --- FINAL PLAN: 720p MJPEG Stream ---
    # We are giving up on H.264. It's a buggy-driver-and-stuttery-mess.
    # We are going back to your ORIGINAL low-latency MJPEG pipeline,
    # but we will scale to 720p on the Pi to fix the bandwidth.
    # 'jpegenc' is *much* faster than 'x264enc'.
    
    echo -e "${GREEN}Starting 720p MJPEG stream to $SERVER_IP:$PORT...${NC}"
    echo -e "${CYAN}This is low-latency and fixes the bandwidth problem.${NC}"
    
    PIPELINE="gst-launch-1.0 -q fdsrc fd=0 \
        ! jpegparse \
        ! avdec_mjpeg \
        ! videoconvert \
        ! videoscale \
        ! capsfilter caps=\"video/x-raw,width=1280,height=720\" \
        ! jpegenc quality=90 \
        ! rtpjpegpay pt=96 \
        ! udpsink host=$SERVER_IP port=$PORT"

    # --- Start the chosen pipeline ---
    nohup bash -c "gphoto2 --stdout --capture-movie | $PIPELINE" > /tmp/streamer.log 2>&1 &
    
    echo $! > "$PID_FILE"
    
    sleep 2 
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
    
    # Kill the parent 'bash' process, which will also kill gphoto2 and gst-launch
    if kill -TERM "$pid" 2>/dev/null; then
        # Wait for process to disappear
        timeout=5
        while [ $timeout -gt 0 ] && ps -p $pid > /dev/null; do
            sleep 0.1
            ((timeout--))
        done
        
        if ps -p $pid > /dev/null; then
            echo -e "${YELLOW}Process $pid did not terminate gracefully, sending KILL...${NC}"
            kill -KILL "$pid" 2>/dev/null
        fi

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

# 5. Check Camera (gphoto2)
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
        echo -e "${RED}Warning: 'gphoto2 --auto-detect' found no camera.${NC}"
        echo -e "${YELLOW}This is common. If your manual command works, the stream will work.${NC}"
    fi
}

# 6. Handshake Test (TCP)
handshake_test_tcp() {
    if ! command -v nc &> /dev/null; then
        echo -e "${RED}'nc' (netcat) not found. Run 'Install/Update Dependencies' first.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Enter your server's Tailscale IP address:${NC}"
    read -r SERVER_IP

    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}No IP address entered. Aborting.${NC}"
        return 1
    fi

    echo -e "${CYAN}Testing connection to $SERVER_IP on TCP port 8080 (the web receiver)...${NC}"
    
    nc -z -w 5 "$SERVER_IP" 8080
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Success! Connection established.${NC}"
        echo "This means the IP is correct and the receiver.sh script is running."
    else
        echo -e "${RED}Failure. Could not connect.${NC}"
        echo "Check that 'receiver.sh' is running AND index.html is open in a browser."
    fi
}

# 7. Handshake Test (UDP)
handshake_test_udp() {
    if ! command -v nc &> /dev/null; then
        echo -e "${RED}'nc' (netcat) not found. Run 'Install/Update Dependencies' first.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Enter your server's Tailscale IP address:${NC}"
    read -r SERVER_IP

    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}No IP address entered. Aborting.${NC}"
        return 1
    fi

    echo -e "${CYAN}Testing connection to $SERVER_IP on UDP port 5000 (the stream port)...${NC}"
    echo "Please make sure the receiver.sh is STOPPED and you ran 'ncat -u -l 5000' on the server."
    echo -n "Press Enter to send UDP packet..."
    read -r
    
    # Send a UDP packet
    echo -n "udp_test_packet" | nc -u -w 3 "$SERVER_IP" 5000
    
    echo "Packet sent."
    echo "Check your 'ncat' terminal on the server. Did 'udp_test_packet' appear?"
}


# --- MAIN MENU (Re-numbered) ---
while true; do
    show_header
    echo -e "${GREEN}1.${NC} Install/Update Dependencies"
    echo -e "${GREEN}2.${NC} Start Stream (H.264)"
    echo -e "${GREEN}3.${NC} Stop Stream"
    echo -e "${CYAN}4.${NC} Check Camera (gphoto2)"
    echo -e "${BLUE}5.${NC} Run TCP Handshake (Port 8080)"
    echo -e "${BLUE}6.${NC} Run UDP Stream Test (Port 5000)"
    echo -e "${YELLOW}7.${NC} Update This Script (from GitHub)"
    echo -e "${RED}8.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Choose an option [1-8]:${NC}"
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
            handshake_test_tcp
            ;;
        6)
            handshake_test_udp
            ;;
        7)
            self_update
            ;;
        8)
            echo "Exiting."
            stop_stream # Try to stop stream on exit
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