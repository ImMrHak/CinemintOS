#!/bin/bash

# Stop the script immediately if any command fails.
# This helps catch errors early instead of letting the script
# potentially continue in a broken state.
set -e

#-----------------------------------------------------------------------
# STEP 1: Make sure we have all the necessary tools
#-----------------------------------------------------------------------
echo "Checking system and installing dependencies..."

# Little helper function to see if a command is available
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# We'll store the right command to install packages here
INSTALL_CMD=""
# And the names of the packages we need. These can vary a bit
# between Linux distributions, so we figure them out below.
PACKAGES_GPP=""         # C++ compiler (like g++)
PACKAGES_NASM="nasm"      # The NASM assembler
PACKAGES_QEMU=""         # QEMU emulator for i386
PACKAGES_GRUB=""         # GRUB tools (specifically for grub-mkrescue)
PACKAGES_XORRISO="xorriso" # Needed by grub-mkrescue to build the ISO image
PACKAGES_MTOOLS="mtools"    # Also sometimes needed by grub-mkrescue for FAT FS stuff
NEEDS_UPDATE=0           # Does the package manager need an update first? (like apt)

# Figure out which Linux distribution we're on by checking
# for common package manager commands.
if command_exists apt-get; then
    echo "Detected Debian/Ubuntu based system (using apt-get)."
    INSTALL_CMD="sudo apt-get install -y"
    PACKAGES_GPP="g++"         # Standard C++ compiler package
    PACKAGES_QEMU="qemu-system-x86"
    PACKAGES_GRUB="grub-pc-bin" # Provides grub-mkrescue on Debian/Ubuntu
    NEEDS_UPDATE=1             # apt needs an update before install

elif command_exists dnf; then
    echo "Detected Fedora/RHEL/CentOS based system (using dnf)."
    INSTALL_CMD="sudo dnf install -y"
    PACKAGES_GPP="gcc-c++"     # C++ compiler package name on Fedora/RHEL
    PACKAGES_QEMU="qemu-system-x86-core" # More specific QEMU package
    PACKAGES_GRUB="grub2-tools" # Provides grub-mkrescue

elif command_exists yum; then
    # Handling older RHEL/CentOS that might still use yum
    echo "Detected RHEL/CentOS based system (using yum)."
    INSTALL_CMD="sudo yum install -y"
    PACKAGES_GPP="gcc-c++"
    PACKAGES_QEMU="qemu-system-x86-core"
    PACKAGES_GRUB="grub2-tools"

elif command_exists pacman; then
    echo "Detected Arch Linux based system (using pacman)."
    INSTALL_CMD="sudo pacman -S --noconfirm --needed" # --needed avoids reinstalling
    PACKAGES_GPP="gcc"         # On Arch, the main gcc package includes g++
    PACKAGES_QEMU="qemu-system-x86" # Might be part of a larger 'qemu' group
    PACKAGES_GRUB="grub"         # The grub package includes the necessary tools

elif command_exists zypper; then
    echo "Detected openSUSE based system (using zypper)."
    INSTALL_CMD="sudo zypper install -y"
    PACKAGES_GPP="gcc-c++"
    PACKAGES_QEMU="qemu-x86"
    PACKAGES_GRUB="grub2"        # Might need 'grub2-i386-pc' on some versions? Check if issues.
    NEEDS_UPDATE=1             # zypper often needs a refresh first

else
    # If we couldn't find a known package manager
    echo "Error: Could not detect a supported package manager (apt-get, dnf, yum, pacman, zypper)." >&2
    echo "You'll need to install the following dependencies manually for your distribution:" >&2
    echo "  - C++ Compiler (like g++ or gcc-c++)" >&2
    echo "  - nasm (Netwide Assembler)" >&2
    echo "  - qemu-system-x86 (or an equivalent i386 emulator)" >&2
    echo "  - GRUB tools (specifically needing the 'grub-mkrescue' command)" >&2
    echo "  - xorriso" >&2
    echo "  - mtools" >&2
    exit 1
