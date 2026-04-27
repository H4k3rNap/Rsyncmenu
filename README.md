# turbo_rsync_backup

A Bash script that wraps `rsync` with a Microsoft Defrag–style progress UI:
a colored block grid that fills up as the sync progresses, "Status" and
"Legend" panels at the bottom, and a red status bar showing the current
operation (`Creating...`, `Writing...`, `Deleting...`, `Backing up...`).

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Synchronize                                            Ctrl+C=Stop Sync  │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ┌──── Status ──────────────┐  ┌──── Legend ──────────────┐               │
│ │ File 642/1500       42%  │  │ ▓ Done   ▓ Todo          │               │
│ │ ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░  │  │ ▓ Archived               │               │
│ │ Elapsed Time: 00:02:14   │  │   Current                │               │
│ │ Backup Synchronization   │  │ 1 cell = 3 file(s)       │               │
│ └──────────────────────────┘  └──────────────────────────┘               │
│ Backing up...                                          rsync turbo backup│
└──────────────────────────────────────────────────────────────────────────┘
```

## Features

- **Defrag-style live UI** built entirely in Bash with ANSI 256-color codes
  (no `ncurses`, no external rendering library).
- **Two-phase workflow**: dry-run analysis first (counts every operation
  rsync would perform), then real synchronization after explicit
  confirmation.
- **Backup mode** (optional): files about to be deleted or overwritten on
  the destination are moved into a versioned `backupsync/` folder instead
  of being lost. Previous runs are auto-rotated to `backupsync_bak1/`,
  `backupsync_bak2/`, etc.
- **Disk-space safety check** before any backup-mode write: estimates how
  much room the backup will need (with a 10% margin) and aborts with a
  clear error if there isn't enough space.
- **Bandwidth limiting** for external USB SSDs / spinning disks, with
  optional kernel write-back tuning (`vm.dirty_bytes`,
  `vm.dirty_background_bytes`) to avoid the "looks fast then stalls
  forever" pattern.
- **Smart fallback** for narrow terminals (< 78 columns or < 24 rows):
  falls back to a classic ASCII progress bar instead of garbling the
  Defrag layout.
- **Self-cleaning**: an `EXIT` trap restores the cursor, ANSI state, temp
  files, and any modified kernel parameters — even on `Ctrl+C` or crash.
- **Single-file**: pure Bash, no Python, no Node, no installer needed.

## Requirements

| Requirement     | Notes                                                |
| --------------- | ---------------------------------------------------- |
| `bash` ≥ 4      | Uses arrays, `[[ ]]`, regex matching                 |
| `rsync`         | The actual sync engine                               |
| `coreutils`     | Provides `realpath`, `df`, `du`, `find`, `awk`       |
| `ncurses-bin`   | Provides `tput` (optional but strongly recommended)  |
| `sudo`          | Optional, only used when bandwidth limiting is on    |
| A 256-color terminal | Tested on `lxterminal`, `gnome-terminal`, `konsole`, `xterm` |

On Debian / Ubuntu / Mint:

```bash
sudo apt install rsync coreutils ncurses-bin
```

## Installation

```bash
git clone https://github.com/H4k3rNap/turbo_rsync_backup.git
cd turbo_rsync_backup
chmod +x turbo_rsync_backup.sh
```

That's it — there is no installer, no system-wide path. Run it directly
from wherever you cloned it, or symlink it into `~/bin/` if you prefer.

## Configuration

Open `turbo_rsync_backup.sh` and edit the **`USER CONFIGURATION`** block
near the top of the file:

```bash
# Sync pairs: SOURCE:DESTINATION (one per array element).
SYNC_PAIRS=(
    "/home/alice/Documents:/media/alice/BACKUP/Documents"
    "/home/alice/Pictures:/mnt/nas/Pictures"
)

# Root directory where the backup folder will be created.
BACKUP_ROOT="${HOME}/turbo_rsync_backups"

# Subdirectory inside BACKUP_ROOT for archived (overwritten/deleted) files.
BACKUP_SUBDIR="backupsync"

# Bandwidth menu presets (MB/s).
BWLIMIT_PRESET_HIGH=150
BWLIMIT_PRESET_LOW=100

# Kernel tuning when bwlimit is active (bytes).
DIRTY_BYTES_VALUE=50000000
DIRTY_BACKGROUND_BYTES_VALUE=25000000

