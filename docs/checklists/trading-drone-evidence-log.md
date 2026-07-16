# Trading Drone Evidence Log

Use this file to capture build-tagged parity evidence for each release-candidate run.

Record one row per platform/mode verification cycle.

This log proves deterministic trading-drone parity coverage only. It does not
prove that packaged app artifacts were manually installed/launched. Manual
release approval is recorded separately in
`docs/checklists/release-manual-signoff-log.md`.

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
| v1.0.3-test7 | 2026-06-20T23:28:36Z | macOS | situational | `472514d6d42c0a2f4abac187cf7b8b15ce95881fa65ad2a2ef999f19465e3fb4` | `fb0d1c364d8379cdf82a34da828036cdde5389e7792d3c13c601250c84f0a504` | `risk_allowed` | macOS release build smoke: plugin rank top SOL-USDT ready scan bf473b4da510; external-package intent executed; BingX order 2068476139097665536; tracking open=yes |
| v1.0.3-test7 | 2026-06-21T13:54:49Z | Android | situational | `bae47fca09191f03a241c7c5cb4ab7a4ffaa4da2f0a60d8969e803fe2c7d44eb` | `beef387e00f17e5423ddce3cfe5ed350136db67b1cb0665f08050c129cf1b9ba` | `risk_allowed` | Android release APK smoke: plugin install BingX 0.2.2; rank top DOGE-USDT ready scan 3c8885ed3ca7; external-package intent executed; BingX order 2068694131987296256 |
| v1.0.3-test7 | 2026-06-21T14:47:50Z | macOS | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `cc47a12c2c12f378ab214b274f2fb415c9d77aa757d649b7a4a4b880f0377a74` | `risk_blocked` | macOS deterministic fixture: interactive risk-block evidence; live market had no ready signal; fixture uses fixed envelope input and risk_governor endpoint |
| v1.0.3-test7 | 2026-06-21T14:55:09Z | Android | interactive | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `cd31134052d49cd7306cd32f13848db33bf3aeb4ddd4b262be7f570a9a296fe1` | `risk_allowed` | Android deterministic fixture: interactive parity evidence for release gate; device build installed versionCode 100000308; live market readiness not required |
| v1.0.3-test8 | 2026-06-21T15:32:21Z | macOS | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `f04cc7aafedc9e76b2bc73f7ab91ba38e3dbb723bf27a045663615d408d69cbf` | `risk_allowed` | macOS deterministic release fixture for v1.0.3-test8; validates situational envelope path after plugin/watchlist changes |
| v1.0.3-test8 | 2026-06-21T15:32:22Z | macOS | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `cc47a12c2c12f378ab214b274f2fb415c9d77aa757d649b7a4a4b880f0377a74` | `risk_blocked` | macOS deterministic release fixture for v1.0.3-test8; validates risk-block envelope path |
| v1.0.3-test8 | 2026-06-21T15:32:22Z | Android | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `ea767fe794bd53ee223dad76aa93e96c48ae2516c85c16124a0faaf9d48705ac` | `risk_allowed` | Android deterministic release fixture for v1.0.3-test8; matches installed versionCode 100000308 smoke path |
| v1.0.3-test8 | 2026-06-21T15:32:23Z | Android | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `62560832fef2e93692c76b6fae96cbc247b0466d9ba3cddca3025b293ee6616e` | `risk_blocked` | Android deterministic release fixture for v1.0.3-test8; validates risk-block parity path |
| v1.0.3-test9 | 2026-06-29T15:43:22Z | macOS | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `f04cc7aafedc9e76b2bc73f7ab91ba38e3dbb723bf27a045663615d408d69cbf` | `risk_allowed` | macOS deterministic release fixture for v1.0.3-test9; validates situational envelope path; manual smoke still required before publish |
| v1.0.3-test9 | 2026-06-29T15:43:22Z | macOS | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `cc47a12c2c12f378ab214b274f2fb415c9d77aa757d649b7a4a4b880f0377a74` | `risk_blocked` | macOS deterministic release fixture for v1.0.3-test9; validates interactive envelope path; manual smoke still required before publish |
| v1.0.3-test9 | 2026-06-29T15:43:22Z | Android | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `ea767fe794bd53ee223dad76aa93e96c48ae2516c85c16124a0faaf9d48705ac` | `risk_allowed` | Android deterministic release fixture for v1.0.3-test9; validates situational envelope path; manual smoke still required before publish |
| v1.0.3-test9 | 2026-06-29T15:43:23Z | Android | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `62560832fef2e93692c76b6fae96cbc247b0466d9ba3cddca3025b293ee6616e` | `risk_blocked` | Android deterministic release fixture for v1.0.3-test9; validates interactive envelope path; manual smoke still required before publish |
| v1.0.3-test10 | 2026-07-08T06:36:21Z | macOS | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `f04cc7aafedc9e76b2bc73f7ab91ba38e3dbb723bf27a045663615d408d69cbf` | `risk_allowed` | macOS-only release fixture for v1.0.3-test10; validates situational envelope path after credential prompt reduction |
| v1.0.3-test10 | 2026-07-08T06:36:21Z | macOS | interactive | `c36af88e8fbe2b025add8e970c89b1a149ac469a153179734304f81cbdb4b9a5` | `49c009a75580d8527efe479af8be4ba10dfbfc59c0c6bc9055f991918c9527b3` | `risk_blocked` | macOS manual smoke: SOL-USDT intent executed; follow-up execute blocked by risk_per_trade_exceeded after credential prompt reduction |
| v1.0.3-test10 | 2026-07-08T06:36:22Z | Android | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `ea767fe794bd53ee223dad76aa93e96c48ae2516c85c16124a0faaf9d48705ac` | `risk_allowed` | Gate parity fixture only; Android packaged-artifact manual signoff was not recorded for this macOS-only release |
| v1.0.3-test10 | 2026-07-08T06:36:22Z | Android | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `62560832fef2e93692c76b6fae96cbc247b0466d9ba3cddca3025b293ee6616e` | `risk_blocked` | Gate parity fixture only; Android packaged-artifact manual signoff was not recorded for this macOS-only release |
| v1.0.3-test11 | 2026-07-09T22:19:01Z | macOS | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `f04cc7aafedc9e76b2bc73f7ab91ba38e3dbb723bf27a045663615d408d69cbf` | `risk_allowed` | macOS deterministic release fixture for v1.0.3-test11; validates situational envelope path after invitation terminal retry and stale intent guard |
| v1.0.3-test11 | 2026-07-09T22:19:02Z | macOS | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `cc47a12c2c12f378ab214b274f2fb415c9d77aa757d649b7a4a4b880f0377a74` | `risk_blocked` | macOS deterministic release fixture for v1.0.3-test11; validates interactive risk-block envelope path |
| v1.0.3-test11 | 2026-07-09T22:19:03Z | Android | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `ea767fe794bd53ee223dad76aa93e96c48ae2516c85c16124a0faaf9d48705ac` | `risk_allowed` | Android deterministic release fixture for v1.0.3-test11; validates situational envelope path only; packaged-artifact manual signoff must be recorded separately |
| v1.0.3-test11 | 2026-07-09T22:19:04Z | Android | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `62560832fef2e93692c76b6fae96cbc247b0466d9ba3cddca3025b293ee6616e` | `risk_blocked` | Android deterministic release fixture for v1.0.3-test11; validates interactive risk-block envelope path |
| v1.0.3-test12 | 2026-07-16T14:49:59Z | macOS | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `f04cc7aafedc9e76b2bc73f7ab91ba38e3dbb723bf27a045663615d408d69cbf` | `risk_allowed` | macOS deterministic release fixture for v1.0.3-test12; validates situational envelope path after plugin catalog 0.2.3 and macOS reopen fix |
| v1.0.3-test12 | 2026-07-16T14:49:59Z | macOS | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `cc47a12c2c12f378ab214b274f2fb415c9d77aa757d649b7a4a4b880f0377a74` | `risk_blocked` | macOS deterministic release fixture for v1.0.3-test12; validates interactive risk-block envelope path |
| v1.0.3-test12 | 2026-07-16T14:49:59Z | Android | situational | `706d466fa1f68c7960df431f285d266b84a4cb099683184952b108514e435bc7` | `ea767fe794bd53ee223dad76aa93e96c48ae2516c85c16124a0faaf9d48705ac` | `risk_allowed` | Android deterministic release fixture for v1.0.3-test12; validates situational envelope path; packaged-artifact manual signoff required separately |
| v1.0.3-test12 | 2026-07-16T14:49:59Z | Android | interactive | `893a7effdb054c179794442737be47fddc3f2adee95896731a8e2fd7dc5ebcd7` | `62560832fef2e93692c76b6fae96cbc247b0466d9ba3cddca3025b293ee6616e` | `risk_blocked` | Android deterministic release fixture for v1.0.3-test12; validates interactive risk-block envelope path |
