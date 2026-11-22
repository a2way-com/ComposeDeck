using GLib;

namespace Logic {
    /*
     * AppShortcut — one desktop shortcut ComposeDeck published for an app.
     */

    public class AppShortcut : GLib.Object {
        public string path { get; private set; }
        public string name { get; private set; }
        public string url { get; private set; }
        public string icon { get; private set; }
        public bool ownBrowser { get; private set; }
        public uint port { get; private set; }

        public AppShortcut (string path, string name, string url, string icon, bool ownBrowser, uint port) {
            this.path = path;
            this.name = name;
            this.url = url;
            this.icon = icon;
            this.ownBrowser = ownBrowser;
            this.port = port;
        }

        /*
         * Reads one managed .desktop file. Returns null when the file
         * cannot be read.
         */
        public static AppShortcut? load (string path, uint port) {
            uint8[] raw;
            string etag;
            try {
                GLib.File.new_for_path(path).load_contents(null, out raw, out etag);
            } catch (Error e) {
                return null;
            }

            string name = "";
            string url = "";
            string icon = "";
            bool ownBrowser = false;

            foreach (var line in ((string) raw).split("\n")) {
                if (line.has_prefix("Name=")) {
                    name = line.substring(5).strip();
                } else if (line.has_prefix("Icon=")) {
                    icon = line.substring(5).strip();
                } else if (line.has_prefix("Exec=")) {
                    url = ComposeDeck.extractExecUrl(line);
                } else if (line.has_prefix("X-ComposeDeck-OpenInOwnBrowser=")) {
                    int eq = line.index_of("=");
                    if (eq >= 0) ownBrowser = line.substring(eq + 1).strip() == "true";
                }
            }

            if (name == "") {
                name = GLib.Path.get_basename(path);
                if (name.has_suffix(".desktop")) {
                    name = name.substring(0, name.length - 8);
                }
            }

            return new AppShortcut(path, name, url, icon, ownBrowser, port);
        }
    }
}
