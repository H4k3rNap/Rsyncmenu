# Rsyncmenu

# Directory Synchronization Script

A simple and interactive bash script for synchronizing directories using rsync with a user-friendly interface and real-time feedback.

## 🚀 Features

- **Interactive Mode**: Prompts user for source and destination paths
- **Real-time Analysis**: Analyzes differences before synchronization
- **Dry-run Support**: Preview changes before applying them
- **Visual Feedback**: Animated spinner during operations
- **Error Handling**: Comprehensive validation and error messages
- **Safe Operations**: Prevents accidental synchronization of identical directories
- **Trash Exclusion**: Automatically excludes `.Trash-1000` directories

## 📋 Prerequisites

The script requires the following tools to be installed on your system:

- `rsync` - For directory synchronization
- `realpath` - For path resolution (part of coreutils)

### Installation on Ubuntu/Debian:
```bash
sudo apt install rsync coreutils
```

### Installation on CentOS/RHEL/Fedora:
```bash
# For CentOS/RHEL
sudo yum install rsync coreutils

# For Fedora
sudo dnf install rsync coreutils
```

### Installation on macOS:
```bash
# Using Homebrew
brew install rsync coreutils
```

## 🛠️ Installation

1. Clone this repository or download the script:
```bash
git clone https://github.com/yourusername/directory-sync-script.git
cd directory-sync-script
```

2. Make the script executable:
```bash
chmod +x sync_directories.sh
```

## 📖 Usage

Run the script:
```bash
./sync_directories.sh
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

## ⚙️ How It Works

### Synchronization Process

1. **Path Validation**: Verifies that both source and destination directories exist and are accessible
2. **Conflict Detection**: Ensures source and destination are not identical
3. **Pre-analysis**: Performs a dry-run to count the number of operations needed
4. **User Confirmation**: Allows user to review and confirm before making changes
5. **Synchronization**: Uses rsync with the following options:
   - `-a`: Archive mode (preserves permissions, timestamps, etc.)
   - `--delete`: Removes files in destination that don't exist in source
   - `--exclude='.Trash-1000'`: Excludes trash directories

### Rsync Options Explained

- **Archive Mode (`-a`)**: Preserves file permissions, timestamps, symbolic links, and ownership
- **Delete (`--delete`)**: Ensures destination is an exact mirror of source by removing extra files
- **Exclude (`--exclude`)**: Skips specified patterns (trash directories in this case)

## 🔒 Safety Features

- **Dry-run by Default**: Always shows what would be changed before applying
- **Path Validation**: Verifies directories exist before proceeding
- **Identity Check**: Prevents synchronization when source equals destination
- **Real-time Feedback**: Shows progress with animated spinner
- **Error Messages**: Clear, color-coded error messages for troubleshooting

## 🎯 Use Cases

- **Backup Creation**: Mirror important directories to backup locations
- **Server Synchronization**: Keep directories synchronized between servers
- **Development Workflows**: Sync code between development and testing environments
- **Media Management**: Organize and backup photo/video collections
- **Document Management**: Keep document folders synchronized across systems

## ⚠️ Important Notes

- **Destructive Operation**: The `--delete` option removes files in destination that don't exist in source
- **One-way Sync**: This script performs one-way synchronization (source → destination)
- **Permissions**: Ensure you have read access to source and write access to destination
- **Network Locations**: Works with network-mounted directories (NFS, SMB, etc.)

## 🐛 Troubleshooting

### Common Issues

**"Command not found" errors:**
- Install missing dependencies (rsync, realpath)
- Check if commands are in your PATH

**"Permission denied" errors:**
- Ensure read access to source directory
- Ensure write access to destination directory
- Run with appropriate permissions (avoid running as root unless necessary)

**"Directory does not exist" errors:**
- Verify directory paths are correct
- Check if directories are mounted (for network shares)
- Ensure proper spelling and case sensitivity

### Debug Mode

For detailed rsync output, you can modify the script to remove `> /dev/null 2>&1` from the rsync command line.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Guidelines

- Follow existing code style and formatting
- Add comments for complex logic
- Test thoroughly before submitting
- Update documentation as needed

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built using [rsync](https://rsync.samba.org/) - the fast, versatile file copying tool
- Inspired by the need for simple, safe directory synchronization
- Thanks to the open-source community for continuous improvements

## 📞 Support

If you encounter any issues or have questions:

1. Check the troubleshooting section above
2. Search existing [issues](https://github.com/yourusername/directory-sync-script/issues)
3. Create a new issue with detailed information about your problem

---

**⭐ If this script helped you, please consider giving it a star!**
