import QtQuick
import "../compat"

Item {
  id: alert
  property var spec: null
  property var look: null
  property real zoom: 1
  signal confirmed()
  signal cancelled()
  function px(v) { return Math.round(Style.space(v) * alert.zoom) }
  Rectangle { anchors.fill: parent; color: "#99000000"; MouseArea { anchors.fill: parent; onClicked: alert.cancelled() } }
  Rectangle {
    width: Math.min(alert.px(390), parent.width - alert.px(36))
    height: panel.implicitHeight + alert.px(36)
    anchors.centerIn: parent
    radius: alert.px(16)
    color: look.elevatedBackground
    border.width: 1
    border.color: Util.alpha(look.foreground, 0.18)
    MouseArea { anchors.fill: parent }
    Column {
      id: panel
      anchors.fill: parent
      anchors.margins: alert.px(18)
      spacing: alert.px(12)
      Text { text: spec ? spec.title : "Confirm"; textFormat: Text.PlainText; color: look.foreground; font.family: look.fontFamily; font.pixelSize: Math.round(Style.font.title * alert.zoom); font.weight: Font.Medium }
      Text { width: parent.width; text: spec ? spec.message : ""; textFormat: Text.PlainText; color: look.secondaryForeground; font.family: look.fontFamily; font.pixelSize: Math.round(Style.font.body * alert.zoom); wrapMode: Text.WordWrap }
      Row {
        width: parent.width
        spacing: alert.px(8)
        Item { width: parent.width - cancel.width - confirm.width - alert.px(8); height: confirm.height }
        Rectangle {
          id: cancel
          width: cancelText.implicitWidth + alert.px(24); height: alert.px(34); radius: alert.px(8)
          color: Util.alpha(look.foreground, 0.06)
          Text { id: cancelText; anchors.centerIn: parent; text: "Cancel"; color: look.foreground; font.family: look.fontFamily; font.pixelSize: Math.round(Style.font.bodySmall * alert.zoom) }
          MouseArea { anchors.fill: parent; onClicked: alert.cancelled() }
        }
        Rectangle {
          id: confirm
          width: confirmText.implicitWidth + alert.px(24); height: alert.px(34); radius: alert.px(8)
          color: spec && spec.destructive ? look.error : look.accent
          Text { id: confirmText; anchors.centerIn: parent; text: spec ? spec.primary : "Confirm"; color: look.selectedForeground; font.family: look.fontFamily; font.pixelSize: Math.round(Style.font.bodySmall * alert.zoom); font.weight: Font.Medium }
          MouseArea { anchors.fill: parent; onClicked: alert.confirmed() }
        }
      }
    }
  }
}
