# ComposeDeck build system — auto-discovers all .vala and .ui files.
# No need to list individual source files.

VALA_SOURCES := $(wildcard *.vala)
UI_FILES     := $(wildcard *.ui)
GRESOURCE_XML := compose-deck.gresource.xml
GRESOURCE_C  := compose-deck.c
BINARY       := composedeck
GRESOURCE_PREFIX := /com/a2way/ComposeDeck

VALAC := valac
VALAC_FLAGS := --pkg gtk4 --pkg gio-2.0 --pkg libadwaita-1

.PHONY: all clean run

all: $(BINARY)

# Auto-generate GResource XML from all .ui files
$(GRESOURCE_XML): $(UI_FILES)
	@echo "Generating $(GRESOURCE_XML) from $(UI_FILES)..."
	@{ \
		echo '<?xml version="1.0" encoding="UTF-8"?>'; \
		echo '<gresources>'; \
		echo '  <gresource prefix="$(GRESOURCE_PREFIX)">'; \
		for f in $(UI_FILES); do echo "    <file>$$f</file>"; done; \
		echo '  </gresource>'; \
		echo '</gresources>'; \
	} > $@

# Compile GResource XML into C
$(GRESOURCE_C): $(GRESOURCE_XML) $(UI_FILES)
	glib-compile-resources --sourcedir=. --generate-source --target=$@ $(GRESOURCE_XML)

# Compile Vala sources (local, requires SDK in PATH)
$(BINARY): $(VALA_SOURCES) $(GRESOURCE_C) $(UI_FILES)
	$(VALAC) $(VALAC_FLAGS) \
		--gresources=$(GRESOURCE_XML) --gresourcesdir=. \
		$(GRESOURCE_C) $(VALA_SOURCES) \
		-o $@

# Build inside Flatpak SDK (no local SDK needed)
SDK_RUNTIME := org.gnome.Sdk/x86_64/51
SDK_PATH := $(HOME)/.local/share/flatpak/runtime/$(SDK_RUNTIME)/3bb470fac9f1a83c6629c2cdd9472a444688372bbc362416e4a9b2e4386e9fad/files

.PHONY: flatpak-build flatpak-run

flatpak-build: $(GRESOURCE_XML)
	@rm -rf build
	@flatpak build-init build com.a2way.ComposeDeck org.gnome.Sdk//51 org.gnome.Platform//51 >/dev/null 2>&1
	@mkdir -p build/files
	@cp $(VALA_SOURCES) $(UI_FILES) $(GRESOURCE_XML) build/files/
	@flatpak build build sh -c "glib-compile-resources --sourcedir=/app --generate-source --target=/app/compose-deck.c /app/compose-deck.gresource.xml && mkdir -p /app/bin && valac --pkg gtk4 --pkg gio-2.0 --pkg libadwaita-1 --gresources=/app/compose-deck.gresource.xml --gresourcesdir=/app /app/compose-deck.c /app/*.vala -o /app/bin/composedeck"
	@flatpak build-finish build --command=composedeck --socket=x11 --socket=wayland --share=ipc --share=network --filesystem=home --filesystem=xdg-run/podman >/dev/null 2>&1
	@echo "Build complete: build/files/bin/composedeck"

flatpak-run: flatpak-build
	@flatpak build-export repo build >/dev/null 2>&1
	@flatpak uninstall --user --assumeyes com.a2way.ComposeDeck >/dev/null 2>&1 || true
	@flatpak install --user --assumeyes localrepo com.a2way.ComposeDeck >/dev/null 2>&1
	@flatpak run --user com.a2way.ComposeDeck

clean:
	rm -f $(BINARY) $(GRESOURCE_C) $(GRESOURCE_XML)

run: $(BINARY)
	./$(BINARY)