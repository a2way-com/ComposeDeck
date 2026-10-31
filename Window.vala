using Gtk;
using Adw;
using GLib;

/*
 * Window — main window for ComposeDeck.
 *
 * UI is defined in Window.ui (GtkBuilder XML, loaded via GResource).
 */

const string APP_NAME = "ComposeDeck";
const string VERSION = "0.1.0";
const string APPS_SUBDIR = "Apps";
[GtkTemplate (ui = "/com/a2way/ComposeDeck/Window.ui")]
class Window : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.NavigationSplitView split_view;
    [GtkChild] private unowned Adw.NavigationPage sidebar_page;
    [GtkChild] private unowned Gtk.Box content_box;
    [GtkChild] private unowned Gtk.Button quit_button;

    private Sidebar sidebar;
    private OverviewPage overview_page;
    private AppDetailsPage app_details_page;

    private OverviewRow overview_row;
    private AppRow? active_row;
    private uint refresh_timeout;

    public Window (Adw.Application app) {

        set_application (app);


        /* Create UI components */
        sidebar = new Sidebar ();
        sidebar_page.set_child (sidebar);

        overview_page = new OverviewPage ();
        app_details_page = new AppDetailsPage ();

        content_box.append (overview_page);
        content_box.append (app_details_page);

        /* Connect signals */
        sidebar.search.changed.connect (on_search_changed);
        sidebar.list_box.row_activated.connect (on_sidebar_row_activated);

        /* Load apps into sidebar */
        populate_apps ();

        /* Poll running status every 10 seconds */
        refresh_timeout = GLib.Timeout.add_seconds (10, () => {
            poll_status ();
            return true;
        });

        /* Select Overview by default */
        sidebar.list_box.select_row (overview_row);
        show_overview_page ();
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

    [GtkCallback]
    private void on_quit_clicked () {
        close ();
    }

    /* ---------- Sidebar population ---------- */

    private void populate_apps () {
        sidebar.remove_all_rows ();

        overview_row = new OverviewRow ();
        sidebar.list_box.append (overview_row);

        string home = Environment.get_home_dir ();
        string apps_dir = home + "/" + APPS_SUBDIR;

        var rows = new List<AppRow> ();

        try {
            var handle = GLib.Dir.open (apps_dir);
            string? entry;
            while ((entry = handle.read_name ()) != null) {
                if (entry == null || entry.has_prefix ("."))
                    continue;
                string path = apps_dir + "/" + entry;
                var file = GLib.File.new_for_path (path);
                if (file.query_file_type (GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS) != GLib.FileType.DIRECTORY) {
                    continue;
                }
                var yaml = GLib.File.new_for_path (path + "/compose.yaml");
                var yml = GLib.File.new_for_path (path + "/docker-compose.yaml");
                if (!yaml.query_exists () && !yml.query_exists ()) {
                    continue;
                }
                bool running = is_app_running (path);
                try {
                    rows.append (new AppRow (path, entry, running));
                } catch (Error e) {
                    continue;
                }
            }
        } catch (Error e) {
            // ~/Apps/ may not exist yet
        }

        rows.sort ((a, b) => {
            if (a.name < b.name) return -1;
            if (a.name > b.name) return 1;
            return 0;
        });

        foreach (AppRow row in rows)
            sidebar.list_box.append (row);
    }

    /* ---------- Live polling ---------- */

    private void poll_status () {
        var child = sidebar.list_box.get_first_child ();
        while (child != null) {
            if (child is AppRow) {
                var app_row = (AppRow) child;
                app_row.update_status (is_app_running (app_row.path));
            }
            child = child.get_next_sibling ();
        }

        if (active_row != null) {
            app_details_page.show_app (active_row.name, active_row.path,
                                       is_app_running (active_row.path));
        }

        int total = 0;
        int running_count = 0;
        compute_app_stats (out total, out running_count);
        overview_page.update_stats (total, running_count);
    }

    /* ---------- Page switching ---------- */

    private void show_overview_page () {
        overview_page.show ();
        app_details_page.hide ();
        active_row = null;

        int total = 0;
        int running_count = 0;
        compute_app_stats (out total, out running_count);
        overview_page.update_stats (total, running_count);
    }

    private void show_app_details (AppRow row) {
        overview_page.hide ();
        app_details_page.show_app (row.name, row.path, row.is_running ());
        active_row = row;
    }

    /* ---------- Compose environment ---------- */

    private static void setup_compose_environment () {
        string? docker_host = Environment.get_variable ("DOCKER_HOST");
        if (docker_host == null || docker_host == "") {
            string? runtime = Environment.get_variable ("XDG_RUNTIME_DIR");
            if (runtime != null) {
                string sock = runtime + "/podman/podman.sock";
                if (GLib.File.new_for_path (sock).query_exists ())
                    docker_host = "unix://" + sock;
            }
        }

        if (docker_host != null)
            Environment.set_variable ("DOCKER_HOST", docker_host, true);
    }

    /* ---------- Running detection ---------- */

    private static bool is_app_running (string path) {
        string project_name = GLib.Path.get_basename (path).down ();

        string? runtime = Environment.get_variable ("XDG_RUNTIME_DIR");
        if (runtime == null) return false;
        string sock = runtime + "/podman/podman.sock";
        if (!GLib.File.new_for_path (sock).query_exists ()) return false;

        try {
            var socket = new GLib.Socket (GLib.SocketFamily.UNIX, GLib.SocketType.STREAM, GLib.SocketProtocol.DEFAULT);
            var addr = new GLib.UnixSocketAddress (sock);
            socket.connect (addr, null);
            socket.set_timeout (5);

            string filter = "{\"label\":[\"com.docker.compose.project=" + project_name + "\"]}";
            string encoded = GLib.Uri.escape_string (filter);
            string request = "GET /containers/json?all=true&filters=" + encoded + " HTTP/1.0\r\nHost: localhost\r\n\r\n";
            var req_bytes = request.data;
            socket.send (req_bytes, null);

            var buf = new uint8[65536];
            var response = new GLib.ByteArray ();
            ssize_t n;
            while ((n = socket.receive (buf, null)) > 0) {
                response.append (buf[:n]);
            }
            response.append (new uint8[] { 0 });
            socket.close ();

            string resp = (string) response.data;
            int body_start = resp.index_of ("\r\n\r\n");
            if (body_start < 0) return false;
            string body = resp.substring (body_start + 4);
    
            var parser = new Json.Parser ();
            parser.load_from_data (body, -1);
            var root = parser.get_root ();
            if (root == null) return false;
            var array = root.get_array ();
            if (array == null) return false;

            bool any_running = false;
            for (int i = 0; i < array.get_length (); i++) {
                var obj = array.get_object_element (i);
                if (obj != null) {
                    string state = obj.get_string_member ("State");
                    if (state == "running") any_running = true;
                }
            }
            return any_running;
        } catch (Error e) {
            return false;
        }
    }

    /* ---------- Stats ---------- */

    private void compute_app_stats (out int total, out int running_count) {
        total = 0;
        running_count = 0;

        string home = Environment.get_home_dir ();
        string apps_dir = home + "/" + APPS_SUBDIR;

        try {
            var handle = GLib.Dir.open (apps_dir);
            string? entry;
            while ((entry = handle.read_name ()) != null) {
                if (entry != null && entry.has_prefix ("."))
                    continue;
                string path = apps_dir + "/" + entry;
                var file = GLib.File.new_for_path (path);
                if (file.query_file_type (GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS)
                    != GLib.FileType.DIRECTORY)
                    continue;

                var yaml = GLib.File.new_for_path (path + "/compose.yaml");
                var yml = GLib.File.new_for_path (path + "/docker-compose.yaml");
                if (!yaml.query_exists () && !yml.query_exists ())
                    continue;

                total++;
                if (is_app_running (path)) {
                    running_count++;
                }
            }
        } catch (Error e) {
            // ~/Apps/ may not exist yet
        }
    }
}
