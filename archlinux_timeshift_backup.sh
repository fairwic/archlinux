#!/bin/bash
# Arch Linux System Backup and Restore Script (using Timeshift)
# This script is used to setup and manage Arch Linux system backups and restoration

set -euo pipefail

# Colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Please run this script with root privileges, e.g.: sudo $0"
    fi
}

# Install Timeshift
install_timeshift() {
    log "Installing Timeshift..."
    
    # Check if yay is already installed
    if ! command -v yay &> /dev/null; then
        log "Installing AUR helper yay..."
        # Install build tools and Go language
        pacman -S --needed --noconfirm base-devel git go curl
        
        # Create a non-root build user if it doesn't exist
        if ! id -u builduser &>/dev/null; then
            useradd -m builduser
        fi
        
        # Create temporary directory
        temp_dir=$(mktemp -d)
        chown -R builduser:builduser "$temp_dir"
        cd "$temp_dir"
        
        # Try to download the latest release version instead of cloning repo
        log "Downloading yay release version..."
        YAY_VERSION="12.3.5"
        
        # Create download function to automatically select the fastest method
        download_yay() {
            # Try mirrors first
            log "Trying to download yay-${YAY_VERSION}.tar.gz from mirror..."
            if curl -L -o yay.tar.gz "https://ghproxy.com/https://github.com/Jguer/yay/releases/download/v${YAY_VERSION}/yay_${YAY_VERSION}_x86_64.tar.gz" --connect-timeout 10; then
                log "Download from ghproxy mirror successful"
                return 0
            fi
            
            log "Mirror download failed, trying direct download..."
            if curl -L -o yay.tar.gz "https://github.com/Jguer/yay/releases/download/v${YAY_VERSION}/yay_${YAY_VERSION}_x86_64.tar.gz" --connect-timeout 30; then
                log "Direct download successful"
                return 0
            fi
            
            log "Precompiled binary download failed, trying source code..."
            # Try source package
            if curl -L -o yay-src.tar.gz "https://ghproxy.com/https://github.com/Jguer/yay/archive/refs/tags/v${YAY_VERSION}.tar.gz" --connect-timeout 10; then
                log "Source code download from ghproxy successful"
                return 1  # Return 1 means need to compile
            fi
            
            if curl -L -o yay-src.tar.gz "https://github.com/Jguer/yay/archive/refs/tags/v${YAY_VERSION}.tar.gz" --connect-timeout 30; then
                log "Direct source code download successful"
                return 1  # Return 1 means need to compile
            fi
            
            # If all above fail, try to clone AUR repo
            log "Source package download failed, falling back to AUR repo..."
            if git clone https://aur.archlinux.org/yay.git; then
                log "AUR repo clone successful"
                return 2  # Return 2 means use AUR repo
            fi
            
            return 255  # All failed
        }
        
        # Start download and install
        download_result=$(download_yay)
        
        if [ "$download_result" = "0" ]; then
            # Install precompiled version directly
            log "Installing precompiled yay binary..."
            tar xzf yay.tar.gz
            install -Dm755 yay_${YAY_VERSION}_x86_64/yay /usr/bin/yay
            install -Dm644 yay_${YAY_VERSION}_x86_64/yay.8 /usr/share/man/man8/yay.8
            
        elif [ "$download_result" = "1" ]; then
            # Compile from source
            log "Building yay from source..."
            tar xzf yay-src.tar.gz
            cd "yay-${YAY_VERSION}"
            chown -R builduser:builduser .
            sudo -u builduser bash -c 'go build'
            install -Dm755 yay /usr/bin/yay
            
        elif [ "$download_result" = "2" ]; then
            # Build from AUR repo
            log "Building yay from AUR..."
            cd yay
            # Ensure PKGBUILD exists
            if [ ! -f PKGBUILD ]; then
                error "PKGBUILD file not found, cannot build yay"
            fi
            chown -R builduser:builduser .
            sudo -u builduser bash -c 'makepkg -si --noconfirm --skippgpcheck'
            
        else
            error "All download methods failed, please check your network connection or install yay manually"
        fi
        
        cd - > /dev/null
        rm -rf "$temp_dir"
        
        # Check if yay installed successfully
        if ! command -v yay &> /dev/null; then
            error "Failed to install yay, please install it manually and try again"
        else
            log "yay installed successfully!"
        fi
    fi
    
    # Use yay to install timeshift (as a non-root user)
    if id -u builduser &>/dev/null; then
        log "Using yay to install timeshift (this may take some time)..."
        # Try to configure pacman mirrors for faster downloads
        if command -v pacman-mirrors &> /dev/null; then
            echo "Configuring pacman mirrors for faster downloads..."
            pacman-mirrors -c China && pacman -Syy
        fi
        
        # Set longer timeout to avoid download timeout
        sudo -u builduser bash -c "yay -S --noconfirm --noprovides --answerdiff=None --answerclean=None --mflags='--skippgpcheck' timeshift" || error "Failed to install Timeshift"
    else
        # Fallback to nobody user if builduser doesn't exist
        sudo -u nobody yay -S --noconfirm --noprovides --answerdiff=None --answerclean=None --mflags='--skippgpcheck' timeshift || error "Failed to install Timeshift"
    fi
    
    log "Timeshift installation completed"
}

