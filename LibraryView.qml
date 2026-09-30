import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// A biblioteca: os wallpapers da pasta num carrossel inclinado.
FocusScope {
    id: view

    required property var hub
    property string screenName: ""

    readonly property int cardW: 250
    // Encolhe quando a barra de filtros come altura, para o card grande não
    // passar por cima do rodapé.
    readonly property int cardH: Math.max(220, Math.min(380, Math.floor(list.height / 1.25)))
    readonly property real skew: -0.28
    readonly property real skewPad: Math.abs(skew) * cardH / 2

    property string searchText: ""
    property bool searching: false
    property bool favoritesOnly: false
    property bool filtersOpen: false
    property string colorFilter: ""
    property string tagFilter: ""
    readonly property bool anyFilter: favoritesOnly || colorFilter !== "" || tagFilter !== "" || searchText.trim() !== ""
    property string confirmName: ""
    property string pendingSelect: ""
    property var entries: []
    readonly property var current: (list.currentIndex >= 0 && list.currentIndex < entries.length) ? entries[list.currentIndex] : null
    readonly property var colorDefs: [
        {
            key: "red",
            label: "vermelho",
            hex: "#E5484D"
        },
        {
            key: "orange",
            label: "laranja",
            hex: "#F76B15"
        },
        {
            key: "yellow",
            label: "amarelo",
            hex: "#FFC53D"
        },
        {
            key: "green",
            label: "verde",
            hex: "#30A46C"
        },
        {
            key: "teal",
            label: "turquesa",
            hex: "#12A594"
        },
        {
            key: "blue",
            label: "azul",
            hex: "#3E63DD"
        },
        {
            key: "purple",
            label: "roxo",
            hex: "#8E4EC6"
        },
        {
            key: "pink",
            label: "rosa",
            hex: "#E93D82"
        },
        {
            key: "dark",
            label: "escuro",
            hex: "#1C1C1F"
        },
        {
            key: "light",
            label: "claro",
            hex: "#F0F0F0"
        },
        {
            key: "gray",
            label: "cinza",
            hex: "#8B8D98"
        }
    ]

    readonly property var colorCounts: {
        const c = {};
        for (const n of hub.names)
            for (const k of (hub.colors[n] || []))
                c[k] = (c[k] || 0) + 1;
        return c;
    }

    readonly property var topTags: {
        const c = {};
        for (const n of hub.names)
            for (const t of (hub.tags[n] || []))
                c[t] = (c[t] || 0) + 1;
        return Object.keys(c).sort((a, b) => c[b] - c[a] || a.localeCompare(b)).slice(0, 8).map(t => ({
                    tag: t,
                    count: c[t]
                }));
    }

    // Percorre "sem filtro" e as opções, para filtrar só pelo teclado.
    function cycle(options, current, step) {
        const i = options.indexOf(current);
        return options[(i + step + options.length) % options.length];
    }

    function cycleColor(step) {
        filtersOpen = true;
        colorFilter = cycle([""].concat(colorDefs.map(c => c.key)), colorFilter, step);
    }

    function cycleTag() {
        filtersOpen = true;
        tagFilter = cycle([""].concat(topTags.map(t => t.tag)), tagFilter, 1);
    }

    function clearFilters() {
        colorFilter = "";
        tagFilter = "";
        favoritesOnly = false;
    }

    readonly property bool currentIsFavorite: !!current && !!hub.favoriteSet[current.name]

    function focusList() {
        list.forceActiveFocus();
    }

    // Ao abrir: sem filtro, com o wallpaper em uso no centro.
    function reset() {
        searching = false;
        searchText = "";
        searchBox.text = "";
        confirmName = "";
        clearFilters();
        filtersOpen = false;
        pendingSelect = hub.currentName;
        rebuild();
    }

    ListModel {
        id: shown
    }

    // Põe `out` no modelo. Se só sumiu um item (exclusão), remove essa linha e
    // o ListView mantém a posição sozinho; trocar o modelo inteiro o zeraria.
    function sync(out) {
        if (out.length === entries.length - 1) {
            let i = 0;
            while (i < out.length && out[i].name === entries[i].name)
                i++;
            let rest = true;
            for (let j = i; j < out.length; j++) {
                if (out[j].name !== entries[j + 1].name) {
                    rest = false;
                    break;
                }
            }
            if (rest) {
                entries = out;
                shown.remove(i);
                return "removed";
            }
        }
        if (out.length === entries.length && out.every((e, i) => e.name === entries[i].name))
            return "same";
        entries = out;
        shown.clear();
        for (const e of out)
            shown.append({
                fileName: e.name
            });
        return "reset";
    }

    function rebuild() {
        const keep = pendingSelect || (current ? current.name : "");
        const previous = Math.max(list.currentIndex, 0);
        const q = searchText.trim().toLowerCase();
        const out = [];
        for (const n of hub.names) {
            if (favoritesOnly && !hub.favoriteSet[n])
                continue;
            const nTags = hub.tags[n] || [];
            if (colorFilter && (hub.colors[n] || []).indexOf(colorFilter) < 0)
                continue;
            if (tagFilter && nTags.indexOf(tagFilter) < 0)
                continue;
            if (q && n.toLowerCase().indexOf(q) < 0 && !nTags.some(t => t.toLowerCase().indexOf(q) >= 0))
                continue;
            out.push({
                name: n
            });
        }
        const how = sync(out);
        let idx = out.findIndex(e => e.name === keep);
        if (idx >= 0) {
            pendingSelect = "";
        } else if (how !== "same") {
            idx = Math.min(previous, out.length - 1);
        } else {
            return;
        }
        if (idx !== list.currentIndex)
            list.currentIndex = idx;
        if (idx >= 0)
            list.positionViewAtIndex(idx, ListView.Center);
    }

    onSearchTextChanged: rebuild()
    onFavoritesOnlyChanged: rebuild()
    onColorFilterChanged: rebuild()
    onTagFilterChanged: rebuild()

    Connections {
        target: view.hub
        function onNamesChanged() {
            view.rebuild();
        }
        function onFavoritesChanged() {
            if (view.favoritesOnly)
                view.rebuild();
        }
        function onColorsChanged() {
            if (view.colorFilter)
                view.rebuild();
        }
        function onTagsChanged() {
            if (view.tagFilter || view.searchText)
                view.rebuild();
        }
        function onDownloaded(name) {
            view.pendingSelect = name;
            view.rebuild();
        }
    }

    function neighbour() {
        if (entries.length < 2)
            return "";
        const i = list.currentIndex;
        return entries[i + 1 < entries.length ? i + 1 : i - 1].name;
    }

    function applyCurrent() {
        if (!current)
            return;
        hub.apply(current.name, screenName);
        hub.close();
    }

    function startDelete() {
        if (current)
            confirmName = current.name;
    }

    function confirmDelete() {
        const name = confirmName;
        confirmName = "";
        hub.deleteWallpaper(name, neighbour());
    }

    function openSearch() {
        searching = true;
        searchBox.focusInput();
    }

    function closeSearch() {
        searching = false;
        searchText = "";
        searchBox.text = "";
        list.forceActiveFocus();
    }

    // ── Barra de cima ─────────────────────────────────────────────────────
    Item {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 32
        height: 64

        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            StyledText {
                text: "Wallpapers"
                color: "#F2F2F2"
                font.pixelSize: Theme.fontSizeXLarge
                font.weight: Font.Bold
            }
            StyledText {
                text: (view.anyFilter ? view.entries.length + " de " : "") + view.hub.names.length + " na pasta · " + view.hub.favoriteCount + " favoritos" + (view.hub.cycleCountdown ? " · " + view.hub.cycleCountdown : "")
                color: "#F2F2F2"
                opacity: 0.6
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        HubSearch {
            id: searchBox
            visible: view.searching
            width: 320
            anchors.centerIn: parent
            placeholder: "Filtrar pelo nome"
            onTextChanged: view.searchText = text
            onAccepted: list.forceActiveFocus()
            onEscaped: view.closeSearch()
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            HubButton {
                icon: "search"
                active: view.searching
                onClicked: view.searching ? view.closeSearch() : view.openSearch()
            }
            HubButton {
                icon: "palette"
                label: "Filtros"
                hint: "C"
                active: view.filtersOpen || view.colorFilter !== "" || view.tagFilter !== ""
                onClicked: {
                    view.filtersOpen = !view.filtersOpen;
                    list.forceActiveFocus();
                }
            }
            HubButton {
                icon: "star"
                filledIcon: true
                label: "Só favoritos"
                active: view.favoritesOnly
                onClicked: {
                    view.favoritesOnly = !view.favoritesOnly;
                    list.forceActiveFocus();
                }
            }
            HubButton {
                icon: "shuffle"
                label: view.hub.favoritesRandom ? "Aleatório dos favoritos: ligado" : "Aleatório dos favoritos"
                active: view.hub.favoritesRandom
                onClicked: {
                    view.hub.setFavoritesRandom(!view.hub.favoritesRandom);
                    list.forceActiveFocus();
                }
            }
            HubButton {
                icon: "add_photo_alternate"
                label: "Adicionar"
                hint: "A"
                onClicked: view.hub.showDiscover()
            }
            HubButton {
                icon: "close"
                onClicked: view.hub.close()
            }
        }
    }

    // ── Filtros: cor e etiqueta ───────────────────────────────────────────
    Item {
        id: filterBar
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        height: view.filtersOpen ? filterFlow.implicitHeight + 12 : 0
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: 150
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        Flow {
            id: filterFlow
            width: parent.width
            spacing: 8

            Repeater {
                model: view.colorDefs
                delegate: Rectangle {
                    id: dot
                    required property var modelData
                    readonly property int count: view.colorCounts[modelData.key] || 0
                    readonly property bool picked: view.colorFilter === modelData.key
                    width: 32
                    height: 32
                    radius: 16
                    color: modelData.hex
                    opacity: count === 0 && !picked ? 0.25 : 1
                    border.width: picked ? 3 : 1
                    border.color: picked ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.3)
                    scale: dotMouse.containsMouse || picked ? 1.12 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                        }
                    }

                    MouseArea {
                        id: dotMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.colorFilter = dot.picked ? "" : dot.modelData.key;
                            list.forceActiveFocus();
                        }
                    }
                }
            }

            StyledText {
                height: 32
                verticalAlignment: Text.AlignVCenter
                leftPadding: 4
                rightPadding: 12
                color: "#F2F2F2"
                opacity: 0.7
                font.pixelSize: Theme.fontSizeSmall
                text: {
                    if (view.colorFilter) {
                        const d = view.colorDefs.find(c => c.key === view.colorFilter);
                        return d.label + " · " + (view.colorCounts[d.key] || 0);
                    }
                    return view.hub.analyzing ? "analisando as cores…" : Object.keys(view.hub.colors).length === 0 ? "" : "cor";
                }
            }

            Repeater {
                model: view.topTags
                delegate: HubButton {
                    required property var modelData
                    implicitHeight: 32
                    label: modelData.tag
                    hint: String(modelData.count)
                    active: view.tagFilter === modelData.tag
                    onClicked: {
                        view.tagFilter = view.tagFilter === modelData.tag ? "" : modelData.tag;
                        list.forceActiveFocus();
                    }
                }
            }

            StyledText {
                visible: view.topTags.length === 0
                height: 32
                verticalAlignment: Text.AlignVCenter
                leftPadding: 12
                color: "#F2F2F2"
                opacity: 0.45
                font.pixelSize: Theme.fontSizeSmall
                text: "Etiquetas aparecem para o que vem do Wallhaven."
            }

            HubButton {
                visible: view.colorFilter !== "" || view.tagFilter !== ""
                implicitHeight: 32
                icon: "close"
                label: "Limpar"
                onClicked: {
                    view.colorFilter = "";
                    view.tagFilter = "";
                    list.forceActiveFocus();
                }
            }
        }
    }

    // ── Carrossel ─────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: filterBar.bottom
        anchors.bottom: bottomBar.top
        orientation: ListView.Horizontal
        spacing: 10
        model: shown
        clip: false
        cacheBuffer: view.cardW * 8
        keyNavigationEnabled: false
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: width / 2 - view.cardW / 2
        preferredHighlightEnd: width / 2 + view.cardW / 2
        highlightMoveDuration: 220
        focus: true

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                if (event.angleDelta.y + event.angleDelta.x > 0)
                    list.decrementCurrentIndex();
                else
                    list.incrementCurrentIndex();
            }
        }

        Keys.onPressed: event => {
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                return;
            if (view.confirmName !== "") {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Y)
                    view.confirmDelete();
                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_N)
                    view.confirmName = "";
                event.accepted = true;
                return;
            }
            event.accepted = true;
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_H:
                list.decrementCurrentIndex();
                break;
            case Qt.Key_Right:
            case Qt.Key_L:
                list.incrementCurrentIndex();
                break;
            case Qt.Key_PageUp:
                list.currentIndex = Math.max(0, list.currentIndex - 5);
                break;
            case Qt.Key_PageDown:
                list.currentIndex = Math.min(list.count - 1, list.currentIndex + 5);
                break;
            case Qt.Key_Home:
                list.currentIndex = 0;
                break;
            case Qt.Key_End:
                list.currentIndex = list.count - 1;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                view.applyCurrent();
                break;
            case Qt.Key_F:
                if (view.current)
                    view.hub.toggleFavorite(view.current.name);
                break;
            case Qt.Key_Delete:
            case Qt.Key_D:
                view.startDelete();
                break;
            case Qt.Key_Slash:
                view.openSearch();
                break;
            case Qt.Key_Tab:
                view.favoritesOnly = !view.favoritesOnly;
                break;
            case Qt.Key_R:
                view.hub.setFavoritesRandom(!view.hub.favoritesRandom);
                break;
            case Qt.Key_C:
                view.filtersOpen = !view.filtersOpen;
                break;
            case Qt.Key_Comma:
                view.cycleColor(-1);
                break;
            case Qt.Key_Period:
                view.cycleColor(1);
                break;
            case Qt.Key_T:
                view.cycleTag();
                break;
            case Qt.Key_A:
                view.hub.showDiscover();
                break;
            case Qt.Key_Escape:
                if (view.searchText !== "" || view.searching)
                    view.closeSearch();
                else if (view.colorFilter !== "" || view.tagFilter !== "")
                    view.clearFilters();
                else
                    view.hub.close();
                break;
            default:
                event.accepted = false;
            }
        }

        delegate: Item {
            id: card

            required property int index
            required property string fileName

            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property int dist: Math.abs(index - list.currentIndex)
            readonly property bool isFavorite: !!view.hub.favoriteSet[fileName]
            readonly property bool inUse: fileName === view.hub.currentName

            width: view.cardW
            height: list.height

            Item {
                id: shape
                width: view.cardW
                height: view.cardH
                anchors.centerIn: parent
                scale: isCurrent ? 1.12 : (mouse.containsMouse ? 0.95 : 0.84)
                opacity: isCurrent ? 1 : (mouse.containsMouse ? 0.95 : Math.max(0.3, 0.8 - dist * 0.12))

                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                // Corta o paralelogramo: o retângulo é entortado, e o conteúdo
                // é entortado de volta para a imagem aparecer em pé.
                transform: Matrix4x4 {
                    matrix: Qt.matrix4x4(1, view.skew, 0, -view.skew * view.cardH / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }

                Item {
                    anchors.fill: parent
                    clip: true

                    Item {
                        id: upright
                        x: -view.skewPad
                        width: view.cardW + 2 * view.skewPad
                        height: view.cardH

                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(1, -view.skew, 0, view.skew * view.cardH / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "#1A1A1A"
                        }

                        Image {
                            anchors.fill: parent
                            source: view.hub.urlFor(card.fileName)
                            sourceSize: Qt.size(view.cardW * 2, view.cardH * 2)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }

                        Rectangle {
                            id: star
                            x: view.skewPad + view.cardW + Math.abs(view.skew) * (view.cardH / 2 - 44) - width - 8
                            y: 10
                            width: 34
                            height: 34
                            radius: 17
                            color: card.isFavorite ? Theme.primary : Qt.rgba(0, 0, 0, 0.45)
                            visible: card.isFavorite || card.isCurrent || mouse.containsMouse

                            DankIcon {
                                anchors.centerIn: parent
                                name: "star"
                                size: 20
                                filled: card.isFavorite
                                color: card.isFavorite ? Theme.onPrimary : "#F2F2F2"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.hub.toggleFavorite(card.fileName)
                            }
                        }

                        Rectangle {
                            x: view.skewPad + Math.abs(view.skew) * (view.cardH / 2 - 10) + 10
                            y: 10
                            height: 26
                            width: inUseLabel.implicitWidth + 20
                            radius: 13
                            color: Qt.rgba(0, 0, 0, 0.55)
                            visible: card.inUse

                            StyledText {
                                id: inUseLabel
                                anchors.centerIn: parent
                                text: "em uso"
                                color: "#F2F2F2"
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: card.isCurrent ? 3 : 0
                        border.color: Theme.primary
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (card.isCurrent)
                            view.applyCurrent();
                        else
                            list.currentIndex = card.index;
                    }
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: list
        visible: view.entries.length === 0
        color: "#F2F2F2"
        opacity: 0.7
        font.pixelSize: Theme.fontSizeLarge
        text: view.favoritesOnly && view.colorFilter === "" && view.tagFilter === "" ? "Nenhum favorito ainda. Aperte F sobre um wallpaper." : view.anyFilter ? "Nada com esses filtros." : "A pasta está vazia. Aperte A para baixar do Wallhaven."
    }

    // ── Barra de baixo ────────────────────────────────────────────────────
    Item {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 32
        height: 150

        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            spacing: 6

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, bottomBar.width - 64)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                text: view.confirmName !== "" ? "Mandar “" + view.confirmName + "” para a lixeira?" : (view.current ? view.current.name : "")
                color: "#F2F2F2"
                font.pixelSize: Theme.fontSizeXLarge
                font.weight: Font.Medium
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: view.current !== null
                text: (list.currentIndex + 1) + " de " + list.count + (view.currentIsFavorite ? " · favorito" : "") + (view.current && view.current.name === view.hub.currentName ? " · em uso" : "")
                color: "#F2F2F2"
                opacity: 0.6
                font.pixelSize: Theme.fontSizeMedium
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                topPadding: 8

                HubButton {
                    visible: view.confirmName === "" && view.current !== null
                    icon: "wallpaper"
                    label: "Usar"
                    hint: "Enter"
                    active: true
                    onClicked: view.applyCurrent()
                }
                HubButton {
                    visible: view.confirmName === "" && view.current !== null
                    icon: "star"
                    filledIcon: view.currentIsFavorite
                    label: view.currentIsFavorite ? "Desfavoritar" : "Favoritar"
                    hint: "F"
                    onClicked: view.hub.toggleFavorite(view.current.name)
                }
                HubButton {
                    visible: view.confirmName === "" && view.current !== null
                    icon: "delete"
                    label: "Excluir"
                    hint: "Del"
                    danger: true
                    onClicked: view.startDelete()
                }
                HubButton {
                    visible: view.confirmName !== ""
                    icon: "delete"
                    label: "Mandar para a lixeira"
                    hint: "Enter"
                    danger: true
                    onClicked: view.confirmDelete()
                }
                HubButton {
                    visible: view.confirmName !== ""
                    label: "Cancelar"
                    hint: "Esc"
                    onClicked: view.confirmName = ""
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: "← → navegar    Enter usar    F favorito    Del excluir    / buscar    C filtros (, . cor  T etiqueta)    Tab só favoritos    R aleatório dos favoritos    A adicionar    Esc fechar"
            color: "#F2F2F2"
            opacity: 0.4
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
