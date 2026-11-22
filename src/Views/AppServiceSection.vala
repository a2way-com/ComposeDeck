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
            if (this.service.orphan) {
                subtitle = "Orphan container · " + subtitle;
            }
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
                        shortcutButton.set_label (ShortcutEditor.exists (this.app.name, publicPort) ? "Change shortcut" : "Add shortcut");
                        shortcutButton.set_hexpand (false);
                        shortcutButton.set_valign (Gtk.Align.CENTER);
                        shortcutButton.set_css_classes (new string[] { "flat" });
                        shortcutButton.clicked.connect (() => {
                            var dialog = new ShortcutEditor (this.app.name, publicPort, this.parentWindow);
                            dialog.present ();
                        });
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
