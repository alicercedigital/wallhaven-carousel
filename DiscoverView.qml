import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// Adicionar wallpapers: busca no Wallhaven (só SFW). Escolher um abre os
// controles; baixar põe o arquivo na pasta e, se quiser, já usa e favorita.
FocusScope {
    id: view

    required property var hub

    readonly property string api: "https://wallhaven.cc/api/v1"
    readonly property int detailW: 440

    property string query: ""
    property string categories: "111"
    property string sorting: "toplist"
    property string atleast: "1920x1080"
    property int page: 1
    property int lastPage: 1
    property int total: -1
    property string seed: ""
    property bool loading: false
    property string errorText: ""
    property int serial: 0
    property bool loaded: false

    ListModel {
        id: results
    }

    readonly property var selected: (grid.currentIndex >= 0 && grid.currentIndex < results.count) ? results.get(grid.currentIndex) : null
    readonly property bool selectedInLibrary: !!selected && !!hub.nameSet[selected.fileName]
    readonly property bool selectedBusy: !!selected && !!hub.downloading[selected.wid]
    readonly property bool selectedIsFavorite: !!selected && !!hub.favoriteSet[selected.fileName]

    // Detalhes do selecionado (etiquetas, visualizações), buscados sob demanda.
    property string detailFor: ""
    property var detail: ({})

    function focusGrid() {
        grid.forceActiveFocus();
    }

    function enter() {
        if (!loaded)
            search();
    }

    function leave() {
        hub.showLibrary();
    }

    function url(pageNumber) {
        const p = [];
        p.push("categories=" + categories);
        p.push("purity=100");
        p.push("sorting=" + sorting);
        if (query.trim() !== "")
            p.push("q=" + encodeURIComponent(query.trim()));
        if (atleast !== "")
            p.push("atleast=" + atleast);
        if (sorting === "toplist")
            p.push("topRange=1M");
        p.push("order=desc");
        p.push("page=" + pageNumber);
        if (sorting === "random" && seed !== "" && pageNumber > 1)
            p.push("seed=" + seed);
        return api + "/search?" + p.join("&");
    }

    function curl(target) {
        return ["curl", "-fsSL", "--connect-timeout", "10", "--max-time", "30", "--retry", "2", "--retry-all-errors", "-A", "wallpaperHub/0.1", target];
    }

    function explain(out, code) {
        if (code === 22)
            return "O Wallhaven recusou o pedido (limite de buscas por minuto?). Espere um pouco.";
        if (code === 6 || code === 7 || code === 28)
            return "Sem conexão com o Wallhaven.";
        return "O Wallhaven não respondeu (curl " + code + ").";
    }

    function search() {
        const mine = ++serial;
        page = 1;
        loading = true;
        errorText = "";
        loaded = true;
        results.clear();
        grid.currentIndex = -1;
        Proc.runCommand("wallpaperHub.search", curl(url(1)), (out, code) => {
            if (mine !== view.serial)
                return;
            view.loading = false;
            if (code !== 0) {
                view.errorText = view.explain(out, code);
                return;
            }
            view.take(out);
            if (results.count > 0)
                grid.currentIndex = 0;
        }, 0, 40000, view);
    }

    function loadMore() {
        if (loading || page >= lastPage || results.count === 0)
            return;
        const mine = ++serial;
        const next = page + 1;
        loading = true;
        Proc.runCommand("wallpaperHub.search", curl(url(next)), (out, code) => {
            if (mine !== view.serial)
                return;
            view.loading = false;
            if (code !== 0) {
                view.errorText = view.explain(out, code);
                return;
            }
            view.page = next;
            view.take(out);
        }, 0, 40000, view);
    }

    function take(text) {
        let js;
        try {
            js = JSON.parse(text);
        } catch (e) {
            errorText = "Resposta inválida do Wallhaven.";
            return;
        }
        if (!js.data) {
            errorText = js.error ? String(js.error) : "Resposta inesperada do Wallhaven.";
            return;
        }
        if (js.meta) {
            lastPage = js.meta.last_page || 1;
            total = js.meta.total !== undefined ? js.meta.total : -1;
            if (js.meta.seed)
                seed = js.meta.seed;
        }
        for (const it of js.data) {
            const ext = String(it.path).split(".").pop();
            results.append({
                wid: String(it.id),
                thumb: String((it.thumbs && (it.thumbs.large || it.thumbs.small)) || it.path),
                full: String(it.path),
                resolution: String(it.resolution || ""),
                size: Number(it.file_size || 0),
                category: String(it.category || ""),
                colors: (it.colors || []).join(","),
                views: Number(it.views || 0),
                favs: Number(it.favorites || 0),
                fileName: "wallhaven-" + it.id + "." + ext
            });
        }
    }

    function fetchDetail(wid) {
        if (detailFor === wid)
            return;
        detailFor = wid;
        detail = ({});
        Proc.runCommand("wallpaperHub.detail", curl(api + "/w/" + wid), (out, code) => {
            if (code !== 0 || view.detailFor !== wid)
                return;
            try {
                const d = JSON.parse(out).data;
                view.detail = {
                    tags: (d.tags || []).map(t => t.name),
                    uploader: d.uploader ? d.uploader.username : ""
                };
            } catch (e) {}
        }, 250, 30000, view);
    }

    onSelectedChanged: {
        if (selected)
            fetchDetail(selected.wid);
    }

    function item() {
        return {
            wid: selected.wid,
            full: selected.full,
            fileName: selected.fileName
        };
    }

    function downloadSelected(thenApply, thenFavorite) {
        if (selected)
            hub.download(item(), thenApply, thenFavorite);
    }

    function megabytes(b) {
        return (b / 1048576).toFixed(1) + " MB";
    }

    function toggleCategory(i) {
        const c = categories.split("");
        c[i] = c[i] === "1" ? "0" : "1";
        if (c.join("") === "000")
            return;
        categories = c.join("");
        search();
    }

    // ── Cabeçalho: voltar, busca e filtros ────────────────────────────────
    Item {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 32
        height: 112

        MouseArea {
            anchors.fill: parent
        }

        HubButton {
            id: back
            icon: "arrow_back"
            label: "Biblioteca"
            hint: "Esc"
            onClicked: view.leave()
        }

        StyledText {
            anchors.left: back.right
            anchors.leftMargin: 16
            anchors.verticalCenter: back.verticalCenter
            text: "Wallhaven"
            color: "#F2F2F2"
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Font.Bold
        }

        HubSearch {
            id: searchBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: back.verticalCenter
            width: 420
            placeholder: "Buscar no Wallhaven (Enter)"
            text: view.query
            onAccepted: {
                view.query = text;
                view.search();
                grid.forceActiveFocus();
            }
            onEscaped: grid.forceActiveFocus()
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: back.verticalCenter
            spacing: 10

            HubButton {
                icon: "close"
                onClicked: view.hub.close()
            }
        }

        Flow {
            id: filters
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 8

            Repeater {
                model: [
                    {
                        label: "Geral",
                        i: 0
                    },
                    {
                        label: "Anime",
                        i: 1
                    },
                    {
                        label: "Pessoas",
                        i: 2
                    }
                ]
                delegate: HubButton {
                    required property var modelData
                    implicitHeight: 32
                    label: modelData.label
                    active: view.categories[modelData.i] === "1"
                    onClicked: view.toggleCategory(modelData.i)
                }
            }

            Item {
                width: 16
                height: 1
            }

            Repeater {
                model: [
                    {
                        label: "Top do mês",
                        v: "toplist"
                    },
                    {
                        label: "Recentes",
                        v: "date_added"
                    },
                    {
                        label: "Mais vistos",
                        v: "views"
                    },
                    {
                        label: "Mais favoritados",
                        v: "favorites"
                    },
                    {
                        label: "Relevância",
                        v: "relevance"
                    },
                    {
                        label: "Aleatório",
                        v: "random"
                    }
                ]
                delegate: HubButton {
                    required property var modelData
                    implicitHeight: 32
                    label: modelData.label
                    active: view.sorting === modelData.v
                    onClicked: {
                        view.sorting = modelData.v;
                        view.search();
                    }
                }
            }

            Item {
                width: 16
                height: 1
            }

            Repeater {
                model: [
                    {
                        label: "Qualquer tamanho",
                        v: ""
                    },
                    {
                        label: "1080p+",
                        v: "1920x1080"
                    },
                    {
                        label: "1440p+",
                        v: "2560x1440"
                    },
                    {
                        label: "4K+",
                        v: "3840x2160"
                    }
                ]
                delegate: HubButton {
                    required property var modelData
                    implicitHeight: 32
                    label: modelData.label
                    active: view.atleast === modelData.v
                    onClicked: {
                        view.atleast = modelData.v;
                        view.search();
                    }
                }
            }
        }
    }

    // ── Grade de resultados ───────────────────────────────────────────────
    GridView {
        id: grid
        anchors.top: head.bottom
        anchors.topMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: detailPanel.left
        anchors.rightMargin: 24
        clip: true
        focus: true
        model: results
        cacheBuffer: 600
        keyNavigationEnabled: true
        highlightMoveDuration: 0

        readonly property int cols: Math.max(1, Math.round(width / 230))
        cellWidth: Math.floor(width / cols)
        cellHeight: Math.round(cellWidth * 0.62)

        onAtYEndChanged: if (atYEnd)
            view.loadMore()

        Keys.onPressed: event => {
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                return;
            event.accepted = true;
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (view.selectedInLibrary)
                    view.hub.apply(view.selected.fileName);
                else
                    view.downloadSelected(true, false);
                break;
            case Qt.Key_F:
                if (view.selectedInLibrary)
                    view.hub.toggleFavorite(view.selected.fileName);
                else
                    view.downloadSelected(true, true);
                break;
            case Qt.Key_D:
                view.downloadSelected(false, false);
                break;
            case Qt.Key_Slash:
                searchBox.focusInput();
                break;
            case Qt.Key_Escape:
                view.leave();
                break;
            default:
                event.accepted = false;
            }
        }

        delegate: Item {
            id: cell

            required property int index
            required property string wid
            required property string thumb
            required property string resolution
            required property string fileName

            width: grid.cellWidth
            height: grid.cellHeight

            readonly property bool current: GridView.isCurrentItem
            readonly property bool inLibrary: !!view.hub.nameSet[fileName]
            readonly property bool busy: !!view.hub.downloading[wid]
            readonly property bool fav: !!view.hub.favoriteSet[fileName]

            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: 5
                radius: 10
                color: "#1A1A1A"
                border.width: cell.current ? 3 : 0
                border.color: Theme.primary

                Image {
                    anchors.fill: parent
                    source: cell.thumb
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: cell.busy ? 0.5 : 1
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    height: 22
                    width: resLabel.implicitWidth + 16
                    radius: 11
                    color: Qt.rgba(0, 0, 0, 0.6)

                    StyledText {
                        id: resLabel
                        anchors.centerIn: parent
                        text: cell.resolution
                        color: "#F2F2F2"
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        visible: cell.fav
                        width: 26
                        height: 26
                        radius: 13
                        color: Theme.primary
                        DankIcon {
                            anchors.centerIn: parent
                            name: "star"
                            filled: true
                            size: 16
                            color: Theme.onPrimary
                        }
                    }
                    Rectangle {
                        visible: cell.inLibrary || cell.busy
                        width: 26
                        height: 26
                        radius: 13
                        color: Qt.rgba(0, 0, 0, 0.6)
                        DankIcon {
                            anchors.centerIn: parent
                            name: cell.busy ? "downloading" : "check_circle"
                            size: 18
                            color: "#F2F2F2"
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        grid.currentIndex = cell.index;
                        grid.forceActiveFocus();
                    }
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: grid
        visible: results.count === 0
        color: "#F2F2F2"
        opacity: 0.7
        font.pixelSize: Theme.fontSizeLarge
        horizontalAlignment: Text.AlignHCenter
        width: grid.width - 48
        wrapMode: Text.WordWrap
        text: view.errorText !== "" ? view.errorText : view.loading ? "Buscando…" : "Nada encontrado."
    }

    StyledText {
        anchors.horizontalCenter: grid.horizontalCenter
        anchors.bottom: grid.bottom
        visible: view.loading && results.count > 0
        text: "Carregando mais…"
        color: "#F2F2F2"
        opacity: 0.6
        font.pixelSize: Theme.fontSizeSmall
    }

    // ── Painel do wallpaper escolhido ─────────────────────────────────────
    Rectangle {
        id: detailPanel
        anchors.top: head.bottom
        anchors.topMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        width: view.detailW
        radius: 16
        color: Qt.rgba(1, 1, 1, 0.06)

        MouseArea {
            anchors.fill: parent
        }

        Column {
            visible: view.selected !== null
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            ClippingRectangle {
                width: parent.width
                height: Math.round(width * 0.62)
                radius: 10
                color: "#1A1A1A"

                Image {
                    anchors.fill: parent
                    source: view.selected ? view.selected.thumb : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            StyledText {
                width: parent.width
                text: view.selected ? view.selected.resolution + "  ·  " + view.megabytes(view.selected.size) + "  ·  " + view.selected.category : ""
                color: "#F2F2F2"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
            }

            StyledText {
                width: parent.width
                text: view.selected ? view.selected.views + " visualizações  ·  " + view.selected.favs + " favoritos no Wallhaven" : ""
                color: "#F2F2F2"
                opacity: 0.6
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                spacing: 6
                Repeater {
                    model: view.selected && view.selected.colors !== "" ? view.selected.colors.split(",") : []
                    delegate: Rectangle {
                        required property string modelData
                        width: 22
                        height: 22
                        radius: 11
                        color: modelData
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.25)
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: view.detailFor === (view.selected ? view.selected.wid : "") && view.detail.tags ? view.detail.tags.slice(0, 12) : []
                    delegate: Rectangle {
                        required property string modelData
                        height: 24
                        width: tagLabel.implicitWidth + 16
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.10)
                        StyledText {
                            id: tagLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: "#F2F2F2"
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            Item {
                width: 1
                height: 4
            }

            // Ainda não está na pasta: baixar.
            Column {
                visible: !view.selectedInLibrary
                width: parent.width
                spacing: 10

                HubButton {
                    width: parent.width
                    icon: "download"
                    label: view.selectedBusy ? "Baixando…" : "Baixar e usar"
                    hint: "Enter"
                    active: true
                    busy: view.selectedBusy
                    onClicked: view.downloadSelected(true, false)
                }
                HubButton {
                    width: parent.width
                    icon: "star"
                    label: "Baixar, usar e favoritar"
                    hint: "F"
                    busy: view.selectedBusy
                    onClicked: view.downloadSelected(true, true)
                }
                HubButton {
                    width: parent.width
                    icon: "download"
                    label: "Só baixar"
                    hint: "D"
                    busy: view.selectedBusy
                    onClicked: view.downloadSelected(false, false)
                }
            }

            // Já está na pasta: usar ou favoritar.
            Column {
                visible: view.selectedInLibrary
                width: parent.width
                spacing: 10

                StyledText {
                    text: "Já está na sua pasta."
                    color: "#F2F2F2"
                    opacity: 0.7
                    font.pixelSize: Theme.fontSizeMedium
                }
                HubButton {
                    width: parent.width
                    icon: "wallpaper"
                    label: "Usar"
                    hint: "Enter"
                    active: true
                    onClicked: view.hub.apply(view.selected.fileName)
                }
                HubButton {
                    width: parent.width
                    icon: "star"
                    filledIcon: view.selectedIsFavorite
                    label: view.selectedIsFavorite ? "Desfavoritar" : "Favoritar"
                    hint: "F"
                    onClicked: view.hub.toggleFavorite(view.selected.fileName)
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: view.selected === null
            text: "Escolha um wallpaper"
            color: "#F2F2F2"
            opacity: 0.5
            font.pixelSize: Theme.fontSizeMedium
        }
    }
}
