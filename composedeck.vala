using Gtk;
using GLib;

/*
 * ComposeDeck — GTK4/Vala app that lists Podman Compose projects
 * under ~/Apps/ with a running/stopped indicator.
 *
 * Name: ComposeDeck
 * Build:
 *   valac --pkg gtk4 --pkg gio-2.0 composedeck.vala -o composedeck
 */

const string COMPOSE_BIN = "/app/bin/docker-compose";
const string APPS_SUBDIR = "Apps";

class ComposeApp : Object {
    public ComposeApp (string name, string path, string compose_file, bool running) {
        this.name = name;
        this.path = path;
        this.compose_file = compose_file;
        this.running = running;
    }
    public string name { get; set; }
    public string path { get; set; }
    public string compose_file { get; set; }
    public bool running { get; set; }
}

class ComposeDeckWindow : Gtk.Window {
    private ComposeApp[] apps = { };

    private Gtk.ListStore store;
    private Gtk.TreeView app_list;
    private Gtk.Label info_label;

    public ComposeDeckWindow () {
        set_title ("ComposeDeck");
        set_default_size (800, 500);

        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
        paned.set_wide_handle (true);
        paned.set_position (300);

        // ---------- Left: app list ----------
        var list_scroll = new Gtk.ScrolledWindow ();
        list_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        list_scroll.set_vexpand (true);

        store = new Gtk.ListStore.newv ({ typeof(string) });
        app_list = new Gtk.TreeView ();
        app_list.set_model (store);
        app_list.set_headers_visible (false);
        app_list.set_activate_on_single_click (true);
        app_list.set_hexpand (true);
        app_list.set_vexpand (true);

        var sel = app_list.get_selection ();
        sel.set_mode (Gtk.SelectionMode.SINGLE);
        sel.changed.connect (on_selection_changed);

        var col_name = new Gtk.TreeViewColumn.with_attributes ("Name",
            new Gtk.CellRendererText (), "text", 0);
        col_name.set_expand (true);
        app_list.append_column (col_name);

        list_scroll.set_child (app_list);
        paned.set_start_child (list_scroll);

        // ---------- Right: app info ----------
        var details = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        details.set_margin_top (16);
        details.set_margin_bottom (16);
        details.set_margin_start (16);
        details.set_margin_end (16);
        details.set_vexpand (true);
        details.set_halign (Gtk.Align.START);

        info_label = new Gtk.Label ("No app selected");
        info_label.set_halign (Gtk.Align.START);
        info_label.set_hexpand (true);
        info_label.set_wrap (true);
        info_label.set_xalign (0);
        details.append (info_label);

        paned.set_end_child (details);

        // Header bar
        var header = new Gtk.HeaderBar ();
        header.set_title_widget (new Gtk.Label ("ComposeDeck"));
        var refresh_btn = new Gtk.Button.with_label ("Refresh Apps");
        refresh_btn.clicked.connect (() => populate_apps ());
        header.pack_end (refresh_btn);
        set_titlebar (header);

        set_child (paned);

        // Discover apps on startup
        populate_apps ();
    }

    /* ---------- Compose environment ---------- */

    private static void setup_compose_environment () {
        string? docker_host = Environment.get_variable ("DOCKER_HOST");
        if (docker_host == null || docker_host == "") {
            string? runtime = Environment.get_variable ("XDG_RUNTIME_DIR");
            if (runtime != null) {
                string sock = runtime + "/podman/podman.sock";
                if (GLib.File.new_for_path (sock).query_exists ())
                    docker_host = "unix://" + sock;
            }
        }

        if (docker_host != null)
            Environment.set_variable ("DOCKER_HOST", docker_host, true);
    }

    /* ---------- Running detection ---------- */

    private static bool is_app_running (string path) {
        setup_compose_environment ();
        string? stdout_str = null;
        string? stderr_str = null;
        int wait_status = -1;
        bool ok = false;
        try {
            ok = GLib.Process.spawn_sync (path,
                new string[] { COMPOSE_BIN, "ps", "--status", "running" },
                null, 0, null, out stdout_str, out stderr_str, out wait_status);
        } catch (Error err) {
            return false;
        }
        if (!ok) return false;
        string output = stdout_str ?? "";
        return output.contains ("Up") || output.contains ("running");
    }

    /* ---------- App discovery ---------- */

    private static ComposeApp[] discover_apps () {
        var found = new List<ComposeApp> ();
        string home = Environment.get_home_dir ();
        string apps_dir = home + "/" + APPS_SUBDIR;

        GLib.Dir apps_dir_handle;
        try {
            apps_dir_handle = GLib.Dir.open (apps_dir);
        } catch (Error e) {
            return new ComposeApp[0];
        }

        string? entry;
        while ((entry = apps_dir_handle.read_name ()) != null) {
            if (entry != null && entry.has_prefix ("."))
                continue;
            string path = apps_dir + "/" + entry;
            var file = GLib.File.new_for_path (path);
            if (file.query_file_type (GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS)
                != GLib.FileType.DIRECTORY)
                continue;

            string? compose_file = null;
            var yaml = GLib.File.new_for_path (path + "/compose.yaml");
            var yml = GLib.File.new_for_path (path + "/docker-compose.yml");
            if (yaml.query_exists ())
                compose_file = "compose.yaml";
            else if (yml.query_exists ())
                compose_file = "docker-compose.yml";
            if (compose_file == null)
                continue;

            bool running = is_app_running (path);
            found.append (new ComposeApp (entry, path, compose_file, running));
        }

        found.sort ((a, b) => {
            if (a.name < b.name) return -1;
            if (a.name > b.name) return 1;
            return 0;
        });

        ComposeApp[] result = { };
        foreach (ComposeApp app in found)
            result = result + app;
        return result;
    }

    private string status_markup (bool running) {
        if (running)
            return "<span foreground='#4CAF50' size='large'>&#9679;</span>";
        else
            return "<span foreground='#F44336' size='large'>&#9679;</span>";
    }

    private void populate_apps () {
        store.clear ();
        apps = { };
        foreach (ComposeApp app in discover_apps ()) {
            apps = apps + app;
            var iter = new Gtk.TreeIter ();
            store.append (out iter);
            store.set (iter, 0, app.name, -1);
        }

        if (apps.length == 0) {
            info_label.label = "No compose apps found in ~/Apps/";
        }
    }

    private void on_selection_changed () {
        var sel = app_list.get_selection ();
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        if (!sel.get_selected (out model, out iter)) {
            info_label.label = "No app selected";
            return;
        }

        var path = model.get_path (iter);
        if (path == null) {
            info_label.label = "No app selected";
            return;
        }
        int[]? indices = path.get_indices ();
        if (indices == null || indices.length == 0) {
            info_label.label = "No app selected";
            return;
        }

        var app = apps[indices[0]];
        string short_path = app.path;
        string home = Environment.get_home_dir ();
        if (short_path.has_prefix (home + "/"))
            short_path = "~" + short_path.substring (home.length);
        string status = status_markup (app.running);
        string status_text = app.running ? "Active" : "Stopped";
        info_label.set_markup ("<b>%s</b>\n%s\n%s %s".printf (
            app.name, short_path, status, status_text));
    }
}

int main (string[] args) {
    var app = new Gtk.Application ("com.a2way.ComposeDeck", GLib.ApplicationFlags.FLAGS_NONE);
    app.activate.connect (() => {
        var window = new ComposeDeckWindow ();
        window.set_application (app);
        window.present ();
    });
    return app.run (args);
}
