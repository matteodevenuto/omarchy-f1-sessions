// Helpers for fetching, parsing, and formatting OpenF1 session data.
// All functions are pure; state lives in the QML files.

var SESSION_SHORTS = {
  "Practice 1": "FP1",
  "Practice 2": "FP2",
  "Practice 3": "FP3",
  "Sprint Qualifying": "SQ",
  "Qualifying": "Q",
  "Sprint": "SPRINT",
  "Race": "RACE"
}

// Remote responses and strings are untrusted. curl enforces the byte limit
// before this code runs; these limits provide a second guard before parsing
// and keep the model/UI bounded even if a source ignores its query limit.
var MAX_RESPONSE_CHARS = 1024 * 1024
var MAX_SESSIONS = 256
var MAX_MEETINGS = 64
var MAX_RACES = 40
var MAX_TEXT_LENGTH = 96

function parseJson(rawText, fallback) {
  var raw = String(rawText || "")
  if (raw.length > MAX_RESPONSE_CHARS) throw new Error("API response is too large")
  return JSON.parse(raw || fallback)
}

// Produce short, single-line strings for all display and notification sinks.
// Strip control/format characters (including bidi overrides) and collapse
// whitespace. QML Text elements still explicitly use PlainText as defence in
// depth against AutoText treating '<...>' as rich text.
function safeText(value, fallback, maxLength) {
  var text = (typeof value === "string" || typeof value === "number")
    ? String(value) : ""
  text = text.replace(/[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g, " ")
  text = text.replace(/\s+/g, " ").trim()
  var limit = Math.max(1, Math.min(parseInt(maxLength, 10) || MAX_TEXT_LENGTH,
                                    MAX_TEXT_LENGTH))
  if (text.length > limit) text = text.slice(0, limit)
  return text || String(fallback || "")
}

function safeCode(value) {
  var code = safeText(value, "", 3).toUpperCase()
  return /^[A-Z]{3}$/.test(code) ? code : ""
}

function safeMeetingKey(value, fallback) {
  var key = String(value === undefined || value === null ? "" : value)
  return /^\d{1,12}$/.test(key) ? key : String(fallback)
}

function escapeHtml(value) {
  return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}

// ISO alpha-3 -> alpha-2 for countries on recent F1 calendars. Used to build
// emoji flags offline; anything unmapped falls back to the plain code.
var ALPHA2 = {
  AUS: "AU", CHN: "CN", JPN: "JP", BHR: "BH", SAU: "SA", MCO: "MC",
  ESP: "ES", CAN: "CA", AUT: "AT", GBR: "GB", HUN: "HU", BEL: "BE",
  NED: "NL", ITA: "IT", AZE: "AZ", SGP: "SG", USA: "US", MEX: "MX",
  BRA: "BR", QAT: "QA", UAE: "AE", FRA: "FR", GER: "DE", KOR: "KR",
  IND: "IN", RUS: "RU", TUR: "TR", ARG: "AR", POR: "PT", VNM: "VN"
}

function sessionsUrl(year) {
  return "https://api.openf1.org/v1/sessions?year=" + year
}

function meetingsUrl(year) {
  return "https://api.openf1.org/v1/meetings?year=" + year
}

// Fallback source: Jolpica (Ergast-compatible). Used automatically when
// OpenF1 is unreachable or refuses requests.
function jolpicaUrl() {
  return "https://api.jolpi.ca/ergast/f1/current.json?limit=40"
}

var COUNTRY_TO_A3 = {
  "Netherlands": "NED", "Italy": "ITA", "Spain": "ESP", "Azerbaijan": "AZE",
  "Bahrain": "BHR", "Singapore": "SGP", "United States": "USA", "USA": "USA",
  "Mexico": "MEX", "Brazil": "BRA", "Qatar": "QAT",
  "United Arab Emirates": "UAE", "UAE": "UAE", "UK": "GBR", "United Kingdom": "GBR",
  "Monaco": "MCO", "Saudi Arabia": "SAU", "China": "CHN", "Japan": "JPN",
  "Australia": "AUS", "Canada": "CAN", "Hungary": "HUN", "Belgium": "BEL",
  "Austria": "AUT", "France": "FRA", "Germany": "GER", "Malaysia": "MAS"
}

// Approximate durations so live-state detection keeps working.
var JOLPICA_DURATION_MIN = {
  "Practice 1": 60, "Practice 2": 60, "Practice 3": 60,
  "Sprint Qualifying": 45, "Qualifying": 60, "Sprint": 60, "Race": 150
}

function shortName(sessionName) {
  var name = safeText(sessionName, "", 40)
  return SESSION_SHORTS[name] || name || "?"
}

function emojiFlag(countryCode) {
  var a2 = ALPHA2[countryCode]
  if (!a2) return ""
  var out = ""
  for (var i = 0; i < a2.length; i++)
    out += String.fromCodePoint(127397 + a2.charCodeAt(i))
  return out
}

// "FORMULA 1 HEINEKEN DUTCH GRAND PRIX 2026" -> "HEINEKEN DUTCH GRAND PRIX".
function cleanOfficialName(official, fallback) {
  var name = safeText(official, "", MAX_TEXT_LENGTH).toUpperCase()
  name = name.replace(/^F(ORMULA|IA)?\s*1\s*/, "")
  name = name.replace(/\s*20\d\d\s*$/, "")
  name = name.replace(/\s+/g, " ").trim()
  return name || safeText(fallback, "", MAX_TEXT_LENGTH)
}

// Compact display title: "Dutch Grand Prix" -> "Dutch GP".
// Falls back through officialName -> cleaned -> raw.
function shortGpName(meetingName, officialName) {
  var n = safeText(meetingName, "", MAX_TEXT_LENGTH)
  if (!n) n = cleanOfficialName(officialName, "")
  else n = cleanOfficialName(n.replace(/grand prix/i, "GP"), "")
  return n || "Grand Prix"
}

// Parse the raw OpenF1 sessions JSON array into a normalized, sorted list.
// Each entry:
//   { startMs, endMs, name, short, type, meetingKey, meetingName,
//     location, countryName, countryCode }
function parseSessions(rawText, nowMs) {
  var data = parseJson(rawText, "[]")
  if (!Array.isArray(data)) throw new Error("OpenF1 sessions response is not an array")
  var out = []
  for (var i = 0; i < data.length && i < MAX_SESSIONS; i++) {
    var s = data[i]
    if (!s || typeof s !== "object" || Array.isArray(s)) continue
    if (s.is_cancelled) continue
    if (!s.date_start) continue
    var startMs = Date.parse(s.date_start)
    var endMs = s.date_end ? Date.parse(s.date_end) : startMs + 3 * 3600 * 1000
    if (isNaN(startMs)) continue
    // Finished sessions leave the schedule as soon as their reported end time
    // passes, keeping the list consistent with the next-session highlight.
    if (!isNaN(endMs) && endMs < nowMs) continue
    out.push({
      startMs: startMs,
      endMs: isNaN(endMs) ? startMs + 3 * 3600 * 1000 : endMs,
      name: safeText(s.session_name || s.session_type, "Session", 40),
      short: shortName(s.session_name),
      type: safeText(s.session_type, "", 40),
      meetingKey: safeMeetingKey(s.meeting_key, i),
      meetingName: safeText(s.meeting_name, "", MAX_TEXT_LENGTH),
      location: safeText(s.location, "", 64),
      circuitShort: safeText(s.circuit_short_name, "", MAX_TEXT_LENGTH),
      countryName: safeText(s.country_name, "", 64),
      countryCode: safeCode(s.country_code)
    })
  }
  out.sort(function(a, b) { return a.startMs - b.startMs })
  return out
}

// Parse the raw Jolpica/Ergast current-season JSON into the same normalized
// session shape as parseSessions, so the rest of the plugin is source-agnostic.
function parseJolpica(rawText, nowMs) {
  var data = parseJson(rawText, "{}")
  var races = (data.MRData && data.MRData.RaceTable && data.MRData.RaceTable.Races) || []
  if (!Array.isArray(races)) throw new Error("Jolpica races response is not an array")
  var out = []
  var FIELD_SESSIONS = [
    ["FirstPractice", "Practice 1"],
    ["SecondPractice", "Practice 2"],
    ["ThirdPractice", "Practice 3"],
    ["SprintQualifying", "Sprint Qualifying"],
    ["Qualifying", "Qualifying"],
    ["Sprint", "Sprint"]
  ]
  for (var i = 0; i < races.length && i < MAX_RACES && out.length < MAX_SESSIONS; i++) {
    var r = races[i]
    if (!r || typeof r !== "object" || Array.isArray(r)) continue
    var country = safeText(r.Circuit && r.Circuit.Location
                           ? r.Circuit.Location.country : "", "", 64)
    var base = {
      meetingKey: safeMeetingKey(r.round, i),
      meetingName: safeText(r.raceName, "", MAX_TEXT_LENGTH),
      officialName: cleanOfficialName(r.raceName, ""),
      location: safeText(r.Circuit && r.Circuit.Location
                         ? r.Circuit.Location.locality : "", "", 64),
      circuitShort: safeText(r.Circuit ? r.Circuit.circuitName : "", "", MAX_TEXT_LENGTH),
      countryName: country,
      countryCode: COUNTRY_TO_A3[country] || ""
    }
    var entries = []
    for (var f = 0; f < FIELD_SESSIONS.length; f++) {
      var fld = r[FIELD_SESSIONS[f][0]]
      if (fld && fld.date) entries.push([FIELD_SESSIONS[f][1], fld])
    }
    if (r.date) entries.push(["Race", { date: r.date, time: r.time }])
    for (var e = 0; e < entries.length && out.length < MAX_SESSIONS; e++) {
      var name = entries[e][0], when = entries[e][1]
      if (!when.time) continue
      var startMs = Date.parse(when.date + "T" + when.time)
      if (isNaN(startMs)) continue
      var durMin = JOLPICA_DURATION_MIN[name] || 90
      var endMs = startMs + durMin * 60000
      if (endMs < nowMs) continue
      out.push({
        startMs: startMs, endMs: endMs,
        name: name, short: shortName(name), type: typeOf(name),
        meetingKey: base.meetingKey, meetingName: base.meetingName,
        officialName: base.officialName, location: base.location,
        circuitShort: base.circuitShort, countryName: base.countryName,
        countryCode: base.countryCode
      })
    }
  }
  out.sort(function(a, b) { return a.startMs - b.startMs })
  return out
}

function typeOf(sessionName) {
  if (/Practice/.test(sessionName)) return "Practice"
  if (/Qualifying/i.test(sessionName)) return "Qualifying"
  return "Race"
}

// Parse the raw OpenF1 meetings JSON into { [meeting_key]: {officialName} }.
function parseMeetings(rawText) {
  var data = parseJson(rawText, "[]")
  if (!Array.isArray(data)) throw new Error("OpenF1 meetings response is not an array")
  var map = {}
  for (var i = 0; i < data.length && i < MAX_MEETINGS; i++) {
    var m = data[i]
    if (!m || typeof m !== "object" || Array.isArray(m)) continue
    var key = safeMeetingKey(m.meeting_key, i)
    map[key] = {
      officialName: cleanOfficialName(m.meeting_official_name, m.meeting_name)
    }
  }
  return map
}

// Copy meeting details onto each session (returns a new list).
function attachMeetings(list, map) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    var m = map[String(s.meetingKey)]
    out.push({
      startMs: s.startMs, endMs: s.endMs,
      name: s.name, short: s.short, type: s.type,
      meetingKey: s.meetingKey, meetingName: s.meetingName,
      location: s.location, circuitShort: s.circuitShort,
      countryName: s.countryName, countryCode: s.countryCode,
      officialName: m ? m.officialName : s.meetingName
    })
  }
  return out
}

