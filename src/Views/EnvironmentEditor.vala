using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * EnvironmentEditor — edits the .env file of one compose project.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/EnvironmentEditor.ui")]
    [CCode (cname = "EnvironmentEditor")]
    public class EnvironmentEditor : Adw.Dialog {
        [GtkChild] private unowned Gtk.ListBox variableList;
        [GtkChild] private unowned Gtk.Button addButton;
        [GtkChild] private unowned Gtk.Button cancelButton;
        [GtkChild] private unowned Gtk.Button saveButton;
        [GtkChild] private unowned Gtk.CheckButton applyCheck;
        [GtkChild] private unowned Gtk.Label fileLabel;
        [GtkChild] private unowned Gtk.Label emptyLabel;
        [GtkChild] private unowned Adw.ToastOverlay toastOverlay;
        [GtkChild] private unowned Adw.WindowTitle windowTitle;

        private Logic.ComposeApp app;
        private Logic.EnvDocument document;
        private List<Views.EnvVariableRow> rows = new List<Views.EnvVariableRow> ();

        public EnvironmentEditor (Logic.ComposeApp app) {
            this.app = app;
            this.windowTitle.set_subtitle (app.name);

            string path = Logic.EnvDocument.envPath (app.path);
            this.fileLabel.set_text (path);

            string? error;
            this.document = Logic.EnvDocument.load (path, out error);
            if (error != null) {
                this.toastOverlay.add_toast (
                    new Adw.Toast ("Could not read .env: %s".printf (error)));
            }

            this.cancelButton.clicked.connect (() => this.close ());
            this.saveButton.clicked.connect (this.onSaveClicked);
            this.addButton.clicked.connect (this.onAddClicked);

            bool hasContainers = false;
            foreach (var service in app.services) {
                if (service.containerName != "") {
                    hasContainers = true;
                    break;
                }
            }
            bool running = app.runningCount > 0;
            this.applyCheck.set_visible (hasContainers);
            this.applyCheck.set_active (running);
            this.applyCheck.set_tooltip_text (
                "Runs compose up, which recreates the containers and starts the app if it is stopped.");

            var entries = this.document.entries ();
            entries.sort ((a, b) => {
                int comparison = strcmp (a.key.up (), b.key.up ());
                if (comparison != 0) return comparison;
                return strcmp (a.key, b.key);
            });
            foreach (var line in entries) {
                this.appendRow (line);
            }
            this.updateEmptyState ();
        }

        private Views.EnvVariableRow appendRow (Logic.EnvLine line) {
            var row = new Views.EnvVariableRow (line, this.document.commentFor (line));
            row.remove_requested.connect (() => this.onRemoveRequested (row));
            this.variableList.append (row);
            this.rows.append (row);
            return row;
        }

        private void onRemoveRequested (Views.EnvVariableRow row) {
            this.variableList.remove (row);
            this.rows.remove (row);
            this.document.removeLine (row.line);
            this.updateEmptyState ();
        }

        private void onAddClicked () {
            if (!this.commitRows ()) {
                this.toastOverlay.add_toast (new Adw.Toast ("Fix the highlighted names first."));
                return;
            }

            var line = this.document.appendEntry ("", "");
            var row = this.appendRow (line);
            this.updateEmptyState ();
            row.grabKeyFocus ();
        }

        /*
         * Copies edited values into the document and reports whether every
         * key is a valid, unique variable name.
         */
        private bool commitRows () {
            var seen = new GLib.HashTable<string, bool> (str_hash, str_equal);
            bool allValid = true;

            foreach (var row in this.rows) {
                string key = row.keyText ();
                bool valid = Logic.EnvDocument.isValidKey (key) && !seen.contains (key);
                row.setInvalid (!valid);
                if (!valid) {
                    allValid = false;
                    continue;
                }
                seen.insert (key, true);
                row.commit ();
            }
            return allValid;
        }

        private void updateEmptyState () {
            this.emptyLabel.set_visible (this.rows.length () == 0);
            this.variableList.set_visible (this.rows.length () > 0);
        }

        private void onSaveClicked () {
            if (!this.commitRows ()) {
                this.toastOverlay.add_toast (
                    new Adw.Toast ("Give every variable a unique name."));
                return;
            }

            bool recreate = this.applyCheck.get_visible () && this.applyCheck.get_active ();
            if (!Logic.ComposeDeck.saveEnvDocument (this.app, this.document)) {
                return;
            }

            if (recreate) {
                Logic.ComposeDeck.recreateApp (this.app);
            } else {
                var state = Logic.Application.getState ();
                state.actionSuccess = "Environment saved.";
                state.changed ();
            }
            this.close ();
        }
    }
}
