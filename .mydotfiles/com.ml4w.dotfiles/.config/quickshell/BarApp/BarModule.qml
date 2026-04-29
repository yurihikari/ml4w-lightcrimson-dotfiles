import QtQuick
import qs.CustomTheme

Rectangle {
    default property alias content: container.data
    
    implicitWidth: container.width + 20
    implicitHeight: 32
    
    radius: 12
    // Use the theme background with some transparency
    color: Theme.background
    opacity: 0.9
    
    // Add a subtle border like Caelestia
    border.color: Theme.primary
    border.width: 1

    Item {
        id: container
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }
}