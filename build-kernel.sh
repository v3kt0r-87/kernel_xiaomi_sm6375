#!/bin/bash
#set -e  

# Clean previous build outputs
KERNEL_NAME=$(tr -d '~ ' < localversion 2>/dev/null)
KERNEL_NAME="${KERNEL_NAME:-THANGAN}"
rm -rf out/ "${KERNEL_NAME}-"*

# AOSP Clang
CLANG_BRANCH="mirror-goog-main-llvm-toolchain-source"
CLANG_VERSION="clang-r614150"
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${CLANG_BRANCH}/${CLANG_VERSION}.tgz"
ARCHIVE_NAME="aosp-clang.tar.gz"

# Set the working directory and paths
DIR=$(readlink -f .)
TC_DIR="${DIR}/clang"
OUT_DIR="${DIR}/out"
ZIMAGE_DIR="${OUT_DIR}/arch/arm64/boot"
KERNEL_DEFCONFIG=veux_defconfig

# Set environment variables for the build
export PATH="${TC_DIR}/bin:${TC_DIR}/gcc/bin:${TC_DIR}/gcc32/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64

LINKER="ld.lld"
BUILD_START=$(date +"%s")
TIME="$(date "+%Y%m%d-%H%M%S")"

# Colors for terminal output
blue='\033[0;34m'
nocol='\033[0m'

# Check or Download AOSP Clang if it doesn't exist
if [ ! -d "$TC_DIR" ]; then
    echo "No clang compiler found ... Downloading AOSP Clang"

    # Download Clang archive
    if ! wget "$CLANG_URL" -O "$DIR/$ARCHIVE_NAME"; then
        echo "Failed to download. Exiting..."
        exit 1
    fi

    # Create clang directory and extract archive
    mkdir -p "$TC_DIR"

    if ! tar -xvf "$DIR/$ARCHIVE_NAME" -C "$TC_DIR"; then
        echo "Failed to extract Clang. Exiting..."
        exit 1
    fi

    # Clean up the archive file
    rm -rf "$DIR/$ARCHIVE_NAME"

    # Clone GCC for aarch64 (64-bit) and arm (32-bit)
    git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 "$TC_DIR/gcc" || { echo "Failed to clone GCC for aarch64. Exiting..."; exit 1; }
    git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git --depth=1 "$TC_DIR/gcc32" || { echo "Failed to clone GCC for arm. Exiting..."; exit 1; }

    # Verify GCC toolchains were cloned
    if [ ! -d "$TC_DIR/gcc" ] || [ ! -d "$TC_DIR/gcc32" ]; then
        echo "Failed :( Exiting..."
        exit 1
    fi
fi

clear

# Display initialization message
echo -e "$blue***********************************************"
echo "          Initializing Kernel Compilation          "
echo -e "***********************************************$nocol"

# Start the kernel build process
MAKE_ARGS=(
    O=out
    ARCH=arm64
    SUBARCH=arm64
    CC=clang
    LD=ld.lld
    LLVM=1
    LLVM_IAS=1
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE=aarch64-linux-android-
    CROSS_COMPILE_COMPAT=arm-linux-androideabi-
)

make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG" || { echo "Defconfig generation failed! Exiting..."; exit 1; }
make -j$(nproc --all) "${MAKE_ARGS[@]}" Image dtbs || { echo "Kernel compilation failed! Exiting..."; exit 1; }

# Verify kernel output before packaging
if [ ! -f "$ZIMAGE_DIR/Image" ] && [ ! -f "$ZIMAGE_DIR/Image.gz" ]; then
    echo "Error: Kernel Image was not generated in $ZIMAGE_DIR! Exiting..."
    exit 1
fi

# Create a zip file with the built kernel
mkdir -p tmp
if [ -f "$ZIMAGE_DIR/Image" ]; then
    cp -fp "$ZIMAGE_DIR/Image" tmp/Image
elif [ -f "$ZIMAGE_DIR/Image.gz" ]; then
    cp -fp "$ZIMAGE_DIR/Image.gz" tmp/Image.gz
fi

if [ -f "$OUT_DIR/arch/arm64/boot/dts/vendor/xiaomi/veux.dtb" ]; then
    cp -fp "$OUT_DIR/arch/arm64/boot/dts/vendor/xiaomi/veux.dtb" tmp/dtb
elif [ -f "$ZIMAGE_DIR/dtb" ]; then
    cp -fp "$ZIMAGE_DIR/dtb" tmp/dtb
elif [ -f "$ZIMAGE_DIR/dtb.img" ]; then
    cp -fp "$ZIMAGE_DIR/dtb.img" tmp/dtb
fi

if [ -f "$ZIMAGE_DIR/dtbo.img" ]; then
    cp -fp "$ZIMAGE_DIR/dtbo.img" tmp/dtbo.img
fi

if [ -d "./AnyKernel3" ]; then
    cp -rp ./AnyKernel3/* tmp/
elif [ -d "./anykernel" ]; then
    cp -rp ./anykernel/* tmp/
fi

cd tmp
[ -f dtb.img ] && mv -f dtb.img dtb
7za a -mx9 tmp.zip *
cd ..

# Clean up temporary files and rename the zip
ZIP_FINAL="${KERNEL_NAME}-veux-$TIME.zip"
cp -fp tmp/tmp.zip "$ZIP_FINAL"
rm -rf tmp

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo -e "$blue***********************************************"
echo " Build successful in $((DIFF / 60))m $((DIFF % 60))s"
echo " Flashable zip: $ZIP_FINAL"
echo -e "***********************************************$nocol"
