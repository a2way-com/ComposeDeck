using Gtk;
using Adw;
using GLib;
using Gdk;
using Logic;

namespace Views {
    /*
     * AppServiceSection — one service's rows inside the "Services" area.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/AppServiceSection.ui")]
    [CCode (cname = "AppServiceSection")]
    public class AppServiceSection : Adw.PreferencesGroup {
        private static GLib.HashTable<string, bool> expandedStates =
            new GLib.HashTable<string, bool> (str_hash, str_equal);

        private Logic.AppService service;
        private Logic.ComposeApp app;
        private Gtk.Window? parentWindow;

        [GtkChild] private unowned Adw.ActionRow headerRow;
        [GtkChild] private unowned Gtk.Button logsButton;
        [GtkChild] private unowned Adw.ActionRow imageRow;
        [GtkChild] private unowned Gtk.Label imageValue;
        [GtkChild] private unowned Gtk.Button imageCopy;
        [GtkChild] private unowned Adw.ActionRow containerRow;
        [GtkChild] private unowned Gtk.Label containerValue;
        [GtkChild] private unowned Gtk.Button containerCopy;
        [GtkChild] private unowned Adw.ExpanderRow portsExpander;

        public AppServiceSection (Logic.AppService service, Logic.ComposeApp app, Gtk.Window? parentWindow = null) {
            this.service = service;
            this.app = app;
            this.parentWindow = parentWindow;

            this.populateHeader ();
            this.populateImageRow ();
            this.populateContainerRow ();
            this.populatePorts ();
        }

        private void populateHeader () {
            this.headerRow.set_title (this.service.name);
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
                subtitle = "%s · <span foreground='%s'>%s</span>".printf (subtitle, hColor, this.service.healthStatus);
                this.headerRow.set_use_markup (true);
            }
            this.headerRow.set_subtitle (subtitle);

            var dotLabel = new Gtk.Label (null);
            string dotColor = this.service.running
                ? "#4CAF50"
                : (this.service.statusText == "Not created" ? "#9E9E9E" : "#F44336");
            dotLabel.set_markup ("<span foreground='%s'>●</span>".printf (dotColor));
            dotLabel.set_valign (Gtk.Align.CENTER);
            this.headerRow.add_prefix (dotLabel);

            this.logsButton.set_visible (this.service.containerName != "");
            this.logsButton.clicked.connect (() => {
                var dialog = new LogsDialog (this.service.containerName, this.service.name, this.parentWindow);
                dialog.present ();
            });
        }

        private void populateImageRow () {
            if (this.service.image == "") return;

            this.imageRow.set_visible (true);
            this.imageValue.set_text (this.service.image);
            this.imageValue.set_tooltip_text (this.service.image);
            this.imageCopy.clicked.connect (() => {
                var display = Gdk.Display.get_default ();
                display.get_clipboard ().set_text (this.service.image);
            });
        }

        private void populateContainerRow () {
            if (this.service.containerName == "") return;

            this.containerRow.set_visible (true);
            this.containerValue.set_text (this.service.containerName);
            this.containerCopy.clicked.connect (() => {
                var display = Gdk.Display.get_default ();
                display.get_clipboard ().set_text (this.service.containerName);
            });
        }

        private void populatePorts () {
            var ports = new List<AppPort> ();
            string seenKeys = "";
            foreach (var port in this.service.ports) {
                if (port.publicPort <= 0 && port.privatePort <= 0) continue;
                string key = "%d:%d:%s".printf (port.publicPort, port.privatePort, port.protocol);
                if (seenKeys.index_of (key) >= 0) continue;
                seenKeys = seenKeys + key + "|";
                ports.append (port);
            }

            // Stable ordering so rows don't jump between refreshes.
            ports.sort ((a, b) => {
                if (a.privatePort != b.privatePort) return a.privatePort - b.privatePort;
                if (a.publicPort != b.publicPort) return a.publicPort - b.publicPort;
                return strcmp (a.protocol, b.protocol);
            });

            int mappingCount = (int) ports.length ();
            if (mappingCount == 0) return;

            this.portsExpander.set_visible (true);
            this.portsExpander.set_subtitle ("%d mapping%s".printf (mappingCount, mappingCount == 1 ? "" : "s"));

            string stateKey = this.app.path + "::" + this.service.name;
            bool expanded = false;
            if (AppServiceSection.expandedStates.contains (stateKey)) {
                expanded = AppServiceSection.expandedStates.get (stateKey);
            }
            this.portsExpander.set_expanded (expanded);
            this.portsExpander.notify["expanded"].connect (() => {
                AppServiceSection.expandedStates.insert (stateKey, this.portsExpander.get_expanded ());
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
            this.portsExpander.add_row (tableBox);
        }
    }
}
