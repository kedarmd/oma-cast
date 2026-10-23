import QtQuick
import "../compat"

Rectangle {
  id: panel
  property string title: ""
  property var rows: []
  property var look: null
  property real zoom: 1
  function px(v) { return Math.round(Style.space(v) * panel.zoom) }
  width: px(320)
  height: Math.min(px(320), content.implicitHeight + px(28))
  radius: px(14)
  color: look.elevatedBackground
  border.width: 1
  border.color: Util.alpha(look.foreground, 0.15)
  MouseArea { anchors.fill: parent }
  Column {
    id: content
    anchors.fill: parent
    anchors.margins: panel.px(14)
    spacing: panel.px(8)
    Text { text: panel.title; textFormat: Text.PlainText; color: look.foreground; font.family: look.fontFamily; font.pixelSize: Math.round(Style.font.title * panel.zoom); elide: Text.ElideRight; width: parent.width }
    Repeater {
      model: panel.rows
      Row {
        required property var modelData
        width: content.width
        spacing: panel.px(12)
        Text { width: panel.px(78); text: modelData.label; textFormat: Text.PlainText; color: look.secondaryForeground; font.family: look.fontFamily; font.pixelSize: Math.round(Style.font.bodySmall * panel.zoom); elide: Text.ElideRight }
        Text { width: parent.width - panel.px(90); text: modelData.value; textFormat: Text.PlainText; color: look.foreground; font.family: look.fontFamily; font.pixelSize: Math.round(Style.font.bodySmall * panel.zoom); wrapMode: Text.WrapAnywhere }
      }
    }
  }
}
