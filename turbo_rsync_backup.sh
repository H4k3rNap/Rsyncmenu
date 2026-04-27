#!/bin/bash
###############################################################################
#
# SCRIPT : turbo_rsync_backup.sh
#
# Batch directory synchronization with rsync, featuring a progress UI
# inspired by Microsoft Defrag (MS-DOS): a colored block grid that fills up
# progressively, "Status" and "Legend" panels at the bottom, and a red
# status bar showing the current operation.
#
# -----------------------------------------------------------------------------
# HIGH-LEVEL FLOW
# -----------------------------------------------------------------------------
#
#  STEP  0 : Initialization (LC_ALL, temp files, cleanup trap, ANSI codes)
#  STEP  1 : Dependency check (rsync, realpath, tput)
#  STEP  2 : Validate the SYNC_PAIRS array from USER CONFIGURATION
#  STEP  3 : Ask the user whether to enable backup mode
#  STEP  4 : Ask the user whether to limit rsync bandwidth (bwlimit menu)
#  STEP  5 : Apply kernel tuning (vm.dirty_bytes) if bwlimit is active
#  STEP  6 : Prepare the backup directory (rotate previous run if any)
#  STEP  7 : Validate every "SOURCE:DESTINATION" pair (realpath, dir checks)
#  STEP  8 : Detect terminal size and compute the Defrag UI layout
#  STEP  9 : ANALYSIS PHASE (rsync dry-run -n -i, count operations)
#  STEP 10 : Disk-space check for backup mode (vs df + 10% margin)
#  STEP 11 : Special case "nothing to do"
#  STEP 12 : Confirm switch from dry-run to production
#  STEP 13 : SYNCHRONIZATION PHASE (real rsync) with Defrag-style UI
#  STEP 14 : Restore the screen
#  STEP 15 : Print final report
#  STEP 16 : Restore kernel parameters if they were modified
#  STEP 17 : Exit
#
# Dependencies: rsync, coreutils (realpath), ncurses-bin (tput), bash 4+
# Optional: sudo (only needed for the kernel tuning step, which is skipped
#           gracefully if sudo isn't available).
#
# Format of SYNC_PAIRS (see USER CONFIGURATION below):
#   one entry per pair, "SOURCE_PATH:DESTINATION_PATH"
#   Both directories must already exist; they cannot be identical.
#
# Notes on the Defrag-style UI internals (palette, cell rendering, animation,
# anti-flicker tricks, terminal size quirks under lxterminal, etc.) are
# documented in README.md to keep this script header concise.
#
###############################################################################

# ============================================================================
# USER CONFIGURATION — edit these to match your setup
# ============================================================================

# Sync pairs: SOURCE:DESTINATION (one per array element).
# Both directories must already exist.
# Comment out a line (with #) to disable that pair.
SYNC_PAIRS=(
    "/path/to/source:/path/to/destination"
    # "${HOME}/Documents:/media/${USER}/BACKUP/Documents"
    # "${HOME}/Pictures:/mnt/nas/Pictures"
)

# Root directory where the backup folder will be created.
# Default: $HOME/turbo_rsync_backups (works out of the box).
# Strict-mode example: BACKUP_ROOT="/media/USERNAME/DATAS"
BACKUP_ROOT="${HOME}/turbo_rsync_backups"

# Subdirectory inside BACKUP_ROOT where overwritten/deleted files are archived.
BACKUP_SUBDIR="backupsync"

# Derived (do not edit unless you know what you do).
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_SUBDIR}"

# Bandwidth menu presets (MB/s) — used by the interactive bwlimit menu.
BWLIMIT_PRESET_HIGH=150
BWLIMIT_PRESET_LOW=100

# Kernel tuning applied when bwlimit is active (bytes).
# These shrink the write-back cache so an external USB SSD doesn't appear
# "instantly fast" then stall for minutes flushing dirty pages.
DIRTY_BYTES_VALUE=50000000
DIRTY_BACKGROUND_BYTES_VALUE=25000000

# Patterns excluded from rsync (one element per --exclude).
RSYNC_EXCLUDES=(".Trash-1000")

# ============================================================================
# END OF USER CONFIGURATION
# ============================================================================


clear

# ============================================================================
# STEP 0 — Initialization
# ============================================================================
export LC_ALL=C.UTF-8

DRYRUN_FILE="/tmp/dr$$"
ANALYSIS_FLAG="/tmp/af$$"
SYSCTL_MODIFIED=0

# Useful ANSI codes (Defrag palette)
ESC=$'\033'
C_RESET="${ESC}[0m"
C_BG_BLUE="${ESC}[48;5;19m"
C_BG_BLACK="${ESC}[48;5;0m"
C_BG_RED="${ESC}[48;5;88m"
C_BG_YELLOW="${ESC}[48;5;226m"
# Blinking variant: used for the "Current" cursor that moves across the
# grid. ANSI attribute 5 = slow blink. Not all terminals support it — on
# those that ignore it, the cursor simply stays solid yellow (no regression).
C_BG_YELLOW_BLINK="${ESC}[5;48;5;226m"
C_BG_WHITE="${ESC}[48;5;255m"
C_BG_GREY="${ESC}[48;5;240m"
C_FG_WHITE="${ESC}[38;5;255m"
C_FG_LBLUE="${ESC}[38;5;110m"
C_FG_BLUE="${ESC}[38;5;19m"
C_FG_YELLOW="${ESC}[1;38;5;226m"
C_FG_RED="${ESC}[1;38;5;196m"
C_FG_BLACK="${ESC}[38;5;0m"
HIDE_CUR="${ESC}[?25l"
SHOW_CUR="${ESC}[?25h"
CLEAR_SCR="${ESC}[2J${ESC}[H"

