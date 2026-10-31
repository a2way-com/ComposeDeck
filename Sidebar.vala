using Gtk;

/*
 * Sidebar — left sidebar partial: search entry + app list.
 * UI is defined in Sidebar.ui (GtkBuilder XML, loaded via GResource).
 */

[GtkTemplate (ui = "/com/a2way/ComposeDeck/Sidebar.ui")]
class Sidebar : Gtk.Box {
    [GtkChild] public unowned Gtk.SearchEntry search;
    [GtkChild] public unowned Gtk.ListBox list_box;

    public Sidebar () {
    }

    public void remove_all_rows () {
        var child = list_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            child.unparent ();
            child = next;
        }
    }
}
