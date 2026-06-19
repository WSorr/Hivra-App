# Trading Drone Evidence Log

Use this file to capture build-tagged parity evidence for each release-candidate run.

Record one row per platform/mode verification cycle.

| Build Tag | Date (UTC) | Platform | Mode | Decision Envelope Hash | Execution Envelope Hash | Risk Path | Notes |
|---|---|---|---|---|---|---|---|
| v1.0.3-test6 | 2026-06-19T21:18:25Z | macOS | situational | `652892e56353f0a608d945680a40fc75e2260f6f01c8c50eb8dd2888562293ff` | `9fba3395ad299b2d27b7f25604ff2c7438ef462e1545fd2cc4807bbb9cd7e86e` | `risk_allowed` | macOS release candidate TRX-USDT live smoke, order 2068079093748445184 |
| v1.0.3-test6 | 2026-06-19T21:18:25Z | macOS | interactive | `8b45654e8bec3bbbbd1a8b73d29de4390bd52b92e6a788dedbf13aa789f8be70` | `2b19d9c4895353f4edc2b4a69a764cc8d4dd3027fd3bfa8ea2d754aec8586b0a` | `risk_allowed` | macOS release candidate second TRX-USDT live smoke, order 2068079538545995776 |
| v1.0.3-test6 | 2026-06-19T21:18:25Z | Android | situational | `74d4c6bbe85b27ee919c70de9f60154be3de718cb8db9d4c245250cbf98ca310` | `8dd5c4dfe1696956099411978921b9bce898c115562f22b1169b9a918a8c774f` | `risk_allowed` | Android release candidate TRX-USDT live smoke, order 2068080162213834752 |
| v1.0.3-test6 | 2026-06-19T21:18:25Z | Android | interactive | `74d4c6bbe85b27ee919c70de9f60154be3de718cb8db9d4c245250cbf98ca310` | `c451d63106812a8ff08a6887bbecf40cf7e7f487f79943b97799d2e8763bc848` | `risk_blocked` | Android release candidate risk governor blocked oversized TRX-USDT intent |

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
