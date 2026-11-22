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
        [GtkChild] private unowned Adw.ActionRow actionsRow;
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
        [GtkChild] private unowned Gtk.Box servicesBox;

        private Logic.State state;
        private List<Adw.PreferencesGroup> serviceGroups = new List<Adw.PreferencesGroup> ();
        private List<Adw.PreferencesRow> shortcutRows = new List<Adw.PreferencesRow> ();
        private Adw.PreferencesGroup? podmanBanner;

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

            var pathIcon = new Gtk.Image ();
            pathIcon.icon_name = "edit-copy-symbolic";
            pathIcon.set_pixel_size (16);
            this.pathCopyButton.set_child (pathIcon);

            this.addIconButton (this.startButton, "media-playback-start-symbolic");
            this.addIconButton (this.stopButton, "media-playback-stop-symbolic");
            this.addIconButton (this.restartButton, "view-refresh-symbolic");
            this.addIconButton (this.orphanButton, "user-trash-symbolic");

            this.render();
        }

        private void addIconButton (Gtk.Button button, string iconName) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.set_halign (Gtk.Align.CENTER);
            box.set_valign (Gtk.Align.CENTER);

            var image = new Gtk.Image ();
            image.icon_name = iconName;
            image.set_pixel_size (16);
            box.append (image);

            var label = new Gtk.Label (button.label);
            box.append (label);

            button.label = "";
            button.set_child (box);
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

            // Podman unreachable banner
            if (!this.state.podmanReachable) {
                if (this.podmanBanner == null) {
                    this.podmanBanner = new Adw.PreferencesGroup ();
                    var row = new Adw.ActionRow ();
                    row.set_title ("Podman is not reachable");
                    row.set_subtitle ("ComposeDeck cannot query container state.");
                    var retry = new Gtk.Button ();
                    retry.set_label ("Retry");
                    retry.set_hexpand (false);
                    retry.set_valign (Gtk.Align.CENTER);
                    retry.set_css_classes (new string[] { "flat" });
                    retry.clicked.connect (this.onRetryClicked);
                    row.add_suffix (retry);
                    this.podmanBanner.add (row);
                }
                this.servicesBox.insert_child_after (this.podmanBanner, null);
            } else if (this.podmanBanner != null) {
                this.servicesBox.remove (this.podmanBanner);
                this.podmanBanner = null;
            }

            foreach (var group in this.serviceGroups) {
                this.servicesBox.remove(group);
            }
            this.serviceGroups = new List<Adw.PreferencesGroup> ();

            foreach (var service in selected.services) {
                var serviceGroup = new Adw.PreferencesGroup ();
                this.servicesBox.append(serviceGroup);
                this.serviceGroups.append(serviceGroup);

                var section = new Views.AppServiceSection(service, selected, this.get_toplevel_window());
                section.add_to(serviceGroup);
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
                var row = this.buildShortcutRow(shortcut, app.name);
                this.shortcutsGroup.add(row);
                this.shortcutRows.append(row);
            }
        }

        private Adw.ActionRow buildShortcutRow (Logic.AppShortcut shortcut, string appName) {
            var row = new Adw.ActionRow();
            row.set_activatable(true);
            row.set_title(shortcut.name);
            if (shortcut.url != "") {
                row.set_subtitle(shortcut.url);
            }
            row.set_tooltip_text("Open %s".printf(shortcut.name));

            var icon = this.buildShortcutIcon(shortcut.icon);
            icon.set_valign(Gtk.Align.CENTER);
            row.add_prefix(icon);

            var changeButton = new Gtk.Button.with_label("Change shortcut");
            changeButton.set_hexpand(false);
            changeButton.set_valign(Gtk.Align.CENTER);
            changeButton.set_css_classes(new string[] { "flat" });
            changeButton.clicked.connect(() => {
                var dialog = new Views.ShortcutEditor(appName, shortcut.port, this.get_toplevel_window());
                dialog.present();
            });
            row.add_suffix(changeButton);

            var openButton = new Gtk.Button();
            var openIcon = new Gtk.Image();
            openIcon.icon_name = "web-browser-symbolic";
            openIcon.set_pixel_size(16);
            openButton.set_child(openIcon);
            openButton.set_hexpand(false);
            openButton.set_valign(Gtk.Align.CENTER);
            openButton.set_css_classes(new string[] { "flat" });
            openButton.set_tooltip_text(shortcut.ownBrowser ? "Open in own browser" : "Open in browser");
            openButton.clicked.connect(() => this.launchShortcut(shortcut));
            row.add_suffix(openButton);

            row.activated.connect(() => this.launchShortcut(shortcut));
            return row;
        }

        private Gtk.Image buildShortcutIcon (string iconValue) {
            var image = new Gtk.Image();
            image.set_pixel_size(40);

            if (iconValue.has_prefix("/") && GLib.File.new_for_path(iconValue).query_exists()) {
                image.set_from_file(iconValue);
                return image;
            }

            if (iconValue != "") {
                var display = Gdk.Display.get_default();
                var theme = display != null ? Gtk.IconTheme.get_for_display(display) : null;
                if (theme != null && theme.has_icon(iconValue)) {
                    image.icon_name = iconValue;
                    return image;
                }
            }

            image.icon_name = "application-x-executable-symbolic";
            return image;
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

            var dialog = new Adw.MessageDialog (
                this.get_toplevel_window (),
                "Remove orphan containers?",
                "These containers are not declared in the compose file: %s".printf (names.str));
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("remove", "Remove");
            dialog.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response ("cancel");
            dialog.set_close_response ("cancel");
            dialog.response.connect ((response) => {
                if (response == "remove") {
                    Logic.ComposeDeck.removeOrphans (selected);
                }
            });
            dialog.present ();
        }

        private void onRetryClicked () {
            Logic.ComposeDeck.discoverApps();
        }
    }
}
