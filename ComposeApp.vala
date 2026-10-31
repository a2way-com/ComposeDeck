using GLib;

/*
 * ComposeApp — model representing a single Compose application
 * discovered under ~/Apps/.
 */

public class ComposeApp {
    public string name { get; set; }
    public string path { get; set; }
    public bool running { get; set; }

    public ComposeApp (string name, string path, bool running) {
        this.name = name;
        this.path = path;
        this.running = running;
    }
}