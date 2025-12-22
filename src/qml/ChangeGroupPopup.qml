import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI

FluPopup {
    id: root
    implicitWidth: 500
    padding: 0
    topPadding: 0
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var podIdList: []
    property var groupModel: null
    property var hostModel: treeModel.hostList()

    signal changeGroup(var podIdList, int groupId)

    function filterModel() {
        var searchText = search_input.text.toLowerCase()
        var filteredModel
        if (searchText === "") {
            filteredModel = root.hostModel
        } else {
            filteredModel = root.hostModel.filter(item => {
                return item.ip.toLowerCase().includes(searchText) || String(item.hostId).toLowerCase().includes(searchText)
            })
        }
        listView.model = filteredModel
    }

    onAboutToShow: {
        selectAllBox.checked = false
        search_input.text = ""  // 清空搜索条件
        var tmpModel = treeModel.hostList()
        root.hostModel = tmpModel.filter(item => item.groupId !== (root.groupModel?.groupId ?? 0))
        filterModel()
    }

    ColumnLayout {
        anchors.fill: parent

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.leftMargin: 20
            Layout.rightMargin: 10

            FluText {
                text: qsTr("设置分组 (%1)").arg(root.groupModel?.groupName ?? "")
                font.bold: true
                font.pixelSize: 16
            }

            Item { Layout.fillWidth: true }

            FluImageButton{
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

        RowLayout{
            Layout.fillHeight: true
            Layout.fillWidth: true


            ColumnLayout{
                Layout.preferredWidth: 100
                Layout.fillHeight: true

                Item{
                    Layout.preferredHeight: 40
                }
                FluText{
                    text: qsTr("选择主机")
                    Layout.alignment: Qt.AlignRight
                }
                Item{
                    Layout.fillHeight: true
                }
            }

            ColumnLayout{

                RowLayout{
                    Layout.preferredHeight: 40
                    Layout.leftMargin: 10
                    Layout.rightMargin: 4

                    Rectangle{
                        Layout.preferredWidth: 200
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignVCenter
                        radius: 4
                        border.color: "#eee"
                        border.width: 1

                        FluTextBox {
                            id: search_input
                            anchors.fill: parent
                            placeholderText: qsTr("输入主机IP或ID搜索")
                            placeholderTextColor: "gray"
                            color: "black"
                            background: Item{}
                            onTextChanged: {
                                filterModel()
                            }
                        }
                    }

                    VCheckBox {
                        id: selectAllBox
                        text: qsTr("全选")
                        textColor: "black"
                        enabled: listView.model && listView.model.length > 0

                        onClicked: {
                            var newModel = []
                            for (var i = 0; i < root.hostModel.length; i++) {
                                var item = root.hostModel[i]
                                item.checked = selectAllBox.checked
                                newModel.push(item)
                            }
                            root.hostModel = newModel
                            filterModel()
                        }
                    }

                    Item{
                        Layout.fillWidth: true
                    }
                }

                ListView {
                    id: listView
                    Layout.fillWidth: true
                    Layout.preferredHeight: 300
                    model: root.hostModel
                    clip: true
                    delegate: Item {
                        width: listView.width
                        height: 30

                        RowLayout {
                            anchors.fill: parent
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10;
                            anchors.rightMargin: 10;
                            spacing: 5

                            VCheckBox {
                                text: modelData?.ip ?? ""
                                textColor: "black"
                                checked: modelData?.checked ?? false
                                onClicked: {
                                    // 使用hostId来匹配，而不是索引，因为搜索后索引会变化
                                    var clickedHostId = modelData?.hostId
                                    if (clickedHostId === undefined) return
                                    
                                    // 更新模型并触发重新渲染
                                    var newModel = []
                                    for (var i = 0; i < root.hostModel.length; i++) {
                                        var item = root.hostModel[i]
                                        if (item.hostId === clickedHostId) {
                                            item.checked = checked
                                        }
                                        newModel.push(item)
                                    }
                                    root.hostModel = newModel
                                    
                                    // 检查是否所有项都被勾选
                                    var allChecked = true
                                    for (var j = 0; j < root.hostModel.length; j++) {
                                        if (!root.hostModel[j].checked) {
                                            allChecked = false
                                            break
                                        }
                                    }
                                    selectAllBox.checked = allChecked
                                    
                                    filterModel()
                                }
                            }
                        }
                    }
                }
            }
        }

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
                    var selectedGroupId = root.groupModel?.groupId ?? 1
                    const ids = root.hostModel.filter(
                                  item =>{
                                      return item.checked
                                  }).map(
                                  item => {
                                      return item.hostId
                                  })
                    root.changeGroup(ids, selectedGroupId)

                    root.close()
                }
            }
        }
    }
}
