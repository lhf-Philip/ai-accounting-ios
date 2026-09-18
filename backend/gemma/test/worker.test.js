import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { resolveModelPolicy } from "../src/model-policy.js";
import { GemmaQuota } from "../src/worker.js";

globalThis.crypto ??= webcrypto;

class MemoryStorage {
  constructor() { this.values = new Map(); }
  async get(key) { return structuredClone(this.values.get(key)); }
  async put(key, value) { this.values.set(key, structuredClone(value)); }
  async transaction(action) { return action(this); }
}

const receiptJson = '{"amount":12.5,"currency":"HKD","date":"2026-09-18","time":null,"merchant":"商店","categoryName":"餐飲","note":"午餐"}';
const validUsage = { prompt_tokens: 1_000, completion_tokens: 100, total_tokens: 1_100 };
const modelResponse = (usage = validUsage) => ({
  choices: [{ message: { role: "assistant", content: receiptJson }, finish_reason: "stop" }],
  usage
});
const modelResponseWithoutUsage = () => ({
  choices: [{ message: { role: "assistant", content: receiptJson }, finish_reason: "stop" }]
});

const jsonRequest = (path, body, headers = {}) => new Request(`https://example.test${path}`, {
  method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body)
});

async function registeredQuota(overrides = {}) {
  const storage = new MemoryStorage();
  const env = {
    INVITATION_CODES: '["invitation-code-123456"]',
    DEVICE_DAILY_REQUEST_LIMIT: "50",
    GLOBAL_DAILY_ESTIMATED_NEURON_LIMIT: "5000",
    MODEL: "@cf/google/gemma-4-26b-a4b-it",
    AI: { run: async () => modelResponse() },
    ...overrides
  };
  const quota = new GemmaQuota({ storage }, env);
  const registration = await quota.fetch(jsonRequest("/v1/devices/register", {
    inviteCode: "invitation-code-123456", installationId: "installation-123456", platform: "ios"
  }));
  const credentials = await registration.json();
  const headers = {
    authorization: `Bearer ${credentials.deviceId}.${credentials.credential}`,
    "x-installation-id": "installation-123456"
  };
  return { quota, headers, storage, env };
}

const analyzeBody = requestId => ({
  requestId,
  imageBase64: "QUJDREVGRw==",
  mimeType: "image/jpeg",
  userNote: "午餐 secret-note",
  categories: ["餐飲"]
});

test("registration is one-time and credentials are installation-bound", async () => {
  const { quota, headers } = await registeredQuota();
  const second = await quota.fetch(jsonRequest("/v1/devices/register", {
    inviteCode: "invitation-code-123456", installationId: "another-installation", platform: "ios"
  }));
  assert.equal(second.status, 409);
  const wrongInstall = await quota.fetch(new Request("https://example.test/v1/usage", {
    headers: { ...headers, "x-installation-id": "copied-installation" }
  }));
  assert.equal(wrongInstall.status, 401);
});

test("official choices plus token usage response is parsed and stored only as estimated usage", async () => {
  let capturedModel;
  let capturedOptions;
  const { quota, headers, storage } = await registeredQuota({ AI: { run: async (model, options) => {
    capturedModel = model;
    capturedOptions = options;
    return modelResponse();
  } } });
  const response = await quota.fetch(jsonRequest("/v1/receipts/analyze", analyzeBody("123e4567-e89b-12d3-a456-426614174000"), headers));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.receipt.amount, 12.5);
  assert.equal(body.usage.device.estimatedNeurons, 12);
  assert.equal(body.usage.platform.estimatedNeuronLimit, 5_000);
  assert.equal(capturedModel, "@cf/google/gemma-4-26b-a4b-it");
  assert.equal(capturedOptions.max_completion_tokens, 1_024);
  const stored = JSON.stringify([...storage.values.values()]);
  for (const forbidden of ["商店", "secret-note", "QUJDREVGRw==", "Bearer ", "apiKey", receiptJson]) {
    assert.equal(stored.includes(forbidden), false, `stored data must not contain ${forbidden}`);
  }
});

