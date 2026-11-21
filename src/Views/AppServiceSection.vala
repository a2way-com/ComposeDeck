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
        private Logic.AppService service;
        private Logic.ComposeApp app;
        private List<Adw.PreferencesRow> rows = new List<Adw.PreferencesRow> ();
        private Gtk.Window? parentWindow;

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
            string dotColor = this.service.running ? "#4CAF50" : "#F44336";
            dotLabel.set_markup ("<span foreground='%s'>●</span>".printf (dotColor));
            dotLabel.set_valign (Gtk.Align.CENTER);
            headerRow.add_prefix (dotLabel);

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

            var portsBox = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            portsBox.set_hexpand (true);
            portsBox.set_halign (Gtk.Align.END);
            portsBox.set_valign (Gtk.Align.CENTER);

            string seenKeys = "";
            int portRowCount = 0;
            foreach (var port in this.service.ports) {
                if (port.publicPort <= 0 && port.privatePort <= 0) {
                    continue;
                }
                string key = "%d:%d:%s".printf(port.publicPort, port.privatePort, port.protocol);
                if (seenKeys.index_of(key) >= 0) continue;
                seenKeys = seenKeys + key + "|";

                string proto = port.protocol != "" ? port.protocol : "tcp";
                string line = port.publicPort > 0
                    ? "%d %s (host) \u2192 %d %s".printf(port.publicPort, proto, port.privatePort, proto)
                    : "%d %s".printf(port.privatePort, proto);

                var lineBox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                lineBox.set_hexpand (true);
                lineBox.set_halign (Gtk.Align.END);

                var label = new Gtk.Label (line);
                label.set_hexpand (true);
                label.set_halign (Gtk.Align.END);
                label.set_valign (Gtk.Align.CENTER);
                label.set_xalign (1f);
                label.set_selectable (true);
                label.set_ellipsize (Pango.EllipsizeMode.END);
                label.set_css_classes (new string[] { "monospace" });

                if (port.publicPort > 0 && proto == "tcp") {
                    uint publicPort = (uint) port.publicPort;
                    string url = "http://localhost:%u".printf (publicPort);
                    label.set_tooltip_text ("%s\nClick to open %s".printf (line, url));
                    label.set_cursor_from_name ("pointer");
                    var click = new Gtk.GestureClick ();
                    click.released.connect (() => {
                        try {
                            GLib.AppInfo.launch_default_for_uri (url, null);
                        } catch (Error e) {
                            var state = Logic.Application.getState ();
                            state.actionError = "Could not open %s".printf (url);
                            state.changed ();
                        }
                    });
                    label.add_controller (click);
                } else {
                    label.set_tooltip_text (line);
                }
                lineBox.append (label);

                if (port.publicPort > 0 && proto == "tcp") {
                    uint publicPort = (uint) port.publicPort;
                    var shortcutButton = new Gtk.Button ();
                    shortcutButton.set_label (this.shortcutExists (publicPort) ? "Change shortcut" : "Add shortcut");
                    shortcutButton.set_hexpand (false);
                    shortcutButton.set_valign (Gtk.Align.CENTER);
                    shortcutButton.set_css_classes (new string[] { "flat" });
                    shortcutButton.clicked.connect (() => this.openShortcutDialog (publicPort));
                    lineBox.append (shortcutButton);
                }

                var copy = new Gtk.Button ();
                var copyIcon = new Gtk.Image ();
                copyIcon.icon_name = "edit-copy-symbolic";
                copyIcon.set_pixel_size (16);
                copy.set_child (copyIcon);
                copy.set_hexpand (false);
                copy.set_valign (Gtk.Align.CENTER);
                copy.set_css_classes (new string[] { "flat" });
                copy.set_tooltip_text ("Copy port");
                copy.clicked.connect (() => {
                    var display = Gdk.Display.get_default ();
                    var clipboard = display.get_clipboard ();
                    clipboard.set_text (line);
                });
                lineBox.append (copy);

                portsBox.append (lineBox);
                portRowCount++;
            }

            if (portRowCount > 0) {
                var portsRow = new Adw.ActionRow ();
                portsRow.set_title ("Ports");
                portsRow.set_activatable (false);
                portsRow.add_suffix (portsBox);
                group.add (portsRow);
                this.rows.append (portsRow);
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
                            int q1 = line.index_of ("\"");
                            int q2 = line.last_index_of ("\"");
                            if (q1 >= 0 && q2 > q1) {
                                url = line.substring (q1 + 1, q2 - q1 - 1);
                            }
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

            var defaultsButton = new Gtk.Button.with_label ("Set to defaults");
            defaultsButton.set_halign (Gtk.Align.START);
            defaultsButton.set_css_classes (new string[] { "flat" });
            defaultsButton.clicked.connect (() => {
                nameEntry.set_text (defaultName);
                urlEntry.set_text (defaultUrl);
                iconEntry.set_text (defaultIcon);
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
                    this.savePortShortcut (port, nameEntry.get_text ().strip (), urlEntry.get_text ().strip (), iconEntry.get_text ().strip ());
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

        private void savePortShortcut (uint port, string name, string url, string icon) {
            var state = Logic.Application.getState ();
            string shortcutName = name;
            string shortcutUrl = url;
            string shortcutIcon = icon;
            if (shortcutName == "") shortcutName = "%s — localhost:%u".printf (this.app.name, port);
            if (shortcutUrl == "") shortcutUrl = "http://localhost:%u".printf (port);
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
            string safeName = shortcutName.replace ("\n", " ").replace ("\r", " ");
            string safeUrl = shortcutUrl.replace ("\"", "%22").replace ("\n", "");
            string safeIcon = shortcutIcon.replace ("\n", " ").replace ("\r", " ");
            string content = "[Desktop Entry]\n" +
                "Version=1.0\n" +
                "Type=Application\n" +
                "Name=%s\n".printf (safeName) +
                "Comment=Open %s\n".printf (safeName) +
                "Exec=xdg-open \"%s\"\n".printf (safeUrl) +
                "Icon=%s\n".printf (safeIcon) +
                "Terminal=false\n" +
                "Categories=Network;\n";

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

            state.actionSuccess = "Shortcut saved.";
            state.changed ();
        }

        private void removePortShortcut (uint port) {
            var state = Logic.Application.getState ();
            var file = GLib.File.new_for_path (this.portShortcutPath (port));
            if (!file.query_exists ()) return;
            try {
                file.delete (null);
            } catch (Error e) {
                state.actionError = "Could not remove the application shortcut.";
                state.changed ();
                return;
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
            dialog.set_heading ("Logs — %s".printf (serviceName));

            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.set_vexpand (true);
            scrolled.set_hexpand (true);
            scrolled.set_min_content_height (400);
            scrolled.set_min_content_width (600);

            var view = new Gtk.TextView ();
            view.set_editable (false);
            view.set_cursor_visible (false);
            view.set_monospace (true);
            view.get_buffer ().set_text ("Loading logs...");
            scrolled.set_child (view);

            dialog.set_extra_child (scrolled);
            dialog.add_response ("ok", "OK");
            dialog.set_default_response ("ok");
            dialog.set_close_response ("ok");

            var top = this.parentWindow != null ? this.parentWindow : AppServiceSection.find_toplevel_window ();
            if (top != null) {
                dialog.set_transient_for (top);
                dialog.present ();
            }

            GLib.Thread.create<int> (() => {
                string? logs = Logic.ComposeService.containerLogs (containerName);
                string text = logs != null && logs != "" ? logs : "No logs available.";
                GLib.MainContext.default ().invoke (() => {
                    view.get_buffer ().set_text (text);
                    return false;
                });
                return 0;
            }, false);
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
