using Toybox.Application as App;

class RaceCircuitApp extends App.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new RaceCircuitView();
        return [view, new RaceCircuitDelegate(view)];
    }
}
