using Gtk;
using Adw;
using GLib;

/*
 * Window — main window view for ComposeDeck.
 */

const string APP_NAME = "ComposeDeck";
const string VERSION = "0.1.0";

[GtkTemplate (ui = "/com/a2way/ComposeDeck/Window.ui")]
class Window : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.NavigationSplitView split_view;
    [GtkChild] private unowned Gtk.Box sidebar_box;
    [GtkChild] private unowned Gtk.Box content_box;

    private Sidebar sidebar;
    private ContentArea content_area;
    private OverviewRow overview_row;
    public AppRow? active_row { get; private set; }

    public Window (Adw.Application app) {
        set_application (app);

        /* Create partial views */
        sidebar = new Sidebar ();
        content_area = new ContentArea ();
        if (sidebar_box != null) sidebar_box.append (sidebar);
        if (content_box != null) content_box.append (content_area);

        /* No vertical separator between sidebar and content (GNOME Settings has none in expanded mode) */
        sidebar.add_css_class ("sidebar");
        try {
            var css = new Gtk.CssProvider ();
            css.load_from_string ("navigation-split-view > separator, .navigation-split-view > separator, adw-navigation-split-view > separator { min-width: 0; min-height: 0; opacity: 0; margin: 0; padding: 0; border: none; } headerbar { border: none; box-shadow: none; } .sidebar { border-right: none; box-shadow: none; }");
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        } catch (Error e) {
        }

        /* Connect signals */
        sidebar.search.changed.connect (on_search_changed);
        sidebar.list_box.row_activated.connect (on_sidebar_row_activated);

        /* Hamburger menu */
        if (sidebar.menu_button != null) {
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

            sidebar.menu_button.notify["active"].connect (() => {
                if (sidebar.menu_button.active) {
                    GLib.Idle.add (() => {
                        set_focus (null);
                        return GLib.Source.REMOVE;
                    });
                }
            });
        }

        /* Load apps into sidebar */
        GLib.Idle.add (() => {
            populate_apps ();
            select_overview ();
            return GLib.Source.REMOVE;
        });
    }

    private void on_quit_clicked () {
        close ();
    }

    private void on_about_clicked () {
        var about = new Adw.AboutDialog ();
        about.application_name = "ComposeDeck";
        about.application_icon = "com.a2way.ComposeDeck";
        about.developer_name = "a2way";
        about.version = "0.1.0";
        about.comments = "Manage Compose applications under ~/Apps/.";
        about.present (this);
    }

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
        if (row is OverviewRow) {
            sidebar.list_box.select_row (row);
            show_overview_page ();
            return;
        }

        var app_row = row as AppRow;
        if (app_row == null) {
            return;
        }
        sidebar.list_box.select_row (row);
        show_app_details (app_row);
    }

    public void populate_apps () {
        sidebar.remove_all_rows ();

        overview_row = new OverviewRow ();
        sidebar.list_box.append (overview_row);

        var apps = ComposeService.discover_apps ();
        foreach (ComposeApp app in apps) {
            sidebar.list_box.append (new AppRow (app.path, app.name, app.running));
        }
    }

    public void poll_status () {
        var child = sidebar.list_box.get_first_child ();
        while (child != null) {
            if (child is AppRow) {
                var app_row = (AppRow) child;
                app_row.update_status (ComposeService.is_running (app_row.path));
            }
            child = child.get_next_sibling ();
        }

        if (active_row != null) {
            content_area.show_app (active_row.name, active_row.path,
                                       ComposeService.is_running (active_row.path));
        }

        int total = 0;
        int running_count = 0;
        ComposeService.compute_stats (out total, out running_count);
        content_area.overview.update_stats (total, running_count);
    }

    public void show_overview_page () {
        content_area.show_overview ();
        active_row = null;

        int total = 0;
        int running_count = 0;
        ComposeService.compute_stats (out total, out running_count);
        content_area.overview.update_stats (total, running_count);
    }

    public void show_app_details (AppRow row) {
        content_area.show_app (row.name, row.path, row.is_running ());
        active_row = row;
    }

    public void select_overview () {
        sidebar.list_box.select_row (overview_row);
        show_overview_page ();
    }
}