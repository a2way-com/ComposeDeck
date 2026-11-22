using GLib;

namespace Logic {
    /*
     * WebAppBrowser — a host browser that can open a URL in app mode.
     */
    public class WebAppBrowser {
        private static GLib.List<WebAppBrowser> cachedBrowsers = new GLib.List<WebAppBrowser> ();
        private static bool hasProbe = false;

        public string id { get; private set; }
        public string name { get; private set; }
        public string execPrefix { get; private set; }
        public bool equalsFlag { get; private set; }
        public bool profileMode { get; private set; }
        public string profilePrefix { get; private set; }

        public WebAppBrowser (string id, string name, string execPrefix, bool equalsFlag,
                              bool profileMode = false, string profilePrefix = "") {
            this.id = id;
            this.name = name;
            this.execPrefix = execPrefix;
            this.equalsFlag = equalsFlag;
            this.profileMode = profileMode;
            this.profilePrefix = profilePrefix;
        }

        public string buildExec (string url, string desktopId = "") {
            string safe = url.replace ("\"", "%22").replace ("\n", "");
            if (this.profileMode) {
                if (desktopId == "") return "";
                string safeId = desktopId.replace ("\"", "%22").replace ("\n", "");
                return "%s --application-mode=%s.desktop \"%s\"".printf (this.execPrefix, safeId, safe);
            }
            if (this.equalsFlag) {
                return "%s --app=\"%s\"".printf (this.execPrefix, safe);
            }
            return "%s --application-mode \"%s\"".printf (this.execPrefix, safe);
        }

        /*
         * Probes the host for installed browsers that support app mode.
         * Flatpak browsers are included; GNOME Web uses --application-mode.
         */
        public static void invalidateDetection () {
            WebAppBrowser.hasProbe = false;
            WebAppBrowser.cachedBrowsers = new GLib.List<WebAppBrowser> ();
        }

        public static GLib.List<WebAppBrowser> detect () {
            var result = new GLib.List<WebAppBrowser> ();

            if (!WebAppBrowser.hasProbe) {
                string probe = WebAppBrowser.probeHost ();
                WebAppBrowser.hasProbe = true;
                var seenNames = new GLib.HashTable<string, bool> (str_hash, str_equal);
                foreach (var rawLine in probe.split ("\n")) {
                    string line = rawLine.strip ();
                    if (line == "") continue;
                    var browser = WebAppBrowser.fromDetection (line);
                    if (browser == null) continue;
                    if (seenNames.contains (browser.name)) continue;
                    seenNames.insert (browser.name, true);
                    WebAppBrowser.cachedBrowsers.append (browser);
                }
            }

            foreach (var browser in WebAppBrowser.cachedBrowsers) {
                result.append (browser);
            }
            return result;
        }

        private static string probeHost () {
            string script =
                "for b in chromium chromium-browser google-chrome google-chrome-stable " +
                "brave-browser microsoft-edge microsoft-edge-stable vivaldi vivaldi-stable " +
                "epiphany; do command -v \"$b\" >/dev/null 2>&1 && echo \"bin:$b\"; done; " +
                "installed=$(flatpak list --app --columns=application 2>/dev/null | tr '\\n' ' '); " +
                "for id in org.chromium.Chromium com.google.Chrome com.brave.Browser " +
                "com.microsoft.Edge com.vivaldi.Vivaldi org.gnome.Epiphany org.gnome.Ephemeral; " +
                "do case \" $installed \" in *\" $id \"*) echo \"flatpak:$id\";; esac; done";
            string[] argv = { "flatpak-spawn", "--host", "timeout", "5", "sh", "-c", script };

            try {
                var process = new GLib.Subprocess.newv (
                    argv,
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string? output = null;
                string? err = null;
                process.communicate_utf8 (null, null, out output, out err);
                return output != null ? output : "";
            } catch (Error e) {
                return "";
            }
        }

        private static WebAppBrowser? fromDetection (string line) {
            if (line == "bin:chromium") return new WebAppBrowser ("bin:chromium", "Chromium", "chromium", true);
            if (line == "bin:chromium-browser") return new WebAppBrowser ("bin:chromium-browser", "Chromium", "chromium-browser", true);
            if (line == "bin:google-chrome") return new WebAppBrowser ("bin:google-chrome", "Google Chrome", "google-chrome", true);
            if (line == "bin:google-chrome-stable") return new WebAppBrowser ("bin:google-chrome-stable", "Google Chrome", "google-chrome-stable", true);
            if (line == "bin:brave-browser") return new WebAppBrowser ("bin:brave-browser", "Brave", "brave-browser", true);
            if (line == "bin:microsoft-edge") return new WebAppBrowser ("bin:microsoft-edge", "Microsoft Edge", "microsoft-edge", true);
            if (line == "bin:microsoft-edge-stable") return new WebAppBrowser ("bin:microsoft-edge-stable", "Microsoft Edge", "microsoft-edge-stable", true);
            if (line == "bin:vivaldi") return new WebAppBrowser ("bin:vivaldi", "Vivaldi", "vivaldi", true);
            if (line == "bin:vivaldi-stable") return new WebAppBrowser ("bin:vivaldi-stable", "Vivaldi", "vivaldi-stable", true);

            if (line == "flatpak:org.chromium.Chromium") return new WebAppBrowser ("flatpak:org.chromium.Chromium", "Chromium (Flatpak)", "flatpak run org.chromium.Chromium", true);
            if (line == "flatpak:com.google.Chrome") return new WebAppBrowser ("flatpak:com.google.Chrome", "Google Chrome (Flatpak)", "flatpak run com.google.Chrome", true);
            if (line == "flatpak:com.brave.Browser") return new WebAppBrowser ("flatpak:com.brave.Browser", "Brave (Flatpak)", "flatpak run com.brave.Browser", true);
            if (line == "flatpak:com.microsoft.Edge") return new WebAppBrowser ("flatpak:com.microsoft.Edge", "Microsoft Edge (Flatpak)", "flatpak run com.microsoft.Edge", true);
            if (line == "flatpak:com.vivaldi.Vivaldi") return new WebAppBrowser ("flatpak:com.vivaldi.Vivaldi", "Vivaldi (Flatpak)", "flatpak run com.vivaldi.Vivaldi", true);

            if (line == "bin:epiphany") return new WebAppBrowser ("bin:epiphany", "GNOME Web", "epiphany", false, true, "org.gnome.Epiphany.WebApp_");
            if (line == "flatpak:org.gnome.Epiphany") return new WebAppBrowser ("flatpak:org.gnome.Epiphany", "GNOME Web (Flatpak)", "flatpak run org.gnome.Epiphany", false, true, "org.gnome.Epiphany.WebApp_");
            if (line == "flatpak:org.gnome.Ephemeral") return new WebAppBrowser ("flatpak:org.gnome.Ephemeral", "GNOME Web (Flatpak)", "flatpak run org.gnome.Ephemeral", false, true, "org.gnome.Ephemeral.WebApp_");
            return null;
        }

        /*
         * Resolves the preferred browser id, or the first detected browser
         * when no preference is set. Returns null when nothing is available
         * or the preferred browser is no longer installed.
         */
        public static WebAppBrowser? resolve (string preferredId) {
            if (preferredId != "") {
                // Trust the stored ID without probing the host; Settings is
                // the place where the installed-browser list is refreshed.
                return WebAppBrowser.fromDetection (preferredId);
            }

            var browsers = WebAppBrowser.detect ();
            if (browsers.length () == 0) return null;
            return browsers.nth_data (0);
        }
    }
}
