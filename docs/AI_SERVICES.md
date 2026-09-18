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
2. The app creates an installation identifier in iOS Keychain or Android Keystore-backed storage.
3. Registration atomically redeems the invitation once and returns a random device credential. The app stores it and the registered HTTPS origin in platform secure storage; the invitation itself is not retained. Later edits to the visible URL cannot redirect that credential to another origin.
4. Each receipt request presents the device credential and installation identifier. The Worker rejects copied credentials whose installation identifier does not match.
5. The Durable Object reserves quota before inference, calls only the configured Gemma model, records the returned Neurons, and returns the result for user review.

The installation identifier is not an immutable hardware ID. Reinstalling or losing secure storage requires a new maintainer-issued invitation. Registration never automatically grants a replacement quota.

## Quota and privacy

The initial deployment defaults are 50 receipt requests per device per UTC day, 5,000 Neurons for the whole platform per UTC day, and a 100-Neuron reservation for an in-flight request. These are deployment settings, not product constants. Cloudflare's account-level free allocation remains the outer hard limit.

Model errors and invalid output may still consume inference. Reported Neurons are charged to the device; when upstream usage is unknown, the reservation is retained as a conservative estimate. A request ID is accepted only once, so retries do not call the model twice.

Stored usage records contain the device ID, request ID, timestamps, result class, and Neurons. They do not contain images, user notes, categories, merchant names, or extracted receipt fields. Secrets, real invitation codes, and production URLs must not be committed.

## Verification

From `backend/gemma`:

```sh
npm install
npm test
npm run check
```

`npm test` uses a fake Workers AI binding and makes no live inference request. `npm run check` validates the Worker bundle and bindings without deploying it. Deployment and secret configuration are described in [`backend/gemma/README.md`](../backend/gemma/README.md).
