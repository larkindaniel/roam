import assert from "node:assert/strict";
import { test } from "node:test";
import { issueTitle, scrub } from "./scrub.mjs";

test("emails are taken out", () => {
  assert.equal(scrub("email me at kieran@roam.test please"), "email me at [email] please");
  assert.equal(scrub("first.last+beta@mail.co.uk"), "[email]");
});

test("phone numbers are taken out, in the usual shapes", () => {
  assert.equal(scrub("call +1 (519) 555-0123"), "call [number]");
  assert.equal(scrub("519-555-0123"), "[number]");
  assert.equal(scrub("5195550123"), "[number]");
  assert.equal(scrub("+44 20 7946 0958"), "[number]");
});

test("ids are taken out, upper or lower case", () => {
  assert.equal(scrub("member 00000013-0000-4000-8000-000000000001"), "member [id]");
  assert.equal(scrub("session 0FAD549F-BB3E-4AD5-8E6C-AFB794E7DBFA"), "session [id]");
});

test("dates, times, coordinates, sizes and scores stay", () => {
  const kept = "on 2026-11-15 at 20:46:15, x=145, y=183, 36288 bytes, rated 8.4, 3 photos";
  assert.equal(scrub(kept), kept);
});

test("place names and ordinary words stay", () => {
  assert.equal(scrub("The Lisbon city page froze after tapping Save"), "The Lisbon city page froze after tapping Save");
});

test("the title is the first line, scrubbed and at most 80 characters", () => {
  assert.equal(issueTitle("Map froze\nmore detail here"), "Map froze");
  assert.equal(issueTitle("ping kieran@roam.test, it broke"), "ping [email], it broke");
  assert.equal(issueTitle("x".repeat(120)).length, 80);
  assert.ok(!issueTitle("Map froze").startsWith("Bug:"));
});
