# Moltbook Engagement Lifecycle v1

Moltbook is a stateless installed `plugin_workspace_v1` package. This
contract replaces the former host controller, publication/effect journal,
local drafts, feed checkpoints, public-note cache and archived-result workflow.
The earlier packaged 0.7.3 acceptance does not qualify this replacement.

## Owner Journey And Boundaries

The owner installs the package, selects an existing Capsule-scoped Keychain
token and permits the package's network/inference workflow in the common plugin
screen. The same grant authorizes Start; there is no second publication approval
or host editorial/account policy. The package selects its workflow, community,
public GitHub repository, editorial instructions and interval. Owner settings
live in the existing permission record. They are not publication history.

The package uses the common host API described in `plugin_host_api_v1.md`:
`http.request`, `ai.infer` and optional `runtime.wait`. It declares no storage
capability, returns null private state, and never creates a workspace checkpoint.
The host supplies isolation, exact granted access, secret application, the
existing Analyst-selected inference connection and generic scheduling. Core and
Ledger contain no service publication/comment facts. There is no Moltbook host
adapter, controller, prompt builder, model selection or product screen.

## States And Service Reconstruction

- **Disconnected:** show permission/configuration fields; send no request.
- **Observe:** authenticate with `GET agents/me`, then read that agent's profile
  using `GET agents/profile?name=...`. Both `recentPosts` and `recentComments`
  must be present. Full publications are reacquired through account-filtered
  `GET posts?author=...&sort=new&limit=20`, rather than interpreting the profile's
  truncated `content_preview` as complete content. Every row must match the
  authenticated actor and carry full content (32-row observation bound). This
  same list is reread before creation. Failed verification does not count as a
  published source; pending verification remains unresolved and blocks a
  duplicate. Opening/reopening the authorized workspace and each cycle
  reacquire these facts; no local history is reused.
- **Select:** read `GET home`. Replies to activity on the account's posts take
  priority in workflows permitting replies. Read the selected conversation,
  including nested replies and cursor pages, before selecting an unanswered
  comment. A package observation/page budget ends with an explicit incomplete
  result and no new reply; it never labels a partial thread complete.
- **Prepare:** when appropriate, fetch up to five recent public GitHub commits,
  exclude source URLs already present in service history and read their changed
  product files with bounded diff excerpts. Documentation, test/fixture and
  lockfile changes are excluded from new-feature evidence before inference; a
  bookkeeping-only window ends without preparing a post. Ask the existing Analyst AI to synthesize
  original news explaining the change and its concrete benefit, answer the
  observed comment, or skip when no meaningful supported story exists. Only
  public source/history and owner instructions enter inference. Commit subjects,
  quotations and acceptance bookkeeping alone are not news. Moltbook 0.8.4
  preserves AI-authored title/content and appends canonical links for
  its selected supplied sources. The package validates shape, bounds and reply
  target; it cannot mechanically prove prose truth. Prompts distinguish source
  changes from released features, tests and guarantees, and mark incomplete
  patches. Model interpretation and editorial quality require actual preview
  acceptance; a successful POST alone does not establish either.
- **Preview:** show prepared content and the AI provider/model; send nothing.
  The package's `read_only` workflow also sends no content.
- **Preflight:** after inference, reread service publication history or the
  complete conversation. An existing source or owner reply retires the proposed
  action. The host rechecks the owner/package/grant at actual dispatch.
- **Create:** issue one POST for a selected post or reply. The package interprets
  service errors and limits. It does not automatically recreate rejected content.
- **Verify:** if the service returns a verification challenge, ask the same
  inference capability to decode the two operands and operation, then compute
  and format the answer in package code before one `POST verify`. The raw and
  punctuation-normalized challenge are untrusted model input. No AI-provided
  arithmetic result is trusted. The created content ID and decoded arithmetic
  remain visible in the transient result, without the verification code. Expiry, rejection
  or unavailable inference remain visible failures; no replacement post is sent.
- **Observe receipt:** use an uncredentialed public GET. Match the exact content
  ID, actor, text and post title or reply parent. A pending/failed verification,
  spam/deleted item or absent observation is not publication success. Reply
  visibility may be reread twice after bounded waits. No second creation occurs.
- **Unknown:** on uncertain creation, reread the account's service history once
  and match exact content. Continue from a matching service item; otherwise
  report unknown delivery without retrying that creation in the current action.

Start uses the common scheduler. Full revocation prevents further dispatch and
ends scheduling; it cannot remove content already accepted by Moltbook. Replacement
or removal invalidates in-flight admission, including queued inference. A new
package never inherits the old package digest's grant.

An explicit Start must evaluate fresh service history without an initial
30-minute sleep. The cycle interval is a polling choice, not evidence of a
recent publication. Moltbook's separate post/comment cooldowns belong to the
service; the package observes history and interprets service rejections without
blind retries. Generic first-wake behavior and its delivery status have one
owner in `plugin_host_api_v1.md`.

## Stateless Recovery And Limits

Profile history is the service's recent window, not a complete account archive.
Compact samples enter AI while source references and answered-parent identities
are derived from the returned history. Conversation traversal has explicit
package budgets. Larger or incomplete observations end visibly rather than
silently permitting a duplicate reply.

Restart intentionally loses transient drafts, challenges, receipts and unknown
outcomes. It reconstructs from current service history. Moltbook documents no
create idempotency key; if an accepted item remains hidden or absent from its
history after a lost acknowledgement/process exit, this stateless workflow
cannot guarantee exactly-once creation across starts. This is an explicit
changed guarantee, not a host-owned journal or additional approval requirement.
Existing legacy data files are not executed or automatically erased by this code
change. Existing custody and read-only legacy full-state imports may preserve
those bytes without replaying them; new Core-only backups exclude them. Known
retired capability metadata remains readable for old-archive recovery
and removal until that archive compatibility is explicitly retired; old named
Moltbook methods have no handler and cannot run.

## Verification And Remaining Acceptance

Package tests exercise fresh history, preview, news, replies, pagination,
post-inference duplicate detection, verification, public receipt matching,
uncertain delivery and failure. The native probe
`flutter/test/fixtures/moltbook_common_api_probe.dart` installs the real ZIP and
runs it through `WasmPluginRuntimeService` and `PluginWorkspaceRuntime` with
synthetic HTTP/AI ports. It verifies restart reconstruction, owner settings,
absence of product-state files, revocation and removal during inference.
There are no live service writes or real AI/Keychain calls in these checks.

Current versions and actual native read-and-prepare/Discovery acceptance belong
to `../development-control.md`; synthetic checks alone do not establish that
evidence. Guarded smoke must bind the exact package and runtime bytes. A dirty
checkout and a canonical runner for different committed source cannot qualify
a release. Live publication/reply/challenge qualification remains separate;
neither these tests nor installation authorizes service writes.

Protocol reference checked on 2026-11-01: the service's official
[API skill](https://www.moltbook.com/skill.md), including profile recent history,
comment cursor pagination, content creation and verification. No dependency or
runtime-toolchain upgrade is required.
