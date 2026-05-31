import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;

class BiciMadService {

    // -- API credentials (extracted from the official BiciMAD APK via libkeys.so analysis) --
    private const X_CLIENT_ID = "8ff527f9-f85b-45ef-b1b2-bd9eb59e0fff";
    private const PASS_KEY    = "C3D0E659D8D397782B414AB6FCC477B5C727435FE91E72069D34CEBB2C1491B3B8563FDAC043EA704660C0E87E6FE503C39D38FF43F7447563B1E437B349ACEC";

    // -- Endpoints --
    // EMT Madrid OpenAPI (public, no credentials needed)
    private const URL_LOGIN   = "https://openapi.emtmadrid.es/v2/mobilitylabs/user/login/";
    private const URL_BOOKING = "https://apiemtpay.emtmadrid.es/v1/bicimad/booking/";
    // Proxy (filters/reduces EMT responses to fit the watch's 32 KB network buffer)
    // Default proxy at tinymetrix.com — deploy your own using server/index.js
    private const PROXY_BASE  = "https://tinymetrix.com";
    private const URL_PROXY   = PROXY_BASE + "/bicimad/api/stations";
    private const URL_TRIPS   = PROXY_BASE + "/bicimad/api/trips";
    private const URL_CHECK   = PROXY_BASE + "/bicimad/api/check";
    private const URL_UNLOCK  = PROXY_BASE + "/bicimad/api/unlock";

    // Last known user position (lat/lon) included in booking calls
    private var _lastLat as Double = 40.4168d;
    private var _lastLon as Double = -3.7038d;

    function initialize() {}

    // =====================================================================
    //  ANONYMOUS LOGIN (app token, no user account)
    //  Persisted in Application.Storage. Renewed only when expired.
    //  Independent from the personal user token.
    // =====================================================================

    private var _anonLoginCallback as (Method(token as String?) as Void)? = null;

    // Calls the callback with a valid token (from Storage or via anonymous login)
    function ensureAnonToken(callback as Method(token as String?) as Void) as Void {
        if (getApp().isAnonTokenValid()) {
            callback.invoke(getApp().getAnonToken());
            return;
        }
        _anonLoginCallback = callback;
        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :headers      => {
                "X-ClientId"         => X_CLIENT_ID,
                "passKey"            => PASS_KEY,
                "accessToken"        => "",
                "userId"             => "",
                "appName"            => "BiciMAD",
                "appPlatform"        => "Android",
                "appPlatformVersion" => "Android 12",
                "appVersion"         => "5.0.0",
                "deviceId"           => "garmin-watch-001",
                "deviceModel"        => "{}",
                "language"           => "ES",
                "latitude"           => "40.416775",
                "longitude"          => "-3.703790"
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(URL_LOGIN, null, options, method(:onAnonLoginResponse));
    }

    function onAnonLoginResponse(responseCode as Number, data as Dictionary or Null) as Void {
        if (_anonLoginCallback == null) { return; }
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var code = data.get("code") as String?;
            if (code != null && (code.equals("00") || code.equals("01"))) {
                var arr = data.get("data") as Array?;
                if (arr != null && arr.size() > 0) {
                    var ud     = arr[0] as Dictionary;
                    var token  = ud.get("accessToken") as String?;
                    var expObj = ud.get("tokenDteExpiration") as Dictionary?;
                    var expSec = 0l;
                    if (expObj != null) {
                        var ms = expObj.get("$date") as Number?;
                        if (ms != null) { expSec = ms.toLong() / 1000l; }
                    }
                    if (token != null) {
                        getApp().setAnonToken(token, expSec);
                        _anonLoginCallback.invoke(token);
                        _anonLoginCallback = null;
                        return;
                    }
                }
            }
        }
        _anonLoginCallback.invoke(null);
        _anonLoginCallback = null;
    }

    // =====================================================================
    //  USER LOGIN (personal account, required for reservations)
    //  Independent from the anonymous token above.
    // =====================================================================

