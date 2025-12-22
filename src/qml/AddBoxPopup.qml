import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI

FluPopup {
    id: root
    implicitWidth: 420
    implicitHeight: 350
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    signal addHost(string ips)


    onAboutToShow: {
        ipInput.text = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 标题栏
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.leftMargin: 20
            Layout.rightMargin: 10

            FluText {
                text: qsTr("添加主机")
                font.bold: true
                font.pixelSize: 16
            }

            Item { Layout.fillWidth: true }

            FluImageButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                normalImage: "qrc:/res/common/btn_close_normal.png"
                hoveredImage: "qrc:/res/common/btn_close_normal.png"
                pushedImage: "qrc:/res/common/btn_close_normal.png"
                onClicked: {
                    root.close()
                }
            }
        }

        // 内容区域
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.bottomMargin: 20
            spacing: 15

            FluText {
                text: qsTr("主机IP")
            }

            FluMultilineTextBox {
                id: ipInput
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                placeholderText: qsTr("请输入IP地址，多个使用(,)分割")
                wrapMode: Text.Wrap
            }
        }

        Item { Layout.fillHeight: true }

        // 操作按钮
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            Layout.rightMargin: 20
            spacing: 10

            Item { Layout.fillWidth: true }

            FluButton {
                text: qsTr("取消")
                onClicked: root.close()
            }
            FluFilledButton {
                text: qsTr("确定")
                onClicked: {
                    const trimmedText = ipInput.text.trim()
                    if (!trimmedText) {
                        showError("请输入IP地址")
                        return
                    }

                    const ips = trimmedText.split(",").map(function(ip) { return ip.trim() }).filter(function(ip) { return ip.length > 0 })
                    if (ips.length === 0) {
                        showError("请输入IP地址")
                        return
                    }

                    const ipRegex = /^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/
                    for (var i = 0; i < ips.length; i++) {
                        if (!ipRegex.test(ips[i])) {
                            showError(qsTr("请输入有效的IP地址: ") + ips[i])
                            return
                        }
                    }

                    root.addHost(ips.join(","))
                    root.close()
                }
            }
        }
    }
}
