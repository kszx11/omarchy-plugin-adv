import QtQuick
import qs.Ui

BarWidget {
    id: root
    moduleName: "io.github.kszx11.adventure"
    implicitWidth: launcher.implicitWidth
    implicitHeight: launcher.implicitHeight
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.shell = root.bar ? root.bar.shell : null
        panelLoader.item.hostWidget = root
    }
    function open(payloadJson) {
        if (panelLoader.item) panelLoader.item.open(payloadJson)
    }
    function close() {
        if (panelLoader.item) panelLoader.item.close()
    }
    function toggle() {
        if (opened) close()
        else open("{}")
    }

    onBarChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    BarIconButton {
        id: launcher
        anchors.fill: parent
        bar: root.bar
        text: "󰊈"
        tooltipText: "Adventure"
        onPressed: function(button) {
            if (button === Qt.LeftButton) root.toggle()
        }
    }
}
