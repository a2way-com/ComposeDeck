using Gtk;
using Adw;
using GLib;
using Views;

namespace Logic {
    /*
     * ComposeDeck — business logic + orchestration, operating views through State.
     */

    public class ComposeDeck {
        public const string APP_ID = "com.a2way.ComposeDeck";
        public const string APP_NAME = "ComposeDeck";
        public const string VERSION = "0.1.0";
        public const string DEVELOPER_NAME = "a2way";
        public const string APPS_SUBDIR = "Apps";

        private static State state;

        public static void start (State s) {
            state = s;

            state.selectOverview();
            discoverApps();
            // timer
            Timeout.add_seconds(10, () => {
                discoverApps(); // running flags refreshed
                return true;
            });
        }

        /* ----
         * Pure business logic
         */

        public static void discoverApps () {
            var apps = new List<ComposeApp> ();
            string home = Environment.get_home_dir();
            string appsDir = home + "/" + APPS_SUBDIR;

            try {
                var handle = Dir.open(appsDir);
                string? entry;
                while ((entry = handle.read_name()) != null) {
                    if (entry == null || entry.has_prefix("."))
                        continue;
                    string path = appsDir + "/" + entry;
                    var file = File.new_for_path(path);
                    if (file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS) != FileType.DIRECTORY)
                        continue;

                    var yaml = File.new_for_path(path + "/compose.yaml");
                    var yml = File.new_for_path(path + "/docker-compose.yaml");
                    if (!yaml.query_exists() && !yml.query_exists())
                        continue;

                    bool running = ComposeService.isRunning(path);
                    apps.append(new ComposeApp(entry, path, running));
                }
            } catch (Error e) {
                // ~/Apps/ may not exist yet
            }

            apps.sort((a, b) => {
                if (a.name < b.name) return -1;
                if (a.name > b.name) return 1;
                return 0;
            });
            state.setAppList((owned) apps);
        }

        public static void computeStats (List<ComposeApp> apps, out int total, out int runningCount) {
            total = 0;
            runningCount = 0;
            if (apps == null) return;
            foreach (var app in apps) {
                total++;
                if (app.running) runningCount++;
            }
        }

        /* ----
         * UI orchestration triggered by views
         */

        public static void selectOverview (State state) {
            if (state != null) state.selectOverview();
        }

        public static void selectApp (State state, AppRow row) {
            if (state != null && row != null) state.selectApp(row.app);
        }
    }
}
