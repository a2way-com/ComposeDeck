using Gtk;
using GLib;
using Logic;

namespace Views {
    /*
     * AppRow — sidebar row showing an indicator dot + Compose App name.
     * UI is defined in AppRow.ui(GtkBuilder XML, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/AppRow.ui")]
    [CCode (cname = "AppRow")]
    public class AppRow : Gtk.ListBoxRow {
        public string path { get; set; }
        public new string name { get; set; }
        private bool running;

        [GtkChild] private unowned Gtk.Label indicator;
        [GtkChild] private unowned Gtk.Label nameLabel;

        public AppRow (string path, string name, bool running) {
            this.path = path;
            this.name = name;
            this.running = running;

            updateStatus(running);
            nameLabel.set_text(name);
        }

        public void updateStatus (bool running) {
            this.running = running;
            string dotColor = running ? "#4CAF50" : "#F44336";
            indicator.set_markup("<span foreground='%s' size='large'>●</span>".printf(dotColor));
        }

        public bool isRunning () {
            return running;
        }
    }
}
