using Gtk;
using Adw;
using GLib;
using Gdk;
using Pango;
using Logic;

namespace Views {
    /*
     * AppServiceSection — builds one service's rows inside the "Services"
     * Adw.PreferencesGroup. The rows are tracked so they can be removed on re-render.
     */

    [CCode (cname = "AppServiceSection")]
    public class AppServiceSection : GLib.Object {
        private static GLib.HashTable<string, bool> expandedStates =
            new GLib.HashTable<string, bool> (str_hash, str_equal);

        private Logic.AppService service;
        private Logic.ComposeApp app;
        private List<Adw.PreferencesRow> rows = new List<Adw.PreferencesRow> ();
        private Gtk.Window? parentWindow;
        private int logsGeneration = 0;

        public AppServiceSection (Logic.AppService service, Logic.ComposeApp app, Gtk.Window? parentWindow = null) {
            this.service = service;
            this.app = app;
            this.parentWindow = parentWindow;
        }

        public unowned List<Adw.PreferencesRow> get_rows () {
            return this.rows;
        }

        public void add_to (Adw.PreferencesGroup group) {
            var headerRow = new Adw.ActionRow ();
            headerRow.set_activatable (false);
            headerRow.set_title (this.service.name);
            string subtitle = this.service.statusText != ""
                ? this.service.statusText
                : (this.service.running ? "Running" : "Stopped");
            if (this.service.healthStatus != "") {
                string hColor = this.service.healthStatus == "healthy" ? "#4CAF50"
                    : this.service.healthStatus == "unhealthy" ? "#F44336"
                    : "#FFA500";
                subtitle = "%s · <span foreground='%s'>%s</span>".printf(subtitle, hColor, this.service.healthStatus);
                headerRow.set_use_markup (true);
            }
            headerRow.set_subtitle (subtitle);

            var dotLabel = new Gtk.Label (null);
            string dotColor = this.service.running
                ? "#4CAF50"
                : (this.service.statusText == "Not created" ? "#9E9E9E" : "#F44336");
            dotLabel.set_markup ("<span foreground='%s'>●</span>".printf (dotColor));
            dotLabel.set_valign (Gtk.Align.CENTER);
            headerRow.add_prefix (dotLabel);

            if (this.service.containerName != "") {
                var logsButton = new Gtk.Button ();
                var logsIcon = new Gtk.Image ();
                logsIcon.icon_name = "utilities-terminal-symbolic";
                logsIcon.set_pixel_size (16);
                logsButton.set_child (logsIcon);
                logsButton.set_hexpand (false);
                logsButton.set_valign (Gtk.Align.CENTER);
                logsButton.set_css_classes (new string[] { "flat" });
                logsButton.set_tooltip_text ("Show logs");
                logsButton.clicked.connect (() => {
                    this.showLogsDialog ();
                });
                headerRow.add_suffix (logsButton);
            }

            group.add (headerRow);
            this.rows.append (headerRow);

            if (this.service.image != "") {
                var imageRow = new Adw.ActionRow ();
                imageRow.set_title ("Image");
                imageRow.set_activatable (false);
                var imageValue = new Gtk.Label (this.service.image);
                imageValue.selectable = true;
                imageValue.xalign = 1f;
                imageValue.set_hexpand (true);
                imageValue.set_halign (Gtk.Align.END);
                imageValue.set_ellipsize (Pango.EllipsizeMode.END);
                imageValue.set_tooltip_text (this.service.image);
                imageRow.add_suffix (imageValue);

                var imageCopy = new Gtk.Button ();
                var imageIcon = new Gtk.Image ();
                imageIcon.icon_name = "edit-copy-symbolic";
                imageIcon.set_pixel_size (16);
                imageCopy.set_child (imageIcon);
                imageCopy.set_hexpand (false);
                imageCopy.set_valign (Gtk.Align.CENTER);
                imageCopy.set_css_classes (new string[] { "flat" });
                imageCopy.set_tooltip_text ("Copy image");
                imageCopy.clicked.connect (() => {
                    var display = Gdk.Display.get_default ();
                    var clipboard = display.get_clipboard ();
                    clipboard.set_text (this.service.image);
                });
                imageRow.add_suffix (imageCopy);

                group.add (imageRow);
                this.rows.append (imageRow);
            }

            if (this.service.containerName != "") {
                var containerRow = new Adw.ActionRow ();
                containerRow.set_title ("Container");
                containerRow.set_activatable (false);
                var containerValue = new Gtk.Label (this.service.containerName);
                containerValue.selectable = true;
                containerValue.xalign = 1f;
                containerValue.set_hexpand (true);
                containerValue.set_halign (Gtk.Align.END);
                containerRow.add_suffix (containerValue);

                var containerCopy = new Gtk.Button ();
                var containerIcon = new Gtk.Image ();
                containerIcon.icon_name = "edit-copy-symbolic";
                containerIcon.set_pixel_size (16);
                containerCopy.set_child (containerIcon);
                containerCopy.set_hexpand (false);
                containerCopy.set_valign (Gtk.Align.CENTER);
                containerCopy.set_css_classes (new string[] { "flat" });
                containerCopy.set_tooltip_text ("Copy container name");
                containerCopy.clicked.connect (() => {
                    var display = Gdk.Display.get_default ();
                    var clipboard = display.get_clipboard ();
                    clipboard.set_text (this.service.containerName);
                });
                containerRow.add_suffix (containerCopy);

                group.add (containerRow);
                this.rows.append (containerRow);
            }

            var ports = new List<AppPort> ();
            string seenKeys = "";
            foreach (var port in this.service.ports) {
                if (port.publicPort <= 0 && port.privatePort <= 0) continue;
                string key = "%d:%d:%s".printf(port.publicPort, port.privatePort, port.protocol);
                if (seenKeys.index_of(key) >= 0) continue;
                seenKeys = seenKeys + key + "|";
                ports.append (port);
            }

            // Stable ordering so rows don't jump between refreshes.
            ports.sort ((a, b) => {
                if (a.privatePort != b.privatePort) return a.privatePort - b.privatePort;
                if (a.publicPort != b.publicPort) return a.publicPort - b.publicPort;
                return strcmp (a.protocol, b.protocol);
            });

            int mappingCount = (int) ports.length();
            if (mappingCount > 0) {
                var portsExpander = new Adw.ExpanderRow ();
                portsExpander.set_title ("Ports");
                portsExpander.set_subtitle ("%d mapping%s".printf (mappingCount, mappingCount == 1 ? "" : "s"));

                string stateKey = this.app.path + "::" + this.service.name;
                bool expanded = false;
                if (AppServiceSection.expandedStates.contains (stateKey)) {
                    expanded = AppServiceSection.expandedStates.get (stateKey);
                }
                portsExpander.set_expanded (expanded);
                portsExpander.notify["expanded"].connect (() => {
                    AppServiceSection.expandedStates.insert (stateKey, portsExpander.get_expanded ());
                });

                var tableBox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                tableBox.set_margin_top (6);
                tableBox.set_margin_bottom (12);
                tableBox.set_margin_start (16);
                tableBox.set_margin_end (16);

                var grid = new Gtk.Grid ();
                grid.set_column_spacing (16);
                grid.set_row_spacing (6);
                grid.set_halign (Gtk.Align.START);

                var hostHeader = new Gtk.Label ("Host");
                hostHeader.set_css_classes (new string[] { "caption", "dim-label" });
                hostHeader.set_xalign (0f);
                grid.attach (hostHeader, 0, 0, 1, 1);

                var containerHeader = new Gtk.Label ("Container");
                containerHeader.set_css_classes (new string[] { "caption", "dim-label" });
                containerHeader.set_xalign (0f);
                grid.attach (containerHeader, 1, 0, 1, 1);

                var protocolHeader = new Gtk.Label ("Protocol");
                protocolHeader.set_css_classes (new string[] { "caption", "dim-label" });
                protocolHeader.set_xalign (0f);
                grid.attach (protocolHeader, 2, 0, 1, 1);

                int rowIndex = 1;
                foreach (var port in ports) {
                    string proto = port.protocol != "" ? port.protocol : "tcp";
                    uint publicPort = port.publicPort > 0 ? (uint) port.publicPort : 0;
                    bool canOpen = publicPort > 0 && proto == "tcp";

                    if (publicPort > 0) {
                        var hostBox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                        hostBox.set_halign (Gtk.Align.START);
                        hostBox.set_valign (Gtk.Align.CENTER);

                        var hostLabel = new Gtk.Label ("%u".printf (publicPort));
                        hostLabel.set_css_classes (new string[] { "monospace" });
                        hostLabel.set_selectable (true);
                        hostBox.append (hostLabel);

                        if (canOpen) {
                            string url = "http://localhost:%u".printf (publicPort);
                            var openButton = new Gtk.Button ();
                            var openIcon = new Gtk.Image ();
                            openIcon.icon_name = "web-browser-symbolic";
                            openIcon.set_pixel_size (16);
                            openButton.set_child (openIcon);
                            openButton.set_hexpand (false);
                            openButton.set_valign (Gtk.Align.CENTER);
                            openButton.set_css_classes (new string[] { "flat" });
                            openButton.set_tooltip_text ("Open %s".printf (url));
                            openButton.clicked.connect (() => {
                                try {
                                    GLib.AppInfo.launch_default_for_uri (url, null);
                                } catch (Error e) {
                                    var state = Logic.Application.getState ();
                                    state.actionError = "Could not open %s".printf (url);
                                    state.changed ();
                                }
                            });
                            hostBox.append (openButton);
                        }
                        grid.attach (hostBox, 0, rowIndex, 1, 1);
                    } else {
                        var hostLabel = new Gtk.Label ("—");
                        hostLabel.set_css_classes (new string[] { "dim-label" });
                        hostLabel.set_xalign (0f);
                        grid.attach (hostLabel, 0, rowIndex, 1, 1);
                    }

                    var containerLabel = new Gtk.Label ("%d".printf (port.privatePort));
                    containerLabel.set_css_classes (new string[] { "monospace" });
                    containerLabel.set_xalign (0f);
                    containerLabel.set_selectable (true);
                    grid.attach (containerLabel, 1, rowIndex, 1, 1);

                    var protocolLabel = new Gtk.Label (proto);
                    protocolLabel.set_css_classes (new string[] { "monospace" });
                    protocolLabel.set_xalign (0f);
                    protocolLabel.set_selectable (true);
                    grid.attach (protocolLabel, 2, rowIndex, 1, 1);

                    var actionsBox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                    actionsBox.set_halign (Gtk.Align.END);
                    actionsBox.set_valign (Gtk.Align.CENTER);

                    if (canOpen) {
                        var shortcutButton = new Gtk.Button ();
                        shortcutButton.set_label (this.shortcutExists (publicPort) ? "Change shortcut" : "Add shortcut");
                        shortcutButton.set_hexpand (false);
                        shortcutButton.set_valign (Gtk.Align.CENTER);
                        shortcutButton.set_css_classes (new string[] { "flat" });
                        shortcutButton.clicked.connect (() => this.openShortcutDialog (publicPort));
                        actionsBox.append (shortcutButton);
                    }

                    grid.attach (actionsBox, 3, rowIndex, 1, 1);
                    rowIndex++;
                }

                tableBox.append (grid);
                portsExpander.add_row (tableBox);
                group.add (portsExpander);
                this.rows.append (portsExpander);
            }
        }

