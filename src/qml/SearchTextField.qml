import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI

Rectangle {
    id: root
    
    property alias text: textField.text
    property alias placeholderText: textField.placeholderText
    property string searchIconSource: FluentIcons.Search
    property string clearIconSource: "qrc:/res/common/input_clear.svg"
    property color borderColor: "#E1E3E9"
    property color textColor: "black"
    property color placeholderColor: "gray"
    property color searchIconColor: "#A9ACB3"
    property int searchIconSize: 13
    property int clearIconSize: 16
    property int maximumLength: 0 // 0表示无限制
    
    signal searchTextChanged(string text)
    signal searchTextFinished(string text)
    signal cleared()
    
    implicitWidth: 280
    implicitHeight: 32
    radius: 4
    border.width: 1
    border.color: borderColor
    color: "white"
    
    RowLayout {
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.leftMargin: 12
        anchors.rightMargin: 4
        anchors.bottomMargin: 2
        spacing: 0
        
        FluIcon {
            iconSource: root.searchIconSource
            iconColor: root.searchIconColor
            iconSize: root.searchIconSize
            rotation: 270
        }
        
        TextField {
            id: textField
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
            placeholderTextColor: root.placeholderColor
            color: root.textColor
            background: Item {}
            maximumLength: root.maximumLength > 0 ? root.maximumLength : 32767 // 如果maximumLength为0，则使用默认最大值
            onTextChanged: {
                root.searchTextChanged(text)
            }
            onEditingFinished: {
                root.searchTextFinished(text)
            }
        }
        
        Image {
            source: root.clearIconSource
            width: root.clearIconSize
            height: root.clearIconSize
            visible: textField.text.length > 0
            Layout.rightMargin: 8
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    textField.text = ""
                    root.cleared()
                }
            }
        }
    }
}

