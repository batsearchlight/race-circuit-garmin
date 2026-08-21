using Toybox.WatchUi as Ui;

class RaceCircuitDelegate extends Ui.InputDelegate {
    private var _view;

    function initialize(view) {
        InputDelegate.initialize();
        _view = view;
    }

    function onTap(event) {
        _view.handleTap(event.getCoordinates());
        return true;
    }

    function onHold(event) {
        return true;
    }

    function onSwipe(event) {
        return _view.handleSwipe(event.getDirection());
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();

        if (key == Ui.KEY_ENTER) {
            _view.advance();
            return true;
        }

        if (key == Ui.KEY_ESC) {
            return _view.requestUndo();
        }

        if (key == Ui.KEY_MENU) {
            _view.handleHold();
            return true;
        }

        return false;
    }
}
