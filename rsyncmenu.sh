#!/bin/bash
#
# SCRIPT: Synchronization with Progress Bar and Spinner
# Description: Synchronizes a source directory to a destination
# with real progress bar (without backup system)
#

clear
# Set UTF-8 encoding to handle accented characters
export LC_ALL=C.UTF-8

# Check if rsync is installed
if ! command -v rsync &> /dev/null; then
    echo
    echo -e "\e[38;5;1mThis program requires rsync. Please install it with: sudo apt install rsync\e[0m"
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

# Check if realpath is installed
if ! command -v realpath &> /dev/null; then
    echo
    echo -e "\e[38;5;1mThis program requires realpath. Please install it with: sudo apt install coreutils\e[0m"
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

# Function to display an error message in red
error_message() {
    echo -e "\e[38;5;1m$1\e[0m"
}

# --- START OF SCRIPT ---
echo "Directory synchronization with rsync 1.2 (Dynamic progress with stdbuf)"
echo

# Input directories
echo "Enter the absolute path of the source directory:"
read -r SOURCE_DIR
SOURCE_DIR_REAL=$(realpath "$SOURCE_DIR" 2>/dev/null)

if [ ! -d "$SOURCE_DIR_REAL" ]; then
    error_message "Error: Invalid source directory."
    exit 1
fi

echo "Enter the absolute path of the destination directory:"
read -r DEST_DIR
DEST_DIR_REAL=$(realpath "$DEST_DIR" 2>/dev/null)

if [ ! -d "$DEST_DIR_REAL" ]; then
    error_message "Error: Invalid destination directory."
    exit 1
fi

if [ "$SOURCE_DIR_REAL" == "$DEST_DIR_REAL" ]; then
    error_message "Error: Source and destination are identical."
    exit 1
fi

# --- ANALYSIS PHASE (Dry-run to count files) ---
DRYRUN_FILE="/tmp/dr$$"
ANALYSIS_FLAG="/tmp/af$$"
rm -f "$ANALYSIS_FLAG"

(
    rsync -a --delete -n -i --exclude=.Trash-1000 "$SOURCE_DIR_REAL/" "$DEST_DIR_REAL/" > "$DRYRUN_FILE" 2>&1
    touch "$ANALYSIS_FLAG"
) &
ANALYSIS_PID=$!

i=1
sp="/-\|"
printf "\e[?25lAnalyzing differences...  "
while [ ! -f "$ANALYSIS_FLAG" ]; do
    printf "\b${sp:i++%${#sp}:1}"
    sleep 0.1
done
printf "\e[?25h\b \n"
wait $ANALYSIS_PID

# Precise counting of operations (same regex as the progress loop)
total_operations=$(grep -E '^[[:space:]]*deleting|^[><fcLh*]' "$DRYRUN_FILE" 2>/dev/null | wc -l | awk '{print $1+0}')
rm -f "$DRYRUN_FILE" "$ANALYSIS_FLAG"

if [ "$total_operations" -eq 0 ]; then
    echo "No synchronization needed."
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 0
fi

# --- CONFIRMATION ---
echo "Analysis complete: $total_operations operations detected."
echo -n "Switch to production mode? (y/N) "
read -r confirm

if ! [[ "$confirm" =~ ^[yY]$ ]]; then
    echo "Aborted or dry-run complete."
    exit 0
fi

# --- SYNCHRONIZATION PHASE WITH PROGRESS BAR ---
clear
echo "Synchronization in progress..."

# Build options
RSYNC_OPTS="-a --delete -i --exclude=.Trash-1000"

# Initialize progress bar variables
current=0
sp_idx=1
bar_size=40

# Hide cursor
printf "\e[?25l"

# Launch rsync with stdbuf to force line buffering (real-time progress)
# stdbuf -oL forces line-by-line output instead of buffering
while IFS= read -r line; do
    # Only process lines indicating a transfer or deletion
    if [[ "$line" =~ ^[[:space:]]*deleting|^[\>\<fcLh\*] ]]; then
        ((current++))

        # Calculate percentage
        percent=$(( current * 100 / total_operations ))
        if [ $percent -gt 100 ]; then percent=100; fi

        # Calculate bar
        completed=$(( current * bar_size / total_operations ))
        if [ $completed -gt $bar_size ]; then completed=$bar_size; fi
        remaining=$(( bar_size - completed ))

        # Build bar string
        bar_str=$(printf "%${completed}s" | tr ' ' '#')
        dot_str=$(printf "%${remaining}s" | tr ' ' '-')

        # Spinner animation
        char=${sp:sp_idx++%${#sp}:1}

        # Display: \r returns to beginning, \e[K clears the line
        printf "\r\e[K[%-${bar_size}s] %d%% %s (%d/%d)" "$bar_str$dot_str" "$percent" "$char" "$current" "$total_operations"
    fi
done < <(stdbuf -oL rsync $RSYNC_OPTS "$SOURCE_DIR_REAL/" "$DEST_DIR_REAL/")

# Show cursor again
printf "\e[?25h\n\n"

# --- FINAL RESULTS ---
echo "Synchronization results:"
echo "-----------------------------"
echo "- Total operations performed: $total_operations"
echo
echo "Operation complete."
echo -n "Press [ENTER] to quit ... "
read var_name