cleanup() {
    printf "%s%s\n" "$SHOW_CUR" "$C_RESET"
    rm -f "$DRYRUN_FILE" "$ANALYSIS_FLAG"
    if [ "$SYSCTL_MODIFIED" -eq 1 ] 2>/dev/null; then
        sudo sysctl -w vm.dirty_bytes=0 > /dev/null 2>&1
        sudo sysctl -w vm.dirty_background_bytes=0 > /dev/null 2>&1
    fi
}
trap cleanup EXIT

error_message() {
    printf "%b%s%b\n" "$C_FG_RED" "$1" "$C_RESET"
}

# ============================================================================
# STEP 1 — Dependency check
# ============================================================================
if ! command -v rsync &> /dev/null; then
    echo
    error_message "This script requires rsync. Please install it: sudo apt install rsync"
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

if ! command -v realpath &> /dev/null; then
    echo
    error_message "This script requires realpath. Please install it: sudo apt install coreutils"
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

# tput is almost always available; if not, we fall back to default values.
HAS_TPUT=0
command -v tput &> /dev/null && HAS_TPUT=1

# ============================================================================
# STEP 2 — Validate the SYNC_PAIRS array
# ============================================================================
if [ ${#SYNC_PAIRS[@]} -eq 0 ]; then
    error_message "Error: SYNC_PAIRS is empty. Please edit the USER CONFIGURATION section at the top of this script."
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

# Detect the placeholder value to give a helpful error message.
if [ ${#SYNC_PAIRS[@]} -eq 1 ] && [ "${SYNC_PAIRS[0]}" = "/path/to/source:/path/to/destination" ]; then
    error_message "Error: SYNC_PAIRS still contains the default placeholder."
    error_message "Please edit the USER CONFIGURATION section at the top of this script and set your real source:destination pairs."
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

# ============================================================================
# STEP 3 — User choice: backup mode
# ============================================================================
echo "Directory synchronization with rsync (Defrag-style UI)"
echo
echo -n "Enable backup of deleted/overwritten files? (Y/n) "
read -r backup_choice
if [[ "$backup_choice" =~ ^[nN]$ ]]; then
    echo "Backup mode disabled."
    BACKUP_MODE=0
else
    echo "Backup mode enabled."
    BACKUP_MODE=1
fi

# ============================================================================
# STEP 4 — User choice: rsync bandwidth limit
# ============================================================================
echo
echo "Limit rsync bandwidth? (useful for external USB SSDs)"
echo "  1) No limit"
echo "  2) ${BWLIMIT_PRESET_HIGH} MB/s"
echo "  3) ${BWLIMIT_PRESET_LOW} MB/s"
echo "  4) Custom"
echo -n "Your choice [1-4] (default: 1): "
read -r bwlimit_choice
case "$bwlimit_choice" in
    2) BWLIMIT=$((BWLIMIT_PRESET_HIGH * 1000)) ; echo "Bandwidth limited to ${BWLIMIT_PRESET_HIGH} MB/s." ;;
    3) BWLIMIT=$((BWLIMIT_PRESET_LOW * 1000))  ; echo "Bandwidth limited to ${BWLIMIT_PRESET_LOW} MB/s." ;;
    4)
        echo -n "Enter bandwidth in MB/s: "
        read -r custom_bw
        if [[ "$custom_bw" =~ ^[0-9]+$ ]] && [ "$custom_bw" -gt 0 ]; then
            BWLIMIT=$((custom_bw * 1000))
            echo "Bandwidth limited to ${custom_bw} MB/s."
        else
            echo "Invalid value, no limit applied."
            BWLIMIT=0
        fi
        ;;
    *) BWLIMIT=0 ; echo "No bandwidth limit." ;;
esac

# ============================================================================
# STEP 5 — Apply kernel parameters (if bwlimit is active)
# ============================================================================
if [ "$BWLIMIT" -gt 0 ]; then
    echo "Applying kernel parameters to limit the write-back cache..."
    if sudo sysctl -w vm.dirty_bytes="$DIRTY_BYTES_VALUE" > /dev/null 2>&1 && \
       sudo sysctl -w vm.dirty_background_bytes="$DIRTY_BACKGROUND_BYTES_VALUE" > /dev/null 2>&1; then
        SYSCTL_MODIFIED=1
        echo "Kernel parameters applied (dirty_bytes=${DIRTY_BYTES_VALUE}, dirty_background_bytes=${DIRTY_BACKGROUND_BYTES_VALUE})."
    else
        echo "Could not modify kernel parameters (sudo required). Falling back to bwlimit only."
    fi
fi
echo

# ============================================================================
# STEP 6 — Prepare the backup directory
# ============================================================================
if [ "$BACKUP_MODE" -eq 1 ]; then
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "Backup root '$BACKUP_ROOT' does not exist. Creating it..."
        if ! mkdir -p "$BACKUP_ROOT"; then
            error_message "Error: Could not create '$BACKUP_ROOT'. The script will exit."
            echo
            echo -n "Press [ENTER] to quit ... "
            read var_name
            exit 1
        fi
    fi

    if [ -d "$BACKUP_DIR" ]; then
        echo "Directory '$BACKUP_DIR' already exists. It will be renamed."
        BACKUP_BAK_DIR="${BACKUP_ROOT}/${BACKUP_SUBDIR}_bak1"
        COUNT=1
        while [ -d "$BACKUP_BAK_DIR" ]; do
            COUNT=$((COUNT + 1))
            BACKUP_BAK_DIR="${BACKUP_ROOT}/${BACKUP_SUBDIR}_bak${COUNT}"
        done
        mv "$BACKUP_DIR" "$BACKUP_BAK_DIR" || { error_message "Error: Could not rename '$BACKUP_DIR' to '$BACKUP_BAK_DIR'."; exit 1; }
        echo "Renamed: '$BACKUP_DIR' -> '$BACKUP_BAK_DIR'"
    else
        echo "Directory '$BACKUP_DIR' does not exist yet."
    fi

    echo "Creating fresh '$BACKUP_DIR'..."
    mkdir -p "$BACKUP_DIR" || { error_message "Error: Could not create '$BACKUP_DIR'."; exit 1; }
    echo "Fresh '$BACKUP_DIR' created."
