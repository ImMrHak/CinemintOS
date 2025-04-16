# CinemintOS Core Components

This directory contains the core operating system components of CinemintOS, focusing on the fundamental OS functionality without the multimedia extensions found in other directories.

## Directory Contents

### Key Files

- **kernel.cpp** - The main kernel entry point that initializes the system and provides a simple command shell
- **boot.asm** - Multiboot-compliant bootloader that sets up the initial environment for the kernel
- **linker.ld** - Linker script that defines the memory layout for the kernel binary
- **build.sh** - Build script that compiles and links the kernel, and creates a bootable ISO image
- **disk.img** - Disk image file used during the build process

### Include Directory

The `include/` directory contains header files that define core OS functionality:

- **consts.h** - Constants and enumerations used throughout the kernel (e.g., VGA color definitions)
- **io.h** - Input/output utilities for keyboard handling and screen output
- **memorys.h** - Memory management functions and data structures
- **screens.h** - Text-mode screen handling functions for the console interface
- **vectors.h** - Vector implementation for dynamic data storage

## Core Functionality

### Kernel

The kernel provides:
- A multiboot-compliant entry point that receives system information from the bootloader
- Basic text-mode console with colored output
- Simple command-line interface for user interaction
- Memory information display

### Boot Process

The boot process includes:
- Multiboot header setup for GRUB compatibility
- Stack initialization
- Global Descriptor Table (GDT) setup for memory segmentation
- Transition to 32-bit protected mode
- Kernel initialization

### Memory Management

The memory subsystem provides:
- Access to memory information provided by the bootloader
- Basic memory allocation functionality
- Data structures for memory management

### I/O System

The I/O system includes:
- Keyboard input handling with scancode-to-ASCII conversion
- Text output with color support
- Cursor positioning and management

## Building the Core OS

To build the core OS components:

```bash
# Navigate to the src directory
cd src

# Run the build script
./build.sh
```

This will compile the kernel, create a bootable ISO image, and place it in the build directory.

## Running the Core OS

You can run the built OS image using QEMU:

```bash
# Run the core OS
qemu-system-i386 -cdrom build/cos.iso
```

This will boot into a simple command prompt where you can interact with the basic shell interface.

## Development

The core OS components demonstrate fundamental OS development concepts:
- Bootloader integration with Multiboot standard
- Text-mode console implementation
- Basic memory management
- Simple shell interface
- Hardware interaction through port I/O

These components serve as the foundation for the more advanced multimedia capabilities found in the VGA and WAV subsystems of CinemintOS.