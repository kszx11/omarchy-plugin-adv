import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "qml/Adventure.js" as Adventure

Item {
    id: root
    property var shell: null
    property var hostWidget: null
    readonly property bool opened: gameWindow.visible
    property bool closingFromHost: false
    property bool hasOpened: false
    property bool busy: false
    property string busyMessage: ""
    property bool savesLoaded: false
    property bool apiKeyLoaded: false
    property bool apiKeyTouched: false
    property bool apiKeySavePending: false
    property bool apiKeyPathSafe: false
    property bool savesPathSafe: false
    property string approvedApiKeyPath: ""
    property string approvedSavesPath: ""
    property string apiKeyValue: ""
    property string environmentApiKey: (Quickshell.env("OPENAI_API_KEY") || "").trim()
    property string activeKeyFingerprint: ""
    property string pendingRestoreKey: ""
    property bool savePending: false
    property bool savesCorrupt: false
    property var commandHistory: []
    property int commandHistoryIndex: 0
    property string savesPath: Quickshell.env("HOME") + "/.local/state/omarchy-adventure.json"
    property string privateStateDir: Quickshell.env("HOME") + "/.local/state/omarchy-adventure"
    property string apiKeyPath: privateStateDir + "/api-key.json"
    readonly property int maxApiKeyFileBytes: 4096
    readonly property int maxSavesFileBytes: 256 * 1024
    readonly property int maxSavesFileCharacters: Math.floor(maxSavesFileBytes / 4)
    readonly property int maxSavedGames: 4
    property var savedGames: ({})
    property var gameState: ({ location: "No world loaded", stats: {}, inventory: [], journal: [], visited: [], map: {} })
    property var environment: ({ exits: [], npcs: [], items: [] })

    function open(payloadJson) {
        closingFromHost = false
        hasOpened = true
        gameWindow.visible = true
    }
    function close() {
        closingFromHost = true
        persistCurrentGame()
        gameWindow.visible = false
        closingFromHost = false
    }
    function requestClose() {
        if (hostWidget && typeof hostWidget.close === "function") hostWidget.close()
        else if (shell && typeof shell.hide === "function") shell.hide("io.github.kszx11.adventure")
        else gameWindow.visible = false
    }
    function addMessage(kind, text) {
        text = typeof text === "string" ? text.trim().slice(0, Adventure.maxTranscriptTextLength) : ""
        if (!text) return
        while (transcript.count >= Adventure.maxTranscriptEntries) transcript.remove(0)
        transcript.append({ kind: kind, text: text })
        transcriptView.positionViewAtEnd()
    }
    function transcriptEntries() {
        var entries = []
        for (var index = 0; index < transcript.count; index++) entries.push(transcript.get(index))
        return entries
    }
    function replaceTranscript(entries) {
        transcript.clear()
        for (var index = 0; index < entries.length; index++) transcript.append(entries[index])
    }
    function apply(response) {
        for (let item of response.events) addMessage(item.kind, item.text)
        if (response.ok !== false) {
            gameState = response.state
            environment = Adventure.scene()
            persistCurrentGame()
        }
        busy = false
        busyMessage = ""
        if (gameWindow.visible) Qt.callLater(function() { commandInput.forceActiveFocus() })
    }
    function apiKeyOrExplain() {
        var key = apiKeyValue.trim()
        if (key.length > Adventure.maxApiKeyLength) {
            addMessage("error", "The OpenAI API key is too long.")
            return ""
        }
        if (key.length > 0) return key
        addMessage("error", "Enter an OpenAI API key first.")
        return ""
    }
    function persistApiKey() {
        if (!apiKeyValue.trim()) return
        if (!apiKeyLoaded) {
            apiKeySavePending = true
            return
        }
        apiKeySavePending = false
        if (!apiKeyPathSafe) {
            addMessage("error", "The private API-key file is not safe to write. The key remains available only for this session.")
            return
        }
        apiKeyFile.setText(JSON.stringify({ apiKey: apiKeyValue.trim() }, null, 2) + "\n")
    }
    function commitEnteredApiKey() {
        apiKeyTouched = true
        persistApiKey()
        restoreForKey(apiKeyValue.trim(), false)
    }
    function loadApiKey(raw) {
        var rememberedKey = ""
        try {
            var parsed = JSON.parse(raw || "{}")
            rememberedKey = typeof parsed.apiKey === "string" ? parsed.apiKey.trim().slice(0, Adventure.maxApiKeyLength) : ""
        } catch (ignored) {}
        apiKeyLoaded = true
        if (environmentApiKey.length > 0) {
            apiKeyValue = environmentApiKey
        } else if (!apiKeyTouched && rememberedKey.length > 0) {
            apiKeyValue = rememberedKey
        }
        if (apiKeyValue.trim()) restoreForKey(apiKeyValue.trim(), false)
        if (apiKeySavePending) persistApiKey()
    }
    function newGame() {
        const key = apiKeyOrExplain()
        if (!key) return
        busy = true
        busyMessage = "Weaving a new adventure…"
        Adventure.newGame(key, startInput.text, function(response) {
            if (response.ok !== false) {
                activeKeyFingerprint = keyFingerprint(key)
                transcript.clear()
            }
            apply(response)
        })
    }
    function saveGame() {
        if (!Adventure.hasGame()) {
            addMessage("error", "Start or load an adventure before saving.")
            return
        }
        persistCurrentGame()
        if (!savesCorrupt) addMessage("system", "Game saved for this API key.")
    }
    function loadGame() {
        const key = apiKeyValue.trim()
        if (!key) {
            addMessage("error", "Enter an OpenAI API key before loading its adventure.")
            return
        }
        restoreForKey(key, true)
    }
    function keyFingerprint(key) {
        var hash = 2166136261
        for (var index = 0; index < key.length; index++) {
            hash ^= key.charCodeAt(index)
            hash = Math.imul(hash, 16777619)
        }
        return "v1-" + (hash >>> 0).toString(16) + "-" + key.length
    }
    function persistCurrentGame() {
        if (!activeKeyFingerprint || !Adventure.hasGame() || savesCorrupt || !savesPathSafe) return
        if (!savesLoaded) {
            savePending = true
            return
        }
        var encodedGame = Adventure.serialize(transcriptEntries())
        if (!encodedGame) {
            addMessage("error", "The adventure is too large to save safely. Continue playing, then save again after the transcript has compacted.")
            return
        }
        var next = ({})
        for (var fingerprint in savedGames) next[fingerprint] = savedGames[fingerprint]
        next[activeKeyFingerprint] = encodedGame
        var keys = Object.keys(next).sort()
        while (keys.length > maxSavedGames) {
            var removed = keys.shift()
            if (removed !== activeKeyFingerprint) delete next[removed]
            else {
                var alternate = keys.shift()
                if (alternate) delete next[alternate]
            }
        }
        var serialized = JSON.stringify(next, null, 2) + "\n"
        if (serialized.length > maxSavesFileCharacters) {
            addMessage("error", "Saved adventures exceed the safe storage limit; the current game was not written.")
            return
        }
        savedGames = next
        savedGamesFile.setText(serialized)
    }
    function restoreForKey(key, announceMissing) {
        if (!key) return
        if (!savesLoaded) {
            pendingRestoreKey = key
            return
        }
        restoreLoadedKey(key, announceMissing === true)
    }
    function restoreLoadedKey(key, announceMissing) {
        const fingerprint = keyFingerprint(key)
        const savedGame = savedGames[fingerprint]
        if (!savedGame) {
            if (announceMissing)
                addMessage("system", "No saved adventure exists for this API key yet.")
            return
        }
        if (activeKeyFingerprint === fingerprint && gameState.location !== "No world loaded") return
        const response = Adventure.load(savedGame)
        if (response.ok === false) {
            for (let item of response.events) addMessage(item.kind, item.text)
            return
        }
        activeKeyFingerprint = fingerprint
        replaceTranscript(response.transcript || [])
        apply(response)
    }
    function useSceneAction(section, label) {
        if (busy) return
        if (section === "EXITS") sendCommand("go to " + label)
        else if (section === "PEOPLE") sendCommand("talk to " + label)
        else commandInput.text = "examine " + label
    }
    function sceneActions() {
        var actions = []
        root.environment.exits.forEach(function(label) { actions.push({ section: "EXITS", label: label, command: "go to " + label }) })
        root.environment.npcs.forEach(function(label) { actions.push({ section: "PEOPLE", label: label, command: "talk to " + label }) })
        root.environment.items.forEach(function(label) { actions.push({ section: "ITEMS", label: label, command: "examine " + label }) })
        return actions
    }
    function sceneActionNumber(section, label) {
        var actions = sceneActions()
        for (var index = 0; index < actions.length; index++) {
            if (actions[index].section === section && actions[index].label === label) return index + 1
        }
        return 0
    }
    function activateSceneAction(number) {
        var action = sceneActions()[number - 1]
        if (action && !busy) sendCommand(action.command)
        else if (!busy) addMessage("error", "There is no choice [" + number + "] in the current scene.")
    }
    function rememberCommand(command) {
        if (!commandHistory.length || commandHistory[commandHistory.length - 1] !== command) {
            var next = commandHistory.slice()
            next.push(command)
            commandHistory = next.slice(-100)
        }
        commandHistoryIndex = commandHistory.length
    }
    function browseHistory(direction) {
        if (!commandHistory.length) return
        commandHistoryIndex = Math.max(0, Math.min(commandHistory.length, commandHistoryIndex + direction))
        commandInput.text = commandHistoryIndex === commandHistory.length ? "" : commandHistory[commandHistoryIndex]
        commandInput.cursorPosition = commandInput.text.length
    }
    function completionCandidates() {
        var typed = commandInput.text.trim()
        var commands = ["look", "help", "hint", "inventory", "stats", "journal", "map", "save", "load", "go to ", "talk to ", "examine ", "take ", "give ", "use "]
        var lower = typed.toLowerCase()
        if (lower.indexOf("go to ") === 0) return root.environment.exits.map(function(value) { return "go to " + value })
        if (lower.indexOf("talk to ") === 0) return root.environment.npcs.map(function(value) { return "talk to " + value })
        if (lower.indexOf("examine ") === 0 || lower.indexOf("take ") === 0) {
            var verb = lower.indexOf("take ") === 0 ? "take " : "examine "
            return root.environment.items.map(function(value) { return verb + value })
        }
        return commands
    }
    function completeCommand() {
        var typed = commandInput.text.trim().toLowerCase()
        var matches = completionCandidates().filter(function(candidate) { return candidate.toLowerCase().indexOf(typed) === 0 })
        if (matches.length) {
            commandInput.text = matches[0]
            commandInput.cursorPosition = commandInput.text.length
        }
    }
    function shortcutMode() {
        return !busy && !apiKey.activeFocus && !startInput.activeFocus && commandInput.text.trim().length === 0
    }
    function runQuickCommand(command) {
        if (!busy) sendCommand(command)
    }
    function sendCommand(command) {
        command = command.trim()
        if (!command || busy) return
        if (command.length > Adventure.maxPlayerInputLength) {
            addMessage("error", "Command is too long. Please keep it under " + Adventure.maxPlayerInputLength + " characters.")
            return
        }
        var choice = command.match(/^#?([1-9])$/)
        if (choice) {
            activateSceneAction(Number(choice[1]))
            return
        }
        rememberCommand(command)
        if (command.toLowerCase() === "save") { addMessage("player", "> " + command); saveGame(); return }
        if (command.toLowerCase() === "load") { addMessage("player", "> " + command); loadGame(); return }
        const key = apiKeyOrExplain()
        if (!key) return
        addMessage("player", "> " + command)
        busy = true
        busyMessage = "The narrator is considering your action…"
        Adventure.submit(key, command, apply)
    }

    ListModel { id: transcript }
    Process {
        id: ensurePrivateStateDir
        command: ["timeout", "--signal=TERM", "--kill-after=1s", "5s", "bash", "-c",
                  "d=$1; [ ! -L \"$d\" ] || exit 66; if [ -e \"$d\" ]; then [ -d \"$d\" ] || exit 66; else mkdir -m 700 -- \"$d\" || exit 66; fi; chmod 700 -- \"$d\"",
                  "adventure-private-state", root.privateStateDir]
        onExited: function(code) {
            if (code !== 0) {
                root.apiKeyLoaded = true
                root.apiKeyPathSafe = false
                root.addMessage("error", "The private state directory is unsafe or unavailable. API keys will not be stored.")
                apiKeyFile.path = ""
                savesReadCheck.running = true
                return
            }
            apiKeyReadCheck.running = true
            savesReadCheck.running = true
        }
    }
    Process {
        id: apiKeyReadCheck
        command: ["timeout", "--signal=TERM", "--kill-after=1s", "5s", "bash", "-c",
                  "d=$1; f=$2; l=$3; [ -d \"$d\" ] && [ ! -L \"$d\" ] && [ ! -L \"$f\" ] || exit 66; [ ! -e \"$f\" ] && exit 0; [ -f \"$f\" ] || exit 66; n=$(stat -c %s -- \"$f\") || exit 66; [ \"$n\" -le \"$l\" ] || exit 65",
                  "adventure-api-key-read", root.privateStateDir, root.apiKeyPath, String(root.maxApiKeyFileBytes)]
        onExited: function(code) {
            if (code === 0) {
                root.apiKeyPathSafe = true
                root.approvedApiKeyPath = root.apiKeyPath
                apiKeyFile.path = root.approvedApiKeyPath
                apiKeyFile.reload()
            } else {
                root.apiKeyLoaded = true
                root.apiKeyPathSafe = false
                root.addMessage("error", code === 65
                    ? "The remembered API-key file is too large and was ignored."
                    : "The remembered API-key file is unsafe and was ignored.")
                if (root.environmentApiKey.length > 0) root.apiKeyValue = root.environmentApiKey
                if (root.apiKeySavePending) root.persistApiKey()
            }
        }
    }
    Process {
        id: savesReadCheck
        command: ["timeout", "--signal=TERM", "--kill-after=1s", "5s", "bash", "-c",
                  "f=$1; l=$2; [ ! -L \"$f\" ] || exit 66; [ ! -e \"$f\" ] && exit 0; [ -f \"$f\" ] || exit 66; n=$(stat -c %s -- \"$f\") || exit 66; [ \"$n\" -le \"$l\" ] || exit 65",
                  "adventure-saves-read", root.savesPath, String(root.maxSavesFileBytes)]
        onExited: function(code) {
            if (code === 0) {
                root.savesPathSafe = true
                root.approvedSavesPath = root.savesPath
                savedGamesFile.path = root.approvedSavesPath
                savedGamesFile.reload()
            } else {
                root.savesLoaded = true
                root.savesPathSafe = false
                root.savesCorrupt = true
                root.addMessage("error", code === 65
                    ? "Saved adventures are too large and were not read."
                    : "Saved adventures are unsafe and were not read.")
            }
        }
    }
    FileView {
        id: apiKeyFile
        path: ""
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: { if (root.approvedApiKeyPath && root.approvedApiKeyPath === path) root.loadApiKey(text()) }
        onLoadFailed: { if (root.approvedApiKeyPath && root.approvedApiKeyPath === path) root.loadApiKey("") }
    }
    FileView {
        id: savedGamesFile
        path: ""
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (!root.approvedSavesPath || root.approvedSavesPath !== path) return
            try {
                var parsed = JSON.parse(text() || "{}")
                if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid saves")
                var bounded = ({})
                var keys = Object.keys(parsed).sort()
                if (keys.length > root.maxSavedGames) throw new Error("too many saves")
                for (var index = 0; index < keys.length; index++) {
                    var key = keys[index]
                    var value = parsed[key]
                    if (/^v1-[0-9a-f]+-\d+$/.test(key) && typeof value === "string" && value.length <= Adventure.maxSavedGameCharacters)
                        bounded[key] = value
                }
                root.savedGames = bounded
            } catch (ignored) {
                root.savedGames = ({})
                root.savesCorrupt = true
                root.addMessage("error", "Saved adventures could not be read. They will not be overwritten; restore the file before saving again.")
            }
            root.savesLoaded = true
            if (root.savePending) root.persistCurrentGame()
            if (root.pendingRestoreKey) {
                const key = root.pendingRestoreKey
                root.pendingRestoreKey = ""
                root.restoreLoadedKey(key, false)
            }
        }
        onLoadFailed: {
            if (!root.approvedSavesPath || root.approvedSavesPath !== path) return
            root.savesLoaded = true
            if (root.savePending) root.persistCurrentGame()
            if (root.pendingRestoreKey) {
                const key = root.pendingRestoreKey
                root.pendingRestoreKey = ""
                root.restoreLoadedKey(key, false)
            }
        }
    }

    Component.onCompleted: ensurePrivateStateDir.running = true

    FloatingWindow {
        id: gameWindow
        visible: false
        title: "Adventure"
        color: Color.background
        implicitWidth: 1150
        implicitHeight: 740
        minimumSize: Qt.size(820, 540)
        onVisibleChanged: {
            if (!visible && root.hasOpened && !root.closingFromHost) root.requestClose()
            if (visible) Qt.callLater(function() { commandInput.forceActiveFocus() })
        }

        Shortcut { sequence: "Escape"; onActivated: root.requestClose() }
        Shortcut { sequence: "Ctrl+L"; onActivated: { commandInput.clear(); commandInput.forceActiveFocus() } }
        Shortcut { sequence: "?"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("help") }
        Shortcut { sequence: "L"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("look") }
        Shortcut { sequence: "H"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("hint") }
        Shortcut { sequence: "M"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("map") }
        Shortcut { sequence: "I"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("inventory") }
        Shortcut { sequence: "J"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("journal") }
        Shortcut { sequence: "S"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("save") }
        Shortcut { sequence: "R"; enabled: root.shortcutMode(); onActivated: root.runQuickCommand("load") }
        Shortcut { sequence: "1"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(1) }
        Shortcut { sequence: "2"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(2) }
        Shortcut { sequence: "3"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(3) }
        Shortcut { sequence: "4"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(4) }
        Shortcut { sequence: "5"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(5) }
        Shortcut { sequence: "6"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(6) }
        Shortcut { sequence: "7"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(7) }
        Shortcut { sequence: "8"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(8) }
        Shortcut { sequence: "9"; enabled: root.shortcutMode(); onActivated: root.activateSceneAction(9) }

        Rectangle {
            anchors.fill: parent
            color: Color.background
            border.color: Color.popups.border
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "ADVENTURE"; font.bold: true; font.letterSpacing: 2; color: Color.accent; font.pixelSize: 19 }
                    Label { text: root.gameState.location; textFormat: Text.PlainText; Layout.fillWidth: true; color: Color.foreground; elide: Label.ElideRight }
                    BusyIndicator { running: root.busy; visible: root.busy; implicitWidth: 24; implicitHeight: 24 }
                    Button { text: "Close"; onClicked: root.requestClose() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle {
                        Layout.preferredWidth: Math.max(260, Math.min(440, gameWindow.width * 0.25)); Layout.fillHeight: true
                        color: Color.popups.background; radius: 8; border.color: Color.popups.border
                        ScrollView {
                            id: sceneScroll
                            anchors.fill: parent; anchors.margins: 14; clip: true
                            Column {
                                // ScrollView's content item starts at the width of its widest child.
                                // Use the viewport width so every label gets the full side-panel width.
                                width: sceneScroll.availableWidth
                                spacing: 12
                                Label { text: "CURRENT SCENE"; color: Color.accent; font.bold: true; font.pixelSize: 12 }
                                Label { text: root.gameState.location; textFormat: Text.PlainText; width: parent.width; wrapMode: Text.Wrap; color: Color.foreground; font.pixelSize: 17 }
                                Label { text: "Click a choice below to act."; width: parent.width; wrapMode: Text.Wrap; color: Color.muted; font.pixelSize: 11 }
                                Repeater {
                                    model: [["EXITS", root.environment.exits], ["PEOPLE", root.environment.npcs], ["ITEMS", root.environment.items]]
                                    delegate: Column {
                                        id: sceneSection
                                        property string sectionName: modelData[0]
                                        width: parent.width; spacing: 4
                                        Label { text: modelData[0]; textFormat: Text.PlainText; color: Color.muted; font.bold: true; font.pixelSize: 11 }
                                        Repeater {
                                            model: modelData[1]
                                            delegate: Rectangle {
                                                id: sceneAction
                                                width: parent.width
                                                height: actionText.implicitHeight + 12
                                                radius: 5
                                                color: actionMouse.containsMouse ? Color.accent : Color.background
                                                opacity: root.busy ? 0.55 : 1
                                                implicitHeight: Math.max(32, actionText.implicitHeight + 12)
                                                Text {
                                                    id: actionText
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    text: "[" + root.sceneActionNumber(sceneSection.sectionName, modelData) + "] " +
                                                        (sceneSection.sectionName === "EXITS" ? "Go: " + modelData
                                                        : sceneSection.sectionName === "PEOPLE" ? "Talk: " + modelData
                                                        : "Examine: " + modelData)
                                                    textFormat: Text.PlainText
                                                    wrapMode: Text.Wrap
                                                    elide: Text.ElideNone
                                                    horizontalAlignment: Text.AlignLeft
                                                    verticalAlignment: Text.AlignVCenter
                                                    color: Color.foreground
                                                }
                                                MouseArea {
                                                    id: actionMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: !root.busy
                                                    onClicked: root.useSceneAction(sceneSection.sectionName, modelData)
                                                }
                                            }
                                        }
                                        Label { visible: modelData[1].length === 0; text: "None"; color: Color.muted }
                                    }
                                }
                                Rectangle { width: parent.width; height: 1; color: Color.popups.border }
                                Label { text: "CHARACTER"; color: Color.accent; font.bold: true; font.pixelSize: 12 }
                                Repeater { model: Object.keys(root.gameState.stats); delegate: Label { text: modelData + ": " + root.gameState.stats[modelData]; textFormat: Text.PlainText; color: Color.foreground } }
                                Label { text: "INVENTORY"; color: Color.muted; font.bold: true; font.pixelSize: 11 }
                                Label { text: root.gameState.inventory.join(", ") || "Empty"; textFormat: Text.PlainText; width: parent.width; wrapMode: Text.Wrap; color: Color.foreground }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        color: Color.popups.background; radius: 8; border.color: Color.popups.border
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 10
                            ListView {
                                id: transcriptView; Layout.fillWidth: true; Layout.fillHeight: true; model: transcript; spacing: 8; clip: true
                                delegate: Rectangle {
                                    required property string kind
                                    required property string text
                                    width: transcriptView.width
                                    height: message.implicitHeight + (kind === "player" ? 12 : 20)
                                    radius: 7
                                    color: kind === "error" ? "#9c2c2c" : kind === "player" ? Color.background : Color.popups.background
                                    opacity: 1
                                    border.width: kind === "player" ? 1 : 0
                                    border.color: kind === "player" ? Color.accent : "transparent"
                                    Label {
                                        id: message
                                        anchors.fill: parent
                                        anchors.margins: kind === "player" ? 6 : 10
                                        text: parent.text
                                        textFormat: Text.PlainText
                                        color: kind === "error" ? "#ffffff" : Color.foreground
                                        wrapMode: Text.Wrap
                                        lineHeight: 1.25
                                    }
                                }
                                ScrollBar.vertical: ScrollBar { }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.busy
                                spacing: 8
                                BusyIndicator { running: root.busy; implicitWidth: 18; implicitHeight: 18 }
                                Label { text: root.busyMessage || "Working…"; color: Color.accent; font.italic: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                TextField {
                                    id: commandInput
                                    Layout.fillWidth: true
                                    placeholderText: root.busy ? "The narrator is working…" : "Enter a command…  (Tab completes; ↑/↓ history)"
                                    enabled: !root.busy
                                    onAccepted: { root.sendCommand(text); clear() }
                                    Keys.onPressed: function(event) {
                                        if (event.key === Qt.Key_Up) { root.browseHistory(-1); event.accepted = true }
                                        else if (event.key === Qt.Key_Down) { root.browseHistory(1); event.accepted = true }
                                        else if (event.key === Qt.Key_Tab) { root.completeCommand(); event.accepted = true }
                                    }
                                }
                                Button { text: root.busy ? "Working…" : "Send"; enabled: !root.busy && commandInput.text.trim().length > 0; onClicked: { root.sendCommand(commandInput.text); commandInput.clear() } }
                            }
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 215; Layout.fillHeight: true
                        color: Color.popups.background; radius: 8; border.color: Color.popups.border
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 9
                            Label { text: "ADVENTURE"; color: Color.accent; font.bold: true; font.pixelSize: 12 }
                            TextField {
                                id: apiKey
                                Layout.fillWidth: true
                                placeholderText: "OpenAI API key"
                                echoMode: TextInput.Password
                                text: root.apiKeyValue
                                onTextEdited: root.apiKeyValue = text
                                onEditingFinished: root.commitEnteredApiKey()
                            }
                            Label {
                                text: root.environmentApiKey.length > 0
                                    ? "Using OPENAI_API_KEY from the shell environment."
                                    : "Remembered locally on this device."
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Color.muted
                                font.pixelSize: 11
                            }
                            TextArea { id: startInput; Layout.fillWidth: true; Layout.preferredHeight: 96; placeholderText: "Where and when does the story begin?"; wrapMode: TextArea.Wrap }
                            Button { text: "New game"; Layout.fillWidth: true; enabled: !root.busy; onClicked: root.newGame() }
                            Button { text: "Save"; Layout.fillWidth: true; enabled: !root.busy; onClicked: root.saveGame() }
                            Button { text: "Load"; Layout.fillWidth: true; enabled: !root.busy; onClicked: root.loadGame() }
                            Button { text: "Look"; Layout.fillWidth: true; enabled: !root.busy; onClicked: root.sendCommand("look") }
                            Button { text: "Map"; Layout.fillWidth: true; enabled: !root.busy; onClicked: root.sendCommand("map") }
                            Button { text: "Hint"; Layout.fillWidth: true; enabled: !root.busy; onClicked: root.sendCommand("hint") }
                            Item { Layout.fillHeight: true }
                            Label {
                                text: "Keyboard: Enter send · Tab complete · ↑/↓ history · type 1–9 (or #1–#9) for choices · L look · H hint · M map · I inventory · J journal · S save · R load · ? help · Esc close.\n\nYou can also type: go to <exit>, talk to <person>, examine <item>."
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Color.muted
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}
