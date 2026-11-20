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
            var state = Logic.Application.getState();

            var prefs = new Adw.PreferencesWindow ();
            prefs.set_transient_for (this.window);
            prefs.set_title ("Settings");
            prefs.set_modal (true);

            var page = new Adw.PreferencesPage ();
            prefs.add (page);

            var group = new Adw.PreferencesGroup ();
            group.set_title ("Applications directory");
            group.set_description ("Folder ComposeDeck scans for compose projects.");
            page.add (group);

            var row = new Adw.ActionRow ();
            row.set_title ("Apps directory");
            row.set_subtitle (state.appsDir);

            var entry = new Gtk.Entry ();
            entry.text = state.appsDir;
            entry.set_placeholder_text ("~/Apps");
            entry.set_hexpand (true);
            entry.set_width_chars (40);
            entry.set_valign (Gtk.Align.CENTER);
            entry.set_margin_top (6);
            entry.set_margin_bottom (6);
            entry.set_margin_start (6);
            entry.set_margin_end (6);
            entry.notify["text"].connect ((e, pspec) => {
                state.appsDir = entry.text;
                state.saveSettings();
                row.set_subtitle (state.appsDir);
                Logic.ComposeDeck.discoverApps();
            });
            row.add_suffix (entry);

            group.add (row);

            var resetRow = new Adw.ActionRow ();
            resetRow.set_title ("Reset to default");
            resetRow.set_subtitle ("Use ~/Apps");
            resetRow.set_activatable (true);
            var resetButton = new Gtk.Button ();
            resetButton.label = "Reset";
            resetButton.hexpand = false;
            resetButton.valign = Gtk.Align.CENTER;
            resetButton.css_classes = new string[] { "flat" };
            resetButton.set_margin_top (6);
            resetButton.set_margin_bottom (6);
            resetRow.add_suffix (resetButton);
            resetButton.clicked.connect (() => {
                string home = Environment.get_home_dir ();
                state.appsDir = home + "/Apps";
                state.saveSettings();
                entry.text = state.appsDir;
                row.set_subtitle (state.appsDir);
                Logic.ComposeDeck.discoverApps();
            });
            group.add (resetRow);

            prefs.present ();
        }

        private void onAboutClicked () {
            var about = new Adw.AboutDialog();
            about.application_name = ComposeDeck.APP_NAME;
            about.application_icon = "com.a2way.ComposeDeck";
            about.developer_name = ComposeDeck.DEVELOPER_NAME;
            about.version = ComposeDeck.VERSION;
            about.comments = "Manage Compose applications under ~/Apps/.";
            about.present(this.window);
        }
    }
}