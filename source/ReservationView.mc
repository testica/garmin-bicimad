import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Tinymetrix;

class ReservationView extends WatchUi.View {
    enum {
        STATE_CONFIRM = 0,
        STATE_SUBMITTING = 1,
        STATE_SUCCESS = 2,
        STATE_ERROR = 3
    }

    private var _state as Number = STATE_CONFIRM;
    private var _selectedChoice as Number = 0; // 0 = Confirm, 1 = Cancel
    private var _stationId as String;
    private var _stationName as String;
    private var _userToken as String;
    private var _errorMsg as String = "";

    function initialize(stationId as String, stationName as String, userToken as String) {
        View.initialize();
        _stationId = stationId;
        _stationName = stationName;
        _userToken = userToken;
    }

    function getSelectedChoice() as Number {
        return _selectedChoice;
    }

    function setSelectedChoice(choice as Number) as Void {
        _selectedChoice = choice;
        WatchUi.requestUpdate();
    }

    function getState() as Number {
        return _state;
    }

    function setState(state as Number) as Void {
        _state = state;
        WatchUi.requestUpdate();
    }

    function performReservation() as Void {
        Tinymetrix.Client.track("reserve_bike");
        _state = STATE_SUBMITTING;
        WatchUi.requestUpdate();
        getApp().biciMadService.reserveBike(_stationId, _userToken, method(:onReservationCompleted));
    }

    function onReservationCompleted(success as Boolean, description as String?) as Void {
        if (success) {
            _state = STATE_SUCCESS;
        } else {
            // Show the API error message (e.g. "No active subscription")
            _errorMsg = description != null ? description : "Error";
            _state = STATE_ERROR;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(0x121212, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var centerY = height / 2;

        if (_state == STATE_CONFIRM) {
            dc.setColor(0x00FF88, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 0.1, Graphics.FONT_MEDIUM, (WatchUi.loadResource(Rez.Strings.Confirm) as String) + "?", Graphics.TEXT_JUSTIFY_CENTER);

            var cleanName = _stationName;
            if (cleanName.length() > 22) {
                cleanName = cleanName.substring(0, 19) + "...";
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 0.28, Graphics.FONT_XTINY, cleanName, Graphics.TEXT_JUSTIFY_CENTER);

            var btnWidth = (width * 0.8).toNumber();
            var btnHeight = (height * 0.18).toNumber();
            var btnX = centerX - (btnWidth / 2);

            var y1 = (height * 0.42).toNumber();
            var isSel1 = (_selectedChoice == 0);
            dc.setColor(isSel1 ? 0x00FF66 : 0x222222, 0x1A1A1A);
            dc.fillRoundedRectangle(btnX, y1, btnWidth, btnHeight, 8);
            if (isSel1) {
                dc.setColor(0x00FF66, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(btnX, y1, btnWidth, btnHeight, 8);
            }
            dc.setColor(isSel1 ? Graphics.COLOR_BLACK : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y1 + (btnHeight / 2) - 10, Graphics.FONT_SMALL, (WatchUi.loadResource(Rez.Strings.ReservationConfirm) as String), Graphics.TEXT_JUSTIFY_CENTER);

            var y2 = (height * 0.64).toNumber();
            var isSel2 = (_selectedChoice == 1);
            dc.setColor(isSel2 ? 0xFF3333 : 0x222222, 0x1A1A1A);
            dc.fillRoundedRectangle(btnX, y2, btnWidth, btnHeight, 8);
            if (isSel2) {
                dc.setColor(0xFF3333, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(btnX, y2, btnWidth, btnHeight, 8);
            }
            dc.setColor(isSel2 ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y2 + (btnHeight / 2) - 10, Graphics.FONT_SMALL, (WatchUi.loadResource(Rez.Strings.Cancel) as String), Graphics.TEXT_JUSTIFY_CENTER);

        } else if (_state == STATE_SUBMITTING) {
            dc.setColor(0x00FF88, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, centerY - 20, Graphics.FONT_MEDIUM, (WatchUi.loadResource(Rez.Strings.Reserving) as String), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, centerY + 15, Graphics.FONT_XTINY, (WatchUi.loadResource(Rez.Strings.GoToStation) as String), Graphics.TEXT_JUSTIFY_CENTER);

        } else if (_state == STATE_SUCCESS) {
            dc.setColor(0x00FF66, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 0.12, Graphics.FONT_MEDIUM, (WatchUi.loadResource(Rez.Strings.ReservationOk) as String), Graphics.TEXT_JUSTIFY_CENTER);

            var cleanName2 = _stationName;
            if (cleanName2.length() > 22) { cleanName2 = cleanName2.substring(0, 19) + "..."; }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 0.34, Graphics.FONT_XTINY, cleanName2, Graphics.TEXT_JUSTIFY_CENTER);

            // "RESERVED" badge
            dc.setColor(0x1F1F1F, 0x1A1A1A);
            dc.fillRoundedRectangle(centerX - 70, centerY - 18, 140, 36, 8);
            dc.setColor(0x00FF66, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(centerX - 70, centerY - 18, 140, 36, 8);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, centerY - 12, Graphics.FONT_SMALL, (WatchUi.loadResource(Rez.Strings.Reserved) as String), Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 0.78, Graphics.FONT_XTINY, (WatchUi.loadResource(Rez.Strings.GoToStation) as String), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX, height * 0.87, Graphics.FONT_XTINY, (WatchUi.loadResource(Rez.Strings.UseYourApp) as String), Graphics.TEXT_JUSTIFY_CENTER);

        } else if (_state == STATE_ERROR) {
            dc.setColor(0xFF3333, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, centerY - 35, Graphics.FONT_MEDIUM, (WatchUi.loadResource(Rez.Strings.NoReservation) as String), Graphics.TEXT_JUSTIFY_CENTER);
            // Show the API error description (may be long)
            var errMsg = _errorMsg;
            if (errMsg.length() > 28) { errMsg = errMsg.substring(0, 25) + "..."; }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, centerY, Graphics.FONT_XTINY, errMsg, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0x00FF88, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, centerY + 30, Graphics.FONT_XTINY, (WatchUi.loadResource(Rez.Strings.SelectToRetry) as String), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
