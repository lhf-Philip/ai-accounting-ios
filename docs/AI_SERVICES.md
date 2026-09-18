# AI Services

Status: Active
Last reviewed: 2026-09-18
Applies to: iOS, Android, Cloudflare Worker

## Access policy

- A user-provided Gemini API key does not require an invitation. Its provider quota and charges belong to that key owner.
- The project-provided Gemma receipt service requires a one-time invitation for each app installation.
- Apple on-device receipt analysis remains a separately evaluated future path. It is not implemented by this change.
- No failure path silently switches from platform Gemma to a potentially paid user key.

Both current paths apply only to receipt analysis in this slice. Budget suggestions continue to use the existing user-provided Gemini key.

## Gemma request flow

1. The maintainer creates a random invitation code for one intended installation and adds it to the Worker's secret JSON array.
2. The app creates an installation identifier in iOS Keychain or Android Keystore-backed storage. On iOS, a newly generated identifier must be persisted successfully before a registration request is sent.
3. Registration atomically redeems the invitation once and returns a random device credential. The app stores it and the exact canonical HTTPS origin used for that registration in platform secure storage; the invitation itself is not retained. Later edits to the visible URL cannot redirect that credential to another origin.
4. Each receipt request presents the device credential and installation identifier. The Worker rejects copied credentials whose installation identifier does not match.
5. The Durable Object atomically reserves the supported model's whole-request estimated-Neuron upper bound before inference, then finalizes from trustworthy token usage or retains the whole reservation if usage cannot be trusted.

The installation identifier is not an immutable hardware ID and is not an idempotency key for registration. Replaying a redeemed invitation is rejected; registering again requires a new invitation. Receipt inference uses a different boundary: the same `requestId` is rejected without another model call, while a new `requestId` is a new request and may consume quota.

## Model policy and estimated-Neuron accounting

As checked against Cloudflare documentation on 2026-09-18, the only supported platform model is `@cf/google/gemma-4-26b-a4b-it`:

- context window: 256,000 tokens;
- input accounting rate: 9,091 Neurons per 1M input tokens;
- output accounting rate: 27,273 Neurons per 1M output tokens;
- documented usage fields: `prompt_tokens`, `completion_tokens`, `total_tokens`.

Cloudflare documents `max_completion_tokens` as an upper-bound parameter but does not give a numeric maximum on this model page. The service therefore owns a tested fixed output limit of 1,024 completion tokens. The conservative admission reservation is:

```text
ceil(256000 × 9091 / 1,000,000
   + 1024 × 27273 / 1,000,000)
= 2356 estimated Neurons
```

The Worker never depends on `usage.neurons`. It converts trustworthy token counts with the named model policy and rounds upward. These values are called `estimatedNeurons` / `estimatedNeuronLimit` because they are locally calculated estimates, not actual Neurons returned by Cloudflare. An unknown configured model is rejected before inference rather than applying Gemma rates to it.

Official Cloudflare sources:

- <https://developers.cloudflare.com/workers-ai/models/gemma-4-26b-a4b-it/>
- <https://developers.cloudflare.com/workers-ai/platform/pricing/>
- <https://developers.cloudflare.com/api/resources/ai/methods/run/>

## Quota and privacy

The application hard caps are 50 receipt requests per device per UTC day and 5,000 estimated Neurons for the whole platform per UTC day. Deployment settings may lower these values but cannot raise them.

Before every model call, one Durable Object transaction requires:

```text
committedEstimatedNeurons + pendingEstimatedNeurons + requestUpperBound <= 5000
```

For the current model, `requestUpperBound` is 2,356. Finalization releases the pending reservation and commits the upward-rounded token-derived estimate. Missing, malformed, negative, non-finite, inconsistent, or out-of-policy usage metadata fails closed by committing the full reservation. Cloudflare's separate account-level free allocation is an external billing boundary, not the mechanism enforcing this internal 5,000 cap.

Receipt requests bound category input by count, per-item length, and total category characters before building the prompt. Stored usage records contain only identifiers/hashes, timestamps, model name, result class, request upper bound, and estimated-Neuron counters. They do not contain receipt/base64 images, user notes, categories, merchant names, extracted receipt fields, API keys, bearer credentials, or full model output.

Android excludes only `platform_gemma_settings.xml` from Auto Backup cloud restore and device-to-device transfer, using both Android 12+ data extraction rules and the legacy full-backup rules. Other normal preferences keep the platform's default backup behavior.

## Known follow-up risk

This blocker repair does not implement automatic recovery of Durable Object pending reservations after an isolate/process crash. A crash after reservation but before finalization can leave conservative pending usage. Recovery/expiry should be designed separately so this repair does not expand the quota architecture.

## Verification

From `backend/gemma`:

```sh
npm install
npm test
npm run check
```

`npm test` uses fake Workers AI bindings and makes no live inference request. `npm run check` validates the Worker bundle and bindings without deploying it. Deployment and secret configuration are described in [`backend/gemma/README.md`](../backend/gemma/README.md).
