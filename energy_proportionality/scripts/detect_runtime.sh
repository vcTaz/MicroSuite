#!/bin/bash
# ==============================================================================
# Container Runtime Detection
# Podman-only runtime support
# ==============================================================================

# Detect Podman runtime
detect_runtime() {
    if command -v podman &>/dev/null; then
        # Verify podman is functional
        if podman info &>/dev/null; then
            echo "podman"
            return 0
        fi
    fi

    echo "none"
    return 1
}

# Check if runtime supports checkpointing
check_checkpoint_support() {
    local runtime="$1"

    if [ "$runtime" = "podman" ]; then
        # Podman has native checkpoint support
        if podman container checkpoint --help &>/dev/null; then
            echo "supported"
            return 0
        fi
    fi

    echo "unsupported"
    return 1
}

# Get compose command for runtime
get_compose_command() {
    local runtime="$1"

    if [ "$runtime" = "podman" ]; then
        if command -v podman-compose &>/dev/null; then
            echo "podman-compose"
        else
            echo "ERROR: podman-compose not found. Please install it with: pip install podman-compose" >&2
            return 1
        fi
    fi
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    RUNTIME=$(detect_runtime)
    echo "Detected runtime: $RUNTIME"

    if [ "$RUNTIME" != "none" ]; then
        CHECKPOINT=$(check_checkpoint_support "$RUNTIME")
        echo "Checkpoint support: $CHECKPOINT"

        COMPOSE=$(get_compose_command "$RUNTIME")
        echo "Compose command: $COMPOSE"
    else
        echo "ERROR: Podman is not installed or not functional"
        exit 1
    fi
fi