test("missing or malformed token usage charges the full request reservation", async () => {
  const upperBound = resolveModelPolicy().requestUpperBoundEstimatedNeurons;
  for (const usage of [undefined, { prompt_tokens: -1, completion_tokens: 2, total_tokens: 1 }]) {
    const { quota, headers } = await registeredQuota({ AI: { run: async () => usage === undefined ? modelResponseWithoutUsage() : modelResponse(usage) } });
    const response = await quota.fetch(jsonRequest("/v1/receipts/analyze", analyzeBody("123e4567-e89b-12d3-a456-426614174000"), headers));
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.usage.platform.estimatedNeurons, upperBound);
  }
});

test("two pending reservations make the next request exceed the 5000 hard cap before AI is called", async () => {
  let calls = 0;
  const resolvers = [];
  const { quota, headers } = await registeredQuota({ AI: { run: () => {
    calls += 1;
    return new Promise(resolve => resolvers.push(resolve));
  } } });

  const first = quota.fetch(jsonRequest(
    "/v1/receipts/analyze", analyzeBody("123e4567-e89b-12d3-a456-426614174000"), headers
  ));
  const second = quota.fetch(jsonRequest(
    "/v1/receipts/analyze", analyzeBody("223e4567-e89b-12d3-a456-426614174000"), headers
  ));
  while (calls < 2) await new Promise(resolve => setImmediate(resolve));

  const third = await quota.fetch(jsonRequest(
    "/v1/receipts/analyze", analyzeBody("323e4567-e89b-12d3-a456-426614174000"), headers
  ));
  assert.equal(third.status, 429);
  assert.equal((await third.json()).error.code, "platform_quota_exhausted");
  assert.equal(calls, 2);

  resolvers.forEach(resolve => resolve(modelResponseWithoutUsage()));
  assert.equal((await first).status, 200);
  assert.equal((await second).status, 200);
});

test("finalize releases unused reservation and commits only the rounded estimate", async () => {
  const { quota, headers, storage } = await registeredQuota();
  const response = await quota.fetch(jsonRequest("/v1/receipts/analyze", analyzeBody("123e4567-e89b-12d3-a456-426614174000"), headers));
  assert.equal(response.status, 200);
  const values = [...storage.values.entries()];
  const global = values.find(([key]) => key.includes(":global"))?.[1];
  assert.equal(global.pendingEstimatedNeurons, 0);
  assert.equal(global.committedEstimatedNeurons, 12);
});

test("duplicate request and per-device daily request quota do not call the model again", async () => {
  let calls = 0;
  const { quota, headers } = await registeredQuota({
    DEVICE_DAILY_REQUEST_LIMIT: "1",
    AI: { run: async () => { calls += 1; return modelResponse(); } }
  });
  const body = analyzeBody("123e4567-e89b-12d3-a456-426614174000");
  assert.equal((await quota.fetch(jsonRequest("/v1/receipts/analyze", body, headers))).status, 200);
  assert.equal((await quota.fetch(jsonRequest("/v1/receipts/analyze", body, headers))).status, 409);
  assert.equal((await quota.fetch(jsonRequest("/v1/receipts/analyze", analyzeBody("223e4567-e89b-12d3-a456-426614174000"), headers))).status, 429);
  assert.equal(calls, 1);
});

test("unknown configured model is rejected before AI call", async () => {
  let calls = 0;
  const { quota, headers } = await registeredQuota({
    MODEL: "@cf/example/not-supported",
    AI: { run: async () => { calls += 1; return modelResponse(); } }
  });
  const response = await quota.fetch(jsonRequest("/v1/receipts/analyze", analyzeBody("123e4567-e89b-12d3-a456-426614174000"), headers));
  assert.equal(response.status, 503);
  assert.equal(calls, 0);
});
