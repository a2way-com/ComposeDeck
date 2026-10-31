#!/bin/sh
set -e
cd /app

# Compile Blueprint (.blp) sources into GtkBuilder (.ui) files.
for f in *.blp; do
    [ -e "$f" ] || continue
    blueprint-compiler compile "$f" --output "${f%.blp}.ui"
done

# Generate the GResource manifest listing every compiled .ui file.
echo '<?xml version="1.0" encoding="UTF-8"?>' > compose-deck.gresource.xml
echo '<gresources>' >> compose-deck.gresource.xml
echo '  <gresource prefix="/com/a2way/ComposeDeck">' >> compose-deck.gresource.xml
for f in *.ui; do
    echo "    <file>$f</file>" >> compose-deck.gresource.xml
done
echo '  </gresource>' >> compose-deck.gresource.xml
echo '</gresources>' >> compose-deck.gresource.xml

# Compile the GResource bundle into C.
glib-compile-resources --sourcedir=/app --generate-source \
    --target=/app/compose-deck.c /app/compose-deck.gresource.xml

# Compile all Vala sources (autoloaded via *.vala).
mkdir -p /app/bin
valac --pkg gtk4 --pkg gio-2.0 --pkg gio-unix-2.0 --pkg libadwaita-1 \
    --pkg json-glib-1.0 --gresources=/app/compose-deck.gresource.xml \
    --gresourcesdir=/app /app/compose-deck.c /app/*.vala -o /app/bin/composedeck