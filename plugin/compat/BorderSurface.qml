import QtQuick
Rectangle {
  property var borderSpec: ({ color: Color.menu.border, width: 1.5 })
  readonly property real borderLeft: border.width
  readonly property real borderRight: border.width
  readonly property real borderTop: border.width
  readonly property real borderBottom: border.width
  border.color: borderSpec.color
  border.width: borderSpec.width
}
