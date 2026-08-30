const fs = require("fs")
const vm = require("vm")

const source = fs.readFileSync("qml/Adventure.js", "utf8").replace(/^\.pragma library\s*/, "")
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
if (saved.version !== 2 || saved.transcript.length !== 1 || saved.player.inventory[0] !== "Brass key")
    throw new Error("Versioned save serialization failed")
if (context.load("{}").ok !== false) throw new Error("Malformed saves must be rejected")

console.log("Adventure logic checks passed")
