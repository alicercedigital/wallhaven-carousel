import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "wallpaperHub"

    StyledText {
        width: parent.width
        text: "Wallpaper Hub"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Abra com: dms ipc call wallpaperHub toggle. O plugin usa uma pasta só, a mesma da troca automática do DMS."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "folder"
        label: "Pasta dos wallpapers"
        description: "Vazio: a pasta da troca automática do DMS, ou a do wallpaper atual."
        placeholder: "/home/dretz/Wallpapers"
    }

    SelectionSetting {
        settingKey: "favoritesInterval"
        label: "Trocar entre os favoritos a cada"
        description: "Vale quando o aleatório dos favoritos está ligado."
        options: [
            {
                label: "5 minutos",
                value: "5"
            },
            {
                label: "15 minutos",
                value: "15"
            },
            {
                label: "30 minutos",
                value: "30"
            },
            {
                label: "1 hora",
                value: "60"
            },
            {
                label: "3 horas",
                value: "180"
            },
            {
                label: "6 horas",
                value: "360"
            }
        ]
        defaultValue: "60"
    }
}
