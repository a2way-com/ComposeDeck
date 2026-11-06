using Gtk;

namespace Views {
    /*
     * OverviewPage — overview page partial: title + stat labels.
     * UI is defined in OverviewPage.ui (GTK blueprint, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OverviewPage.ui")]
    [CCode (cname = "OverviewPage")]
    public class OverviewPage : Gtk.Box {
        [GtkChild] private unowned Gtk.Label totalValue;
        [GtkChild] private unowned Gtk.Label runningValue;
        [GtkChild] private unowned Gtk.Label stoppedValue;

        private Logic.State state;

        public OverviewPage () {
            this.state = Logic.Application.getState();
            this.state.changed.connect(this.render);
            this.render();
        }

        private void render () {
            this.updateStats();
            this.set_visible(this.state.selectedApp == null);
        }

        public void updateStats () {
            int total = this.state.total;
            int runningCount = this.state.runningCount;
            int stoppedCount = total - runningCount;

            this.totalValue.set_text(total.to_string());
            this.runningValue.set_markup("<span foreground='#4CAF50'><b>%d</b></span>".printf(runningCount));
            this.stoppedValue.set_markup("<span foreground='#F44336'><b>%d</b></span>".printf(stoppedCount));
        }
    }
}
