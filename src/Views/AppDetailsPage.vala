using Gtk;
using GLib;
using Logic;

namespace Views {
    /*
     * AppDetailsPage — app details page partial: icon, name, path, status.
     * Always stays in sync with the selected app coming from State.
     * UI is defined in AppDetailsPage.ui (GTK blueprint, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/AppDetailsPage.ui")]
    [CCode (cname = "AppDetailsPage")]
    public class AppDetailsPage : Gtk.Box {
        [GtkChild] private unowned Gtk.Label pathLabel;
        [GtkChild] private unowned Gtk.Label statusLabel;

        private Logic.State state;

        public AppDetailsPage () {
            this.state = Logic.Application.getState();
            this.state.changed.connect(this.render);
            this.render();
        }

        private void render () {
            var selected = this.state.selectedApp;
            if (selected == null) {
                this.set_visible(false);
                return;
            }
            this.set_visible(true);

            this.pathLabel.set_text(selected.path);

            string dotColor = selected.running ? "#4CAF50" : "#F44336";
            string statusText = selected.running ? "Running" : "Stopped";
            string markup = "<span foreground='%s' size='large'>●</span> %s".printf(dotColor, statusText);
            this.statusLabel.set_markup(markup);
        }
    }
}
