# Rsyncmenu

# Directory Synchronization Script

A simple and interactive bash script for synchronizing directories using rsync with a user-friendly interface and real-time feedback.

## * Features

- **Interactive Mode**: Prompts user for source and destination paths
- **Real-time Analysis**: Analyzes differences before synchronization
- **Dry-run Support**: Preview changes before applying them
- **Visual Feedback**: Animated spinner during operations
- **Error Handling**: Comprehensive validation and error messages
- **Safe Operations**: Prevents accidental synchronization of identical directories
- **Trash Exclusion**: Automatically excludes `.Trash-1000` directories

## * Prerequisites

The script requires the following tools to be installed on your system:

- `rsync` - For directory synchronization
- `realpath` - For path resolution (part of coreutils)

### Installation on Ubuntu/Debian:
```bash
sudo apt install rsync coreutils
```
## * Installation

1. Clone this repository or download the script:
```bash
git clone https://github.com/H4k3rNap/Rsyncmenu.git
cd Rsyncmenu
```

2. Make the script executable:
```bash
chmod +x rsyncmenu.sh
```

## * Usage

Run the script:
```bash
./rsyncmenu.sh
```

The script will guide you through the following steps:

1. **Source Directory**: Enter the path to the directory you want to sync from
2. **Destination Directory**: Enter the path to the directory you want to sync to
3. **Analysis**: The script analyzes differences between directories
4. **Confirmation**: Choose between dry-run mode or production mode
5. **Synchronization**: Execute the synchronization process

### Example Session:
```
Rsyncmenu 1.0

Enter the source directory path: /home/user/Documents
Source directory validated: /home/user/Documents

Enter the destination directory path: /backup/Documents
Destination directory validated: /backup/Documents

Analyzing differences between directories... Total operations detected: 15

Analysis completed: 15 operation(s) to perform
Source      : /home/user/Documents
Destination : /backup/Documents

Do you want to switch to production mode (without dry-run)? (y/N) y
Production mode activated: modifications will be applied.

Synchronization in progress... completed.

Synchronization results:
-----------------------------
- Source: /home/user/Documents
- Destination: /backup/Documents
- Total operations completed: 15

Synchronization completed.
Operation finished.
Press [ENTER] to quit ...
```