    function loginUser(email as String, password as String,
            callback as Method(success as Boolean, token as String?) as Void) as Void {
        _loginCallback = callback;

        // All parameters sent as headers (no JSON body) so Garmin doesn't
        // serialize anything and the server receives exactly what it expects.
        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :headers      => {
                "X-ClientId"         => X_CLIENT_ID,
                "passKey"            => PASS_KEY,
                "email"              => email,
                "password"           => password,
                "accessToken"        => "",
                "userId"             => "",
                "appName"            => "BiciMAD",
                "appPlatform"        => "Android",
                "appPlatformVersion" => "Android 12",
                "appVersion"         => "5.0.0",
                "deviceId"           => "garmin-watch-001",
                "deviceModel"        => "{}",
                "language"           => "ES",
                "latitude"           => "40.416775",
                "longitude"          => "-3.703790"
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(URL_LOGIN, null, options, method(:onLoginResponse));
    }

    private var _loginCallback as (Method(success as Boolean, token as String?) as Void)? = null;

    function onLoginResponse(responseCode as Number, data as Dictionary or Null) as Void {
        if (_loginCallback == null) { return; }

        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var apiCode = data.get("code") as String?;
            // "00" = new login, "01" = extended token (cached) — both are success
            if (apiCode != null && (apiCode.equals("00") || apiCode.equals("01"))) {
                var dataArr = data.get("data") as Array?;
                if (dataArr != null && dataArr.size() > 0) {
                    var ud = dataArr[0] as Dictionary;
                    var token  = ud.get("accessToken") as String?;
                    var userId = ud.get("idUser")      as String?;
                    var email  = ud.get("email")       as String?;
                    getApp().setUserId(userId);
                    getApp().setUserEmail(email);

                    // Store token expiry date
                    // tokenDteExpiration = {"$date": <epoch milliseconds>}
                    var expObj = ud.get("tokenDteExpiration") as Dictionary?;
                    if (expObj != null) {
                        var expMs = expObj.get("$date") as Number?;
                        if (expMs != null) {
                            getApp().setTokenExpiry(expMs.toLong() / 1000l);
                        }
                    }

                    _loginCallback.invoke(true, token);
                    _loginCallback = null;
                    return;
                }
            }
        }
        _loginCallback.invoke(false, null);
        _loginCallback = null;
    }

    // =====================================================================
    //  STATIONS — via tinymetrix.com proxy
    //  The watch first ensures a valid anonymous token, then calls the proxy.
    // =====================================================================

    private var _stationsCallback as (Method(responseCode as Number, data as Array?) as Void)? = null;
    private var _pendingFilter    as String = "";
    private var _pendingValue     as String = "";

    // Nearby stations by GPS
    function fetchNearbyStations(lat as Double, lon as Double,
            callback as Method(responseCode as Number, data as Array?) as Void) as Void {
        _lastLat = lat;
        _lastLon = lon;
        getApp().setLastLocation(lat, lon);
        _stationsCallback  = callback;
        _pendingFilter     = "coordinates";
        _pendingValue      = lat.format("%.5f") + "," + lon.format("%.5f");
        ensureAnonToken(method(:onAnonTokenForStations));
    }

    // Search by name
    function fetchStationsByName(query as String,
            callback as Method(responseCode as Number, data as Array?) as Void) as Void {
        _stationsCallback = callback;
        _pendingFilter    = "name";
        _pendingValue     = query;
        ensureAnonToken(method(:onAnonTokenForStations));
    }

    function onAnonTokenForStations(token as String?) as Void {
        if (token == null) {
            if (_stationsCallback != null) {
                _stationsCallback.invoke(-1, null);
                _stationsCallback = null;
            }
            return;
        }
        var params = {
            "filter" => _pendingFilter,
            "value"  => _pendingValue,
            "token"  => token,
            "limit"  => "15"
        };
        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(URL_PROXY, params, options, method(:onStationsResponse));
    }

