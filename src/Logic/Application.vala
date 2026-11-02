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
            if (window == null) {
                state = new State();
                window = new Views.Window(this);
                ComposeDeck.start(state);
            }
            window.present();
        }

        public static State? getState () {
            return instance != null ? instance.state : null;
        }
    }
}
