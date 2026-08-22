const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadModel() {
  const context = {
    Qt: {
      formatDate: () => "DATE",
      formatTime: () => "TIME"
    }
  }
  vm.createContext(context)
  const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  vm.runInContext(source, context, { filename: "Model.js" })
  return context
}

const Model = loadModel()
const now = Date.parse("2026-08-22T12:00:00Z")

function openF1Session(overrides = {}) {
  return {
    date_start: "2026-08-23T12:00:00Z",
    date_end: "2026-08-23T14:00:00Z",
    session_name: "Race",
    session_type: "Race",
    meeting_key: 1234,
    meeting_name: "Dutch Grand Prix",
    location: "Zandvoort",
    country_name: "Netherlands",
    country_code: "NED",
    ...overrides
  }
}

test("normalizes OpenF1 sessions", () => {
  const sessions = Model.parseSessions(JSON.stringify([openF1Session()]), now)
  assert.equal(sessions.length, 1)
  assert.equal(sessions[0].short, "RACE")
  assert.equal(sessions[0].countryCode, "NED")
})

test("removes sessions immediately after their end time", () => {
  const ended = openF1Session({
    date_start: "2026-08-22T10:00:00Z",
    date_end: "2026-08-22T11:59:59Z"
  })
  assert.equal(Model.parseSessions(JSON.stringify([ended]), now).length, 0)
})

test("bounds items and remote strings", () => {
  const input = Array.from({ length: 300 }, (_, index) => openF1Session({
    meeting_key: index,
    session_name: "<b>Race</b>\n\u202e" + "x".repeat(100),
    location: "x".repeat(200)
  }))
  const sessions = Model.parseSessions(JSON.stringify(input), now)
  assert.equal(sessions.length, Model.MAX_SESSIONS)
  assert.ok(sessions[0].name.length <= 40)
  assert.ok(sessions[0].location.length <= 64)
  assert.equal(/[\n\u202e]/.test(sessions[0].name), false)
})

test("rejects oversized and incorrectly shaped responses", () => {
  assert.throws(() => Model.parseSessions(" ".repeat(Model.MAX_RESPONSE_CHARS + 1), now))
  assert.throws(() => Model.parseSessions("{}", now), /not an array/)
  assert.throws(() => Model.parseMeetings("{}"), /not an array/)
})

test("rejects unsafe meeting keys and escapes tooltip markup", () => {
  const sessions = Model.parseSessions(JSON.stringify([
    openF1Session({ meeting_key: "__proto__", session_name: "<b>Race</b>" })
  ]), now)
  assert.notEqual(sessions[0].meetingKey, "__proto__")
  assert.equal(Model.tooltipSummary(sessions[0], now, true).includes("<b>"), false)
})

test("normalizes Jolpica and bounds races", () => {
  const race = {
    round: "1",
    raceName: "Australian Grand Prix",
    Circuit: {
      circuitName: "Albert Park Grand Prix Circuit",
      Location: { locality: "Melbourne", country: "Australia" }
    },
    date: "2026-08-23",
    time: "12:00:00Z"
  }
  const races = Array.from({ length: 60 }, (_, index) => ({ ...race, round: String(index + 1) }))
  const payload = JSON.stringify({ MRData: { RaceTable: { Races: races } } })
  const sessions = Model.parseJolpica(payload, now)
  assert.equal(sessions.length, Model.MAX_RACES)
  assert.equal(sessions[0].countryCode, "AUS")
})

test("bounds and sanitizes meeting records", () => {
  const meetings = Array.from({ length: 100 }, (_, index) => ({
    meeting_key: index,
    meeting_official_name: "FORMULA 1 <b>TEST</b> GRAND PRIX 2026\n"
  }))
  const parsed = Model.parseMeetings(JSON.stringify(meetings))
  assert.equal(Object.keys(parsed).length, Model.MAX_MEETINGS)
  assert.equal(parsed["0"].officialName.includes("\n"), false)
})
