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
        [GtkChild] public unowned Gtk.Box content_box;
        [GtkChild] private unowned Adw.WindowTitle content_title;

        private OverviewPage overview_page;
        private AppDetailsPage app_details_page;

        public OverviewPage overview {
            get { return overview_page; }
        }

        public AppDetailsPage details {
            get { return app_details_page; }
        }

        public ContentArea () {
            overview_page = new OverviewPage ();
            app_details_page = new AppDetailsPage ();
            if (content_box != null) {
                content_box.append (overview_page);
                content_box.append (app_details_page);
            }
            show_overview ();
        }

        public void show_overview () {
            if (overview_page != null) overview_page.show ();
            if (app_details_page != null) app_details_page.hide ();
            if (content_title != null) content_title.title = "Overview";
        }

        public void show_app (string name, string path, bool running) {
            if (overview_page != null) overview_page.hide ();
            if (app_details_page != null) app_details_page.show_app (name, path, running);
            if (content_title != null) content_title.title = name;
        }
    }
}
