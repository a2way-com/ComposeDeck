using GLib;

namespace Logic {
    public class State : GLib.Object {
        public GLib.List<ComposeApp> apps;

        public State () {
            this.apps = new GLib.List<ComposeApp> ();
            this.selectedApp = null;
        }
        public int total { get; private set; default = 0; }
        public int runningCount { get; private set; default = 0; }
        public ComposeApp? selectedApp;
        public bool overviewSelected { get { return this.selectedApp == null; } }

        public signal void changed ();

        public void setAppList (owned GLib.List<ComposeApp> a) {
            string? selectedPath = (this.selectedApp != null) ? this.selectedApp.path : null;
            this.apps = (owned) a;
            this.recompute();

            if (selectedPath != null) {
                ComposeApp? found = null;
                foreach (var app in this.apps) {
                    if (app.path == selectedPath) {
                        found = app;
                        break;
                    }
                }
                this.selectedApp = found;
            }

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
            this.selectedApp = null;
            this.changed();
        }

        public void selectApp (ComposeApp app) {
            this.selectedApp = app;
            this.changed();
        }
    }
}
