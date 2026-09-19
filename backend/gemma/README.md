# Invited Gemma backend

This Worker exposes only receipt analysis. It keeps the Cloudflare credential server-side, redeems each invitation once, issues one credential bound to that installation identifier, and records requests plus **token-derived estimated Neurons** per registered installation. Receipt images and extracted accounting content are not stored.

## Local checks

```sh
npm ci
npm test
npm run check
npm run check:staging
```

`npm test` uses only fake Workers AI responses. `npm run check` validates the top-level Worker configuration with Wrangler's dry run. `npm run check:staging` independently validates the named staging environment. Both dry runs compile and validate configuration only: they do **not** deploy a Worker, create Cloudflare resources, configure secrets, or call a live model.

## Model and accounting policy

The supported-model registry currently accepts only `@cf/google/gemma-4-26b-a4b-it`. Unknown `MODEL` values are rejected before Workers AI is called; this prevents another model from being charged with Gemma-specific rates.

Cloudflare documentation checked on 2026-09-18 states:

- context window: 256,000 tokens;
- price/accounting equivalence: 9,091 Neurons per 1M input tokens and 27,273 Neurons per 1M output tokens;
- Workers AI usage metadata: `prompt_tokens`, `completion_tokens`, and `total_tokens`.

Cloudflare documents `max_completion_tokens` as an upper-bound request parameter but does not publish a numeric model maximum on this model page. This service therefore sets and tests its own fixed completion bound of 1,024 tokens. With the documented 256,000-token context and the service-owned output bound, each request reserves the conservative maximum:

```text
ceil(256000 × 9091 / 1,000,000
   + 1024 × 27273 / 1,000,000)
= 2356 estimated Neurons
```

The returned token counts are converted to an **estimate** with the model-specific rates and rounded upward. The API and ledger deliberately call this value `estimatedNeurons`; it is not presented as a Cloudflare-reported actual Neuron count. Missing, malformed, negative, non-finite, inconsistent, or out-of-policy usage metadata fails closed and commits the full 2,356 reservation.

Official sources (checked 2026-09-18):

- <https://developers.cloudflare.com/workers-ai/models/gemma-4-26b-a4b-it/>
- <https://developers.cloudflare.com/workers-ai/platform/pricing/>
- <https://developers.cloudflare.com/api/resources/ai/methods/run/>

## Quota semantics

The hard application limits are 50 requests per installation per UTC day and 5,000 estimated Neurons across the platform per UTC day. Environment variables may lower these limits but cannot raise them above those hard caps.

Before inference, the Durable Object atomically checks:

```text
committedEstimatedNeurons + pendingEstimatedNeurons + requestUpperBound <= estimatedNeuronLimit
```

and reserves the full request upper bound. Finalization removes the reservation and commits the upward-rounded token-derived estimate. If trustworthy usage is unavailable, the whole reservation is committed. Cloudflare's separate account-level free allocation is an external billing limit and is not used to claim that this internal 5,000 cap is enforced.

A receipt `requestId` is the deduplication boundary: replaying the same `requestId` is rejected without another model call, while a new `requestId` is a new request and can consume request/estimated-Neuron quota. Registration is different: `installationId` is **not** an idempotency key. Replaying a redeemed invitation is rejected; registering again requires a new invitation.

Pending reservations are intentionally not auto-recovered after a Durable Object isolate/process failure in this blocker repair. A crash can therefore leave conservative pending usage until a future recovery mechanism is implemented.

## Staging configuration

The top-level Wrangler configuration remains production-compatible and must **not** be used as the staging deployment target. Cloudflare named environments append the environment name to the top-level Worker name, so `--env staging` is expected to target **`ai-accounting-gemma-staging`**.

The checked-in staging environment is intentionally isolated:

- it enables only `workers.dev` and declares no route or custom domain;
- it re-declares the non-inheritable `AI` binding and staging `vars`;
- it limits each device to **1** receipt request per UTC day and the platform to **2,356 estimated Neurons** per UTC day, which admits at most one current-model whole-request reservation;
- it binds `QUOTA` to `GemmaQuota` without `script_name`, so it resolves to the staging Worker rather than the top-level Worker's Durable Object namespace/storage;
- it explicitly declares its own `v1` `new_sqlite_classes` migration because environment-level Durable Object migrations override top-level migrations;
- it contains no invitation, Account ID, API token, or other secret.

Cloudflare environment and Durable Object behavior was rechecked on 2026-09-19:

- <https://developers.cloudflare.com/workers/wrangler/environments/>
- <https://developers.cloudflare.com/durable-objects/reference/environments/>
- <https://developers.cloudflare.com/durable-objects/reference/durable-objects-migrations/>
- <https://developers.cloudflare.com/durable-objects/best-practices/access-durable-objects-storage/>

A future explicitly approved staging deployment may add the one-time invitation only with Wrangler's hidden interactive secret input:

```sh
npx wrangler secret put INVITATION_CODES --env staging
```

Do not put an invitation, Cloudflare API token, or Account ID in this repository, a command argument, shell history, or CI log. This repository intentionally does not configure a staging invitation.

Passing either dry run is **not** evidence that staging was deployed and is **not** a real Workers AI validation. Any staging deployment, secret mutation, real Gemma request, or Cloudflare resource deletion requires a separate explicit decision.

## Configuration and deployment

1. Review `DEVICE_DAILY_REQUEST_LIMIT` and `GLOBAL_DAILY_ESTIMATED_NEURON_LIMIT` in `wrangler.jsonc`. They can only reduce the code-level 50 / 5,000 hard caps.
2. Generate a different random invitation code (at least 16 characters) for every installation. Store the JSON array as a secret; do not commit it:

   ```sh
   npx wrangler secret put INVITATION_CODES
   ```

3. Run `npm run deploy` only as an explicit deployment operation. Configure the resulting HTTPS URL in each invited app installation and redeem its code once.

No request logging should include invitation receipts, receipt/base64 payloads, API keys, bearer credentials, or full model output.
