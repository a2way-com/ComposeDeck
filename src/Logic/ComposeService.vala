using GLib;
using Json;

namespace Logic {
    /*
     * ComposeService — talks with the Compose provider (podman) over its
     * Docker-compatible socket. No business orchestration here.
     */

    public class ComposeService {
        private static int64 lastActivation = 0;

        private static bool canConnect (string sock) {
            if (!GLib.File.new_for_path(sock).query_exists()) return false;
            try {
                var probe = new GLib.Socket(GLib.SocketFamily.UNIX, GLib.SocketType.STREAM, GLib.SocketProtocol.DEFAULT);
                probe.connect(new GLib.UnixSocketAddress(sock), null);
                probe.close();
                return true;
            } catch (Error e) {
                // Listening socket not accepting yet; treat as not ready.
                return false;
            }
        }

        private static void startService () {
            try {
                var proxy = new GLib.DBusProxy.for_bus_sync(GLib.BusType.SESSION,
                    GLib.DBusProxyFlags.NONE, null,
                    "org.freedesktop.systemd1",
                    "/org/freedesktop/systemd1",
                    "org.freedesktop.systemd1.Manager", null);
                if (proxy != null) {
                    proxy.call_sync("StartUnit",
                        new GLib.Variant("(ss)", "podman.service", "replace"),
                        GLib.DBusCallFlags.NONE, 1000, null);
                }
            } catch (Error e) {
                // systemd unreachable; ignore and retry on the next poll.
            }
            ComposeService.lastActivation = GLib.get_monotonic_time();
        }

        /*
         * Makes sure the Podman API is reachable. On a cold boot nothing
         * runs podman, so this starts the systemd unit when needed. Failed
         * activation attempts are throttled to once per 30s so a broken
         * podman can't turn every poll into a unit-start storm.
         */
        public static bool ensureService () {
            string? runtime = Environment.get_variable("XDG_RUNTIME_DIR");
            if (runtime == null) return false;
            string sock = runtime + "/podman/podman.sock";

            if (ComposeService.canConnect(sock)) return true;

            int64 now = GLib.get_monotonic_time();
            if (now - ComposeService.lastActivation > 30 * 1000 * 1000) {
                GLib.debug("podman not reachable, activating podman.service");
                ComposeService.startService();
                for (int i = 0; i < 10; i++) {
                    if (ComposeService.canConnect(sock)) return true;
                    GLib.Thread.usleep(100 * 1000);
                }
            }
            return false;
        }

        public static bool isRunning (string path) {
            if (!ComposeService.ensureService()) return false;

            string projectName = GLib.Path.get_basename(path).down();

            string? runtime = Environment.get_variable("XDG_RUNTIME_DIR");
            if (runtime == null) return false;
            string sock = runtime + "/podman/podman.sock";

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
