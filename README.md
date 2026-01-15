# Rsyncmenu 1.2

## Overview
Directory synchronization tool with rsync featuring dynamic progress bar and spinner animation.

## Features
- Real-time progress bar with percentage
- Animated spinner during operations
- Dry-run analysis phase before actual sync
- UTF-8 encoding support for accented characters
- Automatic validation of source and destination directories
- Visual progress tracking with operation count

## Requirements
- `rsync` - File synchronization tool
- `realpath` - Path resolution utility (from coreutils)
- `stdbuf` - Buffer manipulation utility (from coreutils)

Installation:
```bash
sudo apt install rsync coreutils
```

## Usage Example

```
Directory synchronization with rsync 1.2 (Dynamic progress with stdbuf)

Enter the absolute path of the source directory:
/home/user/Documents
Enter the absolute path of the destination directory:
/backup/Documents
Analyzing differences...  
Analysis complete: 15 operations detected.
Switch to production mode? (y/N) y

Synchronization in progress...
[####################--------------------] 50% | (7/15)
[########################################] 100% / (15/15)

Synchronization results:
-----------------------------
- Total operations performed: 15

Operation complete.
Press [ENTER] to quit ...
```

## How It Works

### Phase 1: Analysis (Dry-run)
- Performs a dry-run with `rsync -n` to detect all changes
- Displays animated spinner during analysis
- Counts total operations needed (files to copy, update, or delete)
- No modifications are made during this phase

### Phase 2: Confirmation
- Shows total number of operations detected
- Asks user confirmation to proceed with actual synchronization
- User can abort or continue to production mode

### Phase 3: Synchronization
- Real-time progress bar showing:
  - Visual bar with `#` for completed and `-` for remaining
  - Percentage completion
  - Animated spinner (`/ - \ |`)
  - Current and total operations count
- Uses `stdbuf -oL` for line-buffered output ensuring real-time updates
- Progress updates on each file operation

## Features Breakdown

### Progress Bar Display
```
[####################--------------------] 50% | (7/15)
 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  ^^  ^  ^^^^
         40-char bar                       %   spin count
```

### Operations Counted
- File transfers (new files)
- File updates (modified files)
- File deletions (removed from source)
- Directory operations

### Exclusions
- `.Trash-1000` directory automatically excluded

## Rsync Options Used
- `-a` : Archive mode (preserves permissions, timestamps, etc.)
- `--delete` : Delete files in destination not present in source
- `-i` : Item-ize changes (provides detailed operation list)
- `--exclude=.Trash-1000` : Exclude trash directory
- `-n` : Dry-run mode (analysis phase only)

## Error Handling
- Validates source directory exists
- Validates destination directory exists
- Prevents synchronization if source and destination are identical
- Checks for required utilities (rsync, realpath)
- UTF-8 encoding for special characters

## Technical Details

### Real-time Progress
The script uses `stdbuf -oL` to force line-buffering on rsync output, ensuring each operation is immediately visible in the progress bar rather than being buffered.

### Operation Counting
Uses regex pattern to count operations:
```bash
grep -E '^[[:space:]]*deleting|^[><fcLh*]'
```

This matches:
- `deleting` : File deletions
- `>` : File transfers to destination
- `<` : File transfers from destination (rare)
- `f` : Regular file
- `c` : Character device
- `L` : Symlink
- `h` : Hard link
- `*` : Message follows

### Terminal Control
- `\e[?25l` : Hide cursor during progress
- `\e[?25h` : Show cursor after completion
- `\r` : Return to line beginning
- `\e[K` : Clear line from cursor to end

## Exit Conditions
- No operations needed: Script exits after analysis
- User declines production mode: Script exits after confirmation
- Successful completion: Shows results and waits for user

## Output Example (Detailed)

```
Directory synchronization with rsync 1.2 (Dynamic progress with stdbuf)

Enter the absolute path of the source directory:
/home/user/Documents
Enter the absolute path of the destination directory:
/backup/Documents
Analyzing differences... \ 
Analysis complete: 23 operations detected.
Switch to production mode? (y/N) y

Synchronization in progress...
[###############-------------------------] 38% - (9/23)

Synchronization results:
-----------------------------
- Total operations performed: 23

Operation complete.
Press [ENTER] to quit ...
```

## Notes
- The script uses trailing slashes in rsync commands (`/`) to sync directory contents
- Temporary files are created in `/tmp/` with PID-based naming
- Progress bar size is fixed at 40 characters
- Spinner characters: `/ - \ |`

## Version History
- **1.2**: Added dynamic progress bar with stdbuf, removed backup system
- **1.0**: Initial version with backup system

## Safety Features
- Dry-run analysis before any modifications
- User confirmation required before synchronization
- Clear error messages in red color
- Validation of all paths before operations
- Identical source/destination prevention
