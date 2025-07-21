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
    
    log_success "Repository $(basename "$repo_path") reset successfully"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dependencies
install_dependencies() {
    log_info "Checking and installing dependencies..."
    
    local packages=(
        "make"
        "mingw-w64-x86_64-gcc"
        "mingw-w64-x86_64-cmake"
        "mingw-w64-x86_64-yasm"
        "mingw-w64-x86_64-diffutils"
        "mingw-w64-x86_64-SDL2"
        "mingw-w64-x86_64-binutils"
        "mingw-w64-x86_64-pkg-config"
        "git"
        "patch"
    )
    
    local missing_packages=()
    
    for package in "${packages[@]}"; do
        if ! pacman -Qi "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_info "Installing missing packages: ${missing_packages[*]}"
        pacman -S --needed --noconfirm "${missing_packages[@]}" || {
            log_error "Failed to install dependencies. Please run as administrator or install manually."
            exit 1
        }
    else
        log_success "All dependencies are already installed."
    fi
}

# Main build process
main() {
    log_info "Starting JPEG XS FFmpeg build process..."
    
    # Set up directories
    export PATCHES_DIR="$PWD/patches"
    export INSTALL_DIR="$PWD/install-dir"
    export JXS_DIR="$PWD/SVT-JPEG-XS"
    
    log_info "Build directories:"
    log_info "  - Patches: $PATCHES_DIR"
    log_info "  - Install: $INSTALL_DIR"
    log_info "  - SVT-JPEG-XS: $JXS_DIR"
    
    # Check if we're in MSYS2 environment
    if [[ "$OSTYPE" != "msys" ]]; then
        log_warning "This script is designed for MSYS2 environment on Windows"
    fi
    
    # Install dependencies
    install_dependencies
    
    # Set up MinGW-w64 toolchain paths
    log_info "Setting up MinGW-w64 toolchain paths..."
    export PATH="/mingw64/bin:$PATH"
    export PKG_CONFIG_PATH="/mingw64/lib/pkgconfig:$PKG_CONFIG_PATH"
    export LDFLAGS="-L/mingw64/lib $LDFLAGS"
    export CPPFLAGS="-I/mingw64/include $CPPFLAGS"
    
    # Check and setup cross-compilation tools
    log_info "Checking MinGW-w64 toolchain..."
    
    # Create symbolic links for cross-compilation tools if they don't exist
    local mingw_bin="/mingw64/bin"
    local tools=("gcc" "g++" "ar" "ranlib" "strip" "nm" "objdump" "windres")
    
    for tool in "${tools[@]}"; do
        local cross_tool="x86_64-w64-mingw32-$tool"
        local native_tool="$tool"
        
        if [ ! -f "$mingw_bin/$cross_tool" ] && [ -f "$mingw_bin/$native_tool" ]; then
            log_info "Creating symlink: $cross_tool -> $native_tool"
            ln -sf "$native_tool" "$mingw_bin/$cross_tool" 2>/dev/null || {
                log_warning "Failed to create symlink for $cross_tool"
            }
        fi
    done
    
    # Verify toolchain availability
    if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
        log_success "MinGW-w64 cross-compilation toolchain ready"
    elif command -v gcc >/dev/null 2>&1; then
        log_warning "Cross-compilation tools not available, using native tools"
    else
        log_error "No suitable compiler found"
        exit 1
    fi
    
    # Create install directory
    if [ ! -d "$INSTALL_DIR" ]; then
        log_info "Creating install directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR" || {
            log_error "Failed to create install directory"
            exit 1
        }
    fi
    
    # ===== STEP 1: Clone and initialize all repositories first =====
    log_info "Step 1: Setting up repositories..."
    
    # Clone SVT-JPEG-XS if not exists
    if [ ! -d "$JXS_DIR" ]; then
        log_info "Cloning SVT-JPEG-XS repository..."
        git clone https://github.com/OpenVisualCloud/SVT-JPEG-XS.git || {
            log_error "Failed to clone SVT-JPEG-XS repository"
            exit 1
        }
        log_success "SVT-JPEG-XS cloned successfully"
    else
        log_info "SVT-JPEG-XS directory already exists"
    fi
    
    # Clone FFmpeg if not exists
    if [ ! -d "$PWD/ffmpeg" ]; then
        log_info "Cloning FFmpeg repository..."
        git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg || {
            log_error "Failed to clone FFmpeg repository"
            exit 1
        }
        log_success "FFmpeg cloned successfully"
    else
        log_info "FFmpeg directory already exists"
    fi
    
    # Initialize FFmpeg repository state
    log_info "Initializing FFmpeg repository..."
    local original_dir="$PWD"
    cd ffmpeg || {
        log_error "Failed to enter ffmpeg directory"
        exit 1
    }
    
    # Reset repository to clean state
    reset_git_repository "$original_dir/ffmpeg" "$original_dir"
    # Checkout specific version
    log_info "Checking out FFmpeg release/7.1..."
    git checkout release/7.1 || {
        log_error "Failed to checkout FFmpeg release/7.1"
        cd "$original_dir"
        exit 1
    }

    cd "$original_dir"
    cd "$JXS_DIR" || {
        log_error "Failed to enter SVT-JPEG-XS directory"
        exit 1
    }
    reset_git_repository "$JXS_DIR" "$original_dir"
    cd "$original_dir"
    
    log_success "All repositories initialized successfully"
    
    # ===== STEP 2: Build SVT-JPEG-XS library =====
    log_info "Step 2: Building SVT-JPEG-XS library..."
    build_svt_with_cmake
    
    # Set up environment variables
    export LD_LIBRARY_PATH="$INSTALL_DIR/lib:${LD_LIBRARY_PATH}"
    export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig:${PKG_CONFIG_PATH}"
    
    # ===== STEP 3: Build FFmpeg with JPEG XS support =====
    log_info "Step 3: Building FFmpeg with JPEG XS support..."
    
    cd ffmpeg || {
        log_error "Failed to enter ffmpeg directory"
        exit 1
    }

    # Copy plugin files
    log_info "Copying SVT-JPEG-XS plugin files..."
    if [ -d "$JXS_DIR/ffmpeg-plugin" ]; then
        cp "$JXS_DIR/ffmpeg-plugin/libsvtjpegxs"* "libavcodec/" -f || {
            log_error "Failed to copy SVT-JPEG-XS plugin files"
            cd "$original_dir"
            exit 1
        }
        log_success "Plugin files copied successfully"
    else
        log_error "SVT-JPEG-XS plugin directory not found"
        cd "$original_dir"
        exit 1
    fi
    
    # Apply patches
    log_info "Applying patches..."
    if [ -d "$JXS_DIR/ffmpeg-plugin/7.1" ] && [ "$(ls -A "$JXS_DIR/ffmpeg-plugin/7.1"/*.patch 2>/dev/null)" ]; then
        git am --whitespace=fix "$JXS_DIR/ffmpeg-plugin/7.1"/*.patch || {
            log_error "Failed to apply SVT-JPEG-XS patches"
            cd "$original_dir"
            exit 1
        }
        log_success "SVT-JPEG-XS patches applied"
    fi
    
    if [ -d "$PATCHES_DIR" ] && [ "$(ls -A "$PATCHES_DIR"/*.patch 2>/dev/null)" ]; then
        git am --whitespace=fix "$PATCHES_DIR"/*.patch || {
            log_error "Failed to apply mpeg-ts patches"
            cd "$original_dir"
            exit 1
        }
        log_success "mpeg-ts patches applied"
    fi
    
    # Configure FFmpeg
    log_info "Configuring FFmpeg..."
    
    # Determine compilation settings
    CONFIG_ARGS=(
        "--enable-libsvtjpegxs"
        "--prefix=$INSTALL_DIR"
        "--enable-static"
        "--disable-shared"
        "--enable-gpl"
        "--enable-version3"
        "--arch=x86_64"
        "--target-os=mingw32"
        "--pkg-config=pkg-config"
        "--extra-cflags=-I$INSTALL_DIR/include"
        "--extra-ldflags=-L$INSTALL_DIR/lib"
    )
    
    # Add cross-prefix only if cross-compilation tools are available
    if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 && command -v x86_64-w64-mingw32-nm >/dev/null 2>&1; then
        CONFIG_ARGS+=("--cross-prefix=x86_64-w64-mingw32-")
        log_info "Using cross-compilation with x86_64-w64-mingw32- prefix"
    else
        log_info "Using native compilation (no cross-prefix)"
        # For native compilation, we might need to adjust some settings
        CONFIG_ARGS+=("--cc=gcc")
        CONFIG_ARGS+=("--cxx=g++")
    fi
    
    log_info "FFmpeg configure arguments: ${CONFIG_ARGS[*]}"
    
    ./configure "${CONFIG_ARGS[@]}" || {
        log_error "FFmpeg configuration failed"
        log_info "Trying fallback configuration without cross-compilation..."
        
        # Fallback configuration without cross-compilation
        ./configure \
            --enable-libsvtjpegxs \
            --prefix="$INSTALL_DIR" \
            --enable-static \
            --disable-shared \
            --enable-gpl \
            --enable-version3 \
            --pkg-config=pkg-config \
            --extra-cflags="-I$INSTALL_DIR/include" \
            --extra-ldflags="-L$INSTALL_DIR/lib" || {
            log_error "Fallback FFmpeg configuration also failed"
            cd "$original_dir"
            exit 1
        }
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
    log_info "FFmpeg with JPEG XS support installed to: $INSTALL_DIR"
    log_info "Add $INSTALL_DIR/bin to your PATH to use the built FFmpeg"
}

# Function to build SVT-JPEG-XS with CMake
build_svt_with_cmake() {
    log_info "Building SVT-JPEG-XS with CMake..."
    
    # Save current directory for safe return
    local original_dir="$PWD"
    
    cd "$JXS_DIR" || {
        log_error "Failed to enter SVT-JPEG-XS directory"
        exit 1
    }

    cmake -S . -B svtjpegxs-build -DBUILD_APPS=off -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" || {
        log_error "CMake configuration failed"
        cd "$original_dir"
        exit 1
    }

    cmake --build svtjpegxs-build -j10 --config Release --target install || {
        log_error "SVT-JPEG-XS build failed"
        cd "$original_dir"
        exit 1
    }
    
    # Return to original directory
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
