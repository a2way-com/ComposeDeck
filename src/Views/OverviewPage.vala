using Gtk;
using Adw;
using GLib;
using Gdk;
using Logic;

namespace Views {
    /*
     * OverviewPage — dashboard: aggregate stats + app cards grid.
     */
    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OverviewPage.ui")]
    [CCode (cname = "OverviewPage")]
    public class OverviewPage : Gtk.Box {
        [GtkChild] private unowned Adw.Banner podmanBanner;
        [GtkChild] private unowned Gtk.Label updatedLabel;
        [GtkChild] private unowned Gtk.Button refreshButton;
        [GtkChild] private unowned Gtk.Label totalValue;
        [GtkChild] private unowned Gtk.Label runningValue;
        [GtkChild] private unowned Gtk.Label stoppedValue;
        [GtkChild] private unowned Gtk.Label partialValue;
        [GtkChild] private unowned Gtk.Button startAllButton;
        [GtkChild] private unowned Gtk.Button stopAllButton;
        [GtkChild] private unowned Gtk.Button restartAllButton;
        [GtkChild] private unowned Adw.Spinner bulkSpinner;
        [GtkChild] private unowned Gtk.ToggleButton allFilter;
        [GtkChild] private unowned Gtk.ToggleButton runningFilter;
        [GtkChild] private unowned Gtk.ToggleButton partialFilter;
        [GtkChild] private unowned Gtk.ToggleButton stoppedFilter;
        [GtkChild] private unowned Gtk.ToggleButton pinnedFilter;
        [GtkChild] private unowned Gtk.Stack contentStack;
        [GtkChild] private unowned Gtk.FlowBox flowBox;
        [GtkChild] private unowned Gtk.Box emptyState;
        [GtkChild] private unowned Gtk.Label emptyTitle;
        [GtkChild] private unowned Gtk.Label emptyHint;

        private Logic.State state;
        private List<Views.OverviewCard> cards = new List<Views.OverviewCard> ();
        private string activeFilter = "all";

        public OverviewPage () {
            this.state = Logic.Application.getState();
            this.state.changed.connect(this.render);
            this.startAllButton.clicked.connect(this.onStartAllClicked);
            this.stopAllButton.clicked.connect(this.onStopAllClicked);
            this.restartAllButton.clicked.connect(this.onRestartAllClicked);
            this.podmanBanner.button_clicked.connect(() => Logic.ComposeDeck.discoverApps ());
            this.refreshButton.clicked.connect(() => Logic.ComposeDeck.discoverApps ());
            this.allFilter.toggled.connect(() => this.setFilter ("all", this.allFilter.get_active ()));
            this.runningFilter.toggled.connect(() => this.setFilter ("running", this.runningFilter.get_active ()));
            this.partialFilter.toggled.connect(() => this.setFilter ("partial", this.partialFilter.get_active ()));
            this.stoppedFilter.toggled.connect(() => this.setFilter ("stopped", this.stoppedFilter.get_active ()));
            this.pinnedFilter.toggled.connect(() => this.setFilter ("pinned", this.pinnedFilter.get_active ()));

            var nav = new Gtk.EventControllerKey ();
            nav.key_pressed.connect (this.onKeyPressed);
            this.add_controller (nav);

            this.render();
        }

        private bool onKeyPressed (uint keyval, uint keycode, Gdk.ModifierType mods) {
            if (this.cards.length() == 0) return false;
            int idx = -1;
            int i = 0;
            foreach (var card in this.cards) {
                if (card.has_focus) {
                    idx = i;
                    break;
                }
                i++;
            }
            if (idx < 0) return false;

            int columns = this.estimateColumns ();
            int next = idx;
            switch (keyval) {
                case Gdk.Key.Left:
                    next = idx - 1;
                    break;
                case Gdk.Key.Right:
                    next = idx + 1;
                    break;
                case Gdk.Key.Up:
                    next = idx - columns;
                    break;
                case Gdk.Key.Down:
                    next = idx + columns;
                    break;
                default:
                    return false;
            }
            if (next < 0 || next >= (int) this.cards.length()) return false;
            this.cards.nth_data (next).grab_focus ();
            return true;
        }

        private int estimateColumns () {
            int count = (int) this.cards.length ();
            if (count == 0) return 1;
            int width = this.flowBox.get_width ();
            int columns = width / (280 + 16);
            if (columns < 1) columns = 1;
            if (columns > count) columns = count;
            return columns;
        }

        private void setFilter (string filter, bool active) {
            if (!active) return;
            this.activeFilter = filter;
            this.rebuildCards ();
        }

        private void render () {
            this.podmanBanner.set_revealed (!this.state.podmanReachable);
            bool hasPinned = this.state.pinnedApps.length() > 0;
            this.pinnedFilter.set_visible (hasPinned);
            if (!hasPinned && this.activeFilter == "pinned") {
                this.allFilter.set_active (true);
            }
            this.updateFreshness ();
            this.updateStats();
            this.updateBulkButtons();
            this.rebuildCards();
            this.set_visible(this.state.selectedApp == null);
        }

