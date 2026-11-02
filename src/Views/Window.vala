using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * Window — pure GUI view for ComposeDeck (reads state; does not drive).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/Window.ui")]
    [CCode (cname = "Window")]
    public class Window : Adw.ApplicationWindow {
        [GtkChild] private unowned Adw.NavigationSplitView splitView;
        [GtkChild] private unowned Gtk.Box sidebarBox;
        [GtkChild] private unowned Gtk.Box contentBox;

        public Sidebar sidebar { get; private set; }
        public ContentArea contentArea { get; private set; }
        public OverviewRow? overviewRow { get; set; default = null; }
        public AppRow? activeRow { get; set; default = null; }

        public Window (Adw.Application app) {
            set_application(app);

            prepareView();
            setupHamburger();
            connectState();
        }

        private void prepareView () {
            sidebar = new Sidebar ();
            contentArea = new ContentArea ();

            sidebarBox.append(sidebar);
            contentBox.append(contentArea);
        }

        private void connectState () {
            var state = Logic.Application.getState();
            if (state != null) {
                state.changed.connect(render);
            }
        }

        private void setupHamburger () {
            var sidebarRef = sidebar;
            if (sidebarRef == null || sidebarRef.menuButton == null) return;

            sidebarRef.menuButton.notify["active"].connect(() => {
                if (sidebarRef.menuButton.active) {
                    GLib.Idle.add(() => {
                        set_focus(null);
                        return GLib.Source.REMOVE;
                    });
                }
            });

            var menu = new GLib.Menu();
            menu.append("About", "win.about");
            menu.append("Quit", "win.quit");
            sidebarRef.menuButton.set_menu_model(menu);

            var aboutAction = new GLib.SimpleAction("about", null);
            aboutAction.activate.connect((action, param) => onAboutClicked ());
            add_action(aboutAction);

            var quitAction = new GLib.SimpleAction("quit", null);
            quitAction.activate.connect((action, param) => onQuitClicked ());
            add_action(quitAction);
        }

        /* ---------- Signal handlers (UI only) ---------- */

        private void onSearchChanged (Gtk.Editable editable) {
            // Search handling now lives in Sidebar; keep for backward compat.
        }

        private void onQuitClicked () {
            close();
        }

        private void onAboutClicked () {
            var about = new Adw.AboutDialog();
            about.application_name = ComposeDeck.APP_NAME;
            about.application_icon = "com.a2way.ComposeDeck";
            about.developer_name = ComposeDeck.DEVELOPER_NAME;
            about.version = ComposeDeck.VERSION;
            about.comments = "Manage Compose applications under ~/Apps/.";
            about.present(this);
        }

        /* ----
         * View helpers
         */
        private void render () {
            var state = Logic.Application.getState();
            if (state == null || sidebar == null || contentArea == null) return;

            /* rebuild sidebar rows from state */
            sidebar.removeAllRows();

            overviewRow = new OverviewRow ();
            sidebar.listBox.append(overviewRow);

            foreach (var app in state.apps) {
                sidebar.listBox.append(new AppRow (app.path, app.name, app.running));
            }

            contentArea.overview.updateStats(state.total, state.runningCount);

            if (state.overviewSelected) {
                sidebar.listBox.select_row(overviewRow);
                contentArea.showOverview();
            } else {
                Gtk.Widget? selectedWidget = null;
                var child = sidebar.listBox.get_first_child();
                while (child != null) {
                    if (child is AppRow) {
                        var appRow = (AppRow) child;
                        if (state.selectedPath != null && appRow.path == state.selectedPath) {
                            selectedWidget = child;
                            break;
                        }
                    }
                    child = child.get_next_sibling();
                }
                if (selectedWidget == null) {
                    sidebar.listBox.select_row(overviewRow);
                    contentArea.showOverview();
                    return;
                }
                sidebar.listBox.select_row((Gtk.ListBoxRow) selectedWidget);
                var appRow = (AppRow) selectedWidget;
                string pname = appRow.name;
                string ppath = appRow.path;
                bool run = false;
                foreach (var app in state.apps) {
                    if (app.path == ppath) {
                        pname = app.name;
                        run = app.running;
                    }
                }
                contentArea.showApp(pname, ppath, run);
            }
        }
    }
}
