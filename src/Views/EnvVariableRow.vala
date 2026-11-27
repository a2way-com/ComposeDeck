using Gtk;
using GLib;
using Logic;

namespace Views {
    /*
     * EnvVariableRow — one editable key/value pair in the environment
     * editor.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/EnvVariableRow.ui")]
    [CCode (cname = "EnvVariableRow")]
    public class EnvVariableRow : Gtk.ListBoxRow {
        [GtkChild] private unowned Gtk.Entry keyEntry;
        [GtkChild] private unowned Gtk.Entry valueEntry;
        [GtkChild] private unowned Gtk.ToggleButton revealButton;
        [GtkChild] private unowned Gtk.Button removeButton;
        [GtkChild] private unowned Gtk.Label commentLabel;

        public Logic.EnvLine line { get; private set; }
        public signal void remove_requested ();

        public EnvVariableRow (Logic.EnvLine line, string comment = "") {
            this.line = line;
            this.keyEntry.set_text (line.key);
            this.valueEntry.set_text (line.value);
            this.commentLabel.set_text (comment);
            this.commentLabel.set_visible (comment != "");

            this.revealButton.toggled.connect (() => {
                bool shown = this.revealButton.get_active ();
                this.valueEntry.set_visibility (shown);
                this.revealButton.set_tooltip_text (shown ? "Hide value" : "Show value");
            });
            this.keyEntry.changed.connect (this.updateSecretState);
            this.removeButton.clicked.connect (() => this.remove_requested ());

            this.updateSecretState ();
        }

        public string keyText () {
            return this.keyEntry.get_text ().strip ();
        }

        public string valueText () {
            return this.valueEntry.get_text ();
        }

        /*
         * Copies the edited values into the line. The line then renders
         * from the key and value instead of its original text.
         */
        public void commit () {
            string key = this.keyText ();
            string value = this.valueText ();
            if (key == this.line.key && value == this.line.value) return;
            this.line.key = key;
            this.line.value = value;
            this.line.dirty = true;
        }

        public void setInvalid (bool invalid) {
            if (invalid) {
                this.keyEntry.add_css_class ("error");
                this.keyEntry.set_tooltip_text ("Enter a unique variable name");
            } else {
                this.keyEntry.remove_css_class ("error");
                this.keyEntry.set_tooltip_text ("Variable name");
            }
        }

        public void grabKeyFocus () {
            this.keyEntry.grab_focus ();
        }

        private void updateSecretState () {
            bool secret = Logic.EnvDocument.isSecretKey (this.keyEntry.get_text ());
            this.revealButton.set_visible (secret);
            if (!secret) {
                this.valueEntry.set_visibility (true);
                this.revealButton.set_active (false);
            } else if (!this.revealButton.get_active ()) {
                this.valueEntry.set_visibility (false);
            }
        }
    }
}
