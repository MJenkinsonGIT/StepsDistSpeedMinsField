# StepsDistSpeedMinsField

A data field for the Garmin Venu 3 that packs ten pieces of information into a single half-screen slot — activity steps, distance, rolling speed, session intensity minutes (total, moderate, and vigorous), plus a header showing the current time, daily step progress, and weekly intensity minute progress.

---

## About This Project

This app was built through **vibecoding** — a development approach where the human provides direction, intent, and testing, and an AI (in this case, Claude by Anthropic) writes all of the code. I have no formal programming background; this is an experiment in what's possible when curiosity and AI assistance meet.

Every line of Monkey C in this project was written by Claude. My role was to describe what I wanted, test each iteration on a real Garmin Venu 3, report back what worked and what didn't, and keep pushing until the result was something I was happy with.

As part of this process, I've been building a knowledge base — a growing collection of Markdown documents that capture the real-world lessons Claude and I have uncovered together: non-obvious API behaviours, compiler quirks, layout constraints specific to the Venu 3's circular display, and fixes for bugs that aren't covered anywhere in the official SDK documentation. These files are fed back into Claude at the start of each new session so the knowledge carries forward rather than being rediscovered from scratch every time.

The knowledge base is open source. If you're building Connect IQ apps for the Venu 3 and want to skip some of the trial and error, you're welcome to use it:

