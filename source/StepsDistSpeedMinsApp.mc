//
// Steps Distance Speed Mins Data Field
// Combines activity steps/distance/speed and intensity minutes
// into a single half-screen field, with time + daily step goal in the header.
//

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class StepsDistSpeedMinsApp extends Application.AppBase {

    public function initialize() {
        AppBase.initialize();
    }

    public function getInitialView() {
        return [new StepsDistSpeedMinsView()];
    }
}

function getApp() as Application.AppBase {
    return Application.getApp();
}
