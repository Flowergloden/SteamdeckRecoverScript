#!/bin/bash
# Script: Start.sh
# Purpose: Restore packages from ~/pkglist on Steam Deck (SteamOS Holo) with pre/post hooks
# Author: System Admin
# Date: $(date +%Y-%m-%d)
# Warning: This script will install many packages. Ensure you trust the source of pkglist.

set -u  # Only strict error on unset variables, not on command failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PKG_LIST_FILE="./pkglist"
PRE_HOOK_SCRIPT="./pre_hook.sh"
POST_HOOK_SCRIPT="./post_hook.sh"
PARU_FLAGS="--skipreview --needed --noconfirm"

# Variables
USE_PROXY=false
PROXY_URL=""

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

# Check if required files exist
check_requirements() {
    if [[ ! -f "$PKG_LIST_FILE" ]]; then
        print_error "Package list file not found: $PKG_LIST_FILE"
        exit 1
    fi
    
    if [[ ! -s "$PKG_LIST_FILE" ]]; then
        print_error "Package list file is empty: $PKG_LIST_FILE"
        exit 1
    fi
    
    if ! command -v paru &> /dev/null; then
        print_error "paru AUR helper is not installed. Please install it first."
        exit 1
    fi
}

# Disable SteamOS readonly mode
disable_readonly_mode() {
    print_status "Disabling SteamOS readonly mode..."
    if ! sudo steamos-readonly disable; then
        print_error "Failed to disable SteamOS readonly mode"
        exit 1
    fi
    print_status "SteamOS readonly mode disabled"
}

# Enable SteamOS readonly mode
enable_readonly_mode() {
    print_status "Re-enabling SteamOS readonly mode..."
    if ! sudo steamos-readonly enable; then
        print_error "Failed to re-enable SteamOS readonly mode"
        # Continue anyway since we don't want to leave the system in a vulnerable state
    else
        print_status "SteamOS readonly mode re-enabled"
    fi
}

# Execute pre-installation hook if exists
execute_pre_hook() {
    if [[ -f "$PRE_HOOK_SCRIPT" ]]; then
        print_status "Executing pre-installation hook: $PRE_HOOK_SCRIPT"
        
        if [[ ! -x "$PRE_HOOK_SCRIPT" ]]; then
            print_warning "Pre-hook script is not executable, making it executable..."
            chmod +x "$PRE_HOOK_SCRIPT"
        fi
        
        if ! "$PRE_HOOK_SCRIPT"; then
            print_error "Pre-installation hook failed. Aborting installation."
            enable_readonly_mode  # Re-enable readonly mode before exiting
            exit 1
        else
            print_status "Pre-installation hook executed successfully"
        fi
    else
        print_status "No pre-installation hook found at $PRE_HOOK_SCRIPT"
    fi
}

# Execute post-installation hook if exists
execute_post_hook() {
    if [[ -f "$POST_HOOK_SCRIPT" ]]; then
        print_status "Executing post-installation hook: $POST_HOOK_SCRIPT"
        
        if [[ ! -x "$POST_HOOK_SCRIPT" ]]; then
            print_warning "Post-hook script is not executable, making it executable..."
            chmod +x "$POST_HOOK_SCRIPT"
        fi
        
        if ! "$POST_HOOK_SCRIPT"; then
            print_error "Post-installation hook failed, but installation has completed."
            return 1
        else
            print_status "Post-installation hook executed successfully"
        fi
    else
        print_status "No post-installation hook found at $POST_HOOK_SCRIPT"
    fi
}

# Ask user if they want to use proxy
ask_proxy() {
    echo "====================================="
    echo "Proxy Configuration"
    echo "====================================="
    read -p "Do you want to use a proxy for package downloads? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_PROXY=true
        print_status "Proxy functionality enabled"
    else
        print_status "No proxy will be used"
    fi
}

