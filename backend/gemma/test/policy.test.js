import test from "node:test";
import assert from "node:assert/strict";
import { parseInvitationCodes, parseReceipt, positiveInteger, RequestError, utcDay, validateAnalyzeInput } from "../src/policy.js";

test("configuration values fail closed to defaults", () => {
  assert.equal(positiveInteger("50", 10), 50);
  assert.equal(positiveInteger("0", 10), 10);
  assert.equal(positiveInteger("oops", 10), 10);
  assert.deepEqual(parseInvitationCodes('["1234567890abcdef"]'), ["1234567890abcdef"]);
  assert.throws(() => parseInvitationCodes('["short"]'));
});

test("UTC quota day is deterministic", () => {
  assert.equal(utcDay(new Date("2026-09-18T23:59:59Z")), "2026-09-18");
});

test("receipt parser accepts strict values and markdown fences", () => {
  const receipt = parseReceipt('```json\n{"amount":12.5,"currency":"HKD","date":"2026-09-18","time":null,"merchant":"商店","categoryName":"餐飲","note":"午餐"}\n```');
  assert.equal(receipt.amount, 12.5);
  assert.equal(receipt.note, "午餐");
});

test("receipt parser rejects null note", () => {
  assert.throws(() => parseReceipt('{"amount":12.5,"currency":"HKD","date":"2026-09-18","time":null,"merchant":"商店","categoryName":"餐飲","note":null}'), RequestError);
});

test("receipt parser rejects negative amounts and invalid dates", () => {
  assert.throws(() => parseReceipt('{"amount":-1,"currency":"HKD","date":"2026-09-18","time":null,"merchant":"商店","categoryName":"餐飲","note":"午餐"}'), RequestError);
  assert.throws(() => parseReceipt('{"amount":1,"currency":"HKD","date":"not-a-date","time":null,"merchant":"商店","categoryName":"餐飲","note":"午餐"}'), RequestError);
});

test("analyze input bounds images and categories", () => {
  const value = validateAnalyzeInput({
    requestId: "123e4567-e89b-12d3-a456-426614174000", imageBase64: "AA==", mimeType: "image/jpeg",
    userNote: "x".repeat(600), categories: ["餐飲", 4, ""]
  });
  assert.equal(value.userNote.length, 500);
  assert.deepEqual(value.categories, ["餐飲"]);
  assert.throws(() => validateAnalyzeInput({ requestId: "bad", imageBase64: "AA==" }), RequestError);
});
