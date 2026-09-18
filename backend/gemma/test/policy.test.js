import test from "node:test";
import assert from "node:assert/strict";
import { cappedPositiveInteger, parseInvitationCodes, parseReceipt, positiveInteger, RequestError, utcDay, validateAnalyzeInput } from "../src/policy.js";

const validAnalyzeBody = (overrides = {}) => ({
  requestId: "123e4567-e89b-12d3-a456-426614174000",
  imageBase64: "AA==",
  mimeType: "image/jpeg",
  userNote: "午餐",
  categories: ["餐飲"],
  ...overrides
});

test("configuration values fail closed to defaults and hard maxima", () => {
  assert.equal(positiveInteger("50", 10), 50);
  assert.equal(positiveInteger("0", 10), 10);
  assert.equal(positiveInteger("oops", 10), 10);
  assert.equal(cappedPositiveInteger("9999", 50, 50), 50);
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

test("analyze input bounds images, user note and categories", () => {
  const value = validateAnalyzeInput(validAnalyzeBody({ userNote: "x".repeat(600), categories: ["餐飲", " 交通 ", ""] }));
  assert.equal(value.userNote.length, 500);
  assert.deepEqual(value.categories, ["餐飲", "交通"]);
  assert.throws(() => validateAnalyzeInput({ requestId: "bad", imageBase64: "AA==" }), RequestError);
  assert.throws(() => validateAnalyzeInput(validAnalyzeBody({ categories: ["x".repeat(81)] })), /單一分類名稱過長/);
  assert.throws(() => validateAnalyzeInput(validAnalyzeBody({ categories: Array.from({ length: 51 }, () => "x".repeat(80)) })), /總長度過長/);
  assert.throws(() => validateAnalyzeInput(validAnalyzeBody({ categories: Array.from({ length: 101 }, () => "x") })), /分類數量過多/);
});
