using Gtk;
using GLib;
using Views;

namespace Logic {
    /*
     * ComposeDeck — pure business logic and orchestration (manipulates views).
     */

    public class ComposeDeck {
        public const string APP_ID = "com.a2way.ComposeDeck";
        public const string APP_NAME = "ComposeDeck";
        public const string VERSION = "0.1.0";
        public const string DEVELOPER_NAME = "a2way";
        public const string APPS_SUBDIR = "Apps";

        private static Views.Window? window;
        private static uint poll_timeout;

        public static void start (Views.Window w) {
            window = w;
            if (window == null) return;
            populate (window);
            select_overview (window);
            poll_timeout = GLib.Timeout.add_seconds (10, () => {
                poll (window);
                return true;
            });
        }

        /* ---- Business logic ---- */

        public static List<ComposeApp> discover_apps () {
            var apps = new List<ComposeApp> ();
            string home = Environment.get_home_dir ();
            string apps_dir = home + "/" + APPS_SUBDIR;

            try {
                var handle = Dir.open (apps_dir);
                string? entry;
                while ((entry = handle.read_name ()) != null) {
                    if (entry == null || entry.has_prefix ("."))
                        continue;
                    string path = apps_dir + "/" + entry;
                    var file = File.new_for_path (path);
                    if (file.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS) != FileType.DIRECTORY)
                        continue;

                    var yaml = File.new_for_path (path + "/compose.yaml");
                    var yml = File.new_for_path (path + "/docker-compose.yaml");
                    if (!yaml.query_exists () && !yml.query_exists ())
                        continue;

                    bool running = ComposeService.is_running (path);
                    apps.append (new ComposeApp (entry, path, running));
                }
            } catch (Error e) {
                // ~/Apps/ may not exist yet
            }

            apps.sort ((a, b) => {
                if (a.name < b.name) return -1;
                if (a.name > b.name) return 1;
                return 0;
            });
            return apps;
        }

        public static void compute_stats (out int total, out int running_count) {
            total = 0;
            running_count = 0;

            string home = Environment.get_home_dir ();
            string apps_dir = home + "/" + APPS_SUBDIR;

            try {
                var handle = Dir.open (apps_dir);
                string? entry;
                while ((entry = handle.read_name ()) != null) {
                    if (entry == null || entry.has_prefix ("."))
                        continue;
                    string path = apps_dir + "/" + entry;
                    var file = File.new_for_path (path);
                    if (file.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS) != FileType.DIRECTORY)
                        continue;

                    var yaml = File.new_for_path (path + "/compose.yaml");
                    var yml = File.new_for_path (path + "/docker-compose.yaml");
                    if (!yaml.query_exists () && !yml.query_exists ())
                        continue;

                    total++;
                    if (ComposeService.is_running (path)) {
                        running_count++;
                    }
                }
            } catch (Error e) {
                // ~/Apps/ may not exist yet
            }
        }

        /* ---- Orchestration (manipulates views) ---- */

        public static void populate (Views.Window window) {
            if (window == null || window.sidebar == null) return;
            window.sidebar.remove_all_rows ();

            window.overview_row = new OverviewRow ();
            window.sidebar.list_box.append (window.overview_row);

            var apps = discover_apps ();
            foreach (ComposeApp app in apps) {
                window.sidebar.list_box.append (new AppRow (app.path, app.name, app.running));
            }
        }

        public static void poll (Views.Window window) {
            if (window == null || window.sidebar == null) return;

            var child = window.sidebar.list_box.get_first_child ();
            while (child != null) {
                if (child is AppRow) {
                    var app_row = (AppRow) child;
                    app_row.update_status (ComposeService.is_running (app_row.path));
                }
                child = child.get_next_sibling ();
            }

            if (window.active_row != null) {
                window.content_area.show_app (window.active_row.name, window.active_row.path,
                                             ComposeService.is_running (window.active_row.path));
            }

            int total = 0;
            int running_count = 0;
            compute_stats (out total, out running_count);
            window.content_area.overview.update_stats (total, running_count);
        }

        public static void show_overview (Views.Window window) {
            if (window == null || window.content_area == null) return;
            window.content_area.show_overview ();
            window.active_row = null;

            int total = 0;
            int running_count = 0;
            compute_stats (out total, out running_count);
            window.content_area.overview.update_stats (total, running_count);
        }

        public static void show_app_details (Views.Window window, AppRow row) {
            if (window == null || window.content_area == null) return;
            window.content_area.show_app (row.name, row.path, row.is_running ());
            window.active_row = row;
        }

        public static void handle_row_activated (Views.Window window, Gtk.ListBoxRow row) {
            if (window == null || window.sidebar == null) return;
            if (row is OverviewRow) {
                window.sidebar.list_box.select_row (row);
                show_overview (window);
                return;
            }

            var app_row = row as AppRow;
            if (app_row == null) {
                return;
            }
            window.sidebar.list_box.select_row (app_row);
            show_app_details (window, app_row);
        }

        public static void select_overview (Views.Window window) {
            if (window == null || window.overview_row == null || window.sidebar == null) return;
            window.sidebar.list_box.select_row (window.overview_row);
            show_overview (window);
        }

    }
}
