using Gtk;
using GLib;

/*
 * AppRow — sidebar row showing an indicator dot + Compose App name.
 * UI is defined in AppRow.ui (GtkBuilder XML, loaded via GResource).
 */

[GtkTemplate (ui = "/com/a2way/ComposeDeck/AppRow.ui")]
class AppRow : Gtk.ListBoxRow {
    public string path { get; set; }
    public new string name { get; set; }
    private bool running;

    [GtkChild] private unowned Gtk.Label indicator;
    [GtkChild] private unowned Gtk.Label name_label;

    public AppRow (string path, string name, bool running) {
        this.path = path;
        this.name = name;
        this.running = running;

        update_status (running);
        name_label.set_text (name);
    }

    public void update_status (bool running) {
        this.running = running;
        string dot_color = running ? "#4CAF50" : "#F44336";
        indicator.set_markup ("<span foreground='%s' size='large'>●</span>".printf (dot_color));
    }

    public bool is_running () {
        return running;
    }
}
