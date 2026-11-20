using GLib;
using Json;

namespace Logic {
    public class State : GLib.Object {
        public GLib.List<ComposeApp> apps = new GLib.List<ComposeApp>();
        public ComposeApp? selectedApp = null;
        public bool actionInProgress = false;
        public string? actionError = null;
        public bool podmanReachable = true;
        public int64 lastUpdated = 0;
        public string appsDir { get; set; }

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
            } catch (Error e) {
                // Ignore malformed settings; use defaults.
            }
        }

        public void saveSettings () {
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("appsDir");
            builder.add_string_value(this.appsDir);
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
