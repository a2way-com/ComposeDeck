using Gtk;

namespace Views {
    /*
     * AppDetailsPage — app details page partial: icon, name, path, status.
     * UI is defined in AppDetailsPage.ui(GtkBuilder XML, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/AppDetailsPage.ui")]
    [CCode (cname = "AppDetailsPage")]
    public class AppDetailsPage : Gtk.Box {
        [GtkChild] private unowned Gtk.Label pathLabel;
        [GtkChild] private unowned Gtk.Label statusLabel;

        public AppDetailsPage () {
        }

        public void showApp (string name, string path, bool running) {
            this.set_visible(true);

            this.pathLabel.set_text(path);

            string dotColor = running ? "#4CAF50" : "#F44336";
            string statusText = running ? "Running" : "Stopped";
            this.statusLabel.set_markup("<span foreground='%s' size='large'>●</span> %s"
                                     .printf(dotColor, statusText));
        }

        public void hide () {
            this.set_visible(false);
        }
    }
}
