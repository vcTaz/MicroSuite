#!/bin/bash
# ==============================================================================
# Container Runtime Detection
# Detects whether Docker or Podman is available and configured
# ==============================================================================

# Detect available runtime
detect_runtime() {
    # Check for user preference via environment variable
    if [ -n "${CONTAINER_RUNTIME:-}" ]; then
        if [ "$CONTAINER_RUNTIME" = "podman" ] && command -v podman &>/dev/null; then
            echo "podman"
            return 0
        elif [ "$CONTAINER_RUNTIME" = "docker" ] && command -v docker &>/dev/null; then
            echo "docker"
            return 0
        fi
    fi

    # Auto-detect: prefer podman if available (better CRIU support)
    if command -v podman &>/dev/null; then
        # Verify podman is functional
        if podman info &>/dev/null; then
            echo "podman"
            return 0
        fi
    fi

    # Fall back to docker
    if command -v docker &>/dev/null; then
        if docker info &>/dev/null; then
            echo "docker"
            return 0
        fi
    fi

    echo "none"
    return 1
}

# Check if runtime supports checkpointing
check_checkpoint_support() {
    local runtime="$1"

    case "$runtime" in
        podman)
            # Podman has native checkpoint support
            if podman container checkpoint --help &>/dev/null; then
                echo "supported"
                return 0
            fi
            ;;
        docker)
            # Docker requires experimental mode
            if docker info 2>/dev/null | grep -q "Experimental: true"; then
                echo "supported"
                return 0
            else
                echo "requires_experimental"
                return 1
            fi
            ;;
    esac

    echo "unsupported"
    return 1
}

# Get compose command for runtime
get_compose_command() {
    local runtime="$1"

    case "$runtime" in
        podman)
            if command -v podman-compose &>/dev/null; then
                echo "podman-compose"
            else
                echo "podman compose"
            fi
            ;;
        docker)
            if command -v docker-compose &>/dev/null; then
                echo "docker-compose"
            else
                echo "docker compose"
            fi
            ;;
    esac
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
    fi
fi
