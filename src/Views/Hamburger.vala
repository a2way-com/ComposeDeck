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
            resetButton.css_classes = new string[] { "suggested-action" };
            resetButton.set_margin_top (6);
            resetButton.set_margin_bottom (6);
            resetRow.add_suffix (resetButton);
            resetButton.clicked.connect (() => {
                string home = Environment.get_home_dir ();
                state.appsDir = home + "/Apps";
                state.saveSettings();
                entry.text = state.appsDir;
                Logic.ComposeDeck.discoverApps();
            });
            group.add (resetRow);

            var scanGroup = new Adw.PreferencesGroup ();
            scanGroup.set_title ("Scanning");
            page.add (scanGroup);

            var intervalRow = new Adw.ComboRow ();
            intervalRow.set_title ("Refresh interval");
            intervalRow.set_model (new Gtk.StringList (new string[] {
                "5 seconds", "10 seconds", "30 seconds", "60 seconds"
            }));
            int[] intervalValues = { 5, 10, 30, 60 };
            int selectedIndex = 1;
            for (int i = 0; i < intervalValues.length; i++) {
                if (intervalValues[i] == state.refreshInterval) selectedIndex = i;
            }
            intervalRow.set_selected (selectedIndex);
            intervalRow.notify["selected"].connect (() => {
                int index = (int) intervalRow.get_selected ();
                if (index >= 0 && index < intervalValues.length) {
                    state.refreshInterval = intervalValues[index];
                    state.saveSettings ();
                }
            });
            scanGroup.add (intervalRow);

            var pinnedRow = new Adw.SwitchRow ();
            pinnedRow.set_title ("Pinned apps first");
            pinnedRow.set_subtitle ("Show pinned apps before others");
            pinnedRow.set_active (state.pinnedFirst);
            pinnedRow.notify["active"].connect (() => {
                state.pinnedFirst = pinnedRow.get_active ();
                state.saveSettings ();
                state.changed ();
            });
            scanGroup.add (pinnedRow);

            var webGroup = new Adw.PreferencesGroup ();
            webGroup.set_title ("Web apps");
            page.add (webGroup);

            Logic.WebAppBrowser.invalidateDetection ();
            var browsers = Logic.WebAppBrowser.detect ();
            var browserRow = new Adw.ComboRow ();
            browserRow.set_title ("App browser");
            browserRow.set_subtitle ("Used by shortcuts that open in their own browser");
            if (browsers.length () == 0) {
                if (state.webAppBrowser != "") {
                    state.webAppBrowser = "";
                    state.saveSettings ();
                }
                browserRow.set_sensitive (false);
                browserRow.set_subtitle ("No app-mode browser found");
            } else {
                var browserModel = new Gtk.StringList (null);
                foreach (var browser in browsers) {
                    browserModel.append (browser.name);
                }
                browserRow.set_model (browserModel);

                int browserIndex = -1;
                int index = 0;
                foreach (var browser in browsers) {
                    if (browser.id == state.webAppBrowser) browserIndex = index;
                    index++;
                }
                if (browserIndex < 0) {
                    browserIndex = 0;
                    state.webAppBrowser = browsers.nth_data (0).id;
                    state.saveSettings ();
                    Logic.ComposeDeck.rewriteAppShortcuts ();
                }
                browserRow.set_selected ((uint) browserIndex);

                browserRow.notify["selected"].connect (() => {
                    int selected = (int) browserRow.get_selected ();
                    if (selected >= 0 && selected < (int) browsers.length ()) {
                        state.webAppBrowser = browsers.nth_data (selected).id;
                        state.saveSettings ();
                        Logic.ComposeDeck.rewriteAppShortcuts ();
                    }
                });
            }
            webGroup.add (browserRow);

            prefs.present ();
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