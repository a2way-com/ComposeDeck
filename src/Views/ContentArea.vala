using Gtk;
using Adw;
using Logic;

namespace Views {
    /*
     * ContentArea — view partial for the right-hand content pane.
     * Owns its header (with dynamic title) and the page stack
     * (Overview / AppDetails).
     */

    [GtkTemplate (ui = "/com/a2way/ComposeDeck/ContentArea.ui")]
    [CCode (cname = "ContentArea")]
    public class ContentArea : Gtk.Box {
        [GtkChild] public unowned Gtk.Box contentBox;
        [GtkChild] private unowned Adw.WindowTitle contentTitle;

        private OverviewPage overviewPage;
        private AppDetailsPage appDetailsPage;

        public OverviewPage overview {
            get { return overviewPage; }
        }

        public AppDetailsPage details {
            get { return appDetailsPage; }
        }

        public ContentArea () {
            overviewPage = new OverviewPage();
            appDetailsPage = new AppDetailsPage();
            contentBox.append(overviewPage);
            contentBox.append(appDetailsPage);
            showOverview();
        }

        public void showOverview () {
            if (overviewPage != null) overviewPage.show();
            if (appDetailsPage != null) appDetailsPage.hide();
            contentTitle.title = "Overview";
        }

        public void showApp (string name, string path, bool running) {
            if (overviewPage != null) overviewPage.hide();
            if (appDetailsPage != null) appDetailsPage.showApp(name, path, running);
            contentTitle.title = name;
        }
    }
}
