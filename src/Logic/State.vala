using GLib;
using Json;

namespace Logic {
    public class State : GLib.Object {
        public GLib.List<ComposeApp> apps = new GLib.List<ComposeApp>();
        public ComposeApp? selectedApp = null;
        public bool actionInProgress = false;
        public string? actionError = null;
        public string? actionSuccess = null;
        public bool engineReachable = true;
        public int64 lastUpdated = 0;
        public string appsDir { get; set; }
        public string containerEngine = "auto";
        public int refreshInterval = 10;
        public bool pinnedFirst = true;
        public int windowWidth = 1000;
        public int windowHeight = 700;
        public string webAppBrowser = "";
        public GLib.List<string> pinnedApps = new GLib.List<string> ();

        private const string SETTINGS_DIR = ".ComposeDeck";
        private const string SETTINGS_FILE = "settings.jsonc";

        public State () {
            this.apps = new GLib.List<ComposeApp>();
            this.selectedApp = null;
            string home = Environment.get_home_dir();
            this.appsDir = home + "/Apps";
            this.loadSettings();
        }

        public bool overviewSelected { get { return this.selectedApp == null; } }

        /*
         * Returns the pending action error, if any, and clears it so the
         * same failure is only surfaced once.
         */
        public string? consumeActionError () {
            string? error = this.actionError;
            this.actionError = null;
            return error;
        }

        /*
         * Returns the pending success message, if any, and clears it so the
         * same message is only surfaced once.
         */
        public string? consumeActionSuccess () {
            string? message = this.actionSuccess;
            this.actionSuccess = null;
            return message;
        }

        public bool isPinned (string name) {
            foreach (var pinned in this.pinnedApps) {
                if (pinned == name) return true;
            }
            return false;
        }

        public void togglePin (string name) {
            if (this.isPinned (name)) {
                var updated = new GLib.List<string> ();
                foreach (var pinned in this.pinnedApps) {
                    if (pinned != name) updated.append (pinned);
                }
                this.pinnedApps = (owned) updated;
            } else {
                this.pinnedApps.append (name);
            }
            this.saveSettings ();
        }

        private string settings_path () {
            string home = Environment.get_home_dir();
            string dir = home + "/" + SETTINGS_DIR;
            if (!GLib.File.new_for_path(dir).query_exists()) {
                try {
                    GLib.File.new_for_path(dir).make_directory();
                } catch (Error e) {
                    // Ignore; settings will be unsaved.
                }
            }
            return dir + "/" + SETTINGS_FILE;
        }

        public void loadSettings () {
            var file = GLib.File.new_for_path(this.settings_path());
            if (!file.query_exists()) return;
            try {
                uint8[] contentsRaw;
                string etag;
                file.load_contents(null, out contentsRaw, out etag);
                string contents = (string) contentsRaw;
                contents = ComposeDeck.strip_jsonc_comments(contents);
                var parser = new Json.Parser();
                parser.load_from_data(contents, -1);
                var root = parser.get_root();
                var obj = root != null ? root.get_object() : null;
                if (obj != null && obj.has_member("appsDir")) {
                    this.appsDir = obj.get_string_member("appsDir");
                }
                if (obj != null && obj.has_member("refreshInterval")) {
                    this.refreshInterval = (int) obj.get_int_member("refreshInterval");
                    if (this.refreshInterval < 1) this.refreshInterval = 10;
                }
                if (obj != null && obj.has_member("pinnedFirst")) {
                    this.pinnedFirst = obj.get_boolean_member("pinnedFirst");
                }
                if (obj != null && obj.has_member("windowWidth")) {
                    this.windowWidth = (int) obj.get_int_member("windowWidth");
                }
                if (obj != null && obj.has_member("windowHeight")) {
                    this.windowHeight = (int) obj.get_int_member("windowHeight");
                }
                if (obj != null && obj.has_member("webAppBrowser")) {
                    this.webAppBrowser = obj.get_string_member("webAppBrowser");
                }
                if (obj != null && obj.has_member("containerEngine")) {
                    string engine = obj.get_string_member("containerEngine");
                    if (engine == "podman" || engine == "docker") {
                        this.containerEngine = engine;
                    }
                }
                if (obj != null && obj.has_member("pinned")) {
                    var pinnedArray = obj.get_array_member("pinned");
                    for (int i = 0; i < pinnedArray.get_length(); i++) {
                        this.pinnedApps.append (pinnedArray.get_string_element (i));
                    }
                }
            } catch (Error e) {
                // Ignore malformed settings; use defaults.
            }
        }

        public void saveSettings () {
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("appsDir");
            builder.add_string_value(this.appsDir);
            builder.set_member_name("refreshInterval");
            builder.add_int_value(this.refreshInterval);
            builder.set_member_name("pinnedFirst");
            builder.add_boolean_value(this.pinnedFirst);
            builder.set_member_name("windowWidth");
            builder.add_int_value(this.windowWidth);
            builder.set_member_name("windowHeight");
            builder.add_int_value(this.windowHeight);
            builder.set_member_name("webAppBrowser");
            builder.add_string_value(this.webAppBrowser);
            builder.set_member_name("containerEngine");
            builder.add_string_value(this.containerEngine);
            builder.set_member_name("pinned");
            builder.begin_array();
            foreach (var pinned in this.pinnedApps) {
                builder.add_string_value(pinned);
            }
            builder.end_array();
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            size_t len;
            string json = generator.to_data(out len);
            var path = this.settings_path();
            try {
                var file = GLib.File.new_for_path(path);
                var stream = file.replace(null, false, GLib.FileCreateFlags.NONE, null);
                var data = new uint8[json.length];
                for (int i = 0; i < json.length; i++) {
                    data[i] = (uint8) json[i];
                }
                stream.write_all(data, null);
                stream.close(null);
            } catch (Error e) {
                // Ignore; settings will not persist.
            }
        }

        public signal void changed ();


    }
}