        private void updateFreshness () {
            if (this.state.lastUpdated == 0) {
                this.updatedLabel.set_text ("");
                return;
            }
            int64 now = GLib.get_monotonic_time() / 1000 / 1000;
            int64 age = now - this.state.lastUpdated;
            if (age <= 1) {
                this.updatedLabel.set_text ("Updated just now");
            } else if (age < 60) {
                this.updatedLabel.set_text ("Updated %d s ago".printf ((int) age));
            } else {
                this.updatedLabel.set_text ("Updated %d min ago".printf ((int) (age / 60)));
            }
        }

        private void updateStats () {
            int total = 0;
            int runningCount = 0;
            int stoppedCount = 0;
            int partialCount = 0;
            foreach (var app in this.state.apps) {
                total++;
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
            this.restartAllButton.set_visible(!this.state.actionInProgress && this.state.apps.length() > 0);
            this.bulkSpinner.set_visible(this.state.actionInProgress);
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
                this.emptyTitle.set_text ("No apps found");
                this.emptyHint.set_text ("Add compose projects to your apps folder,\nor change it in Settings (hamburger menu).");
                this.contentStack.set_visible_child (this.emptyState);
                return;
            }

            var matching = new List<ComposeApp> ();
            foreach (var app in this.state.apps) {
                if (this.matchesFilter (app)) matching.append (app);
            }

            matching.sort ((a, b) => {
                int ra = OverviewPage.statusRank (a);
                int rb = OverviewPage.statusRank (b);
                if (ra != rb) return ra - rb;
                if (a.name < b.name) return -1;
                if (a.name > b.name) return 1;
                return 0;
            });

            // Pinned apps first when enabled, preserving the order above.
            var ordered = new List<ComposeApp> ();
            if (this.state.pinnedFirst) {
                foreach (var app in matching) {
                    if (this.state.isPinned (app.name)) ordered.append (app);
                }
                foreach (var app in matching) {
                    if (!this.state.isPinned (app.name)) ordered.append (app);
                }
            } else {
                foreach (var app in matching) {
                    ordered.append (app);
                }
            }


            if (ordered.length() == 0) {
                this.emptyTitle.set_text ("No matching apps");
                this.emptyHint.set_text ("Try a different filter.");
                this.contentStack.set_visible_child (this.emptyState);
                return;
            }

            this.contentStack.set_visible_child (this.flowBox);

            foreach (var app in ordered) {
                var card = new Views.OverviewCard(app);
                // Add click gesture to select app
                var click = new Gtk.GestureClick();
                click.released.connect((n, x, y) => {
                    this.state.selectedApp = app;
                    this.state.changed();
                });
                card.add_controller(click);
                card.set_cursor_from_name ("pointer");

                string status = app.serviceCount == 0
                    ? "never started"
                    : app.runningCount == app.serviceCount
                        ? "running"
                        : app.runningCount > 0
                            ? "%d of %d services running".printf (app.runningCount, app.serviceCount)
                            : "stopped";
                string summary = "%s, %s, %d service%s".printf (
                    app.name,
                    status,
                    app.serviceCount,
                    app.serviceCount == 1 ? "" : "s");
                var props = new Gtk.AccessibleProperty[] { Gtk.AccessibleProperty.LABEL };
                var values = new GLib.Value[1];
                values[0] = GLib.Value (typeof (string));
                values[0].set_string (summary);
                card.update_property_value (props, values);

                // Keyboard: focusable cards, Enter/Space opens details.
                card.set_focusable (true);
                card.set_focus_on_click (true);
                var key = new Gtk.EventControllerKey ();
                key.key_pressed.connect ((keyval, keycode, mods) => {
                    if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.space) {
                        this.state.selectedApp = app;
                        this.state.changed ();
                        return true;
                    }
                    return false;
                });
                card.add_controller (key);

                this.flowBox.append(card);
                this.cards.append(card);
            }
        }

        private static int statusRank (ComposeApp app) {
            if (app.serviceCount == 0) return 2;
            if (app.runningCount == app.serviceCount) return 0;
            if (app.runningCount > 0) return 1;
            return 2;
        }

        private bool matchesFilter (ComposeApp app) {
            switch (this.activeFilter) {
                case "running":
                    return app.serviceCount > 0 && app.runningCount == app.serviceCount;
                case "partial":
                    return app.serviceCount > 0 && app.runningCount > 0 && app.runningCount < app.serviceCount;
                case "stopped":
                    return app.runningCount == 0;
                case "pinned":
                    return this.state.isPinned (app.name);
                default:
                    return true;
            }
        }

        private void onStartAllClicked () {
            Logic.ComposeDeck.startAllApps();
        }

        private void onStopAllClicked () {
            Logic.ComposeDeck.stopAllApps();
        }

        private void onRestartAllClicked () {
            Logic.ComposeDeck.restartAllApps();
        }
    }
}