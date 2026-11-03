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

        public Sidebar sidebar { get; private set; }
        public ContentArea contentArea { get; private set; }
        public Hamburger hamburger { get; private set; }

        public Window (Adw.Application app) {
            this.set_application(app);

            this.sidebar = new Sidebar();
            this.contentArea = new ContentArea();
            this.hamburger = new Hamburger(this, this.sidebar.menuButton);

            this.sidebarBox.append(this.sidebar);
            this.contentBox.append(this.contentArea);
        }

    }
}
