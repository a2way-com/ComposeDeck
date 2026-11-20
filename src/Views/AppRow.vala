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

            string dotColor;
            string indicatorText;
            if (app.serviceCount == 0) {
                dotColor = "#9E9E9E";
                indicatorText = "●";
            } else if (app.runningCount == app.serviceCount) {
                dotColor = "#4CAF50";
                indicatorText = "●";
            } else if (app.runningCount > 0) {
                dotColor = "#FFA500";
                indicatorText = "●";
            } else {
                dotColor = "#F44336";
                indicatorText = "●";
            }
            this.indicator.set_markup("<span foreground='%s' size='large'>%s</span>".printf(dotColor, indicatorText));
            this.nameLabel.set_text(this.app.name);

            string subtitle;
            if (app.serviceCount == 0) {
                subtitle = "Never started";
            } else if (app.runningCount == app.serviceCount) {
                subtitle = "Running";
            } else if (app.runningCount > 0) {
                subtitle = "%d of %d running".printf(app.runningCount, app.serviceCount);
            } else {
                subtitle = "All stopped";
            }
            this.nameLabel.set_tooltip_text(subtitle);
        }

    }
}
