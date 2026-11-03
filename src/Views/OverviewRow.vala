using Gtk;

namespace Views {
    /*
     * OverviewRow — sidebar row for the Overview entry.
     * UI is defined in OverviewRow.ui(GtkBuilder XML, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OverviewRow.ui")]
    [CCode (cname = "OverviewRow")]
    public class OverviewRow : Gtk.ListBoxRow {
    }
}
