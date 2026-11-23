using Gtk;
using Adw;
using GLib;
using Gdk;
using Logic;

namespace Views {
    /*
     * AppDetailsPage — app details page partial.
     * Always stays in sync with the selected app coming from State.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/AppDetailsPage.ui")]
    [CCode (cname = "AppDetailsPage")]
    public class AppDetailsPage : Gtk.Box {
        [GtkChild] private unowned Adw.ActionRow pathRow;
        [GtkChild] private unowned Adw.ActionRow projectRow;
        [GtkChild] private unowned Adw.ActionRow statusRow;
        [GtkChild] private unowned Gtk.Label refreshedLabel;
        [GtkChild] private unowned Gtk.Button openButton;
        [GtkChild] private unowned Gtk.Button pathCopyButton;
        [GtkChild] private unowned Gtk.Button composeButton;
        [GtkChild] private unowned Gtk.Button startButton;
        [GtkChild] private unowned Gtk.Button stopButton;
        [GtkChild] private unowned Gtk.Button restartButton;
        [GtkChild] private unowned Gtk.Button orphanButton;
        [GtkChild] private unowned Adw.Spinner actionSpinner;
        [GtkChild] private unowned Gtk.Label shortcutsHeading;
        [GtkChild] private unowned Adw.PreferencesGroup shortcutsGroup;
        [GtkChild] private unowned Adw.PreferencesGroup podmanBanner;
        [GtkChild] private unowned Gtk.Button retryButton;
        [GtkChild] private unowned Gtk.Box servicesBox;

        private Logic.State state;
        private List<Adw.PreferencesGroup> serviceGroups = new List<Adw.PreferencesGroup> ();
        private List<Adw.PreferencesRow> shortcutRows = new List<Adw.PreferencesRow> ();

        public AppDetailsPage () {
            this.state = Logic.Application.getState();
            this.state.changed.connect(this.render);
            this.openButton.clicked.connect(this.onOpenDirClicked);
            this.pathCopyButton.clicked.connect(this.onPathCopyClicked);
            this.composeButton.clicked.connect(this.onComposeClicked);
            this.startButton.clicked.connect(this.onStartAppClicked);
            this.stopButton.clicked.connect(this.onStopAppClicked);
            this.restartButton.clicked.connect(this.onRestartAppClicked);
            this.orphanButton.clicked.connect(this.onRemoveOrphansClicked);
            this.retryButton.clicked.connect(this.onRetryClicked);

            this.render();
        }

        private void render () {
            var selected = this.state.selectedApp;
            if (selected == null) {
                this.set_visible(false);
                return;
            }
            this.set_visible(true);

            pathRow.set_subtitle(selected.path);

            bool showProject = selected.projectName != "" && selected.projectName != selected.name;
            projectRow.set_visible (showProject);
            if (showProject) {
                projectRow.set_subtitle (selected.projectName);
            }

            int runningCount = selected.runningCount;
            int serviceCount = selected.serviceCount;
            string statusText;
            string dotColor;
            if (serviceCount == 0) {
                statusText = "Never started";
                dotColor = "#9E9E9E";
            } else if (runningCount == serviceCount) {
                statusText = "Running";
                dotColor = "#4CAF50";
            } else if (runningCount > 0) {
                statusText = "%d of %d running".printf(runningCount, serviceCount);
                dotColor = "#FFA500";
            } else {
                statusText = "All stopped";
                dotColor = "#F44336";
            }
            string markup = "<span foreground='%s' size='large'>●</span> %s".printf(dotColor, statusText);
            statusRow.set_subtitle(markup);

            if (this.state.lastUpdated == 0) {
                this.refreshedLabel.set_text ("");
            } else {
                int64 now = GLib.get_monotonic_time() / 1000 / 1000;
                int64 age = now - this.state.lastUpdated;
                if (age <= 1) {
                    this.refreshedLabel.set_text ("Updated just now");
                } else if (age < 60) {
                    this.refreshedLabel.set_text ("Updated %d s ago".printf ((int) age));
                } else {
                    this.refreshedLabel.set_text ("Updated %d min ago".printf ((int) (age / 60)));
                }
            }

            bool busy = this.state.actionInProgress;
            this.startButton.set_visible(!busy && !selected.running);
            this.stopButton.set_visible(!busy && selected.running);
            this.restartButton.set_visible(!busy && selected.running);
            this.orphanButton.set_visible(!busy && selected.orphanCount > 0);

            if (busy) {
                this.actionSpinner.set_visible(true);
            } else {
                this.actionSpinner.set_visible(false);
            }

            this.renderShortcuts (selected);
            this.podmanBanner.set_visible(!this.state.podmanReachable);

            foreach (var group in this.serviceGroups) {
                this.servicesBox.remove(group);
            }
            this.serviceGroups = new List<Adw.PreferencesGroup> ();

            foreach (var service in selected.services) {
                var section = new Views.AppServiceSection(service, selected, this.get_toplevel_window());
                this.servicesBox.append(section);
                this.serviceGroups.append(section);
            }
        }

        /*
         * Shows every shortcut published for the selected app, with the
         * icon and name from its desktop entry, and makes each one launch.
         */
        private void renderShortcuts (Logic.ComposeApp app) {
            foreach (var row in this.shortcutRows) {
                this.shortcutsGroup.remove(row);
            }
            this.shortcutRows = new List<Adw.PreferencesRow>();

            var shortcuts = Logic.ComposeDeck.listAppShortcuts(app);
            bool hasShortcuts = shortcuts.length() > 0;
            this.shortcutsHeading.set_visible(hasShortcuts);
            this.shortcutsGroup.set_visible(hasShortcuts);

            foreach (var shortcut in shortcuts) {
                var row = new Views.ShortcutRow(shortcut);
                row.change_requested.connect(() => {
                    var dialog = new Views.ShortcutEditor(app.name, shortcut.port, this.get_toplevel_window());
                    dialog.present();
                });
                row.open_requested.connect(() => this.launchShortcut(shortcut));
                this.shortcutsGroup.add(row);
                this.shortcutRows.append(row);
            }
        }

