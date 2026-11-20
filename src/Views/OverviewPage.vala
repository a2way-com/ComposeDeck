using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * OverviewPage — dashboard: aggregate stats + app cards grid.
     */
    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OverviewPage.ui")]
    [CCode (cname = "OverviewPage")]
    public class OverviewPage : Gtk.Box {
        [GtkChild] private unowned Gtk.Label totalValue;
        [GtkChild] private unowned Gtk.Label runningValue;
        [GtkChild] private unowned Gtk.Label stoppedValue;
        [GtkChild] private unowned Gtk.Label partialValue;
        [GtkChild] private unowned Gtk.Button startAllButton;
        [GtkChild] private unowned Gtk.Button stopAllButton;
        [GtkChild] private unowned Gtk.Stack contentStack;
        [GtkChild] private unowned Gtk.FlowBox flowBox;
        [GtkChild] private unowned Gtk.Box emptyState;

        private Logic.State state;
        private List<Views.OverviewCard> cards = new List<Views.OverviewCard> ();

        public OverviewPage () {
            this.state = Logic.Application.getState();
            this.state.changed.connect(this.render);
            this.startAllButton.clicked.connect(this.onStartAllClicked);
            this.stopAllButton.clicked.connect(this.onStopAllClicked);
            this.render();
        }

        private void render () {
            this.updateStats();
            this.updateBulkButtons();
            this.rebuildCards();
            this.set_visible(this.state.selectedApp == null);
        }

        private void updateStats () {
            int total = 0;
            int runningCount = 0;
            int stoppedCount = 0;
            int partialCount = 0;
            int totalServices = 0;
            foreach (var app in this.state.apps) {
                total++;
                totalServices += app.serviceCount;
                if (app.serviceCount == 0) {
                    // never started, count as stopped
                    stoppedCount++;
                } else if (app.runningCount == app.serviceCount) {
                    runningCount++;
                } else if (app.runningCount > 0) {
                    partialCount++;
                } else {
                    stoppedCount++;
                }
            }
            this.totalValue.set_text(total.to_string());
            this.runningValue.set_markup("<span foreground='#4CAF50'><b>%d</b></span>".printf(runningCount));
            this.stoppedValue.set_markup("<span foreground='#F44336'><b>%d</b></span>".printf(stoppedCount));
            this.partialValue.set_markup("<span foreground='#FFA500'><b>%d</b></span>".printf(partialCount));
        }

        private void updateBulkButtons () {
            bool hasStopped = false;
            bool hasRunning = false;
            foreach (var app in this.state.apps) {
                if (app.serviceCount > 0 && app.runningCount < app.serviceCount) hasStopped = true;
                if (app.runningCount > 0) hasRunning = true;
            }
            this.startAllButton.set_visible(!this.state.actionInProgress && hasStopped);
            this.stopAllButton.set_visible(!this.state.actionInProgress && hasRunning);
        }

        private void rebuildCards () {
            // Remove all existing children from flowBox
            var child = this.flowBox.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                this.flowBox.remove (child);
                child = next;
            }
            this.cards = new List<Views.OverviewCard> ();

            if (this.state.apps.length() == 0) {
                this.contentStack.set_visible_child (this.emptyState);
                return;
            }
            this.contentStack.set_visible_child (this.flowBox);

            foreach (var app in this.state.apps) {
                var card = new Views.OverviewCard(app);
                // Add click gesture to select app
                var click = new Gtk.GestureClick();
                click.released.connect((n, x, y) => {
                    this.state.selectedApp = app;
                    this.state.changed();
                });
                card.add_controller(click);
                this.flowBox.append(card);
                this.cards.append(card);
            }
        }

        private void onStartAllClicked () {
            Logic.ComposeDeck.startAllApps();
        }

        private void onStopAllClicked () {
            Logic.ComposeDeck.stopAllApps();
        }
    }
}