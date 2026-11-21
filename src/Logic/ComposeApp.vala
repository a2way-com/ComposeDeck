using GLib;

namespace Logic {
    /*
     * ComposeApp — model representing a single Compose application
     * discovered under ~/Apps/.
     */
    public class ComposeApp {
        public string name { get; set; }
        public string path { get; set; }
        public string projectName { get; set; }
        public bool running { get; set; }
        public int runningCount { get; set; }
        public int serviceCount { get; set; }
        public GLib.List<AppService> services;

        public ComposeApp (string name, string path, bool running) {
            this.name = name;
            this.path = path;
            this.projectName = name;
            this.running = running;
            this.runningCount = 0;
            this.serviceCount = 0;
            this.services = new GLib.List<AppService>();
        }
    }
}