# Configure proxy by starting clash and enabling proxy
configure_proxy() {
    if [[ "$USE_PROXY" == true ]]; then
        print_status "Configuring proxy settings..."
        
        # Check if clash directory and script exist
        if [[ -d "./clash" ]] && [[ -f "./clash/start.sh" ]]; then
            print_status "Starting clash proxy service..."
            
            # Reset CLASH_URL in .env file to avoid string parsing issues with special characters
            if [[ -f "./clash/.env" ]]; then
                print_status "Resetting CLASH_URL in .env file to prevent string parsing errors..."
                
                # Create a temporary file to hold the updated content
                local temp_env_file=$(mktemp)
                
                # Process the .env file line by line
                while IFS= read -r line || [[ -n "$line" ]]; do
                    if [[ $line =~ ^CLASH_URL= ]]; then
                        # Replace the CLASH_URL line with an empty value first to prevent parsing issues
                        echo "CLASH_URL=''" >> "$temp_env_file"
                    else
                        echo "$line" >> "$temp_env_file"
                    fi
                done < "./clash/.env"
                
                # Move the temporary file to replace the original
                mv "$temp_env_file" "./clash/.env"
                
                print_status "CLASH_URL reset completed"
            fi
            
            if ! sudo bash ./clash/start.sh; then
                print_error "Failed to start clash proxy service"
                exit 1
            fi
            
            print_status "Loading clash environment variables..."
            if [[ -f "/etc/profile.d/clash.sh" ]]; then
                source /etc/profile.d/clash.sh
            else
                print_warning "/etc/profile.d/clash.sh not found, skipping"
            fi
            
            print_status "Enabling proxy..."
            if ! proxyon; then
                print_error "Failed to enable proxy"
                exit 1
            fi
            
            print_status "Proxy configured and enabled successfully"
        else
            print_error "Clash directory or start.sh script not found"
            print_error "Expected path: ./clash/start.sh"
            exit 1
        fi
    fi
}

# Disable proxy by turning it off
disable_proxy() {
    if [[ "$USE_PROXY" == true ]]; then
        print_status "Disabling proxy..."
        if command -v proxyoff &> /dev/null; then
            if ! proxyoff; then
                print_warning "Failed to disable proxy"
            else
                print_status "Proxy disabled successfully"
            fi
        else
            print_warning "proxyoff command not found, skipping"
        fi
    fi
}

# Install packages from the list
install_packages() {
    print_status "Reading package list from $PKG_LIST_FILE"
    
    local total_packages=$(wc -l < "$PKG_LIST_FILE")
    print_status "Found $total_packages packages to install"
    
    # Pass the entire package list to paru at once
    print_status "Installing all packages at once using paru..."
    
    if paru $PARU_FLAGS -S - < "$PKG_LIST_FILE"; then
        print_status "All installable packages processed successfully"
    else
        print_warning "Some packages could not be installed (this is normal for unavailable packages)"
    fi
}

# Verify installed packages
verify_installation() {
    print_status "Verifying installed packages..."
    
    local missing_packages=()
    while IFS= read -r package; do
        [[ -z "$package" ]] && continue
        if ! pacman -Q "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done < "$PKG_LIST_FILE"
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        print_status "All packages verified successfully"
    else
        print_warning "Some packages could not be verified:"
        for pkg in "${missing_packages[@]}"; do
            print_warning "  - $pkg"
        done
        print_warning "These packages may require manual installation or are not available"
    fi
}

# Main execution
main() {
    print_status "Steam Deck Package Restorer with Hooks"
    echo "====================================="
    
    check_steamdeck
    check_requirements
    
    # Show package list info
    local pkg_count=$(wc -l < "$PKG_LIST_FILE")
    echo "Package list contains $pkg_count packages:"
    head -n 10 "$PKG_LIST_FILE"
    if [[ $pkg_count -gt 10 ]]; then
        echo "... and $((pkg_count - 10)) more packages"
    fi
    echo ""
    
    # Show hook information
    echo "Hook scripts:"
    echo "  Pre-hook: $([ -f "$PRE_HOOK_SCRIPT" ] && echo "✓ Found" || echo "✗ Not found")"
    echo "  Post-hook: $([ -f "$POST_HOOK_SCRIPT" ] && echo "✓ Found" || echo "✗ Not found")"
    echo ""
    
    ask_proxy
    
    echo ""
    echo "====================================="
    echo "Package Installation Summary"
    echo "====================================="
    echo "- Source file: $PKG_LIST_FILE"
    echo "- Total packages to install: $pkg_count"
    echo "- Using proxy: $([ "$USE_PROXY" = true ] && echo "Yes" || echo "No")"
    echo "- Pre-installation hook: $([ -f "$PRE_HOOK_SCRIPT" ] && echo "Yes" || echo "No")"
    echo "- Post-installation hook: $([ -f "$POST_HOOK_SCRIPT" ] && echo "Yes" || echo "No")"
    echo ""
    
    read -p "Proceed with installation? This may take a long time. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled"
        exit 0
    fi
    
    # Disable readonly mode before installing packages
    disable_readonly_mode
    
    configure_proxy
    
    # Execute pre-installation hook
    execute_pre_hook
    
    print_status "Starting package installation..."
    install_packages
    verify_installation
    
    # Execute post-installation hook
    execute_post_hook
    
    # Disable proxy if it was enabled
    disable_proxy
    
    # Re-enable readonly mode after installation
    enable_readonly_mode
    
    print_status "Package restoration completed!"
    print_status "Please restart your Steam Deck for all changes to take effect."
    print_status "Check system logs if you encounter any issues with installed packages."
}

# Run main function
main "$@"
exit 0
