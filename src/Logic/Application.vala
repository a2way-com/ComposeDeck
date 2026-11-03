using Adw;
using GLib;
using Views;
using Logic;

namespace Logic {
    public class Application : Adw.Application {
        private Views.Window? window;
        private State? state;
        private static Application? instance;

        public Application () {
            Object(application_id: ComposeDeck.APP_ID);
        }

        protected override void activate () {
            instance = this;
            if (this.window == null) {
                this.state = new State();
                this.window = new Views.Window(this);
                ComposeDeck.start(this.state);
            }
            this.window.present();
        }

        public static State getState () {
            if (instance == null || instance.state == null) {
                GLib.error ("Application state is not initialized");
            }
            return instance.state;
        }
    }
}