// Group a sorted session list into race weekends keyed by meeting.
function groupByMeeting(list) {
  var groups = []
  var byKey = {}
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    var key = String(s.meetingKey)
    if (!(key in byKey)) {
      byKey[key] = groups.length
      groups.push({
        key: key,
        officialName: s.officialName,
        meetingName: s.meetingName,
        location: s.location,
        circuitShort: s.circuitShort,
        countryCode: s.countryCode,
        sessions: []
      })
    }
    groups[byKey[key]].sessions.push(s)
  }
  return groups
}

// Cluster one weekend's sessions into local calendar days.
// -> [{ key, weekday, dateLabel, label, tabLabel, sessions }]
function groupDays(list, locale) {
  var days = []
  var byDay = {}
  for (var i = 0; i < list.length; i++) {
    var d = new Date(list[i].startMs)
    var key = d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
    if (!(key in byDay)) {
      byDay[key] = days.length
      days.push({
        key: key,
        weekday: Qt.formatDate(d, "dddd"),
        dateLabel: Qt.formatDate(d, "d MMMM").toUpperCase(),
        label: (Qt.formatDate(d, "dddd") + " · " + Qt.formatDate(d, "d MMMM")).toUpperCase(),
        tabLabel: Qt.formatDate(d, "ddd d").toUpperCase(),
        sessions: []
      })
    }
    days[byDay[key]].sessions.push(list[i])
  }
  return days
}

