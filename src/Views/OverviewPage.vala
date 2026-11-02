using Gtk;
using Logic;

namespace Views {
    /*
     * OverviewPage — overview page partial: title + stat labels.
     * UI is defined in OverviewPage.ui(GtkBuilder XML, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OverviewPage.ui")]
    [CCode (cname = "OverviewPage")]
    public class OverviewPage : Gtk.Box {
        [GtkChild] private unowned Gtk.Label totalValue;
        [GtkChild] private unowned Gtk.Label runningValue;
        [GtkChild] private unowned Gtk.Label stoppedValue;

        public OverviewPage () {
        }

        public void updateStats (int total, int runningCount) {
            int stoppedCount = total - runningCount;

            totalValue.set_text(total.to_string());
            runningValue.set_markup("<span foreground='#4CAF50'><b>%d</b></span>".printf(runningCount));
            stoppedValue.set_markup("<span foreground='#F44336'><b>%d</b></span>".printf(stoppedCount));
        }

        public void show () {
            set_visible(true);
        }

        public void hide () {
            set_visible(false);
        }
    }
}
