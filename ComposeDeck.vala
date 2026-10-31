using Adw;

/*
 * ComposeDeck — application entry point.
 *
 * UI is defined in .ui files (GtkBuilder XML) embedded in a GResource,
 * and loaded via [GtkTemplate].
 *
 * App id (RNDS): com.a2way.ComposeDeck
 * Executable:  composedeck
 *
 * Build:
 *   glib-compile-resources --sourcedir=. --generate-source --target=compose-deck.c compose-deck.gresource.xml
 *   valac --pkg gtk4 --pkg gio-2.0 --pkg libadwaita-1 --gresources=compose-deck.gresource.xml \
 *     ComposeDeck.vala Window.vala AppRow.vala OverviewRow.vala Sidebar.vala OverviewPage.vala AppDetailsPage.vala -o composedeck
 */

const string APP_ID = "com.a2way.ComposeDeck";

class ComposeDeckApplication : Adw.Application {
    private Window? window;

    public ComposeDeckApplication () {
        Object (application_id: APP_ID);
    }

    protected override void activate () {
        if (window == null) {
            window = new Window (this);
        }
        window.present ();
    }
}

int main (string[] args) {
    return new ComposeDeckApplication ().run (args);
}
