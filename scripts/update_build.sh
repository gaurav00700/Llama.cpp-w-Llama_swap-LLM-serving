#############################################
# 🧠 Llama.cpp Auto-Build & Deploy Script
#
# This script checks the remote llama.cpp repo
# for updates and builds only when needed.
#
# 🔁 Workflow:
# - Triggered by systemd timer (on boot + once daily)
# - Also handles missed runs (e.g., system sleep)
# - Fetches latest commits from origin/<branch>
# - If changes OR missed schedule:
#     → pulls latest code
#     → performs incremental CMake build (CUDA + ccache)
#     → locates llama-server binary
#     → updates symlink (build_prod → build/bin)
#     → computes binary checksum
#     → restarts Docker container ONLY if binary changed
#
# ⚡ Features:
# - Incremental builds (fast)
# - ccache acceleration
# - Sleep-safe (no missed runs)
# - Zero unnecessary container restarts
# - GPU-enabled builds
# - Timer-driven execution (no loops)
#
# ⚠️ Notes:
# - Do NOT run as root
# - Requires CUDA, Docker, ccache
#############################################

#!/bin/bash
set -e


# === 🔒 SAFETY === Prevent root execution

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do NOT run this script as root"
    exit 1
fi


# === 🌍 ENVIRONMENT === CUDA setup
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# === 📁 PATH CONFIG ===
SOURCE_DIR="$HOME/.llm/llama.cpp"
BUILD_DIR="$HOME/.llm/llama.cpp/build"
BUILD_PROD="$HOME/.llm/llama.cpp/build_prod"

# === ⚙️ CONFIG ===
BRANCH="master"
CUDA_ARCHITECTURE="89"
CONTAINER_NAME="llswap"

# === 🧠 STATE FILES ===
HASH_FILE="$HOME/.llm/llama_cpp_last_hash"
BIN_HASH_FILE="$HOME/.llm/llama_binary_hash"
LAST_RUN_FILE="$HOME/.llm/last_successful_run"

mkdir -p "$(dirname "$HASH_FILE")"

# === 🧾 LOGGING ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# === 🔒 SAFETY === Fix ccache permissions
mkdir -p "$HOME/.cache/ccache"
chown -R "$(whoami):$(whoami)" "$HOME/.cache/ccache" 2>/dev/null || true

# === ⏱️ MISSED RUN DETECTION ===
# Ensures script runs if system was asleep/off

should_run_now() {
    CURRENT_TIME=$(date +%s)
    MAX_DELAY=90000   # ~25 hours

    if [ ! -f "$LAST_RUN_FILE" ]; then
        log "First run → triggering build"
        return 0
    fi

    LAST_RUN=$(cat "$LAST_RUN_FILE")
    DIFF=$((CURRENT_TIME - LAST_RUN))

    if [ "$DIFF" -ge "$MAX_DELAY" ]; then
        log "Missed scheduled run → triggering build"
        return 0
    fi

    return 1
}

# === 🔍 CHANGE DETECTION ===
has_changes() {
    cd "$SOURCE_DIR" || exit 1

    git fetch origin >/dev/null 2>&1

    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse origin/$BRANCH)

    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
        log "Remote changes detected"
        return 0
    fi

    if [ ! -f "$HASH_FILE" ]; then
        return 0
    fi

    return 1
}

# === 🔍 FIND BINARY ===
detect_bin_dir() {
    if [ -d "$BUILD_DIR/bin" ]; then
        echo "$BUILD_DIR/bin"
        return
    fi

    BIN_PATH=$(find "$BUILD_DIR" -type f -name "llama-server" 2>/dev/null | head -n 1)
    [ -n "$BIN_PATH" ] && dirname "$BIN_PATH"
}

# === 🔨 BUILD + DEPLOY ===
build_binaries() {
    cd "$SOURCE_DIR" || return 1

    log "Updating source..."
    git reset --hard origin/$BRANCH

    CURRENT_HASH=$(git rev-parse HEAD)

    log "Starting incremental build..."

    mkdir -p "$BUILD_DIR"

    cmake \
      -S "$SOURCE_DIR" \
      -B "$BUILD_DIR" \
      -DGGML_CUDA=ON \
      -DGGML_CCACHE=ON \
      -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURE" \
      -DCMAKE_BUILD_RPATH='$ORIGIN' \
      -DCMAKE_INSTALL_RPATH='$ORIGIN'

    if ! cmake --build "$BUILD_DIR" --config Release -j $(nproc); then
        log "Build FAILED"
        return 1
    fi

    BIN_DIR=$(detect_bin_dir)

    if [ -z "$BIN_DIR" ]; then
        log "ERROR: llama-server not found"
        return 1
    fi

    NEW_BIN_HASH=$(sha256sum "$BIN_DIR/llama-server" | awk '{print $1}')
    OLD_BIN_HASH=$(cat "$BIN_HASH_FILE" 2>/dev/null || echo "")

    log "Deploying binaries..."

    rm -rf "$BUILD_PROD"
    ln -s "$BIN_DIR" "$BUILD_PROD"

    echo "$CURRENT_HASH" > "$HASH_FILE"
    
    # === 🔄 CONDITIONAL RESTART ===
    if [ "$NEW_BIN_HASH" != "$OLD_BIN_HASH" ]; then
        log "Binary changed → restarting container"

        echo "$NEW_BIN_HASH" > "$BIN_HASH_FILE"

        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            docker restart "$CONTAINER_NAME"
			log "Successfully updated the container: $CONTAINER_NAME"
        else
            log "Container $CONTAINER_NAME not running → skipping restart"
        fi
    else
        log "Binary unchanged → skipping restart"
    fi

    log "Deployment complete"
}

# === 🚀 ENTRYPOINT ===
if should_run_now || has_changes; then
    build_binaries
    date +%s > "$LAST_RUN_FILE"
else
    log "No changes detected and schedule not missed"
fi