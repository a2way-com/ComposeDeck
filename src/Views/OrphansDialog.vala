using Gtk;
using Adw;
using GLib;

namespace Views {
    /*
     * OrphansDialog — confirmation for removing containers that are no
     * longer declared in the compose file.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/OrphansDialog.ui")]
    [CCode (cname = "OrphansDialog")]
    public class OrphansDialog : Adw.MessageDialog {
        public OrphansDialog (string names, Gtk.Window? parentWindow = null) {
            this.set_transient_for (parentWindow);
            this.set_body ("These containers are not declared in the compose file: %s".printf (names));

            this.add_response ("cancel", "Cancel");
            this.add_response ("remove", "Remove");
            this.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            this.set_default_response ("cancel");
            this.set_close_response ("cancel");
        }
    }
}
