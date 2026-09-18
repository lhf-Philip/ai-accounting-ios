import { cappedPositiveInteger, parseInvitationCodes, parseReceipt, RequestError, sha256, utcDay, validateAnalyzeInput } from "./policy.js";
import {
  DEFAULT_MODEL,
  DEVICE_DAILY_REQUEST_HARD_CAP,
  estimateNeuronsFromUsage,
  PLATFORM_DAILY_ESTIMATED_NEURON_HARD_CAP,
  resolveModelPolicy
} from "./model-policy.js";

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
});

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname === "/health") return json({ ok: true });
    const id = env.QUOTA.idFromName("global");
    return env.QUOTA.get(id).fetch(request);
  }
};

export class GemmaQuota {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    try {
      const path = new URL(request.url).pathname;
      if (request.method === "POST" && path === "/v1/devices/register") return await this.register(request);
      if (request.method === "POST" && path === "/v1/receipts/analyze") return await this.analyze(request);
      if (request.method === "GET" && path === "/v1/usage") return await this.usage(request);
      return json({ error: { code: "not_found", message: "找不到此服務。" } }, 404);
    } catch (error) {
      const known = error instanceof RequestError;
      if (!known) console.error("Gemma backend error", error?.name, error?.message);
      return json({ error: { code: known ? error.code : "internal_error", message: known ? error.message : "服務暫時無法使用。" } }, known ? error.status : 500);
    }
  }

  async register(request) {
    const body = await request.json().catch(() => null);
    const inviteCode = String(body?.inviteCode || "").trim();
    const installationId = String(body?.installationId || "").trim();
    const platform = String(body?.platform || "").trim().toLowerCase();
    if (!inviteCode || installationId.length < 16 || !new Set(["ios", "android"]).has(platform)) {
      throw new RequestError(400, "invalid_registration", "邀請碼或設備資料格式錯誤。");
    }
    const allowed = parseInvitationCodes(this.env.INVITATION_CODES);
    if (!allowed.includes(inviteCode)) throw new RequestError(403, "invalid_invitation", "邀請碼無效。");
    const inviteHash = await sha256(inviteCode);
    const installationHash = await sha256(`${platform}:${installationId}`);
    const credential = randomSecret();
    const credentialHash = await sha256(credential);
    const deviceId = crypto.randomUUID();
    await this.ctx.storage.transaction(async txn => {
      if (await txn.get(`invite:${inviteHash}`)) throw new RequestError(409, "invitation_redeemed", "此邀請碼已使用。");
      await txn.put(`invite:${inviteHash}`, { deviceId, redeemedAt: new Date().toISOString() });
      await txn.put(`device:${deviceId}`, { credentialHash, installationHash, platform, createdAt: new Date().toISOString(), revoked: false });
    });
    return json({ deviceId, credential });
  }

  async authenticate(request) {
    const match = /^Bearer ([0-9a-f-]{36})\.([A-Za-z0-9_-]+)$/i.exec(request.headers.get("authorization") || "");
    if (!match) throw new RequestError(401, "unauthorized", "缺少有效的設備憑證。");
    const device = await this.ctx.storage.get(`device:${match[1]}`);
    const installationId = request.headers.get("x-installation-id") || "";
    const installationHash = installationId ? await sha256(`${device?.platform}:${installationId}`) : "";
    if (!device || device.revoked || device.credentialHash !== await sha256(match[2]) || device.installationHash !== installationHash) {
      throw new RequestError(401, "unauthorized", "設備憑證無效或已撤銷。");
    }
    return { deviceId: match[1], device };
  }

  async usage(request) {
    const { deviceId } = await this.authenticate(request);
    const day = utcDay();
    const [deviceUsage, globalUsage] = await Promise.all([
      this.ctx.storage.get(`usage:${day}:device:${deviceId}`),
      this.ctx.storage.get(`usage:${day}:global`)
    ]);
    return json(this.usagePayload(day, deviceUsage, globalUsage));
  }

  async analyze(request) {
    const { deviceId } = await this.authenticate(request);
    const input = validateAnalyzeInput(await request.json().catch(() => null));
    const policy = resolveModelPolicy(this.env.MODEL || DEFAULT_MODEL);
    const day = utcDay();
    const requestUpperBound = policy.requestUpperBoundEstimatedNeurons;
    await this.reserve(day, deviceId, input.requestId, requestUpperBound, policy.model);

    let rawResponse;
    try {
      rawResponse = await this.env.AI.run(policy.model, {
        messages: [{ role: "user", content: [
          { type: "text", text: receiptPrompt(input.userNote, input.categories) },
          { type: "image_url", image_url: { url: `data:${input.mimeType};base64,${input.imageBase64}` } }
        ] }],
        temperature: 0,
        max_completion_tokens: policy.maxCompletionTokens,
        stream: false,
        chat_template_kwargs: { enable_thinking: false }
      });
    } catch {
      await this.finalize(day, deviceId, input.requestId, requestUpperBound, null, "upstream_error");
      throw new RequestError(502, "upstream_error", "Gemma 暫時無法完成辨識；本次可能已耗用額度。");
    }

    const estimatedNeurons = estimateNeuronsFromUsage(rawResponse?.usage, policy);
    const content = rawResponse?.choices?.[0]?.message?.content ?? rawResponse?.response;
    let receipt;
    try {
      receipt = parseReceipt(content);
    } catch (error) {
      await this.finalize(day, deviceId, input.requestId, requestUpperBound, estimatedNeurons, "invalid_output");
      throw error;
    }
    const usage = await this.finalize(day, deviceId, input.requestId, requestUpperBound, estimatedNeurons, "success");
    return json({ receipt, usage });
  }

  async reserve(day, deviceId, requestId, requestUpperBound, model) {
    const requestKey = `request:${deviceId}:${requestId}`;
    const deviceKey = `usage:${day}:device:${deviceId}`;
    const globalKey = `usage:${day}:global`;
    const deviceLimit = this.deviceRequestLimit();
    const globalLimit = this.platformEstimatedNeuronLimit();
    await this.ctx.storage.transaction(async txn => {
      if (await txn.get(requestKey)) throw new RequestError(409, "duplicate_request", "此請求已處理，沒有再次呼叫模型。");
      const device = normalizeUsage(await txn.get(deviceKey));
      const global = normalizeUsage(await txn.get(globalKey));
      if (device.requests >= deviceLimit) throw new RequestError(429, "device_quota_exhausted", "此設備今日 Gemma 次數已用完。");
      if (global.committedEstimatedNeurons + global.pendingEstimatedNeurons + requestUpperBound > globalLimit) {
        throw new RequestError(429, "platform_quota_exhausted", "平台今日 Gemma 估算額度已用完。");
      }
      device.requests += 1;
      device.pendingEstimatedNeurons += requestUpperBound;
      global.requests += 1;
      global.pendingEstimatedNeurons += requestUpperBound;
      await txn.put(deviceKey, device);
      await txn.put(globalKey, global);
      await txn.put(requestKey, {
        day,
        model,
        requestUpperBoundEstimatedNeurons: requestUpperBound,
        status: "pending",
        createdAt: new Date().toISOString()
      });
    });
  }

  async finalize(day, deviceId, requestId, requestUpperBound, estimatedNeurons, result) {
    const deviceKey = `usage:${day}:device:${deviceId}`;
    const globalKey = `usage:${day}:global`;
    const chargedEstimatedNeurons = estimatedNeurons ?? requestUpperBound;
    await this.ctx.storage.transaction(async txn => {
      const requestKey = `request:${deviceId}:${requestId}`;
      const record = await txn.get(requestKey);
      if (!record || record.status !== "pending") return;
      for (const key of [deviceKey, globalKey]) {
        const usage = normalizeUsage(await txn.get(key));
        usage.pendingEstimatedNeurons = Math.max(0, usage.pendingEstimatedNeurons - requestUpperBound);
        usage.committedEstimatedNeurons += chargedEstimatedNeurons;
        await txn.put(key, usage);
      }
      await txn.put(requestKey, {
        ...record,
        status: "complete",
        result,
        estimatedNeurons: chargedEstimatedNeurons,
        completedAt: new Date().toISOString()
      });
    });
    const [deviceUsage, globalUsage] = await Promise.all([this.ctx.storage.get(deviceKey), this.ctx.storage.get(globalKey)]);
    return this.usagePayload(day, deviceUsage, globalUsage);
  }

  usagePayload(day, device = {}, global = {}) {
    const normalizedDevice = normalizeUsage(device);
    const normalizedGlobal = normalizeUsage(global);
    return {
      day,
      resetsAt: `${new Date(Date.parse(`${day}T00:00:00Z`) + 86_400_000).toISOString()}`,
      device: {
        requests: normalizedDevice.requests,
        requestLimit: this.deviceRequestLimit(),
        estimatedNeurons: normalizedDevice.committedEstimatedNeurons
      },
      platform: {
        estimatedNeurons: normalizedGlobal.committedEstimatedNeurons,
        estimatedNeuronLimit: this.platformEstimatedNeuronLimit()
      }
    };
  }

  deviceRequestLimit() {
    return cappedPositiveInteger(this.env.DEVICE_DAILY_REQUEST_LIMIT, DEVICE_DAILY_REQUEST_HARD_CAP, DEVICE_DAILY_REQUEST_HARD_CAP);
  }

  platformEstimatedNeuronLimit() {
    return cappedPositiveInteger(
      this.env.GLOBAL_DAILY_ESTIMATED_NEURON_LIMIT,
      PLATFORM_DAILY_ESTIMATED_NEURON_HARD_CAP,
      PLATFORM_DAILY_ESTIMATED_NEURON_HARD_CAP
    );
  }
}

function normalizeUsage(value) {
  return {
    requests: safeNonNegativeInteger(value?.requests),
    committedEstimatedNeurons: safeNonNegativeInteger(value?.committedEstimatedNeurons),
    pendingEstimatedNeurons: safeNonNegativeInteger(value?.pendingEstimatedNeurons)
  };
}

function safeNonNegativeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function randomSecret() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function receiptPrompt(note, categories) {
  const categoryList = categories.length ? categories.join(", ") : "未分類";
  return `Analyze this receipt for a personal finance app. User instruction: ${JSON.stringify(note)}. Allowed categories: ${categoryList}.
Return strict JSON only with amount (number), currency, date (YYYY-MM-DD), time (HH:mm or null), merchant, categoryName and note.
Use the relevant user share when instructed; otherwise use the grand total. If the year is missing assume the current UTC year. If currency is unknown use HKD. Choose an allowed category or 未分類. merchant, categoryName and note must use Traditional Chinese. note must be a string, never null.`;
}
