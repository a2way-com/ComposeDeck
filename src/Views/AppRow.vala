using Gtk;
using GLib;
using Logic;

namespace Views {
    /*
     * AppRow — sidebar row showing an indicator dot + Compose App name.
     * UI is defined in AppRow.ui (GTK blueprint, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/AppRow.ui")]
    [CCode (cname = "AppRow")]
    public class AppRow : Gtk.ListBoxRow {
        public ComposeApp app { get; set; }

        [GtkChild] private unowned Gtk.Label indicator;
        [GtkChild] private unowned Gtk.Label nameLabel;

        public AppRow (ComposeApp app) {
            this.app = app;

            string dotColor = this.app.running ? "#4CAF50" : "#F44336";
            this.indicator.set_markup("<span foreground='%s' size='large'>●</span>".printf(dotColor));
            this.nameLabel.set_text(this.app.name);
        }

    }
}
