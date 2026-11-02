using GLib;

namespace Logic {
    public class State : GLib.Object {
        public GLib.List<ComposeApp> apps;

        public State () {
            apps = new GLib.List<ComposeApp> ();
        }
        public int total { get; private set; default = 0; }
        public int runningCount { get; private set; default = 0; }
        public bool overviewSelected { get; private set; default = true; }
        public string? selectedPath { get; private set; default = null; }

        public signal void changed ();

        public void setAppList (owned GLib.List<ComposeApp> a) {
            apps = (owned) a;
            recompute();
            changed();
        }

        private void recompute () {
            int totalApps = 0;
            int runningApps = 0;
            foreach (var app in apps) {
                totalApps++;
                if (app.running) {
                    runningApps++;
                }
            }
            total = totalApps;
            runningCount = runningApps;
        }

        public void selectOverview () {
            overviewSelected = true;
            selectedPath = null;
            changed();
        }

        public void selectApp (string path) {
            overviewSelected = false;
            selectedPath = path;
            changed();
        }
    }
}
