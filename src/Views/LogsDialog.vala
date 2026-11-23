using Gtk;
using Adw;
using GLib;
using Gdk;
using Logic;

namespace Views {
    /*
     * LogsDialog — container log viewer with refresh, copy, and save.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/LogsDialog.ui")]
    [CCode (cname = "LogsDialog")]
    public class LogsDialog : Adw.MessageDialog {
        [GtkChild] private unowned Gtk.DropDown tailDrop;
        [GtkChild] private unowned Gtk.Button refreshButton;
        [GtkChild] private unowned Gtk.Button copyButton;
        [GtkChild] private unowned Gtk.Button saveButton;
        [GtkChild] private unowned Gtk.TextView logView;

        private string containerName;
        private string serviceName;
        private int logsGeneration = 0;

        public LogsDialog (string containerName, string serviceName, Gtk.Window? parentWindow = null) {
            this.containerName = containerName;
            this.serviceName = serviceName;

            this.set_transient_for (parentWindow);
            this.set_heading ("Logs — %s".printf (this.serviceName));

            this.tailDrop.set_model (new Gtk.StringList (new string[] {
                "200 lines", "1000 lines", "All"
            }));
            this.tailDrop.set_selected (0);

            this.refreshButton.clicked.connect (() => {
                this.loadLogs (this.logsTailForIndex (this.tailDrop.get_selected ()));
            });
            this.tailDrop.notify["selected"].connect (() => {
                this.loadLogs (this.logsTailForIndex (this.tailDrop.get_selected ()));
            });
            this.copyButton.clicked.connect (() => {
                var display = Gdk.Display.get_default ();
                display.get_clipboard ().set_text (this.logText ());
            });
            this.saveButton.clicked.connect (this.saveLogsToFile);

            this.add_response ("close", "Close");
            this.set_default_response ("close");
            this.set_close_response ("close");

            this.loadLogs (200);
        }

        private int logsTailForIndex (uint index) {
            switch (index) {
                case 1:
                    return 1000;
                case 2:
                    return 0;
                default:
                    return 200;
            }
        }

        private string logText () {
            var buffer = this.logView.get_buffer ();
            Gtk.TextIter start;
            Gtk.TextIter end;
            buffer.get_start_iter (out start);
            buffer.get_end_iter (out end);
            return buffer.get_text (start, end, true);
        }

        private void loadLogs (int tail) {
            this.logsGeneration++;
            int generation = this.logsGeneration;
            this.logView.get_buffer ().set_text ("Loading logs...");
            GLib.Thread.create<int> (() => {
                string? logs = Logic.ComposeService.containerLogs (this.containerName, tail);
                string text = logs != null && logs != "" ? logs : "No logs available.";
                GLib.MainContext.default ().invoke (() => {
                    if (generation == this.logsGeneration) {
                        this.logView.get_buffer ().set_text (text);
                    }
                    return false;
                });
                return 0;
            }, false);
        }

        private void saveLogsToFile () {
            var fileDialog = new Gtk.FileDialog ();
            fileDialog.set_title ("Save logs");
            fileDialog.set_initial_name ("%s-logs.txt".printf (this.serviceName));
            fileDialog.save.begin (this.get_transient_for (), null, (source, result) => {
                try {
                    var file = fileDialog.save.end (result);
                    if (file == null) return;
                    string text = this.logText ();
                    var stream = file.replace (null, false, GLib.FileCreateFlags.REPLACE_DESTINATION, null);
                    var data = new uint8[text.length];
                    for (int i = 0; i < text.length; i++) {
                        data[i] = (uint8) text[i];
                    }
                    stream.write_all (data, null);
                    stream.close (null);
                    var state = Logic.Application.getState ();
                    state.actionSuccess = "Logs saved.";
                    state.changed ();
                } catch (Error e) {
                    // Cancelled.
                }
            });
        }
    }
}
