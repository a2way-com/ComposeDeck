using GLib;
using Json;

/*
 * ComposeService — business logic for discovering Compose applications
 * under ~/Apps/ and detecting their running status via the podman socket.
 *
 * This class contains NO UI code.
 */

public class ComposeService {
    public const string APPS_SUBDIR = "Apps";

    public static List<ComposeApp> discover_apps () {
        var apps = new List<ComposeApp> ();
        string home = Environment.get_home_dir ();
        string apps_dir = home + "/" + APPS_SUBDIR;

        try {
            var handle = Dir.open (apps_dir);
            string? entry;
            while ((entry = handle.read_name ()) != null) {
                if (entry == null || entry.has_prefix ("."))
                    continue;
                string path = apps_dir + "/" + entry;
                var file = File.new_for_path (path);
                if (file.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS) != FileType.DIRECTORY)
                    continue;

                var yaml = File.new_for_path (path + "/compose.yaml");
                var yml = File.new_for_path (path + "/docker-compose.yaml");
                if (!yaml.query_exists () && !yml.query_exists ())
                    continue;

                bool running = is_running (path);
                apps.append (new ComposeApp (entry, path, running));
            }
        } catch (Error e) {
            // ~/Apps/ may not exist yet
        }

        apps.sort ((a, b) => {
            if (a.name < b.name) return -1;
            if (a.name > b.name) return 1;
            return 0;
        });
        return apps;
    }

    public static bool is_running (string path) {
        string project_name = GLib.Path.get_basename (path).down ();

        string? runtime = Environment.get_variable ("XDG_RUNTIME_DIR");
        if (runtime == null) return false;
        string sock = runtime + "/podman/podman.sock";
        if (!File.new_for_path (sock).query_exists ()) return false;

        try {
            var socket = new Socket (SocketFamily.UNIX, SocketType.STREAM, SocketProtocol.DEFAULT);
            var addr = new GLib.UnixSocketAddress (sock);
            socket.connect (addr, null);
            socket.set_timeout (5);

            string filter = "{\"label\":[\"com.docker.compose.project=" + project_name + "\"]}";
            string encoded = Uri.escape_string (filter);
            string request = "GET /containers/json?all=true&filters=" + encoded + " HTTP/1.0\r\nHost: localhost\r\n\r\n";
            var req_bytes = request.data;
            socket.send (req_bytes, null);

            var buf = new uint8[65536];
            var response = new ByteArray ();
            ssize_t n;
            while ((n = socket.receive (buf, null)) > 0) {
                response.append (buf[:n]);
            }
            response.append (new uint8[] { 0 });
            socket.close ();

            string resp = (string) response.data;
            int body_start = resp.index_of ("\r\n\r\n");
            if (body_start < 0) return false;
            string body = resp.substring (body_start + 4);

            var parser = new Parser ();
            parser.load_from_data (body, -1);
            var root = parser.get_root ();
            if (root == null) return false;
            var array = root.get_array ();
            if (array == null) return false;

            for (int i = 0; i < array.get_length (); i++) {
                var obj = array.get_object_element (i);
                if (obj != null) {
                    string state = obj.get_string_member ("State");
                    if (state == "running") return true;
                }
            }
            return false;
        } catch (Error e) {
            return false;
        }
    }

    public static void compute_stats (out int total, out int running_count) {
        total = 0;
        running_count = 0;

        string home = Environment.get_home_dir ();
        string apps_dir = home + "/" + APPS_SUBDIR;

        try {
            var handle = Dir.open (apps_dir);
            string? entry;
            while ((entry = handle.read_name ()) != null) {
                if (entry == null || entry.has_prefix ("."))
                    continue;
                string path = apps_dir + "/" + entry;
                var file = File.new_for_path (path);
                if (file.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS) != FileType.DIRECTORY)
                    continue;

                var yaml = File.new_for_path (path + "/compose.yaml");
                var yml = File.new_for_path (path + "/docker-compose.yaml");
                if (!yaml.query_exists () && !yml.query_exists ())
                    continue;

                total++;
                if (is_running (path)) {
                    running_count++;
                }
            }
        } catch (Error e) {
            // ~/Apps/ may not exist yet
        }
    }
}