        private string portShortcutPath (uint port) {
            string baseName = "%s-%u".printf (this.app.name, port).down ();
            var safe = new StringBuilder ();
            for (int i = 0; i < baseName.length; i++) {
                char ch = baseName[i];
                if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '.') {
                    safe.append_c (ch);
                } else {
                    safe.append_c ('-');
                }
            }
            // Use the host data dir: inside Flatpak, XDG_DATA_HOME points at
            // the sandbox-private ~/.var/app/<id>/data.
            return Environment.get_home_dir () + "/.local/share/applications/composedeck-" + safe.str + ".desktop";
        }

        private bool shortcutExists (uint port) {
            return GLib.File.new_for_path (this.portShortcutPath (port)).query_exists ();
        }

        private void openShortcutDialog (uint port) {
            bool exists = this.shortcutExists (port);
            string defaultName = "%s — localhost:%u".printf (this.app.name, port);
            string defaultUrl = "http://localhost:%u".printf (port);
            string defaultIcon = "com.a2way.ComposeDeck";

            string name = defaultName;
            string url = defaultUrl;
            string icon = defaultIcon;
            bool ownBrowser = false;

            if (exists) {
                try {
                    uint8[] raw;
                    string etag;
                    GLib.File.new_for_path (this.portShortcutPath (port)).load_contents (null, out raw, out etag);
                    foreach (var line in ((string) raw).split ("\n")) {
                        if (line.has_prefix ("Name=")) {
                            name = line.substring (5).strip ();
                        } else if (line.has_prefix ("Icon=")) {
                            icon = line.substring (5).strip ();
                        } else if (line.has_prefix ("Exec=")) {
                            url = Logic.ComposeDeck.extractExecUrl (line);
                        } else if (line.has_prefix ("X-ComposeDeck-OpenInOwnBrowser=")) {
                            int eq = line.index_of ("=");
                            if (eq >= 0) ownBrowser = line.substring (eq + 1).strip () == "true";
                        }
                    }
                } catch (Error e) {
                    // Fall back to defaults.
                }
            }

            var dialog = new Adw.MessageDialog (null, exists ? "Shortcut options" : "Add shortcut", null);
            dialog.set_transient_for (this.parentWindow);
            dialog.set_modal (true);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var nameEntry = new Gtk.Entry ();
            nameEntry.set_placeholder_text ("Name");
            nameEntry.set_text (name);
            var urlEntry = new Gtk.Entry ();
            urlEntry.set_placeholder_text ("URL");
            urlEntry.set_text (url);
            var iconBox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var iconPreview = new Gtk.Image ();
            iconPreview.set_pixel_size (24);
            var iconEntry = new Gtk.Entry ();
            iconEntry.set_placeholder_text ("Icon name or image");
            iconEntry.set_hexpand (true);
            iconEntry.set_text (icon);
            var chooseIcon = new Gtk.Button.with_label ("Choose…");
            chooseIcon.set_hexpand (false);
            chooseIcon.set_valign (Gtk.Align.CENTER);
            iconBox.append (iconPreview);
            iconBox.append (iconEntry);
            iconBox.append (chooseIcon);

            this.updateIconPreview (iconPreview, icon);
            iconEntry.changed.connect (() => this.updateIconPreview (iconPreview, iconEntry.get_text ()));
            chooseIcon.clicked.connect (() => this.openIconPicker (iconEntry, iconPreview));

            box.append (nameEntry);
            box.append (urlEntry);
            box.append (iconBox);

            var ownBrowserCheck = new Gtk.CheckButton.with_label ("Open in own browser");
            ownBrowserCheck.set_active (ownBrowser);
            bool canOwnBrowser = Logic.WebAppBrowser.resolve (Logic.Application.getState ().webAppBrowser) != null;
            ownBrowserCheck.set_sensitive (canOwnBrowser || ownBrowser);
            if (!canOwnBrowser) {
                ownBrowserCheck.set_tooltip_text ("Install Chromium, Chrome, Brave, Edge, Vivaldi, or GNOME Web");
            }
            box.append (ownBrowserCheck);

            var defaultsButton = new Gtk.Button.with_label ("Set to defaults");
            defaultsButton.set_halign (Gtk.Align.START);
            defaultsButton.set_css_classes (new string[] { "flat" });
            defaultsButton.clicked.connect (() => {
                nameEntry.set_text (defaultName);
                urlEntry.set_text (defaultUrl);
                iconEntry.set_text (defaultIcon);
                ownBrowserCheck.set_active (false);
            });
            box.append (defaultsButton);

            dialog.set_extra_child (box);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", "Save");
            if (exists) {
                dialog.add_response ("remove", "Remove");
            }
            dialog.set_default_response ("save");
            dialog.set_close_response ("cancel");

            dialog.response.connect ((d, response) => {
                if (response == "save") {
                    this.savePortShortcut (port, nameEntry.get_text ().strip (), urlEntry.get_text ().strip (), iconEntry.get_text ().strip (), ownBrowserCheck.get_active ());
                } else if (response == "remove") {
                    this.removePortShortcut (port);
                }
                d.close ();
            });
            dialog.present ();
        }