**[Venu 3 Claude Coding Knowledge Base](https://github.com/MJenkinsonGIT/Venu3ClaudeCodingKnowledge)**

---

## What It Displays

The slot is divided into a header row and two triangles:

```
          10:42 AM
        4821 / 8k
          51/150m

  Steps              Tot
   312               14

  Mi    Mph      Mod    Vig
  1.23   3.4      6      4
```

### Header (centre, top of slot)

| Value | Description |
|-------|-------------|
| **Time** | Current time of day — respects your 12/24-hour setting |
| **Daily steps / goal** | Your all-day step count vs your step goal (e.g. `4821/8k`) |
| **Weekly intensity mins / goal** | Your cumulative weekly intensity minutes vs your weekly goal (e.g. `51/150m`) |

### Left triangle — activity movement

| Value | Position | Description |
|-------|----------|-------------|
| **Steps** | Apex (centre-left) | Steps taken since the activity timer started |
| **Mi** | Base left | Distance covered since the activity timer started, in miles |
| **Mph** | Base right | Current rolling speed in miles per hour |

### Right triangle — intensity minutes

| Value | Position | Description |
|-------|----------|-------------|
| **Tot** | Apex (centre-right) | Total intensity minutes earned this session, colour-coded |
| **Mod** | Base left | Moderate intensity minutes earned this session |
| **Vig** | Base right | Vigorous intensity minutes earned this session |

---

## How Each Value Is Calculated

**Time** — reads `System.getClockTime()` and formats according to `System.getDeviceSettings().is24Hour`. No configuration needed.

**Daily steps / goal** — reads `ActivityMonitor.Info.steps` and `ActivityMonitor.Info.stepGoal`. This is your all-day step total, not just steps in the current activity. The goal is displayed shortened to the nearest thousand (e.g. `8k`).

**Weekly intensity mins / goal** — reads `ActivityMonitor.Info.activeMinutesWeek.total` and `activeMinutesWeekGoal`. This is your cumulative weekly total, not a per-session count. It updates as you earn minutes during the activity.

**Steps (activity)** — the Connect IQ SDK does not expose a direct per-session step count. This field works around that by snapshotting `ActivityMonitor.Info.steps` at the moment the activity timer starts, then subtracting that baseline from the current running total on each update. Resets to zero if the activity is discarded.

**Distance (Mi)** — calculated the same way as steps: a baseline of `ActivityMonitor.Info.distance` (in centimetres internally) is captured at timer start and subtracted from the current value. Converted to miles for display. This distance is not GPS-derived — Garmin estimates it from your step count using a stride length calculated from the height entered in your Garmin profile (typically around 41% of height per stride for walking, adjusted upward for running based on cadence and motion data). Accuracy therefore depends on how well your actual stride length matches Garmin's estimate for your height, and will vary between individuals and activity types.

**Speed (Mph)** — derived from the same step-based distance as above, not from GPS. A 15-second rolling average is calculated from a circular buffer of distance samples. Each compute cycle, the current session distance is added to the buffer; samples older than 15 seconds are discarded. Speed is then derived from the difference in distance between the oldest and newest sample in the buffer, divided by the elapsed time between them. This produces a smoother reading than instantaneous speed. Because both distance and speed come from step counting rather than GPS, they remain functional indoors and on treadmills where GPS is unavailable, but carry the same stride-length estimation caveats as the distance value above. Displays `0.0` when the timer is not running.

**Intensity minutes (Mod, Vig, Tot)** — like steps and distance, the SDK only exposes cumulative weekly intensity minute totals, not per-session values. Baselines for both moderate and vigorous are captured at timer start and subtracted each cycle to give session-only values. The total is calculated as `moderate + (vigorous × 2)`, matching the WHO physical activity guidelines and Garmin's own convention — one vigorous minute is equivalent to two moderate minutes.

### Tot colour coding

The **Tot** value (and the corresponding **Mod** or **Vig** value) changes colour when a new intensity minute is awarded:

| Colour | Meaning |
|--------|---------|
| **Green** | A moderate minute was just earned |
| **Red** | A vigorous minute was just earned |
| **White** (default) | No new minute in the last 2 minutes |

The colour persists for 2 minutes after the last award, then resets to white. This gives you a persistent visual confirmation of recent intensity without the display flickering on every compute cycle.

---

## Layout

This field was designed and tested exclusively in the **2-data-field layout**, where the screen is split into a top slot and a bottom slot. The field works correctly in **either position** — it detects which slot it occupies using the obscurity flags API and mirrors the entire layout vertically for the bottom slot, keeping the header near the watch edge and the triangle values filling the slot toward the centre of the face.

Due to the sheer number of elements that had to be individually positioned to fit within the Venu 3's circular bezel — ten values across two triangles plus a three-line header — this layout is highly specific to the 2-field slot dimensions. **It is very unlikely to display correctly in any other layout** (1-field full screen, 4-field quarter screen, or others). Using it outside the 2-field layout is not supported and has not been tested.

---

## Installation

### Which file should I download?

Each release includes three files. All three contain the same app — the difference is how they were compiled:

| File | Size | Best for |
|------|------|----------|
| `StepsDistSpeedMinsField-release.prg` | Smallest | Most users — just install and run |
| `StepsDistSpeedMinsField-debug.prg` | ~4× larger | Troubleshooting crashes — includes debug symbols |
| `StepsDistSpeedMinsField.iq` | Small (7-zip archive) | Developers / advanced users |

**Release `.prg`** is a fully optimised build with debug symbols and logging stripped out. This is what you want if you just want to use the app.

**Debug `.prg` + `.prg.debug.xml`** — these two files must be kept together. The `.prg` is the app binary; the `.prg.debug.xml` is the symbol map that translates raw crash addresses into source file names and line numbers. If the app crashes, the watch writes a log to `GARMIN\APPS\LOGS\CIQ_LOG.YAML` — cross-referencing that log against the `.prg.debug.xml` tells you exactly which line of code caused the crash. Without the `.prg.debug.xml`, the crash addresses in the log are unreadable hex. The app behaves identically to the release build; there is no difference in features or behaviour.

**`.iq` file** is a 7-zip archive containing the release `.prg` plus metadata (manifest, settings schema, signature). It is the format used for Connect IQ Store submissions. You can extract the `.prg` from it by renaming it to `.7z` and extracting — Windows 11 (22H2 and later) supports 7-zip natively via File Explorer's right-click menu. On older Windows versions you will need [7-Zip](https://www.7-zip.org/) (free).

---

**Option A — direct `.prg` download (simplest)**
1. Download the `.prg` file from the [Releases](#) section
2. Connect your Venu 3 via USB
3. Copy the `.prg` to `GARMIN\APPS\` on the watch
4. Press the **Back button** on the watch — it will show "Verifying Apps"
5. Unplug once the watch finishes

**Option B — debug build (for crash analysis)**
1. Download both `StepsDistSpeedMinsField-debug.prg` and `StepsDistSpeedMinsField.prg.debug.xml` — keep them together in the same folder on your PC
2. Copy `StepsDistSpeedMinsField-debug.prg` to `GARMIN\APPS\` on the watch
3. Press the **Back button** on the watch — it will show "Verifying Apps"
4. If the app crashes, retrieve `GARMIN\APPS\LOGS\CIQ_LOG.YAML` from the watch and cross-reference it against the `.prg.debug.xml` to identify the crash location

**Option C — extracting from the `.iq` file**
1. Rename `StepsDistSpeedMinsField.iq` to `StepsDistSpeedMinsField.7z`
2. Right-click it → **Extract All** (Windows 11 22H2+) or use [7-Zip](https://www.7-zip.org/) on older Windows
3. Inside the extracted folder, find the `.prg` file inside the device ID subfolder
4. Copy the `.prg` to `GARMIN\APPS\` on the watch
5. Press the **Back button** on the watch — it will show "Verifying Apps"
6. Unplug once the watch finishes

To add the field to an activity data screen: start an activity, long-press the lower button, navigate to **Data Screens**, and configure a screen for **2 data fields**. Place this field in either the top or bottom slot.

> **To uninstall:** Use Garmin Express. Sideloaded apps cannot be removed directly from the watch or the Garmin Connect phone app.

---

## Device Compatibility

Built and tested on: **Garmin Venu 3**
SDK Version: **8.4.1 / API Level 5.2**

Compatibility with other devices has not been tested.

---

## Notes

- All session values (Steps, Mi, Mph, Mod, Vig, Tot) show zero before the activity timer starts. Baselines are captured at timer start, so there is nothing to display until then.
- If you discard an activity, all session baselines reset to zero ready for the next start.
- **Daily steps** and **weekly intensity minutes** in the header are running all-day/all-week totals — they do not reset when a new activity starts.
- Distance and speed are step-based (derived from `ActivityMonitor`), not GPS-based. They are suitable for indoor walking and treadmill use where GPS is unavailable or unreliable.
- Speed updates every compute cycle using the 15-second rolling window. At the very start of an activity there may be a brief period before enough samples have accumulated for a meaningful speed reading.
