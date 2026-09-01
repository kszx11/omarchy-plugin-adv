const fs = require("fs")
const vm = require("vm")

const source = fs.readFileSync("qml/Adventure.js", "utf8").replace(/^\.pragma library\s*/, "")
const panelSource = fs.readFileSync("Panel.qml", "utf8")
const context = { JSON, Math, Array, Object, String, Number, isFinite, setTimeout }
vm.createContext(context)
vm.runInContext(source, context, { filename: "Adventure.js" })

const legacySave = {
    history: [{ role: "developer", content: "rules" }, { role: "assistant", content: "story" }],
    player: {
        stats: { STR: 10, DEX: 11, CON: 12, INT: 13, WIS: 9, CHA: 14 },
        inventory: ["Brass key"], journal: ["Find the bell"], visited: ["Shrine"], map: {}, location: "Shrine"
    },
    scenes: { Shrine: { exits: ["North: tower stair"], npcs: ["Mara Vell, ferrymaster"], items: ["Bell"] } },
    descriptions: { Shrine: "A rain-soaked shrine." }
}

const loaded = context.load(JSON.stringify(legacySave))
if (!loaded.ok) throw new Error("A compatible existing save should load")
if (!context.personHere("Mara")) throw new Error("NPC short-name matching should work")
if (!context.movementExit("go to tower").exit) throw new Error("Displayed exits should resolve")
if (!context.movementExit("go to the North: tower stair").exit) throw new Error("Natural exit phrasing should resolve")
if (context.movementExit("go to nowhere").exit) throw new Error("Unknown exits must be rejected")

const saved = JSON.parse(context.serialize([{ kind: "narrator", text: "A rain-soaked shrine." }]))
if (saved.version !== 4 || saved.transcript.length !== 1 || saved.player.inventory[0] !== "Brass key")
    throw new Error("Versioned save serialization failed")
if (context.load("{}").ok !== false) throw new Error("Malformed saves must be rejected")

const hostileSave = JSON.parse(JSON.stringify(legacySave))
hostileSave.player.inventory = Array(100).fill("<b>too much</b>" + "x".repeat(300))
hostileSave.player.journal = Array(100).fill("j".repeat(300))
hostileSave.player.visited = Array(150).fill("v".repeat(300))
hostileSave.player.map = Object.fromEntries(Array.from({ length: 70 }, (_, i) => ["Map" + i, Array(30).fill("L".repeat(300))]))
hostileSave.scenes = Object.assign({ Shrine: legacySave.scenes.Shrine }, Object.fromEntries(Array.from({ length: 70 }, (_, i) => ["Scene" + i, { exits: Array(30).fill("E".repeat(300)), npcs: [], items: [] }])))
hostileSave.descriptions = Object.fromEntries(Object.keys(hostileSave.scenes).map(key => [key, "D".repeat(9000)]))
hostileSave.descriptions.Shrine = "A shrine."
hostileSave.history = [{ role: "developer", content: "rules" }].concat(Array(150).fill({ role: "assistant", content: "H".repeat(9000) }))
hostileSave.transcript = Array(250).fill({ kind: "narrator", text: "T".repeat(10000) })
const bounded = context.normalizeSave(hostileSave)
if (bounded.player.inventory.length !== context.maxInventoryItems || bounded.history.length !== context.maxHistoryEntries || bounded.transcript.length !== context.maxTranscriptEntries)
    throw new Error("Save collection bounds were not enforced")
if (bounded.descriptions.Shrine.length > context.maxNarrationLength || bounded.player.map.Map0.length > context.maxMapLinks)
    throw new Error("Save field bounds were not enforced")
if (context.load("x".repeat(context.maxSavedGameCharacters + 1)).ok !== false)
    throw new Error("Oversized saved-game strings must be rejected before parsing")

const durableState = context.stateForModel(context.game)
if (!durableState.worldRecord || durableState.worldRecord.discoveredLocations[0].name !== "Shrine")
    throw new Error("Known locations should be included in the authoritative world record")
context.applyAction(context.game, {
    narration: "The ferrymaster reveals the bell remembers names.", location: "Shrine", moved: false, isEnding: false,
    exits: ["North: tower stair"], npcs: ["Mara Vell, ferrymaster"], items: ["Bell"], inventory: ["Brass key"],
    journal: ["Find the bell"], worldFacts: ["Mara Vell says the bell remembers names."], stats: context.game.player.stats
}, "Shrine")
if (context.game.world.facts[0] !== "Mara Vell says the bell remembers names.")
    throw new Error("New durable world facts should persist across turns")
if (context.historyCharacters([{ content: "abc" }, { content: "de" }]) !== 5)
    throw new Error("History size accounting failed")

if (context.responseText({ output_text: "Direct text" }) !== "Direct text")
    throw new Error("Responses API direct text parsing failed")
const responseWithContent = { output: [{ type: "reasoning", content: [] }, { type: "message", content: [{ type: "output_text", text: "Structured text" }] }] }
if (context.responseText(responseWithContent) !== "Structured text")
    throw new Error("Responses API output array parsing failed")
if (!/ran out of response space/i.test(context.emptyResponseError({ status: "incomplete", incomplete_details: { reason: "max_output_tokens" } })))
    throw new Error("Incomplete Responses API errors should be actionable")

const plainTextBindings = [
    "text: root.gameState.location; textFormat: Text.PlainText",
    "text: root.gameState.inventory.join(\", \") || \"Empty\"; textFormat: Text.PlainText",
    "text: parent.text\n                                        textFormat: Text.PlainText",
    "textFormat: Text.PlainText\n                                                    wrapMode: Text.Wrap"
]
if (!plainTextBindings.every(binding => panelSource.includes(binding)))
    throw new Error("Model and saved-game content must be rendered as plain text")
if (!source.includes("xhr.responseText.length > maxApiResponseCharacters") || !source.includes("typeof saved !== \"string\" || saved.length > maxSavedGameCharacters"))
    throw new Error("Network and saved-game byte limits must remain enforced")

console.log("Adventure logic checks passed")
