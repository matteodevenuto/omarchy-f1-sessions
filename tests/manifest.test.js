const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")

const root = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
const widget = manifest.barWidget

function schemaEntry(key) {
  return widget.schema.find(entry => entry.key === key)
}

test("release metadata and entry point are valid", () => {
  assert.equal(manifest.version, "0.3.0")
  assert.equal(manifest.entryPoints.barWidget, "BarWidget.qml")
  assert.equal(fs.existsSync(path.join(root, manifest.entryPoints.barWidget)), true)
})

test("display modes stay aligned between defaults and schema", () => {
  const entry = schemaEntry("displayMode")
  assert.deepEqual(entry.options, ["next", "time", "weekend", "icon", "logo"])
  assert.equal(widget.defaults.displayMode, "icon")
  assert.equal(entry.defaultValue, "icon")
})

test("notification filters stay aligned between defaults and schema", () => {
  const entry = schemaEntry("notificationSessions")
  assert.deepEqual(entry.options, ["all", "competitive", "race"])
  assert.equal(entry.options.includes(widget.defaults.notificationSessions), true)
})
