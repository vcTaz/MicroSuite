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
        # First check if it's in PATH
        if command -v podman-compose &>/dev/null; then
            echo "podman-compose"
            return 0
        fi

        # Common locations for pip-installed podman-compose
        local common_paths=(
            "/usr/local/bin/podman-compose"
            "/usr/bin/podman-compose"
        )

        # Check SUDO_USER's home directory (when running with sudo)
        if [ -n "$SUDO_USER" ]; then
            local sudo_user_home
            sudo_user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            if [ -n "$sudo_user_home" ]; then
                common_paths+=("$sudo_user_home/.local/bin/podman-compose")
            fi
        fi

        # Also check current user's home
        if [ -n "$HOME" ]; then
            common_paths+=("$HOME/.local/bin/podman-compose")
        fi

        # Search through common paths
        for path in "${common_paths[@]}"; do
            if [ -x "$path" ]; then
                echo "$path"
                return 0
            fi
        done

        echo "ERROR: podman-compose not found. Please install it with: pip install podman-compose" >&2
        return 1
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