fi

# ============================================================================
# STEP 7 — Read and validate source:destination pairs
# ============================================================================
declare -a VALID_PAIRS
declare -a SOURCE_DIRS
declare -a DEST_DIRS

for line in "${SYNC_PAIRS[@]}"; do
    [[ -z "$line" || "$line" == \#* ]] && continue

    IFS=":" read -r SOURCE DEST <<< "$line"
    DEST="${DEST#:}"

    if [[ -z "$SOURCE" || -z "$DEST" ]]; then
        echo "Error: Malformed entry in SYNC_PAIRS: '$line'"
        continue
    fi

    SOURCE_REAL=$(realpath "$SOURCE" 2>/dev/null)
    DEST_REAL=$(realpath "$DEST" 2>/dev/null)

    if [ ! -d "$SOURCE_REAL" ]; then
        error_message "Error: Source directory '$SOURCE' (resolved to '$SOURCE_REAL') does not exist or is not accessible."
        continue
    fi
    if [ ! -d "$DEST_REAL" ]; then
        error_message "Error: Destination directory '$DEST' (resolved to '$DEST_REAL') does not exist or is not accessible."
        continue
    fi

    if [ "$SOURCE_REAL" == "$DEST_REAL" ]; then
        error_message "Error: Source and destination are identical ('$SOURCE_REAL') for pair: $line"
        continue
    fi

    VALID_PAIRS+=("$line")
    SOURCE_DIRS+=("$SOURCE_REAL")
    DEST_DIRS+=("$DEST_REAL")
done

if [ ${#VALID_PAIRS[@]} -eq 0 ]; then
    error_message "No valid pairs found in SYNC_PAIRS."
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

echo "Valid pairs found: ${#VALID_PAIRS[@]}"
echo

# ============================================================================
# STEP 8 — Detect terminal size and compute the Defrag layout
# ============================================================================
if [ "$HAS_TPUT" -eq 1 ]; then
    TERM_COLS=$(tput cols)
    TERM_ROWS=$(tput lines)
else
    TERM_COLS=80
    TERM_ROWS=24
fi

USE_DEFRAG_UI=1
# Threshold is 78 (not 80) because lxterminal under LXDE typically reports
# 79 columns. With a strict 80-col threshold, lxterminal would always fall
# back to the ASCII progress bar.
if [ "$TERM_COLS" -lt 78 ] || [ "$TERM_ROWS" -lt 24 ]; then
    USE_DEFRAG_UI=0
fi

# Layout (Defrag mode):
#   row 1                                     : title bar
#   rows 2 .. (TERM_ROWS - 7)                 : block grid
#   rows (TERM_ROWS-6) .. (TERM_ROWS-1)       : Status + Legend frames
#   row TERM_ROWS                             : red status bar
#
# Bottom-frame width: Status takes the left half, Legend the right half.
# Side margins = 1 column.

GRID_TOP=2
GRID_BOTTOM=$(( TERM_ROWS - 7 ))
GRID_H=$(( GRID_BOTTOM - GRID_TOP + 1 ))
[ "$GRID_H" -lt 5 ] && GRID_H=5
GRID_LEFT=2
GRID_RIGHT=$(( TERM_COLS - 1 ))
GRID_W=$(( GRID_RIGHT - GRID_LEFT + 1 ))
GRID_CELLS=$(( GRID_W * GRID_H ))

STATUS_TOP=$(( TERM_ROWS - 5 ))
STATUS_LEFT=2
STATUS_W=$(( TERM_COLS / 2 - 2 ))
LEGEND_LEFT=$(( TERM_COLS / 2 + 1 ))
LEGEND_W=$(( TERM_COLS - LEGEND_LEFT - 1 ))
BAR_ROW=$TERM_ROWS

# ----------------------------------------------------------------------------
# Defrag rendering helpers
# ----------------------------------------------------------------------------

# Move the cursor to (row, col), 1-based
goto() { printf "%s[%d;%dH" "$ESC" "$1" "$2"; }

# Draw the title bar (row 1)
draw_titlebar() {
    local title_left="$1"   # e.g. "Synchronize"
    local title_right="$2"  # e.g. "Ctrl+C=Stop Sync"
    goto 1 1
    # White background, black text: classic "Defrag bar" look
    printf "%s%s" "$C_BG_WHITE" "$C_FG_BLACK"
    local left_pad=" $title_left"
    local right_pad="$title_right "
    local mid=$(( TERM_COLS - ${#left_pad} - ${#right_pad} ))
    [ "$mid" -lt 1 ] && mid=1
    printf "%s%*s%s" "$left_pad" "$mid" "" "$right_pad"
    # Right portion on black background, like the original screenshot
    goto 1 $(( TERM_COLS - ${#right_pad} + 1 ))
    printf "%s%s%s%s" "$C_BG_BLACK" "$C_FG_WHITE" "$right_pad" "$C_RESET"
}

# Draw the red status bar (last row)
draw_bottom_bar() {
    local left="$1"   # e.g. "Writing..."
    local right="$2"  # e.g. "rsync turbo backup"
    goto "$BAR_ROW" 1
    printf "%s%s" "$C_BG_RED" "$C_FG_WHITE"
    local left_pad=" $left"
    local right_pad="$right "
    local mid=$(( TERM_COLS - ${#left_pad} - ${#right_pad} ))
    [ "$mid" -lt 1 ] && mid=1
    printf "%s%*s%s%s" "$left_pad" "$mid" "" "$right_pad" "$C_RESET"
}

# Paint the entire grid area with a blue background and '▓' (unused-block) glyphs
draw_empty_grid() {
    local r c
    printf "%s%s" "$C_BG_BLUE" "$C_FG_LBLUE"
    for (( r=0; r<GRID_H; r++ )); do
        goto $(( GRID_TOP + r )) "$GRID_LEFT"
        for (( c=0; c<GRID_W; c++ )); do
            printf "▓"
        done
    done
    printf "%s" "$C_RESET"
}

# Paint ONE cell of the grid (0-based index, 0..GRID_CELLS-1)
# with the given character + color
# $1 = index, $2 = char, $3 = full ANSI prefix (e.g. "$C_BG_BLUE$C_FG_WHITE")
paint_cell() {
    local idx=$1 ; local ch="$2" ; local color="$3"
    local row=$(( idx / GRID_W ))
    local col=$(( idx % GRID_W ))
    [ "$row" -ge "$GRID_H" ] && return
    goto $(( GRID_TOP + row )) $(( GRID_LEFT + col ))
    printf "%s%s%s" "$color" "$ch" "$C_RESET"
}

# Paint a "filled" cell: each cell shows a character that itself contains a
# checkerboard pattern (▓ = Unicode dense shade U+2593), white on blue
# background. All cells are painted (no pattern spread across cells).
# $1 = index, $2 = kind ("write" | "delete")
paint_filled_cell() {
    local idx=$1 ; local kind="$2"
    local row=$(( idx / GRID_W ))
    local col=$(( idx % GRID_W ))
    [ "$row" -ge "$GRID_H" ] && return
    goto $(( GRID_TOP + row )) $(( GRID_LEFT + col ))
    if [ "$kind" = "delete" ]; then
        # Pale-grey shade for deletions
        printf "%s%s▓%s" "$C_BG_BLUE" "${ESC}[38;5;245m" "$C_RESET"
    else
        # White shade for transfers
        printf "%s%s▓%s" "$C_BG_BLUE" "$C_FG_WHITE" "$C_RESET"
    fi
}

# Draw the Legend frame (bottom-right). Static, drawn only once.
# Arg: files_per_block (label "1 cell = N file(s)")
#
# The legend describes ONLY the visual states of the grid, NOT the rsync
# operations (Reading/Writing/...) which are shown live in the red bar.
draw_legend() {
    local fpb="$1"
    local r="$STATUS_TOP" l="$LEGEND_LEFT" w="$LEGEND_W"
    local title_w=8                     # length of " Legend "
    local dashes=$(( w - 2 - title_w )) # total number of dashes around the title
    [ "$dashes" -lt 2 ] && dashes=2
    local left_dashes=$(( dashes / 2 ))
    local right_dashes=$(( dashes - left_dashes ))
    local inner_w=$(( w - 2 ))          # inner width (between the two │)

    # Top border: ┌────── Legend ──────┐
    goto "$r" "$l"
    printf "%s%s┌%s Legend %s┐%s" "$C_BG_BLUE" "$C_FG_YELLOW" \
        "$(printf '─%.0s' $(seq 1 "$left_dashes"))" \
        "$(printf '─%.0s' $(seq 1 "$right_dashes"))" "$C_RESET"

    # Helper: paint a full inner row "│ ... │" with blue background over the
    # entire width; the actual content is then overwritten on top.
    local i
    for i in 1 2 3 4; do
        goto $(( r+i )) "$l"
        printf "%s%s│%*s│%s" "$C_BG_BLUE" "$C_FG_YELLOW" \
            "$inner_w" "" "$C_RESET"
    done

    # Row 1: ▓ Done   ▓ Todo
    #   ▓ white on blue = cell processed (transfer done)
    #   ▓ pale blue on blue = cell not processed yet
    goto $(( r+1 )) $(( l+2 ))
    printf "%s%s▓%s Done   %s%s▓%s Todo%s" \
        "$C_BG_BLUE" "$C_FG_WHITE" \
        "$C_BG_BLUE$C_FG_WHITE" \
        "$C_BG_BLUE" "$C_FG_LBLUE" \
        "$C_BG_BLUE$C_FG_WHITE" \
        "$C_RESET"

    # Row 2: ▓ Deleted (default) or ▓ Archived (backup mode)
    #   ▓ pale grey = deleted on the destination side
    #   In backup mode, "deleted" actually means "moved into backupsync/" —
    #   the user already sees this through "Backing up..." in the red bar,
    #   so we just adapt the label to be honest.
    goto $(( r+2 )) $(( l+2 ))
    local del_label="Deleted"
    if [ "${BACKUP_MODE:-0}" -eq 1 ]; then
        del_label="Archived"
    fi
    printf "%s%s▓%s %s%s" \
        "$C_BG_BLUE" "${ESC}[38;5;245m" \
        "$C_BG_BLUE$C_FG_WHITE" \
        "$del_label" \
        "$C_RESET"

    # Row 3: ■ Current  (solid blinking yellow square = cell being processed)
    goto $(( r+3 )) $(( l+2 ))
    printf "%s %s%s Current%s" \
        "$C_BG_YELLOW_BLINK" \
        "$C_BG_BLUE$C_FG_WHITE" "" \
        "$C_RESET"

    # Row 4: 1 cell = N file(s)
    goto $(( r+4 )) $(( l+2 ))
    printf "%s%s1 cell = %s file(s)%s" \
        "$C_BG_BLUE" "$C_FG_WHITE" "$fpb" "$C_RESET"

    # Bottom border: └──────────────────────┘
    goto $(( r+5 )) "$l"
    printf "%s%s└%s┘%s" "$C_BG_BLUE" "$C_FG_YELLOW" \
        "$(printf '─%.0s' $(seq 1 $(( w-2 )) ))" "$C_RESET"
}

# Draw ONLY the Status frame borders (static, drawn once).
# The contents are then updated by draw_status_content() to avoid the
# flicker that would result from redrawing the entire frame.
draw_status_frame() {
    local r="$STATUS_TOP" l="$STATUS_LEFT" w="$STATUS_W"
    local title_w=8                     # length of " Status "
    local dashes=$(( w - 2 - title_w ))
    [ "$dashes" -lt 2 ] && dashes=2
    local left_dashes=$(( dashes / 2 ))
    local right_dashes=$(( dashes - left_dashes ))

    goto "$r" "$l"
    printf "%s%s┌%s Status %s┐%s" "$C_BG_BLUE" "$C_FG_YELLOW" \
        "$(printf '─%.0s' $(seq 1 "$left_dashes"))" \
        "$(printf '─%.0s' $(seq 1 "$right_dashes"))" "$C_RESET"
    local i
    for i in 1 2 3 4; do
        goto $(( r+i )) "$l"
        printf "%s%s│%*s│%s" "$C_BG_BLUE" "$C_FG_YELLOW" $(( w-2 )) "" "$C_RESET"
    done
    goto $(( r+5 )) "$l"
    printf "%s%s└%s┘%s" "$C_BG_BLUE" "$C_FG_YELLOW" \
        "$(printf '─%.0s' $(seq 1 $(( w-2 )) ))" "$C_RESET"
}

# Update ONLY the Status frame content (not the borders).
# "sync" mode    : shows File N/T, %, mini bar, elapsed, label
# "analyze" mode : shows Found: N, spinner, elapsed, label "Analyzing..."
# Args: mode_kind cur tot pct elapsed_str mode_label
#   mode_kind = "sync" | "analyze"
draw_status_content() {
    local kind="$1" cur="$2" tot="$3" pct="$4" elapsed="$5" mode="$6"
    local r="$STATUS_TOP" l="$STATUS_LEFT" w="$STATUS_W"
    local inner_w=$(( w - 4 ))

    # Row 1: depends on mode
    goto $(( r+1 )) $(( l+2 ))
    printf "%s%s%-*s" "$C_BG_BLUE" "$C_FG_WHITE" "$inner_w" ""   # blank
    goto $(( r+1 )) $(( l+2 ))
    if [ "$kind" = "analyze" ]; then
        printf "%s%sFound: %d" "$C_BG_BLUE" "$C_FG_WHITE" "$cur"
    else
        if [ "$tot" -gt 0 ]; then
            printf "%s%sFile %d/%d" "$C_BG_BLUE" "$C_FG_WHITE" "$cur" "$tot"
        else
            printf "%s%sFile %d" "$C_BG_BLUE" "$C_FG_WHITE" "$cur"
        fi
        goto $(( r+1 )) $(( l+w-7 ))
        printf "%s%s%3d%%%s" "$C_BG_BLUE" "$C_FG_WHITE" "$pct" "$C_RESET"
    fi

    # Row 2: mini bar (sync) or wide spinner (analyze)
    goto $(( r+2 )) $(( l+2 ))
    printf "%s%s%-*s" "$C_BG_BLUE" "$C_FG_WHITE" "$inner_w" ""
    goto $(( r+2 )) $(( l+2 ))
    local barw="$inner_w"
    if [ "$kind" = "analyze" ]; then
        # "Pulse": one character sweeping across the bar area
        local pulse_pos=$(( cur % barw ))
        local before=$pulse_pos
        local after=$(( barw - pulse_pos - 1 ))
        printf "%s" "$C_BG_BLUE"
        [ "$before" -gt 0 ] && printf "%s%s" "$C_FG_LBLUE" "$(printf '░%.0s' $(seq 1 $before))"
        printf "%s▓%s" "$C_FG_YELLOW" "$C_BG_BLUE"
        [ "$after" -gt 0 ] && printf "%s%s" "$C_FG_LBLUE" "$(printf '░%.0s' $(seq 1 $after))"
        printf "%s" "$C_RESET"
    else
        local filled=$(( pct * barw / 100 ))
        [ "$filled" -gt "$barw" ] && filled=$barw
        local empty=$(( barw - filled ))
        printf "%s" "$C_BG_BLUE"
        [ "$filled" -gt 0 ] && printf "%s%s" "$C_FG_YELLOW" "$(printf '▓%.0s' $(seq 1 $filled))"
        [ "$empty"  -gt 0 ] && printf "%s%s" "$C_FG_LBLUE" "$(printf '░%.0s' $(seq 1 $empty))"
        printf "%s" "$C_RESET"
    fi

    # Row 3: Elapsed Time
    goto $(( r+3 )) $(( l+2 ))
    printf "%s%s%-*s" "$C_BG_BLUE" "$C_FG_WHITE" "$inner_w" ""
    goto $(( r+3 )) $(( l+2 ))
    printf "%s%sElapsed Time: %s%s" "$C_BG_BLUE" "$C_FG_WHITE" "$elapsed" "$C_RESET"

    # Row 4: mode label
    goto $(( r+4 )) $(( l+2 ))
    printf "%s%s%-*s" "$C_BG_BLUE" "$C_FG_WHITE" "$inner_w" ""
    goto $(( r+4 )) $(( l+2 ))
    printf "%s%s%s%s" "$C_BG_BLUE" "$C_FG_WHITE" "$mode" "$C_RESET"
}

# Format a number of seconds as HH:MM:SS
format_elapsed() {
    local s=$1
    printf "%02d:%02d:%02d" $(( s / 3600 )) $(( (s % 3600) / 60 )) $(( s % 60 ))
}

# ============================================================================
# STEP 9 — Analysis phase (dry-run)
# ============================================================================
rm -f "$ANALYSIS_FLAG"

# Build the rsync exclude flags once
RSYNC_EXCLUDE_FLAGS=()
for excl in "${RSYNC_EXCLUDES[@]}"; do
    RSYNC_EXCLUDE_FLAGS+=("--exclude=$excl")
done

(
    for idx in "${!SOURCE_DIRS[@]}"; do
        SOURCE_REAL="${SOURCE_DIRS[$idx]}"
        DEST_REAL="${DEST_DIRS[$idx]}"
        rsync -a --delete -n -i "${RSYNC_EXCLUDE_FLAGS[@]}" "$SOURCE_REAL/" "$DEST_REAL/" >> "$DRYRUN_FILE" 2>&1
    done
    touch "$ANALYSIS_FLAG"
) &
ANALYSIS_PID=$!

# Simple text spinner during the analysis (the dry-run is fast — typically
# under a few seconds — so a full Defrag screen for it would be overkill;
# the Defrag UI is reserved for the actual sync phase).
i=1
sp="/-\\|"
printf "%sAnalyzing differences...  " "$HIDE_CUR"
while [ ! -f "$ANALYSIS_FLAG" ]; do
    printf "\b${sp:i++%${#sp}:1}"
    sleep 0.1
done
printf "%s\b \n" "$SHOW_CUR"
wait $ANALYSIS_PID

total_operations=$(grep -E '^[[:space:]]*deleting|^[><fcLh*]' "$DRYRUN_FILE" 2>/dev/null | wc -l | awk '{print $1+0}')

# ============================================================================
# STEP 10 — Disk-space check for backup mode
# ============================================================================
if [ "$BACKUP_MODE" -eq 1 ] && [ "$total_operations" -gt 0 ]; then
    # Switch back to normal terminal mode to display messages cleanly
    if [ "$USE_DEFRAG_UI" -eq 1 ]; then
        printf "%s%s" "$C_RESET" "$CLEAR_SCR"
    fi

    total_needed_kb=0

    while IFS= read -r dryrun_line; do
        filename="${dryrun_line:12}"
        [ -z "$filename" ] && continue
        [[ "$filename" == */ ]] && continue
        for idx in "${!DEST_DIRS[@]}"; do
            filepath="${DEST_DIRS[$idx]}/$filename"
            if [ -f "$filepath" ]; then
                filesize_kb=$(du -k "$filepath" 2>/dev/null | cut -f1)
                total_needed_kb=$((total_needed_kb + ${filesize_kb:-0}))
                break
            fi
        done
    done < <(grep -E '^[[:space:]]*deleting|^[><fcLh*]' "$DRYRUN_FILE" 2>/dev/null)

    # Add 10% safety margin
    total_needed_kb=$((total_needed_kb + total_needed_kb / 10))

    available_kb=$(df -k "$BACKUP_ROOT" 2>/dev/null | awk 'NR==2 {print $4}')
    available_kb=${available_kb:-0}

    if [ "$total_needed_kb" -gt 0 ] && [ "$available_kb" -gt 0 ]; then
        total_needed_mb=$((total_needed_kb / 1024))
        available_mb=$((available_kb / 1024))

        if [ "$total_needed_kb" -gt "$available_kb" ]; then
            rm -f "$DRYRUN_FILE" "$ANALYSIS_FLAG"
            echo
            error_message "Error: Insufficient disk space for the backup!"
            error_message "  Estimated space needed (+10% margin): ${total_needed_mb} MB"
            error_message "  Available space on '$BACKUP_ROOT': ${available_mb} MB"
            echo
            echo -n "Press [ENTER] to quit ... "
            read var_name
            exit 1
        else
            echo "Disk space OK: ${total_needed_mb} MB needed / ${available_mb} MB available on '$BACKUP_ROOT'"
            echo
            echo -n "Press [ENTER] to continue ... "
            read var_name
        fi
    fi
fi

rm -f "$DRYRUN_FILE" "$ANALYSIS_FLAG"

# ============================================================================
# STEP 11 — "Nothing to do" case
# ============================================================================
if [ "$total_operations" -eq 0 ]; then
    printf "%s%s" "$C_RESET" "$CLEAR_SCR"
    echo "No synchronization needed - all directories are already in sync."
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 0
fi

# ============================================================================
# STEP 12 — Confirm switch to production mode
# ============================================================================
printf "%s%s" "$C_RESET" "$CLEAR_SCR"
echo "Analysis complete: $total_operations operation(s) on ${#VALID_PAIRS[@]} pair(s)"
for pair in "${VALID_PAIRS[@]}"; do
    echo "  - $pair"
done
echo
echo -n "Switch to production mode (no more dry-run)? (y/N) "
read -r confirm
if ! [[ "$confirm" =~ ^[yYoO]$ ]]; then
    echo "Staying in dry-run mode: no changes will be applied."
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 0
fi

# ============================================================================
# STEP 13 — Synchronization phase (real rsync) with the Defrag UI
# ============================================================================
# Files-per-block ratio (the active block sweeps the whole grid)
files_per_block=$(( total_operations / GRID_CELLS ))
[ "$files_per_block" -lt 1 ] && files_per_block=1

if [ "$USE_DEFRAG_UI" -eq 1 ]; then
    printf "%s%s%s" "$HIDE_CUR" "$C_BG_BLUE" "$CLEAR_SCR"
    draw_titlebar "Synchronize" "Ctrl+C=Stop Sync"
    draw_empty_grid
    draw_legend "$files_per_block"
    draw_status_frame
    if [ "$BACKUP_MODE" -eq 1 ]; then
        mode_label="Backup Synchronization"
    else
        mode_label="Full Synchronization"
    fi
    draw_status_content "sync" 0 "$total_operations" 0 "00:00:00" "$mode_label"
    # Initial message: "Thinking..." rather than "Writing..." because rsync
    # sometimes spends several seconds scanning files before the first real
    # operation. Without this the user would see "Writing..." frozen and
    # think the script crashed. As soon as the first rsync line arrives,
    # the main loop overwrites this with the real label
    # (Creating/Deleting/...).
    draw_bottom_bar "Thinking..." "rsync turbo backup"
else
    printf "%s" "$CLEAR_SCR"
    echo "Synchronizing..."
fi

# Sync-phase state
current=0
last_drawn_cell=-1
prev_op_kind="write"
SYNC_START=$SECONDS
last_status_update=0
status_update_step=$(( total_operations / 200 ))   # ~200 redraws max
[ "$status_update_step" -lt 1 ] && status_update_step=1

# Regex matching the rsync operations we count
rsync_pattern='^[[:space:]]*deleting|^[><fcLh*]'

# Loop over each pair (typically only one, but the code stays generic)
for idx in "${!SOURCE_DIRS[@]}"; do
    SOURCE_REAL="${SOURCE_DIRS[$idx]}"
    DEST_REAL="${DEST_DIRS[$idx]}"

    RSYNC_OPTS=(-a --delete -i "${RSYNC_EXCLUDE_FLAGS[@]}")
    if [ "$BWLIMIT" -gt 0 ]; then
        RSYNC_OPTS+=("--bwlimit=$BWLIMIT")
    fi
    if [ "$BACKUP_MODE" -eq 1 ]; then
        DEST_BACKUP_DIR="$BACKUP_DIR/$(basename "$DEST_REAL")"
        mkdir -p "$DEST_BACKUP_DIR"
        RSYNC_OPTS+=(--backup "--backup-dir=$DEST_BACKUP_DIR")
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ $rsync_pattern ]]; then
            ((current++))

            # Detect the operation type.
            if [[ "$line" =~ ^[[:space:]]*deleting ]]; then
                op_left="Deleting..."
                op_kind="delete"
                active_char=" "
            elif [[ "$line" =~ ^c ]]; then
                op_left="Creating..."
                op_kind="write"
                active_char=" "
            else
                # Transfers >, <, *, f, etc.
                if [ "$BACKUP_MODE" -eq 1 ]; then
                    op_left="Backing up..."
                else
                    op_left="Writing..."
                fi
                op_kind="write"
                active_char=" "
            fi

            # Progress math
            percent=$(( current * 100 / total_operations ))
            [ "$percent" -gt 100 ] && percent=100

            # Target cell: the grid MUST end up 100% filled when the sync
            # ends, regardless of the operation count. So target_cell is
            # proportional: current=total -> last cell.
            target_cell=$(( current * GRID_CELLS / total_operations ))
            [ "$target_cell" -ge "$GRID_CELLS" ] && target_cell=$(( GRID_CELLS - 1 ))

            if [ "$USE_DEFRAG_UI" -eq 1 ]; then
                # Cell-by-cell animation: when we jump several cells at once
                # (rsync running fast), we slide the yellow cursor cell by
                # cell, painting the dense-shade pattern right behind it.
                # The visual effect is a smooth sweep instead of whole rows
                # filling at once.
                if [ "$target_cell" -ne "$last_drawn_cell" ]; then
                    fill_from=$(( last_drawn_cell + 1 ))
                    if [ "$fill_from" -lt 0 ]; then fill_from=0; fi

                    # Freeze the previous active cell into the dense shade
                    if [ "$last_drawn_cell" -ge 0 ]; then
                        paint_filled_cell "$last_drawn_cell" "$prev_op_kind"
                    fi

                    # Animation: slide the yellow cursor from fill_from to
                    # target_cell, painting the dense shade right behind it.
                    # The sleep is calibrated to stay smooth even on big
                    # jumps: traversing N cells globally sleeps about 80ms
                    # max (so we don't slow rsync, which can output 200
                    # lines/s).
                    nb_cells_to_animate=$(( target_cell - fill_from + 1 ))
                    if [ "$nb_cells_to_animate" -le 1 ]; then
                        # 1-cell jump: no animation needed
                        paint_cell "$target_cell" " " "$C_BG_YELLOW_BLINK"
                    else
                        # Multi-cell jump: animate
                        cc=$fill_from
                        while [ "$cc" -le "$target_cell" ]; do
                            # Paint the yellow cursor on cc
                            # - Intermediate cells: solid yellow (5ms each,
                            #   no time to blink)
                            # - Final cell: BLINKING yellow — the cell where
                            #   the cursor actually stops
                            if [ "$cc" -eq "$target_cell" ]; then
                                paint_cell "$cc" " " "$C_BG_YELLOW_BLINK"
                            else
                                paint_cell "$cc" " " "$C_BG_YELLOW"
                            fi
                            # Tiny delay to make the motion visible (~5ms
                            # per cell). usleep is more precise but not
                            # always available, so we use bash builtin
                            # `read -t` which is precise to the millisecond.
                            read -rt 0.005 _ < /dev/zero 2>/dev/null || true
                            # Erase the cursor on cc by painting the final
                            # dense shade (except for the target cell which
                            # must stay yellow).
                            if [ "$cc" -lt "$target_cell" ]; then
                                paint_filled_cell "$cc" "$op_kind"
                            fi
                            cc=$(( cc + 1 ))
                        done
                    fi
                    last_drawn_cell=$target_cell
                    prev_op_kind="$op_kind"
                else
                    prev_op_kind="$op_kind"
                fi

                # Throttled update of Status frame and red bar
                if (( current - last_status_update >= status_update_step )); then
                    last_status_update=$current
                    elapsed=$(( SECONDS - SYNC_START ))
                    draw_status_content "sync" "$current" "$total_operations" "$percent" \
                        "$(format_elapsed $elapsed)" "$mode_label"
                    draw_bottom_bar "$op_left" "rsync turbo backup"
                fi
            else
                # Fallback mode: classic ASCII progress bar
                bar_size=40
                completed=$(( current * bar_size / total_operations ))
                [ "$completed" -gt "$bar_size" ] && completed=$bar_size
                remaining=$(( bar_size - completed ))
                bar_str=$(printf "%${completed}s" | tr ' ' '#')
                dot_str=$(printf "%${remaining}s" | tr ' ' '-')
                printf "\r\e[K[%-${bar_size}s] %d%% (%d/%d)" \
                    "$bar_str$dot_str" "$percent" "$current" "$total_operations"
            fi
        fi
    done < <(stdbuf -oL rsync "${RSYNC_OPTS[@]}" "$SOURCE_REAL/" "$DEST_REAL/")
done

# Final redraw to freeze the last cell and show 100%
if [ "$USE_DEFRAG_UI" -eq 1 ]; then
    if [ "$last_drawn_cell" -ge 0 ]; then
        paint_filled_cell "$last_drawn_cell" "$prev_op_kind"
    fi
    elapsed=$(( SECONDS - SYNC_START ))
    draw_status_content "sync" "$current" "$total_operations" 100 \
        "$(format_elapsed $elapsed)" "$mode_label"
    draw_bottom_bar "Done." "rsync turbo backup"
fi

# ============================================================================
# STEP 14 — Restore the screen
# ============================================================================
printf "%s%s" "$SHOW_CUR" "$C_RESET"
if [ "$USE_DEFRAG_UI" -eq 1 ]; then
    # Brief pause so the user can see "Done." on screen
    sleep 1
    printf "%s" "$CLEAR_SCR"
else
    printf "\n\n"
fi

# ============================================================================
# STEP 15 — Final report
# ============================================================================
backup_count=0
backup_dirs_count=0

if [ "$BACKUP_MODE" -eq 1 ] && [ -d "$BACKUP_DIR" ]; then
    read backup_count backup_dirs_count < <(
        find "$BACKUP_DIR" \( -type f -o -type d \) -printf '%y\n' 2>/dev/null |
        awk 'BEGIN {f=0; d=0} $1=="f" {f++} $1=="d" {d++} END {print f+0, (d>0?d-1:0)}'
    )
    backup_count=${backup_count:-0}
    backup_dirs_count=${backup_dirs_count:-0}
fi

echo "Synchronization results:"
echo "------------------------"
echo "- Pairs processed: ${#VALID_PAIRS[@]}"
echo "- Total operations performed: $total_operations"

if [ "$BACKUP_MODE" -eq 1 ]; then
    if [ "$backup_count" -gt 0 ]; then
        echo "- Files archived (deleted/overwritten): $backup_count"
    fi
    if [ "$backup_dirs_count" -gt 0 ]; then
        echo "- Directories archived: $backup_dirs_count"
    fi
    if [ "$backup_count" -eq 0 ] && [ "$backup_dirs_count" -eq 0 ]; then
        echo "- No files were deleted or overwritten"
    fi
else
    echo "- Backup mode off: deleted/overwritten files were not archived"
fi

if [ "$BACKUP_MODE" -eq 1 ] && [ -d "$BACKUP_DIR" ]; then
    echo "- Cleaning empty directories under '$BACKUP_DIR'..."
    find "$BACKUP_DIR" -type d -empty -delete 2>/dev/null
fi

# ============================================================================
# STEP 16 — Restore kernel parameters
# ============================================================================
if [ "$SYSCTL_MODIFIED" -eq 1 ]; then
    echo "Restoring default kernel parameters..."
    sudo sysctl -w vm.dirty_bytes=0 > /dev/null 2>&1
    sudo sysctl -w vm.dirty_background_bytes=0 > /dev/null 2>&1
    SYSCTL_MODIFIED=0
    echo "Kernel parameters restored."
fi

# ============================================================================
# STEP 17 — Exit
# ============================================================================
echo
echo "Operation complete."
echo -n "Press [ENTER] to quit ... "
read var_name
