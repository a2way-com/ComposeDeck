using Gtk;

/*
 * AppDetailsPage — app details page partial: icon, name, path, status.
 * UI is defined in AppDetailsPage.ui (GtkBuilder XML, loaded via GResource).
 */

[GtkTemplate (ui = "/com/a2way/ComposeDeck/AppDetailsPage.ui")]
class AppDetailsPage : Gtk.Box {
    [GtkChild] private unowned Gtk.Label name_label;
    [GtkChild] private unowned Gtk.Label path_label;
    [GtkChild] private unowned Gtk.Label status_label;

    public AppDetailsPage () {
    }

    public void show_app (string name, string path, bool running) {
        set_visible (true);

        name_label.set_markup ("<b>%s</b>".printf (name));
        path_label.set_text (path);

        string dot_color = running ? "#4CAF50" : "#F44336";
        string status_text = running ? "Running" : "Stopped";
        status_label.set_markup ("<span foreground='%s' size='large'>●</span> %s"
                                 .printf (dot_color, status_text));
    }

    public void hide () {
        set_visible (false);
    }
}
