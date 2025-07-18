# FFmpeg with SVT-JPEG-XS Build Script

This script automates the process of building a static FFmpeg executable with integrated SVT-JPEG-XS support on a Windows environment using MSYS2/MinGW64. It handles dependency installation, repository cloning, patching, and compilation.

## Features

- **Automated Dependency Installation**: Automatically checks for and installs required packages using `pacman`.
- **Robust Build Process**: The script is designed to be resilient, with error handling and logging for each step.
- **Idempotent Repository Setup**: Resets the `FFmpeg` and `SVT-JPEG-XS` repositories to a clean state before each build, ensuring consistency.
- **Custom Patch Support**: Automatically applies custom user patches located in the `patches/` directory.
- **Static Build**: Produces a self-contained static build of FFmpeg, which is easier to distribute and use.
- **Toolchain Correction**: Automatically creates symbolic links for the MinGW toolchain to ensure compatibility with FFmpeg's configure script.

## Prerequisites

- **Windows 10/11 (64-bit)**
- **MSYS2**: The script must be run from an MSYS2 MinGW 64-bit shell (`mingw64.exe`).

The script will attempt to install the following required packages via `pacman`:
- `make`
- `mingw-w64-x86_64-gcc`
- `mingw-w64-x86_64-cmake`
- `mingw-w64-x86_64-yasm`
- `mingw-w64-x86_64-diffutils`
- `mingw-w64-x86_64-SDL2`
- `mingw-w64-x86_64-binutils`
- `mingw-w64-x86_64-pkg-config`
- `git`
- `patch`

## Usage

1.  Clone this repository.
2.  Open an MSYS2 MinGW 64-bit shell.
3.  Navigate to the repository directory.
4.  Run the build script:
    ```sh
    ./build_ffmpeg.sh
    ```

The script will perform all necessary steps. The final build will be located in the `install-dir` directory.

## Build Process Overview

The script executes the following steps:

1.  **Setup**: Creates an `install-dir` for the final build and an `SVT-JPEG-XS` directory for the codec source.
2.  **Dependency Check**: Installs any missing dependencies.
3.  **Repository Initialization**:
    - Clones the `SVT-JPEG-XS` and `FFmpeg` (release/7.1) repositories if they don't exist.
    - Fetches the latest changes and performs a hard reset to ensure a clean state.
4.  **Build SVT-JPEG-XS**: Compiles `SVT-JPEG-XS` as a static library and installs it into `install-dir`.
5.  **Build FFmpeg**:
    - Copies the necessary plugin files from `SVT-JPEG-XS` to the FFmpeg source tree.
    - Applies the official SVT-JPEG-XS patches for FFmpeg 7.1.
    - Applies any custom patches found in the `./patches` directory.
    - Configures FFmpeg to enable `libsvtjpegxs`, static linking, and points to the `install-dir` for dependencies.
    - Compiles and installs FFmpeg into `install-dir`.

## Output

After a successful build, the `install-dir` will contain the compiled libraries and the `ffmpeg.exe`, `ffplay.exe`, and `ffprobe.exe` executables.

To use the new build from any terminal, add the `install-dir/bin` directory to your system's PATH environment variable.

## Customization

To add your own patches for FFmpeg, simply place them in the `patches/` directory. The script will automatically apply any file ending in `.patch` during the FFmpeg build step, after the official SVT-JPEG-XS patches have been applied.
