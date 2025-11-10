#!/usr/bin/env bash

#===============================================================================
# Interactive HID Device Udev Rule Manager
# Purpose: Safely grant non-root access to specific USB HID devices
# Compatible: Most Linux distributions (Debian, Ubuntu, Fedora, Arch, etc.)
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Safer word splitting

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
readonly RULE_FILE="/etc/udev/rules.d/99-hid-permissions.rules"
readonly GROUP_NAME="plugdev"
readonly SCRIPT_NAME="$(basename "$0")"
readonly USER_NAME="${USER:-$(whoami)}"

#------------------------------------------------------------------------------
# Color output (with fallback for non-color terminals)
#------------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput &>/dev/null && tput setaf 1 &>/dev/null; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly BOLD=$(tput bold)
    readonly RESET=$(tput sgr0)
else
    readonly RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

#------------------------------------------------------------------------------
# Logging functions
#------------------------------------------------------------------------------
log_info() {
    echo "${BLUE}ℹ${RESET} $*"
}

log_success() {
    echo "${GREEN}✓${RESET} $*"
}

log_warning() {
    echo "${YELLOW}⚠${RESET} $*" >&2
}

log_error() {
    echo "${RED}✗${RESET} $*" >&2
}

print_separator() {
    echo "${BOLD}────────────────────────────────────────────────────────${RESET}"
}

#------------------------------------------------------------------------------
# Error handler
#------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        log_info "Please review the error messages above"
    fi
}
trap cleanup EXIT

#------------------------------------------------------------------------------
# Prerequisite checks
#------------------------------------------------------------------------------
check_requirements() {
    local missing_cmds=()
   
    for cmd in udevadm sudo getent id; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
   
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_info "Please install the necessary packages for your distribution"
        exit 1
    fi
   
    # Check if running as root (not recommended)
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root is not recommended"
        read -rp "Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    fi
   
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        log_info "This script requires sudo privileges"
        if ! sudo -v; then
            log_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi
}

