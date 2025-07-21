#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }

# Ubuntu 환경 확인
check_ubuntu_env() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "ubuntu" ]; then
            log_warning "이 스크립트는 Ubuntu 환경에서 실행되어야 합니다."
        fi
    else
        log_warning "/etc/os-release 파일을 찾을 수 없습니다. Ubuntu 환경 확인 불가."
    fi
}

main() {
    check_ubuntu_env

    export LD_LIBRARY_PATH="$PWD/../install-dir/lib:${LD_LIBRARY_PATH:-}"
    log_info "LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"

    local FFMPEG_BIN="$PWD/../install-dir/bin/ffmpeg"
    if [ ! -x "$FFMPEG_BIN" ]; then
        log_error "FFmpeg 실행 파일을 찾을 수 없습니다: $FFMPEG_BIN"
    fi

    log_info "Executing: $FFMPEG_BIN $*"
    exec "$FFMPEG_BIN" "$@"
}

main "$@"

