using GLib;
using Json;

namespace Logic {
    /*
     * ComposeService — talks with the Compose provider (podman) over its
     * Docker-compatible socket. No business orchestration here.
     */

    public class ComposeService {
        private static int64 lastActivation = 0;

        private static string? socketPath () {
            string? runtime = Environment.get_variable("XDG_RUNTIME_DIR");
            if (runtime == null) return null;
            return runtime + "/podman/podman.sock";
        }

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
            string? sock = ComposeService.socketPath();
            if (sock == null) return false;

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

        public static GLib.List<AppService> listServices (string path, out bool anyRunning) {
            anyRunning = false;
            var result = new GLib.List<AppService>();

            if (!ComposeService.ensureService()) return result;

            string projectName = GLib.Path.get_basename(path).down();

            string? sock = ComposeService.socketPath();
            if (sock == null) return result;

            try {
                var socket = new GLib.Socket(GLib.SocketFamily.UNIX, GLib.SocketType.STREAM, GLib.SocketProtocol.DEFAULT);
                var addr = new GLib.UnixSocketAddress(sock);
                socket.connect(addr, null);
                socket.set_timeout(5);

                string filter = "{\"label\":[\"com.docker.compose.project=" + projectName + "\"]}";
                string encoded = GLib.Uri.escape_string(filter);
                string request = "GET /containers/json?all=true&filters=" + encoded + " HTTP/1.0\r\nHost: localhost\r\n\r\n";
                socket.send(request.data, null);

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
                if (bodyStart < 0) return result;
                string body = resp.substring(bodyStart + 4);

                var parser = new Json.Parser();
                parser.load_from_data(body, -1);
                var root = parser.get_root();
                if (root == null) return result;
                var array = root.get_array();
                if (array == null) return result;

                for (int i = 0; i < array.get_length(); i++) {
                    var obj = array.get_object_element(i);
                    if (obj == null) continue;
                    string state = obj.get_string_member("State");
                    bool running = (state == "running");
                    if (running) anyRunning = true;

                    string svcName = projectName;
                    string containerName = "";
                    if (obj.has_member("Labels")) {
                        var labels = obj.get_object_member("Labels");
                        if (labels != null && labels.has_member("com.docker.compose.service")) {
                            svcName = labels.get_string_member("com.docker.compose.service");
                        }
                    }
                    if (obj.has_member("Names")) {
                        var names = obj.get_array_member("Names");
                        if (names != null && names.get_length() > 0) {
                            string? nm = names.get_string_element(0);
                            if (nm != null) {
                                string bare = nm;
                                while (bare.has_prefix("/")) bare = bare.substring(1);
                                containerName = bare;
                                if (svcName == projectName && bare.index_of("/") < 0 && bare != "") {
                                    svcName = bare;
                                }
                            }
                        }
                    }

                    string image = obj.has_member("Image") ? obj.get_string_member("Image") : "";
                    string status = obj.has_member("Status") ? obj.get_string_member("Status") : "";

                    var ports = new GLib.List<AppPort>();
                    if (obj.has_member("Ports")) {
                        var portArray = obj.get_array_member("Ports");
                        if (portArray != null) {
                            for (int p = 0; p < portArray.get_length(); p++) {
                                var portObj = portArray.get_object_element(p);
                                if (portObj == null) continue;
                                int privatePort = 0;
                                int publicPort = 0;
                                string type = "tcp";
                                if (portObj.has_member("PrivatePort")) privatePort = (int) portObj.get_int_member("PrivatePort");
                                if (portObj.has_member("PublicPort")) publicPort = (int) portObj.get_int_member("PublicPort");
                                if (portObj.has_member("Type")) type = portObj.get_string_member("Type");
                                ports.append(new AppPort(publicPort, privatePort, type));
                            }
                        }
                    }

                    var service = new AppService(svcName, running);
                    service.containerName = containerName;
                    service.image = image;
                    service.statusText = status;

                    if (containerName != "") {
                        string? inspect = ComposeService.containerInspect(containerName);
                        if (inspect != null) {
                            try {
                                var hParser = new Json.Parser();
                                hParser.load_from_data(inspect, -1);
                                var hRoot = hParser.get_root();
                                var hObj = hRoot != null ? hRoot.get_object() : null;
                                if (hObj != null) {
                                    var hState = hObj.get_object_member("State");
                                    if (hState != null && hState.has_member("Health")) {
                                        var hHealth = hState.get_object_member("Health");
                                        if (hHealth != null && hHealth.has_member("Status")) {
                                            service.healthStatus = hHealth.get_string_member("Status");
                                        }
                                    }
                                }
                            } catch (Error e) {
                                // Ignore malformed inspect response.
                            }
                        }
                    }

                    foreach (var port in ports) {
                        service.ports.append(port);
                    }
                    result.append(service);
                }
                return result;
            } catch (Error e) {
                return result;
            }
        }