# Configure Timeshift's RSYNC mode
configure_timeshift_rsync() {
    log "Configuring Timeshift RSYNC mode..."
    
    # Create configuration directory
    mkdir -p /etc/timeshift
    
    # Set basic configuration
    cat > /etc/timeshift/timeshift.json <<EOF
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "false",
  "include_btrfs_home" : "false",
  "include_app_data" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [
    "/home/**",
    "/opt/**",
    "/var/cache/**",
    "/var/log/**",
    "/var/tmp/**",
    "/tmp/**",
    "/root/**",
    "/lost+found",
    "/media/**",
    "/mnt/**",
    "/proc/**",
    "/sys/**",
    "/dev/**",
    "/run/**"
  ],
  "exclude-apps" : []
}
EOF
    
    # Get root partition UUID and set as backup partition
    ROOT_UUID=$(findmnt -no UUID /)
    sed -i "s/\"backup_device_uuid\" : \"\"/\"backup_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
    sed -i "s/\"parent_device_uuid\" : \"\"/\"parent_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
    
    log "Timeshift RSYNC mode configuration completed"
}

# Configure Timeshift's BTRFS mode
configure_timeshift_btrfs() {
    log "Checking if BTRFS mode can be used..."
    
    # Check if root filesystem is BTRFS
    if [ "$(findmnt -no FSTYPE /)" = "btrfs" ]; then
        log "BTRFS filesystem detected, configuring Timeshift BTRFS mode..."
        
        # Create configuration directory
        mkdir -p /etc/timeshift
        
        # Set basic configuration
        cat > /etc/timeshift/timeshift.json <<EOF
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home" : "false",
  "include_app_data" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [],
  "exclude-apps" : []
}
EOF
        
        # Get root partition UUID and set as backup partition
        ROOT_UUID=$(findmnt -no UUID /)
        sed -i "s/\"backup_device_uuid\" : \"\"/\"backup_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
        sed -i "s/\"parent_device_uuid\" : \"\"/\"parent_device_uuid\" : \"$ROOT_UUID\"/" /etc/timeshift/timeshift.json
        
        log "Timeshift BTRFS mode configuration completed"
        return 0
    else
        log "BTRFS filesystem not detected, will use RSYNC mode"
        return 1
    fi
}

# Create backup
create_backup() {
    log "Creating system backup..."
    
    # Create label name
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    COMMENT="Auto_Backup_$TIMESTAMP"
    
    # Use timeshift to create snapshot
    if ! timeshift --create --comments "$COMMENT" --verbose; then
        error "Failed to create backup"
    fi
    
    log "System backup created successfully, label: $COMMENT"
}