fi

# Put all the package names together into one list
ALL_PACKAGES="$PACKAGES_GPP $PACKAGES_NASM $PACKAGES_QEMU $PACKAGES_GRUB $PACKAGES_XORRISO $PACKAGES_MTOOLS"

# Update package lists if the package manager requires it (like apt or zypper)
if [ "$NEEDS_UPDATE" -eq 1 ]; then
    echo "Updating package lists..."
    # This feels a bit clumsy, but handles the common cases
    case "$INSTALL_CMD" in
        *apt-get*) sudo apt-get update ;;
        *zypper*) sudo zypper refresh ;;
    esac
fi

# Now, install all the things!
echo "Installing packages: $ALL_PACKAGES"
# Using 'eval' here lets us run the install command string we built earlier.
# It's generally okay here since we constructed the command ourselves.
eval "$INSTALL_CMD $ALL_PACKAGES"

echo "Dependencies should now be installed."
# --- End Dependency Installation ---


#-----------------------------------------------------------------------
# STEP 2: Build the OS Kernel
#-----------------------------------------------------------------------

# Figure out where this script is located. We'll use this to find
# the source files and create the build directory nearby.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define where we'll put the compiled files (object files, kernel binary, ISO)
BUILD_DIR="$SCRIPT_DIR/build"
ISO_DIR="$BUILD_DIR/iso"
ISO_BOOT_DIR="$ISO_DIR/boot"
GRUB_DIR="$ISO_BOOT_DIR/grub"

# Start fresh: remove any old build directory and create a new one.
echo "Cleaning previous build (if any)..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" # -p means create parent directories if needed, and don't error if it exists
echo "Build directory created at $BUILD_DIR"

# Sanity check: Make sure the source files actually exist where we expect them.
echo "Looking for source files..."
if [ ! -f "$SCRIPT_DIR/boot.asm" ]; then
    echo "Error: Can't find 'boot.asm' in the script directory ($SCRIPT_DIR)" >&2
    exit 1
fi
if [ ! -f "$SCRIPT_DIR/kernel.cpp" ]; then
    echo "Error: Can't find 'kernel.cpp' in the script directory ($SCRIPT_DIR)" >&2
    exit 1
fi
if [ ! -f "$SCRIPT_DIR/linker.ld" ]; then
    echo "Error: Can't find 'linker.ld' in the script directory ($SCRIPT_DIR)" >&2
    exit 1
fi
echo "Source files found."

# Compile the assembly bootloader (boot.asm -> boot.o)
echo "Compiling bootloader (boot.asm)..."
# We need NASM for this. The dependency check should have installed it.
nasm -f elf32 "$SCRIPT_DIR/boot.asm" -o "$BUILD_DIR/boot.o"

# Compile the C++ kernel code (kernel.cpp -> kernel.o)
echo "Compiling kernel code (kernel.cpp)..."
# Check if g++ command exists, just in case installation failed silently.
if ! command_exists g++; then echo "Error: g++ command not found! Dependency installation might have failed." >&2; exit 1; fi
# Flags explained:
# -m32: Compile for 32-bit architecture
# -ffreestanding: We're not linking against a standard library/OS
# -fno-exceptions/-fno-rtti: Disable C++ exceptions and RTTI (often not needed/supported in freestanding)
# -O2: Optimization level 2
# -c: Compile only, don't link yet
g++ -m32 -ffreestanding -fno-exceptions -fno-rtti -O2 -c "$SCRIPT_DIR/kernel.cpp" -o "$BUILD_DIR/kernel.o"

# Link the bootloader object and kernel object together into the final kernel binary
echo "Linking kernel..."
# Check if ld command exists (the linker, usually comes with gcc/binutils)
if ! command_exists ld; then echo "Error: ld command not found! Dependency installation might have failed." >&2; exit 1; fi
# Flags explained:
# -m elf_i386: Link for the 32-bit ELF format
# -T linker.ld: Use our custom linker script to define memory layout
# -o build/kernel.bin: Output file name
# build/boot.o build/kernel.o: Input object files
ld -m elf_i386 -T "$SCRIPT_DIR/linker.ld" -o "$BUILD_DIR/kernel.bin" "$BUILD_DIR/boot.o" "$BUILD_DIR/kernel.o"

