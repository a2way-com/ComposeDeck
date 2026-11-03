using Gtk;
using Adw;
using GLib;
using Logic;

namespace Views {
    /*
     * ContentArea — view partial (right content pane).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/ContentArea.ui")]
    [CCode (cname = "ContentArea")]
    public class ContentArea : Gtk.Box {
        [GtkChild] public unowned Gtk.Box contentBox;
        [GtkChild] private unowned Adw.WindowTitle contentTitle;

        private Logic.State state;

        private OverviewPage overviewPage;
        private AppDetailsPage appDetailsPage;

        public OverviewPage overview {
            get { return this.overviewPage; }
        }

        public AppDetailsPage details {
            get { return this.appDetailsPage; }
        }

        public ContentArea () {
            this.state = Logic.Application.getState();
            this.state.changed.connect(this.render);
            this.overviewPage = new OverviewPage();
            this.appDetailsPage = new AppDetailsPage();
            this.contentBox.append(this.overviewPage);
            this.contentBox.append(this.appDetailsPage);
            this.render();
        }

        private void render () {
            this.overviewPage.updateStats();
            if (this.state.overviewSelected) {
                this.showOverview();
            } else {
                string path = this.state.selectedPath ?? "";
                if (path == "") {
                    this.showOverview();
                    return;
                }
                string name = path;
                bool run = false;
                foreach (var app in this.state.apps) {
                    if (app.path == path) {
                        name = app.name;
                        run = app.running;
                    }
                }
                this.showApp(name, path, run);
            }
        }

        public void showOverview () {
            if (this.overviewPage != null) this.overviewPage.show();
            if (this.appDetailsPage != null) this.appDetailsPage.hide();
            this.contentTitle.title = "Overview";
        }

        public void showApp (string name, string path, bool running) {
            if (this.overviewPage != null) this.overviewPage.hide();
            if (this.appDetailsPage != null) this.appDetailsPage.showApp(name, path, running);
            this.contentTitle.title = name;
        }
    }
}