using Gtk;
using Adw;
using GLib;
using Gdk;
using Logic;

namespace Views {
    /*
     * OverviewCard — dashboard card for a single Compose app.
     */
    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OverviewCard.ui")]
    [CCode (cname = "OverviewCard")]
    public class OverviewCard : Gtk.Frame {
        [GtkChild] private unowned Gtk.Label indicator;
        [GtkChild] private unowned Gtk.Label nameLabel;
        [GtkChild] private unowned Gtk.Label statusLabel;
        [GtkChild] private unowned Gtk.Label serviceLabel;
        [GtkChild] private unowned Gtk.Button startButton;
        [GtkChild] private unowned Gtk.Button stopButton;
        [GtkChild] private unowned Gtk.Button restartButton;
        [GtkChild] private unowned Gtk.ToggleButton pinButton;

        public ComposeApp app { get; set; }

        public OverviewCard (ComposeApp app) {
            this.app = app;
            this.render();
        }

        private void render () {
            string dotColor;
            if (this.app.serviceCount == 0) {
                dotColor = "#9E9E9E";
            } else if (this.app.runningCount == this.app.serviceCount) {
                dotColor = "#4CAF50";
            } else if (this.app.runningCount > 0) {
                dotColor = "#FFA500";
            } else {
                dotColor = "#F44336";
            }
            this.indicator.set_markup("<span foreground='%s' size='large'>●</span>".printf(dotColor));

            this.nameLabel.set_text(this.app.name);

            string statusText;
            if (this.app.serviceCount == 0) {
                statusText = "Never started";
            } else if (this.app.runningCount == this.app.serviceCount) {
                statusText = "Running";
            } else if (this.app.runningCount > 0) {
                statusText = "%d of %d running".printf(this.app.runningCount, this.app.serviceCount);
            } else {
                statusText = "All stopped";
            }
            this.statusLabel.set_text(statusText);

            int totalServices = this.app.serviceCount;
            this.serviceLabel.set_text("%d service%s".printf(totalServices, totalServices == 1 ? "" : "s"));

            bool busy = Logic.Application.getState().actionInProgress;
            this.startButton.set_visible(!busy && !this.app.running);
            this.stopButton.set_visible(!busy && this.app.running);
            this.restartButton.set_visible(!busy && this.app.running);

            this.startButton.clicked.connect(() => {
                Logic.ComposeDeck.startApp(this.app);
            });
            this.stopButton.clicked.connect(() => {
                Logic.ComposeDeck.stopApp(this.app);
            });
            this.restartButton.clicked.connect(() => {
                Logic.ComposeDeck.restartApp(this.app);
            });

            this.pinButton.set_active (Logic.Application.getState ().isPinned (this.app.name));
            this.pinButton.toggled.connect (() => {
                Logic.Application.getState ().togglePin (this.app.name);
                Logic.Application.getState ().changed ();
            });
        }
    }
}