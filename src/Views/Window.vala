using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * Window — pure GUI view for ComposeDeck.
     */

    const string APP_NAME = "ComposeDeck";
    const string VERSION = "0.1.0";

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/Window.ui")]
    [CCode (cname = "Window")]
    public class Window : Adw.ApplicationWindow {
        [GtkChild] private unowned Adw.NavigationSplitView split_view;
        [GtkChild] private unowned Gtk.Box sidebar_box;
        [GtkChild] private unowned Gtk.Box content_box;

        public Sidebar sidebar { get; private set; }
        public ContentArea content_area { get; private set; }
        public OverviewRow? overview_row { get; set; default = null; }
        public AppRow? active_row { get; set; default = null; }

        public Window (Adw.Application app) {
            set_application (app);

            /* Create partial views */
            sidebar = new Sidebar ();
            content_area = new ContentArea ();
            if (sidebar_box != null) sidebar_box.append (sidebar);
            if (content_box != null) content_box.append (content_area);

            /* Connect signals */
            sidebar.search.changed.connect (on_search_changed);
            sidebar.list_box.row_activated.connect (on_sidebar_row_activated);

            /* Hamburger menu */
            sidebar.menu_button.notify["active"].connect (() => {
                if (sidebar.menu_button.active) {
                    GLib.Idle.add (() => {
                        set_focus (null);
                        return GLib.Source.REMOVE;
                    });
                }
            });

            var menu = new GLib.Menu ();
            menu.append ("About", "win.about");
            menu.append ("Quit", "win.quit");
            sidebar.menu_button.set_menu_model (menu);

            var about_action = new GLib.SimpleAction ("about", null);
            about_action.activate.connect ((action, param) => on_about_clicked ());
            add_action (about_action);

            var quit_action = new GLib.SimpleAction ("quit", null);
            quit_action.activate.connect ((action, param) => on_quit_clicked ());
            add_action (quit_action);
        }

        /* ---------- Signal handlers ---------- */

        private void on_search_changed (Gtk.Editable editable) {
            var entry = (Gtk.SearchEntry) editable;
            string term = entry.get_text ().down ();

            sidebar.list_box.set_filter_func ((row) => {
                if (row is OverviewRow) {
                    return true;
                }
                var app_row = row as AppRow;
                if (app_row == null) {
                    return true;
                }
                return app_row.name.down ().contains (term) ||
                       app_row.path.down ().contains (term);
            });
            sidebar.list_box.invalidate_filter ();
        }

        private void on_sidebar_row_activated (Gtk.ListBox box, Gtk.ListBoxRow row) {
            ComposeDeck.handle_row_activated (this, row);
        }

        private void on_quit_clicked () {
            close ();
        }

        private void on_about_clicked () {
            var about = new Adw.AboutDialog ();
            about.application_name = ComposeDeck.APP_NAME;
            about.application_icon = "com.a2way.ComposeDeck";
            about.developer_name = ComposeDeck.DEVELOPER_NAME;
            about.version = ComposeDeck.VERSION;
            about.comments = "Manage Compose applications under ~/Apps/.";
            about.present (this);
        }
    }
}
