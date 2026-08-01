# AI Proposal Boundary

Status: normative architecture contract for AI-assisted Hivra capabilities in
the maintained 1.x line and the design of Hivra 2.0.

This contract refines `product-axis.md` and
`architecture-execution-discipline.md`. It does not add an AI capability to
Core and does not create a third workflow lane.

## 1. Purpose

Hivra does not model an inference provider as an autonomous agent with tools.
An inference provider is an untrusted, nondeterministic proposal source.

The permanent boundary is:

```text
explicitly disclosed bounded input
  -> inference adapter
  -> untrusted proposal
  -> drone-owned deterministic validation and decision
  -> canonical capability intent or external-effect request
  -> approval/autonomy policy
  -> existing durable effect lifecycle
  -> capability-scoped adapter
  -> verified receipt or visible failure
```

Inference ends before authority begins. AI prose, structured output, tool-call
syntax, remote content, and provider metadata carry zero capability by default.

## 2. Relationship To The Hivra Axis

The boundary uses the existing two lanes:

- AI analysis that produces no effect remains advisory application/plugin
  state and does not enter the Truth Lane.
- A confirmed Core transition still enters the Truth Lane only through its
  existing capability command, signed fact, ledger append, and canonical
  projector.
- A provider, exchange, wallet, transport, or publication action enters the
  Effect Lane only after the capability owner creates a canonical effect
  request with a stable operation id.

AI output is never a ledger fact, receipt, approval, capability grant, policy,
or proof that an effect occurred.

## 3. Ownership And Dependency Rules

### 3.1 Core

Core knows nothing about Gemini, OpenAI, local models, Moltbook, trading
analysis, prompts, conversations, or model responses. Core continues to own
only its protocol facts and deterministic transitions.

### 3.2 Drone

Each WASM drone owns its domain semantics, proposal schema, deterministic
policy, and capability intent. A Moltbook proposal is not interchangeable with
a trading or staking proposal merely because all three may contain text.

### 3.3 Host

The host owns:

- explicit disclosure and redaction before inference;
- inference-provider credential access;
- schema, size, encoding, and safety validation;
- capability grants and local approval/autonomy policy;
- durable external-effect lifecycle and receipt reconciliation.

The host does not move provider business policy into Core or generic UI.

### 3.4 Adapters

An inference adapter can call only its configured inference origin. It has no
reference to capability adapters or effect executors. A capability adapter can
execute only its pinned provider contract and receives no raw AI response.

The application composition root may connect both adapter families, but
neither may call the other.

## 4. Contract Classes Without A Global DTO Layer

The architecture defines semantic classes, not one shared `AiAgentDto`:

1. **Disclosure envelope**: host-owned, previewable, bounded input selected for
   one inference request. It records provider/model, disclosed sections, size,
   and a canonical hash where the feature requires evidence.
2. **Proposal**: drone-owned untrusted value. It is parsed with an exact schema
   and contains no executable callback, URL, credential, capability, or effect
   state.
3. **Capability decision**: deterministic output owned by the drone or feature
   policy. It is reproducible without trusting AI prose.
4. **Effect request**: the existing capability-specific request entering
   Runtime External Effects or Delivery. Its operation id and canonical payload
   are created by trusted code, never supplied by inference.
5. **Receipt**: adapter evidence reconciled by the existing lifecycle owner.

Types stay with the contract that owns their invariants. Sharing a base class
is forbidden unless lifecycle and semantics are genuinely identical.

## 5. Prompt-Injection Invariant

Assume the inference provider is compromised and every remote post, comment,
market description, repository file, log line, and model response is hostile.

Even under that assumption, hostile input MUST NOT be able to:

- read or select a credential, seed, private key, contact, ledger history, or
  undeclared local file;
- grant a host capability or change a plugin manifest;
- choose an HTTP origin, endpoint, method, account scope, transport session,
  or effect adapter;
- choose or mutate an operation id, approval state, retry state, receipt, or
  deterministic policy;
- invoke Core mutation, ledger append, plugin installation, filesystem write,
  repository mutation, signing, publication, trading, staking, or transfer;
- convert a timeout, malformed response, or missing receipt into success;
- bypass a required exact preview, user approval, rate budget, kill switch, or
  capability-specific hard gate.

