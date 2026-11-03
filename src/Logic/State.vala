using GLib;

namespace Logic {
    public class State : GLib.Object {
        public GLib.List<ComposeApp> apps;

        public State () {
            this.apps = new GLib.List<ComposeApp> ();
        }
        public int total { get; private set; default = 0; }
        public int runningCount { get; private set; default = 0; }
        public bool overviewSelected { get; private set; default = true; }
        public string? selectedPath { get; private set; default = null; }

        public signal void changed ();

        public void setAppList (owned GLib.List<ComposeApp> a) {
            this.apps = (owned) a;
            this.recompute();
            this.changed();
        }

        private void recompute () {
            int totalApps = 0;
            int runningApps = 0;
            foreach (var app in this.apps) {
                totalApps++;
                if (app.running) {
                    runningApps++;
                }
            }
            this.total = totalApps;
            this.runningCount = runningApps;
        }

        public void selectOverview () {
            this.overviewSelected = true;
            this.selectedPath = null;
            this.changed();
        }

        public void selectApp (string path) {
            this.overviewSelected = false;
            this.selectedPath = path;
            this.changed();
        }
    }
}
