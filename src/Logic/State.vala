using GLib;

namespace Logic {
    public class State : GLib.Object {
        public GLib.List<ComposeApp> apps = new GLib.List<ComposeApp>();
        public ComposeApp? selectedApp = null;
        public bool actionInProgress = false;
        public string? actionError = null;
        public bool podmanReachable = true;
        public int64 lastUpdated = 0;

        public State () {
            this.apps = new GLib.List<ComposeApp>();
            this.selectedApp = null;
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

        public signal void changed ();


    }
}
