import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var shell: null
    property var snapshot: ({})
    property string error: ""
    property bool ready: false
    property bool loading: false
    property bool acting: false
    property string actionError: ""
    property int days: 7
    property string lobby: "ranked"
    property int selected: 0
    property int focusId: 0
    property bool refreshQueued: false
    readonly property var settings: snapshot.settings || ({refreshMinutes: 10, matches: 20, notify: true, barMode: "winrate"})
    readonly property var accounts: snapshot.accounts || []
    readonly property var current: accounts.length > 0 ? accounts[Math.min(selected, accounts.length - 1)] : null
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("dota_fetch.py").toString().replace(/^file:\/\//, ""))

    signal accountAdded()

    function refresh() {
        if (fetcher.running) {
            refreshQueued = true
            return
        }
        loading = true
        fetcher.running = true
    }
    function setDays(value) {
        if (days === value) return
        days = value
        refresh()
    }
    function setLobby(value) {
        if (lobby === value) return
        lobby = value
        refresh()
    }
    function setSetting(key, value) {
        runAction(["--set", key, String(value)], false)
    }
    function addAccount(rawId, label) {
        runAction(["--add", String(rawId || "").trim(), "--label", String(label || "").trim()], true)
    }
    function removeAccount(id) {
        runAction(["--remove", String(id)], false)
    }
    function runAction(args, adding) {
        if (acting) return
        actionError = ""
        acting = true
        actionProc.adding = adding
        actionProc.command = ["python3", "-u", root.helper].concat(args)
        actionProc.running = true
    }
    function next() {
        if (accounts.length > 1) selected = (selected + 1) % accounts.length
    }
    function applyAction(text) {
        var raw = String(text || "").trim()
        var data = null
        try {
            data = JSON.parse(raw)
        } catch (e) {
            root.actionError = "Некорректный ответ помощника"
            return
        }
        if (!data.ok) {
            root.actionError = data.error || "Не удалось сохранить"
            return
        }
        root.actionError = ""
        if (actionProc.adding) {
            root.focusId = data.id
            root.accountAdded()
        }
        root.refresh()
    }
    function apply(text) {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
            var data = JSON.parse(raw)
            if (!data.ok) {
                root.error = data.error || "Ошибка помощника"
                return
            }
            root.error = ""
            root.ready = true
            root.snapshot = data
            if (root.focusId) {
                for (var i = 0; i < data.accounts.length; i++) {
                    if (data.accounts[i].id === root.focusId) root.selected = i
                }
                root.focusId = 0
            }
            if (root.selected >= data.accounts.length) root.selected = 0
        } catch (e) {
            root.error = "Некорректный ответ помощника"
        }
    }

    Process {
        id: fetcher
        command: ["python3", "-u", root.helper, "--days", String(root.days), "--lobby", root.lobby]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
        onExited: function(code, status) {
            root.loading = false
            if (code !== 0) root.error = "Помощник завершился с кодом " + code
            if (root.refreshQueued) {
                root.refreshQueued = false
                root.refresh()
            }
        }
    }

    Process {
        id: actionProc
        property bool adding: false
        stdout: StdioCollector {
            onStreamFinished: root.applyAction(text)
        }
        onExited: function(code, status) {
            root.acting = false
            if (code !== 0) root.actionError = "Помощник завершился с кодом " + code
        }
    }

    Timer {
        interval: (root.settings.refreshMinutes || 10) * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()

    IpcHandler {
        target: "dota-stats"
        function refresh(): void { root.refresh() }
        function next(): void { root.next() }
        function status(): string { return JSON.stringify({ready: root.ready, error: root.error, accounts: root.accounts.length}) }
    }
}