        private void openIconPicker (Gtk.Entry entry, Gtk.Image preview) {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title ("Choose icon");

            var filter = new Gtk.FileFilter ();
            filter.name = "Images";
            filter.add_pattern ("*.png");
            filter.add_pattern ("*.svg");
            filter.add_pattern ("*.jpg");
            filter.add_pattern ("*.jpeg");
            filter.add_pattern ("*.webp");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            dialog.set_filters (filters);

            dialog.open.begin (this.parentWindow, null, (source, result) => {
                try {
                    var file = dialog.open.end (result);
                    if (file != null) {
                        string? path = file.get_path ();
                        if (path != null) entry.set_text (path);
                    }
                } catch (Error e) {
                    // Cancelled.
                }
            });
        }

        private void updateIconPreview (Gtk.Image preview, string icon) {
            if (icon == "") {
                preview.icon_name = "com.a2way.ComposeDeck";
                return;
            }
            if (icon.has_prefix ("/")) {
                try {
                    var texture = Gdk.Texture.from_filename (icon);
                    preview.set_from_paintable (texture);
                    return;
                } catch (Error e) {
                    // Fall back to icon name below.
                }
            }
            preview.icon_name = icon;
        }

        private void savePortShortcut (uint port, string name, string url, string icon, bool ownBrowser) {
            var state = Logic.Application.getState ();
            string shortcutName = name;
            string shortcutUrl = url;
            string shortcutIcon = icon;
            if (shortcutName == "") shortcutName = "%s — localhost:%u".printf (this.app.name, port);
            if (shortcutUrl == "") shortcutUrl = "http://localhost:%u".printf (port);
            if (shortcutUrl.index_of ("://") < 0) shortcutUrl = "http://" + shortcutUrl;
            if (shortcutIcon == "") shortcutIcon = "com.a2way.ComposeDeck";

            try {
                var dir = GLib.File.new_for_path (Environment.get_home_dir () + "/.local/share/applications");
                if (!dir.query_exists ()) {
                    dir.make_directory_with_parents (null);
                }
            } catch (Error e) {
                state.actionError = "Could not create the applications folder.";
                state.changed ();
                return;
            }

            string path = this.portShortcutPath (port);
            string shortcutFileBase = GLib.Path.get_basename (path);
            if (shortcutFileBase.has_suffix (".desktop")) {
                shortcutFileBase = shortcutFileBase.substring (0, shortcutFileBase.length - 8);
            }

            Logic.ComposeDeck.cleanupLegacyPortalEntriesFor (
                Logic.ComposeDeck.legacySegment (this.app.name, port));

            string oldProfileName = "";
            string content;
            if (ownBrowser) {
                var browser = Logic.WebAppBrowser.resolve (state.webAppBrowser);
                if (browser == null) {
                    state.actionError = "No app-mode browser found. Install Chromium, Chrome, Brave, Edge, Vivaldi, or GNOME Web.";
                    state.changed ();
                    return;
                }

                var existing = GLib.File.new_for_path (path);
                if (existing.query_exists ()) {
                    try {
                        uint8[] raw;
                        string etag;
                        existing.load_contents (null, out raw, out etag);
                        string oldContent = (string) raw;
                        if (oldContent.contains ("--application-mode")) {
                            string oldName = "";
                            foreach (var line in oldContent.split ("\n")) {
                                if (line.has_prefix ("Name=")) {
                                    oldName = line.substring (5).strip ();
                                }
                            }
                            if (browser.profileMode) {
                                string newName = shortcutName.replace ("\n", " ").replace ("\r", " ");
                                Logic.ComposeDeck.moveWebAppProfile (oldName, newName);
                            } else {
                                oldProfileName = oldName;
                            }
                        }
                    } catch (Error e) {
                        // Best effort; save proceeds.
                    }
                }

                content = Logic.ComposeDeck.buildOwnBrowserShortcut (browser, shortcutName, shortcutIcon, shortcutUrl, shortcutFileBase);
            } else {
                string safeName = shortcutName.replace ("\n", " ").replace ("\r", " ");
                string safeUrl = shortcutUrl.replace ("\"", "%22").replace ("\n", "");
                string safeIcon = shortcutIcon.replace ("\n", " ").replace ("\r", " ");
                content = "[Desktop Entry]\n" +
                    "Version=1.0\n" +
                    "Type=Application\n" +
                    "Name=%s\n".printf (safeName) +
                    "Comment=Open %s\n".printf (safeName) +
                    "Exec=xdg-open \"%s\"\n".printf (safeUrl) +
                    "Icon=%s\n".printf (safeIcon) +
                    "Terminal=false\n" +
                    "Categories=Network;\n";
            }

            try {
                var file = GLib.File.new_for_path (path);
                var stream = file.replace (null, false, GLib.FileCreateFlags.REPLACE_DESTINATION, null);
                var data = new uint8[content.length];
                for (int i = 0; i < content.length; i++) {
                    data[i] = (uint8) content[i];
                }
                stream.write_all (data, null);
                stream.close (null);
            } catch (Error e) {
                state.actionError = "Could not create the application shortcut.";
                state.changed ();
                return;
            }

            if (oldProfileName != "" && !Logic.ComposeDeck.webAppProfileShared (oldProfileName, path)) {
                Logic.ComposeDeck.cleanupWebAppProfile (oldProfileName);
            }

            state.actionSuccess = "Shortcut saved.";
            state.changed ();
        }

