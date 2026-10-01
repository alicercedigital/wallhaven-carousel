import QtQuick
import qs.Common
import qs.Widgets

// A pill-shaped button, made to sit on the overlay's dark backdrop.
Rectangle {
    id: btn

    property string icon: ""
    property string label: ""
    property string hint: ""
    property bool active: false
    property bool danger: false
    property bool filledIcon: false
    property bool busy: false

    signal clicked

    readonly property color fg: active ? Theme.onPrimary : danger ? Theme.error : Theme.surfaceText

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 28
    radius: height / 2
    color: active ? Theme.primary : Theme.withAlpha(danger ? Theme.error : Theme.surfaceText, mouse.containsMouse ? 0.22 : 0.10)
    opacity: busy ? 0.6 : 1

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        DankIcon {
            visible: btn.icon !== ""
            name: btn.icon
            size: 20
            filled: btn.filledIcon
            color: btn.fg
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            visible: btn.label !== ""
            text: btn.label
            color: btn.fg
            font.pixelSize: Theme.fontSizeMedium
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            visible: btn.hint !== ""
            text: btn.hint
            color: btn.fg
            opacity: 0.6
            font.pixelSize: Theme.fontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!btn.busy) btn.clicked()
    }
}