# Important check: Did the linking actually produce a non-empty file?
if [ ! -s "$BUILD_DIR/kernel.bin" ]; then
    # -s checks if the file exists and has a size greater than zero
    echo "Error: Linking failed or kernel.bin is empty. Check compiler/linker output for errors." >&2
    exit 1
fi
echo "Kernel linked successfully: $BUILD_DIR/kernel.bin"


#-----------------------------------------------------------------------
# STEP 3: Create a Bootable ISO Image
#-----------------------------------------------------------------------
echo "Creating bootable ISO image..."

# Set up the directory structure required by GRUB inside the ISO
mkdir -p "$GRUB_DIR" # This creates build/iso/boot/grub

# Copy our freshly built kernel into the ISO's boot directory
cp "$BUILD_DIR/kernel.bin" "$ISO_BOOT_DIR/"

# Create the GRUB configuration file (grub.cfg)
# This tells GRUB how to load our kernel.
echo "Creating GRUB config (grub.cfg)..."
cat > "$GRUB_DIR/grub.cfg" << EOF
# Basic GRUB config

# Don't wait for user input at boot menu
set timeout=0
# Boot the first (and only) menu entry automatically
set default=0

# Define our OS entry
menuentry "Cinemint OS" {
    # Load the kernel using the multiboot standard
    # GRUB looks for this file relative to the ISO root (/)
    multiboot /boot/kernel.bin
    # Tell GRUB we're done loading and it should execute the kernel
    boot
}
EOF
echo "GRUB config written to $GRUB_DIR/grub.cfg"

# Use the grub-mkrescue utility to create the final bootable ISO
# Check if the command exists first.
if ! command_exists grub-mkrescue; then
    echo "Error: grub-mkrescue command not found. Dependency installation might have failed or the GRUB package name was wrong for your system." >&2
    exit 1
fi
echo "Running grub-mkrescue..."
grub-mkrescue -o "$BUILD_DIR/cos.iso" "$ISO_DIR"
# This command takes the contents of the build/iso directory and wraps
# them up with GRUB's bootloader files into a bootable ISO image.

# Final check: Did the ISO get created properly?
if [ ! -s "$BUILD_DIR/cos.iso" ]; then
    echo "Error: ISO creation failed or cos.iso is empty. Check output from grub-mkrescue." >&2
    exit 1
fi
echo "Build successful! ISO created at $BUILD_DIR/cos.iso"


#-----------------------------------------------------------------------
# STEP 4: Run the OS in QEMU
#-----------------------------------------------------------------------
echo "Attempting to run the OS in QEMU..."

# Find the right QEMU command for an i386 system.
QEMU_CMD=""
if command_exists qemu-system-i386; then
    # Prefer the specific i386 emulator if available
    QEMU_CMD="qemu-system-i386"
elif command_exists qemu-system-x86_64; then
    # Fallback: The x86_64 emulator can usually run 32-bit guests too.
    echo "Info: qemu-system-i386 not found, trying qemu-system-x86_64 instead."
    QEMU_CMD="qemu-system-x86_64"
else
    # If neither is found, we can't run it.
    echo "Error: Could not find a suitable QEMU command (qemu-system-i386 or qemu-system-x86_64)." >&2
    echo "QEMU might not be installed correctly." >&2
    exit 1
fi

# Launch QEMU!
# -cdrom tells QEMU to use our ISO file as a virtual CD-ROM drive
echo "Starting QEMU with command: $QEMU_CMD -cdrom $BUILD_DIR/cos.iso"
$QEMU_CMD -cdrom "$BUILD_DIR/cos.iso"

# Once QEMU exits (either by shutting down the guest OS or closing the window)
echo "QEMU has finished."
exit 0 # Exit successfully