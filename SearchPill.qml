import QtQuick
import qs.Common
import qs.Widgets

// A search field on the overlay's dark backdrop.
Rectangle {
    id: box

    property alias text: input.text
    property string placeholder: ""

    signal accepted
    signal escaped

    function focusInput() {
        input.forceActiveFocus();
        input.selectAll();
    }

    implicitHeight: 40
    radius: height / 2
    color: Theme.withAlpha(Theme.surfaceText, input.activeFocus ? 0.16 : 0.10)
    border.width: input.activeFocus ? 2 : 0
    border.color: Theme.primary

    DankIcon {
        id: glass
        name: "search"
        size: 20
        color: Theme.surfaceText
        opacity: 0.7
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
    }

    TextInput {
        id: input
        anchors.left: glass.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.surfaceText
        selectionColor: Theme.primary
        selectedTextColor: Theme.onPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        selectByMouse: true
        clip: true
        onAccepted: box.accepted()
        Keys.onEscapePressed: box.escaped()

        StyledText {
            visible: input.text === "" && !input.preeditText
            text: box.placeholder
            color: Theme.surfaceText
            opacity: 0.45
            font.pixelSize: Theme.fontSizeMedium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
