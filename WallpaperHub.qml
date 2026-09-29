import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt.labs.folderlistmodel
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Wallpaper Hub: carrossel da pasta de wallpapers, com favoritos, exclusão,
// download do Wallhaven e a troca aleatória só entre os favoritos.
// O DMS continua dono do wallpaper (SessionData); aqui só se escolhe qual.
PluginComponent {
    id: root

    property var popoutService: null

    // ── Pasta ─────────────────────────────────────────────────────────────
    // Uma pasta só: a que o plugin diz, senão a da troca automática do DMS,
    // senão a do wallpaper atual.
    function stripFile(p) {
        return String(p ?? "").replace(/^file:\/\//, "");
    }

    readonly property string folder: {
        const own = stripFile(pluginData?.folder).trim();
        if (own)
            return own.replace(/\/+$/, "");
        const cycling = stripFile(SessionData.wallpaperCyclingFolderPath).trim();
        if (cycling)
            return cycling.replace(/\/+$/, "");
        const current = stripFile(SessionData.wallpaperPath);
        if (current && !current.startsWith("#") && current.lastIndexOf("/") > 0)
            return current.substring(0, current.lastIndexOf("/"));
        return stripFile(Paths.pictures);
    }

    readonly property string currentPath: {
        const p = stripFile(SessionData.wallpaperPath);
        return p.startsWith("#") ? "" : p;
    }
    readonly property string currentName: currentPath.substring(currentPath.lastIndexOf("/") + 1)

    function urlFor(name) {
        return "file://" + folder + "/" + encodeURIComponent(name);
    }

    // ── Arquivos da pasta ─────────────────────────────────────────────────
    property var names: []
    property var nameSet: ({})

    FolderListModel {
        id: folderModel
        folder: "file://" + root.folder
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.bmp", "*.jxl", "*.avif", "*.heif"]
        caseSensitive: false
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: scanTimer.restart()
        onStatusChanged: scanTimer.restart()
    }

    Timer {
        id: scanTimer
        interval: 60
        onTriggered: root.scan()
    }

    function scan() {
        const out = [];
        const set = {};
        for (let i = 0; i < folderModel.count; i++) {
            const n = folderModel.get(i, "fileName");
            out.push(n);
            set[n] = true;
        }
        if (out.join("\n") === names.join("\n"))
            return;
        names = out;
        nameSet = set;
        analyzeTimer.restart();
        tagTimer.restart();
    }

    // ── Favoritos ─────────────────────────────────────────────────────────
    // Guardados pelo nome do arquivo em plugin_settings.json: a pasta é uma só.
    property var favorites: []
    readonly property var favoriteSet: {
        const s = {};
        for (const n of favorites)
            s[n] = true;
        return s;
    }
    readonly property int favoriteCount: {
        let c = 0;
        for (const n of names)
            if (favoriteSet[n])
                c++;
        return c;
    }

    function loadFavorites() {
        const v = pluginData?.favorites;
        const arr = v ? Array.from(v) : [];
        if (JSON.stringify(arr) !== JSON.stringify(favorites))
            favorites = arr;
    }

    onPluginDataChanged: {
        loadFavorites();
        loadTags();
    }

    function saveFavorites(arr) {
        favorites = arr;
        pluginService?.savePluginData(pluginId, "favorites", arr);
    }

    function setFavorite(name, on) {
        const has = !!favoriteSet[name];
        if (on === has)
            return;
        saveFavorites(on ? favorites.concat([name]) : favorites.filter(n => n !== name));
    }

    function toggleFavorite(name) {
        setFavorite(name, !favoriteSet[name]);
    }

    // ── Cores e etiquetas (para filtrar) ──────────────────────────────────
    // As cores saem da própria imagem (colors.py, com cache em ~/.local/state);
    // as etiquetas vêm do Wallhaven, só para o que foi baixado de lá.
    property var colors: ({})
    property bool analyzing: false
    property bool analyzeAgain: false
    readonly property string colorCache: stripFile(Paths.state) + "/wallpaperHub/colors.json"

    Timer {
        id: analyzeTimer
        interval: 2000
        onTriggered: root.analyzeColors()
    }

    function analyzeColors() {
        const dir = pluginService ? pluginService.getPluginPath(pluginId) : "";
        if (!dir || names.length === 0)
            return;
        if (analyzing) {
            analyzeAgain = true;
            return;
        }
        analyzing = true;
        analyzeAgain = false;
        Proc.runCommand("wallpaperHub.colors", ["nice", "-n", "10", "python3", dir + "/colors.py", folder, colorCache], (out, code) => {
            root.analyzing = false;
            if (code === 0) {
                try {
                    root.colors = JSON.parse(out);
                } catch (e) {
                    console.warn("wallpaperHub: colors.py devolveu algo que não é JSON");
                }
            }
            if (root.analyzeAgain)
                analyzeTimer.restart();
        }, 0, 600000, root);
    }

    property var tags: ({})

    function loadTags() {
        const v = pluginData?.tags;
        const t = v ? JSON.parse(JSON.stringify(v)) : {};
        if (JSON.stringify(t) !== JSON.stringify(tags))
            tags = t;
    }

    function setTags(name, list) {
        const t = Object.assign({}, tags);
        if (list === null)
            delete t[name];
        else
            t[name] = list;
        tags = t;
        saveData("tags", t);
    }

    property var tagQueue: []
    property bool tagBusy: false

    Timer {
        id: tagTimer
        interval: 3000
        onTriggered: root.queueTags()
    }

    Timer {
        id: tagNext
        interval: 1500
        onTriggered: root.nextTag()
    }

    // O nome wallhaven-<id>.<ext> diz de onde veio; busca as etiquetas que faltam.
    function queueTags() {
        const q = [];
        for (const n of names) {
            const m = /^wallhaven-([a-z0-9]+)\./i.exec(n);
            if (m && tags[n] === undefined)
                q.push({
                    name: n,
                    wid: m[1]
                });
        }
        tagQueue = q;
        nextTag();
    }

    function nextTag() {
        if (tagBusy || tagQueue.length === 0)
            return;
        tagBusy = true;
        const it = tagQueue[0];
        tagQueue = tagQueue.slice(1);
        Proc.runCommand("wallpaperHub.tags", ["curl", "-fsSL", "--connect-timeout", "10", "--max-time", "30", "-A", "wallpaperHub/0.1", "https://wallhaven.cc/api/v1/w/" + it.wid], (out, code) => {
            root.tagBusy = false;
            if (code === 0) {
                try {
                    root.setTags(it.name, JSON.parse(out).data.tags.map(t => t.name).slice(0, 12));
                } catch (e) {}
            }
            tagNext.restart();
        }, 0, 40000, root);
    }

    // ── Aplicar, excluir ──────────────────────────────────────────────────
    function apply(name, screenName) {
        const path = folder + "/" + name;
        if (SessionData.perMonitorWallpaper) {
            if (screenName) {
                SessionData.setMonitorWallpaper(screenName, path);
            } else {
                for (const s of Quickshell.screens)
                    SessionData.setMonitorWallpaper(s.name, path);
            }
        } else {
            SessionData.setWallpaper(path);
        }
    }

    property int _seq: 0

    // Vai para a lixeira, nunca apaga de vez. Se era o wallpaper em uso,
    // `replacement` assume o lugar antes.
    function deleteWallpaper(name, replacement) {
        if (name === currentName && replacement)
            apply(replacement);
        Proc.runCommand("wallpaperHub.trash." + (++_seq), ["gio", "trash", folder + "/" + name], (out, code) => {
            if (code !== 0) {
                ToastService?.showError("Não consegui mandar para a lixeira", String(out));
                return;
            }
            setFavorite(name, false);
            if (tags[name] !== undefined)
                setTags(name, null);
            scanTimer.restart();
            ToastService?.showInfo("Na lixeira: " + name);
        }, 0, 15000, root);
    }

    // ── Aleatório só dos favoritos ────────────────────────────────────────
    // O timer do DMS troca entre todos os arquivos da pasta. Enquanto este
    // está ligado, o do DMS fica desligado (e volta como estava ao desligar).
    readonly property bool favoritesRandom: !!pluginData?.favoritesRandom
    readonly property int favoritesIntervalMin: parseInt(pluginData?.favoritesInterval) || 60
    property bool _changingCycling: false

    function saveData(key, value) {
        pluginService?.savePluginData(pluginId, key, value);
    }

    function setDmsCycling(on) {
        _changingCycling = true;
        SessionData.setWallpaperCyclingEnabled(on);
        _changingCycling = false;
    }

    function pickRandomFavorite() {
        const pool = favorites.filter(n => nameSet[n] && n !== currentName);
        if (pool.length === 0)
            return false;
        apply(pool[Math.floor(Math.random() * pool.length)]);
        return true;
    }

    function setFavoritesRandom(on) {
        if (on === favoritesRandom)
            return;
        if (on) {
            if (favoriteCount === 0) {
                ToastService?.showInfo("Marque alguns favoritos antes (tecla F)");
                return;
            }
            if (SessionData.wallpaperCyclingEnabled) {
                saveData("restoreCycling", true);
                setDmsCycling(false);
            }
            saveData("favoritesRandom", true);
            pickRandomFavorite();
            ToastService?.showInfo("Aleatório dos favoritos ligado");
        } else {
            saveData("favoritesRandom", false);
            if (pluginData?.restoreCycling) {
                saveData("restoreCycling", false);
                setDmsCycling(true);
            }
            ToastService?.showInfo("Aleatório dos favoritos desligado");
        }
    }

    // Se o troca-automática do DMS for ligado por fora, ele manda: este desliga.
    Connections {
        target: SessionData
        function onWallpaperCyclingEnabledChanged() {
            if (root._changingCycling || !root.favoritesRandom || !SessionData.wallpaperCyclingEnabled)
                return;
            root.saveData("restoreCycling", false);
            root.saveData("favoritesRandom", false);
        }
    }

    Timer {
        interval: root.favoritesIntervalMin * 60000
        running: root.favoritesRandom && !SessionService.locked
        repeat: true
        onTriggered: root.pickRandomFavorite()
    }

    // ── Download do Wallhaven ─────────────────────────────────────────────
    property var downloading: ({})

    signal downloaded(string name)

    // item: { wid, full, fileName }
    function download(item, thenApply, thenFavorite) {
        const name = item.fileName;
        const finish = () => {
            if (thenFavorite)
                setFavorite(name, true);
            if (thenApply)
                apply(name);
            downloaded(name);
        };
        if (nameSet[name]) {
            finish();
            return;
        }
        if (downloading[item.wid])
            return;
        downloading = Object.assign({}, downloading, {
            [item.wid]: true
        });
        const dest = folder + "/" + name;
        // Baixa para .part e só então renomeia: a pasta nunca mostra arquivo pela metade.
        Proc.runCommand("wallpaperHub.download." + item.wid, ["sh", "-c", 'mkdir -p "$(dirname "$1")" && curl -fsSL --connect-timeout 10 --max-time 180 --retry 3 --retry-all-errors -A "wallpaperHub/0.1" -o "$1.part" "$2" && mv "$1.part" "$1"', "sh", dest, item.full], (out, code) => {
            const d = Object.assign({}, root.downloading);
            delete d[item.wid];
            root.downloading = d;
            if (code !== 0) {
                Quickshell.execDetached(["rm", "-f", dest + ".part"]);
                ToastService?.showError("O download falhou", String(out));
                return;
            }
            scanTimer.restart();
            finish();
        }, 0, 200000, root);
    }

    // ── Painel ────────────────────────────────────────────────────────────
    property string mode: "library"
    readonly property bool overlayVisible: overlay.visible

    function open(m) {
        mode = m || "library";
        const s = CompositorService.getFocusedScreen();
        if (s)
            overlay.screen = s;
        library.reset();
        overlay.visible = true;
        Qt.callLater(focusMode);
    }

    function close() {
        overlay.visible = false;
    }

    function toggle() {
        if (overlay.visible)
            close();
        else
            open("library");
    }

    function showLibrary() {
        mode = "library";
        Qt.callLater(focusMode);
    }

    function showDiscover() {
        mode = "discover";
        discover.enter();
        Qt.callLater(focusMode);
    }

    function focusMode() {
        if (mode === "discover")
            discover.focusGrid();
        else
            library.focusList();
    }

    IpcHandler {
        target: "wallpaperHub"

        function toggle(): string {
            root.toggle();
            return overlay.visible ? "opened" : "closed";
        }
        function open(): string {
            if (!overlay.visible)
                root.open("library");
            return "opened";
        }
        function discover(): string {
            if (!overlay.visible)
                root.open("discover");
            root.showDiscover();
            return "opened";
        }
        function close(): string {
            root.close();
            return "closed";
        }
        // Marca ou desmarca o wallpaper em uso.
        function favorite(): string {
            if (!root.currentName || !root.nameSet[root.currentName])
                return "no-current";
            root.toggleFavorite(root.currentName);
            return root.favoriteSet[root.currentName] ? "favorited" : "unfavorited";
        }
        // Troca agora por um favorito ao acaso.
        function random(): string {
            return root.pickRandomFavorite() ? "changed" : "no-favorites";
        }
        // on, off ou toggle.
        function favoritesRandom(mode: string): string {
            const on = mode === "toggle" ? !root.favoritesRandom : mode === "on";
            root.setFavoritesRandom(on);
            return root.favoritesRandom ? "on" : "off";
        }
    }

    PanelWindow {
        id: overlay
        visible: false
        color: "transparent"

        WlrLayershell.namespace: "dms:plugins:wallpaperHub"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        Rectangle {
            anchors.fill: parent
            color: "#F0000000"
            opacity: overlay.visible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        // Clicar fora de tudo fecha.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        LibraryView {
            id: library
            anchors.fill: parent
            hub: root
            visible: root.mode === "library"
            screenName: overlay.screen ? overlay.screen.name : ""
        }

        DiscoverView {
            id: discover
            anchors.fill: parent
            hub: root
            visible: root.mode === "discover"
        }
    }

    Component.onCompleted: {
        loadFavorites();
        loadTags();
        scanTimer.restart();
        console.info("wallpaperHub: pronto (dms ipc call wallpaperHub toggle)");
    }
}
