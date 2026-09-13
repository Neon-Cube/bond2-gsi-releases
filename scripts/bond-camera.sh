#!/usr/bin/env bash
# bond-camera.sh — bake Daria Bond II stock camera into an unpacked GSI tree.
# Usage: bond-camera.sh <SYS_DIR> [<BLOBS_DIR>]
# No modules, no overlays: files land in the image with real inodes.
set -euo pipefail

SYS_DIR="${1:?Usage: $0 <SYS_DIR> [<BLOBS_DIR>]}"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BLOBS_DIR="${2:-$SCRIPT_DIR/../blobs/camera}"

APK_SRC="$BLOBS_DIR/PriCamera.apk"
LIBS_SRC="$BLOBS_DIR/libs"
PERM_SRC="$BLOBS_DIR/privapp-permissions-com.mediatek.camera.xml"
SYSCTL_SRC="$BLOBS_DIR/pri-camera-preinstalled.xml"
PROPS_SRC="$BLOBS_DIR/bond-camera-props.txt"

for f in "$APK_SRC" "$PERM_SRC" "$SYSCTL_SRC" "$PROPS_SRC"; do
    if [ ! -f "$f" ]; then
        echo "[ERROR] missing blob: $f" >&2
        exit 1
    fi
done
if [ ! -d "$LIBS_SRC" ]; then
    echo "[ERROR] missing libs dir: $LIBS_SRC" >&2
    exit 1
fi

# Resolve system_ext target: GSI trees carry it as <SYS>/system/system_ext
# (sometimes via <SYS>/system_ext symlink). Prefer the real directory.
if [ -d "$SYS_DIR/system/system_ext" ]; then
    SE="$SYS_DIR/system/system_ext"
elif [ -d "$SYS_DIR/system_ext" ] && [ ! -L "$SYS_DIR/system_ext" ]; then
    SE="$SYS_DIR/system_ext"
else
    echo "[ERROR] no system_ext dir found under $SYS_DIR" >&2
    exit 1
fi

echo "==> bond-camera: target $SE"

# 1. Priv-app APK (real inode in image — survives PackageManager scan)
mkdir -p "$SE/priv-app/PriCamera"
cp -f "$APK_SRC" "$SE/priv-app/PriCamera/PriCamera.apk"
chmod 644 "$SE/priv-app/PriCamera/PriCamera.apk"

# 2. Native libs (stock app dlopens by soname from system_ext/lib64)
mkdir -p "$SE/lib64"
cp -f "$LIBS_SRC"/*.so "$SE/lib64/"
chmod 644 "$SE"/lib64/*.so

# 3. Privapp allowlist (SYSTEM_CAMERA + stock privileged perms; stock ships none)
mkdir -p "$SE/etc/permissions"
cp -f "$PERM_SRC" "$SE/etc/permissions/privapp-permissions-com.mediatek.camera.xml"
chmod 644 "$SE/etc/permissions/privapp-permissions-com.mediatek.camera.xml"

# 4. Sysconfig install entry (verbatim FULL/PROFILE from stock product/etc/sysconfig)
mkdir -p "$SE/etc/sysconfig"
cp -f "$SYSCTL_SRC" "$SE/etc/sysconfig/pri-camera-preinstalled.xml"
chmod 644 "$SE/etc/sysconfig/pri-camera-preinstalled.xml"

# 5. Props (dump-verified camera flags; appended once, idempotent marker)
PROP_DST=""
for cand in "$SE/build.prop" "$SYS_DIR/system/build.prop"; do
    if [ -f "$cand" ]; then PROP_DST="$cand"; break; fi
done
if [ -z "$PROP_DST" ]; then
    echo "[ERROR] no build.prop found for camera props" >&2
    exit 1
fi
if ! grep -q "# bond-camera v1" "$PROP_DST"; then
    {
        echo ""
        echo "# bond-camera v1 by neoncube (Daria Bond II stock camera, dump-verified)"
        cat "$PROPS_SRC"
    } >> "$PROP_DST"
fi

# 6. Verify
echo "==> bond-camera verify:"
ls -l "$SE/priv-app/PriCamera/PriCamera.apk"
ls "$SE"/lib64/*.so | wc -l
grep -c "privapp-permissions" "$SE/etc/permissions/privapp-permissions-com.mediatek.camera.xml"
grep -c "bond-camera v1" "$PROP_DST"
echo "✓ bond-camera baked"
