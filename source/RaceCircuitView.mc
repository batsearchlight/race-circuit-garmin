using Toybox.Attention as Attention;
using Toybox.Graphics as Gfx;
using Toybox.Sensor as Sensor;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

class RaceCircuitView extends Ui.View {
    private var _names;
    private var _details;
    private var _isRun;
    private var _splits;
    private var _stationNames;
    private var _segmentStationIds;
    private var _stationOrder;
    private var _timer;

    private var _configured = false;
    private var _setupStep = 0;
    private var _setupSelection = 0;
    private var _singleMode = false;
    private var _division = 1;
    private var _scalePercent = 100;
    private var _reorderIndex = 0;
    private var _reorderMoving = false;
    private var _started = false;
    private var _finished = false;
    private var _segmentIndex = 0;
    private var _debriefPage = 0;
    private var _heartRate = null;
    private var _previousHeartRate = null;
    private var _lastHeartRateAlertTime = null;
    private var _lastBackPressTime = null;
    private var _startTime = 0;
    private var _segmentStartTime = 0;
    private var _finishTime = 0;

    function initialize() {
        View.initialize();

        _names = [];
        _details = [];
        _isRun = [];
        _segmentStationIds = [];

        _stationNames = [
            "SKIERG",
            "SLED PUSH",
            "SLED PULL",
            "BURPEES",
            "ROW",
            "FARMERS",
            "LUNGES",
            "W-BALLS"
        ];

        _stationOrder = [0, 1, 2, 3, 4, 5, 6, 7];

        _splits = [
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        ];

        _timer = new Timer.Timer();
    }

