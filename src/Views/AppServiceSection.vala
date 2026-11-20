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
        private List<Adw.PreferencesRow> rows = new List<Adw.PreferencesRow> ();
        private Gtk.Window? parentWindow;

        public AppServiceSection (Logic.AppService service, Gtk.Window? parentWindow = null) {
            this.service = service;
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

            string portsText = "";
            bool first = true;
            string seenKeys = "";
            foreach (var port in this.service.ports) {
                if (port.publicPort <= 0 && port.privatePort <= 0) {
                    continue;
                }
                string key = "%d:%d:%s".printf(port.publicPort, port.privatePort, port.protocol);
                if (seenKeys.index_of(key) >= 0) continue;
                seenKeys = seenKeys + key + "|";
                string proto = port.protocol != "" ? port.protocol : "tcp";
                string portText = port.publicPort > 0
                    ? "%d %s (host) \u2192 %d %s".printf(port.publicPort, proto, port.privatePort, proto)
                    : "%d %s".printf(port.privatePort, proto);
                if (!first) {
                    portsText = portsText + "\n";
                }
                portsText = portsText + portText;
                first = false;
            }

            if (portsText != "") {
                var portsRow = new Adw.ActionRow ();
                portsRow.set_title ("Ports");
                portsRow.set_activatable (false);

                var portsBox = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                portsBox.set_hexpand (true);
                portsBox.set_halign (Gtk.Align.END);
                portsBox.set_valign (Gtk.Align.CENTER);

                foreach (var line in portsText.split ("\n")) {
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
                    label.set_tooltip_text (line);
                    label.set_css_classes (new string[] { "monospace" });
                    lineBox.append (label);

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
                }

                portsRow.add_suffix (portsBox);

                group.add (portsRow);
                this.rows.append (portsRow);
            }
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
