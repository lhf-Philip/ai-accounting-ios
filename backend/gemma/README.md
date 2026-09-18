# Invited Gemma backend

This Worker exposes only receipt analysis. It keeps the Cloudflare credential server-side, redeems each invitation once, issues one credential bound to that installation identifier, and records requests and Neurons per registered installation. Receipt images and extracted accounting content are not stored.

## Local checks

```sh
npm install
npm test
npm run check
```

## Configuration and deployment

1. Review `DEVICE_DAILY_REQUEST_LIMIT`, `GLOBAL_DAILY_NEURON_LIMIT`, and `NEURON_RESERVATION` in `wrangler.jsonc`.
2. Generate a different random invitation code (at least 16 characters) for every installation. Store the JSON array as a secret; do not commit it:

   ```sh
   npx wrangler secret put INVITATION_CODES
   ```

3. Run `npm run deploy`. Configure the resulting HTTPS URL in each invited app installation and redeem its code once.

The free allocation resets at 00:00 UTC. The configured platform limit is intentionally below Cloudflare's account limit. A request reserves Neurons before inference; unknown upstream usage is charged at the reservation. Invalid model output still consumes reported usage.
