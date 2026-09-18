import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { GemmaQuota } from "../src/worker.js";

globalThis.crypto ??= webcrypto;

class MemoryStorage {
  constructor() { this.values = new Map(); }
  async get(key) { return structuredClone(this.values.get(key)); }
  async put(key, value) { this.values.set(key, structuredClone(value)); }
  async transaction(action) { return action(this); }
}

const jsonRequest = (path, body, headers = {}) => new Request(`https://example.test${path}`, {
  method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body)
});

async function registeredQuota(overrides = {}) {
  const storage = new MemoryStorage();
  const env = {
    INVITATION_CODES: '["invitation-code-123456"]',
    DEVICE_DAILY_REQUEST_LIMIT: "1", GLOBAL_DAILY_NEURON_LIMIT: "5000", NEURON_RESERVATION: "100",
    MODEL: "test-model",
    AI: { run: async () => ({ response: '{"amount":12.5,"currency":"HKD","date":"2026-09-18","time":null,"merchant":"商店","categoryName":"餐飲","note":"午餐"}', usage: { neurons: 6 } }) },
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
  return { quota, headers, storage };
}

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

test("successful inference records actual per-device usage without receipt content", async () => {
  const { quota, headers, storage } = await registeredQuota();
  const response = await quota.fetch(jsonRequest("/v1/receipts/analyze", {
    requestId: "123e4567-e89b-12d3-a456-426614174000", imageBase64: "AA==", mimeType: "image/jpeg",
    userNote: "午餐", categories: ["餐飲"]
  }, headers));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.receipt.amount, 12.5);
  assert.equal(body.usage.device.neurons, 6);
  assert.equal(JSON.stringify([...storage.values.values()]).includes("商店"), false);
});

test("duplicate request and per-device quota do not call the model again", async () => {
  let calls = 0;
  const { quota, headers } = await registeredQuota({ AI: { run: async () => {
    calls += 1;
    return { response: '{"amount":1,"currency":"HKD","date":"2026-09-18","time":null,"merchant":"店","categoryName":"餐飲","note":"餐"}', usage: { neurons: 2 } };
  } } });
  const body = { requestId: "123e4567-e89b-12d3-a456-426614174000", imageBase64: "AA==" };
  assert.equal((await quota.fetch(jsonRequest("/v1/receipts/analyze", body, headers))).status, 200);
  assert.equal((await quota.fetch(jsonRequest("/v1/receipts/analyze", body, headers))).status, 409);
  assert.equal((await quota.fetch(jsonRequest("/v1/receipts/analyze", { ...body, requestId: "223e4567-e89b-12d3-a456-426614174000" }, headers))).status, 429);
  assert.equal(calls, 1);
});
