using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * ShortcutEditor — dialog for creating or editing the desktop shortcut
     * published for one app port.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/ShortcutEditor.ui")]
    [CCode (cname = "ShortcutEditor")]
    public class ShortcutEditor : Adw.MessageDialog {
        [GtkChild] private unowned Gtk.Entry nameEntry;
        [GtkChild] private unowned Gtk.Entry urlEntry;
        [GtkChild] private unowned Gtk.Entry iconEntry;
        [GtkChild] private unowned Gtk.Image iconPreview;
        [GtkChild] private unowned Gtk.Button chooseIcon;
        [GtkChild] private unowned Gtk.CheckButton ownBrowserCheck;
        [GtkChild] private unowned Gtk.Button defaultsButton;

        private string appName;
        private uint port;

        public static bool exists (string appName, uint port) {
            return GLib.File.new_for_path(ShortcutEditor.shortcutPath(appName, port)).query_exists();
        }

        private static string shortcutPath (string appName, uint port) {
            // Use the host data dir: inside Flatpak, XDG_DATA_HOME points at
            // the sandbox-private ~/.var/app/<id>/data.
            return Environment.get_home_dir() + "/.local/share/applications/" +
                Logic.ComposeDeck.portShortcutFileName(appName, port);
        }

        public ShortcutEditor (string appName, uint port, Gtk.Window? parentWindow = null) {
            this.appName = appName;
            this.port = port;

            string defaultName = "%s — localhost:%u".printf(this.appName, this.port);
            string defaultUrl = "http://localhost:%u".printf(this.port);
            string defaultIcon = "com.a2way.ComposeDeck";

            string name = defaultName;
            string url = defaultUrl;
            string icon = defaultIcon;
            bool ownBrowser = false;
            bool exists = ShortcutEditor.exists(this.appName, this.port);

            if (exists) {
                try {
                    uint8[] raw;
                    string etag;
                    GLib.File.new_for_path(this.portShortcutPath()).load_contents(null, out raw, out etag);
                    foreach (var line in ((string) raw).split ("\n")) {
                        if (line.has_prefix("Name=")) {
                            name = line.substring(5).strip();
                        } else if (line.has_prefix("Icon=")) {
                            icon = line.substring(5).strip();
                        } else if (line.has_prefix("Exec=")) {
                            url = Logic.ComposeDeck.extractExecUrl(line);
                        } else if (line.has_prefix("X-ComposeDeck-OpenInOwnBrowser=")) {
                            int eq = line.index_of("=");
                            if (eq >= 0) ownBrowser = line.substring(eq + 1).strip() == "true";
                        }
                    }
                } catch (Error e) {
                    // Fall back to defaults.
                }
            }

            this.set_transient_for(parentWindow);
            this.set_heading(exists ? "Shortcut options" : "Add shortcut");

            this.nameEntry.set_text(name);
            this.urlEntry.set_text(url);
            this.iconEntry.set_text(icon);
            this.updateIconPreview(icon);
            this.iconEntry.changed.connect(() => this.updateIconPreview(this.iconEntry.get_text()));
            this.chooseIcon.clicked.connect(this.openIconPicker);

            this.ownBrowserCheck.set_active(ownBrowser);
            bool canOwnBrowser = Logic.WebAppBrowser.resolve(Logic.Application.getState().webAppBrowser) != null;
            this.ownBrowserCheck.set_sensitive(canOwnBrowser || ownBrowser);
            if (!canOwnBrowser) {
                this.ownBrowserCheck.set_tooltip_text("Install Chromium, Chrome, Brave, Edge, Vivaldi, or GNOME Web");
            }

            this.defaultsButton.clicked.connect(() => {
                this.nameEntry.set_text(defaultName);
                this.urlEntry.set_text(defaultUrl);
                this.iconEntry.set_text(defaultIcon);
                this.ownBrowserCheck.set_active(false);
            });

            this.add_response("cancel", "Cancel");
            this.add_response("save", "Save");
            if (exists) {
                this.add_response("remove", "Remove");
            }
            this.set_default_response("save");
            this.set_close_response("cancel");
            this.response.connect((dialog, response) => this.onResponse(response));
        }

        private string portShortcutPath () {
            return ShortcutEditor.shortcutPath(this.appName, this.port);
        }

        private void onResponse (string response) {
            if (response == "save") {
                this.savePortShortcut(this.nameEntry.get_text().strip(), this.urlEntry.get_text().strip(), this.iconEntry.get_text().strip(), this.ownBrowserCheck.get_active());
            } else if (response == "remove") {
                this.removePortShortcut();
            }
            this.close();
        }

        private void openIconPicker () {
            var dialog = new Gtk.FileDialog();
            dialog.set_title("Choose icon");

            var filter = new Gtk.FileFilter();
            filter.name = "Images";
            filter.add_pattern("*.png");
            filter.add_pattern("*.svg");
            filter.add_pattern("*.jpg");
            filter.add_pattern("*.jpeg");
            filter.add_pattern("*.webp");

            var filters = new GLib.ListStore(typeof (Gtk.FileFilter));
            filters.append(filter);
            dialog.set_filters(filters);

            dialog.open.begin(this.get_transient_for(), null, (source, result) => {
                try {
                    var file = dialog.open.end(result);
                    if (file != null) {
                        string? path = file.get_path();
                        if (path != null) this.iconEntry.set_text(path);
                    }
                } catch (Error e) {
                    // Cancelled.
                }
            });
        }

        private void updateIconPreview (string icon) {
            if (icon == "") {
                this.iconPreview.icon_name = "com.a2way.ComposeDeck";
                return;
            }
            if (icon.has_prefix("/")) {
                if (GLib.File.new_for_path(icon).query_exists()) {
                    // Gtk.Image loads SVG as well as raster images here.
                    this.iconPreview.set_from_file(icon);
                } else {
                    this.iconPreview.icon_name = "com.a2way.ComposeDeck";
                }
                return;
            }
            this.iconPreview.icon_name = icon;
        }

        private void savePortShortcut (string name, string url, string icon, bool ownBrowser) {
            var state = Logic.Application.getState();
            string shortcutName = name;
            string shortcutUrl = url;
            string shortcutIcon = icon;
            if (shortcutName == "") shortcutName = "%s — localhost:%u".printf(this.appName, this.port);
            if (shortcutUrl == "") shortcutUrl = "http://localhost:%u".printf(this.port);
            if (shortcutUrl.index_of("://") < 0) shortcutUrl = "http://" + shortcutUrl;
            if (shortcutIcon == "") shortcutIcon = "com.a2way.ComposeDeck";

            try {
                var dir = GLib.File.new_for_path(Environment.get_home_dir() + "/.local/share/applications");
                if (!dir.query_exists()) {
                    dir.make_directory_with_parents(null);
                }
            } catch (Error e) {
                state.actionError = "Could not create the applications folder.";
                state.changed();
                return;
            }

            string path = this.portShortcutPath();
            string shortcutFileBase = GLib.Path.get_basename(path);
            if (shortcutFileBase.has_suffix(".desktop")) {
                shortcutFileBase = shortcutFileBase.substring(0, shortcutFileBase.length - 8);
            }

            Logic.ComposeDeck.cleanupLegacyPortalEntriesFor(
                Logic.ComposeDeck.legacySegment(this.appName, this.port));

            string oldProfileName = "";
            string content;
            if (ownBrowser) {
                var browser = Logic.WebAppBrowser.resolve(state.webAppBrowser);
                if (browser == null) {
                    state.actionError = "No app-mode browser found. Install Chromium, Chrome, Brave, Edge, Vivaldi, or GNOME Web.";
                    state.changed();
                    return;
                }

                var existing = GLib.File.new_for_path(path);
                if (existing.query_exists()) {
                    try {
                        uint8[] raw;
                        string etag;
                        existing.load_contents(null, out raw, out etag);
                        string oldContent = (string) raw;
                        if (oldContent.contains("--application-mode")) {
                            string oldName = "";
                            foreach (var line in oldContent.split("\n")) {
                                if (line.has_prefix("Name=")) {
                                    oldName = line.substring(5).strip();
                                }
                            }
                            if (browser.profileMode) {
                                string newName = shortcutName.replace("\n", " ").replace("\r", " ");
                                Logic.ComposeDeck.moveWebAppProfile(oldName, newName);
                            } else {
                                oldProfileName = oldName;
                            }
                        }
                    } catch (Error e) {
                        // Best effort; save proceeds.
                    }
                }

                content = Logic.ComposeDeck.buildOwnBrowserShortcut(browser, shortcutName, shortcutIcon, shortcutUrl, shortcutFileBase);
            } else {
                string safeName = shortcutName.replace("\n", " ").replace("\r", " ");
                string safeUrl = shortcutUrl.replace("\"", "%22").replace("\n", "");
                string safeIcon = shortcutIcon.replace("\n", " ").replace("\r", " ");
                content = "[Desktop Entry]\n" +
                    "Version=1.0\n" +
                    "Type=Application\n" +
                    "Name=%s\n".printf(safeName) +
                    "Comment=Open %s\n".printf(safeName) +
                    "Exec=xdg-open \"%s\"\n".printf(safeUrl) +
                    "Icon=%s\n".printf(safeIcon) +
                    "Terminal=false\n" +
                    "Categories=Network;\n";
            }

            try {
                var file = GLib.File.new_for_path(path);
                var stream = file.replace(null, false, GLib.FileCreateFlags.REPLACE_DESTINATION, null);
                var data = new uint8[content.length];
                for (int i = 0; i < content.length; i++) {
                    data[i] = (uint8) content[i];
                }
                stream.write_all(data, null);
                stream.close(null);
            } catch (Error e) {
                state.actionError = "Could not create the application shortcut.";
                state.changed();
                return;
            }

            if (oldProfileName != "" && !Logic.ComposeDeck.webAppProfileShared(oldProfileName, path)) {
                Logic.ComposeDeck.cleanupWebAppProfile(oldProfileName);
            }

            state.actionSuccess = "Shortcut saved.";
            state.changed();
        }

        private void removePortShortcut () {
            var state = Logic.Application.getState();
            string path = this.portShortcutPath();
            var file = GLib.File.new_for_path(path);
            if (!file.query_exists()) return;

            string name = "";
            bool profileMode = false;
            try {
                uint8[] raw;
                string etag;
                file.load_contents(null, out raw, out etag);
                string content = (string) raw;
                profileMode = content.contains("--application-mode");
                foreach (var line in content.split("\n")) {
                    if (line.has_prefix("Name=")) {
                        name = line.substring(5).strip();
                    }
                }
            } catch (Error e) {
                // Best effort; still remove the shortcut below.
            }

            try {
                file.delete(null);
            } catch (Error e) {
                state.actionError = "Could not remove the application shortcut.";
                state.changed();
                return;
            }

            Logic.ComposeDeck.cleanupLegacyPortalEntriesFor(
                Logic.ComposeDeck.legacySegment(this.appName, this.port));
            if (profileMode && name != "" && !Logic.ComposeDeck.webAppProfileShared(name, path)) {
                Logic.ComposeDeck.cleanupWebAppProfile(name);
            }
            state.actionSuccess = "Shortcut removed.";
            state.changed();
        }
    }
}
