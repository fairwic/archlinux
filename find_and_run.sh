#!/bin/bash
# find_and_run.sh - Automatically find Arch Linux installation USB and run installation script
# This script solves the issue of inconsistent USB mount points

# Set error handling
# Note: Using simple error handling, avoiding pipefail (better compatibility)
set -e

echo "=== Arch Linux Installation Helper Script ==="
echo "Searching for installation script..."

# Target filename
INSTALL_SCRIPT="install_archlinux.sh"
SCRIPT_DIR=""
MOUNTED_USB=0  # Whether USB was mounted by this script

# Check if script is found
find_script() {
    local dir="$1"
    if [ -f "$dir/$INSTALL_SCRIPT" ]; then
        SCRIPT_DIR="$dir"
        return 0
    elif [ -f "$dir/scripts/$INSTALL_SCRIPT" ]; then
        SCRIPT_DIR="$dir/scripts"
        return 0
    fi
    return 1
}

# Search in already mounted filesystems
find_in_mounted() {
    # First check current directory
    if find_script "$(pwd)"; then
        echo "Installation script found in current directory"
        return 0
    fi
    
    # Check possible USB mount points
    local common_mounts=("/run/archiso/bootmnt" "/mnt/usb" "/media" "/mnt" "/run/media")
    
    for mount_point in "${common_mounts[@]}"; do
        if [ -d "$mount_point" ]; then
            # If it's a directory, check directly first
            if find_script "$mount_point"; then
                echo "Installation script found in $mount_point"
                return 0
            fi
            
            # Check subdirectories
            for subdir in "$mount_point"/*; do
                if [ -d "$subdir" ]; then
                    if find_script "$subdir"; then
                        echo "Installation script found in $subdir"
                        return 0
                    fi
                fi
            done
        fi
    done
    
    return 1
}

# Try to mount USB and search
mount_and_find() {
    echo "Installation script not found in mounted locations, trying to mount USB drives..."
    
    # Create temporary mount point
    mkdir -p /mnt/usb
    
    # Find possible USB devices
    local possible_usb=($(lsblk -o NAME,TYPE,SIZE | grep "part" | grep -v "boot\|root\|swap" | awk '{print $1}'))
    
    for dev in "${possible_usb[@]}"; do
        dev="/dev/$dev"
        echo "Attempting to mount: $dev"
        
        if mount "$dev" /mnt/usb 2>/dev/null; then
            echo "Successfully mounted $dev to /mnt/usb"
            MOUNTED_USB=1
            
            if find_script "/mnt/usb"; then
                echo "Installation script found in /mnt/usb"
                return 0
            fi
            
            # Script not found, unmount device and continue trying
            umount /mnt/usb
            MOUNTED_USB=0
        fi
    done
    
    echo "Could not find USB drive with installation script"
    return 1
}

# Search for script
find_install_script() {
    # First look in mounted filesystems
    if find_in_mounted; then
        return 0
    fi
    
    # Try mounting USB and searching
    if mount_and_find; then
        return 0
    fi
    
    return 1
}

# Cleanup function
cleanup() {
    # If we mounted the USB, unmount it during cleanup
    if [ $MOUNTED_USB -eq 1 ] && [ -d "/mnt/usb" ]; then
        echo "Cleanup: Unmounting /mnt/usb"
        umount /mnt/usb
    fi
}

# Set cleanup function to execute on exit
trap cleanup EXIT

# Main function
main() {
    # Search for installation script
    if ! find_install_script; then
        echo "Error: Could not find $INSTALL_SCRIPT"
        echo "Please ensure the installation script is in the USB root directory or scripts subdirectory"
        exit 1
    fi
    
    # Ensure script has execute permission
    chmod +x "$SCRIPT_DIR/$INSTALL_SCRIPT"
    
    echo "Installation script found: $SCRIPT_DIR/$INSTALL_SCRIPT"
    echo "============================================================"
    echo "Starting installation script. Press Ctrl+C to cancel..."
    sleep 2
    
    # Use bash to execute script (avoid shell compatibility issues)
    cd "$SCRIPT_DIR"
    echo "Running command: bash $INSTALL_SCRIPT $@"
    bash "$INSTALL_SCRIPT" "$@"
}

# Run main function, passing all arguments
main "$@"