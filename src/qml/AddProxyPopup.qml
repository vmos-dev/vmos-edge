import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI

FluPopup {
    id: root
    implicitWidth: 420
    implicitHeight: 550
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string phoneName: "AC4513165321156"
    property var protocolModel: ["SOCKS5", "HTTP", "HTTPS"]
    property var accountModel: []

    signal setProxy(var settings)
    signal networkTest()

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
                text: qsTr("设置代理 (云机名称: %1)").arg(root.phoneName)
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
                onClicked: root.close()
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

            FluText { text: qsTr("代理协议") }
            FluComboBox {
                id: protocolComboBox
                Layout.fillWidth: true
                model: root.protocolModel
            }

            FluText { text: qsTr("服务器地址") }
            FluTextBox {
                id: addressInput
                Layout.fillWidth: true
                placeholderText: qsTr("请输入服务器地址")
            }

            FluText { text: qsTr("服务端口") }
            FluTextBox {
                id: portInput
                Layout.fillWidth: true
                placeholderText: qsTr("请输入正确的端口")
                validator: IntValidator { bottom: 1; top: 65535 }
            }

            FluText { text: qsTr("账号") }
            FluComboBox {
                id: accountComboBox
                Layout.fillWidth: true
                editable: true
                model: root.accountModel
                // placeholderText: qsTr("请账号")
            }

            FluText { text: qsTr("密码") }
            FluTextBox {
                id: passwordInput
                Layout.fillWidth: true
                placeholderText: qsTr("请输入密码")
                echoMode: TextInput.Password
            }
        }

        Item { Layout.fillHeight: true }

        // 底部操作栏
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 10

            TextButtonEx {
                text: qsTr("网络检测")
                textColor: ThemeUI.primaryColor
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.networkTest()
            }

            Item { Layout.fillWidth: true }

            FluButton {
                text: qsTr("取消")
                onClicked: root.close()
            }
            FluFilledButton {
                text: qsTr("确定")
                onClicked: {
                    // 在这里收集数据并发出信号
                    // var settings = { ... }
                    // root.setProxy(settings)
                    root.close()
                }
            }
        }
    }
}
