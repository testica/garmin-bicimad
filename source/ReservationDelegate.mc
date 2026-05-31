import Toybox.Lang;
import Toybox.WatchUi;

class ReservationDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ReservationView;

    function initialize(view as ReservationView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Scroll Down -> select cancel
    function onNextPage() as Boolean {
        if (_view.getState() == ReservationView.STATE_CONFIRM) {
            _view.setSelectedChoice(1);
        }
        return true;
    }

    // Scroll Up -> select confirm
    function onPreviousPage() as Boolean {
        if (_view.getState() == ReservationView.STATE_CONFIRM) {
            _view.setSelectedChoice(0);
        }
        return true;
    }

    // Select / Enter pressed
    function onSelect() as Boolean {
        var state = _view.getState();
        
        if (state == ReservationView.STATE_CONFIRM) {
            var choice = _view.getSelectedChoice();
            if (choice == 0) {
                // User confirmed: perform booking
                _view.performReservation();
            } else {
                // User cancelled: return to station list
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            }
        } else if (state == ReservationView.STATE_ERROR) {
            // Reset to try again on networking failure
            _view.setState(ReservationView.STATE_CONFIRM);
        } else if (state == ReservationView.STATE_SUCCESS) {
            // Successful reservation completed! Return back to station list view.
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
