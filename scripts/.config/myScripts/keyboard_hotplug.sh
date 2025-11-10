#!/usr/bin/env bash
# keyboard_hotplug.sh
# Monitors for external keyboard plug/unplug and toggles internal keyboard + layout.

INTERNAL_KEYBOARD="AT Translated Set 2 keyboard"
LAYOUT_INTERNAL="fr"      # Laptop default layout
LAYOUT_EXTERNAL="us"      # Layout when external keyboard is present

check_external() {
    # Check for USB keyboards connected (ignore internal)
    external=$(xinput list | grep -i "keyboard" | grep -v "$INTERNAL_KEYBOARD")
    if [[ -n "$external" ]]; then
        return 0
    else
        return 1
    fi
}

toggle_keyboard() {
    if check_external; then
        # External keyboard detected
        xinput disable "$INTERNAL_KEYBOARD"
        setxkbmap "$LAYOUT_EXTERNAL"
        echo "$(date): External keyboard detected — internal disabled, layout $LAYOUT_EXTERNAL" >> /tmp/keyboard.log
    else
        # No external keyboard
        xinput enable "$INTERNAL_KEYBOARD"
        setxkbmap "$LAYOUT_INTERNAL"
        echo "$(date): No external keyboard — internal enabled, layout $LAYOUT_INTERNAL" >> /tmp/keyboard.log
    fi
}

# Initial toggle on script start
toggle_keyboard

# Watch for USB events (hotplug)
udevadm monitor --subsystem-match=input --property | while read -r line; do
    # Small delay to allow device to initialize
    sleep 1
    toggle_keyboard
done
