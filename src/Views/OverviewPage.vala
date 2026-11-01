using Gtk;
using Logic;

namespace Views {
    /*
     * OverviewPage — overview page partial: title + stat labels.
     * UI is defined in OverviewPage.ui (GtkBuilder XML, loaded via GResource).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OverviewPage.ui")]
    [CCode (cname = "OverviewPage")]
    public class OverviewPage : Gtk.Box {
        [GtkChild] private unowned Gtk.Label total_value;
        [GtkChild] private unowned Gtk.Label running_value;
        [GtkChild] private unowned Gtk.Label stopped_value;

        public OverviewPage () {
        }

        public void update_stats (int total, int running_count) {
            int stopped_count = total - running_count;

            total_value.set_text (total.to_string ());
            running_value.set_markup ("<span foreground='#4CAF50'><b>%d</b></span>".printf (running_count));
            stopped_value.set_markup ("<span foreground='#F44336'><b>%d</b></span>".printf (stopped_count));
        }

        public void show () {
            set_visible (true);
        }

        public void hide () {
            set_visible (false);
        }
    }
}