        public static bool isRunning (string path) {
            bool anyRunning = false;
            ComposeService.listServices(path, out anyRunning);
            return anyRunning;
        }

        /*
         * Sends a container lifecycle action (start/stop/restart) to the podman
         * socket and reports success based on the HTTP status code.
         */
        private static bool containerAction (string name, string action) {
            string? sock = ComposeService.socketPath();
            if (sock == null) return false;
            if (!ComposeService.canConnect(sock)) return false;

            try {
                var socket = new GLib.Socket(GLib.SocketFamily.UNIX, GLib.SocketType.STREAM, GLib.SocketProtocol.DEFAULT);
                var addr = new GLib.UnixSocketAddress(sock);
                socket.connect(addr, null);
                socket.set_timeout(10);

                string request = "POST /containers/" + name + "/" + action + " HTTP/1.0\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n";
                socket.send(request.data, null);

                var buf = new uint8[4096];
                var response = new GLib.ByteArray();
                ssize_t received;
                while ((received = socket.receive(buf, null)) > 0) {
                    response.append(buf[:received]);
                }
                socket.close();

                string resp = (string) response.data;
                int start = resp.index_of(" ") + 1;
                if (start <= 0) return false;
                string rest = resp.substring(start);
                int end = rest.index_of(" ");
                if (end < 0) end = rest.length;
                string codeStr = rest.substring(0, end);
                int code = int.parse (codeStr);
                return code >= 200 && code < 300;
            } catch (Error e) {
                return false;
            }
        }

        /*
         * GET /containers/{name}/json and return the response body, or null
         * on any failure.
         */
        private static string? containerInspect (string name) {
            string? sock = ComposeService.socketPath();
            if (sock == null) return null;
            if (!ComposeService.canConnect(sock)) return null;

            try {
                var socket = new GLib.Socket(GLib.SocketFamily.UNIX, GLib.SocketType.STREAM, GLib.SocketProtocol.DEFAULT);
                var addr = new GLib.UnixSocketAddress(sock);
                socket.connect(addr, null);
                socket.set_timeout(10);

                string request = "GET /containers/" + name + "/json HTTP/1.0\r\nHost: localhost\r\n\r\n";
                socket.send(request.data, null);

                var buf = new uint8[65536];
                var response = new GLib.ByteArray();
                ssize_t received;
                while ((received = socket.receive(buf, null)) > 0) {
                    response.append(buf[:received]);
                }
                socket.close();

                string resp = (string) response.data;
                int bodyStart = resp.index_of("\r\n\r\n");
                if (bodyStart < 0) return null;
                return resp.substring(bodyStart + 4);
            } catch (Error e) {
                return null;
            }
        }

        /*
         * GET /containers/{name}/logs?stdout=1&stderr=1&tail=200 and return
         * the log text, or null on any failure.
         */
        public static string? containerLogs (string name) {
            string? sock = ComposeService.socketPath();
            if (sock == null) return null;
            if (!ComposeService.canConnect(sock)) return null;

            try {
                var socket = new GLib.Socket(GLib.SocketFamily.UNIX, GLib.SocketType.STREAM, GLib.SocketProtocol.DEFAULT);
                var addr = new GLib.UnixSocketAddress(sock);
                socket.connect(addr, null);
                socket.set_timeout(10);

                string request = "GET /containers/" + name + "/logs?stdout=1&stderr=1&tail=200 HTTP/1.0\r\nHost: localhost\r\n\r\n";
                socket.send(request.data, null);

                var buf = new uint8[65536];
                var response = new GLib.ByteArray();
                ssize_t received;
                while ((received = socket.receive(buf, null)) > 0) {
                    response.append(buf[:received]);
                }
                socket.close();

                string resp = (string) response.data;
                int bodyStart = resp.index_of("\r\n\r\n");
                if (bodyStart < 0) return null;
                return resp.substring(bodyStart + 4);
            } catch (Error e) {
                return null;
            }
        }

        public static bool startContainer (string name) {
            return ComposeService.containerAction(name, "start");
        }

        public static bool stopContainer (string name) {
            return ComposeService.containerAction(name, "stop?t=10");
        }

        public static bool restartContainer (string name) {
            return ComposeService.containerAction(name, "restart?t=10");
        }
    }
}
