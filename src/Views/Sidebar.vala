using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * Sidebar — view partial (full sidebar incl. header, search, app list).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/Sidebar.ui")]
    [CCode (cname = "Sidebar")]
    public class Sidebar : Gtk.Box {
        [GtkChild] public unowned Gtk.SearchEntry search;
        [GtkChild] public unowned Gtk.ListBox listBox;
        [GtkChild] public unowned Gtk.MenuButton menuButton;

        public Sidebar () {
            search.changed.connect(onSearchChanged);
            listBox.row_activated.connect(onRowActivated);
        }

        private void onSearchChanged (Gtk.Editable editable) {
            var entry = (Gtk.SearchEntry) editable;
            string term = entry.get_text().down();
            listBox.set_filter_func((row) => {
                if (row is OverviewRow) return true;
                var appRow = row as AppRow;
                if (appRow == null) return true;
                return appRow.name.down().contains(term) ||
                       appRow.path.down().contains(term);
            });
            listBox.invalidate_filter();
        }

        private void onRowActivated (Gtk.ListBox box, Gtk.ListBoxRow row) {
            var state = Logic.Application.getState();
            if (state == null) return;
            if (row is OverviewRow) {
                listBox.select_row(row);
                state.selectOverview();
                return;
            }
            var appRow = row as AppRow;
            if (appRow == null) return;
            listBox.select_row(appRow);
            state.selectApp(appRow.path);
        }

        public void removeAllRows () {
            if (listBox == null) return;
            var child = listBox.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                listBox.remove(child);
                child = next;
            }
        }
    }
}
