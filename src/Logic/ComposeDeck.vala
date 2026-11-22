using Gtk;
using Adw;
using GLib;
using Views;

namespace Logic {
    public class ComposeDeck {
        public const string APP_ID = "com.a2way.ComposeDeck";
        public const string APP_NAME = "ComposeDeck";
        public const string VERSION = "0.2.0";
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

            var browser = WebAppBrowser.resolve (state.webAppBrowser);
            if (browser == null) {
                browser = WebAppBrowser.resolve ("");
            }
            if (browser != null && browser.id != state.webAppBrowser) {
                state.webAppBrowser = browser.id;
                state.saveSettings ();
                ComposeDeck.rewriteAppShortcuts ();
            } else if (browser == null && state.webAppBrowser != "") {
                state.webAppBrowser = "";
                state.saveSettings ();
            }

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

                    // Include services declared in the compose file but with
                    // no container yet, so they can be surfaced and created.
                    var declared = ComposeDeck.composeDeclaredServices (path);
                    var declaredNames = new HashTable<string, bool> (str_hash, str_equal);
                    foreach (var def in declared) declaredNames.insert (def.name, true);

                    // Containers whose service is no longer in the compose
                    // file are orphans; keep them visible until removed.
                    int orphanCount = 0;
                    foreach (var svc in services) {
                        if (declared.length() == 0 || svc.containerName == "")
                            continue;
                        if (declaredNames.contains (svc.name))
                            continue;
                        svc.orphan = true;
                        orphanCount++;
                    }

                    var existingNames = new HashTable<string, bool> (str_hash, str_equal);
                    foreach (var svc in services) existingNames.insert (svc.name, true);
                    foreach (var def in declared) {
                        if (!existingNames.contains (def.name)) {
                            services.append (def);
                        }
                    }

                    int runningCount = 0;
                    foreach (var svc in services) {
                        if (svc.running) runningCount++;
                    }
                    var app = new ComposeApp(entry, path, anyRunning);
                    app.projectName = projectName;
                    app.runningCount = runningCount;
                    app.serviceCount = (int) services.length();
                    app.orphanCount = orphanCount;
                    app.services = (owned) services;
                    app.services.sort ((a, b) => {
                        if (a.name < b.name) return -1;
                        if (a.name > b.name) return 1;
                        return 0;
                    });

                    // Reorder by compose file order; unknown services stay
                    // in the alphabetical fallback order.
                    var declaredOrder = ComposeDeck.composeServiceOrder (path);
                    if (declaredOrder.length() > 0) {
                        var ordered = new List<AppService> ();
                        var used = new HashTable<string, bool> (str_hash, str_equal);
                        foreach (var name in declaredOrder) {
                            foreach (var svc in app.services) {
                                if (svc.name == name && !used.contains (name)) {
                                    ordered.append (svc);
                                    used.insert (name, true);
                                    break;
                                }
                            }
                        }
                        foreach (var svc in app.services) {
                            if (!used.contains (svc.name)) ordered.append (svc);
                        }
                        app.services = (owned) ordered;
                    }

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

        /*
         * Returns service names in the order they appear under the top-level
         * "services:" key of the compose file.
         */
        private static GLib.List<string> composeServiceOrder (string path) {
            var order = new GLib.List<string> ();
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
            if (filePath == null) return order;

            try {
                uint8[] raw;
                string etag;
                File.new_for_path(filePath).load_contents (null, out raw, out etag);
                string text = (string) raw;
                bool inServices = false;
                int serviceIndent = -1;
                foreach (var line in text.split ("\n")) {
                    string trimmed = line.strip ();
                    if (trimmed == "" || trimmed.has_prefix ("#")) continue;

                    int indent = 0;
                    while (indent < line.length && line[indent] == ' ') indent++;

                    if (!inServices) {
                        if (line.has_prefix ("services:")) inServices = true;
                        continue;
                    }
                    if (indent == 0) break;
                    if (serviceIndent < 0) serviceIndent = indent;
                    if (indent != serviceIndent) continue;

                    int colon = trimmed.index_of (":");
                    if (colon <= 0) continue;
                    string name = trimmed.substring (0, colon).strip ();
                    if (name == "" || name.has_prefix ("#")) continue;
                    order.append (name);
                }
            } catch (Error e) {
                // Fall back to alphabetical order.
            }
            return order;
        }

