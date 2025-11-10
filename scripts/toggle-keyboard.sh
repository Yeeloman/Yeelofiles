#!/bin/bash
# toggle-keyboard.sh
# Disables internal keyboard if external is connected, otherwise enables it.

INTERNAL_KEYBOARD="AT Translated Set 2 keyboard"
EXTERNAL_KEYBOARD=$(xinput list | grep -E "Sino Wealth|Compx")

if [ -n "$EXTERNAL_KEYBOARD" ]; then
    echo "External keyboard detected, disabling internal keyboard..."
    xinput disable "$(xinput list --id-only "$INTERNAL_KEYBOARD")"
else
    echo "No external keyboard found, enabling internal keyboard..."
    xinput enable "$(xinput list --id-only "$INTERNAL_KEYBOARD")"
fi
