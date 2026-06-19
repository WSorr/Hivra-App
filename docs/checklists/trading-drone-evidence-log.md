# Trading Drone Evidence Log

Use this file to capture build-tagged parity evidence for each release-candidate run.

Record one row per platform/mode verification cycle.

| Build Tag | Date (UTC) | Platform | Mode | Decision Envelope Hash | Execution Envelope Hash | Risk Path | Notes |
|---|---|---|---|---|---|---|---|

## Required Coverage Per Candidate

- `situational` on macOS
- `interactive` on macOS
- `situational` on Android
- `interactive` on Android
- at least one deterministic `risk_blocked` record
- at least one execution receipt trace (`drone.execution.envelope`)
- every decision/execution hash is exactly 64 hexadecimal characters

Verification command:

```bash
tools/release/check_trading_drone_evidence.sh --build-tag <version-tag>
```
