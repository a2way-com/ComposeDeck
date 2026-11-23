using Gtk;
using Adw;
using GLib;
using Gdk;
using Logic;

namespace Views {
    /*
     * ShortcutRow — preview of one published desktop shortcut.
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/ShortcutRow.ui")]
    [CCode (cname = "ShortcutRow")]
    public class ShortcutRow : Adw.ActionRow {
        [GtkChild] private unowned Gtk.Button changeButton;
        [GtkChild] private unowned Gtk.Button openButton;

        public signal void change_requested ();
        public signal void open_requested ();

        public ShortcutRow (Logic.AppShortcut shortcut) {
            this.set_title (shortcut.name);
            if (shortcut.url != "") {
                this.set_subtitle (shortcut.url);
            }
            this.set_tooltip_text ("Open %s".printf (shortcut.name));

            var icon = this.buildIcon (shortcut.icon);
            icon.set_valign (Gtk.Align.CENTER);
            this.add_prefix (icon);

            this.openButton.set_tooltip_text (shortcut.ownBrowser ? "Open in own browser" : "Open in browser");
            this.changeButton.clicked.connect (() => this.change_requested ());
            this.openButton.clicked.connect (() => this.open_requested ());
            this.activated.connect (() => this.open_requested ());
        }

        private Gtk.Image buildIcon (string iconValue) {
            var image = new Gtk.Image ();
            image.set_pixel_size (40);

            if (iconValue.has_prefix ("/") && GLib.File.new_for_path (iconValue).query_exists ()) {
                image.set_from_file (iconValue);
                return image;
            }

            if (iconValue != "") {
                var display = Gdk.Display.get_default ();
                var theme = display != null ? Gtk.IconTheme.get_for_display (display) : null;
                if (theme != null && theme.has_icon (iconValue)) {
                    image.icon_name = iconValue;
                    return image;
                }
            }

            image.icon_name = "application-x-executable-symbolic";
            return image;
        }
    }
}
