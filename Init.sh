#!/bin/bash
# Script: Init.sh
# Purpose: Export current package list (including AUR) to ~/pkglist on Steam Deck (SteamOS Holo)
# Author: System Admin
# Date: $(date +%Y-%m-%d)
# Warning: This script will overwrite any existing pkglist file in ~/

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PKG_LIST_FILE="$HOME/pkglist"

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

# Main execution
main() {
    print_status "Steam Deck Package List Exporter"
    echo "====================================="
    
    check_steamdeck
    check_dependencies
    
    echo "This script will export all installed packages (official + AUR) to:"
    echo "  $PKG_LIST_FILE"
    echo ""
    echo "The file will contain one package name per line."
    echo ""
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled"
        exit 0
    fi
    
    # Create backup if file already exists
    if [[ -f "$PKG_LIST_FILE" ]]; then
        local backup_file="${PKG_LIST_FILE}_$(date +%Y%m%d_%H%M%S).bak"
        mv "$PKG_LIST_FILE" "$backup_file"
        print_status "Existing pkglist backed up to $backup_file"
    fi
    
    get_package_list
    verify_output
    
    print_status "Package list export completed!"
    print_status "You can now use this file to reinstall packages on another system."
}

# Run main function
main "$@"
exit 0
