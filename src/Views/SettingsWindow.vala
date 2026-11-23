using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * SettingsWindow — application, scanning, and web-app preferences.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/SettingsWindow.ui")]
    [CCode (cname = "SettingsWindow")]
    public class SettingsWindow : Adw.PreferencesWindow {
        [GtkChild] private unowned Gtk.Entry appsEntry;
        [GtkChild] private unowned Gtk.Button resetButton;
        [GtkChild] private unowned Adw.ComboRow intervalRow;
        [GtkChild] private unowned Adw.SwitchRow pinnedRow;
        [GtkChild] private unowned Adw.ComboRow browserRow;

        private Logic.State state;
        private int[] intervalValues = { 5, 10, 30, 60 };

        public SettingsWindow (Gtk.Window? parentWindow) {
            this.state = Logic.Application.getState();
            this.set_transient_for (parentWindow);

            this.appsEntry.set_text (this.state.appsDir);
            this.appsEntry.notify["text"].connect (() => {
                this.state.appsDir = this.appsEntry.text;
                this.state.saveSettings ();
                Logic.ComposeDeck.discoverApps ();
            });
            this.resetButton.clicked.connect (this.onResetClicked);

            this.intervalRow.set_model (new Gtk.StringList (new string[] {
                "5 seconds", "10 seconds", "30 seconds", "60 seconds"
            }));
            int selectedIndex = 1;
            for (int i = 0; i < this.intervalValues.length; i++) {
                if (this.intervalValues[i] == this.state.refreshInterval) selectedIndex = i;
            }
            this.intervalRow.set_selected (selectedIndex);
            this.intervalRow.notify["selected"].connect (() => {
                int index = (int) this.intervalRow.get_selected ();
                if (index >= 0 && index < this.intervalValues.length) {
                    this.state.refreshInterval = this.intervalValues[index];
                    this.state.saveSettings ();
                }
            });

            this.pinnedRow.set_active (this.state.pinnedFirst);
            this.pinnedRow.notify["active"].connect (() => {
                this.state.pinnedFirst = this.pinnedRow.get_active ();
                this.state.saveSettings ();
                this.state.changed ();
            });

            this.setupBrowserRow ();
        }

        private void onResetClicked () {
            string home = Environment.get_home_dir ();
            this.state.appsDir = home + "/Apps";
            this.state.saveSettings ();
            this.appsEntry.text = this.state.appsDir;
            Logic.ComposeDeck.discoverApps ();
        }

        private void setupBrowserRow () {
            Logic.WebAppBrowser.invalidateDetection ();
            var browsers = Logic.WebAppBrowser.detect ();

            if (browsers.length () == 0) {
                if (this.state.webAppBrowser != "") {
                    this.state.webAppBrowser = "";
                    this.state.saveSettings ();
                }
                this.browserRow.set_sensitive (false);
                this.browserRow.set_subtitle ("No app-mode browser found");
                return;
            }

            var browserModel = new Gtk.StringList (null);
            foreach (var browser in browsers) {
                browserModel.append (browser.name);
            }
            this.browserRow.set_model (browserModel);

            int browserIndex = -1;
            int index = 0;
            foreach (var browser in browsers) {
                if (browser.id == this.state.webAppBrowser) browserIndex = index;
                index++;
            }
            if (browserIndex < 0) {
                browserIndex = 0;
                this.state.webAppBrowser = browsers.nth_data (0).id;
                this.state.saveSettings ();
                Logic.ComposeDeck.rewriteAppShortcuts ();
            }
            this.browserRow.set_selected ((uint) browserIndex);

            this.browserRow.notify["selected"].connect (() => {
                int selected = (int) this.browserRow.get_selected ();
                if (selected >= 0 && selected < (int) browsers.length ()) {
                    this.state.webAppBrowser = browsers.nth_data (selected).id;
                    this.state.saveSettings ();
                    Logic.ComposeDeck.rewriteAppShortcuts ();
                }
            });
        }
    }
}