    function onStationsResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (_stationsCallback == null) { return; }
        if (responseCode == 200 && data != null && data instanceof Array) {
            _stationsCallback.invoke(200, data as Array);
        } else {
            _stationsCallback.invoke(responseCode, null);
        }
        _stationsCallback = null;
    }

    // Search by name against the local cache (if stations were loaded before)
    function searchStationsByName(query as String) as Array {
        var all = getApp().getAllStations();
        if (all == null || all.size() == 0) { return []; }
        var lower = query.toLower();
        var matches = [];
        for (var i = 0; i < all.size(); i++) {
            var s = all[i] as Dictionary;
            if ((s.get("name") as String).toLower().find(lower) != null) {
                matches.add(s);
            }
        }
        return matches;
    }

    // Select the N nearest stations WITHOUT trigonometry in the main loop.
    //
    // To sort all 632 stations we use squared distance (only additions/multiplications).
    // Fixed factors for Madrid (~40.4 lat):
    //   1 deg lat ~ 111 194 m
    //   1 deg lon ~ 111 194 * cos(40.4 deg) ~ 84 740 m
    // We only call sqrt() for the final N results (10 times, not 632).
    //
    // Input format:  [[id, name, lat, lon], ...]
    // Output format: [{id, name, dist(m)}, ...]
    private function _topNFromCoords(raw as Array, userLat as Double, userLon as Double,
                                      n as Number) as Array {
        var LAT_M = 111194.0d;
        var LON_M = 84740.0d;  // 111194 * cos(40.4 deg in radians) ~ 84740

        // Step 1: compute squared distance for all stations — no sqrt, no cos, no trig
        var sqDists = new [raw.size()];
        for (var i = 0; i < raw.size(); i++) {
            var e    = raw[i] as Array;
            var dLat = ((e[2] as Numeric).toDouble() - userLat) * LAT_M;
            var dLon = ((e[3] as Numeric).toDouble() - userLon) * LON_M;
            sqDists[i] = dLat * dLat + dLon * dLon;
        }

        // Step 2: selection sort on sqDists to pick the N smallest
        var result = [];
        for (var k = 0; k < n && k < raw.size(); k++) {
            var minSq = 9.0e18d;
            var minI  = -1;
            for (var i = 0; i < sqDists.size(); i++) {
                var sq = sqDists[i] as Double;
                if (sq >= 0.0d && sq < minSq) { minSq = sq; minI = i; }
            }
            if (minI >= 0) {
                var e    = raw[minI] as Array;
                // sqrt only here, 10 times total
                var dist = Math.sqrt(minSq).toNumber();
                result.add({ "id" => e[0] as String, "name" => e[1] as String, "dist" => dist });
                sqDists[minI] = -1.0d;
            }
        }
        return result;
    }


    // =====================================================================
    //  RESERVE BIKE (by station ID)
    // =====================================================================

    function reserveBike(stationId as String, userToken as String,
            callback as Method(success as Boolean, description as String?) as Void) as Void {
        _reserveCallback = callback;

        var userId = getApp().getUserId();
        if (userId == null) { userId = ""; }

        var options = {
            :method  => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "accessToken" => userToken,
                "station"     => stationId,
                "userId"      => userId,
                "latitude"    => _lastLat.format("%.6f"),
                "longitude"   => _lastLon.format("%.6f"),
                "deviceId"    => "garmin-watch-001",
                "appName"     => "BiciMAD",
                "appPlatform" => "Android",
                "appVersion"  => "5.0.0",
                "language"    => "ES"
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(URL_BOOKING, null, options, method(:onReservationResponse));
    }

    private var _reserveCallback as (Method(success as Boolean, description as String?) as Void)? = null;

    function onReservationResponse(responseCode as Number, data as Dictionary or Null) as Void {
        if (_reserveCallback == null) { return; }

        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var code = data.get("code") as String?;
            var desc = data.get("description") as String?;
            if (code != null && (code.equals("00") || code.equals("01"))) {
                _reserveCallback.invoke(true, desc);
            } else {
                _reserveCallback.invoke(false, desc);
            }
        } else {
            _reserveCallback.invoke(false, null);
        }
        _reserveCallback = null;
    }

    // =====================================================================
    //  UNLOCK BIKE BY PLATE (via tinymetrix proxy)
    //  The proxy computes the DES hashcode and calls sellTicket.
    // =====================================================================

    private var _unlockCallback as (Method(success as Boolean, description as String?) as Void)? = null;

    function unlockBike(plate as String,
            callback as Method(success as Boolean, description as String?) as Void) as Void {
        _unlockCallback = callback;
        var token  = getApp().getUserToken();
        var userId = getApp().getUserId();
        if (token == null || userId == null) { callback.invoke(false, (WatchUi.loadResource(Rez.Strings.MenuLoginSub) as String)); return; }

        var params = {
            "plate"  => plate,
            "token"  => token,
            "userId" => userId,
            "lat"    => _lastLat.format("%.6f"),
            "lon"    => _lastLon.format("%.6f")
        };
        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(URL_UNLOCK, params, options, method(:onUnlockResponse));
    }

    function onUnlockResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (_unlockCallback == null) { return; }
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var code = (data as Dictionary).get("code") as String?;
            var desc = (data as Dictionary).get("description") as String?;
            if (code != null && (code.equals("00") || code.equals("01"))) {
                _unlockCallback.invoke(true, desc);
            } else {
                _unlockCallback.invoke(false, desc);
            }
        } else {
            _unlockCallback.invoke(false, null);
        }
        _unlockCallback = null;
    }

    // =====================================================================
    //  CHECK BIKE BY PLATE
    //  GET https://apiemtpay.emtmadrid.es/v1/checkresource/bicimad/{plate}/
    //  Response: { code, data: { id, number, docker, geometry: {coordinates:[lon,lat]}, fleet } }
    // =====================================================================

    function checkBikeByPlate(plate as String,
            callback as Method(success as Boolean, bikeData as Dictionary?) as Void) as Void {
        _plateCallback = callback;

        var token  = getApp().getUserToken();
        var userId = getApp().getUserId();
        if (token == null)  { token  = ""; }
        if (userId == null) { userId = ""; }

        // Via proxy (apiemtpay.emtmadrid.es is not reachable from Garmin directly)
        var params = {
            "plate"  => plate,
            "token"  => token,
            "userId" => userId
        };
        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(URL_CHECK, params, options, method(:onPlateResponse));
    }

    private var _plateCallback as (Method(success as Boolean, bikeData as Dictionary?) as Void)? = null;

    function onPlateResponse(responseCode as Number, data as Dictionary or Null) as Void {
        if (_plateCallback == null) { return; }

        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var code = data.get("code") as String?;
            if (code != null && code.equals("00")) {
                var bikeData = data.get("data") as Dictionary?;
                _plateCallback.invoke(true, bikeData);
                _plateCallback = null;
                return;
            }
        }
        _plateCallback.invoke(false, null);
        _plateCallback = null;
    }

    // =====================================================================
    //  USER TRIPS
    //  GET https://apiemtpay.emtmadrid.es/v1/bicimad/trips/
    //  If dock==null -> trip in progress; if dock!=null -> completed.
    // =====================================================================

    private var _tripsCallback as (Method(success as Boolean, trips as Array?) as Void)? = null;

    function fetchTrips(callback as Method(success as Boolean, trips as Array?) as Void) as Void {
        _tripsCallback = callback;
        var token  = getApp().getUserToken();
        var userId = getApp().getUserId();
        if (token == null || userId == null) { callback.invoke(false, null); return; }

        // The proxy forwards to apiemtpay.emtmadrid.es (blocked by Garmin directly)
        var params = {
            "token"  => token,
            "userId" => userId
        };
        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(URL_TRIPS, params, options, method(:onTripsResponse));
    }

    function onTripsResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (_tripsCallback == null) { return; }
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var code = (data as Dictionary).get("code") as String?;
            if (code != null && (code.equals("00") || code.equals("01"))) {
                var trips = (data as Dictionary).get("data") as Array?;
                _tripsCallback.invoke(true, trips != null ? trips : []);
                _tripsCallback = null;
                return;
            }
        }
        _tripsCallback.invoke(false, null);
        _tripsCallback = null;
    }

    // =====================================================================
    //  UTILITY: distance in meters between two GPS coordinates
    // =====================================================================

    private function calcDistance(lat1 as Double, lon1 as Double,
                                   lat2 as Double, lon2 as Double) as Float {
        var R    = 6371000.0;
        var dLat = (lat2 - lat1) * Math.PI / 180.0;
        var dLon = (lon2 - lon1) * Math.PI / 180.0;
        var mLat = (lat1 + lat2) * Math.PI / 360.0;
        var x    = dLon * Math.cos(mLat);
        var y    = dLat;
        return (Math.sqrt(x * x + y * y) * R).toFloat();
    }

    // Distance from current saved position to the given coordinates
    function distanceFromUser(lat as Double, lon as Double) as Number {
        return calcDistance(_lastLat, _lastLon, lat, lon).toNumber();
    }
}
