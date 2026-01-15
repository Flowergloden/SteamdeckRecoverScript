#!/bin/bash
# Script: Init.sh
# Purpose: Export current package list (including AUR) to ~/pkglist on Steam Deck (SteamOS Holo)
#         Optionally initialize clash proxy software
# Author: System Admin
# Date: $(date +%Y-%m-%d)
# Warning: This script will overwrite any existing pkglist file in ~/
#          Proxy initialization will modify ./clash/.env file

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PKG_LIST_FILE="./pkglist"

# Function to print status messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Steam Deck
check_steamdeck() {
    if [[ ! -d "/home/deck" ]] || [[ ! -f "/etc/os-release" ]] || ! grep -q "SteamOS" "/etc/os-release"; then
        print_warning "This script is designed for Steam Deck running SteamOS Holo"
    fi
}

# Check if pacman and paru are available
check_dependencies() {
    if ! command -v pacman &> /dev/null; then
        print_error "pacman is not available"
        exit 1
    fi
    
    if ! command -v paru &> /dev/null; then
        print_warning "paru AUR helper not found, falling back to pacman for AUR detection"
    fi
}

# Get all installed packages (both official and AUR)
get_package_list() {
    print_status "Gathering installed packages..."
    
    # Get all explicitly installed packages (both official and AUR)
    # pacman -Q gives all installed packages
    # We'll use paru to identify which ones are AUR packages if available
    if command -v paru &> /dev/null; then
        # Get all installed packages
        pacman -Qqe > "$PKG_LIST_FILE"
    else
        # Fallback: get all packages using pacman only
        pacman -Qqe > "$PKG_LIST_FILE"
    fi
    
    # Count packages for confirmation
    local total_count=$(wc -l < "$PKG_LIST_FILE")
    print_status "Exported $total_count packages to $PKG_LIST_FILE"
}

# Verify the package list file was created
verify_output() {
    if [[ -f "$PKG_LIST_FILE" ]] && [[ -s "$PKG_LIST_FILE" ]]; then
        print_status "Package list successfully created at $PKG_LIST_FILE"
        print_status "First few entries:"
        head -n 5 "$PKG_LIST_FILE"
        if [[ $(wc -l < "$PKG_LIST_FILE") -gt 5 ]]; then
            echo "... and $(($(wc -l < "$PKG_LIST_FILE") - 5)) more packages"
        fi
    else
        print_error "Failed to create package list file"
        exit 1
    fi
}

# Initialize clash proxy software
initialize_clash_proxy() {
    print_status "Initializing Clash proxy software..."
    
    local clash_env_file="./clash/.env"
    
    # Check if clash directory and env file exist
    if [[ ! -d "./clash" ]]; then
        print_error "Clash directory not found. Creating directory..."
        mkdir -p "./clash"
    fi
    
    # Create .env file if it doesn't exist
    if [[ ! -f "$clash_env_file" ]]; then
        print_status "Creating $clash_env_file file..."
        cat > "$clash_env_file" << EOF
export CLASH_URL=''
export CLASH_SECRET=''
EOF
    fi
    
    # Get proxy URL
    local proxy_url
    read -p "Enter your Clash proxy URL: " proxy_url
    
    if [[ -z "$proxy_url" ]]; then
        print_warning "No proxy URL provided. Skipping proxy initialization."
        return 0
    fi
    
    # Update the CLASH_URL in the .env file using proper quoting to handle special characters
    if [[ -f "$clash_env_file" ]]; then
        # Use awk to safely replace the entire export line
        awk -v new_url="$proxy_url" '
        /^export CLASH_URL=/ { 
            gsub(/^export CLASH_URL=.*/, "export CLASH_URL=\x27" new_url "\x27")
        }
        /^export CLASH_SECRET=/ { 
            gsub(/^export CLASH_SECRET=.*/, "export CLASH_SECRET=\x27\x27")
        }
        { print }
        ' "$clash_env_file" > "${clash_env_file}.tmp" && mv "${clash_env_file}.tmp" "$clash_env_file"
        
        print_status "Updated CLASH_URL in $clash_env_file"
        print_status "CLASH_SECRET has been cleared in $clash_env_file"
    else
        print_error "Failed to find $clash_env_file"
        return 1
    fi
}

# Main execution
main() {
    print_status "Steam Deck Package List Exporter & Proxy Initializer"
    echo "======================================================"
    
    check_steamdeck
    check_dependencies
    
    echo "This script can perform the following actions:"
    echo "1. Export all installed packages (official + AUR) to:"
    echo "   $PKG_LIST_FILE"
    echo "2. Initialize Clash proxy software"
    echo ""
    echo "The package list file will contain one package name per line."
    echo ""
    
    read -p "Do you want to export the package list? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        # Create backup if file already exists
        if [[ -f "$PKG_LIST_FILE" ]]; then
            local backup_file="${PKG_LIST_FILE}_$(date +%Y%m%d_%H%M%S).bak"
            mv "$PKG_LIST_FILE" "$backup_file"
            print_status "Existing pkglist backed up to $backup_file"
        fi
        
        get_package_list
        verify_output
    else
        print_status "Skipping package list export"
    fi
    
    echo ""
    read -p "Do you want to initialize Clash proxy software? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        initialize_clash_proxy
    fi
    
    print_status "Package list export and proxy initialization completed!"
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "You can now use this file to reinstall packages on another system."
    fi
}

# Run main function
main "$@"
exit 0
