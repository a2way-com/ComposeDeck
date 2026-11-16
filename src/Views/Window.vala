using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * Window — pure GUI view for ComposeDeck (reads state; does not drive).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/Window.ui")]
    [CCode (cname = "Window")]
    public class Window : Adw.ApplicationWindow {
        [GtkChild] private unowned Gtk.Box sidebarBox;
        [GtkChild] private unowned Gtk.Box contentBox;
        [GtkChild] private unowned Adw.ToastOverlay toastOverlay;

        private Logic.State state;

        public Sidebar sidebar { get; private set; }
        public ContentArea contentArea { get; private set; }
        public Hamburger hamburger { get; private set; }

        public Window (Adw.Application app) {
            this.set_application(app);
            this.state = Logic.Application.getState();

            this.sidebar = new Sidebar();
            this.contentArea = new ContentArea();
            this.hamburger = new Hamburger(this, this.sidebar.menuButton);

            this.sidebarBox.append(this.sidebar);
            this.contentBox.append(this.contentArea);

            this.state.changed.connect(this.onStateChanged);
        }

        /*
         * Surfaces a failed app action once its busy state ends, no matter
         * which page is showing.
         */
        private void onStateChanged () {
            if (this.state.actionInProgress) return;

            string? error = this.state.consumeActionError();
            if (error != null) {
                this.toastOverlay.add_toast (new Adw.Toast (error));
            }
        }

    }
}
