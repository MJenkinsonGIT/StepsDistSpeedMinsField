//
// Steps Distance Speed Mins Data Field - View
//
// Layout (upper slot / full-screen, flipped for lower slot):
//
//   +--[TIME]--[STEPS / GOAL]--+
//   |                           |
//   | [ACT.STEPS] [MOD.MIN]    |
//   | [DIST(mi) ] [VIG.MIN]    |
//   | [SPD(mph) ] [TOT.MIN]    |
//   +---------------------------+
//
// Left triangle  = activity steps, distance, speed
// Right triangle = moderate minutes, vigorous minutes, total minutes
// Top center     = time of day + daily steps vs goal
//
// Position is auto-detected via getObscurityFlags():
//   OBSCURE_TOP set   -> upper slot -> label row at top, values below
//   OBSCURE_BOTTOM set -> lower slot -> mirrored (label row at bottom)
//

import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class StepsDistSpeedMinsView extends WatchUi.DataField {

    // ── Cached display values ──────────────────────────────────────────────
    private var _timeStr    as String;   // "10:42 AM" / "10:42"
    private var _stepsStr   as String;   // "4,821 / 8k"
    private var _actSteps   as String;   // activity step count
    private var _distNum    as String;   // "1.23" (number only)
    private var _speedNum   as String;   // "3.4"  (number only)

    // ── Activity baselines (captured at timer start) ───────────────────────
    private var _baselineSteps  as Number;
    private var _baselineDistCm as Number;
    private var _modMin     as String;   // moderate intensity minutes this week
    private var _vigMin     as String;   // vigorous intensity minutes this week
    private var _totMin     as String;   // total = mod + 2*vig (WHO standard)
    private var _weekMinsStr as String;  // "51/150m" weekly intensity minutes vs goal

    // ── Intensity-minutes baseline (captured at timer start) ───────────────
    private var _imBaselineSet  as Boolean;
    private var _imBaseMod      as Number;
    private var _imBaseVig      as Number;

    // ── Tot color tracking (delta-based, 2-min timeout) ───────────────────
    private var _prevMod           as Number;  // mod count last cycle
    private var _prevVig           as Number;  // vig count last cycle
    private var _totColor          as Number;  // current Tot label color
    private var _lastAwardedMs     as Number;  // System.getTimer() when last minute awarded
    private const TOT_TIMEOUT_MS   = 120000;   // 2 minutes in milliseconds

    // ── Rolling speed (last 15 seconds of distance deltas) ────────────────
    private var _speedSamples   as Array<Dictionary<Symbol, Number>>;

    private const SPEED_WINDOW_MS  = 15000;  // 15-second rolling window
    private const MAX_SPEED_SAMPLES = 20;

    public function initialize() {
        DataField.initialize();

        _timeStr   = "--:--";
        _stepsStr  = "---";
        _actSteps  = "0";
        _distNum   = "0.00";
        _speedNum  = "0.0";

        _baselineSteps  = 0;
        _baselineDistCm = 0;
        _modMin      = "0";
        _vigMin      = "0";
        _totMin      = "0";
        _weekMinsStr = "0/150m";

        _imBaselineSet  = false;
        _imBaseMod      = 0;
        _imBaseVig      = 0;

        _prevMod       = 0;
        _prevVig       = 0;
        _totColor      = Graphics.COLOR_WHITE;
        _lastAwardedMs = 0;

        _speedSamples   = [] as Array<Dictionary<Symbol, Number>>;
    }

    // ── Timer lifecycle ────────────────────────────────────────────────────

    public function onTimerStart() as Void {
        var amInfo = ActivityMonitor.getInfo();
        // Capture activity baselines for steps and distance
        _baselineSteps  = (amInfo.steps    != null) ? amInfo.steps    : 0;
        _baselineDistCm = (amInfo.distance != null) ? amInfo.distance : 0;
        // Capture intensity minutes baseline
        if (!_imBaselineSet) {
            var weekMin = amInfo.activeMinutesWeek;
            if (weekMin != null) {
                _imBaseMod = weekMin.moderate;
                _imBaseVig = weekMin.vigorous;
            }
            _imBaselineSet = true;
        }
        // Seed speed buffer
        var nowMs = System.getTimer();
        for (var i = 0; i < _speedSamples.size(); i++) {
            _speedSamples[i] = { :distCm => 0, :time => nowMs };
        }
    }

    public function onTimerReset() as Void {
        _baselineSteps  = 0;
        _baselineDistCm = 0;
        _imBaselineSet  = false;
        _imBaseMod      = 0;
        _imBaseVig      = 0;
        _speedSamples   = [] as Array<Dictionary<Symbol, Number>>;
    }

    public function onTimerStop()   as Void { }
    public function onTimerPause()  as Void { }
    public function onTimerResume() as Void { }
    public function onTimerLap()    as Void { }

    // ── Compute (called periodically by runtime) ───────────────────────────

    public function compute(info as Activity.Info) as Void {

        // ── Time of day ──────────────────────────────────────────────────
        var clock   = System.getClockTime();
        var hour    = clock.hour;
        var minute  = clock.min;
        var devSet  = System.getDeviceSettings();
        if (!devSet.is24Hour) {
            var ampm = "AM";
            if (hour >= 12) {
                ampm = "PM";
                if (hour > 12) { hour = hour - 12; }
            }
            if (hour == 0) { hour = 12; }
            _timeStr = hour.format("%d") + ":" + minute.format("%02d") + " " + ampm;
        } else {
            _timeStr = hour.format("%02d") + ":" + minute.format("%02d");
        }

        // ── Daily steps / goal ───────────────────────────────────────────
        var amInfo = ActivityMonitor.getInfo();
        var dailySteps = 0;
        var stepGoal   = 0;
        if (amInfo.steps != null) { dailySteps = amInfo.steps; }
        if (amInfo.stepGoal != null) { stepGoal = amInfo.stepGoal; }

        var goalK = (stepGoal / 1000).format("%d") + "k";
        _stepsStr = dailySteps.format("%d") + "/" + goalK;

        // ── Weekly intensity minutes total vs goal ────────────────────────────
        var weekMin     = amInfo.activeMinutesWeek;
        var weekMinsGoal = amInfo.activeMinutesWeekGoal;
        var weekTotal   = (weekMin     != null) ? weekMin.total : 0;
        var weekGoal    = (weekMinsGoal != null) ? weekMinsGoal : 150;
        _weekMinsStr = weekTotal.format("%d") + "/" + weekGoal.format("%d") + "m";

        // ── Intensity minutes (delta from baseline) ──────────────────────
        var modDelta = 0;
        var vigDelta = 0;
        if (info.timerState != null && info.timerState == Activity.TIMER_STATE_ON) {
            if (weekMin != null) {
                modDelta = weekMin.moderate - _imBaseMod;
                vigDelta = weekMin.vigorous  - _imBaseVig;
                if (modDelta < 0) { modDelta = 0; }
                if (vigDelta < 0) { vigDelta = 0; }
            }
        }
        var totDelta = modDelta + (vigDelta * 2);
        _modMin = modDelta.format("%d");
        _vigMin = vigDelta.format("%d");
        _totMin = totDelta.format("%d");

        // ── Tot color: detect which counter ticked up this cycle ───────────
        var nowForColor = System.getTimer();
        var vigTicked = (vigDelta > _prevVig);
        var modTicked = (modDelta > _prevMod);
        if (vigTicked) {
            // Vigorous minute awarded -- red
            _totColor      = Graphics.COLOR_RED;
            _lastAwardedMs = nowForColor;
        } else if (modTicked) {
            // Moderate minute awarded (and no vigorous) -- green
            _totColor      = Graphics.COLOR_GREEN;
            _lastAwardedMs = nowForColor;
        } else if ((nowForColor - _lastAwardedMs) > TOT_TIMEOUT_MS) {
            // No new minute for 2 min -- reset to white
            _totColor = Graphics.COLOR_WHITE;
        }
        // else: color holds from last award
        _prevMod = modDelta;
        _prevVig = vigDelta;

        // ── Activity steps and distance (baseline-subtracted) ────────────
        var currentSteps  = _baselineSteps;
        var currentDistCm = _baselineDistCm;
        if (amInfo.steps    != null) { currentSteps  = amInfo.steps;    }
        if (amInfo.distance != null) { currentDistCm = amInfo.distance; }

        var sessionSteps  = currentSteps  - _baselineSteps;
        var sessionDistCm = currentDistCm - _baselineDistCm;
        if (sessionSteps  < 0) { sessionSteps  = 0; }
        if (sessionDistCm < 0) { sessionDistCm = 0; }

        var distMiles = sessionDistCm.toFloat() / 160934.4f;
        _actSteps = sessionSteps.format("%d");
        _distNum  = distMiles.format("%.2f");

        // ── Rolling speed via distance circular buffer ────────────────────
        if (info.timerState != null && info.timerState == Activity.TIMER_STATE_ON) {
            var nowMs = System.getTimer();
            var sample = { :distCm => sessionDistCm, :time => nowMs };
            _speedSamples.add(sample);

            // Trim samples outside 15-second window
            var cutoff = nowMs - SPEED_WINDOW_MS;
            while (_speedSamples.size() > 0) {
                var first = _speedSamples[0] as Dictionary<Symbol, Number>;
                if ((first[:time] as Number) >= cutoff) { break; }
                _speedSamples.remove(_speedSamples[0]);
            }
            while (_speedSamples.size() > MAX_SPEED_SAMPLES) {
                _speedSamples.remove(_speedSamples[0]);
            }

            var speedMph = 0.0f;
            if (_speedSamples.size() >= 2) {
                var oldest  = _speedSamples[0] as Dictionary<Symbol, Number>;
                var newest  = _speedSamples[_speedSamples.size() - 1] as Dictionary<Symbol, Number>;
                var deltaCm = (newest[:distCm] as Number) - (oldest[:distCm] as Number);
                var deltaMs = (newest[:time]   as Number) - (oldest[:time]   as Number);
                speedMph = (deltaCm.toFloat() / (deltaMs.toFloat() + 1.0f)) * (3600000.0f / 160934.4f);
            }
            _speedNum = speedMph.format("%.1f");
        } else {
            _speedNum = "0.0";
        }
    }

    // ── Render ─────────────────────────────────────────────────────────────
    //
    // Target layout (top slot):
    //
    //         [  TIME  ]                <- centered
    //       [steps / goal]              <- centered, below time
    //
    //  [steps]            [tot]         <- triangle apexes
    //
    //  [dist] [pace]   [mod] [vig]      <- triangle bases (dist/pace: no labels)
    //
    // Bottom slot mirrors vertically: apex at bottom, base at top.

    public function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Background
        var bgColor = getBackgroundColor();
        var fgColor = Graphics.COLOR_WHITE;
        if (bgColor == Graphics.COLOR_WHITE) { fgColor = Graphics.COLOR_BLACK; }
        dc.setColor(fgColor, bgColor);
        dc.clear();
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);

        // Tot color reflects last intensity-minute type awarded (with 2-min timeout)
        var totColor = _totColor;
        if (bgColor == Graphics.COLOR_WHITE && totColor == Graphics.COLOR_WHITE) {
            totColor = Graphics.COLOR_BLACK;  // light theme: white->black
        }

        // Detect slot
        var flags     = getObscurityFlags();
        var inBotSlot = (flags & OBSCURE_BOTTOM) != 0;
        var topLayout = !inBotSlot;

        // ── Horizontal positions (same for both orientations) ─────────────
        // Left peak shifted right vs. right peak shifted left to keep base
        // values away from the curved bezel edges.
        var xCenter    = w / 2;
        var xLeftPeak  = (w * 27) / 100 - 9;  // left apex  ~27% - 9px
        var xRightPeak = (w * 73) / 100 + 9;  // right apex ~73% + 9px
        var xSpread    = (w * 11) / 100;  // half-spread of base row

        var xLeftA  = xLeftPeak  - xSpread;  // dist  ~16%
        var xLeftB  = xLeftPeak  + xSpread;  // speed ~38%
        var xRightA = xRightPeak - xSpread;  // mod   ~62%
        var xRightB = xRightPeak + xSpread;  // vig   ~84%

        // ── Vertical positions (flipped for bottom slot) ──────────────────
        var yTime       = 0;
        var yDailySteps = 0;
        var yPeak       = 0;  // apex row (steps / tot)
        var yBase       = 0;  // base row (dist+speed / mod+vig)
        var labelOff    = 0;  // negative = label above value; positive = below

        if (topLayout) {
            yTime       = (h *  4) / 100;       //  4% (unchanged)
            yDailySteps = (h * 25) / 100 + 7;  // 25% + 7px down
            yPeak       = (h * 42) / 100 + 8;  // 42% + 8px down
            yBase       = (h * 69) / 100 + 15; // 69% + 15px down
            labelOff    = -22;
        } else {
            yTime       = (h * 76) / 100 - 10; // 76% - 10px up
            yDailySteps = (h * 61) / 100 - 17; // 61% - 17px up
            yPeak       = (h * 40) / 100 - 25; // 40% - 25px up
            yBase       = (h * 13) / 100 - 35; // 13% - 35px up
            labelOff    = 36;
        }

        // ── Header: time + daily steps + weekly intensity mins ──────────────
        // FONT_XTINY is ~13px tall; weekly mins sits 13+6=19px below daily steps
        dc.drawText(xCenter, yTime,            Graphics.FONT_SMALL,
                    _timeStr,   Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(xCenter, yDailySteps,      Graphics.FONT_XTINY,
                    _stepsStr,  Graphics.TEXT_JUSTIFY_CENTER);
        // Top slot: weekly mins sits 35px below daily steps (toward peak row)
        // Bot slot: weekly mins sits 35px above daily steps (toward peak row)
        var yWeekMins = topLayout ? yDailySteps + 41 : yDailySteps - 41;
        dc.drawText(xCenter, yWeekMins, Graphics.FONT_XTINY,
                    _weekMinsStr, Graphics.TEXT_JUSTIFY_CENTER);

        // ── Left triangle ─────────────────────────────────────────────────
        // Apex: steps count (with label)
        drawLabelValue(dc, xLeftPeak, yPeak, labelOff, "Steps", _actSteps);
        // Base: number in FONT_SMALL, unit in FONT_XTINY below
        dc.drawText(xLeftA, yBase + labelOff, Graphics.FONT_XTINY, "Mi",      Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(xLeftA, yBase,              Graphics.FONT_SMALL, _distNum,  Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(xLeftB, yBase + labelOff, Graphics.FONT_XTINY, "Mph",     Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(xLeftB, yBase,              Graphics.FONT_SMALL, _speedNum, Graphics.TEXT_JUSTIFY_CENTER);

        // ── Right triangle ────────────────────────────────────────────────
        // Tot: green=mod minute, red=vig minute, white=idle
        // Mod mirrors Tot green; Vig mirrors Tot red; the other reverts to white
        dc.setColor(totColor, Graphics.COLOR_TRANSPARENT);
        drawLabelValue(dc, xRightPeak, yPeak, labelOff, "Tot", _totMin);

        var modColor = fgColor;
        var vigColor = fgColor;
        if (totColor == Graphics.COLOR_GREEN) {
            modColor = Graphics.COLOR_GREEN;
            vigColor = fgColor;
        } else if (totColor == Graphics.COLOR_RED) {
            modColor = fgColor;
            vigColor = Graphics.COLOR_RED;
        }
        dc.setColor(modColor, Graphics.COLOR_TRANSPARENT);
        drawLabelValue(dc, xRightA, yBase, labelOff, "Mod", _modMin);
        dc.setColor(vigColor, Graphics.COLOR_TRANSPARENT);
        drawLabelValue(dc, xRightB, yBase, labelOff, "Vig", _vigMin);
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
    }

    // ── Helper: draw a label + value pair centered at (x, yValue) ─────────
    private function drawLabelValue(
            dc       as Dc,
            x        as Number,
            yValue   as Number,
            labelOff as Number,
            label    as String,
            value    as String) as Void {

        dc.drawText(x, yValue + labelOff, Graphics.FONT_XTINY,
                    label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, yValue, Graphics.FONT_SMALL,
                    value, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
