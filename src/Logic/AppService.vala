using GLib;

namespace Logic {
    /*
     * AppService — model representing a single service inside a Compose project.
     */

    public class AppService {
        public string name { get; set; }
        public string containerName { get; set; }
        public string image { get; set; }
        public bool running { get; set; }
        public GLib.List<AppPort> ports = new GLib.List<AppPort>();

        public AppService (string name, bool running) {
            this.name = name;
            this.containerName = "";
            this.image = "";
            this.running = running;
        }
    }
}
