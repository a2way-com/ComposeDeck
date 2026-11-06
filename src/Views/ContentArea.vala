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
            var selected = this.state.selectedApp;
            if (selected == null) {
                this.showOverview();
                return;
            }
            this.showApp();
        }

        public void showOverview () {
            this.overviewPage.show();
            this.appDetailsPage.hide();
            this.contentTitle.title = "Overview";
        }

        public void showApp () {
            this.overviewPage.hide();
            this.appDetailsPage.showApp();
            var selected = this.state.selectedApp;
            if (selected != null) {
                this.contentTitle.title = selected.name;
            }
        }
    }
}