        private void removePortShortcut (uint port) {
            var state = Logic.Application.getState ();
            string path = this.portShortcutPath (port);
            var file = GLib.File.new_for_path (path);
            if (!file.query_exists ()) return;

            string name = "";
            bool profileMode = false;
            try {
                uint8[] raw;
                string etag;
                file.load_contents (null, out raw, out etag);
                string content = (string) raw;
                profileMode = content.contains ("--application-mode");
                foreach (var line in content.split ("\n")) {
                    if (line.has_prefix ("Name=")) {
                        name = line.substring (5).strip ();
                    }
                }
            } catch (Error e) {
                // Best effort; still remove the shortcut below.
            }

            try {
                file.delete (null);
            } catch (Error e) {
                state.actionError = "Could not remove the application shortcut.";
                state.changed ();
                return;
            }

            Logic.ComposeDeck.cleanupLegacyPortalEntriesFor (
                Logic.ComposeDeck.legacySegment (this.app.name, port));
            if (profileMode && name != "" && !Logic.ComposeDeck.webAppProfileShared (name, path)) {
                Logic.ComposeDeck.cleanupWebAppProfile (name);
            }
            state.actionSuccess = "Shortcut removed.";
            state.changed ();
        }

        private void showLogsDialog () {
            if (this.service.containerName == "") return;

            string containerName = this.service.containerName;
            string serviceName = this.service.name;

            var dialog = new Adw.MessageDialog (null, "Logs — %s".printf (serviceName), null);
            dialog.set_modal (true);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var tailDrop = new Gtk.DropDown.from_strings (new string[] { "200 lines", "1000 lines", "All" });
            tailDrop.set_selected (0);
            var refresh = this.makeLogButton ("view-refresh-symbolic", "Refresh");
            var copy = this.makeLogButton ("edit-copy-symbolic", "Copy all");
            var save = this.makeLogButton ("document-save-symbolic", "Save to file");
            controls.append (tailDrop);
            controls.append (refresh);
            controls.append (copy);
            controls.append (save);
            box.append (controls);

            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.set_vexpand (true);
            scrolled.set_hexpand (true);
            scrolled.set_min_content_height (400);
            scrolled.set_min_content_width (600);

            var view = new Gtk.TextView ();
            view.set_editable (false);
            view.set_cursor_visible (false);
            view.set_monospace (true);
            scrolled.set_child (view);
            box.append (scrolled);

            dialog.set_extra_child (box);
            dialog.add_response ("close", "Close");
            dialog.set_default_response ("close");
            dialog.set_close_response ("close");

            var top = this.parentWindow != null ? this.parentWindow : AppServiceSection.find_toplevel_window ();
            if (top != null) {
                dialog.set_transient_for (top);
            }
            dialog.present ();

            this.loadLogs (view, containerName, 200);
            tailDrop.notify["selected"].connect (() => {
                this.loadLogs (view, containerName, this.logsTailForIndex (tailDrop.get_selected ()));
            });
            refresh.clicked.connect (() => {
                this.loadLogs (view, containerName, this.logsTailForIndex (tailDrop.get_selected ()));
            });
            copy.clicked.connect (() => {
                var display = Gdk.Display.get_default ();
                display.get_clipboard ().set_text (this.logText (view));
            });
            save.clicked.connect (() => this.saveLogsToFile (view, serviceName));
        }

