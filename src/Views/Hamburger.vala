using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * Hamburger — helper for the sidebar hamburger menu (menu model + window actions).
     */

    public class Hamburger : GLib.Object {
        private Adw.ApplicationWindow window;
        private Gtk.MenuButton menuButton;

        public Hamburger (Adw.ApplicationWindow window, Gtk.MenuButton menuButton) {
            this.window = window;
            this.menuButton = menuButton;

            this.menuButton.notify["active"].connect(() => {
                if (this.menuButton.active) {
                    GLib.Idle.add(() => {
                        this.window.set_focus(null);
                        return GLib.Source.REMOVE;
                    });
                }
            });

            var menu = new GLib.Menu();
            menu.append("About", "win.about");
            menu.append("Settings", "win.settings");
            menu.append("Quit", "win.quit");
            this.menuButton.set_menu_model(menu);

            var aboutAction = new GLib.SimpleAction("about", null);
            aboutAction.activate.connect((action, param) => this.onAboutClicked());
            this.window.add_action(aboutAction);

            var settingsAction = new GLib.SimpleAction("settings", null);
            settingsAction.activate.connect((action, param) => this.onSettingsClicked());
            this.window.add_action(settingsAction);

            var quitAction = new GLib.SimpleAction("quit", null);
            quitAction.activate.connect((action, param) => this.onQuitClicked());
            this.window.add_action(quitAction);
        }

        private void onQuitClicked () {
            this.window.close();
        }

        private void onSettingsClicked () {
            var settings = new SettingsWindow (this.window);
            settings.present ();
        }

        private void onAboutClicked () {
            var about = new Adw.AboutDialog();
            about.application_name = ComposeDeck.APP_NAME;
            about.application_icon = "com.a2way.ComposeDeck";
            about.developer_name = ComposeDeck.DEVELOPER_NAME;
            about.version = ComposeDeck.VERSION;
            about.comments = "Manage Compose applications from a configurable folder.";
            about.present(this.window);
        }
    }
}