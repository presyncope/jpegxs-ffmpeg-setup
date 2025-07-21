#!/bin/bash

# Exit on any error
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to reset git repository to clean state
reset_git_repository() {
    local repo_path="$1"
    local original_dir="$2"
    
    if [ -z "$repo_path" ] || [ -z "$original_dir" ]; then
        log_error "reset_git_repository requires repo_path and original_dir parameters"
        return 1
    fi

    cd "$repo_path" || {
        log_error "Failed to change directory to $repo_path"
        return 1
    }
    
    # Check for ongoing git operations and abort them
    if [ -d ".git/rebase-apply" ] || [ -d ".git/rebase-merge" ]; then
        log_warning "Ongoing git operation detected. Aborting..."
        git am --abort 2>/dev/null || true
        git rebase --abort 2>/dev/null || true
        git merge --abort 2>/dev/null || true
        log_success "Git operations aborted"
    fi
    
    # Determine target branch based on repository
    local target_branch=""
    local repo_name=$(basename "$repo_path")
    
    if [[ "$repo_name" == "ffmpeg" ]]; then
        target_branch="origin/release/7.1"
        log_info "Resetting FFmpeg repository to $target_branch"
    elif [[ "$repo_name" == "SVT-JPEG-XS" ]]; then
        target_branch="origin/main"
        log_info "Resetting SVT-JPEG-XS repository to $target_branch"
    else
        log_warning "Unknown repository type: $repo_name. Using generic reset."
    fi
    
    # Fetch latest changes from remote
    log_info "Fetching latest changes from remote..."
    git fetch --all 2>/dev/null || {
        log_warning "Failed to fetch remote changes. Continuing with local reset."
    }
    
    # Reset to specific remote branch or just clean locally
    if [ -n "$target_branch" ]; then
        log_warning "Resetting $(basename "$repo_path") repository to $target_branch..."
        git reset --hard "$target_branch" 2>/dev/null || {
            log_warning "Failed to reset to $target_branch. Trying local reset..."
            git reset --hard HEAD~10 2>/dev/null || git reset --hard HEAD
        }
    else
        # Fallback: reset any uncommitted changes
        if [ -n "$(git status --porcelain)" ]; then
            log_warning "Uncommitted changes detected in $(basename "$repo_path") repository. Resetting..."
            git reset --hard || {
                log_error "Failed to reset repository"
                cd "$original_dir"
                exit 1
            }
        fi
    fi
    
    # Clean untracked files and directories
    git clean -fd || {
        log_error "Failed to clean repository"
        cd "$original_dir"
        exit 1
    }
    
    cd "$original_dir"
    log_success "Repository $(basename "$repo_path") reset successfully"
}

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

ensure_dir() {
    local target_dir="$1"
    if [ ! -d "$target_dir" ]; then
        log_info "Creating directory: $target_dir"
        mkdir -p "$target_dir" || {
            log_error "Failed to create directory: $target_dir"
            exit 1
        }
    fi
}

ensure_clone_repo() {
    local repo_url="$1"
    local dest_dir="$2"
    local repo_name
    repo_name=$(basename "$dest_dir")

    if [ ! -d "$dest_dir" ]; then
        log_info "Cloning ${repo_name} into ${dest_dir}..."
        git clone "$repo_url" "$dest_dir" || {
            log_error "Failed to clone ${repo_name}"
            exit 1
        }
        log_success "${repo_name} cloned successfully"
    else
        log_info "${repo_name} directory already exists"
    fi
}

init_third_party_repos() {
    local original_dir="$PWD"
    ensure_clone_repo "https://github.com/OpenVisualCloud/SVT-JPEG-XS.git" "$JXS_DIR"
    ensure_clone_repo "https://git.ffmpeg.org/ffmpeg.git" "$FFMPEG_DIR"

    reset_git_repository "$FFMPEG_DIR" "$original_dir"
    reset_git_repository "$JXS_DIR" "$original_dir"

    log_info "Checking out FFmpeg release/7.1..."
    cd "$FFMPEG_DIR"
    git checkout release/7.1 || {
        log_error "Failed to checkout FFmpeg release/7.1"
        cd "$original_dir"
        exit 1
    }

    cd $original_dir
    log_success "All repositories initialized successfully"
}

