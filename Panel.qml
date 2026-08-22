import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "matteodevenuto.f1-sessions"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Mirrored from the host widget so the panel renders the same data.
  readonly property var sessions: hostWidget ? hostWidget.visibleSessions() : []
  readonly property real nowMs: hostWidget ? hostWidget.nowMs : Date.now()
  readonly property int tzOffsetMinutes: hostWidget ? hostWidget.tzOffsetMinutes : 0
  readonly property bool use24h: hostWidget ? hostWidget.use24h : true
  readonly property bool loaded: hostWidget ? hostWidget.loaded : false
  readonly property string lastUpdated: hostWidget ? hostWidget.lastUpdated : ""
  readonly property int focusIdx: Model.focusIndex(sessions, nowMs)
  readonly property var focusSession: (focusIdx >= 0 && focusIdx < sessions.length) ? sessions[focusIdx] : null
  // All upcoming race weekends, nearest first.
  readonly property var meetingGroups: Model.groupByMeeting(sessions)

  function open() {
    root.controller.show()
    if (hostWidget) hostWidget.refresh()
  }

  function openFromHotkey() { root.open() }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(scheduleColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Notification bell, bottom-right corner of the panel.
      Rectangle {
        z: 10
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Style.space(30)
        height: width
        radius: height / 2
        color: bellArea.containsMouse
               ? Style.hoverFillFor(root.bar.foreground, Color.accent)
               : "transparent"

        Text {
          anchors.centerIn: parent
          // Emoji instead of nerd-font glyphs: renders reliably everywhere.
          text: hostWidget && hostWidget.notificationsOn ? "🔔" : "🔕"
          color: (hostWidget && hostWidget.notificationsOn)
                 ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: bellArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (hostWidget) hostWidget.toggleNotifications()
        }
      }

      Flickable {
        id: scheduleScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: scheduleColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: scheduleColumn
          width: scheduleScroll.width
          spacing: Style.space(14)

          // ---- Hero: big flag + next session name + where ------------------
          Row {
            visible: !!root.focusSession
            width: parent.width
            spacing: Style.space(16)

            Text {
              id: heroFlag
              anchors.verticalCenter: parent.verticalCenter
              text: root.focusSession ? Model.emojiFlag(root.focusSession.countryCode) : ""
              font.family: root.bar.fontFamily
              // Deliberately oversized decorative emoji, outside the scale.
              font.pixelSize: 46
            }

            Column {
              id: heroColumn
              width: parent.width - heroFlag.implicitWidth - Style.space(16)
                    - heroWhen.implicitWidth - Style.space(16)
              spacing: Style.space(3)

              Text {
                text: root.focusSession && Model.isLive(root.focusSession, root.nowMs)
                      ? "LIVE NOW" : "NEXT SESSION"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 2
              }

              Text {
                text: root.focusSession ? root.focusSession.name : ""
                elide: Text.ElideRight
                width: parent.width
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
                font.capitalization: Font.AllUppercase
              }

              Text {
                text: {
                  if (!root.focusSession) return ""
                  var s = root.focusSession
                  var gp = Model.shortGpName(s.meetingName, s.officialName)
                  return gp + (s.location ? "  ·  " + s.location : "")
                }
                elide: Text.ElideRight
                width: parent.width
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
            }

            // Right side of the hero: loud time over quiet date/countdown.
            Column {
              id: heroWhen
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                anchors.right: parent.right
                text: root.focusSession ? Model.formatTime(new Date(root.focusSession.startMs), root.use24h) : ""
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Text {
                anchors.right: parent.right
                visible: !!root.focusSession
                text: root.focusSession ? Qt.formatDate(new Date(root.focusSession.startMs), "ddd d MMM").toUpperCase() : ""
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 2
              }

              Text {
                anchors.right: parent.right
                visible: !!root.focusSession
                text: {
                  if (!root.focusSession) return ""
                  if (Model.isLive(root.focusSession, root.nowMs)) return "LIVE"
                  return "in " + Model.countdown(root.focusSession.startMs - root.nowMs, false)
                }
                color: root.focusSession && Model.isLive(root.focusSession, root.nowMs)
                       ? root.bar.urgent !== undefined ? root.bar.urgent : root.bar.foreground
                       : Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
            }
          }

          Text {
            visible: !root.focusSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.loaded ? "No upcoming F1 sessions" : "Fetching schedule…"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          // ---- One block per upcoming race weekend -------------------------
          Repeater {
            model: root.meetingGroups

            Column {
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(8)

              // Strong separator above each weekend (skipped on the first,
              // which already has the hero divider), matching the top one.
              Rectangle {
                visible: index > 0
                width: parent.width
                height: Style.spacing.hairline
                color: root.bar.foreground
                opacity: 0.12
              }

              // Weekend header: flag, full GP name, city right-aligned.
              Item {
                width: parent.width
                height: Math.max(headerFlag.implicitHeight, headerName.implicitHeight)

                Text {
                  id: headerFlag
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.emojiFlag(modelData.countryCode)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                }

                Text {
                  id: headerName
                  anchors.left: headerFlag.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: headerTrack.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.officialName || modelData.meetingName
                  elide: Text.ElideRight
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  id: headerTrack
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: [modelData.location, modelData.countryCode].filter(function(x) { return !!x }).join(" · ")
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
              }

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                color: root.bar.foreground
                opacity: 0.12
              }

              // Day sections within the weekend. void tz reference keeps day
              // labels reactive to timezone changes.
              Repeater {
                model: {
                  void root.tzOffsetMinutes
                  return Model.groupDays(modelData.sessions)
                }

                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    text: modelData.label
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 2
                  }

                  Repeater {
                    model: modelData.sessions

                    Item {
                      id: sessionRow
                      required property var modelData
                      readonly property bool live: Model.isLive(modelData, root.nowMs)
                      readonly property bool isNext: root.sessions[Model.focusIndex(root.sessions, root.nowMs)] === modelData
                      width: parent.width
                      height: Math.max(sessionTime.implicitHeight, sessionName.implicitHeight) + Style.space(6)

                      Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: sessionRow.live || sessionRow.isNext
                               ? Style.hoverFillFor(root.bar.foreground, Color.accent)
                               : "transparent"
                        opacity: sessionRow.live ? 0.9 : 0.35
                      }

                      Text {
                        id: sessionTime
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(12)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(58)
                        text: Model.formatTime(new Date(sessionRow.modelData.startMs), root.use24h)
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: sessionRow.live || sessionRow.isNext
                      }

                      Text {
                        id: sessionName
                        anchors.left: sessionTime.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - sessionTime.width - Style.space(80)
                        text: sessionRow.modelData.name
                        elide: Text.ElideRight
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: sessionRow.live || sessionRow.isNext
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(12)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: sessionRow.live
                        text: "● LIVE"
                        color: root.bar.urgent !== undefined ? root.bar.urgent : root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Footer -----------------------------------------------------
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (hostWidget ? hostWidget.sourceLabel : "OpenF1")
                  + " · times local"
                  + (root.lastUpdated !== "" ? " · updated " + root.lastUpdated : "")
            color: Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.italic: true
          }
        }
      }
    }
  }
}
