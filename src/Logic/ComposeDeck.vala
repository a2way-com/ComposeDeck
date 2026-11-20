using Gtk;
using Adw;
using GLib;
using Views;

namespace Logic {
    public class ComposeDeck {
        public const string APP_ID = "com.a2way.ComposeDeck";
        public const string APP_NAME = "ComposeDeck";
        public const string VERSION = "0.1.0";
        public const string DEVELOPER_NAME = "a2way";
        public const string APPS_SUBDIR = "Apps";

        // Strip // and /* */ comments from a JSONC document so it can be
        // parsed by Json.Parser.
        public static string strip_jsonc_comments (string text) {
            var result = new StringBuilder ();
            int i = 0;
            while (i < text.length) {
                if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '/') {
                    while (i < text.length && text[i] != '\n') i++;
                } else if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '*') {
                    i += 2;
                    while (i + 1 < text.length && !(text[i] == '*' && text[i + 1] == '/')) i++;
                    i += 2;
                } else {
                    result.append_c (text[i]);
                    i++;
                }
            }
            return result.str;
        }

        private static State state;
        private static int64 lastPoll = 0;

        public static void start (State state) {
            ComposeDeck.state = state;

            ComposeDeck.state.selectedApp = null;
            discoverApps();
            ComposeDeck.lastPoll = GLib.get_monotonic_time() / 1000 / 1000;

            Timeout.add_seconds(1, () => {
                int64 now = GLib.get_monotonic_time() / 1000 / 1000;
                if (now - ComposeDeck.lastPoll >= ComposeDeck.state.refreshInterval) {
                    ComposeDeck.lastPoll = now;
                    discoverApps();
                }
                return true;
            });
        }

        /*
         * Blocking discovery: scans ~/Apps/ and queries podman for every app.
         * Runs off the GTK main thread when called from startApp/stopApp/restartApp;
         * runs on the main thread when called from start() and the poll timer.
         */
        private static void fetchApps (out List<ComposeApp> apps) {
            apps = new List<ComposeApp> ();
            string appsDir = ComposeDeck.state.appsDir;

            // Probe podman once; if it's unreachable every app looks empty.
            ComposeDeck.state.podmanReachable = ComposeService.ensureService();
            ComposeDeck.state.lastUpdated = GLib.get_monotonic_time() / 1000 / 1000;

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

                    string[] composeNames = {
                        "compose.yaml", "compose.yml",
                        "docker-compose.yaml", "docker-compose.yml"
                    };
                    bool hasCompose = false;
                    foreach (var composeName in composeNames) {
                        if (File.new_for_path(path + "/" + composeName).query_exists()) {
                            hasCompose = true;
                            break;
                        }
                    }
                    if (!hasCompose)
                        continue;

                    bool anyRunning = false;
                    string projectName = ComposeDeck.composeProjectName (path);
                    var services = ComposeService.listServices(path, projectName, out anyRunning);
                    int runningCount = 0;
                    foreach (var svc in services) {
                        if (svc.running) runningCount++;
                    }
                    var app = new ComposeApp(entry, path, anyRunning);
                    app.runningCount = runningCount;
                    app.serviceCount = (int) services.length();
                    app.services = (owned) services;
                    app.services.sort ((a, b) => {
                        if (a.name < b.name) return -1;
                        if (a.name > b.name) return 1;
                        return 0;
                    });
                    apps.append(app);
                }
            } catch (Error e) {
                // ~/Apps/ may not exist yet
            }

            apps.sort((a, b) => {
                if (a.name < b.name) return -1;
                if (a.name > b.name) return 1;
                return 0;
            });
        }

        /*
         * Reads the top-level "name:" from the compose file, falling back to
         * the folder name. Podman labels containers with this project name.
         */
        private static string composeProjectName (string path) {
            string fallback = GLib.Path.get_basename(path).down();
            string[] composeNames = {
                "compose.yaml", "compose.yml",
                "docker-compose.yaml", "docker-compose.yml"
            };
            string? filePath = null;
            foreach (var composeName in composeNames) {
                string candidate = path + "/" + composeName;
                if (File.new_for_path(candidate).query_exists ()) {
                    filePath = candidate;
                    break;
                }
            }
            if (filePath == null) return fallback;

            try {
                uint8[] raw;
                string etag;
                File.new_for_path(filePath).load_contents (null, out raw, out etag);
                string text = (string) raw;
                foreach (var rawLine in text.split ("\n")) {
                    if (rawLine.length == 0) continue;
                    // Only top-level keys: no leading whitespace.
                    if (rawLine[0] == ' ' || rawLine[0] == '\t') continue;
                    if (!rawLine.has_prefix ("name")) continue;
                    int colon = rawLine.index_of (":");
                    if (colon < 0) continue;
                    if (rawLine.substring (0, colon).strip () != "name") continue;
                    string value = rawLine.substring (colon + 1).strip ();
                    int comment = value.index_of (" #");
                    if (comment >= 0) value = value.substring (0, comment).strip ();
                    if (value.length >= 2) {
                        if ((value[0] == '"' && value[value.length - 1] == '"') ||
                            (value[0] == '\'' && value[value.length - 1] == '\'')) {
                            value = value.substring (1, value.length - 2);
                        }
                    }
                    if (value != "") return value;
                }
            } catch (Error e) {
                // Fall back to the folder name.
            }
            return fallback;
        }

        public static void discoverApps () {
            List<ComposeApp> apps;
            fetchApps (out apps);
            ComposeDeck.state.apps = (owned) apps;
            string? selectedPath = (ComposeDeck.state.selectedApp != null) ? ComposeDeck.state.selectedApp.path : null;
            if (selectedPath != null) {
                ComposeApp? found = null;
                foreach (var app in ComposeDeck.state.apps) {
                    if (app.path == selectedPath) { found = app; break; }
                }
                ComposeDeck.state.selectedApp = found;
            }
            ComposeDeck.state.changed();
        }

        /*
         * Marks a user-triggered app action as running. The details page
         * renders its spinner and button visibility from this flag.
         */
        private static void beginAppAction () {
            ComposeDeck.state.actionInProgress = true;
            ComposeDeck.state.actionError = null;
            ComposeDeck.state.actionSuccess = null;
            ComposeDeck.state.changed();
        }

        /*
         * Refreshes app state after an action and clears the in-progress
         * flag. The flag is held for a minimum time so that fast local
         * podman actions still produce visible feedback.
         */
        private static void finishAppAction (int64 startedAt, string? error = null, string? success = null) {
            List<ComposeApp> apps;
            fetchApps (out apps);

            GLib.MainContext.default ().invoke (() => {
                ComposeDeck.state.apps = (owned) apps;
                ComposeDeck.state.actionError = error;
                ComposeDeck.state.actionSuccess = success;
                string? selectedPath = (ComposeDeck.state.selectedApp != null) ? ComposeDeck.state.selectedApp.path : null;
                if (selectedPath != null) {
                    ComposeApp? found = null;
                    foreach (var candidate in ComposeDeck.state.apps) {
                        if (candidate.path == selectedPath) { found = candidate; break; }
                    }
                    ComposeDeck.state.selectedApp = found;
                }

                int64 elapsedMs = (GLib.get_monotonic_time() - startedAt) / 1000;
                int64 minVisibleMs = 700;
                if (elapsedMs < minVisibleMs) {
                    GLib.Timeout.add ((uint) (minVisibleMs - elapsedMs), () => {
                        ComposeDeck.state.actionInProgress = false;
                        ComposeDeck.state.changed();
                        return false;
                    });
                } else {
                    ComposeDeck.state.actionInProgress = false;
                    ComposeDeck.state.changed();
                }
                return false;
            });
        }

        /*
         * Builds a single-line toast message for the services whose action
         * failed, or returns null when every action succeeded.
         */
        private static string? formatFailures (string verb, List<string> failed) {
            if (failed.length() == 0) return null;

            var names = new StringBuilder ();
            foreach (var name in failed) {
                if (names.len > 0) names.append(", ");
                names.append(name);
            }
            return "Failed to %s: %s".printf (verb, names.str);
        }

        public static void startApp (ComposeApp app) {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                foreach (var service in app.services) {
                    if (!service.running && !ComposeService.startContainer (service.containerName)) {
                        failed.append (service.name);
                    }
                }
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("start", failed));
                return 0;
            }, false);
        }

        public static void stopApp (ComposeApp app) {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                foreach (var service in app.services) {
                    if (service.running && !ComposeService.stopContainer (service.containerName)) {
                        failed.append (service.name);
                    }
                }
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("stop", failed));
                return 0;
            }, false);
        }

        public static void restartApp (ComposeApp app) {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                foreach (var service in app.services) {
                    if (!ComposeService.restartContainer (service.containerName)) {
                        failed.append (service.name);
                    }
                }
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("restart", failed));
                return 0;
            }, false);
        }

        public static void startAllApps () {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                int affected = 0;
                foreach (var app in ComposeDeck.state.apps) {
                    bool changed = false;
                    foreach (var service in app.services) {
                        if (!service.running) {
                            if (ComposeService.startContainer (service.containerName)) {
                                changed = true;
                            } else {
                                failed.append (service.name);
                            }
                        }
                    }
                    if (changed) affected++;
                }
                string? success = affected > 0
                    ? "Started %d app%s".printf (affected, affected == 1 ? "" : "s")
                    : null;
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("start", failed), success);
                return 0;
            }, false);
        }

        public static void stopAllApps () {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                int affected = 0;
                foreach (var app in ComposeDeck.state.apps) {
                    bool changed = false;
                    foreach (var service in app.services) {
                        if (service.running) {
                            if (ComposeService.stopContainer (service.containerName)) {
                                changed = true;
                            } else {
                                failed.append (service.name);
                            }
                        }
                    }
                    if (changed) affected++;
                }
                string? success = affected > 0
                    ? "Stopped %d app%s".printf (affected, affected == 1 ? "" : "s")
                    : null;
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("stop", failed), success);
                return 0;
            }, false);
        }

        public static void restartAllApps () {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                int affected = 0;
                foreach (var app in ComposeDeck.state.apps) {
                    bool changed = false;
                    foreach (var service in app.services) {
                        if (ComposeService.restartContainer (service.containerName)) {
                            changed = true;
                        } else {
                            failed.append (service.name);
                        }
                    }
                    if (changed) affected++;
                }
                string? success = affected > 0
                    ? "Restarted %d app%s".printf (affected, affected == 1 ? "" : "s")
                    : null;
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("restart", failed), success);
                return 0;
            }, false);
        }


    }
}
