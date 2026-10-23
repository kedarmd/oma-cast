// Read only generated color declarations, never execute a desktop QML file.
function parse(text) {
  var palette = {}, match
  var re = /(?:readonly\s+)?property\s+color\s+(\w+)\s*:\s*["'](#[0-9a-fA-F]{8}|#[0-9a-fA-F]{6})["']/g
  while ((match = re.exec(String(text)))) palette[match[1]] = match[2]
  var required = ["surface_high", "text", "primary", "primary_container", "on_primary_container", "outline_variant"]
  for (var i = 0; i < required.length; i++) if (!palette[required[i]]) throw new Error("Missing kmDot color: " + required[i])
  return palette
}
if (typeof module !== "undefined") module.exports = { parse: parse }
