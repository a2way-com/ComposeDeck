# ComposeDeck build system.
# Blueprint (.blp) sources are compiled into build/ui/*.ui (never into the
# project root). Everything else also goes under build/.

BLUEPRINT = flatpak run --user --command=blueprint-compiler --filesystem=$(CURDIR) org.gnome.Sdk//51
VALA_SOURCES := $(wildcard *.vala)
BLP_FILES   := $(wildcard *.blp)

BUILD_DIR   := build
UI_DIR      := $(BUILD_DIR)/ui
UI_FILES    := $(addprefix $(UI_DIR)/,$(BLP_FILES:.blp=.ui))
GRESOURCE_XML := $(BUILD_DIR)/compose-deck.gresource.xml
GRESOURCE_C  := $(BUILD_DIR)/compose-deck.c
BINARY       := $(BUILD_DIR)/bin/composedeck
GRESOURCE_PREFIX := /com/a2way/ComposeDeck

VALAC := valac
VALAC_FLAGS := --pkg gtk4 --pkg gio-2.0 --pkg gio-unix-2.0 --pkg libadwaita-1 --pkg json-glib-1.0

.PHONY: all clean run blueprint

all: flatpak-build

blueprint: $(UI_FILES)

$(UI_DIR)/%.ui: %.blp
	@mkdir -p $(UI_DIR)
	GI_TYPELIB_PATH="$(SDK_PATH)/lib/x86_64-linux-gnu/girepository-1.0:$(SDK_PATH)/lib/girepository-1.0" XDG_DATA_DIRS="$(SDK_PATH)/share" $(BLUEPRINT) compile $< --output $@

# Auto-generate GResource XML from all .ui files
$(GRESOURCE_XML): $(UI_FILES)
	@mkdir -p $(BUILD_DIR)
	@echo "Generating $(GRESOURCE_XML) from $(UI_FILES)..."
	@{ \
		echo '<?xml version="1.0" encoding="UTF-8"?>'; \
		echo '<gresources>'; \
		echo '  <gresource prefix="$(GRESOURCE_PREFIX)">'; \
		for f in $(notdir $(UI_FILES)); do echo "    <file>$$f</file>"; done; \
		echo '  </gresource>'; \
		echo '</gresources>'; \
	} > $@

# Compile GResource XML into C
$(GRESOURCE_C): $(GRESOURCE_XML) $(UI_FILES)
	glib-compile-resources --sourcedir=$(UI_DIR) --generate-source --target=$@ $(GRESOURCE_XML)

# Native build (requires GTK dev headers; prefer flatpak-build normally)
$(BINARY): $(VALA_SOURCES) $(GRESOURCE_C) $(UI_FILES) $(BLP_FILES)
	@mkdir -p $(BUILD_DIR)/bin
	$(VALAC) $(VALAC_FLAGS) \
		--gresources=$(GRESOURCE_XML) --gresourcesdir=$(UI_DIR) \
		$(GRESOURCE_C) $(VALA_SOURCES) \
		-o $@

run: $(BINARY)
	./$(BINARY)

SDK_RUNTIME := org.gnome.Sdk/x86_64/51
SDK_PATH := $(HOME)/.local/share/flatpak/runtime/$(SDK_RUNTIME)/3bb470fac9f1a83c6629c2cdd9472a444688372bbc362416e4a9b2e4386e9fad/files

.PHONY: flatpak-build flatpak-run

flatpak-build: $(BLP_FILES)
	@rm -rf build
	@flatpak build-init build com.a2way.ComposeDeck org.gnome.Sdk//51 org.gnome.Platform//51 >/dev/null 2>&1
	@mkdir -p build/files
	@cp $(VALA_SOURCES) $(BLP_FILES) build.sh build/files/
	@flatpak build build sh -c "sh /app/build.sh"
	@flatpak build-finish build --command=composedeck --socket=x11 --socket=wayland --share=ipc --share=network --filesystem=home --filesystem=xdg-run/podman >/dev/null 2>&1
	@echo "Build complete: build/files/bin/composedeck"

flatpak-run: flatpak-build
	@flatpak build-export repo build >/dev/null 2>&1
	@flatpak uninstall --user --assumeyes com.a2way.ComposeDeck >/dev/null 2>&1 || true
	@flatpak install --user --assumeyes localrepo com.a2way.ComposeDeck >/dev/null 2>&1
	@flatpak run --user com.a2way.ComposeDeck

clean:
	rm -rf build