// Index of the session to highlight: the first live one, else the next one
// that hasn't started yet. Sessions that already finished are skipped.
function focusIndex(list, nowMs) {
  for (var i = 0; i < list.length; i++)
    if (nowMs >= list[i].startMs && nowMs <= list[i].endMs) return i
  for (var i = 0; i < list.length; i++)
    if (nowMs < list[i].startMs) return i
  return -1
}

function isLive(session, nowMs) {
  return !!session && nowMs >= session.startMs && nowMs <= session.endMs
}

// Compact human countdown: "LIVE", "45m", "2h 05m", "3d 4h", "12d".
function countdown(msUntilStart, live) {
  if (live) return "LIVE"
  if (msUntilStart <= 0) return "LIVE"
  var minutes = Math.floor(msUntilStart / 60000)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 48) {
    var rem = minutes % 60
    return hours + "h" + (rem > 0 && hours < 24 ? " " + pad2(rem) + "m" : "")
  }
  var days = Math.floor(hours / 24)
  var remH = hours % 24
  return days + "d" + (remH > 0 ? " " + remH + "h" : "")
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

function formatTime(d, use24h) {
  return Qt.formatTime(d, use24h ? "HH:mm" : "h:mm ap")
}

// Mode-aware bar labels. Modes:
//   next    - "Q LIVE", "SPRINT 12:00", "NED FP1 Fri", "ITA Q 12d"
//   time    - always the clock time: "SPRINT 12:00", "Sat 15:00"
//   weekend - meeting-centric: "NED GP LIVE", "NED GP Fri", "NED GP 12d"
//   logo    - "" (icon only)
function barLabelForMode(mode, session, nowMs, use24h, locale) {
  if (mode === "logo" || !session) return ""
  var live = isLive(session, nowMs)
  if (live) return mode === "weekend" ? session.countryCode + " GP LIVE" : session.short + " LIVE"

  var d = new Date(session.startMs)
  var today = new Date(nowMs)
  var sameDay = d.toDateString() === today.toDateString()
  var days = Math.floor((stripTime(d) - stripTime(today)) / 86400000)

  if (mode === "time")
    return sameDay ? session.short + " " + formatTime(d, use24h)
                   : Qt.formatDate(d, "ddd") + " " + formatTime(d, use24h)

  if (mode === "weekend")
    return session.countryCode + " GP" + (days < 7 ? " " + Qt.formatDate(d, "ddd") : " " + days + "d")

  // "next"
  if (sameDay) return session.short + " " + formatTime(d, use24h)
  if (days >= 0 && days < 7)
    return session.countryCode + " " + session.short + " " + Qt.formatDate(d, "ddd")
  return session.countryCode + " " + days + "d"
}

// Longer one-line summary used for tooltips and panel headers.
function longSummary(session, nowMs, use24h, locale) {
  if (!session) return ""
  var d = new Date(session.startMs)
  var when = Qt.formatDate(d, "ddd d MMM") + " · " + formatTime(d, use24h)
  if (isLive(session, nowMs)) return session.name + " · LIVE"
  return session.name + " · " + when + " · in " + countdown(session.startMs - nowMs, false)
}

// WidgetButton tooltips may share a rich-text-capable sink. Escape the whole
// already-normalized summary before handing it to that component.
function tooltipSummary(session, nowMs, use24h) {
  return escapeHtml(longSummary(session, nowMs, use24h))
}

function stripTime(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}