# Main build process
main() {
    log_info "Starting JPEG XS FFmpeg build process..."
    
    # Set up directories
    export PATCHES_DIR="$PWD/patches"
    export INSTALL_DIR="$PWD/install-dir"
    export JXS_DIR="$PWD/svtjpegxs"
    export FFMPEG_DIR="$PWD/ffmpeg"
    
    log_info "Build directories:"
    log_info "  - Patches: $PATCHES_DIR"
    log_info "  - Install: $INSTALL_DIR"
    log_info "  - SVT-JPEG-XS: $JXS_DIR"
    
    check_ubuntu_env
    
    ensure_dir "$INSTALL_DIR"
    
    init_third_party_repos
    
    build_svtjpegxs
    
    export LD_LIBRARY_PATH="$INSTALL_DIR/lib:${LD_LIBRARY_PATH}"
    export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig:${PKG_CONFIG_PATH}"
    
    local original_dir="$PWD"
    cd "$FFMPEG_DIR"

    # Copy plugin files
    log_info "Copying svtjpegxs plugin files..."
    if [ -d "$JXS_DIR/ffmpeg-plugin" ]; then
        cp "$JXS_DIR/ffmpeg-plugin/libsvtjpegxs"* "libavcodec/" -f || {
            log_error "Failed to copy svtjpegxs plugin files"
            cd "$original_dir"
            exit 1
        }
        log_success "Plugin files copied successfully"
    else
        log_error "svtjpegxs plugin directory not found"
        cd "$original_dir"
        exit 1
    fi
    
    # Apply patches
    log_info "Applying patches..."
    if [ -d "$JXS_DIR/ffmpeg-plugin/7.1" ] && [ "$(ls -A "$JXS_DIR/ffmpeg-plugin/7.1"/*.patch 2>/dev/null)" ]; then
        git am --whitespace=fix "$JXS_DIR/ffmpeg-plugin/7.1"/*.patch || {
            log_error "Failed to apply svtjpegxs patches"
            cd "$original_dir"
            exit 1
        }
        log_success "svtjpegxs patches applied"
    fi
    
    if [ -d "$PATCHES_DIR" ] && [ "$(ls -A "$PATCHES_DIR"/*.patch 2>/dev/null)" ]; then
        git am --whitespace=fix "$PATCHES_DIR"/*.patch || {
            log_error "Failed to apply mpeg-ts patches"
            cd "$original_dir"
            exit 1
        }
        log_success "mpeg-ts patches applied"
    fi
    
    log_info "Configuring FFmpeg..."
    
    # Determine compilation settings
    CONFIG_ARGS=(
        "--enable-libsvtjpegxs"
        "--prefix=$INSTALL_DIR"
        "--enable-shared"
        "--enable-gpl"
        "--enable-libx265"
    )
    
    log_info "FFmpeg configure arguments: ${CONFIG_ARGS[*]}"
    
    ./configure "${CONFIG_ARGS[@]}" || {
        log_error "FFmpeg configuration failed"
        cd "$original_dir"
        exit 1
    }
    
    log_success "FFmpeg configured successfully"
    
    # Build FFmpeg
    log_info "Building FFmpeg (this may take a while)..."
    make -j$(nproc) || {
        log_error "FFmpeg build failed"
        cd "$original_dir"
        exit 1
    }
    
    log_success "FFmpeg built successfully"
    
    # Install FFmpeg
    log_info "Installing FFmpeg..."
    make install || {
        log_error "FFmpeg installation failed"
        cd "$original_dir"
        exit 1
    }
    
    # Return to original directory
    cd "$original_dir"
    
    log_success "Build completed successfully!"
    log_info "FFmpeg with svtjpegxs support installed to: $INSTALL_DIR"
    log_info "Add $INSTALL_DIR/bin to your PATH to use the built FFmpeg"
}

build_svtjpegxs() {
    log_info "Building svtjpegxs with cmake..."
    
    local original_dir="$PWD"
    
    cd "$JXS_DIR/Build/linux"
    ./build.sh install --prefix $INSTALL_DIR || {
        log_error "SVT-JPEG-XS build script failed"
        cd "$original_dir"
        exit 1
    }
    
    cd "$original_dir"
    log_success "SVT-JPEG-XS built and installed successfully"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    # Add cleanup commands here if needed
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
