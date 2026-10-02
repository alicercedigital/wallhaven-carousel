import QtQuick
import qs.Common
import qs.Widgets

// DMS's text field as a pill with a search icon. Escape, which the field
// leaves alone, reaches this item and becomes `escaped`.
Item {
    id: box

    property alias text: field.text
    property string placeholder: ""

    signal accepted
    signal escaped

    function focusInput() {
        field.forceActiveFocus();
        field.selectAll();
    }

    implicitHeight: field.height
    Keys.onEscapePressed: box.escaped()

    DankTextField {
        id: field
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter
        leftIconName: "search"
        leftIconSize: Theme.iconSize - 4
        placeholderText: box.placeholder
        cornerRadius: height / 2
        onAccepted: box.accepted()
    }
}
