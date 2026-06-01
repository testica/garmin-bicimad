import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.System;
import Toybox.Cryptography;
import Tinymetrix;

class bicimadApp extends Tinymetrix.ApplicationBase {
    public var positionManager as PositionManager?;
    public var biciMadService  as BiciMadService?;

    // Reference to the main menu so it can be refreshed after login/logout
    public var mainMenu as BiciMadMenu? = null;

    // -- User token (personal login, required for reservations) --
    private var _userToken    as String? = null;
    private var _userId       as String? = null;
    private var _userEmail    as String? = null;
    private var _tokenExpiry  as Long    = 0l;

    // -- Anonymous app token (no account needed, used for reading stations) --
    private var _anonToken        as String? = null;
    private var _anonTokenExpiry  as Long    = 0l;
    private var _lastLat      as Double  = 40.4168d;
    private var _lastLon      as Double  = -3.7038d;
    private var _allStations  as Array?  = null;

    // -- Device identity --
    // Unique ID generated once on first install; persists across restarts.
    // Identifies this watch in the BiciMAD "connected devices" list.
    private var _deviceId as String? = null;

    function initialize() {
        Tinymetrix.ApplicationBase.initialize({
            "syncDelay" => 21600,  // Sync every 6 hours
        });
    }

    function onStart(state as Dictionary?) as Void {
        Tinymetrix.ApplicationBase.onStart(state);

        // Load persistent session
        var storedToken = Application.Storage.getValue("token") as String?;
        if (storedToken != null && !storedToken.equals("")) {
            _userToken = storedToken;
        }
        var storedEmail = Application.Storage.getValue("email") as String?;
        if (storedEmail != null) { _userEmail = storedEmail; }
        var storedId = Application.Storage.getValue("userId") as String?;
        if (storedId != null) { _userId = storedId; }

        // Load token expiry date
        var storedExpiry = Application.Storage.getValue("tokenExpiry") as Long?;
        if (storedExpiry != null) { _tokenExpiry = storedExpiry; }

        // Load persisted anonymous token
        var storedAnon = Application.Storage.getValue("anonToken") as String?;
        if (storedAnon != null && !storedAnon.equals("")) { _anonToken = storedAnon; }
        var storedAnonExpiry = Application.Storage.getValue("anonTokenExpiry") as Long?;
        if (storedAnonExpiry != null) { _anonTokenExpiry = storedAnonExpiry; }

        // Set Tinymetrix user ID if logged in
        if (isLoggedIn() && _userEmail != null) {
            Tinymetrix.Client.setUserId(_userEmail);
        }
    }

    function onStop(state as Dictionary?) as Void {
        Tinymetrix.ApplicationBase.onStop(state);
        if (positionManager != null) { positionManager.stopGPS(); }
    }

    // Replaces getInitialView() — return your views and delegates here
    function onCreateView() as [Views] or [Views, InputDelegates] {
        positionManager = new PositionManager();
        biciMadService  = new BiciMadService();

        var menu = new BiciMadMenu();
        mainMenu = menu;
        return [ menu, new BiciMadMenuDelegate(menu) ];
    }

    // ── Token ────────────────────────────────────────────────────────────────

    function getUserToken() as String? { return _userToken; }
    function setUserToken(token as String?) as Void {
        _userToken = token;
        Application.Storage.setValue("token", token != null ? token : "");
    }

    function isLoggedIn() as Boolean {
        if (_userToken == null || _userToken.equals("")) { return false; }
        if (_tokenExpiry > 0l) {
            if (Time.now().value().toLong() >= _tokenExpiry) { _clearSession(); return false; }
        }
        return true;
    }

    function setTokenExpiry(expirySec as Long) as Void {
        _tokenExpiry = expirySec;
        Application.Storage.setValue("tokenExpiry", expirySec);
    }

    function logout() as Void { _clearSession(); }

    private function _clearSession() as Void {
        _userToken = null; _userId = null; _tokenExpiry = 0l;
        Application.Storage.setValue("token", "");
        Application.Storage.setValue("userId", "");
        Application.Storage.setValue("tokenExpiry", 0l);
    }

    // ── User data ────────────────────────────────────────────────────────────

    function getUserId() as String? { return _userId; }
    function setUserId(id as String?) as Void {
        _userId = id;
        Application.Storage.setValue("userId", id != null ? id : "");
    }

    function getUserEmail() as String? { return _userEmail; }
    function setUserEmail(email as String?) as Void {
        _userEmail = email;
        Application.Storage.setValue("email", email != null ? email : "");
    }

    // ── Last GPS position ────────────────────────────────────────────────────

    function getLastLat() as Double { return _lastLat; }
    function getLastLon() as Double { return _lastLon; }
    function setLastLocation(lat as Double, lon as Double) as Void {
        _lastLat = lat; _lastLon = lon;
    }

    // ── Anonymous token ──────────────────────────────────────────────────────

    function getAnonToken() as String? { return _anonToken; }
    function setAnonToken(token as String, expirySec as Long) as Void {
        _anonToken = token; _anonTokenExpiry = expirySec;
        Application.Storage.setValue("anonToken", token);
        Application.Storage.setValue("anonTokenExpiry", expirySec);
    }
    function isAnonTokenValid() as Boolean {
        if (_anonToken == null || _anonToken.equals("")) { return false; }
        if (_anonTokenExpiry > 0l) {
            return Time.now().value().toLong() < _anonTokenExpiry - 300l;
        }
        return true;
    }

    // ── Device identity ──────────────────────────────────────────────────────

    function getDeviceId() as String {
        // Hardware ID: stable across installs, no storage needed
        var settings = System.getDeviceSettings();
        if ((settings has :uniqueIdentifier) && settings.uniqueIdentifier != null) {
            return settings.uniqueIdentifier as String;
        }
        // Fallback for older firmware: generate once and persist
        if (_deviceId == null || (_deviceId as String).equals("")) {
            var stored = Application.Storage.getValue("deviceId") as String?;
            if (stored != null && !stored.equals("")) {
                _deviceId = stored;
            } else {
                var bytes = Cryptography.randomBytes(8) as ByteArray;
                var hex   = "" as String;
                for (var i = 0; i < bytes.size(); i++) {
                    hex += (bytes[i] & 0xFF).format("%02x");
                }
                _deviceId = hex;
                Application.Storage.setValue("deviceId", _deviceId);
            }
        }
        return _deviceId as String;
    }

    // Returns a JSON object string describing this Garmin device.
    // Mirrors the format the Android app sends for Build info.
    function getDeviceModel() as String {
        var settings  = System.getDeviceSettings();
        var partNum   = settings.partNumber;
        var modelStr  = (partNum != null && !(partNum as String).equals(""))
            ? (partNum as String)
            : "watch";
        return "{\"brand\":\"Garmin\",\"model\":\"" + modelStr + "\"}";
    }

    // ── Station cache ────────────────────────────────────────────────────────

    function getAllStations() as Array? { return _allStations; }
    function setAllStations(stations as Array) as Void { _allStations = stations; }
}

function getApp() as bicimadApp {
    return Application.getApp() as bicimadApp;
}
