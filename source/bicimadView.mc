import Toybox.WatchUi;
import Toybox.Lang;
import Tinymetrix;

// -- Main menu (native Menu2) --
//
// Logged out: [View Stations, Sign In]
// Logged in:  [View Stations, Trips, Unlock Bike, Sign Out]
//
// "Sign In/Out" is always the last item.
// "Trips" and "Unlock Bike" only appear when logged in.

class BiciMadMenu extends WatchUi.Menu2 {
    private var _wasLoggedIn as Boolean = false;

    function initialize() {
        Menu2.initialize({:title => "BiciMAD"});
        _wasLoggedIn = getApp().isLoggedIn();
        _build();
    }

    function onShow() as Void { refresh(); }

    function refresh() as Void {
        var now = getApp().isLoggedIn();
        if (now == _wasLoggedIn) { return; }
        _wasLoggedIn = now;

        if (now) {
            deleteItem(1);
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.MenuTrips) as String),        (WatchUi.loadResource(Rez.Strings.MenuTripsSub) as String),    :trips,   {}));
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.PlateMenuTitle) as String),  (WatchUi.loadResource(Rez.Strings.MenuUnlockSub) as String),      :plate,   {}));
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.MenuLogout) as String), getApp().getUserEmail(), :account, {}));
        } else {
            deleteItem(3);
            deleteItem(2);
            deleteItem(1);
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.LoginTitle) as String),(WatchUi.loadResource(Rez.Strings.MenuLoginSub) as String),     :account, {}));
        }
        WatchUi.requestUpdate();
    }

    private function _build() as Void {
        addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.MenuStations) as String), null, :stations, {}));
        if (_wasLoggedIn) {
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.MenuTrips) as String),        (WatchUi.loadResource(Rez.Strings.MenuTripsSub) as String),    :trips,   {}));
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.PlateMenuTitle) as String),  (WatchUi.loadResource(Rez.Strings.MenuUnlockSub) as String),      :plate,   {}));
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.MenuLogout) as String), getApp().getUserEmail(), :account, {}));
        } else {
            addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.LoginTitle) as String),(WatchUi.loadResource(Rez.Strings.MenuLoginSub) as String),     :account, {}));
        }
    }
}

class BiciMadMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _menu as BiciMadMenu;

    function initialize(menu as BiciMadMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :stations) {
            WatchUi.pushView(new StationSearchMenu(), new StationSearchMenuDelegate(), WatchUi.SLIDE_UP);

        } else if (id == :trips) {
            Tinymetrix.Client.track("view_trips");
            WatchUi.pushView(
                new WatchUi.ProgressBar((WatchUi.loadResource(Rez.Strings.LoadingTrips) as String), null),
                new TripsLoadingDelegate(),
                WatchUi.SLIDE_UP
            );

        } else if (id == :plate) {
            WatchUi.pushView(new PlateInputMenu(), new PlateInputDelegate(), WatchUi.SLIDE_UP);

        } else if (id == :account) {
            if (getApp().isLoggedIn()) {
                Tinymetrix.Client.track("logout");
                getApp().logout();
                _menu.refresh();
            } else {
                var loginMenu = new LoginMenu();
                WatchUi.pushView(loginMenu, new LoginMenuDelegate(loginMenu, null, null, null), WatchUi.SLIDE_UP);
            }
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