# Patterns excluded from rsync.
RSYNC_EXCLUDES=(".Trash-1000")
```

### Sync pairs format

Each entry of `SYNC_PAIRS` is a single string with the form
`SOURCE:DESTINATION`. Both directories **must already exist** — the
script does not create them, on purpose, to prevent accidentally seeding
the wrong drive. To temporarily disable a pair, just comment its line:

```bash
SYNC_PAIRS=(
    "/home/alice/Documents:/media/alice/BACKUP/Documents"
    # "/home/alice/Pictures:/mnt/nas/Pictures"   # disabled for now
)
```

### Defaults vs. strict mode

The defaults use values under `$HOME` so the script runs out of the box.
If you'd rather force every user to edit the config explicitly, the
script header includes commented-out "strict mode" examples like:

```bash
# Strict-mode example: BACKUP_ROOT="/media/USERNAME/DATAS"
```

The script also detects the placeholder pair
`/path/to/source:/path/to/destination` and refuses to run until it has
been replaced.

## Usage

```bash
./turbo_rsync_backup.sh
```

The script will, in order:

1. Check dependencies (`rsync`, `realpath`, optionally `tput`).
2. Validate `SYNC_PAIRS`.
3. Ask whether to enable backup mode (Y/n).
4. Ask whether to limit bandwidth (1=no limit / 2=high preset / 3=low
   preset / 4=custom).
5. If bandwidth limiting is on and `sudo` is available, apply the kernel
   tuning. If `sudo` isn't available, fall back gracefully to bwlimit
   alone.
6. Rotate any previous `backupsync/` to `backupsync_bakN/` (backup mode
   only).
7. Resolve every pair with `realpath` and check the directories exist
   and are different from each other.
8. Detect terminal size and decide between Defrag UI and ASCII fallback.
9. Run the **dry-run analysis** with a spinner, count operations.
10. In backup mode, estimate disk space and abort if insufficient.
11. If nothing to do, exit cleanly.
12. Otherwise show a summary and ask for confirmation
    (`Switch to production mode (no more dry-run)? (y/N)`).
13. Run the **real synchronization** with the Defrag UI.
14. Print a final report (pairs processed, total operations, files /
    directories archived).
15. Restore kernel parameters and clean up.

You can interrupt at any point with `Ctrl+C`; the cleanup trap restores
the terminal, removes temp files, and reverts kernel parameters.

## How it works (technical notes)

### Two-phase rsync (dry-run + real)

The dry-run uses `rsync -a --delete -n -i` and accumulates output into a
temp file. The script then counts lines matching
`^[[:space:]]*deleting|^[><fcLh*]` to get the total operation count.
This lets the UI display an accurate `File N/Total` and percentage from
the very first operation of the real run.

### Backup mode

The script generates `--backup --backup-dir=<BACKUP_ROOT>/backupsync/<dest_basename>`
options for rsync. Any file that rsync would otherwise overwrite or
delete on the destination side is silently moved into that directory
instead. After the run, empty directories under `backupsync/` are
pruned.

### Defrag-style UI design

The most-iterated detail of the script. Below are the choices that won
out, with rationale.

#### Terminal-size detection

`lxterminal` under LXDE typically reports `tput cols = 79` (not 80) and
`tput lines = 24`. The Defrag/fallback threshold is therefore set at
**78 columns × 24 rows** — using 80 columns would make `lxterminal`
always fall back to ASCII.

#### Why the analysis phase uses a plain text spinner

Initial idea: render the full Defrag screen during the dry-run with
flickering yellow `r`s. Bad idea, because:

- The dry-run is fast (often < 5 seconds).
- It can't be cleanly cancelled at this stage.
- The user just wants to get to the confirmation prompt.

Final design: a simple `Analyzing differences... /-\|` spinner. The
full-screen Defrag UI is reserved for the actual sync, where the user
has already committed to the operation and wants visual feedback on
progress.

#### Always 100% filled at 100% progress

Naive `1 op = 1 cell` breaks for short syncs: 78 ops in a 1248-cell grid
gives a grid that's only 6% painted at 100% progress. Solution:

```
target_cell = current * GRID_CELLS / total_operations
```

When `target_cell` jumps (e.g. from cell 0 to cell 16 in one op), all
intermediate cells are filled in one sweep so the painted area stays
**continuous** — no diagonals, no gaps.

#### Cell-by-cell cursor animation

When the cursor jumps N cells at once, painting all N cells instantly
looks like whole rows appearing in a single frame — visually jarring.
Instead, the yellow cursor is animated cell by cell with a ~5ms delay
per cell, leaving the dense-shade pattern behind it. Result: a smooth
progressive sweep.

The 5ms delay uses the bash builtin `read -rt 0.005 _ < /dev/zero` —
more precise than `sleep 0.005` (which forks a process every call and
has ~10ms granularity) and instantaneous because it's a builtin.

#### Filled-cell glyph: ▓ on blue (the big lesson)

Many alternatives were tried:

| Attempt                                       | Result                                                       |
| --------------------------------------------- | ------------------------------------------------------------ |
| `█` (full block) black-on-white               | Renders as a solid black block — `█` masks the background    |
| ` ` (space) on white                          | OK but visually flat, not Defrag at all                      |
| `▒` (medium shade) blue-on-white              | The internal pattern blends into a uniform pale blue         |
| `▓` (dense shade) on every cell, white-on-blue | Cells merge into one bar — too dense                         |
| Two-column cells (`▓` + blue space)           | Blue spaces form vertical columns dominating the image       |
| Checker `▓ / ▒` based on `(row+col) % 2`      | Tweed-like texture, individual cells still invisible         |
| Checker `■ / blue space`                      | Distinct pixels but too sparse — looks like a constellation  |

**Final choice**: `printf "%s%s▓%s" "$C_BG_BLUE" "$C_FG_WHITE" "$C_RESET"`.
The `▓` glyph (Unicode U+2593) carries its own dense-shade pattern, and
on a modern terminal that combination gives the best legibility-vs-style
trade-off. For deletions: same glyph but foreground `38;5;245` (pale
grey).

#### Active cursor: blinking yellow block

For the cell currently being processed (the equivalent of Defrag's
yellow `W`):

```bash
paint_cell "$target_cell" " " "$C_BG_YELLOW_BLINK"
```

A space on yellow background **with ANSI attribute 5 (slow blink)**.
Cleaner than a yellow `W` on yellow (low contrast), and the blink is
free — the terminal handles it, no Bash CPU cost. Terminals that ignore
attribute 5 simply show solid yellow (no regression).

#### Anti-flicker

The Status frame has its borders drawn **once** by `draw_status_frame()`
and only its 4 inner content rows redrawn by `draw_status_content()`.
Redrawing the bright-yellow borders every tick produces very visible
flicker.

#### Redraw throttling

- The active cell is repainted on **every** operation (cheap: one cursor
  positioning + one character).
- The Status frame content is redrawn only every
  `total_operations / 200` operations (≈ 200 redraws across the whole
  sync, with a floor of 1).
- The full grid is **never** redrawn during the sync, only at the start
  to paint it empty.

This keeps the terminal responsive even when rsync emits 50,000+
operations.

### ANSI 256-color palette

| Code         | Use                                |
| ------------ | ---------------------------------- |
| `48;5;19`    | Defrag deep-blue background        |
| `48;5;255`   | Bright white background            |
| `38;5;110`   | Pale-blue foreground (unused cell) |
| `48;5;226`   | Bright yellow background (cursor)  |
| `48;5;240`   | Mid-grey background                |
| `38;5;245`   | Pale-grey foreground (deletions)   |
| `1;38;5;226` | Bold yellow foreground (titles)    |
| `1;38;5;196` | Bold red foreground (errors)       |
| `48;5;88`    | Burgundy red background (status)   |
| `38;5;19`    | Deep-blue foreground               |

Always use the 256-color form (`\e[38;5;Nm` / `\e[48;5;Nm`); the basic
8-color ANSI codes give inconsistent results across terminals.

### Cleanup trap

The `EXIT` trap is essential. Without it, `Ctrl+C` or any crash leaves
the user with: hidden cursor, blue background, modified kernel
parameters, leftover `/tmp/dr*` files. The trap takes care of all of
that.

## Tested on

- Linux Mint (Cinnamon, MATE, XFCE)
- Debian 12
- Ubuntu 22.04+
- Terminals: `lxterminal`, `gnome-terminal`, `konsole`, `xterm`,
  `tilix`, `kitty`, `alacritty`

## License

MIT — see `LICENSE` (add one when publishing on GitHub).

## Contributing

Issues and PRs welcome. The most useful contributions are:

- Reports of terminals where the Defrag UI breaks (please include
  `tput cols`, `tput lines`, `$TERM`, and a screenshot if you can).
- Performance reports on very large syncs (100k+ files).
- Translations (the script header and messages are in English; user-
  visible strings are isolated near each `echo` / `printf` call).
