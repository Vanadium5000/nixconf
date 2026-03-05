#!/usr/bin/env bash

PID_FILE="/tmp/dictation-overlay.pid"

show() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Overlay already running"
        exit 0
    fi
    
    # Run the quickshell binary, storing the PID
    dictation-overlay &
    echo $! > "$PID_FILE"
}

hide() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
        fi
        rm -f "$PID_FILE"
    fi
    
    # Fallback to killall just in case
    killall dictation-overlay 2>/dev/null || true
}

toggle() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        hide
    else
        show
    fi
}

case "$1" in
    show) show ;;
    hide) hide ;;
    toggle|*) toggle ;;
esac
