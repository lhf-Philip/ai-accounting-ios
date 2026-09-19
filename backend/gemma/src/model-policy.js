import { RequestError } from "./policy.js";

export const DEFAULT_MODEL = "@cf/google/gemma-4-26b-a4b-it";
export const PLATFORM_DAILY_ESTIMATED_NEURON_HARD_CAP = 5_000;
export const DEVICE_DAILY_REQUEST_HARD_CAP = 50;

// Cloudflare model/pricing/API docs checked 2026-09-18.
// 1,024 is this service's tested completion cap; Cloudflare documents the
// max_completion_tokens parameter but not a numeric maximum for this model.
const MODEL_POLICIES = Object.freeze({
  [DEFAULT_MODEL]: Object.freeze({
    contextWindowTokens: 256_000,
    maxCompletionTokens: 1_024,
    inputNeuronsPerMillionTokens: 9_091,
    outputNeuronsPerMillionTokens: 27_273
  })
});

export function resolveModelPolicy(rawModel) {
  const model = String(rawModel || DEFAULT_MODEL).trim();
  const base = MODEL_POLICIES[model];
  if (!base) {
    throw new RequestError(503, "unsupported_model", "Gemma 服務模型設定不受支援。");
  }
  const requestUpperBoundEstimatedNeurons = Math.ceil(
    base.contextWindowTokens * base.inputNeuronsPerMillionTokens / 1_000_000 +
    base.maxCompletionTokens * base.outputNeuronsPerMillionTokens / 1_000_000
  );
  return Object.freeze({ model, ...base, requestUpperBoundEstimatedNeurons });
}

export function estimateNeuronsFromUsage(usage, policy) {
  if (!usage || typeof usage !== "object") return null;
  const promptTokens = tokenCount(usage.prompt_tokens);
  const completionTokens = tokenCount(usage.completion_tokens);
  const totalTokens = tokenCount(usage.total_tokens);
  if (promptTokens === null || completionTokens === null || totalTokens === null) return null;
  if (promptTokens + completionTokens !== totalTokens) return null;
  if (promptTokens > policy.contextWindowTokens || completionTokens > policy.maxCompletionTokens) return null;
  if (totalTokens > policy.contextWindowTokens) return null;

  const estimated = Math.ceil(
    promptTokens * policy.inputNeuronsPerMillionTokens / 1_000_000 +
    completionTokens * policy.outputNeuronsPerMillionTokens / 1_000_000
  );
  if (!Number.isSafeInteger(estimated) || estimated < 0 || estimated > policy.requestUpperBoundEstimatedNeurons) {
    return null;
  }
  return estimated;
}

function tokenCount(value) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : null;
}
