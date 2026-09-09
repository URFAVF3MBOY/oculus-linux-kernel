#!/bin/sh
set -eu

GKI_ROOT=$(pwd)

display_usage() {
    echo "Usage: $0 [--cleanup | <commit-or-tag>]"
    echo "  --cleanup:              Cleans up previous modifications made by the script."
    echo "  <commit-or-tag>:        Sets up or updates the KernelSU to specified tag or commit."
    echo "  -h, --help:             Displays this usage information."
    echo "  (no args):              Sets up or updates the KernelSU environment to the latest tagged version."
}

initialize_variables() {
     if test -d "$GKI_ROOT/common/drivers"; then
          DRIVER_DIR="$GKI_ROOT/common/drivers"
     elif test -d "$GKI_ROOT/drivers"; then
          DRIVER_DIR="$GKI_ROOT/drivers"
     else
          echo '[ERROR] "drivers/" directory not found.'
          exit 127
     fi

     DRIVER_MAKEFILE=$DRIVER_DIR/Makefile
     DRIVER_KCONFIG=$DRIVER_DIR/Kconfig
}

# Reverts modifications made by this script
perform_cleanup() {
    echo "[+] Cleaning up..."
    [ -L "$DRIVER_DIR/kernelsu" ] && rm "$DRIVER_DIR/kernelsu" && echo "[-] Symlink removed."
    grep -q "kernelsu" "$DRIVER_MAKEFILE" && sed -i '/kernelsu/d' "$DRIVER_MAKEFILE" && echo "[-] Makefile reverted."
    grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG" && sed -i '/drivers\/kernelsu\/Kconfig/d' "$DRIVER_KCONFIG" && echo "[-] Kconfig reverted."
    if [ -d "$GKI_ROOT/KernelSU" ]; then
        rm -rf "$GKI_ROOT/KernelSU" && echo "[-] KernelSU directory deleted."
    fi
}

setup_kernelsu() {
    echo "[+] Setting up KernelSU..."

    KSU_DIR="$GKI_ROOT/KernelSU"

    # Clone the repository directly into the KernelSU directory.
    if [ ! -d "$KSU_DIR/.git" ]; then
        echo "[+] Cloning KernelSU into $KSU_DIR..."

        rm -rf "$KSU_DIR"

        git clone https://github.com/gmh5225/KernelSU-4.4.git "$KSU_DIR"

        echo "[+] Repository cloned."
    fi

    # Enter the cloned KernelSU repository.
    cd "$KSU_DIR"

    git stash || true
    echo "[-] Stashed current changes."

    # If currently detached on a tag, return to main before updating.
    if [ "$(git status | grep -Po 'v\d+(\.\d+)*' | head -n1)" ]; then
        git checkout main
        echo "[-] Switched to main branch."
    fi

    git pull
    echo "[+] Repository updated."

    if [ -z "${1-}" ]; then
    TAG="$(git describe --abbrev=0 --tags 2>/dev/null || true)"

    if [ -n "$TAG" ]; then
        git checkout "$TAG"
        echo "[-] Checked out latest tag: $TAG"
    else
        echo "[+] No tags found; using the repository's current branch."
    fi
else
    git checkout "$1"
    echo "[-] Checked out $1."
fi

    # Verify the repository has the expected kernel directory.
    if [ ! -d "$KSU_DIR/kernel" ]; then
        echo "[ERROR] KernelSU repository does not contain:"
        echo "        $KSU_DIR/kernel"
        exit 1
    fi

    # Return to the kernel's drivers directory.
    cd "$DRIVER_DIR"

    # Create drivers/kernelsu -> ../../KernelSU/kernel
    ln -sfn \
        "$(realpath --relative-to="$DRIVER_DIR" "$KSU_DIR/kernel")" \
        "kernelsu"

    echo "[+] Symlink created."

    # Add entries in Makefile and Kconfig if not already existing.
    grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$DRIVER_MAKEFILE" || \
        printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_MAKEFILE"

    grep -q 'source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG" || \
        sed -i '/endmenu/i\
source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG"

    echo '[+] Done.'
}

# Process command-line arguments
if [ "$#" -eq 0 ]; then
    initialize_variables
    setup_kernelsu
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    display_usage
elif [ "$1" = "--cleanup" ]; then
    initialize_variables
    perform_cleanup
else
    initialize_variables
    setup_kernelsu "$@"
fi