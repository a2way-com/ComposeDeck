#!/bin/sh
set -eu

SRCDIR=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)
BUILDDIR=$(mktemp -d "${TMPDIR:-/tmp}/composedeck-build.XXXXXX")
trap 'rm -rf "$BUILDDIR"' EXIT HUP INT TERM

mkdir -p "$BUILDDIR/ui" "$BUILDDIR/c" "$BUILDDIR/bin"

# Compile Blueprint (.blp) sources into GtkBuilder (.ui) files.
for blueprint in "$SRCDIR"/src/blueprints/*.blp; do
    [ -e "$blueprint" ] || continue
    name=$(basename "$blueprint" .blp)
    blueprint-compiler compile "$blueprint" --output "$BUILDDIR/ui/$name.ui"
done

cp "$SRCDIR/src/style.css" "$BUILDDIR/ui/style.css"

# Generate the GResource manifest listing every compiled resource.
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<gresources>'
    echo '  <gresource prefix="/com/a2way/ComposeDeck">'
    for resource in "$BUILDDIR"/ui/*.ui "$BUILDDIR"/ui/*.css; do
        [ -e "$resource" ] || continue
        echo "    <file>$(basename "$resource")</file>"
    done
    echo '  </gresource>'
    echo '</gresources>'
} > "$BUILDDIR/compose-deck.gresource.xml"

# Compile the GResource bundle into C.
glib-compile-resources --sourcedir="$BUILDDIR/ui" --generate-source \
    --target="$BUILDDIR/compose-deck.c" "$BUILDDIR/compose-deck.gresource.xml"

# Compile all Vala sources.
valac --pkg gtk4 --pkg gio-2.0 --pkg gio-unix-2.0 --pkg libadwaita-1 \
    --pkg json-glib-1.0 \
    --directory="$BUILDDIR/c" \
    --gresources="$BUILDDIR/compose-deck.gresource.xml" \
    --gresourcesdir="$BUILDDIR/ui" \
    "$BUILDDIR/compose-deck.c" \
    "$SRCDIR"/src/Logic/*.vala \
    "$SRCDIR"/src/Views/*.vala \
    -o "$BUILDDIR/bin/composedeck"

# flatpak-builder sets FLATPAK_DEST. The local flatpak-build target in the
# Makefile sets it to /app; a plain local run installs under build/install.
if [ -n "${FLATPAK_DEST:-}" ]; then
    DEST="$FLATPAK_DEST"
elif [ -d /app ] && [ -w /app ]; then
    DEST=/app
else
    DEST="$SRCDIR/build/install"
fi

install -Dm755 "$BUILDDIR/bin/composedeck" "$DEST/bin/composedeck"
install -Dm644 "$SRCDIR/data/com.a2way.ComposeDeck.desktop" \
    "$DEST/share/applications/com.a2way.ComposeDeck.desktop"
install -Dm644 "$SRCDIR/data/com.a2way.ComposeDeck.metainfo.xml" \
    "$DEST/share/metainfo/com.a2way.ComposeDeck.metainfo.xml"
install -Dm644 "$SRCDIR/data/icons/hicolor/scalable/apps/com.a2way.ComposeDeck.svg" \
    "$DEST/share/icons/hicolor/scalable/apps/com.a2way.ComposeDeck.svg"
install -Dm644 "$SRCDIR/LICENSE" \
    "$DEST/share/licenses/com.a2way.ComposeDeck/LICENSE"

echo "Installed ComposeDeck to $DEST"
