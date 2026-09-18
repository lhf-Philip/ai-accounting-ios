import test from "node:test";
import assert from "node:assert/strict";
import { estimateNeuronsFromUsage, resolveModelPolicy } from "../src/model-policy.js";
import { RequestError } from "../src/policy.js";

test("Gemma 4 policy has documented rates and conservative request upper bound", () => {
  const policy = resolveModelPolicy("@cf/google/gemma-4-26b-a4b-it");
  assert.equal(policy.contextWindowTokens, 256_000);
  assert.equal(policy.maxCompletionTokens, 1_024);
  assert.equal(policy.inputNeuronsPerMillionTokens, 9_091);
  assert.equal(policy.outputNeuronsPerMillionTokens, 27_273);
  assert.equal(policy.requestUpperBoundEstimatedNeurons, 2_356);
});

test("estimated Neurons round upward", () => {
  const policy = resolveModelPolicy();
  assert.equal(estimateNeuronsFromUsage({ prompt_tokens: 1, completion_tokens: 0, total_tokens: 1 }, policy), 1);
  assert.equal(estimateNeuronsFromUsage({ prompt_tokens: 1_000, completion_tokens: 100, total_tokens: 1_100 }, policy), 12);
});

test("missing, malformed, negative, non-finite or inconsistent usage fails closed", () => {
  const policy = resolveModelPolicy();
  const invalid = [
    undefined,
    {},
    { prompt_tokens: "1", completion_tokens: 1, total_tokens: 2 },
    { prompt_tokens: -1, completion_tokens: 1, total_tokens: 0 },
    { prompt_tokens: Number.POSITIVE_INFINITY, completion_tokens: 1, total_tokens: 1 },
    { prompt_tokens: 1, completion_tokens: 1, total_tokens: 3 },
    { prompt_tokens: 1, completion_tokens: 1_025, total_tokens: 1_026 },
    { prompt_tokens: 256_000, completion_tokens: 1, total_tokens: 256_001 }
  ];
  for (const usage of invalid) assert.equal(estimateNeuronsFromUsage(usage, policy), null);
});

test("unknown configured models are rejected", () => {
  assert.throws(() => resolveModelPolicy("@cf/example/not-supported"), RequestError);
});
