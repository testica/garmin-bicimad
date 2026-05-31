import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Position;
import Tinymetrix;

// -- Search submenu: Nearby / Search by Name --

class StationSearchMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => (WatchUi.loadResource(Rez.Strings.StationMenuTitle) as String)});
        addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.StationNearby) as String),      (WatchUi.loadResource(Rez.Strings.StationNearbySub) as String),        :nearby, {}));
        addItem(new WatchUi.MenuItem((WatchUi.loadResource(Rez.Strings.StationSearchByName) as String), (WatchUi.loadResource(Rez.Strings.StationSearchSub) as String), :search, {}));
    }
}

class StationSearchMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :nearby) {
            Tinymetrix.Client.track("search_stations_gps");
            // Native ProgressBar while acquiring GPS + loading stations
            WatchUi.pushView(
                new WatchUi.ProgressBar((WatchUi.loadResource(Rez.Strings.GpsSearching) as String), null),
                new StationGPSDelegate(),
                WatchUi.SLIDE_UP
            );
        } else if (item.getId() == :search) {
            Tinymetrix.Client.track("search_stations_name");
            WatchUi.pushView(
                new WatchUi.TextPicker(""),
                new StationNamePickerDelegate(),
                WatchUi.SLIDE_UP
            );
        }
    }

    function onBack() as Void { WatchUi.popView(WatchUi.SLIDE_DOWN); }
}

// -- GPS delegate (ProgressBar while acquiring GPS + network) --

class StationGPSDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
        getApp().positionManager.startGPS(method(:onGpsLock));
    }

    function onGpsLock(position as Position.Location) as Void {
        getApp().positionManager.stopGPS();
        var coords = position.toDegrees();
        getApp().biciMadService.fetchNearbyStations(
            coords[0], coords[1], method(:onStations));
    }

    function onStations(responseCode as Number, data as Array?) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN); // close ProgressBar
        if (responseCode == 200 && data != null && data.size() > 0) {
            WatchUi.pushView(
                new StationResultsMenu(data, :gps),
                new StationResultsMenuDelegate(),
                WatchUi.SLIDE_UP
            );
        } else {
            WatchUi.pushView(
                new WatchUi.Confirmation((WatchUi.loadResource(Rez.Strings.NoResultsRetry) as String)),
                new StationRetryDelegate(:nearby),
                WatchUi.SLIDE_UP
            );
        }
    }

    function onCancel() as Boolean {
        getApp().positionManager.stopGPS();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

// -- Search by name delegate (TextPicker -> ProgressBar -> results) --

class StationNamePickerDelegate extends WatchUi.TextPickerDelegate {
    function initialize() { TextPickerDelegate.initialize(); }

    function onTextEntered(text as String, changed as Boolean) as Boolean {
        if (text.length() > 0) {
            WatchUi.pushView(
                new WatchUi.ProgressBar((WatchUi.loadResource(Rez.Strings.Searching) as String) + " \"" + text + "\"", null),
                new StationNameDelegate(text),
                WatchUi.SLIDE_UP
            );
        }
        return true;
    }

    function onCancel() as Boolean { return true; }
}

class StationNameDelegate extends WatchUi.BehaviorDelegate {
    private var _query as String;

    function initialize(query as String) {
        BehaviorDelegate.initialize();
        _query = query;
        getApp().biciMadService.fetchStationsByName(query, method(:onStations));
    }

    function onStations(responseCode as Number, data as Array?) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (responseCode == 200 && data != null && data.size() > 0) {
            WatchUi.pushView(
                new StationResultsMenu(data, :name),
                new StationResultsMenuDelegate(),
                WatchUi.SLIDE_UP
            );
        } else {
            WatchUi.pushView(
                new WatchUi.Confirmation((WatchUi.loadResource(Rez.Strings.NoResultsSearchAgain) as String)),
                new StationRetryDelegate(:search),
                WatchUi.SLIDE_UP
            );
        }
    }

    function onCancel() as Boolean { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

// -- Retry delegate (Confirmation dialog) --

class StationRetryDelegate extends WatchUi.ConfirmationDelegate {
    private var _mode as Symbol;

    function initialize(mode as Symbol) {
        ConfirmationDelegate.initialize();
        _mode = mode;
    }

    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            if (_mode == :nearby) {
                WatchUi.pushView(
                    new WatchUi.ProgressBar((WatchUi.loadResource(Rez.Strings.GpsSearching) as String), null),
                    new StationGPSDelegate(),
                    WatchUi.SLIDE_UP
                );
            } else {
                WatchUi.pushView(
                    new WatchUi.TextPicker(""),
                    new StationNamePickerDelegate(),
                    WatchUi.SLIDE_UP
                );
            }
        }
        return true;
    }
}

// -- Native results menu --
// Label: station name (without prefix)  /  SubLabel: "11/25 · 57m"

class StationResultsMenu extends WatchUi.Menu2 {
    function initialize(stations as Array, mode as Symbol) {
        var title = (mode == :gps) ? (WatchUi.loadResource(Rez.Strings.StationNearbyTitle) as String) : (WatchUi.loadResource(Rez.Strings.StationResultsTitle) as String);
        Menu2.initialize({:title => title});

        for (var i = 0; i < stations.size(); i++) {
            var s     = stations[i] as Dictionary;
            var name  = s.get("name")  as String;
            var bikes = s.get("bikes") as Number;
            var slots = s.get("slots") as Number;
            var dist  = s.get("dist")  as Number;
            var total = bikes + slots;

            // Strip "N - " prefix for better fit
            var dashIdx = name.find(" - ");
            var shortName = (dashIdx != null && dashIdx >= 0)
                ? name.substring(dashIdx + 3, name.length())
                : name;
            if (shortName.length() > 22) { shortName = shortName.substring(0, 20) + ".."; }

            var sub = bikes.toString() + "/" + total.toString();
            if (mode == :gps && dist > 0) {
                var distText = dist >= 1000
                    ? (dist / 1000.0).format("%.1f") + "km"
                    : dist.toString() + "m";
                sub = sub + " · " + distText;
            }

            addItem(new WatchUi.MenuItem(shortName, sub, i, {}));
        }
    }
}

class StationResultsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }
    function onSelect(item as WatchUi.MenuItem) as Void {}  // informational only
    function onBack() as Void { WatchUi.popView(WatchUi.SLIDE_DOWN); }
}
