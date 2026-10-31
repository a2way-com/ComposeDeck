using Adw;
using GLib;

/*
 * ComposeDeck — application entry point and logic coordinator.
 *
 * This file owns the application lifecycle and polling timer (logic).
 * All UI manipulation is delegated to Window (view).
 */

const string APP_ID = "com.a2way.ComposeDeck";

class ComposeDeckApplication : Adw.Application {
    private Window? window;
    private uint poll_timeout;

    public ComposeDeckApplication () {
        Object (application_id: APP_ID);
    }

    protected override void activate () {
        if (window == null) {
            window = new Window (this);
            window.populate_apps ();
            window.select_overview ();

            /* Poll running status every 10 seconds */
            poll_timeout = GLib.Timeout.add_seconds (10, () => {
                window.poll_status ();
                return true;
            });
        }
        window.present ();
    }
}

int main (string[] args) {
    return new ComposeDeckApplication ().run (args);
}