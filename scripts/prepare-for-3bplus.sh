#!/usr/bin/env bash
# prepare-for-3bplus.sh
#
# Apply Pi 3B+ migration edits to a CLONED paper-console SD card's boot
# partition. Run on the cloning host (Mac/Linux) after mounting the clone's
# FAT partition, or on the Pi 3B+ itself after first boot (idempotent).
#
# Usage:
#   ./prepare-for-3bplus.sh [BOOT_MOUNT]
#
# BOOT_MOUNT defaults to /boot/firmware (correct when run on the Pi itself).
# On a cloning host, pass the mount point of the FAT partition, e.g.:
#   ./prepare-for-3bplus.sh /Volumes/bootfs
#   ./prepare-for-3bplus.sh /mnt/clone-boot
#
# Safe to re-run: edits are guarded by markers and config.txt is backed up
# only on the first run.

set -euo pipefail

BOOT="${1:-/boot/firmware}"
CONFIG="${BOOT}/config.txt"
MARKER_BEGIN="# >>> paper-console pi3b+ migration >>>"
MARKER_END="# <<< paper-console pi3b+ migration <<<"

if [[ ! -f "${CONFIG}" ]]; then
    echo "error: ${CONFIG} not found. Pass the boot-partition mount point as arg 1." >&2
    exit 2
fi

if grep -qF "${MARKER_BEGIN}" "${CONFIG}"; then
    echo "config.txt already migrated — nothing to do."
    exit 0
fi

backup="${CONFIG}.pre-pi3bplus.$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "${CONFIG}" "${backup}"
echo "backed up: ${backup}"

# 1. Remove `dtparam=uart0=on` from any [all] section (it's BCM2712-only).
#    Only matches the exact line; leaves comments and other directives alone.
tmp="$(mktemp)"
awk '
    /^dtparam=uart0=on[[:space:]]*$/ { next }
    { print }
' "${CONFIG}" > "${tmp}"
mv "${tmp}" "${CONFIG}"

# 2. Append filtered blocks for Pi 5 (restore uart0=on) and Pi 3B+.
cat >> "${CONFIG}" <<EOF

${MARKER_BEGIN}
[pi5]
dtparam=uart0=on

[pi3+]
enable_uart=1
dtoverlay=disable-bt

[all]
${MARKER_END}
EOF

echo "applied [pi5] and [pi3+] blocks to ${CONFIG}"

# 3. Sanity-check the result parses by line.
if ! grep -qE '^\[pi3\+\]$' "${CONFIG}"; then
    echo "error: [pi3+] section missing after edit — restoring backup" >&2
    cp -p "${backup}" "${CONFIG}"
    exit 3
fi

echo
echo "Done. Next steps:"
echo "  - Eject the SD card cleanly and insert into the Pi 3B+."
echo "  - Boot. On first boot, expect serial0 -> ttyAMA0 (PL011 on GPIO 14/15)."
echo "  - Verify: ls -l /dev/serial0 ; cat /proc/cpuinfo | grep Model"
echo "  - If you don't need Bluetooth: sudo systemctl disable --now hciuart bluetooth"
