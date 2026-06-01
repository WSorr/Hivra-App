# Trading Drone Evidence Log

Use this file to capture build-tagged parity evidence for each release-candidate run.

Record one row per platform/mode verification cycle.

| Build Tag | Date (UTC) | Platform | Mode | Decision Envelope Hash | Execution Envelope Hash | Risk Path | Notes |
|---|---|---|---|---|---|---|---|
| v1.0.3-test2 | 2026-06-01T12:00:00Z | macOS | situational | `abc...` | `def...` | `risk_allowed` | baseline smoke |
| v1.0.3-test2 | 2026-06-01T12:15:00Z | Android | interactive | `abc...` | `def...` | `risk_blocked` | retry path exercised |

## Required Coverage Per Candidate

- `situational` on macOS
- `interactive` on macOS
- `situational` on Android
- `interactive` on Android
- at least one deterministic `risk_blocked` record
- at least one execution receipt trace (`drone.execution.envelope`)

Verification command:

```bash
tools/release/check_trading_drone_evidence.sh --build-tag <version-tag>
```