        /*
         * Launches the shortcut's desktop entry through the host so
         * app-mode browsers also work from inside the Flatpak sandbox.
         */
        private void launchShortcut (Logic.AppShortcut shortcut) {
            string[] argv = { "flatpak-spawn", "--host", "gio", "launch", shortcut.path };
            try {
                var process = new GLib.Subprocess.newv(argv,
                    GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE);
                if (process.wait_check(null)) return;
            } catch (Error e) {
                // Fall back to opening the URL directly.
            }

            if (shortcut.url == "") {
                var state = Logic.Application.getState();
                state.actionError = "Could not open shortcut.";
                state.changed();
                return;
            }

            try {
                GLib.AppInfo.launch_default_for_uri(shortcut.url, null);
            } catch (Error e) {
                var state = Logic.Application.getState();
                state.actionError = "Could not open %s".printf(shortcut.url);
                state.changed();
            }
        }

        private void onOpenDirClicked () {
            var selected = this.state.selectedApp;
            if (selected == null) return;
            try {
                var file = GLib.File.new_for_path(selected.path);
                GLib.AppInfo.launch_default_for_uri(file.get_uri(), null);
            } catch (Error e) {
                // Ignore; file manager may be unavailable in sandbox.
            }
        }

        private void onComposeClicked () {
            var selected = this.state.selectedApp;
            if (selected == null) return;
            string[] composeFiles = {
                "compose.yaml", "compose.yml",
                "docker-compose.yaml", "docker-compose.yml"
            };
            foreach (var fname in composeFiles) {
                var f = GLib.File.new_for_path(selected.path + "/" + fname);
                if (f.query_exists()) {
                    try {
                        GLib.AppInfo.launch_default_for_uri(f.get_uri(), null);
                    } catch (Error e) {
                        // Ignore.
                    }
                    break;
                }
            }
        }

        private void onPathCopyClicked () {
            var selected = this.state.selectedApp;
            if (selected == null) return;
            var display = Gdk.Display.get_default ();
            var clipboard = display.get_clipboard ();
            clipboard.set_text (selected.path);
        }

        private Gtk.Window? get_toplevel_window () {
            var top = this.get_root ();
            if (top != null && top is Gtk.Window) {
                return (Gtk.Window) top;
            }
            return null;
        }

        private void onStartAppClicked () {
            var selected = this.state.selectedApp;
            if (selected == null) return;
            Logic.ComposeDeck.startApp(selected);
        }

        private void onStopAppClicked () {
            var selected = this.state.selectedApp;
            if (selected == null) return;
            Logic.ComposeDeck.stopApp(selected);
        }

        private void onRestartAppClicked () {
            var selected = this.state.selectedApp;
            if (selected == null) return;
            Logic.ComposeDeck.restartApp(selected);
        }

        private void onRemoveOrphansClicked () {
            var selected = this.state.selectedApp;
            if (selected == null) return;

            var names = new StringBuilder ();
            foreach (var service in selected.services) {
                if (!service.orphan) continue;
                if (names.len > 0) names.append (", ");
                names.append (service.name);
            }
            if (names.len == 0) return;

            var dialog = new Views.OrphansDialog (
                names.str,
                this.get_toplevel_window ());
            dialog.response.connect ((d, response) => {
                if (response == "remove") {
                    Logic.ComposeDeck.removeOrphans (selected);
                }
                d.close ();
            });
            dialog.present ();
        }

        private void onRetryClicked () {
            Logic.ComposeDeck.discoverApps();
        }
    }
}
