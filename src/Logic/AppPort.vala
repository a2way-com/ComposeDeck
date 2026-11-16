using GLib;

namespace Logic {
    /*
     * AppPort — one published port of a service/container.
     */

    public class AppPort {
        public int publicPort { get; set; }
        public int privatePort { get; set; }
        public string protocol { get; set; }

        public AppPort (int publicPort, int privatePort, string protocol) {
            this.publicPort = publicPort;
            this.privatePort = privatePort;
            this.protocol = protocol;
        }
    }
}
