import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "matteodevenuto.f1-sessions"

  // ---- State -------------------------------------------------------------
  property var sessions: []
  property var meetingsMap: ({})
  property bool useFallback: false
  property string fetchSource: "openf1"
  property int scheduleYear: 0
  property int focusIdx: -1
  property bool loaded: false
  property bool fetching: false
  property bool usingCache: false
  property string fetchError: ""
  property string lastUpdated: ""
  property bool cacheDirReady: false
  readonly property var focusSession: (focusIdx >= 0 && focusIdx < sessions.length) ? sessions[focusIdx] : null

  readonly property int refreshMinutes: Math.min(360, Math.max(10, parseInt(setting("refreshMinutes", 60), 10) || 60))
  readonly property int daysAhead: Math.min(60, Math.max(1, parseInt(setting("daysAhead", 21), 10) || 21))
  readonly property bool hideWhenQuiet: setting("hideWhenQuiet", false) === true
  readonly property bool use24h: setting("use24h", true) !== false
  readonly property bool notificationsOn: setting("notifications", true) !== false
  readonly property bool notificationSoundOn: setting("notificationSound", true) !== false
  readonly property string notificationSessions: {
    var value = String(setting("notificationSessions", "all"))
    return ["all", "competitive", "race"].indexOf(value) >= 0 ? value : "all"
  }
  readonly property string sourceLabel: useFallback ? "Jolpica" : "OpenF1"
  readonly property int maxResponseBytes: 1024 * 1024
  readonly property string apiUserAgent: "omarchy-f1-sessions/0.3.0"
  readonly property url notificationSoundUrl: Qt.resolvedUrl("assets/radio-alert.wav")
  readonly property string cacheRoot: {
    var xdg = Quickshell.env("XDG_CACHE_HOME")
    if (xdg && xdg.length > 0) return xdg
    var home = Quickshell.env("HOME")
    return home && home.length > 0 ? home + "/.cache" : "/tmp"
  }
  readonly property string cacheDir: cacheRoot + "/omarchy-f1-sessions"
  readonly property string cachePath: cacheDir + "/schedule.json"

  // Persist a complete settings entry. Widgets normally live directly in a
  // bar section, but container widgets may host them inside their own
  // `widgets` setting. In that case updateEntryInline cannot see the nested
  // entry, so update the host instead.
  function persistSettings(entry) {
    root.settings = entry

    var shell = root.bar ? root.bar.shell : null
    if (shell && typeof shell.persistShellConfig === "function" && shell.shellConfig) {
      var config = JSON.parse(JSON.stringify(shell.shellConfig))
      var layout = config.bar ? config.bar.layout : null
      var sections = ["left", "center", "right"]
      for (var s = 0; layout && s < sections.length; s++) {
        var slots = layout[sections[s]] || []
        for (var i = 0; i < slots.length; i++) {
          var widgets = slots[i] && slots[i].widgets
          if (!Array.isArray(widgets)) continue
          for (var j = 0; j < widgets.length; j++) {
            var hosted = widgets[j] && widgets[j].entry
            if (hosted && String(hosted.id || "") === root.moduleName) {
              widgets[j].entry = entry
              shell.persistShellConfig(config)
              return
            }
          }
        }
      }
    }

    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline(root.moduleName, entry)
  }

  function playNotificationSound() {
    if (!root.notificationSoundOn) return
    var soundPath = root.notificationSoundUrl.toString().replace(/^file:\/\//, "")
    Quickshell.execDetached(["pw-play", soundPath])
  }

  function toggleNotifications() {
    var next = !root.notificationsOn
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.notifications = next
    root.persistSettings(entry)
    // Turning notifications on should arm an alert for an imminent session.
    if (next) {
      root.notifiedKeys = {}
      Quickshell.execDetached(["omarchy-notification-send",
        "F1 alerts on · you'll get a ping 5 min before each session starts"])
      root.playNotificationSound()
    }
  }

  function toggleNotificationSound() {
    var next = !root.notificationSoundOn
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.notificationSound = next
    root.persistSettings(entry)
    if (next) Qt.callLater(root.playNotificationSound)
  }

  function cycleAlertMode() {
    var wasOff = !root.notificationsOn
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    if (wasOff) {
      entry.notifications = true
      entry.notificationSound = true
    } else if (root.notificationSoundOn) {
      entry.notifications = true
      entry.notificationSound = false
    } else {
      entry.notifications = false
      entry.notificationSound = false
    }
    root.persistSettings(entry)
    if (wasOff) {
      root.notifiedKeys = {}
      var scope = root.notificationSessions === "race" ? "races and sprints"
        : (root.notificationSessions === "competitive" ? "competitive sessions" : "all sessions")
      Quickshell.execDetached(["omarchy-notification-send",
        "F1 alerts on · sound on · 5 min before " + scope])
      Qt.callLater(root.playNotificationSound)
    }
  }

  function cycleNotificationSessions() {
    var modes = ["all", "competitive", "race"]
    var next = modes[(modes.indexOf(root.notificationSessions) + 1) % modes.length]
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.notificationSessions = next
    root.persistSettings(entry)
  }

  // One-shot alerts fired NOTIFY_LEAD minutes before each session start.
  readonly property int notifyLeadMin: 5
  property var notifiedKeys: ({})

  function notifyKey(s) {
    return String(s.meetingKey + "-" + s.startMs).replace(/[^A-Za-z0-9._-]/g, "_")
  }

  function shouldNotify(s) {
    return Model.shouldNotifySession(s, root.notificationSessions)
  }

  function sendSessionAlert(s) {
    var d = new Date(s.startMs)
    var message = "F1 · " + Model.shortGpName(s.meetingName, s.officialName) + ": "
      + s.name + " starts " + Model.formatTime(d, root.use24h)
    var soundPath = root.notificationSoundUrl.toString().replace(/^file:\/\//, "")
    // Atomic marker creation makes delivery singleton across every monitor
    // instance and across shell restarts in the same login session.
    var script = "runtime=${XDG_RUNTIME_DIR:-/tmp}; dir=\"$runtime/omarchy-f1-sessions-alerts\"; "
      + "mkdir -p \"$dir\"; marker=\"$dir/$1\"; "
      + "(set -o noclobber; : > \"$marker\") 2>/dev/null || exit 0; "
      + "omarchy-notification-send \"$2\"; "
      + "if [ \"$3\" = 1 ]; then pw-play \"$4\"; fi"
    Quickshell.execDetached(["bash", "-c", script, "f1-alert", notifyKey(s), message,
                             root.notificationSoundOn ? "1" : "0", soundPath])
  }

  function pruneNotifiedKeys(nowMs) {
    var next = {}
    for (var k in root.notifiedKeys) {
      var parts = k.split("-")
      var startMs = parseInt(parts[1], 10)
      if (!isNaN(startMs) && startMs > nowMs - 3600000) next[k] = true
    }
    root.notifiedKeys = next
  }

  function checkNotifications() {
    if (!root.notificationsOn || !root.loaded || root.sessions.length === 0) return
    var now = Date.now()
    for (var i = 0; i < root.sessions.length; i++) {
      var s = root.sessions[i]
      var untilStart = s.startMs - now
      if (untilStart <= 0 || untilStart > root.notifyLeadMin * 60000) continue
      if (!root.shouldNotify(s)) continue
      var key = notifyKey(s)
      if (root.notifiedKeys[key]) continue
      root.notifiedKeys[key] = true
      root.sendSessionAlert(s)
    }
    pruneNotifiedKeys(now)
  }

  // Bar display mode, cycled by right-click and persisted in shell.json.
  readonly property var displayModes: ["next", "time", "weekend", "icon", "logo"]
  readonly property string displayMode: {
    var v = setting("displayMode", "icon")
    return displayModes.indexOf(v) >= 0 ? v : "icon"
  }

  function cycleDisplayMode() {
    var idx = displayModes.indexOf(displayMode)
    var next = displayModes[(idx + 1) % displayModes.length]
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.displayMode = next
    root.persistSettings(entry)
  }

  // Ticking clock so labels/countdowns update between fetches. Also watches
  // for timezone changes (system or manual): formatted local times elsewhere
  // are computed once per render, so a TZ change rebuilds the data arrays to
  // force every delegate to re-render with the new offset.
  property real nowMs: Date.now()
  property int lastTzOffset: new Date().getTimezoneOffset()
  readonly property int tzOffsetMinutes: lastTzOffset

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      var cur = new Date().getTimezoneOffset()
      if (cur !== root.lastTzOffset) {
        root.lastTzOffset = cur
        // New array identities make every downstream binding and Repeater
        // rebuild, so all times re-render in the fresh timezone.
        root.sessions = root.sessions.slice(0)
        root.meetingsMap = Object.assign({}, root.meetingsMap)
      }
      root.recomputeFocus()
      root.checkNotifications()
    }
  }

  function recomputeFocus() {
    focusIdx = Model.focusIndex(sessions, Date.now())
  }

  // Sessions merged with meeting details, trimmed to the display horizon.
  function visibleSessions() {
    var now = Date.now()
    var cutoff = now + root.daysAhead * 86400000
    var merged = Model.attachMeetings(sessions, meetingsMap)
    var out = []
    for (var i = 0; i < merged.length; i++)
      if (merged[i].endMs > now && (merged[i].startMs <= cutoff || Model.isLive(merged[i], now)))
        out.push(merged[i])
    return out
  }

  function saveCache() {
    if (!root.cacheDirReady || root.sessions.length === 0) return
    var payload = {
      version: 1,
      savedAt: Date.now(),
      sessions: root.sessions,
      meetingsMap: root.meetingsMap,
      source: root.fetchSource
    }
    cacheFile.setText(JSON.stringify(payload))
  }

  function loadCache(raw) {
    try {
      if (root.loaded && !root.usingCache) return
      var payload = JSON.parse(String(raw || ""))
      if (!payload || payload.version !== 1 || !Array.isArray(payload.sessions)) return
      var cached = []
      var now = Date.now()
      for (var i = 0; i < payload.sessions.length; i++) {
        var s = payload.sessions[i]
        if (s && Number(s.endMs) > now) cached.push(s)
      }
      if (cached.length === 0) return
      root.sessions = cached
      root.meetingsMap = payload.meetingsMap && typeof payload.meetingsMap === "object"
        ? payload.meetingsMap : {}
      root.useFallback = payload.source === "jolpica"
      root.fetchSource = root.useFallback ? "jolpica" : "openf1"
      root.loaded = true
      root.usingCache = true
      root.lastUpdated = payload.savedAt
        ? Qt.formatDateTime(new Date(payload.savedAt), "HH:mm") : "cached"
      root.recomputeFocus()
    } catch (e) {}
  }

  // ---- Fetching ----------------------------------------------------------
  function refresh() {
    if (root.fetching) return
    root.fetching = true
    root.fetchError = ""
    root.fetchSource = "openf1"
    fetchOpenF1(new Date().getFullYear())
  }

  function fetchOpenF1(year) {
    sessionsProc.year = year
    sessionsProc.sourceName = "openf1"
    sessionsProc.command = ["curl", "-fsS", "--max-time", "8", "--user-agent",
                            root.apiUserAgent, "--max-filesize",
                            String(root.maxResponseBytes), Model.sessionsUrl(year)]
    sessionsProc.running = true
  }

  function fetchJolpica() {
    root.fetchSource = "jolpica"
    sessionsProc.sourceName = "jolpica"
    sessionsProc.command = ["curl", "-fsS", "--max-time", "8", "--user-agent",
                            root.apiUserAgent, "--max-filesize",
                            String(root.maxResponseBytes), Model.jolpicaUrl()]
    sessionsProc.running = true
  }

  function fetchMeetings(year) {
    meetingsProc.year = year
    meetingsProc.command = ["curl", "-fsS", "--max-time", "8", "--user-agent",
                            root.apiUserAgent, "--max-filesize",
                            String(root.maxResponseBytes), Model.meetingsUrl(year)]
    meetingsProc.running = true
  }

  Process {
    id: sessionsProc
    property int year: new Date().getFullYear()
    property string sourceName: "openf1"
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var parsed = null
        if (raw !== "") {
          try {
            parsed = sessionsProc.sourceName === "jolpica"
              ? Model.parseJolpica(raw, Date.now())
              : Model.parseSessions(raw, Date.now())
          } catch (e) { parsed = null }
        }
        if (parsed && parsed.length > 0) {
          root.fetchSource = sessionsProc.sourceName
          root.useFallback = sessionsProc.sourceName === "jolpica"
          root.scheduleYear = root.useFallback ? 0 : sessionsProc.year
          if (root.useFallback) root.meetingsMap = {}
          else root.fetchMeetings(root.scheduleYear)
          root.sessions = parsed
          root.loaded = true
          root.usingCache = false
          root.fetchError = ""
          root.lastUpdated = Qt.formatDateTime(new Date(), "HH:mm")
          root.recomputeFocus()
          root.fetching = false
          root.saveCache()
          return
        }
        // Once this season has no usable sessions, try the next calendar
        // automatically. Only fall back after both OpenF1 requests fail.
        if (sessionsProc.sourceName === "openf1") {
          var currentYear = new Date().getFullYear()
          if (sessionsProc.year === currentYear) {
            Qt.callLater(function() { root.fetchOpenF1(currentYear + 1) })
            return
          }
          Qt.callLater(root.fetchJolpica)
          return
        }
        root.fetching = false
        root.fetchError = root.loaded
          ? "Update failed · showing cached schedule" : "Unable to fetch schedule"
      }
    }
  }

  Process {
    id: meetingsProc
    property int year: new Date().getFullYear()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (meetingsProc.year !== root.scheduleYear) return
        try {
          root.meetingsMap = Model.parseMeetings(text)
          root.saveCache()
        } catch (e) {}
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: ensureCacheDir
    command: ["mkdir", "-p", root.cacheDir]
    onExited: function(exitCode) {
      root.cacheDirReady = exitCode === 0
      if (root.cacheDirReady) cacheFile.reload()
    }
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadCache(text())
  }

  Component.onCompleted: ensureCacheDir.running = true

  // Bootstrap retries while the first load hasn't succeeded yet (e.g. shell
  // starts before the network is up, or the primary source is down).
  Timer {
    interval: 20000
    running: true
    repeat: true
    onTriggered: if (!root.loaded && !root.fetching) root.refresh()
  }

  // ---- Bar chrome --------------------------------------------------------
  readonly property string label: {
    if (!loaded) return "…"
    return Model.barLabelForMode(displayMode, focusSession, nowMs, use24h)
  }
  readonly property string tooltip: {
    if (!focusSession) return loaded ? "No upcoming F1 sessions" : "Fetching F1 schedule…"
    return "Next: " + Model.tooltipSummary(focusSession, nowMs, use24h)
  }

  visible: !hideWhenQuiet || !!focusSession

  implicitWidth: root.displayMode === "icon" ? iconButton.implicitWidth : button.implicitWidth
  implicitHeight: root.displayMode === "icon" ? iconButton.implicitHeight : button.implicitHeight

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root.displayMode === "icon" ? iconButton : button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    visible: root.displayMode !== "icon"
    bar: root.bar
    // Custom content below paints the F1 logo + label; a single space keeps
    // the button's own visibility logic happy.
    text: " "
    labelVisible: false
    keepSpace: true
    tooltipText: root.tooltip + (root.vertical ? "" : "\nRight-click: change display")

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
      else if (buttonCode === Qt.RightButton) root.cycleDisplayMode()
      else root.refresh()
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Image {
        id: logo
        anchors.verticalCenter: parent.verticalCenter
        source: Qt.resolvedUrl("f1-logo.svg")
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectFit
        height: Style.space(9)
        width: height * 4
        mipmap: true
      }

      // Fallback wordmark while/if the bundled SVG fails to load.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !logo.visible
        text: "F1"
        color: "#E10600"
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        font.italic: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && root.label !== ""
        text: root.label
        textFormat: Text.PlainText
        color: button.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    // Size the slot to the custom content instead of the hidden label.
    fixedWidth: Math.max(12, contentRow.implicitWidth + scaledHorizontalMargin * 2)
  }

  // Match the Agents plugin exactly in compact mode.
  BarIconButton {
    id: iconButton
    anchors.fill: parent
    visible: root.displayMode === "icon"
    bar: root.bar
    text: "\uf11e"
    tooltipText: root.tooltip + (root.vertical ? "" : "\nRight-click: change display")

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
      else if (buttonCode === Qt.RightButton) root.cycleDisplayMode()
      else root.refresh()
    }
  }

  IpcHandler {
    target: "matteodevenuto.f1-sessions"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
    function cycleDisplay(): void { root.cycleDisplayMode() }
    function status(): string {
      return JSON.stringify({
        loaded: root.loaded,
        fetching: root.fetching,
        usingCache: root.usingCache,
        error: root.fetchError,
        source: root.sourceLabel,
        sessions: root.sessions.length,
        notificationSessions: root.notificationSessions
      })
    }
  }
}