        /*
         * Returns services declared under the top-level "services:" key,
         * with their image. They represent containers that do not exist yet.
         */
        private static GLib.List<AppService> composeDeclaredServices (string path) {
            var result = new GLib.List<AppService> ();
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
            if (filePath == null) return result;

            try {
                uint8[] raw;
                string etag;
                File.new_for_path(filePath).load_contents (null, out raw, out etag);
                string text = (string) raw;
                bool inServices = false;
                int serviceIndent = -1;
                AppService? current = null;
                foreach (var line in text.split ("\n")) {
                    string trimmed = line.strip ();
                    if (trimmed == "" || trimmed.has_prefix ("#")) continue;

                    int indent = 0;
                    while (indent < line.length && line[indent] == ' ') indent++;

                    if (!inServices) {
                        if (line.has_prefix ("services:")) inServices = true;
                        continue;
                    }
                    if (indent == 0) break;
                    if (serviceIndent < 0) serviceIndent = indent;

                    if (indent == serviceIndent) {
                        int colon = trimmed.index_of (":");
                        if (colon <= 0) continue;
                        string name = trimmed.substring (0, colon).strip ();
                        if (name == "") continue;
                        current = new AppService (name, false);
                        current.statusText = "Not created";
                        result.append (current);
                    } else if (current != null && indent > serviceIndent && trimmed.has_prefix ("image:")) {
                        current.image = trimmed.substring (6).strip ();
                    }
                }
            } catch (Error e) {
                // Ignore; no declared services.
            }
            return result;
        }

        /*
         * Builds a managed shortcut entry that opens the URL in app mode.
         */
        public static string buildOwnBrowserShortcut (WebAppBrowser browser, string name, string icon, string url, string fileBase) {
            string safeName = name.replace ("\n", " ").replace ("\r", " ");
            string safeUrl = url.replace ("\"", "%22").replace ("\n", "");
            string safeIcon = icon.replace ("\n", " ").replace ("\r", " ");

            string execLine;
            string wmClass = "";
            if (browser.profileMode) {
                execLine = browser.buildExec (safeUrl, fileBase);
                wmClass = browser.profilePrefix + GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA1, safeName);
            } else {
                execLine = browser.buildExec (safeUrl, "");
            }

            string content = "[Desktop Entry]\n" +
                "Version=1.0\n" +
                "Type=Application\n" +
                "Name=%s\n".printf (safeName) +
                "Comment=Open %s\n".printf (safeName) +
                "Exec=%s\n".printf (execLine) +
                "Icon=%s\n".printf (safeIcon) +
                "Terminal=false\n" +
                "Categories=Network;\n" +
                "X-ComposeDeck-OpenInOwnBrowser=true\n";
            if (wmClass != "") {
                content += "StartupWMClass=%s\n".printf (wmClass);
            }
            return content;
        }

        /*
         * Directories that may contain GNOME Web app profiles.
         */
        private static string[] profileBases () {
            string home = Environment.get_home_dir ();
            return {
                home + "/.local/share",
                home + "/.cache",
                home + "/.config",
                home + "/.var/app/org.gnome.Epiphany/data",
                home + "/.var/app/org.gnome.Epiphany/cache",
                home + "/.var/app/org.gnome.Epiphany/config",
                home + "/.var/app/org.gnome.Ephemeral/data",
                home + "/.var/app/org.gnome.Ephemeral/cache",
                home + "/.var/app/org.gnome.Ephemeral/config"
            };
        }

