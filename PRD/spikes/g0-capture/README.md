# G0 spike — capture + Vision

Phase G0 of [`PRD/gaze-focus.md`](../../gaze-focus.md) §12. Answers two questions
before any product code exists:

1. Does head yaw actually separate between two side-by-side displays?
2. Does the pipeline fit the §10 CPU budget of < 3% average CPU?

This is a throwaway measurement harness, not production code. It is not wired into
mStats and should not be — it lives in `PRD/spikes/` precisely so it cannot be
accidentally imported by the app target.

## Build and run

```bash
cd PRD/spikes/g0-capture
swiftc -O -o /tmp/g0-capture Sources/g0capture/main.swift
/tmp/g0-capture --help
```

No dependencies beyond the system frameworks. Frames are analysed in memory only
and never written to disk or sent anywhere — the file contains no networking code
at all, which is the §10 privacy requirement enforced structurally rather than by
convention.

## Permissions

The binary is unsigned, so macOS TCC attributes camera access to whatever process
launched it — usually Terminal or iTerm. Grant **that app** camera access in
System Settings → Privacy & Security → Camera. This is the same code-signature
caveat PRD §8 describes, and it is why §8's signing recommendation is a real
sequencing blocker rather than a footnote.

If the camera is already in use by another app (Zoom, FaceTime, Continuity
Camera), no frames arrive. The tool detects this and reports `INCONCLUSIVE` with
the likely causes rather than a spurious technical verdict.

## Measurement protocol

Follow it exactly or the tool will refuse to conclude anything — see
"Why it says INCONCLUSIVE" below.

1. Sit centred between the two displays, at your normal distance, in your normal
   lighting. Do not optimise the conditions; you are measuring the real case.
2. Verify your displays are **side by side**, not stacked. PRD §4 scopes v1 to
   side-by-side precisely because yaw does not separate vertically.
3. Run with the default 30 seconds. **Look at display B for the first third,
   then display A for the last third.** Actually turn your head — do not just
   move your eyes. Eye movement alone produces almost no head rotation, which is
   the whole premise of the feature and the thing most likely to invalidate the
   test if you do it wrong.
4. Swap which display you start on and run again. Side-of-first-display bias is
   real and a one-sided protocol will hide it.
5. Run at least 3 times and record the numbers.

## Reading the output

| Field | Meaning |
|---|---|
| `processed frames` | Frames that passed the throttle and ran Vision. This is what the CPU number covers. |
| `delivered frames` | Frames the camera produced. Much higher than processed is expected and correct — see throttling note below. |
| `faces detected` | Detection rate. Below ~80% suggests bad lighting and the yaw estimate will be unreliable. |
| `CPU (1 core=100%)` | This process's CPU over the run, via `proc_pidinfo`. Comparable to Activity Monitor. |
| `gap` | Difference in mean yaw between the two displays. The raw signal size. |
| `Cohen's d` | The verdict metric. ≥ 2 strong, ≥ 0.8 moderate, below poor. |
| `in-sample accuracy` | Threshold fitted **and evaluated on the same data**. Optimistic by construction — not evidence for §13's 90% target. |

## Verdict thresholds

- **PASS** (d ≥ 2) — proceed to G1 on head yaw as specced.
- **MARGINAL** (0.8 ≤ d < 2) — add pupil offset to the feature vector and re-run
  before committing to G1.
- **FAIL** (d < 0.8) — do not build G1 on yaw alone. The §11 risk row "head pose
  is not true gaze" is the dominant failure mode.

## Why it says INCONCLUSIVE

The tool distinguishes three outcomes that look similar in a raw mean/SD printout
but mean very different things:

- **No frames** → capture or permission problem. Says so explicitly rather than
  printing a zero-variance FAIL.
- **Too few samples** (< 20, or < 5 per group) → run longer or raise `--fps`.
- **Sufficient samples but identical groups** → the head did not move between
  them. This is a protocol failure, not a finding about yaw. Reporting it as
  `FAIL` would record a conclusion the data never tested.

A harness that cannot distinguish "the technique failed" from "the measurement
broke" produces confidently wrong results, which is worse than no harness.

## Notes on the implementation

**Frame rate is throttled in the consumer, not on the device.** Setting
`activeVideoMinFrameDuration` on this camera raises an `NSException` — which
`try`/`catch` cannot catch — whenever the requested duration falls outside the
active format's supported ranges. The spike therefore lets the camera run at its
natural rate and skips frames in the Vision callback before any Vision work
happens. This bounds pipeline cost identically while keeping the buffer holding
the freshest frame. It also means `delivered frames` will always exceed
`processed frames`; that is intended, not a bug.

**The constellation is pinned to 76 points.** `leftPupil` and `rightPupil` are
only populated under `VNRequestFaceLandmarksConstellation76Points`, and PRD §6.2
wants pupil positions in the feature vector. The request revision is pinned too.
Calibration data is persisted against a specific point count and revision, and
relying on an SDK default that has changed before would silently invalidate it.

**This derives yaw from 2D landmark asymmetry, not from Vision's yaw angle.**
See "Vision API correction" in the parent PRD — `VNDetectFaceLandmarksRequest`
does not expose yaw/pitch/roll at any revision. This is a conservative proxy: a
weak result here is a lower bound, not proof that a proper model would fail.