        private Gtk.Button makeLogButton (string iconName, string tooltip) {
            var button = new Gtk.Button ();
            var icon = new Gtk.Image ();
            icon.icon_name = iconName;
            icon.set_pixel_size (16);
            button.set_child (icon);
            button.set_hexpand (false);
            button.set_valign (Gtk.Align.CENTER);
            button.set_css_classes (new string[] { "flat" });
            button.set_tooltip_text (tooltip);
            return button;
        }

        private string logText (Gtk.TextView view) {
            var buffer = view.get_buffer ();
            Gtk.TextIter start;
            Gtk.TextIter end;
            buffer.get_start_iter (out start);
            buffer.get_end_iter (out end);
            return buffer.get_text (start, end, true);
        }

        private int logsTailForIndex (uint index) {
            switch (index) {
                case 1:
                    return 1000;
                case 2:
                    return 0;
                default:
                    return 200;
            }
        }

        private void loadLogs (Gtk.TextView view, string containerName, int tail) {
            this.logsGeneration++;
            int generation = this.logsGeneration;
            view.get_buffer ().set_text ("Loading logs...");
            GLib.Thread.create<int> (() => {
                string? logs = Logic.ComposeService.containerLogs (containerName, tail);
                string text = logs != null && logs != "" ? logs : "No logs available.";
                GLib.MainContext.default ().invoke (() => {
                    if (generation == this.logsGeneration) {
                        view.get_buffer ().set_text (text);
                    }
                    return false;
                });
                return 0;
            }, false);
        }

        private void saveLogsToFile (Gtk.TextView view, string serviceName) {
            var fileDialog = new Gtk.FileDialog ();
            fileDialog.set_title ("Save logs");
            fileDialog.set_initial_name ("%s-logs.txt".printf (serviceName));
            fileDialog.save.begin (this.parentWindow, null, (source, result) => {
                try {
                    var file = fileDialog.save.end (result);
                    if (file == null) return;
                    string text = this.logText (view);
                    var stream = file.replace (null, false, GLib.FileCreateFlags.REPLACE_DESTINATION, null);
                    var data = new uint8[text.length];
                    for (int i = 0; i < text.length; i++) {
                        data[i] = (uint8) text[i];
                    }
                    stream.write_all (data, null);
                    stream.close (null);
                    var state = Logic.Application.getState ();
                    state.actionSuccess = "Logs saved.";
                    state.changed ();
                } catch (Error e) {
                    // Cancelled.
                }
            });
        }

        private static Gtk.Window? find_toplevel_window () {
            foreach (var w in Gtk.Window.list_toplevels ()) {
                if (w is Gtk.Window && w.get_visible ()) {
                    return (Gtk.Window) w;
                }
            }
            return null;
        }
    }
}