    function onShow() {
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensor));
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() {
        _timer.stop();
        Sensor.enableSensorEvents(null);
        Sensor.setEnabledSensors([]);
    }

    function onTick() {
        if (_lastBackPressTime != null &&
            System.getTimer() - _lastBackPressTime > 2000) {
            _lastBackPressTime = null;
            Ui.requestUpdate();
        }

        if (_started && !_finished) {
            Ui.requestUpdate();
        }
    }

    function onSensor(sensorInfo as Sensor.Info) as Void {
        if (sensorInfo.heartRate != null) {
            var nextHeartRate = sensorInfo.heartRate;

            if (_started && !_finished && _previousHeartRate != null) {
                var crossedYellow =
                    _previousHeartRate <= 160 && nextHeartRate > 160;
                var crossedRed =
                    _previousHeartRate < 180 && nextHeartRate >= 180;

                if (crossedYellow || crossedRed) {
                    var now = System.getTimer();
                    var cooldownFinished =
                        _lastHeartRateAlertTime == null ||
                        now - _lastHeartRateAlertTime >= 60000;

                    if (cooldownFinished) {
                        heartRateAlertBuzz(crossedRed);
                        _lastHeartRateAlertTime = now;
                    }
                }
            }

            _previousHeartRate = nextHeartRate;
            _heartRate = nextHeartRate;
            Ui.requestUpdate();
        }
    }

    function advance() {
        var now = System.getTimer();
        _lastBackPressTime = null;

        if (!_configured) {
            confirmSetup();
            return;
        }

        if (!_started) {
            _started = true;
            _startTime = now;
            _segmentStartTime = now;
            buzz(80, 180);
            Ui.requestUpdate();
            return;
        }

        if (_finished) {
            _debriefPage = (_debriefPage + 1) % getDebriefPageCount();
            Ui.requestUpdate();
            return;
        }

        _splits[_segmentIndex] = now - _segmentStartTime;

        if (_segmentIndex == _names.size() - 1) {
            _finished = true;
            _finishTime = now;
            _debriefPage = 0;
            finishBuzz();
        } else {
            _segmentIndex += 1;
            _segmentStartTime = now;
            buzz(65, 120);
        }

        Ui.requestUpdate();
    }

    function requestUndo() {
        if (!_started) {
            if (!_configured && _setupStep > 0) {
                _setupStep -= 1;
                syncSetupSelection();
                Ui.requestUpdate();
                return true;
            }
            return false;
        }

        if (_finished) {
            System.exit();
            return true;
        }

        var now = System.getTimer();

        if (_lastBackPressTime != null &&
            now - _lastBackPressTime <= 2000) {
            _lastBackPressTime = null;
            undo();
        } else {
            _lastBackPressTime = now;
            buzz(25, 70);
            Ui.requestUpdate();
        }

        return true;
    }

    function handleTap(coordinates) {
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;
        var x = coordinates[0];
        var y = coordinates[1];

        if (!_configured) {
            handleSetupTap(x, y, width, height);
            return;
        }

        if (!_started) {
            if (y >= (height * 66) / 100) {
                advance();
            }
            return;
        }

        if (!_finished ||
            (!_singleMode && _debriefPage != getDebriefPageCount() - 1)) {
            return;
        }

        if (x >= (width * 24) / 100 &&
            x <= (width * 76) / 100 &&
            y >= (height * 80) / 100 &&
            y <= (height * 92) / 100) {
            System.exit();
        }
    }

    function handleSwipe(direction) {
        if (!_started && direction == Ui.SWIPE_RIGHT) {
            System.exit();
            return true;
        }

        if (!_configured) {
            if (direction == Ui.SWIPE_UP) {
                moveSetupSelection(1);
                return true;
            }
            if (direction == Ui.SWIPE_DOWN) {
                moveSetupSelection(-1);
                return true;
            }
        }

        return false;
    }

    function getSetupChoiceCount() {
        if (_setupStep == 0) {
            return 2;
        }
        if (_setupStep == 1) {
            return 4;
        }
        if (_setupStep == 2) {
            return 3;
        }
        return 8;
    }

    function syncSetupSelection() {
        if (_setupStep == 0) {
            _setupSelection = _singleMode ? 1 : 0;
        } else if (_setupStep == 1) {
            _setupSelection = _division;
        } else if (_setupStep == 2) {
            _setupSelection = _scalePercent == 25
                ? 0
                : (_scalePercent == 50 ? 1 : 2);
        } else {
            _setupSelection = _reorderIndex;
        }
        _reorderMoving = false;
    }

    function confirmSetup() {
        if (_setupStep == 0) {
            _singleMode = _setupSelection == 1;
            _setupStep = 1;
            syncSetupSelection();
        } else if (_setupStep == 1) {
            _division = _setupSelection;
            _setupStep = 2;
            syncSetupSelection();
        } else if (_setupStep == 2) {
            _scalePercent = _setupSelection == 0
                ? 25
                : (_setupSelection == 1 ? 50 : 100);
            _setupStep = 3;
            _reorderIndex = 0;
            syncSetupSelection();
        } else if (_singleMode) {
            _stationOrder[0] = _setupSelection;
            finishSetup();
        } else {
            _reorderMoving = !_reorderMoving;
            Ui.requestUpdate();
        }
    }

    function moveSetupSelection(delta) {
        if (_setupStep == 3 && !_singleMode && _reorderMoving) {
            var target = _reorderIndex + delta;
            if (target < 0 || target >= _stationOrder.size()) {
                return;
            }
            var station = _stationOrder[_reorderIndex];
            _stationOrder[_reorderIndex] = _stationOrder[target];
            _stationOrder[target] = station;
            _reorderIndex = target;
            _setupSelection = target;
        } else {
            var count = getSetupChoiceCount();
            _setupSelection = (_setupSelection + delta + count) % count;
            if (_setupStep == 3 && !_singleMode) {
                _reorderIndex = _setupSelection;
            }
        }
        Ui.requestUpdate();
    }

    function handleSetupTap(x, y, width, height) {
        if (_setupStep == 3 && !_singleMode) {
            if (y >= (height * 82) / 100) {
                finishSetup();
            } else if (y >= (height * 28) / 100 &&
                y <= (height * 72) / 100) {
                confirmSetup();
            }
            return;
        }

        var count = getSetupChoiceCount();
        var top = (height * 24) / 100;
        var areaHeight = (height * 56) / 100;
        var rowHeight = areaHeight / count;
        var selected = (y - top) / rowHeight;

        if (y >= top && y < top + areaHeight &&
            selected >= 0 && selected < count) {
            _setupSelection = selected;
            confirmSetup();
        }
    }

    function finishSetup() {
        buildWorkout();
        _configured = true;
        _segmentIndex = 0;
        _debriefPage = 0;
        _reorderMoving = false;
        Ui.requestUpdate();
    }

    function buildWorkout() {
        _names = [];
        _details = [];
        _isRun = [];
        _segmentStationIds = [];

        if (_singleMode) {
            addStationSegment(_stationOrder[0]);
        } else {
            for (var index = 0; index < _stationOrder.size(); index += 1) {
                _names.add("RUN " + (index + 1).format("%d"));
                _details.add(getScaledDistance(1000) + " M");
                _isRun.add(true);
                _segmentStationIds.add(-1);
                addStationSegment(_stationOrder[index]);
            }
        }

        for (var split = 0; split < _splits.size(); split += 1) {
            _splits[split] = 0;
        }
    }

    function addStationSegment(station) {
        _names.add(_stationNames[station]);
        _details.add(getStationDetail(station));
        _isRun.add(false);
        _segmentStationIds.add(station);
    }

    function getScaledDistance(distance) {
        return (distance * _scalePercent) / 100;
    }

    function getDivisionName() {
        if (_division == 0) {
            return "WOMEN OPEN";
        }
        if (_division == 1) {
            return "MEN OPEN";
        }
        if (_division == 2) {
            return "WOMEN PRO";
        }
        return "MEN PRO";
    }

    function getStationDetail(station) {
        if (station == 0) {
            return getScaledDistance(1000) + " M";
        }
        if (station == 1) {
            var pushWeights = [102, 152, 152, 202];
            return (_scalePercent / 25).format("%d") +
                "X12.5M / " + pushWeights[_division].format("%d") + "KG";
        }
        if (station == 2) {
            var pullWeights = [78, 103, 103, 153];
            return (_scalePercent / 25).format("%d") +
                "X12.5M / " + pullWeights[_division].format("%d") + "KG";
        }
        if (station == 3) {
            return getScaledDistance(80) + " M";
        }
        if (station == 4) {
            return getScaledDistance(1000) + " M";
        }
        if (station == 5) {
            var farmerWeights = [16, 24, 24, 32];
            return getScaledDistance(200) + "M / 2X" +
                farmerWeights[_division].format("%d") + "KG";
        }
        if (station == 6) {
            var lungeWeights = [10, 20, 20, 30];
            return getScaledDistance(100) + "M / " +
                lungeWeights[_division].format("%d") + "KG";
        }

        var ballWeights = [4, 6, 6, 9];
        return getScaledDistance(100) + " REPS / " +
            ballWeights[_division].format("%d") + "KG";
    }

    function getDebriefPageCount() {
        return _singleMode ? 1 : 4;
    }

    function undo() {
        if (!_started) {
            return;
        }

        var now = System.getTimer();

        if (_finished) {
            if (_debriefPage > 0) {
                _debriefPage -= 1;
            } else {
                _finished = false;
                _splits[_segmentIndex] = 0;
                _segmentStartTime = now;
                buzz(35, 100);
            }
            Ui.requestUpdate();
            return;
        }

        if (_segmentIndex > 0) {
            _splits[_segmentIndex] = 0;
            _segmentIndex -= 1;
            _splits[_segmentIndex] = 0;
            _segmentStartTime = now;
            buzz(35, 100);
            Ui.requestUpdate();
        }
    }

    function handleHold() {
        if (!_configured && _setupStep == 3 && !_singleMode) {
            finishSetup();
            return;
        }

        if (_finished) {
            reset();
        }
    }

    function reset() {
        _started = false;
        _finished = false;
        _segmentIndex = 0;
        _debriefPage = 0;
        _startTime = 0;
        _segmentStartTime = 0;
        _finishTime = 0;
        _lastHeartRateAlertTime = null;
        _lastBackPressTime = null;

        for (var index = 0; index < _splits.size(); index += 1) {
            _splits[index] = 0;
        }

        buzz(45, 140);
        Ui.requestUpdate();
    }

    function buzz(strength, duration) {
        Attention.vibrate([
            new Attention.VibeProfile(strength, duration)
        ]);
    }

    function finishBuzz() {
        Attention.vibrate([
            new Attention.VibeProfile(100, 180),
            new Attention.VibeProfile(0, 100),
            new Attention.VibeProfile(100, 260)
        ]);
    }

    function heartRateAlertBuzz(isRed) {
        var strength = isRed ? 100 : 70;

        Attention.vibrate([
            new Attention.VibeProfile(strength, 110),
            new Attention.VibeProfile(0, 70),
            new Attention.VibeProfile(strength, 110)
        ]);
    }

    function formatDuration(milliseconds) {
        var totalSeconds = milliseconds / 1000;
        var hours = totalSeconds / 3600;
        var minutes = (totalSeconds % 3600) / 60;
        var seconds = totalSeconds % 60;

        if (hours > 0) {
            return hours.format("%d") + ":" +
                minutes.format("%02d") + ":" +
                seconds.format("%02d");
        }

        return minutes.format("%02d") + ":" + seconds.format("%02d");
    }

    function formatPace(milliseconds) {
        return formatPaceValue(milliseconds) + " /KM";
    }

    function formatPaceValue(milliseconds) {
        return milliseconds <= 0 ? "--:--" : formatDuration(milliseconds);
    }

    function getAverageRunPace() {
        var total = 0;
        var count = 0;

        for (var index = 0; index < _names.size(); index += 1) {
            if (_isRun[index] && _splits[index] > 0) {
                total += _splits[index];
                count += 1;
            }
        }

        return count > 0
            ? ((total / count) * 100) / _scalePercent
            : 0;
    }

    function getAverageStationTime() {
        var total = 0;
        var count = 0;

        for (var index = 0; index < _names.size(); index += 1) {
            if (!_isRun[index] && _splits[index] > 0) {
                total += _splits[index];
                count += 1;
            }
        }

        return count > 0 ? total / count : 0;
    }

    function getHeartRateText() {
        return _heartRate == null ? "--" : _heartRate.format("%d");
    }

    function getHeartRateColor() {
        if (_heartRate == null) {
            return 0x83939D;
        }
        if (_heartRate <= 160) {
            return 0x00E6A8;
        }
        if (_heartRate < 180) {
            return 0xFFD447;
        }

        return 0xFF453A;
    }

    function isBackConfirmationPending() {
        return _lastBackPressTime != null &&
            System.getTimer() - _lastBackPressTime <= 2000;
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        if (!_configured) {
            drawAtmosphere(dc, 0x00E6A8);
            drawSetup(dc);
        } else if (!_started) {
            drawAtmosphere(dc, 0x00E6A8);
            drawReady(dc);
        } else if (_finished) {
            drawAtmosphere(dc, 0x00E6A8);
            drawFinished(dc);
        } else {
            drawAtmosphere(
                dc,
                _isRun[_segmentIndex] ? 0x00E6A8 : 0xFF8A3D
            );
            drawActive(dc);
        }
    }

    function drawAtmosphere(dc, accent) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var centerY = height / 2;

        dc.setPenWidth(1);
        dc.setColor(0x142029, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(centerX, centerY, (width * 45) / 100);
        dc.setColor(0x0C151C, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(centerX, centerY, (width * 39) / 100);

        dc.setPenWidth(3);
        dc.setColor(0x22313A, Gfx.COLOR_TRANSPARENT);
        dc.drawArc(
            centerX,
            centerY,
            (width * 47) / 100,
            Gfx.ARC_CLOCKWISE,
            32,
            148
        );
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.drawArc(
            centerX,
            centerY,
            (width * 47) / 100,
            Gfx.ARC_CLOCKWISE,
            150,
            164
        );
        dc.setPenWidth(1);
    }

    function drawPanel(dc, x, y, width, height, radius) {
        dc.setColor(0x0C141A, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, width, height, radius);
        dc.setColor(0x26343D, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, width, height, radius);
    }

    function drawHeartIcon(dc, x, y, size, color) {
        var radius = size / 4;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - radius, y - radius, radius);
        dc.fillCircle(x + radius, y - radius, radius);
        dc.fillPolygon([
            [x - (size / 2), y - radius],
            [x + (size / 2), y - radius],
            [x, y + (size / 2)]
        ]);
    }

    function drawClockIcon(dc, x, y, size, color) {
        var radius = size / 2;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(x, y, radius);
        dc.drawLine(x, y, x, y - (radius / 2));
        dc.drawLine(x, y, x + (radius / 2), y);
        dc.setPenWidth(1);
    }

    function drawStopwatchIcon(dc, x, y, size, color) {
        var radius = size / 2;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(x, y + 2, radius);
        dc.drawLine(x - (radius / 3), y - radius, x + (radius / 3), y - radius);
        dc.drawLine(x, y - radius, x, y - radius - 4);
        dc.drawLine(x, y + 2, x + (radius / 2), y - (radius / 3));
        dc.setPenWidth(1);
    }

    function drawRunnerIcon(dc, x, y, size, color) {
        var unit = size / 6;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x + unit, y - (unit * 2), unit);
        dc.setPenWidth(3);
        dc.drawLine(x, y - unit, x + unit, y + unit);
        dc.drawLine(x, y - unit, x - (unit * 2), y);
        dc.drawLine(x, y - unit, x + (unit * 2), y - unit);
        dc.drawLine(x + unit, y + unit, x - unit, y + (unit * 3));
        dc.drawLine(x + unit, y + unit, x + (unit * 3), y + (unit * 2));
        dc.setPenWidth(1);
    }

    function drawDumbbellIcon(dc, x, y, size, color) {
        var plateWidth = size / 5;
        var plateHeight = size / 2;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(
            x - (size / 2),
            y - (plateHeight / 2),
            plateWidth,
            plateHeight,
            3
        );
        dc.fillRoundedRectangle(
            x + (size / 2) - plateWidth,
            y - (plateHeight / 2),
            plateWidth,
            plateHeight,
            3
        );
        dc.fillRectangle(
            x - (size / 2) + plateWidth,
            y - 2,
            size - (plateWidth * 2),
            4
        );
    }

    function drawSkiErgIcon(dc, x, y, size, color) {
        var unit = size / 6;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x - (unit * 2), y - (unit * 3), x - (unit * 2), y + (unit * 3));
        dc.drawLine(x + (unit * 2), y - (unit * 3), x + (unit * 2), y + (unit * 3));
        dc.drawLine(x - (unit * 2), y - (unit * 3), x + (unit * 2), y - (unit * 3));
        dc.drawLine(x - (unit * 2), y - unit, x, y + (unit * 2));
        dc.drawLine(x + (unit * 2), y - unit, x, y + (unit * 2));
        dc.setPenWidth(1);
    }

    function drawSledIcon(dc, x, y, size, color) {
        var unit = size / 6;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(x - (unit * 2), y - (unit * 3), x - (unit * 2), y + unit);
        dc.drawLine(x + (unit * 2), y - (unit * 3), x + (unit * 2), y + unit);
        dc.drawLine(x - (unit * 3), y + unit, x + (unit * 3), y + unit);
        dc.drawLine(x - (unit * 3), y + unit, x - (unit * 2), y + (unit * 2));
        dc.drawLine(x + (unit * 3), y + unit, x + (unit * 2), y + (unit * 2));
        dc.setPenWidth(1);
    }

    function drawBurpeeIcon(dc, x, y, size, color) {
        var unit = size / 6;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - (unit * 2), y - unit, unit);
        dc.setPenWidth(3);
        dc.drawLine(x - unit, y, x + (unit * 2), y);
        dc.drawLine(x, y, x - (unit * 2), y + (unit * 2));
        dc.drawLine(x + unit, y, x + (unit * 3), y + (unit * 2));
        dc.setPenWidth(1);
    }

    function drawRowIcon(dc, x, y, size, color) {
        var unit = size / 6;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - unit, y - (unit * 2), unit);
        dc.setPenWidth(2);
        dc.drawLine(x - unit, y - unit, x + unit, y + unit);
        dc.drawLine(x + unit, y + unit, x + (unit * 3), y + unit);
        dc.drawLine(x - (unit * 3), y + (unit * 2), x + (unit * 3), y + (unit * 2));
        dc.drawLine(x, y, x + (unit * 3), y - (unit * 3));
        dc.setPenWidth(1);
    }

    function drawLungeIcon(dc, x, y, size, color) {
        var unit = size / 6;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x, y - (unit * 3), unit);
        dc.setPenWidth(3);
        dc.drawLine(x, y - (unit * 2), x, y);
        dc.drawLine(x, y - unit, x - (unit * 2), y);
        dc.drawLine(x, y, x - (unit * 2), y + (unit * 2));
        dc.drawLine(x, y, x + (unit * 3), y + unit);
        dc.setPenWidth(1);
    }

    function drawBallIcon(dc, x, y, size, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(x, y, size / 3);
        dc.drawLine(x - (size / 3), y, x + (size / 3), y);
        dc.drawLine(x, y - (size / 3), x, y + (size / 3));
        dc.setPenWidth(1);
    }

    function drawExerciseIcon(dc, x, y, size, color) {
        if (_isRun[_segmentIndex]) {
            drawRunnerIcon(dc, x, y, size, color);
            return;
        }

        var station = _segmentStationIds[_segmentIndex];

        if (station == 0) {
            drawSkiErgIcon(dc, x, y, size, color);
        } else if (station == 1 || station == 2) {
            drawSledIcon(dc, x, y, size, color);
        } else if (station == 3) {
            drawBurpeeIcon(dc, x, y, size, color);
        } else if (station == 4) {
            drawRowIcon(dc, x, y, size, color);
        } else if (station == 5) {
            drawDumbbellIcon(dc, x, y, size, color);
        } else if (station == 6) {
            drawLungeIcon(dc, x, y, size, color);
        } else {
            drawBallIcon(dc, x, y, size, color);
        }
    }

    function drawProgressRail(dc, activeIndex, accent) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var startX = (width * 25) / 100;
        var endX = (width * 75) / 100;
        var segmentCount = _names.size();
        var step = segmentCount > 1
            ? (endX - startX) / (segmentCount - 1)
            : 0;
        var y = (height * 12) / 100;

        dc.setPenWidth(3);
        for (var index = 0; index < segmentCount; index += 1) {
            dc.setColor(
                index <= activeIndex ? accent : 0x26343D,
                Gfx.COLOR_TRANSPARENT
            );
            dc.drawLine(startX + (index * step), y, startX + (index * step) + 5, y);
        }
        dc.setPenWidth(1);
    }

    function drawSetup(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 7) / 100,
            Gfx.FONT_XTINY,
            "SETUP " + (_setupStep + 1).format("%d") + "/4",
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 14) / 100,
            Gfx.FONT_MEDIUM,
            getSetupTitle(),
            Gfx.TEXT_JUSTIFY_CENTER
        );

        if (_setupStep == 3 && !_singleMode) {
            drawOrderSetup(dc);
        } else {
            drawChoiceSetup(dc);
        }

        dc.setColor(0x596A75, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 92) / 100,
            Gfx.FONT_XTINY,
            "RECHTS WISCHEN: ENDE",
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function getSetupTitle() {
        if (_setupStep == 0) {
            return "MODUS";
        }
        if (_setupStep == 1) {
            return "DIVISION";
        }
        if (_setupStep == 2) {
            return "UMFANG";
        }
        return _singleMode ? "UEBUNG" : "REIHENFOLGE";
    }

    function getSetupChoice(index) {
        if (_setupStep == 0) {
            return index == 0 ? "GANZER RUN" : "EINZEL-UEBUNG";
        }
        if (_setupStep == 1) {
            var divisions = [
                "WOMEN OPEN", "MEN OPEN", "WOMEN PRO", "MEN PRO"
            ];
            return divisions[index];
        }
        if (_setupStep == 2) {
            var scales = ["25 %", "50 %", "100 %"];
            return scales[index];
        }
        return _stationNames[index];
    }

    function drawChoiceSetup(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var count = getSetupChoiceCount();
        var top = (height * 24) / 100;
        var areaHeight = (height * 56) / 100;
        var rowHeight = areaHeight / count;

        for (var index = 0; index < count; index += 1) {
            var y = top + (index * rowHeight);
            var selected = index == _setupSelection;
            dc.setColor(
                selected ? 0x00E6A8 : 0x0C141A,
                Gfx.COLOR_TRANSPARENT
            );
            dc.fillRoundedRectangle(
                (width * 17) / 100,
                y + 2,
                (width * 66) / 100,
                rowHeight - 4,
                18
            );
            dc.setColor(
                selected ? Gfx.COLOR_BLACK : Gfx.COLOR_WHITE,
                Gfx.COLOR_TRANSPARENT
            );
            dc.drawText(
                width / 2,
                y + ((rowHeight - dc.getFontHeight(Gfx.FONT_XTINY)) / 2),
                Gfx.FONT_XTINY,
                getSetupChoice(index),
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }

        dc.setColor(0x83939D, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            width / 2,
            (height * 83) / 100,
            Gfx.FONT_XTINY,
            "WISCHEN + START",
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function drawOrderSetup(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        for (var offset = -2; offset <= 2; offset += 1) {
            var index = _reorderIndex + offset;
            if (index < 0 || index >= _stationOrder.size()) {
                continue;
            }
            var y = ((30 + ((offset + 2) * 10)) * height) / 100;
            var selected = offset == 0;
            if (selected) {
                dc.setColor(
                    _reorderMoving ? 0xFF8A3D : 0x00E6A8,
                    Gfx.COLOR_TRANSPARENT
                );
                dc.fillRoundedRectangle(
                    (width * 12) / 100,
                    y - 3,
                    (width * 76) / 100,
                    (height * 9) / 100,
                    18
                );
            }
            dc.setColor(
                selected ? Gfx.COLOR_BLACK : 0x83939D,
                Gfx.COLOR_TRANSPARENT
            );
            dc.drawText(
                (width * 18) / 100,
                y,
                Gfx.FONT_XTINY,
                (index + 1).format("%d"),
                Gfx.TEXT_JUSTIFY_LEFT
            );
            dc.drawText(
                (width * 27) / 100,
                y,
                Gfx.FONT_XTINY,
                _stationNames[_stationOrder[index]],
                Gfx.TEXT_JUSTIFY_LEFT
            );
        }

        dc.setColor(0x83939D, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 75) / 100,
            Gfx.FONT_XTINY,
            _reorderMoving ? "WISCHEN: VERSCHIEBEN" : "START: VERSCHIEBEN",
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(
            (width * 29) / 100,
            (height * 82) / 100,
            (width * 42) / 100,
            (height * 9) / 100,
            20
        );
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 83) / 100,
            Gfx.FONT_XTINY,
            "MENU: FERTIG",
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function drawReady(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        drawPanel(
            dc,
            (width * 32) / 100,
            (height * 8) / 100,
            (width * 36) / 100,
            (height * 8) / 100,
            18
        );
        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 10) / 100,
            Gfx.FONT_XTINY,
            "RACE COMPANION",
            Gfx.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 22) / 100,
            Gfx.FONT_LARGE,
            "8 X 8",
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 34) / 100,
            Gfx.FONT_SMALL,
            "PIT CREW",
            Gfx.TEXT_JUSTIFY_CENTER
        );

        drawPanel(
            dc,
            (width * 18) / 100,
            (height * 43) / 100,
            (width * 64) / 100,
            (height * 21) / 100,
            24
        );
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            (width * 35) / 100,
            (height * 46) / 100,
            Gfx.FONT_SMALL,
            _singleMode ? "1 UEBUNG" : "8 RUNS",
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            (width * 65) / 100,
            (height * 46) / 100,
            Gfx.FONT_SMALL,
            _scalePercent.format("%d") + "%",
            Gfx.TEXT_JUSTIFY_CENTER
        );
        drawRunnerIcon(
            dc,
            (width * 35) / 100,
            (height * 58) / 100,
            18,
            0x83939D
        );
        drawDumbbellIcon(
            dc,
            (width * 65) / 100,
            (height * 57) / 100,
            24,
            0x83939D
        );
        dc.setColor(0x26343D, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(
            centerX,
            (height * 47) / 100,
            centerX,
            (height * 60) / 100
        );

        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 64) / 100,
            Gfx.FONT_XTINY,
            getDivisionName(),
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.fillRoundedRectangle(
            (width * 25) / 100,
            (height * 69) / 100,
            (width * 50) / 100,
            (height * 13) / 100,
            28
        );

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 72) / 100,
            Gfx.FONT_SMALL,
            "PRESS  >",
            Gfx.TEXT_JUSTIFY_CENTER
        );

    }

    function drawActive(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var now = System.getTimer();
        var accent = _isRun[_segmentIndex] ? 0x00E6A8 : 0xFF8A3D;
        var titleLength = _names[_segmentIndex].length();
        var titleFont = titleLength > 13 ? Gfx.FONT_XTINY : Gfx.FONT_SMALL;

        drawPanel(
            dc,
            (width * 27) / 100,
            (height * 2) / 100,
            (width * 46) / 100,
            (height * 9) / 100,
            18
        );
        drawProgressRail(dc, _segmentIndex, accent);

        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            (width * 35) / 100,
            (height * 4) / 100,
            Gfx.FONT_XTINY,
            (_segmentIndex + 1).format("%d") + "/" +
                _names.size().format("%d"),
            Gfx.TEXT_JUSTIFY_CENTER
        );
        var totalTimeText = formatDuration(now - _startTime);
        var totalTimeCenterX = (width * 63) / 100;
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            totalTimeCenterX,
            (height * 4) / 100,
            Gfx.FONT_XTINY,
            totalTimeText,
            Gfx.TEXT_JUSTIFY_CENTER
        );
        var totalTimeDimensions =
            dc.getTextDimensions(totalTimeText, Gfx.FONT_XTINY);
        drawClockIcon(
            dc,
            totalTimeCenterX + (totalTimeDimensions[0] / 2) + 8,
            (height * 6) / 100,
            10,
            accent
        );

        var heartRateColor = getHeartRateColor();
        drawHeartIcon(
            dc,
            (width * 31) / 100,
            (height * 24) / 100,
            34,
            heartRateColor
        );
        dc.setColor(heartRateColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            (width * 57) / 100,
            (height * 16) / 100,
            Gfx.FONT_NUMBER_MILD,
            getHeartRateText(),
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(0x83939D, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            (width * 75) / 100,
            (height * 24) / 100,
            Gfx.FONT_XTINY,
            "BPM",
            Gfx.TEXT_JUSTIFY_CENTER
        );

        var segmentTimeText = formatDuration(now - _segmentStartTime);
        var segmentTimeY = (height * 37) / 100;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            segmentTimeY,
            Gfx.FONT_NUMBER_MILD,
            segmentTimeText,
            Gfx.TEXT_JUSTIFY_CENTER
        );
        var segmentTimeDimensions =
            dc.getTextDimensions(segmentTimeText, Gfx.FONT_NUMBER_MILD);
        drawStopwatchIcon(
            dc,
            centerX + (segmentTimeDimensions[0] / 2) + 14,
            segmentTimeY +
                (dc.getFontHeight(Gfx.FONT_NUMBER_MILD) / 2),
            18,
            0x83939D
        );

        drawPanel(
            dc,
            (width * 11) / 100,
            (height * 55) / 100,
            (width * 78) / 100,
            (height * 22) / 100,
            24
        );
        var titleText = _names[_segmentIndex];
        var titleDimensions = dc.getTextDimensions(titleText, titleFont);
        var titleIconSize = 20;
        var titleGap = 8;
        var titleStartX =
            (width - titleDimensions[0] - titleIconSize - titleGap) / 2;
        var titleY = (height * 58) / 100;
        drawExerciseIcon(
            dc,
            titleStartX + (titleIconSize / 2),
            titleY + (dc.getFontHeight(titleFont) / 2),
            titleIconSize,
            accent
        );
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            titleStartX + titleIconSize + titleGap,
            titleY,
            titleFont,
            titleText,
            Gfx.TEXT_JUSTIFY_LEFT
        );
        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 68) / 100,
            Gfx.FONT_XTINY,
            _details[_segmentIndex],
            Gfx.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(accent, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(
            (width * 27) / 100,
            (height * 82) / 100,
            (width * 46) / 100,
            (height * 11) / 100,
            24
        );
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 84) / 100,
            Gfx.FONT_XTINY,
            isBackConfirmationPending() ? "BACK 2X" : "PRESS  >",
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function drawFinished(dc) {
        if (_debriefPage == 0) {
            drawDebriefSummary(dc);
        } else if (_debriefPage == 1) {
            drawRunGraph(dc);
        } else if (_debriefPage == 2) {
            drawStationPage(dc, 0, "STATIONS 1-4", "3 / 4");
        } else {
            drawStationPage(dc, 4, "STATIONS 5-8", "4 / 4");
        }
    }

    function drawDebriefHeader(dc, title, page) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        drawPanel(
            dc,
            (width * 32) / 100,
            (height * 5) / 100,
            (width * 36) / 100,
            (height * 8) / 100,
            18
        );
        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 7) / 100,
            Gfx.FONT_XTINY,
            "DEBRIEF  " + page,
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 15) / 100,
            Gfx.FONT_SMALL,
            title,
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function drawDebriefSummary(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        drawDebriefHeader(dc, "COMPLETE", "1 / 4");

        drawPanel(
            dc,
            (width * 14) / 100,
            (height * 26) / 100,
            (width * 72) / 100,
            (height * 22) / 100,
            24
        );
        drawClockIcon(
            dc,
            centerX,
            (height * 29) / 100,
            14,
            0x83939D
        );
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            (height * 33) / 100,
            Gfx.FONT_NUMBER_MILD,
            formatDuration(_finishTime - _startTime),
            Gfx.TEXT_JUSTIFY_CENTER
        );

        drawPanel(
            dc,
            (width * 11) / 100,
            (height * 53) / 100,
            (width * 78) / 100,
            (height * 22) / 100,
            24
        );
        dc.setColor(0x26343D, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(
            centerX,
            (height * 56) / 100,
            centerX,
            (height * 72) / 100
        );

        drawRunnerIcon(
            dc,
            (width * 30) / 100,
            (height * 57) / 100,
            20,
            0x83939D
        );
        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            (width * 30) / 100,
            (height * 62) / 100,
            Gfx.FONT_SMALL,
            formatPaceValue(getAverageRunPace()),
            Gfx.TEXT_JUSTIFY_CENTER
        );

        drawDumbbellIcon(
            dc,
            (width * 70) / 100,
            (height * 57) / 100,
            24,
            0x83939D
        );
        dc.setColor(0xFF8A3D, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            (width * 70) / 100,
            (height * 62) / 100,
            Gfx.FONT_SMALL,
            formatDuration(getAverageStationTime()),
            Gfx.TEXT_JUSTIFY_CENTER
        );

        if (_singleMode) {
            dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(
                (width * 24) / 100,
                (height * 80) / 100,
                (width * 52) / 100,
                (height * 12) / 100,
                20
            );
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                centerX,
                (height * 82) / 100,
                Gfx.FONT_XTINY,
                "APP BEENDEN",
                Gfx.TEXT_JUSTIFY_CENTER
            );
        } else {
            dc.setColor(0x83939D, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                centerX,
                (height * 81) / 100,
                Gfx.FONT_XTINY,
                "START >  MENU RESET",
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }
    }

    function drawRunGraph(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var paces = [
            (_splits[0] * 100) / _scalePercent,
            (_splits[2] * 100) / _scalePercent,
            (_splits[4] * 100) / _scalePercent,
            (_splits[6] * 100) / _scalePercent,
            (_splits[8] * 100) / _scalePercent,
            (_splits[10] * 100) / _scalePercent,
            (_splits[12] * 100) / _scalePercent,
            (_splits[14] * 100) / _scalePercent
        ];
        var minPace = paces[0];
        var maxPace = paces[0];

        for (var index = 1; index < paces.size(); index += 1) {
            if (paces[index] < minPace) {
                minPace = paces[index];
            }
            if (paces[index] > maxPace) {
                maxPace = paces[index];
            }
        }

        drawDebriefHeader(dc, "RUN PACE", "2 / 4");

        var left = (width * 14) / 100;
        var right = (width * 86) / 100;
        var top = (height * 28) / 100;
        var bottom = (height * 51) / 100;
        var stepX = (right - left) / 7;
        var paceRange = maxPace - minPace;
        var previousX = null;
        var previousY = null;

        drawPanel(
            dc,
            (width * 10) / 100,
            (height * 26) / 100,
            (width * 80) / 100,
            (height * 30) / 100,
            20
        );
        dc.setColor(0x26343D, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(left, top, right, top);
        dc.drawLine(left, (top + bottom) / 2, right, (top + bottom) / 2);
        dc.drawLine(left, bottom, right, bottom);

        for (var run = 0; run < paces.size(); run += 1) {
            var x = left + (run * stepX);
            var y = paceRange == 0
                ? (top + bottom) / 2
                : top + (((paces[run] - minPace) * (bottom - top)) / paceRange);

            if (previousX != null) {
                dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
                dc.drawLine(previousX, previousY, x, y);
            }

            dc.setColor(0xFF8A3D, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 5);

            dc.setColor(0x83939D, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                bottom + 4,
                Gfx.FONT_XTINY,
                (run + 1).format("%d"),
                Gfx.TEXT_JUSTIFY_CENTER
            );

            previousX = x;
            previousY = y;
        }

        drawPanel(
            dc,
            (width * 19) / 100,
            (height * 57) / 100,
            (width * 62) / 100,
            (height * 19) / 100,
            18
        );
        for (var paceRow = 0; paceRow < 4; paceRow += 1) {
            for (var paceColumn = 0; paceColumn < 2; paceColumn += 1) {
                var paceIndex = (paceRow * 2) + paceColumn;
                var paceX = ((30 + (paceColumn * 40)) * width) / 100;
                var paceY = ((58 + (paceRow * 5)) * height) / 100;

                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawText(
                    paceX,
                    paceY,
                    Gfx.FONT_XTINY,
                    (paceIndex + 1).format("%d") + " " +
                        formatDuration(paces[paceIndex]),
                    Gfx.TEXT_JUSTIFY_CENTER
                );
            }
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            width / 2,
            (height * 79) / 100,
            Gfx.FONT_XTINY,
            "BEST " + formatPace(minPace),
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            width / 2,
            (height * 85) / 100,
            Gfx.FONT_XTINY,
            "AVG  " + formatPace(getAverageRunPace()),
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function drawStationPage(dc, startStation, title, page) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        drawDebriefHeader(dc, title, page);

        for (var row = 0; row < 4; row += 1) {
            var orderIndex = startStation + row;
            var station = _stationOrder[orderIndex];
            var splitIndex = findSplitForStation(station);
            var y = ((28 + (row * 13)) * height) / 100;

            drawPanel(
                dc,
                (width * 13) / 100,
                ((26 + (row * 13)) * height) / 100,
                (width * 74) / 100,
                (height * 10) / 100,
                18
            );
            dc.setColor(0xFF8A3D, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                (width * 17) / 100,
                y,
                Gfx.FONT_XTINY,
                (orderIndex + 1).format("%d"),
                Gfx.TEXT_JUSTIFY_CENTER
            );

            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                (width * 24) / 100,
                y,
                Gfx.FONT_XTINY,
                _stationNames[station],
                Gfx.TEXT_JUSTIFY_LEFT
            );

            dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                (width * 84) / 100,
                y,
                Gfx.FONT_SMALL,
                formatDuration(_splits[splitIndex]),
                Gfx.TEXT_JUSTIFY_RIGHT
            );
        }

        if (startStation == 4) {
            dc.setColor(0x00E6A8, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(
                (width * 24) / 100,
                (height * 80) / 100,
                (width * 52) / 100,
                (height * 12) / 100,
                20
            );
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                width / 2,
                (height * 82) / 100,
                Gfx.FONT_XTINY,
                "APP BEENDEN",
                Gfx.TEXT_JUSTIFY_CENTER
            );
        } else {
            dc.setColor(0x83939D, Gfx.COLOR_TRANSPARENT);
            dc.drawText(
                width / 2,
                (height * 82) / 100,
                Gfx.FONT_XTINY,
                "START >  MENU RESET",
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }
    }

    function findSplitForStation(station) {
        for (var index = 0; index < _segmentStationIds.size(); index += 1) {
            if (_segmentStationIds[index] == station) {
                return index;
            }
        }
        return 0;
    }
}
