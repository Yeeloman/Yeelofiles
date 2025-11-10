# HID Device Permissions Setup Script

## Overview

This script (`setup-hid-permissions.sh`) fixes USB HID device permissions on Linux systems, allowing non-root users to access keyboards, mice, and other HID devices without requiring `sudo`. It's specifically useful for custom keyboards (like the G-COME M68 HE) that need direct hardware access.

## What It Does

- **Detects** all connected HID devices (`/dev/hidraw*`)
- **Creates** udev rules to grant your user access to selected devices
- **Configures** the `plugdev` group with appropriate permissions
- **Applies** changes automatically without manual configuration

## Prerequisites

- Linux-based operating system (Ubuntu, Debian, Fedora, Arch, etc.)
- `sudo` privileges
- Basic command-line knowledge

## Installation & Usage

### 1. Make the script executable

```bash
chmod +x setup-hid-permissions.sh
```

### 2. Run the script

```bash
./setup-hid-permissions.sh
```

### 3. Select your device(s)

The script will display all detected HID devices:

```
[1] 19f5:fb2b [G-COME M68 HE] → /dev/hidraw0
[2] 19f5:fb2b [G-COME M68 HE] → /dev/hidraw1
[3] 19f5:fb2b [G-COME M68 HE] → /dev/hidraw2
```

**Select devices by:**
- Single number: `1`
- Multiple devices: `1,3,5`
- Range: `1-3`

### 4. **IMPORTANT: Reboot your system**

After the script completes successfully, **you must reboot your computer** for all changes to take full effect:

```bash
sudo reboot
```

> **Why reboot?** While the script triggers udev events and may apply some changes immediately, a full reboot ensures:
> - Group membership is properly recognized by all processes
> - All system services reload with new permissions
> - Device enumeration happens cleanly

### 5. Verify (after reboot)

Check device permissions:

```bash
ls -l /dev/hidraw*
```

You should see `plugdev` as the group with read/write permissions (`crw-rw----`).

## Troubleshooting

### Device still shows "Permission denied"
- **Verify reboot**: Make sure you rebooted after running the script
- **Unplug/replug device**: Disconnect and reconnect your keyboard
- **Check group membership**: Run `groups` and verify `plugdev` is listed
- **Re-run script**: If you added new devices, run the script again

### Script can't find devices
- Ensure devices are plugged in and recognized: `ls /dev/hidraw*`
- Check kernel modules are loaded: `lsmod | grep hidraw`
- Try reconnecting the device to a different USB port

### Need to add more devices later?
Simply run the script again—it will backup existing rules and create new ones.

## Technical Details

- **Rules file**: `/etc/udev/rules.d/99-hid-permissions.rules`
- **Group**: `plugdev`
- **Permissions**: `0660` (read/write for owner and group)
- **Backups**: Automatic timestamped backups of existing rules

## License

This script is provided as-is for configuring HID device permissions on Linux systems.