        /*
         * Builds the legacy app/port segment used by the old portal layout.
         */
        public static string legacySegment (string appName, uint port) {
            string lower = appName.down ();
            var safe = new StringBuilder ();
            for (int i = 0; i < lower.length; i++) {
                char ch = lower[i];
                if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) {
                    safe.append_c (ch);
                } else {
                    safe.append_c ('_');
                }
            }
            return safe.str + "_" + port.to_string ();
        }

        private static void deleteRecursively (File file) {
            try {
                if (file.query_file_type (GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null) != GLib.FileType.DIRECTORY) {
                    file.delete (null);
                    return;
                }
                var enumerator = file.enumerate_children (
                    "standard::name,standard::type",
                    GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
                GLib.FileInfo? info;
                while ((info = enumerator.next_file (null)) != null) {
                    var child = file.get_child (info.get_name ());
                    if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                        ComposeDeck.deleteRecursively (child);
                    } else {
                        try {
                            child.delete (null);
                        } catch (Error e) {
                            // Ignore individual files.
                        }
                    }
                }
                enumerator.close (null);
                file.delete (null);
            } catch (Error e) {
                // Ignore.
            }
        }

        /*
         * Removes legacy portal files and profiles for one app/port.
         */
        public static void cleanupLegacyPortalEntriesFor (string segment) {
            string home = Environment.get_home_dir ();
            string[] dirs = {
                home + "/.local/share/applications",
                home + "/.local/share/xdg-desktop-portal/applications"
            };
            string[] prefixes = {
                "org.gnome.Epiphany.WebApp_",
                "org.gnome.Ephemeral.WebApp_"
            };

            foreach (var dirPath in dirs) {
                foreach (var prefix in prefixes) {
                    var file = File.new_for_path (dirPath + "/" + prefix + "composedeck_" + segment + ".desktop");
                    if (!file.query_exists ()) continue;
                    try {
                        file.delete (null);
                    } catch (Error e) {
                        // Ignore.
                    }
                }
            }

            foreach (var baseDir in ComposeDeck.profileBases ()) {
                foreach (var prefix in prefixes) {
                    var profile = File.new_for_path (baseDir + "/" + prefix + "composedeck_" + segment);
                    if (profile.query_exists ()) {
                        ComposeDeck.deleteRecursively (profile);
                    }
                }
            }
        }

        /*
         * Whether another managed shortcut still uses the same web app name.
         */
        public static bool webAppProfileShared (string name, string excludePath) {
            if (name == "") return false;
            string dirPath = Environment.get_home_dir () + "/.local/share/applications";
            try {
                var handle = Dir.open (dirPath);
                string? entry;
                while ((entry = handle.read_name ()) != null) {
                    if (!entry.has_prefix ("composedeck-") || !entry.has_suffix (".desktop")) continue;
                    string path = dirPath + "/" + entry;
                    if (path == excludePath) continue;
                    uint8[] raw;
                    string etag;
                    try {
                        File.new_for_path (path).load_contents (null, out raw, out etag);
                    } catch (Error e) {
                        continue;
                    }
                    string other = (string) raw;
                    if (!other.contains ("X-ComposeDeck-OpenInOwnBrowser=true")) continue;
                    if (!other.contains ("--application-mode")) continue;
                    foreach (var line in other.split ("\n")) {
                        if (line.has_prefix ("Name=") && line.substring (5).strip () == name) {
                            return true;
                        }
                    }
                }
            } catch (Error e) {
                // Treat as not shared.
            }
            return false;
        }

        /*
         * Removes the GNOME Web profile for a shortcut name.
         */
        public static void cleanupWebAppProfile (string name) {
            if (name == "") return;
            string hash = GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA1, name);
            string[] prefixes = {
                "org.gnome.Epiphany.WebApp_",
                "org.gnome.Ephemeral.WebApp_"
            };
            foreach (var baseDir in ComposeDeck.profileBases ()) {
                foreach (var prefix in prefixes) {
                    var profile = File.new_for_path (baseDir + "/" + prefix + hash);
                    if (profile.query_exists ()) {
                        ComposeDeck.deleteRecursively (profile);
                    }
                }
            }
        }

        /*
         * Removes desktop entries left by the old GNOME Web portal layout.
         */
        public static void cleanupLegacyPortalEntries () {
            string home = Environment.get_home_dir ();
            string[] dirs = {
                home + "/.local/share/applications",
                home + "/.local/share/xdg-desktop-portal/applications"
            };
            string[] prefixes = {
                "org.gnome.Epiphany.WebApp_composedeck_",
                "org.gnome.Ephemeral.WebApp_composedeck_"
            };

            foreach (var dirPath in dirs) {
                try {
                    var handle = Dir.open (dirPath);
                    string? entry;
                    while ((entry = handle.read_name ()) != null) {
                        bool match = false;
                        foreach (var prefix in prefixes) {
                            if (entry.has_prefix (prefix)) {
                                match = true;
                                break;
                            }
                        }
                        if (!match) continue;
                        try {
                            File.new_for_path (dirPath + "/" + entry).delete (null);
                        } catch (Error e) {
                            // Ignore individual failures.
                        }
                    }
                } catch (Error e) {
                    // Directory may not exist.
                }
            }

            foreach (var baseDir in ComposeDeck.profileBases ()) {
                try {
                    var handle = Dir.open (baseDir);
                    string? entry;
                    while ((entry = handle.read_name ()) != null) {
                        bool match = false;
                        foreach (var prefix in prefixes) {
                            if (entry.has_prefix (prefix)) {
                                match = true;
                                break;
                            }
                        }
                        if (match) {
                            ComposeDeck.deleteRecursively (File.new_for_path (baseDir + "/" + entry));
                        }
                    }
                } catch (Error e) {
                    // Directory may not exist.
                }
            }
        }

        /*
         * Moves GNOME Web profile data when a shortcut's name changes.
         */
        public static void moveWebAppProfile (string oldName, string newName) {
            if (oldName == "" || newName == "" || oldName == newName) return;

            string oldHash = GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA1, oldName);
            string newHash = GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA1, newName);
            string[] prefixes = {
                "org.gnome.Epiphany.WebApp_",
                "org.gnome.Ephemeral.WebApp_"
            };
            foreach (var baseDir in ComposeDeck.profileBases ()) {
                foreach (var prefix in prefixes) {
                    var oldProfile = File.new_for_path (baseDir + "/" + prefix + oldHash);
                    var newProfile = File.new_for_path (baseDir + "/" + prefix + newHash);
                    if (!oldProfile.query_exists () || newProfile.query_exists ()) continue;
                    try {
                        oldProfile.move (newProfile, GLib.FileCopyFlags.NONE, null, null);
                    } catch (Error e) {
                        // Leave the old profile in place.
                    }
                }
            }
        }

        /*
         * Extracts the last quoted URL from a desktop Exec line.
         */
        public static string extractExecUrl (string line) {
            string last = "";
            int pos = 0;
            while (true) {
                int q1 = line.index_of ("\"", pos);
                if (q1 < 0) break;
                int q2 = line.index_of ("\"", q1 + 1);
                if (q2 < 0) break;
                last = line.substring (q1 + 1, q2 - q1 - 1);
                pos = q2 + 1;
            }
            int http = last.index_of ("http://");
            if (http < 0) http = last.index_of ("https://");
            if (http > 0) last = last.substring (http);
            return last;
        }

        /*
         * Rewrites all ComposeDeck-managed shortcuts that open in app mode
         * so they use the currently selected browser.
         */
        public static int rewriteAppShortcuts () {
            var state = ComposeDeck.state;
            var browser = WebAppBrowser.resolve (state.webAppBrowser);
            if (browser == null) {
                state.actionError = "No app-mode browser is available for the existing shortcuts.";
                state.changed ();
                return 0;
            }

            ComposeDeck.cleanupLegacyPortalEntries ();
            string dirPath = Environment.get_home_dir () + "/.local/share/applications";
            int updated = 0;

            try {
                var handle = Dir.open (dirPath);
                string? entry;
                while ((entry = handle.read_name ()) != null) {
                    if (!entry.has_prefix ("composedeck-") || !entry.has_suffix (".desktop")) continue;
                    string path = dirPath + "/" + entry;

                    uint8[] raw;
                    string etag;
                    try {
                        File.new_for_path (path).load_contents (null, out raw, out etag);
                    } catch (Error e) {
                        continue;
                    }
                    string content = (string) raw;
                    if (!content.contains ("X-ComposeDeck-OpenInOwnBrowser=true")) continue;

                    string name = "";
                    string icon = "";
                    string url = "";
                    foreach (var line in content.split ("\n")) {
                        if (line.has_prefix ("Name=")) {
                            name = line.substring (5).strip ();
                        } else if (line.has_prefix ("Icon=")) {
                            icon = line.substring (5).strip ();
                        } else if (line.has_prefix ("Exec=")) {
                            url = ComposeDeck.extractExecUrl (line);
                        }
                    }
                    if (url == "") continue;
                    if (name == "") name = entry.substring (0, entry.length - 8);

                    string fileBase = entry.substring (0, entry.length - 8);
                    string newContent = ComposeDeck.buildOwnBrowserShortcut (browser, name, icon, url, fileBase);
                    if (newContent == content) continue;

                    try {
                        var file = File.new_for_path (path);
                        var stream = file.replace (null, false, GLib.FileCreateFlags.REPLACE_DESTINATION, null);
                        var data = new uint8[newContent.length];
                        for (int i = 0; i < newContent.length; i++) {
                            data[i] = (uint8) newContent[i];
                        }
                        stream.write_all (data, null);
                        stream.close (null);
                        if (!browser.profileMode && content.contains ("--application-mode") && name != ""
                            && !ComposeDeck.webAppProfileShared (name, path)) {
                            ComposeDeck.cleanupWebAppProfile (name);
                        }
                        updated++;
                    } catch (Error e) {
                        // Leave this shortcut unchanged.
                    }
                }
            } catch (Error e) {
                state.actionError = "Could not update the existing shortcuts.";
                state.changed ();
                return 0;
            }

            if (updated > 0) {
                state.actionSuccess = "Updated %d shortcut%s.".printf (updated, updated == 1 ? "" : "s");
                state.changed ();
            }
            return updated;
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
                bool changed = false;

                bool hasMissing = false;
                foreach (var service in app.services) {
                    if (service.containerName == "") {
                        hasMissing = true;
                        break;
                    }
                }

                if (hasMissing) {
                    changed = ComposeService.composeUp (app.path);
                    if (!changed) failed.append (app.name);
                } else {
                    foreach (var service in app.services) {
                        if (!service.running) {
                            if (ComposeService.startContainer (service.containerName)) {
                                changed = true;
                            } else {
                                failed.append (service.name);
                            }
                        }
                    }
                }

                string? success = changed ? "Started %s".printf (app.name) : null;
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("start", failed), success);
                return 0;
            }, false);
        }

        public static void stopApp (ComposeApp app) {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
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
                string? success = changed ? "Stopped %s".printf (app.name) : null;
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("stop", failed), success);
                return 0;
            }, false);
        }

        public static void restartApp (ComposeApp app) {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                bool changed = false;
                foreach (var service in app.services) {
                    if (ComposeService.restartContainer (service.containerName)) {
                        changed = true;
                    } else {
                        failed.append (service.name);
                    }
                }
                string? success = changed ? "Restarted %s".printf (app.name) : null;
                ComposeDeck.finishAppAction (startedAt, ComposeDeck.formatFailures ("restart", failed), success);
                return 0;
            }, false);
        }

        /*
         * Removes containers belonging to this app's project that are no
         * longer declared in its compose file.
         */
        public static void removeOrphans (ComposeApp app) {
            if (ComposeDeck.state.actionInProgress) return;
            ComposeDeck.beginAppAction();

            int64 startedAt = GLib.get_monotonic_time();
            GLib.Thread.create<int> (() => {
                var failed = new List<string> ();
                int removed = 0;
                int orphanCount = 0;

                var declared = ComposeDeck.composeDeclaredServices(app.path);
                var declaredNames = new HashTable<string, bool> (str_hash, str_equal);
                foreach (var def in declared) declaredNames.insert(def.name, true);

                // An empty declaration list means the compose file could not
                // be parsed; never treat every container as an orphan then.
                if (declared.length() > 0) {
                    bool anyRunning = false;
                    var services = ComposeService.listServices(app.path, app.projectName, out anyRunning);
                    foreach (var service in services) {
                        if (service.containerName == "") continue;
                        if (declaredNames.contains(service.name)) continue;
                        orphanCount++;
                        if (ComposeService.removeContainer(service.containerName)) {
                            removed++;
                        } else {
                            failed.append(service.name);
                        }
                    }
                }

                string? error = ComposeDeck.formatFailures("remove", failed);
                string? success = null;
                if (orphanCount == 0) {
                    success = "No orphan containers found in %s".printf(app.name);
                } else if (removed > 0) {
                    success = "Removed %d orphan%s from %s".printf(
                        removed, removed == 1 ? "" : "s", app.name);
                }
                ComposeDeck.finishAppAction(startedAt, error, success);
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
