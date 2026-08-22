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
  property int focusIdx: -1
  property bool loaded: false
  property bool fetching: false
  property string lastUpdated: ""
  readonly property var focusSession: (focusIdx >= 0 && focusIdx < sessions.length) ? sessions[focusIdx] : null

  readonly property int refreshMinutes: Math.max(10, parseInt(setting("refreshMinutes", 60), 10) || 60)
  readonly property int daysAhead: Math.max(1, parseInt(setting("daysAhead", 21), 10) || 21)
  readonly property bool hideWhenQuiet: setting("hideWhenQuiet", false) === true
  readonly property bool use24h: setting("use24h", true) !== false
  readonly property bool notificationsOn: setting("notifications", true) !== false
  readonly property string sourceLabel: useFallback ? "Jolpica" : "OpenF1"

  function toggleNotifications() {
    var next = !root.notificationsOn
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.notifications = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    // Turning notifications on should arm an alert for an imminent session.
    if (next) {
      root.notifiedKeys = {}
      Quickshell.execDetached(["omarchy-notification-send",
        "F1 alerts on · you'll get a ping 5 min before each session starts"])
    }
  }

  // One-shot alerts fired NOTIFY_LEAD minutes before each session start.
  readonly property int notifyLeadMin: 5
  property var notifiedKeys: ({})

  function notifyKey(s) {
    return s.meetingKey + "-" + s.startMs + "-" + s.name
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
      var key = notifyKey(s)
      if (root.notifiedKeys[key]) continue
      root.notifiedKeys[key] = true
      var d = new Date(s.startMs)
      Quickshell.execDetached(["omarchy-notification-send",
        "F1 · " + Model.shortGpName(s.meetingName, s.officialName) + ": "
        + s.name + " starts " + Model.formatTime(d, root.use24h)])
    }
    pruneNotifiedKeys(now)
  }

  // Bar display mode, cycled by right-click and persisted in shell.json.
  readonly property var displayModes: ["next", "time", "weekend", "logo"]
  readonly property string displayMode: {
    var v = setting("displayMode", "next")
    return displayModes.indexOf(v) >= 0 ? v : "next"
  }

  function cycleDisplayMode() {
    var idx = displayModes.indexOf(displayMode)
    var next = displayModes[(idx + 1) % displayModes.length]
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.displayMode = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
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
      if (merged[i].startMs <= cutoff || Model.isLive(merged[i], now)) out.push(merged[i])
    return out
  }

  // ---- Fetching ----------------------------------------------------------
  function refresh() {
    if (root.fetching) return
    root.fetching = true
    if (root.useFallback) {
      sessionsProc.command = ["curl", "-fsS", "--max-time", "8", Model.jolpicaUrl()]
      sessionsProc.running = true
    } else {
      fetchOpenF1(new Date().getFullYear())
    }
  }

  function fetchOpenF1(year) {
    sessionsProc.year = year
    sessionsProc.command = ["curl", "-fsS", "--max-time", "8", Model.sessionsUrl(year)]
    sessionsProc.running = true
    meetingsProc.command = ["curl", "-fsS", "--max-time", "8", Model.meetingsUrl(year)]
    meetingsProc.running = true
  }

  Process {
    id: sessionsProc
    property int year: new Date().getFullYear()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var parsed = null
        if (raw !== "") {
          try {
            parsed = root.useFallback
              ? Model.parseJolpica(raw, Date.now())
              : Model.parseSessions(raw, Date.now())
          } catch (e) { parsed = null }
        }
        if (parsed && parsed.length > 0) {
          root.sessions = parsed
          root.loaded = true
          root.lastUpdated = Qt.formatDateTime(new Date(), "HH:mm")
          root.recomputeFocus()
          root.fetching = false
          return
        }
        // OpenF1 failed or went empty: switch to Jolpica once and retry.
        if (!root.useFallback) {
          root.useFallback = true
          root.fetching = false
          Qt.callLater(root.refresh)
          return
        }
        root.fetching = false
      }
    }
  }

  Process {
    id: meetingsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.meetingsMap = Model.parseMeetings(text)
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
    return "Next: " + Model.longSummary(focusSession, nowMs, use24h)
  }

  visible: !hideWhenQuiet || !!focusSession

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
    if ("anchorItem" in target) target.anchorItem = button
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
        color: button.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    // Size the slot to the custom content instead of the hidden label.
    fixedWidth: Math.max(12, contentRow.implicitWidth + scaledHorizontalMargin * 2)
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
  }
}
