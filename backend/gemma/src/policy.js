const encoder = new TextEncoder();

const MAX_CATEGORY_COUNT = 100;
const MAX_CATEGORY_LENGTH = 80;
const MAX_CATEGORY_TOTAL_LENGTH = 4_000;

export function utcDay(now = new Date()) {
  return now.toISOString().slice(0, 10);
}

export function cappedQuotaInteger(raw, defaultValue, maximum) {
  if (raw === undefined) return defaultValue;

  let value;
  if (typeof raw === "number") {
    value = raw;
  } else if (typeof raw === "string") {
    const normalized = raw.trim();
    if (!/^\d+$/.test(normalized)) throw invalidConfiguration();
    value = Number(normalized);
  } else {
    throw invalidConfiguration();
  }

  if (!Number.isSafeInteger(value) || value < 0) throw invalidConfiguration();
  return Math.min(value, maximum);
}

function invalidConfiguration() {
  return new RequestError(503, "invalid_configuration", "Gemma 服務設定錯誤。");
}

export async function sha256(value) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

export function parseInvitationCodes(raw) {
  let values;
  try {
    values = JSON.parse(raw || "[]");
  } catch {
    throw new Error("INVITATION_CODES must be a JSON array");
  }
  if (!Array.isArray(values) || values.some(value => typeof value !== "string" || value.trim().length < 16)) {
    throw new Error("Every invitation code must be a string with at least 16 characters");
  }
  return values.map(value => value.trim());
}

export function validateAnalyzeInput(body) {
  if (!body || typeof body !== "object") throw new RequestError(400, "invalid_request", "請求格式錯誤。");
  const requestId = String(body.requestId || "");
  if (!/^[0-9a-fA-F-]{36}$/.test(requestId)) throw new RequestError(400, "invalid_request_id", "requestId 格式錯誤。");
  const imageBase64 = String(body.imageBase64 || "");
  if (!imageBase64 || imageBase64.length > 8_000_000) throw new RequestError(413, "image_too_large", "圖片不可超過約 6 MB。");
  const mimeType = String(body.mimeType || "image/jpeg");
  if (!new Set(["image/jpeg", "image/png", "image/webp"]).has(mimeType)) {
    throw new RequestError(415, "unsupported_image", "只支援 JPEG、PNG 或 WebP。");
  }
  const userNote = String(body.userNote || "").slice(0, 500);
  const categories = validateCategories(body.categories);
  return { requestId, imageBase64, mimeType, userNote, categories };
}

function validateCategories(rawCategories) {
  if (rawCategories === undefined || rawCategories === null) return [];
  if (!Array.isArray(rawCategories)) throw new RequestError(400, "invalid_categories", "分類格式錯誤。");
  if (rawCategories.length > MAX_CATEGORY_COUNT) throw new RequestError(413, "categories_too_large", "分類數量過多。");

  const categories = [];
  let totalLength = 0;
  for (const value of rawCategories) {
    if (typeof value !== "string") throw new RequestError(400, "invalid_categories", "分類格式錯誤。");
    const category = value.trim();
    if (!category) continue;
    if (category.length > MAX_CATEGORY_LENGTH) {
      throw new RequestError(413, "category_too_long", "單一分類名稱過長。");
    }
    totalLength += category.length;
    if (totalLength > MAX_CATEGORY_TOTAL_LENGTH) {
      throw new RequestError(413, "categories_too_large", "分類內容總長度過長。");
    }
    categories.push(category);
  }
  return categories;
}

export function parseReceipt(raw) {
  const text = String(raw || "").replace(/^```json\s*/i, "").replace(/^```\s*/, "").replace(/```\s*$/, "").trim();
  let value;
  try { value = JSON.parse(text); } catch { throw new RequestError(502, "invalid_model_output", "AI 回傳格式錯誤，仍可能已耗用額度。"); }
  const requiredStrings = ["currency", "date", "merchant", "categoryName", "note"];
  const amount = Number(value?.amount);
  const validDate = /^\d{4}-\d{2}-\d{2}$/.test(value?.date || "") && !Number.isNaN(Date.parse(`${value.date}T00:00:00Z`));
  const validTime = value?.time === null || /^([01]\d|2[0-3]):[0-5]\d$/.test(value?.time || "");
  if (!Number.isFinite(amount) || amount < 0 || !/^[A-Z]{3}$/.test(value?.currency || "") || !validDate || !validTime ||
      requiredStrings.some(key => typeof value?.[key] !== "string") || !value.merchant.trim() || !value.note.trim()) {
    throw new RequestError(502, "invalid_model_output", "AI 回傳欄位不完整，仍可能已耗用額度。");
  }
  return {
    amount, currency: value.currency, date: value.date, time: value.time,
    merchant: value.merchant, categoryName: value.categoryName, note: value.note
  };
}

export class RequestError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
