using GLib;
using Json;

namespace Logic {
    /*
     * ComposeService — talks with the Compose provider (podman) over its
     * Docker-compatible socket. No business orchestration here.
     */

    public class ComposeService {
        public static bool isRunning (string path) {
            string projectName = GLib.Path.get_basename(path).down();

            string? runtime = Environment.get_variable("XDG_RUNTIME_DIR");
            if (runtime == null) return false;
            string sock = runtime + "/podman/podman.sock";
            if (!GLib.File.new_for_path(sock).query_exists()) return false;

            try {
                var socket = new GLib.Socket(GLib.SocketFamily.UNIX, GLib.SocketType.STREAM, GLib.SocketProtocol.DEFAULT);
                var addr = new GLib.UnixSocketAddress(sock);
                socket.connect(addr, null);
                socket.set_timeout(5);

                string filter = "{\"label\":[\"com.docker.compose.project=" + projectName + "\"]}";
                string encoded = GLib.Uri.escape_string(filter);
                string request = "GET /containers/json?all=true&filters=" + encoded + " HTTP/1.0\r\nHost: localhost\r\n\r\n";
                var reqBytes = request.data;
                socket.send(reqBytes, null);

                var buf = new uint8[65536];
                var response = new GLib.ByteArray();
                ssize_t received;
                while ((received = socket.receive(buf, null)) > 0) {
                    response.append(buf[:received]);
                }
                response.append(new uint8[] { 0 });
                socket.close();

                string resp = (string) response.data;
                int bodyStart = resp.index_of("\r\n\r\n");
                if (bodyStart < 0) return false;
                string body = resp.substring(bodyStart + 4);

                var parser = new Json.Parser();
                parser.load_from_data(body, -1);
                var root = parser.get_root();
                if (root == null) return false;
                var array = root.get_array();
                if (array == null) return false;

                for (int i = 0; i < array.get_length(); i++) {
                    var obj = array.get_object_element(i);
                    if (obj == null) continue;
                    string state = obj.get_string_member("State");
                    if (state == "running") return true;
                }
                return false;
            } catch (Error e) {
                return false;
            }
        }
    }
}
