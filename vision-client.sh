#!/bin/bash

# --- CONFIGURATION ---
PID_FILE="/tmp/streamer.pid"
GIT_BRANCH="main"

# --- STREAM CONFIG (NEW) ---
VIDEO_DEVICE="/dev/video0" # Default for HDMI capture card
WIDTH=1920
HEIGHT=1080
FRAMERATE=30
BITRATE=6000000 # 6 Mbps. Increase for higher quality, decrease if bandwidth is an issue.
RTSP_PATH="mystream"
RTSP_PORT="8554" # Default for mediamtx/rtsp-simple-server

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
    echo -e "  ${PURPLE}Big Brother Vision Client v0.23 (RTSP H.264)${NC}"
    echo ""
}

# --- FUNCTIONS ---

# 1. Install Dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    echo "This may take a few minutes."
    
    sudo apt-get update
    # We need v4l-utils for 'v4l2-ctl' (replaces gphoto2 check)
    # The 'v4l2h264enc' encoder is in the 'gstreamer1.0-plugins-good' package.
    # GStreamer plugins 'good' and 'bad' provide rtspclientsink and videoconvert.
    
    # --- THIS LINE IS THE FIX (v4l-utils) ---
    sudo apt-get install -y git gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-libav v4l-utils \
        netcat-traditional
    
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

    echo -e "${YELLOW}Enter your server's (Mac's) Tailscale IP address:${NC}"
    read -r SERVER_IP

    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}No IP address entered. Aborting.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Starting RTSP H.264 stream to rtsp://$SERVER_IP:$RTSP_PORT/$RTSP_PATH...${NC}"
    echo -e "${CYAN}Using Pi's hardware encoder for low-latency, high-quality stream.${NC}"
    
    # --- THIS IS THE QUOTATION FIX ---
    # We use single quotes for the 'extra-controls' property.
    # $BITRATE will be expanded by 'bash -c' because the *entire*
    # command is wrapped in double quotes for the 'nohup' command.
    PIPELINE="gst-launch-1.0 -v v4l2src device=$VIDEO_DEVICE \
        ! video/x-raw,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 \
        ! videoconvert \
        ! v4l2h264enc extra-controls='controls,video_bitrate=$BITRATE' \
        ! 'video/x-h264,stream-format=byte-stream,alignment=au,profile=high' \
        ! h264parse \
        ! rtph264pay config-interval=1 pt=96 \
        ! rtspclientsink location=rtsp://$SERVER_IP:$RTSP_PORT/$RTSP_PATH"

    # --- Start the chosen pipeline ---
    # We use 'bash -c' to correctly interpret the entire pipeline string,
    # including its internal quotes and variable expansion.
    nohup bash -c "$PIPELINE" > /tmp/streamer.log 2>&1 &
    
    echo $! > "$PID_FILE"
    
    sleep 2 
    if ps -p $(cat $PID_FILE) > /dev/null; then
        echo -e "${GREEN}Stream started successfully! (PID $(cat $PID_FILE))${NC}"
        echo "Log available at /tmp/streamer.log"
        echo -e "${YELLOW}View the stream at: rtsp://$SERVER_IP:$RTSP_PORT/$RTSP_PATH${NC}"
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
    
    # Kill the parent 'bash' process, which will also kill gst-launch
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

# 5. Check Camera (V4L2)
check_camera() {
    if ! command -v v4l2-ctl &> /dev/null; then
        echo -e "${RED}'v4l2-ctl' not found. Run 'Install/Update Dependencies' first.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Checking for V4L2 devices (capture cards / webcams)...${NC}"
    
    local devices
    devices=$(v4l2-ctl --list-devices)
    
    if [ -z "$devices" ]; then
        echo -e "${RED}Error: No V4L2 devices found.${NC}"
        echo "Is the HDMI capture card plugged in and powered on?"
    else
        echo -e "${GREEN}Success! Found the following device(s):${NC}"
        echo "$devices"
        echo -e "${CYAN}The script is configured to use '$VIDEO_DEVICE'.${NC}"
        echo "If this is incorrect, please edit the VIDEO_DEVICE variable at the top of the script."
    fi
}

# 6. Test RTSP Server Connection (TCP)
test_rtsp_connection() {
    if ! command -v nc &> /dev/null; then
        echo -e "${RED}'nc' (netcat) not found. Run 'Install/Update Dependencies' first.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Enter your server's (Mac's) Tailscale IP address:${NC}"
    read -r SERVER_IP

    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}No IP address entered. Aborting.${NC}"
        return 1
    fi

    echo -e "${CYAN}Testing connection to $SERVER_IP on TCP port $RTSP_PORT (the RTSP server port)...${NC}"
    
    nc -z -w 5 "$SERVER_IP" "$RTSP_PORT"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Success! Connection established.${NC}"
        echo "This means the IP is correct and the 'mediamtx' server is running."
    else
        echo -e "${RED}Failure. Could not connect.${NC}"
        echo "Check that 'mediamtx' is running on your Mac and not blocked by a firewall."
    fi
}


# --- MAIN MENU (Re-numbered) ---
while true; do
    show_header
    echo -e "${GREEN}1.${NC} Install/Update Dependencies"
    echo -e "${GREEN}2.${NC} Start Stream (RTSP/H.264)"
    echo -e "${GREEN}3.${NC} Stop Stream"
    echo -e "${CYAN}4.${NC} Check Camera (V4L2)"
    echo -e "${BLUE}5.${NC} Test RTSP Server Connection (TCP $RTSP_PORT)"
    echo -e "${YELLOW}6.${NC} Update This Script (from GitHub)"
    echo -e "${RED}7.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Choose an option [1-7]:${NC}"
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
        4. | 5)
            # Handle 4 and 5 which are now different
            if [ "$choice" = "4" ]; then
                check_camera
            else
                test_rtsp_connection
            fi
            ;;
        6)
            self_update
            ;;
        7)
            echo "Exiting."
            stop_stream # Try to stop stream on exit
            exit 0
            ;;
        *)
            # Handle old menu numbers gracefully
            if [ "$choice" = "5" ] || [ "$choice" = "6" ]; then
                 echo -e "${YELLOW}Menu has changed. Please select from the new options.${NC}"
            elif [ "$choice" = "8" ]; then
                 echo "Exiting."
                 stop_stream
                 exit 0
            else
                echo -e "${RED}Invalid option. Please try again.${NC}"
            fi
            ;;
    esac
    echo ""
    echo "Press Enter to return to the menu..."
    read -r
done