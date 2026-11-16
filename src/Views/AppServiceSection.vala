using Gtk;
using Adw;
using GLib;
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

        public AppServiceSection (Logic.AppService service) {
            this.service = service;
        }

        public unowned List<Adw.PreferencesRow> get_rows () {
            return this.rows;
        }

        public void add_to (Adw.PreferencesGroup group) {
            var headerRow = new Adw.ActionRow ();
            headerRow.set_activatable (false);
            headerRow.set_title (this.service.name);
            headerRow.set_subtitle (this.service.running ? "Running" : "Stopped");

            var dotLabel = new Gtk.Label (null);
            string dotColor = this.service.running ? "#4CAF50" : "#F44336";
            dotLabel.set_markup ("<span foreground='%s'>●</span>".printf (dotColor));
            dotLabel.set_valign (Gtk.Align.CENTER);
            headerRow.add_prefix (dotLabel);

            group.add (headerRow);
            this.rows.append (headerRow);

            if (this.service.image != "") {
                var imageRow = new Adw.ActionRow ();
                imageRow.set_title ("Image");
                imageRow.set_activatable (false);
                var imageValue = new Gtk.Label (this.service.image);
                imageValue.selectable = true;
                imageValue.xalign = 1f;
                imageRow.add_suffix (imageValue);

                group.add (imageRow);
                this.rows.append (imageRow);
            }

            string portsText = "";
            bool first = true;
            foreach (var port in this.service.ports) {
                if (port.publicPort <= 0 && port.privatePort <= 0) {
                    continue;
                }
                string proto = port.protocol != "" ? port.protocol : "tcp";
                string portText = port.publicPort > 0
                    ? "%d %s (host) \u2192 %d %s".printf (port.publicPort, proto, port.privatePort, proto)
                    : "%d %s".printf (port.privatePort, proto);
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
                var portsValue = new Gtk.Label (portsText);
                portsValue.selectable = true;
                portsValue.xalign = 1f;
                portsValue.set_wrap (true);
                portsValue.set_justify (Gtk.Justification.RIGHT);
                portsRow.add_suffix (portsValue);

                group.add (portsRow);
                this.rows.append (portsRow);
            }
        }
    }
}
