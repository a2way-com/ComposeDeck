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

        private Logic.State state;

        public Sidebar () {
            this.state = Logic.Application.getState();

            this.search.changed.connect(this.onSearchChanged);
            this.listBox.row_activated.connect(this.onRowActivated);
            this.state.changed.connect(this.render);
        }

        private void onSearchChanged (Gtk.Editable editable) {
            var entry = (Gtk.SearchEntry) editable;
            string term = entry.get_text().down();
            this.listBox.set_filter_func((row) => {
                if (row is OverviewRow) return true;
                var appRow = row as AppRow;
                if (appRow == null) return true;
                return appRow.app.name.down().contains(term) ||
                       appRow.app.path.down().contains(term);
            });
            this.listBox.invalidate_filter();
        }

        private void onRowActivated (Gtk.ListBox box, Gtk.ListBoxRow row) {
            if (row is OverviewRow) {
                this.state.selectOverview();
                return;
            }
            var appRow = row as AppRow;
            if (appRow != null) {
                this.state.selectApp(appRow.app.path);
            }
        }

        public void removeAllRows () {
            var child = this.listBox.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                this.listBox.remove(child);
                child = next;
            }
        }

        private void render () {
            this.removeAllRows();

            var overviewRow = new OverviewRow();
            this.listBox.append(overviewRow);

            foreach (var app in this.state.apps) {
                this.listBox.append(new AppRow(app));
            }

            if (this.state.overviewSelected) {
                this.listBox.select_row(overviewRow);
            } else if (this.state.selectedPath != null) {
                var child = this.listBox.get_first_child();
                while (child != null) {
                    if (child is AppRow) {
                        var appRow = (AppRow) child;
                        if (appRow.app.path == this.state.selectedPath) {
                            this.listBox.select_row(appRow);
                            break;
                        }
                    }
                    child = child.get_next_sibling();
                }
            }
        }
    }
}