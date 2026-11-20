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
        [GtkChild] private unowned Adw.ActionRow statusRow;
        [GtkChild] private unowned Adw.ActionRow actionsRow;
        [GtkChild] private unowned Gtk.Button openButton;
        [GtkChild] private unowned Gtk.Button pathCopyButton;
        [GtkChild] private unowned Gtk.Button composeButton;
        [GtkChild] private unowned Gtk.Button startButton;
        [GtkChild] private unowned Gtk.Button stopButton;
        [GtkChild] private unowned Gtk.Button restartButton;
        [GtkChild] private unowned Adw.Spinner actionSpinner;
        [GtkChild] private unowned Gtk.Box servicesBox;

        private Logic.State state;
        private List<Adw.PreferencesGroup> serviceGroups = new List<Adw.PreferencesGroup> ();
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

            var pathIcon = new Gtk.Image ();
            pathIcon.icon_name = "edit-copy-symbolic";
            pathIcon.set_pixel_size (16);
            this.pathCopyButton.set_child (pathIcon);

            this.addIconButton (this.startButton, "media-playback-start-symbolic");
            this.addIconButton (this.stopButton, "media-playback-stop-symbolic");
            this.addIconButton (this.restartButton, "view-refresh-symbolic");

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

            int64 now = GLib.get_monotonic_time() / 1000 / 1000;
            int64 age = now - this.state.lastUpdated;
            string ageText = age < 60
                ? "just now"
                : age < 3600
                    ? "%d s ago".printf((int) age)
                    : "%d min ago".printf((int) (age / 60));
            pathRow.set_tooltip_text("Last refreshed %s".printf(ageText));

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

            bool busy = this.state.actionInProgress;
            this.startButton.set_visible(!busy && !selected.running);
            this.stopButton.set_visible(!busy && selected.running);
            this.restartButton.set_visible(!busy && selected.running);

            if (busy) {
                this.actionSpinner.set_visible(true);
            } else {
                this.actionSpinner.set_visible(false);
            }

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

                var section = new Views.AppServiceSection(service, this.get_toplevel_window());
                section.add_to(serviceGroup);
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

        private void onRetryClicked () {
            Logic.ComposeDeck.discoverApps();
        }
    }
}
