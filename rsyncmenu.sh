#!/bin/bash

clear

# Set UTF-8 encoding to handle accented characters
export LC_ALL=C.UTF-8

# Check if rsync is installed
if ! command -v rsync &> /dev/null; then
    echo
    echo -e "\e[38;5;1mThis program requires rsync. Please install it with: sudo apt install rsync\e[0m"
    echo
    echo "Synchronization completed."
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

# Function to display error message in red
error_message() {
    echo -e "\e[38;5;1m$1\e[0m"
}

# Background animation function
animation_spinner() {
    local signal_file="$1"
    i=0
    sp="/-\|"
    while [ ! -f "$signal_file" ]; do
        printf "\b${sp:i++%${#sp}:1}"
        sleep 0.1
    done
    printf "\b"
}

echo "Rsyncmenu 1.0"
echo

# Ask for source directory
while true; do
    echo -n "Enter the source directory path: "
    read -r SOURCE

    if [[ -z "$SOURCE" ]]; then
        error_message "Error: Source path cannot be empty."
        continue
    fi

    # Resolve real path
    SOURCE_REAL=$(realpath "$SOURCE" 2>/dev/null)

    if [ ! -d "$SOURCE_REAL" ]; then
        error_message "Error: Source directory '$SOURCE' does not exist or is not accessible!"
        continue
    fi

    echo "Source directory validated: $SOURCE_REAL"
    break
done

echo

# Ask for destination directory
while true; do
    echo -n "Enter the destination directory path: "
    read -r DEST

    if [[ -z "$DEST" ]]; then
        error_message "Error: Destination path cannot be empty."
        continue
    fi

    # Resolve real path
    DEST_REAL=$(realpath "$DEST" 2>/dev/null)

    if [ ! -d "$DEST_REAL" ]; then
        error_message "Error: Destination directory '$DEST' does not exist or is not accessible!"
        continue
    fi

    # Check if source and destination are identical
    if [ "$SOURCE_REAL" == "$DEST_REAL" ]; then
        error_message "Error: Source and destination directories are identical!"
        continue
    fi

    echo "Destination directory validated: $DEST_REAL"
    break
done

echo
echo -n "Analyzing differences between directories... "

# Signal file for analysis
ANALYSIS_SIGNAL_FILE="/tmp/rsync_analysis_$"

# Start background animation for analysis
animation_spinner "$ANALYSIS_SIGNAL_FILE" &
ANALYSIS_SPINNER_PID=$!

# Analyze changes with a dry-run
TMP_DRYRUN=$(mktemp)
rsync -a --delete -n -i --exclude='.Trash-1000' "$SOURCE_REAL/" "$DEST_REAL/" > "$TMP_DRYRUN" 2>&1

# Count operations
total_operations=0
while IFS= read -r line; do
    if [[ "$line" =~ ^[\>c\*].* ]] || [[ "$line" =~ deleting ]]; then
        total_operations=$((total_operations + 1))
    fi
done < "$TMP_DRYRUN"

rm -f "$TMP_DRYRUN"

# Stop analysis animation
touch "$ANALYSIS_SIGNAL_FILE"
wait $ANALYSIS_SPINNER_PID 2>/dev/null
rm -f "$ANALYSIS_SIGNAL_FILE"

echo "Total operations detected: $total_operations"

if [ "$total_operations" -eq 0 ]; then
    clear
    echo "No synchronization needed - directories are already synchronized."
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 0
fi

# Ask for confirmation before switching to production mode
clear
echo "Analysis completed: $total_operations operation(s) to perform"
echo "Source      : $SOURCE_REAL"
echo "Destination : $DEST_REAL"
echo
echo -n "Do you want to switch to production mode (without dry-run)? (y/N) "
read -r confirm
if ! [[ "$confirm" =~ ^[yY]$ ]]; then
    echo "Dry-run mode activated: no modifications will be applied."
    PRODUCTION_MODE=0
else
    echo "Production mode activated: modifications will be applied."
    PRODUCTION_MODE=1
fi

# Perform synchronization with spinning cursor
echo
echo -n "Synchronization in progress... "

# Signal file for synchronization
SYNC_SIGNAL_FILE="/tmp/rsync_sync_$"

# Start background animation for synchronization
animation_spinner "$SYNC_SIGNAL_FILE" &
SYNC_SPINNER_PID=$!

# Perform synchronization
if [ "$PRODUCTION_MODE" -eq 1 ]; then
    RSYNC_OPTIONS="-a --delete --exclude='.Trash-1000'"
else
    RSYNC_OPTIONS="-a --delete -n --exclude='.Trash-1000'"
fi

# Execute synchronization
rsync $RSYNC_OPTIONS "$SOURCE_REAL/" "$DEST_REAL/" > /dev/null 2>&1

# Stop synchronization animation
touch "$SYNC_SIGNAL_FILE"
wait $SYNC_SPINNER_PID 2>/dev/null
rm -f "$SYNC_SIGNAL_FILE"

echo "completed."

# Display results
echo "Synchronization results:"
echo "-----------------------------"
echo "- Source: $SOURCE_REAL"
echo "- Destination: $DEST_REAL"
if [ "$PRODUCTION_MODE" -eq 1 ]; then
    echo "- Total operations completed: $total_operations"
else
    echo "- $total_operations operation(s) would have been performed"
fi

echo
echo "Synchronization completed."
echo "Operation finished."
echo -n "Press [ENTER] to quit ... "
read var_name
