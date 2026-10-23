var FALLBACK_ID = "fallback:agent"

function launchArgv(query, helper) {
  var prompt = String(query === undefined || query === null ? "" : query)
  if (!prompt.trim()) throw new Error("Type a question first")
  if (prompt.indexOf("\u0000") >= 0) throw new Error("Questions cannot contain a NUL character")
  if (prompt.length > 16384) throw new Error("Keep the question under 16,385 characters")
  return [helper || "kay-cast-desktop", "agent", prompt]
}

if (typeof module !== "undefined") {
  module.exports = { FALLBACK_ID: FALLBACK_ID, launchArgv: launchArgv }
}
