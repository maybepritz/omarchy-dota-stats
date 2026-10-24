import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui

Ui.Panel {
    id: root
    moduleName: "maybepritz.dota-stats"
    manageIpc: false

    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    readonly property var accounts: service ? service.accounts : []
    readonly property var account: service ? service.current : null
    readonly property var prefs: service ? service.settings : ({refreshMinutes: 10, matches: 20, notify: true, barMode: "winrate"})
    readonly property bool available: service !== null && service.ready
    readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
    readonly property color dim: Commons.Color.muted
    readonly property color good: Commons.Color.accent
    readonly property color bad: Commons.Color.urgent
    readonly property string family: bar ? bar.fontFamily : Style.font.family
    readonly property var tabs: ["Обзор", "Матчи", "Герои", "Настройки"]
    property int tab: 0
    readonly property var totals: accounts.reduce(function(sum, a) {
        sum.wins += a.wins || 0
        sum.losses += a.losses || 0
        return sum
    }, {wins: 0, losses: 0})

    function rate(wins, losses) {
        var games = (wins || 0) + (losses || 0)
        return games > 0 ? Math.round(wins / games * 100) + "%" : "—"
    }
    function rateColor(wins, losses) {
        var games = (wins || 0) + (losses || 0)
        return games > 0 && wins / games >= 0.5 ? good : bad
    }
    function duration(seconds) {
        var total = Math.round(seconds || 0)
        if (total <= 0) return "—"
        return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0")
    }
    function ago(unix) {
        var minutes = Math.floor((Date.now() / 1000 - unix) / 60)
        if (minutes < 60) return minutes + " мин назад"
        if (minutes < 60 * 24) return Math.floor(minutes / 60) + " ч назад"
        return Math.floor(minutes / 1440) + " дн назад"
    }
    function rankName(tier) {
        var names = ["", "Herald", "Guardian", "Crusader", "Archon", "Legend", "Ancient", "Divine", "Immortal"]
        var medal = Math.floor(tier / 10)
        if (medal >= 8) return "Immortal"
        return (names[medal] || "?") + " " + (tier % 10)
    }
    function statValue(value) {
        return value > 0 ? String(value) : "—"
    }
    function fileUrl(path) {
        return path ? "file://" + path : ""
    }
    function cssColor(color, alpha) {
        return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255) + ","
            + Math.round(color.b * 255) + "," + alpha + ")"
    }
    function barText() {
        if (!available) return service && service.error ? "Dota ✕" : "Dota…"
        if (!account) return "Dota —"
        if (prefs.barMode === "rank") return "Dota " + account.rank
        if (prefs.barMode === "last") {
            var last = account.matches && account.matches.length > 0 ? account.matches[0] : null
            return last ? "Dota " + last.hero + " " + last.kills + "/" + last.deaths + "/" + last.assists : "Dota —"
        }
        return "Dota " + account.wins + "-" + account.losses + " " + rate(account.wins, account.losses)
    }
    function barDot() {
        if (!available || !account) return dim
        if (prefs.barMode === "rank") return good
        if (prefs.barMode === "last") return account.matches && account.matches.length > 0 && account.matches[0].win ? good : bad
        return rateColor(account.wins, account.losses)
    }

    implicitWidth: barLabel.implicitWidth + Style.space(20)
    implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

    Row {
        id: barLabel
        anchors.centerIn: parent
        spacing: Style.space(6)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6); height: width; radius: width / 2
            color: root.barDot()
        }
        Text {
            text: root.bar && root.bar.vertical ? "D" : root.barText()
            color: root.foreground
            font.family: root.family
            font.pixelSize: Style.font.body
        }
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(event) {
            if (event.button === Qt.RightButton && root.service) root.service.refresh()
            else if (event.button === Qt.MiddleButton && root.service) root.service.next()
            else root.toggle()
        }
        onEntered: if (root.bar) root.bar.showTooltip(root, root.account ? root.account.name + " · " + root.account.rank : "Dota 2")
        onExited: if (root.bar) root.bar.hideTooltip(root)
    }

    component Caption: Text {
        color: root.foreground
        font.family: root.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
    }
    component Action: Ui.Button {
        foreground: root.foreground
        fontFamily: root.family
        focusable: true
    }
    component Stat: ColumnLayout {
        property string label
        property string value
        property color valueColor: root.foreground
        Layout.fillWidth: true
        spacing: Style.space(1)
        Caption { text: label; color: root.dim; font.pixelSize: Style.font.caption }
        Caption { text: value; color: valueColor; font.pixelSize: Style.font.title; font.bold: true }
    }
    component Section: Caption {
        color: root.dim
        font.pixelSize: Style.font.caption
        font.bold: true
    }

    Connections {
        target: root.service
        function onAccountAdded() {
            idField.text = ""
            labelField.text = ""
        }
    }

    Ui.KeyboardPanel {
        id: popup
        anchorItem: root
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: content
        contentWidth: popup.fittedContentWidth(Style.space(500))
        contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(720))

        ColumnLayout {
            id: content
            anchors.fill: parent
            spacing: Style.space(12)
            focus: true
            Keys.onEscapePressed: root.close()

            PanelHero {
                Layout.fillWidth: true
                title: root.account ? (root.account.name || root.account.label) : "Dota 2"
                meta: root.account ? root.account.rank + (root.account.mmr ? " · " + root.account.mmr + " MMR" : "")
                    : root.service && root.service.loading ? "Обновление…" : "Аккаунты не добавлены"
                foreground: root.foreground
                fontFamily: root.family
                iconComponent: Component {
                    Rectangle {
                        width: Style.space(40); height: width
                        radius: Style.space(8)
                        color: Qt.alpha(root.good, 0.15)
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: root.fileUrl(root.account ? root.account.avatar : "")
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Caption {
                            anchors.centerIn: parent
                            visible: !root.account || !root.account.avatar
                            text: "D"
                            font.pixelSize: Style.font.title
                            font.bold: true
                        }
                    }
                }
                trailingControl: Component {
                    PanelActionButton {
                        iconText: "↻"
                        tooltipText: "Обновить"
                        foreground: root.foreground
                        enabled: root.service !== null && !root.service.loading
                        onClicked: root.service.refresh()
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Style.space(6)
                Repeater {
                    model: root.accounts
                    Action {
                        required property var modelData
                        required property int index
                        text: modelData.name || modelData.label
                        selected: root.service && root.service.selected === index
                        fontSize: Style.font.bodySmall
                        onClicked: root.service.selected = index
                    }
                }
                Action {
                    text: "+ Аккаунт"
                    fontSize: Style.font.bodySmall
                    onClicked: root.tab = 3
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)
                Repeater {
                    model: root.tabs
                    Action {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        text: modelData
                        selected: root.tab === index
                        fontSize: Style.font.bodySmall
                        onClicked: root.tab = index
                    }
                }
            }

            Caption {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.tab === 3 && root.service && root.service.actionError !== "" ? root.service.actionError
                    : root.service && root.service.error ? root.service.error : ""
                color: root.bad
                wrapMode: Text.Wrap
            }

            Flickable {
                id: scroller
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(body.implicitHeight, Style.space(480))
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: body
                    width: scroller.width
                    spacing: Style.space(12)

                    // Обзор
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.tab === 0
                        spacing: Style.space(12)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(4)
                            Repeater {
                                model: [{label: "7 дн", days: 7}, {label: "30 дн", days: 30}, {label: "Всё", days: 0}]
                                Action {
                                    required property var modelData
                                    text: modelData.label
                                    selected: root.service && root.service.days === modelData.days
                                    fontSize: Style.font.bodySmall
                                    onClicked: root.service.setDays(modelData.days)
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Repeater {
                                model: [{label: "Ranked", lobby: "ranked"}, {label: "Все", lobby: "all"}]
                                Action {
                                    required property var modelData
                                    text: modelData.label
                                    selected: root.service && root.service.lobby === modelData.lobby
                                    fontSize: Style.font.bodySmall
                                    onClicked: root.service.setLobby(modelData.lobby)
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: kpis.implicitHeight + Style.space(24)
                            radius: Style.cornerRadius
                            color: Qt.alpha(root.good, 0.09)
                            visible: root.account !== null

                            GridLayout {
                                id: kpis
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Style.space(12)
                                columns: 4
                                columnSpacing: Style.space(8)
                                Stat { label: "Винрейт"; value: root.account ? root.rate(root.account.wins, root.account.losses) : "—"; valueColor: root.account ? root.rateColor(root.account.wins, root.account.losses) : root.foreground }
                                Stat { label: "W / L"; value: root.account ? root.account.wins + " / " + root.account.losses : "—" }
                                Stat { label: "KDA"; value: root.account && root.account.summary ? String(root.account.summary.kda) : "—" }
                                Stat { label: "GPM"; value: root.account && root.account.summary ? root.statValue(root.account.summary.gpm) : "—" }
                            }
                        }

                        Caption {
                            Layout.fillWidth: true
                            visible: root.accounts.length > 1
                            text: "Все аккаунты: " + root.totals.wins + " W / " + root.totals.losses + " L · " + root.rate(root.totals.wins, root.totals.losses)
                            color: root.dim; font.pixelSize: Style.font.caption
                        }

                        Section {
                            visible: root.account !== null
                            text: "РЕЙТИНГ"
                        }
                        Canvas {
                            id: chart
                            Layout.fillWidth: true
                            Layout.preferredHeight: Style.space(110)
                            visible: !!root.account && !!root.account.rankHistory && root.account.rankHistory.length > 1
                            property var points: root.account && root.account.rankHistory ? root.account.rankHistory : []
                            onPointsChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var pts = points
                                if (!pts || pts.length < 2) return
                                var low = pts[0].tier, high = pts[0].tier
                                for (var i = 1; i < pts.length; i++) {
                                    low = Math.min(low, pts[i].tier)
                                    high = Math.max(high, pts[i].tier)
                                }
                                var pad = 6
                                var span = Math.max(1, high - low)
                                var last = pts.length - 1
                                function px(index) { return pad + index * (width - 2 * pad) / last }
                                function py(value) { return height - pad - (value - low) / span * (height - 2 * pad) }
                                ctx.beginPath()
                                ctx.moveTo(px(0), py(pts[0].tier))
                                for (var j = 1; j < pts.length; j++) ctx.lineTo(px(j), py(pts[j].tier))
                                ctx.lineTo(px(last), height)
                                ctx.lineTo(px(0), height)
                                ctx.closePath()
                                ctx.fillStyle = root.cssColor(root.good, 0.15)
                                ctx.fill()
                                ctx.beginPath()
                                ctx.moveTo(px(0), py(pts[0].tier))
                                for (var k = 1; k < pts.length; k++) ctx.lineTo(px(k), py(pts[k].tier))
                                ctx.strokeStyle = root.cssColor(root.good, 1)
                                ctx.lineWidth = 2
                                ctx.stroke()
                                ctx.fillStyle = root.cssColor(root.dim, 1)
                                ctx.font = "11px sans-serif"
                                ctx.fillText(root.rankName(high), pad, 12)
                                ctx.fillText(root.rankName(low), pad, height - 2)
                            }
                        }
                        Caption {
                            Layout.fillWidth: true
                            visible: !!root.account && (!root.account.rankHistory || root.account.rankHistory.length < 2)
                            text: "История рангов появится после ranked-игр за выбранный период"
                            color: root.dim; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap
                        }

                        Section {
                            visible: !!root.account && !!root.account.heroes && root.account.heroes.length > 0
                            text: "ТОП ГЕРОЕВ"
                        }
                        Repeater {
                            model: root.account && root.account.heroes ? root.account.heroes.slice(0, 5) : []
                            HeroRow {
                                required property var modelData
                                hero: modelData
                            }
                        }
                    }

                    // Матчи
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.tab === 1
                        spacing: Style.space(6)
                        Caption {
                            visible: !root.account || !root.account.matches || root.account.matches.length === 0
                            Layout.fillWidth: true
                            text: root.account ? "Игр за выбранный период нет" : "Нет данных"
                            color: root.dim
                        }
                        Repeater {
                            model: root.account ? root.account.matches : []
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: Style.space(40)
                                radius: Style.space(6)
                                color: Qt.alpha(root.foreground, 0.04)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.space(10)
                                    anchors.rightMargin: Style.space(12)
                                    spacing: Style.space(10)
                                    Rectangle { width: Style.space(4); height: Style.space(24); radius: 2; color: modelData.win ? root.good : root.bad }
                                    Image {
                                        Layout.preferredWidth: Style.space(28); Layout.preferredHeight: Style.space(28)
                                        source: root.fileUrl(modelData.icon)
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Caption { Layout.fillWidth: true; text: modelData.hero; elide: Text.ElideRight }
                                    Caption { text: modelData.kills + "/" + modelData.deaths + "/" + modelData.assists; font.pixelSize: Style.font.bodySmall }
                                    Caption { text: "GPM " + root.statValue(modelData.gpm); color: root.dim; font.pixelSize: Style.font.caption }
                                    Caption { text: root.duration(modelData.duration); color: root.dim; font.pixelSize: Style.font.caption }
                                    Caption { text: root.ago(modelData.startTime); color: root.dim; font.pixelSize: Style.font.caption }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://www.opendota.com/matches/" + modelData.matchId)
                                }
                            }
                        }
                    }

                    // Герои
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.tab === 2
                        spacing: Style.space(6)
                        Caption {
                            visible: !root.account || !root.account.heroes || root.account.heroes.length === 0
                            Layout.fillWidth: true
                            text: root.account ? "Игр за выбранный период нет" : "Нет данных"
                            color: root.dim
                        }
                        Repeater {
                            model: root.account && root.account.heroes ? root.account.heroes : []
                            HeroRow {
                                required property var modelData
                                hero: modelData
                                wide: true
                            }
                        }
                    }

                    // Настройки
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.tab === 3
                        spacing: Style.space(10)

                        Section { text: "АККАУНТЫ" }
                        Repeater {
                            model: root.accounts
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Style.space(10)
                                Rectangle {
                                    Layout.preferredWidth: Style.space(26); Layout.preferredHeight: Style.space(26)
                                    radius: Style.space(5)
                                    clip: true
                                    color: Qt.alpha(root.good, 0.15)
                                    Image {
                                        anchors.fill: parent
                                        source: root.fileUrl(modelData.avatar)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                                Caption { Layout.fillWidth: true; text: modelData.label; elide: Text.ElideRight }
                                Caption { text: modelData.id; color: root.dim; font.pixelSize: Style.font.caption }
                                Action {
                                    text: "Удалить"
                                    fontSize: Style.font.bodySmall
                                    enabled: root.service && !root.service.acting
                                    onClicked: root.service.removeAccount(modelData.id)
                                }
                            }
                        }
                        Caption {
                            visible: root.accounts.length === 0
                            Layout.fillWidth: true
                            text: "Аккаунтов пока нет. Введи Steam ID ниже."
                            color: root.dim; wrapMode: Text.Wrap
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            Ui.TextField {
                                id: idField
                                Layout.preferredWidth: Style.space(150)
                                placeholderText: "Steam ID"
                                foreground: root.foreground
                                accent: root.good
                                onAccepted: submit.clicked()
                            }
                            Ui.TextField {
                                id: labelField
                                Layout.fillWidth: true
                                placeholderText: "Название (необязательно)"
                                foreground: root.foreground
                                accent: root.good
                                onAccepted: submit.clicked()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Caption {
                                Layout.fillWidth: true
                                text: "32-битный ID или SteamID64. Профиль Dota 2 должен быть публичным."
                                color: root.dim; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap
                            }
                            Action {
                                id: submit
                                text: root.service && root.service.acting ? "Проверка…" : "Добавить"
                                enabled: idField.text.trim() !== "" && root.service !== null && !root.service.acting
                                onClicked: root.service.addAccount(idField.text, labelField.text)
                            }
                        }

                        PanelSeparator { Layout.fillWidth: true }

                        Section { text: "ОБНОВЛЕНИЕ И ДАННЫЕ" }
                        SettingRow {
                            label: "Обновлять каждые"
                            control: Component {
                                Dropdown {
                                    width: Style.space(150)
                                    foreground: root.foreground
                                    accent: root.good
                                    value: String(root.prefs.refreshMinutes)
                                    options: [
                                        {value: "5", label: "5 мин"}, {value: "10", label: "10 мин"},
                                        {value: "30", label: "30 мин"}, {value: "60", label: "60 мин"}
                                    ]
                                    onChanged: function(v) { root.service.setSetting("refreshMinutes", v) }
                                }
                            }
                        }
                        SettingRow {
                            label: "Матчей в сводке"
                            control: Component {
                                Dropdown {
                                    width: Style.space(150)
                                    foreground: root.foreground
                                    accent: root.good
                                    value: String(root.prefs.matches)
                                    options: [{value: "10", label: "10"}, {value: "20", label: "20"}, {value: "50", label: "50"}]
                                    onChanged: function(v) { root.service.setSetting("matches", v) }
                                }
                            }
                        }

                        PanelSeparator { Layout.fillWidth: true }

                        Section { text: "ПАНЕЛЬ И УВЕДОМЛЕНИЯ" }
                        SettingRow {
                            label: "Что показывать на панели"
                            control: Component {
                                Dropdown {
                                    width: Style.space(150)
                                    foreground: root.foreground
                                    accent: root.good
                                    value: root.prefs.barMode
                                    options: [
                                        {value: "winrate", label: "Винрейт"}, {value: "rank", label: "Ранг"},
                                        {value: "last", label: "Последняя игра"}
                                    ]
                                    onChanged: function(v) { root.service.setSetting("barMode", v) }
                                }
                            }
                        }
                        SettingRow {
                            label: "Уведомление после каждой игры"
                            control: Component {
                                ToggleSwitch {
                                    checked: !!root.prefs.notify
                                    foreground: root.foreground
                                    accent: root.good
                                    onToggled: root.service.setSetting("notify", !root.prefs.notify)
                                }
                            }
                        }
                        Caption {
                            Layout.fillWidth: true
                            text: "Лимит OpenDota без ключа — 2000 запросов в сутки. Профиль и рейтинг кэшируются, поэтому при обновлении раз в 10 минут на 3 аккаунта хватает с запасом."
                            color: root.dim; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap
                        }
                    }
                }
            }

            Caption {
                Layout.fillWidth: true
                text: root.service && root.service.ready && root.service.snapshot.updated
                    ? "Данные OpenDota · " + root.ago(root.service.snapshot.updated) : ""
                color: root.dim; font.pixelSize: Style.font.caption
            }
        }
    }

    // One hero line: portrait, name, games, win rate and KDA. The wide variant adds a win-rate bar.
    component HeroRow: RowLayout {
        property var hero: ({})
        property bool wide: false
        Layout.fillWidth: true
        spacing: Style.space(10)
        Rectangle {
            Layout.preferredWidth: Style.space(wide ? 56 : 44)
            Layout.preferredHeight: Style.space(wide ? 32 : 26)
            radius: Style.space(4)
            clip: true
            color: Qt.alpha(root.foreground, 0.06)
            Image {
                anchors.fill: parent
                source: root.fileUrl(hero.portrait)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        Caption { Layout.fillWidth: true; text: hero.hero; elide: Text.ElideRight }
        Caption { text: hero.games + " игр"; color: root.dim; font.pixelSize: Style.font.caption }
        Rectangle {
            visible: wide
            Layout.preferredWidth: Style.space(90)
            Layout.preferredHeight: Style.space(6)
            radius: height / 2
            color: Qt.alpha(root.foreground, 0.1)
            Rectangle {
                width: parent.width * (hero.games > 0 ? hero.wins / hero.games : 0)
                height: parent.height
                radius: parent.radius
                color: root.rateColor(hero.wins, hero.games - hero.wins)
            }
        }
        Caption {
            text: root.rate(hero.wins, hero.games - hero.wins)
            color: root.rateColor(hero.wins, hero.games - hero.wins)
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: Style.space(44)
        }
        Caption {
            visible: wide
            text: hero.kda !== null && hero.kda !== undefined ? hero.kda + " KDA" : "—"
            color: root.dim; font.pixelSize: Style.font.caption
            Layout.preferredWidth: Style.space(60)
            horizontalAlignment: Text.AlignRight
        }
    }

    // A label on the left and a control on the right, used in the settings tab.
    component SettingRow: RowLayout {
        property string label: ""
        property Component control: null
        Layout.fillWidth: true
        spacing: Style.space(10)
        Caption { Layout.fillWidth: true; text: parent.label; wrapMode: Text.Wrap }
        Loader { sourceComponent: parent.control }
    }
}
