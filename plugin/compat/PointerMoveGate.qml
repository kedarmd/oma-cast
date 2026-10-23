import QtQuick
QtObject {
  property var referenceItem: null
  property var lastPosition: null
  function reset() { lastPosition = null }
  function moved(item, mouse) {
    var point = item.mapToItem(referenceItem, mouse.x, mouse.y)
    var previous = lastPosition
    lastPosition = point
    return previous !== null && (Math.abs(previous.x - point.x) + Math.abs(previous.y - point.y) > 1)
  }
}
