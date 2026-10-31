using Gtk;
using Adw;

/*
 * Sidebar — full sidebar partial including header (title + hamburger menu),
 * search entry and app list. Extends Adw.ToolbarView so it owns its own
 * header bar (GNOME Settings style full-height sidebar).
 */

[GtkTemplate (ui = "/com/a2way/ComposeDeck/Sidebar.ui")]
class Sidebar : Gtk.Box {
    [GtkChild] public unowned Gtk.SearchEntry search;
    [GtkChild] public unowned Gtk.ListBox list_box;
    [GtkChild] public unowned Gtk.MenuButton menu_button;

    public Sidebar () {
    }

    public void remove_all_rows () {
        if (list_box == null) return;
        var child = list_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            list_box.remove (child);
            child = next;
        }
    }
}