#------------------------------------------------------------------------------
# Detect HID devices
#------------------------------------------------------------------------------
detect_hid_devices() {
    log_info "Scanning for HID devices..."
   
    local -a hid_paths=()
    local -a hid_info=()
    local index=1
   
    # Check if /dev/hidraw* exists
    if ! compgen -G "/dev/hidraw*" &>/dev/null; then
        log_error "No HID devices found in /dev/hidraw*"
        log_info "Possible reasons:"
        log_info "  • No HID devices are connected"
        log_info "  • Kernel module 'usbhid' or 'hidraw' is not loaded"
        log_info "  • Device permissions prevent detection"
        exit 1
    fi
   
    for hid in /dev/hidraw*; do
        [[ -e "$hid" ]] || continue
       
        # Get device info with error handling
        local info vendor product iface manufacturer device_name
        if ! info=$(udevadm info --attribute-walk --name="$hid" 2>/dev/null); then
            log_warning "Failed to read info for $hid (skipping)"
            continue
        fi
       
        # Extract VID/PID
        vendor=$(echo "$info" | grep -m1 'ATTRS{idVendor}' | sed -n 's/.*=="\([^"]*\)".*/\1/p')
        product=$(echo "$info" | grep -m1 'ATTRS{idProduct}' | sed -n 's/.*=="\([^"]*\)".*/\1/p')
       
        # Skip if VID/PID not found
        if [[ -z "$vendor" || -z "$product" ]]; then
            log_warning "Could not determine VID/PID for $hid (skipping)"
            continue
        fi
       
        # Try to get human-readable names
        manufacturer=$(echo "$info" | grep -m1 'ATTRS{manufacturer}' | sed -n 's/.*=="\([^"]*\)".*/\1/p')
        device_name=$(echo "$info" | grep -m1 'ATTRS{product}' | sed -n 's/.*=="\([^"]*\)".*/\1/p')
        iface=$(echo "$info" | grep -m1 'KERNELS==' | sed -n 's/.*=="\([^"]*\)".*/\1/p')
       
        # Build display string
        local display_name="$vendor:$product"
        [[ -n "$manufacturer" ]] && display_name+=" [$manufacturer"
        [[ -n "$device_name" ]] && display_name+=" $device_name"
        [[ -n "$manufacturer" ]] && display_name+="]"
        display_name+=" → $hid"
        [[ -n "$iface" ]] && display_name+=" (interface: $iface)"
       
        hid_paths+=("$hid")
        hid_info+=("$vendor:$product:$display_name")
       
        echo "  ${BOLD}[$index]${RESET} $display_name"
        ((index++))
    done
   
    if [[ ${#hid_paths[@]} -eq 0 ]]; then
        log_error "No valid HID devices detected"
        log_info "Connect your device and run the script again"
        exit 1
    fi
   
    # Return arrays via global variables (bash doesn't support returning arrays)
    HID_PATHS=("${hid_paths[@]}")
    HID_INFO=("${hid_info[@]}")
}

#------------------------------------------------------------------------------
# Get user selection
#------------------------------------------------------------------------------
get_user_selection() {
    local max_devices=${#HID_PATHS[@]}
   
    print_separator
    echo "${BOLD}Select device(s) to configure:${RESET}"
    echo "  • Enter a single number (e.g., ${BOLD}1${RESET})"
    echo "  • Enter multiple numbers separated by commas (e.g., ${BOLD}1,3,5${RESET})"
    echo "  • Enter a range (e.g., ${BOLD}1-3${RESET})"
    echo "  • Press Ctrl+C to cancel"
    print_separator
   
    local selection valid_selection=false
   
    while [[ "$valid_selection" == false ]]; do
        read -rp "${BOLD}Your selection:${RESET} " selection
       
        # Trim whitespace
        selection=$(echo "$selection" | xargs)
       
        if [[ -z "$selection" ]]; then
            log_warning "Empty selection. Please try again."
            continue
        fi
       
        # Validate and parse selection
        local -a selected_indices=()
        IFS=',' read -ra parts <<< "$selection"
       
        for part in "${parts[@]}"; do
            part=$(echo "$part" | xargs)  # Trim spaces
           
            # Check for range (e.g., 1-3)
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                local start="${BASH_REMATCH[1]}"
                local end="${BASH_REMATCH[2]}"
               
                if [[ $start -lt 1 || $end -gt $max_devices || $start -gt $end ]]; then
                    log_warning "Invalid range: $part (valid: 1-$max_devices)"
                    continue 2
                fi
               
                for ((i=start; i<=end; i++)); do
                    selected_indices+=("$i")
                done
            # Check for single number
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                if [[ $part -lt 1 || $part -gt $max_devices ]]; then
                    log_warning "Invalid number: $part (valid: 1-$max_devices)"
                    continue 2
                fi
                selected_indices+=("$part")
            else
                log_warning "Invalid input: $part"
                continue 2
            fi
        done
       
        if [[ ${#selected_indices[@]} -eq 0 ]]; then
            log_warning "No valid devices selected"
            continue
        fi
       
        # Remove duplicates and sort
        SELECTED_INDICES=($(printf '%s\n' "${selected_indices[@]}" | sort -nu))
        valid_selection=true
    done
   
    log_success "Selected ${#SELECTED_INDICES[@]} device(s)"
}

#------------------------------------------------------------------------------
# Ensure group exists and user is member
#------------------------------------------------------------------------------
setup_group() {
    # Create group if it doesn't exist
    if ! getent group "$GROUP_NAME" &>/dev/null; then
        log_info "Creating group '$GROUP_NAME'..."
        if sudo groupadd "$GROUP_NAME"; then
            log_success "Group '$GROUP_NAME' created"
        else
            log_error "Failed to create group '$GROUP_NAME'"
            exit 1
        fi
    else
        log_success "Group '$GROUP_NAME' already exists"
    fi
   
    # Add user to group if needed
    if id -nG "$USER_NAME" 2>/dev/null | grep -qw "$GROUP_NAME"; then
        log_success "User '$USER_NAME' is already in group '$GROUP_NAME'"
        return 0
    else
        log_info "Adding user '$USER_NAME' to group '$GROUP_NAME'..."
        if sudo usermod -aG "$GROUP_NAME" "$USER_NAME"; then
            log_success "User added to group"
            echo
            log_warning "${BOLD}IMPORTANT:${RESET} You must log out and log back in for group changes to take effect!"
            echo "           Alternatively, run: ${BOLD}newgrp $GROUP_NAME${RESET}"
            NEED_RELOGIN=true
            return 0
        else
            log_error "Failed to add user to group '$GROUP_NAME'"
            exit 1
        fi
    fi
}

#------------------------------------------------------------------------------
# Create udev rules
#------------------------------------------------------------------------------
create_udev_rules() {
    log_info "Creating udev rules in $RULE_FILE..."
   
    # Backup existing file
    if [[ -f "$RULE_FILE" ]]; then
        local backup="${RULE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        if sudo cp "$RULE_FILE" "$backup"; then
            log_info "Existing rules backed up to: $backup"
        fi
    fi
   
    # Create new rules file with header
    local rule_content="# HID device permissions - Generated by $SCRIPT_NAME on $(date)
# This file grants read/write access to selected HID devices for the '$GROUP_NAME' group
#
# DO NOT EDIT MANUALLY - Re-run $SCRIPT_NAME to update
#

"
   
    # Add rules for each selected device
    for num in "${SELECTED_INDICES[@]}"; do
        local hid="${HID_PATHS[$((num-1))]}"
        local info="${HID_INFO[$((num-1))]}"
        local vendor=$(echo "$info" | cut -d':' -f1)
        local product=$(echo "$info" | cut -d':' -f2)
        local description=$(echo "$info" | cut -d':' -f3-)
       
        rule_content+="# $description
SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$vendor\", ATTRS{idProduct}==\"$product\", MODE=\"0660\", GROUP=\"$GROUP_NAME\"

"
        log_success "Added rule for $vendor:$product"
    done
   
    # Write rules atomically
    if echo "$rule_content" | sudo tee "$RULE_FILE" >/dev/null; then
        log_success "Udev rules file created successfully"
    else
        log_error "Failed to write udev rules file"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Apply udev rules
#------------------------------------------------------------------------------
apply_udev_rules() {
    log_info "Reloading udev rules..."
   
    if sudo udevadm control --reload-rules; then
        log_success "Udev rules reloaded"
    else
        log_error "Failed to reload udev rules"
        exit 1
    fi
   
    log_info "Triggering udev events..."
    if sudo udevadm trigger --subsystem-match=hidraw; then
        log_success "Udev events triggered"
    else
        log_warning "Failed to trigger udev events (non-fatal)"
    fi
   
    # Give udev a moment to apply changes
    sleep 1
}

#------------------------------------------------------------------------------
# Display results
#------------------------------------------------------------------------------
show_results() {
    print_separator
    echo "${BOLD}Current HID device permissions:${RESET}"
    print_separator
   
    for num in "${SELECTED_INDICES[@]}"; do
        local hid="${HID_PATHS[$((num-1))]}"
        if [[ -e "$hid" ]]; then
            ls -lh "$hid" | awk '{printf "  %s  %s ← %s\n", $1, $4, $9}'
        fi
    done
   
    print_separator
    echo
    log_success "${BOLD}Configuration complete!${RESET}"
    echo
    echo "${BOLD}Next steps:${RESET}"
   
    if [[ "${NEED_RELOGIN:-false}" == true ]]; then
        echo "  ${BOLD}1.${RESET} Log out and log back in (or run: ${BOLD}newgrp $GROUP_NAME${RESET})"
        echo "  ${BOLD}2.${RESET} Unplug and replug your device(s)"
        echo "  ${BOLD}3.${RESET} Test device access with your application"
    else
        echo "  ${BOLD}1.${RESET} Unplug and replug your device(s)"
        echo "  ${BOLD}2.${RESET} Test device access with your application"
    fi
   
    echo
    log_info "To verify permissions, run: ${BOLD}ls -l /dev/hidraw*${RESET}"
    log_info "To view rules, run: ${BOLD}cat $RULE_FILE${RESET}"
}

#------------------------------------------------------------------------------
# Main execution
#------------------------------------------------------------------------------
main() {
    echo
    echo "${BOLD}═══════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}    Interactive HID Device Udev Rule Manager${RESET}"
    echo "${BOLD}═══════════════════════════════════════════════════════${RESET}"
    echo
   
    check_requirements
    print_separator
   
    # Declare global arrays for device info
    declare -a HID_PATHS
    declare -a HID_INFO
    declare -a SELECTED_INDICES
    declare NEED_RELOGIN=false
   
    detect_hid_devices
    get_user_selection
   
    print_separator
    setup_group
    print_separator
   
    create_udev_rules
    apply_udev_rules
   
    show_results
}

# Run main function
main "$@"
