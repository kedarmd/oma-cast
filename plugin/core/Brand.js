// kmDot mark: exact vector from kmDot/config/quickshell/components/r1icons.js.
// Canonical component: 354ba062-72fc-8008-8008-c87ee54dd13e.
var SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\"><path d=\"M2 5V19M2 12L7.5 5M7.5 19V5L11 10L14.5 5V19M2 12L7.5 19M14.5 5H17L19 8V16L17 19H14.5\" fill=\"none\" stroke=\"#c0caf5\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/><circle cx=\"22\" cy=\"18\" r=\"1.5\" fill=\"#7aa2f7\"/></svg>"

function source(primary, accent) {
  function rgb(value) {
    var hex = String(value)
    return /^#[0-9a-fA-F]{8}$/.test(hex) ? "#" + hex.slice(3) : hex
  }
  var themed = SVG.replace(/#c0caf5/g, "__PRIMARY__").replace(/#7aa2f7/g, "__ACCENT__")
    .split("__PRIMARY__").join(rgb(primary)).split("__ACCENT__").join(rgb(accent || primary))
  return "data:image/svg+xml," + encodeURIComponent(themed)
}
if (typeof module !== "undefined") module.exports = { SVG: SVG, source: source }
