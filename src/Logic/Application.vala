using Adw;
using GLib;
using Views;

namespace Logic {
    /*
     * Application — Adw.Application subclass for ComposeDeck.
     */

    public class Application : Adw.Application {
        private Views.Window? window;

        public Application () {
            Object (application_id: ComposeDeck.APP_ID);
        }

        protected override void activate () {
            if (window == null) {
                window = new Views.Window (this);
                ComposeDeck.start (window);
            }
            window.present ();
        }
    }
}
