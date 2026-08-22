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
  "Monaco": "MON", "Saudi Arabia": "SAU", "China": "CHN", "Japan": "JPN",
  "Australia": "AUS", "Canada": "CAN", "Hungary": "HUN", "Belgium": "BEL",
  "Austria": "AUT", "France": "FRA", "Germany": "GER", "Malaysia": "MAS"
}

// Approximate durations so live-state detection keeps working.
var JOLPICA_DURATION_MIN = {
  "Practice 1": 60, "Practice 2": 60, "Practice 3": 60,
  "Sprint Qualifying": 45, "Qualifying": 60, "Sprint": 60, "Race": 150
}

function shortName(sessionName) {
  return SESSION_SHORTS[sessionName] || sessionName || "?"
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
  var name = String(official || "").toUpperCase()
  name = name.replace(/^F(ORMULA|IA)?\s*1\s*/, "")
  name = name.replace(/\s*20\d\d\s*$/, "")
  name = name.replace(/\s+/g, " ").trim()
  return name || fallback || ""
}

// Compact display title: "Dutch Grand Prix" -> "Dutch GP".
// Falls back through officialName -> cleaned -> raw.
function shortGpName(meetingName, officialName) {
  var n = String(meetingName || "")
  if (!n) n = cleanOfficialName(officialName, "")
  else n = cleanOfficialName(n.replace(/grand prix/i, "GP"), "")
  return n || "Grand Prix"
}

// Parse the raw OpenF1 sessions JSON array into a normalized, sorted list.
// Each entry:
//   { startMs, endMs, name, short, type, meetingKey, meetingName,
//     location, countryName, countryCode }
function parseSessions(rawText, nowMs) {
  var data = JSON.parse(String(rawText || "[]"))
  var out = []
  for (var i = 0; i < data.length; i++) {
    var s = data[i]
    if (s.is_cancelled) continue
    if (!s.date_start) continue
    var startMs = Date.parse(s.date_start)
    var endMs = s.date_end ? Date.parse(s.date_end) : startMs + 3 * 3600 * 1000
    if (isNaN(startMs)) continue
    // Drop finished sessions (small grace window so just-ended ones linger).
    if (!isNaN(endMs) && endMs + 30 * 60 * 1000 < nowMs) continue
    out.push({
      startMs: startMs,
      endMs: isNaN(endMs) ? startMs + 3 * 3600 * 1000 : endMs,
      name: s.session_name || s.session_type || "Session",
      short: shortName(s.session_name),
      type: s.session_type || "",
      meetingKey: s.meeting_key,
      meetingName: s.meeting_name || "",
      location: s.location || "",
      circuitShort: s.circuit_short_name || "",
      countryName: s.country_name || "",
      countryCode: s.country_code || ""
    })
  }
  out.sort(function(a, b) { return a.startMs - b.startMs })
  return out
}

// Parse the raw Jolpica/Ergast current-season JSON into the same normalized
// session shape as parseSessions, so the rest of the plugin is source-agnostic.
function parseJolpica(rawText, nowMs) {
  var data = JSON.parse(String(rawText || "{}"))
  var races = (data.MRData && data.MRData.RaceTable && data.MRData.RaceTable.Races) || []
  var out = []
  var FIELD_SESSIONS = [
    ["FirstPractice", "Practice 1"],
    ["SecondPractice", "Practice 2"],
    ["ThirdPractice", "Practice 3"],
    ["SprintQualifying", "Sprint Qualifying"],
    ["Qualifying", "Qualifying"],
    ["Sprint", "Sprint"]
  ]
  for (var i = 0; i < races.length; i++) {
    var r = races[i]
    var country = r.Circuit && r.Circuit.Location ? r.Circuit.Location.country : ""
    var base = {
      meetingKey: parseInt(r.round, 10) || i,
      meetingName: r.raceName || "",
      officialName: cleanOfficialName(r.raceName, ""),
      location: r.Circuit && r.Circuit.Location ? r.Circuit.Location.locality || "" : "",
      circuitShort: r.Circuit && r.Circuit.circuitName ? r.Circuit.circuitName : "",
      countryName: country,
      countryCode: COUNTRY_TO_A3[country] || ""
    }
    var entries = []
    for (var f = 0; f < FIELD_SESSIONS.length; f++) {
      var fld = r[FIELD_SESSIONS[f][0]]
      if (fld && fld.date) entries.push([FIELD_SESSIONS[f][1], fld])
    }
    if (r.date) entries.push(["Race", { date: r.date, time: r.time }])
    for (var e = 0; e < entries.length; e++) {
      var name = entries[e][0], when = entries[e][1]
      if (!when.time) continue
      var startMs = Date.parse(when.date + "T" + when.time)
      if (isNaN(startMs)) continue
      var durMin = JOLPICA_DURATION_MIN[name] || 90
      var endMs = startMs + durMin * 60000
      if (endMs + 30 * 60 * 1000 < nowMs) continue
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
  var data = JSON.parse(String(rawText || "[]"))
  var map = {}
  for (var i = 0; i < data.length; i++) {
    var m = data[i]
    map[String(m.meeting_key)] = {
      officialName: cleanOfficialName(m.meeting_official_name, m.meeting_name),
      flagUrl: m.country_flag || ""
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
// that hasn't started yet. Sessions that already finished are skipped even
// if they linger in the list through the post-session grace window.
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

function stripTime(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}