# List available backups
list_backups() {
    log "Available system backups:"
    
    # List all snapshots
    timeshift --list
    
    echo ""
    log "Use the 'Restore Backup' option and enter a snapshot name to restore the system"
}

# Restore backup
restore_backup() {
    log "Please select a snapshot to restore from the following backups:"
    
    # Get available snapshot list
    SNAPSHOTS=$(timeshift --list | grep "^[0-9]" | awk '{print $3}')
    
    if [ -z "$SNAPSHOTS" ]; then
        error "No available backup snapshots found"
    fi
    
    # Display available snapshots
    echo "$SNAPSHOTS" | nl
    
    # Read user selection
    read -p "Enter the snapshot number to restore: " choice
    
    # Get selected snapshot name
    SELECTED_SNAPSHOT=$(echo "$SNAPSHOTS" | sed -n "${choice}p")
    
    if [ -z "$SELECTED_SNAPSHOT" ]; then
        error "Invalid selection"
    fi
    
    log "You selected to restore snapshot: $SELECTED_SNAPSHOT"
    read -p "Are you sure you want to restore this snapshot? This will overwrite the current system. (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "Restoring system to snapshot: $SELECTED_SNAPSHOT"
        log "Warning: The system will automatically reboot after restoration..."
        
        # Confirm if need to restart immediately
        read -p "Press Enter to continue when ready..." nothing
        
        # Execute restoration
        if ! timeshift --restore --snapshot "$SELECTED_SNAPSHOT" --verbose --yes; then
            error "System restoration failed"
        fi
    else
        log "Restoration operation cancelled"
    fi
}

# Setup scheduled backups
setup_scheduled_backups() {
    log "Setting up scheduled backups..."
    
    # Enable and start timeshift-autosnap service
    systemctl enable cronie.service
    systemctl start cronie.service
    
    # Create daily backup cron task
    echo "0 4 * * * /usr/bin/timeshift --create --comments \"Daily Auto Backup\" --skip-grub > /dev/null 2>&1" > /tmp/timeshift-cron
    crontab /tmp/timeshift-cron
    rm /tmp/timeshift-cron
    
    log "Scheduled daily backup at 4:00 AM"
    log "System will keep: 2 monthly backups, 3 weekly backups, 5 daily backups"
}

# Setup Timeshift to automatically create snapshot at boot
setup_boot_snapshot() {
    log "Setting up boot time auto backup..."
    
    # Modify Timeshift configuration
    sed -i 's/"schedule_boot" : "false"/"schedule_boot" : "true"/' /etc/timeshift/timeshift.json
    
    log "Boot time auto-snapshot feature enabled"
}

# Clean up old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    # Use timeshift's auto cleanup feature
    if ! timeshift --delete-all; then
        warn "Problem cleaning up old backups, there may be no expired backups to clean"
    fi
    
    log "Old backup cleanup completed"
}

# Main function
main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Arch Linux Backup & Restore Tool    ${NC}"
    echo -e "${BLUE}    (based on Timeshift)                ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Check permissions
    check_root
    
    # Main menu
    while true; do
        echo ""
        echo "Select an operation:"
        echo "1) Install and configure Timeshift"
        echo "2) Create system backup"
        echo "3) List available backups"
        echo "4) Restore system backup"
        echo "5) Setup scheduled auto backups"
        echo "6) Clean up old backups"
        echo "0) Exit"
        
        read -p "Enter your choice [0-6]: " choice
        
        case "$choice" in
            1)
                install_timeshift
                if ! configure_timeshift_btrfs; then
                    configure_timeshift_rsync
                fi
                ;;
            2)
                create_backup
                ;;
            3)
                list_backups
                ;;
            4)
                restore_backup
                ;;
            5)
                setup_scheduled_backups
                setup_boot_snapshot
                ;;
            6)
                cleanup_old_backups
                ;;
            0)
                log "Exiting program"
                exit 0
                ;;
            *)
                warn "Invalid option: $choice"
                ;;
        esac
    done
}

# Run main function
main 