Prompts may instruct the model to ignore hostile text, but prompts are defense
in depth only. The invariant is enforced by absent references, exact schemas,
capability-scoped ports, deterministic policy, and the durable effect
lifecycle.

## 6. Validation Rules

Before a proposal reaches domain policy:

- parse one exact versioned schema and reject unknown fields;
- enforce byte/character, list, nesting, and item-count limits;
- reject unsupported links, effect markers, control characters, invisible
  direction/zero-width controls, and executable encodings where the contract
  does not explicitly permit them;
- keep remote identifiers as untrusted values until validated against the
  bounded observation that produced the proposal;
- preserve the selected Capsule/plugin scope across every asynchronous step;
- invalidate a prepared decision when reviewed input changes;
- never persist raw private inference context by default.

A proposal that passes structural validation is still untrusted. Structural
validity is not approval or factual correctness.

## 7. Operating Modes

### 7.1 Observe

AI may summarize bounded, redacted observations. It creates no capability
decision or external effect.

### 7.2 Assisted

AI proposes. The user reviews the exact outbound or executable intent. Trusted
code binds that reviewed value to a canonical decision/effect, and a separate
explicit action approves execution.

This is the default releasable mode for external writes.

### 7.3 Bounded Delegation

The user may delegate a narrow class of actions to one deterministic local
policy. The policy, not the AI, decides whether a proposal is eligible.

Every delegated capability requires all of the following before release:

- explicit action, topic, target, account, time, and rate bounds;
- deterministic allow/block reason codes and canonical policy version;
- per-Capsule and per-plugin kill switch;
- stable operation ids, durable queue, reconciliation, and receipt evidence;
- unattended restart, revocation, timeout, replay, and duplicate tests;
- hostile-input and compromised-model tests proving the invariant in section 5;
- mandatory return to Assisted mode for ambiguous, private, financial,
  identity, permission, deletion, or irreversible actions unless a separate
  capability specification proves a narrower safe rule.

Changing a profile field cannot silently promote Assisted mode into Bounded
Delegation.

## 8. Reference Mappings

### 8.1 Moltbook Ambassador

Remote conversations are untrusted disclosure input. Gemini may propose post
or reply prose. The Moltbook WASM drone binds exact reviewed text. The host
creates a canonical publication effect. The pinned Moltbook adapter publishes
only after explicit approval and records success only from a matching receipt.

### 8.2 Trading Drone

AI may explain normalized market snapshots, deterministic TVH decisions, risk
blocks, and tracked orders. It cannot select side, entry, leverage, notional,
risk policy, or execution state. Trading eligibility remains owned by the
deterministic trading pipeline and risk governor. Exchange submission uses its
own effect contract.

### 8.3 Staking Drone

AI may explain normalized positions and deterministic alerts. It cannot sign,
move funds, select validators, compound, unstake, or create wallet effects.
Any future executable action requires its own deterministic policy and wallet
effect specification.

## 9. Mandatory Evidence

Every AI-enabled capability must prove:

1. The inference service has no direct effect-adapter or Core-mutation path.
2. Unknown proposal and effect fields fail closed.
3. Hidden controls, oversized content, malformed JSON, and hostile remote text
   cannot alter capability scope.
4. Credentials are resolved only by the originating Capsule/plugin/provider/
   account scope after an effect is authorized.
5. Capsule switching and stale async completion cannot transfer a proposal or
   effect to another owner.
6. Duplicate clicks, retries, timeout-after-acceptance, restart, and missing
   receipts produce at most one semantic effect.
7. The UI distinguishes proposal, prepared decision, approved operation,
   delivery, unresolved state, and verified success.
8. Removing a plugin or Capsule deletes its private proposal/effect state and
   scoped credentials according to their existing lifecycle contracts.

## 10. Rejection Rules

Reject an implementation when:

- AI output is used directly as an adapter request;
- a model-selected tool name maps dynamically to a host capability;
- a generic fetch, shell, filesystem, repository, signing, or credential tool
  is exposed to inference;
- deterministic policy imports an inference adapter;
- Core imports AI or provider types;
- the App Shell becomes the policy owner;
- a second queue, retry loop, receipt store, or approval state is introduced;
- prompt wording is cited as the primary security boundary.

The defining Hivra property is not a smarter prompt. It is that intelligence
has no authority until a deterministic, capability-owned boundary grants one
specific effect through the existing lifecycle.
