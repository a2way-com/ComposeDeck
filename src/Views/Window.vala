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

            // Style overview cards: background without hover highlight.
            var css = new Gtk.CssProvider();
            css.load_from_string("""
                .overview-card {
                    background-color: #2d2d2d;
                    border: 2px solid transparent;
                    border-radius: 12px;
                }
                .overview-card:hover {
                    border-color: @accent_bg_color;
                }
                .overview-card:focus {
                    border-color: @accent_bg_color;
                }
                flowboxchild {
                    background-color: transparent;
                    background: none;
                }
                flowboxchild:hover,
                flowboxchild:selected,
                flowboxchild:active {
                    background-color: transparent;
                    background: none;
                    box-shadow: none;
                }
            """);
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 100
            );

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
            } else {
                string? success = this.state.consumeActionSuccess ();
                if (success != null) {
                    this.toastOverlay.add_toast (new Adw.Toast (success));
                }
            }
        }

    }
}
