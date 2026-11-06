using GLib;

namespace Logic {
    public class State : GLib.Object {
        public GLib.List<ComposeApp> apps = new GLib.List<ComposeApp>();
        public ComposeApp? selectedApp = null;

        public State () {
            this.apps = new GLib.List<ComposeApp>();
            this.selectedApp = null;
        }

        public bool overviewSelected { get { return this.selectedApp == null; } }

        public signal void changed ();


    }
}
