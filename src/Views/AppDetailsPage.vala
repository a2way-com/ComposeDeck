using Gtk;
using Adw;
using GLib;
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
        [GtkChild] private unowned Gtk.Button openButton;
        [GtkChild] private unowned Gtk.Box servicesBox;

        private Logic.State state;
        private List<Adw.PreferencesGroup> serviceGroups = new List<Adw.PreferencesGroup> ();

        public AppDetailsPage () {
            this.state = Logic.Application.getState();
            this.state.changed.connect(this.render);
            this.openButton.clicked.connect(this.onOpenDirClicked);
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

            string dotColor = selected.running ? "#4CAF50" : "#F44336";
            string statusText = selected.running ? "Running" : "Stopped";
            string markup = "<span foreground='%s' size='large'>●</span> %s".printf(dotColor, statusText);
            statusRow.set_subtitle(markup);

            foreach (var group in this.serviceGroups) {
                this.servicesBox.remove(group);
            }
            this.serviceGroups = new List<Adw.PreferencesGroup> ();

            foreach (var service in selected.services) {
                var serviceGroup = new Adw.PreferencesGroup ();
                this.servicesBox.append(serviceGroup);
                this.serviceGroups.append(serviceGroup);

                var section = new Views.AppServiceSection(service);
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
    }
}
