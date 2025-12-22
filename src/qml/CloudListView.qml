import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Utils

Item{
    id: root
    property alias model : deviceListView.model
    readonly property var itemWidth: [150.00, 120.00, 140.00, 90.00, 70.00, 140.00, 200.00]
    readonly property int itemTotalWidth: itemWidth.reduce((acc, cur) => acc + cur, 0)
    // 分页配置
    // property int pageSize: 10
    // property int currentPage: 1
    // readonly property int totalCount: deviceListView.count
    // readonly property int totalPages: Math.max(1, Math.ceil(totalCount / pageSize))
    // readonly property int pageStartIndex: (currentPage - 1) * pageSize
    // readonly property int pageEndIndex: Math.min(pageStartIndex + pageSize, totalCount)
    signal clickMenuItem(var model)
    
    ColumnLayout{
        anchors.fill: parent
        spacing: 0

        Rectangle{
            Layout.preferredHeight: 40
            Layout.fillWidth: true
            color: "white"
            border.width: 1
            border.color: "#eee"
            topLeftRadius: 8
            topRightRadius: 8

            RowLayout{
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 0

                VCheckBox{
                    id: headerPageCheck
                    checked: proxyModel.isSelectAll
                    // enabled: !groupControl.eventSync
                    onClicked: {
                        if(checkIsEventSync()){
                            return
                        }

                        checkBoxInvertSelection.checked = false
                        proxyModel.selectAll(checked)
                    }
                    // 监听模型选择变更与分页变更，实时刷新头部全选状态
                    // Connections{
                    //     target: proxyModel
                    //     function onCheckedCountChanged(){
                    //         headerPageCheck.pageAllChecked = proxyModel.isAllCheckedInRange(root.pageStartIndex, root.pageEndIndex)
                    //     }
                    //     function onIsSelectAllChanged(){
                    //         headerPageCheck.pageAllChecked = proxyModel.isAllCheckedInRange(root.pageStartIndex, root.pageEndIndex)
                    //     }
                    // }
                    // Connections{
                    //     target: root
                    //     function onCurrentPageChanged(){
                    //         headerPageCheck.pageAllChecked = proxyModel.isAllCheckedInRange(root.pageStartIndex, root.pageEndIndex)
                    //     }
                    //     function onPageSizeChanged(){
                    //         headerPageCheck.pageAllChecked = proxyModel.isAllCheckedInRange(root.pageStartIndex, root.pageEndIndex)
                    //     }
                    // }
                }

                Item{
                    Layout.fillHeight: true
                    Layout.preferredWidth: deviceListView.width * itemWidth[0] / itemTotalWidth

                    FluText{
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("云机ID")
                    }
                }

                Item{
                    Layout.fillHeight: true
                    Layout.preferredWidth: deviceListView.width * itemWidth[1] / itemTotalWidth


                    FluText{
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("云机名称")
                    }
                }

                Item{
                    Layout.fillHeight: true
                    Layout.preferredWidth: deviceListView.width * itemWidth[2] / itemTotalWidth


                    FluText{
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("ADB地址")
                    }
                }

                Item{
                    Layout.fillHeight: true
                    Layout.preferredWidth: deviceListView.width * itemWidth[3] / itemTotalWidth


                    FluText{
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Android版本")
                    }
                }
                Item{
                    Layout.fillHeight: true
                    Layout.preferredWidth: deviceListView.width * itemWidth[4] / itemTotalWidth

                    FluText{
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("状态")
                    }
                }
                Item{
                    Layout.fillHeight: true
                    Layout.preferredWidth: deviceListView.width * itemWidth[5] / itemTotalWidth


                    FluText{
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("创建时间")
                    }
                }
                Item{
                    Layout.fillHeight: true
                    Layout.preferredWidth: deviceListView.width * itemWidth[6] / itemTotalWidth

                    FluText{
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("操作")
                    }
                }
                // Item{
                //     Layout.fillWidth: true
                // }
            }
        }

        ListView{
            id: deviceListView
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            interactive: true
            
            // 当数据量变化时修正当前页
            // Connections{
            //     target: deviceListView
            //     function onCountChanged(){
            //         if(root.currentPage > root.totalPages){
            //             root.currentPage = root.totalPages
            //         }
            //         if(root.currentPage < 1){
            //             root.currentPage = 1
            //         }
            //     }
            // }
            // 使用委托内覆盖层实现悬停高亮，避免与行内控件层级冲突

            function formatDateTimeRaw(isoString) {
                return isoString.replace("T", " ").replace("Z", "");
            }

            delegate: Rectangle {
                width: deviceListView.width
                height: 40
                color: "transparent"
                // readonly property bool inPage: index >= root.pageStartIndex && index < root.pageEndIndex

                // 顶层覆盖层：始终在所有内容之上
                Rectangle {
                    anchors.fill: parent
                    color: mouseArea.containsMouse ? "#26000000" : "transparent"
                    z: 999
                    // visible: inPage
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    // visible: inPage
                    onEntered: deviceListView.currentIndex = index
                    onExited: if (deviceListView.currentIndex === index) deviceListView.currentIndex = -1
                }

                ColumnLayout{
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    // visible: inPage


                    RowLayout{
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        VCheckBox{
                            checked: model?.checked ?? false
                            onClicked: {
                                if(model.checked != checked){
                                    model.checked = checked
                                }
                            }
                        }

                        Item{
                            Layout.fillHeight: true
                            Layout.preferredWidth: deviceListView.width * itemWidth[0] / itemTotalWidth

                            FluText{
                                anchors.verticalCenter: parent.verticalCenter
                                text: model?.dbId ?? ""

                                MouseArea{
                                    anchors.fill: parent

                                    onClicked: {
                                        FluTools.clipText(model?.dbId ?? "")
                                        showSuccess(qsTr("复制成功"))
                                    }
                                }
                            }
                        }

                        Item{
                            Layout.fillHeight: true
                            Layout.preferredWidth: deviceListView.width * itemWidth[1] / itemTotalWidth


                            FluText{
                                anchors.verticalCenter: parent.verticalCenter
                                text: model?.displayName ?? ""
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                width: Math.min(implicitWidth, parent.width)        // 确保文本不会超出父容器边界

                                MouseArea{
                                    anchors.fill: parent

                                    onClicked: {
                                        FluTools.clipText(model?.displayName ?? "")
                                        showSuccess(qsTr("复制成功"))
                                    }
                                }
                            }
                        }

                        Item{
                            Layout.fillHeight: true
                            Layout.preferredWidth: deviceListView.width * itemWidth[2] / itemTotalWidth

                            FluText{
                                id: adbAddress
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (model.networkMode === "macvlan") {
                                        if (model.state !== "running") {
                                            return "-"
                                        }
                                    }
                                    return model?.networkMode === "macvlan" ? `${model?.ip ?? ""}:5555` : `${model?.hostIp ?? ""}:${model?.adb ?? ""}`
                                }

                                MouseArea{
                                    anchors.fill: parent

                                    onClicked: {
                                        FluTools.clipText(adbAddress.text)
                                        showSuccess(qsTr("复制成功"))
                                    }
                                }
                            }
                        }

                        Item{
                            Layout.fillHeight: true
                            Layout.preferredWidth: deviceListView.width * itemWidth[3] / itemTotalWidth

                            Rectangle{
                                width: 78
                                height: 28
                                color: "#E7F0FF"
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 14

                                FluText {
                                    anchors.centerIn: parent
                                    text: "Android " + (model?.aospVersion ?? "")
                                    font.pixelSize: 12
                                    color: ThemeUI.primaryColor
                                }
                            }
                        }
                        Item{
                            Layout.fillHeight: true
                            Layout.preferredWidth: deviceListView.width * itemWidth[4] / itemTotalWidth

                            Rectangle{
                                width: statusText.implicitWidth + 16
                                height: statusText.implicitHeight + 8
                                border.color: AppUtils.getStateColorBystate(model.state).border
                                border.width: 1
                                color: AppUtils.getStateColorBystate(model.state).bg
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 2

                                FluText {
                                    id: statusText
                                    anchors.centerIn: parent
                                    text: AppUtils.getStateStringBystate(model?.state ?? "")
                                    color: AppUtils.getStateColorBystate(model.state).text
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Item{
                            Layout.fillHeight: true
                            Layout.preferredWidth: deviceListView.width * itemWidth[5] / itemTotalWidth

                            FluText{
                                anchors.verticalCenter: parent.verticalCenter
                                text: deviceListView.formatDateTimeRaw(model?.created ?? "")
                            }
                        }

                        Item{
                            Layout.fillHeight: true
                            Layout.preferredWidth: deviceListView.width * itemWidth[6] / itemTotalWidth

                            RowLayout{
                                anchors.fill: parent

                                TextButton {
                                    text: qsTr("开机")
                                    visible: (model.state === "exited" || model.state === "stopped")
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: 72
                                    borderRadius: 4
                                    backgroundColor: ThemeUI.primaryColor
                                    Layout.alignment: Qt.AlignHCenter
                                    onClicked: {
                                        if(model.state !== "exited" && model.state !== "stopped"){
                                            return
                                        }
                                        reqRunDevice(model.hostIp, [model.dbId])
                                    }
                                }

                                TextButton {
                                    text: qsTr("打开窗口")
                                    visible: model.state === "running"
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: 72
                                    borderRadius: 4
                                    backgroundColor: ThemeUI.primaryColor
                                    Layout.alignment: Qt.AlignHCenter
                                    onClicked: {
                                        if(model.state !== "running"){
                                            return
                                        }

                                        // 根据配置选择连接模式
                                        const hostIp = model.hostIp || ""
                                        const adb = model.adb || 0
                                        const dbId = model.dbId || model.db_id || model.id || model.name || ""
                                        const ip = model.ip || ""
                                        const useDirectTcp = model.networkMode === "macvlan"
                                        const realIP = useDirectTcp ? ip : hostIp;

                                        if (AppConfig.useDirectTcp) {
                                            // TCP直接连接模式：先启动 scrcpy_server，再连接
                                            const tcpVideoPort = useDirectTcp ? 9999 : (model.tcpVideoPort || 0)
                                            const tcpAudioPort = useDirectTcp ? 9998 : (model.tcpAudioPort || 0)
                                            const tcpControlPort = useDirectTcp ? 9997 : (model.tcpControlPort || 0)

                                            console.log("使用TCP直接连接模式:", hostIp, dbId, "ports:", tcpVideoPort, tcpAudioPort, tcpControlPort)

                                            console.log("scrcpy_server 启动成功，开始连接设备")
                                            deviceManager.connectDeviceDirectTcp(
                                                        dbId,           // serial
                                                        realIP || "localhost",  // host
                                                        tcpVideoPort,   // videoPort
                                                        tcpAudioPort,   // audioPort
                                                        tcpControlPort  // controlPort
                                                        )
                                        } else {
                                            // ADB连接模式
                                            const deviceAddress = `${realIP}:${adb}`
                                            console.log("使用ADB连接模式:", deviceAddress)
                                            deviceManager.connectDevice(deviceAddress)
                                        }
                                        
                                        FluRouter.navigate("/pad", model, undefined, model.id)
                                    }
                                }

                                TextButton {
                                    text: qsTr("克隆")
                                    visible: model.state === "exited" || model.state ===  "stopped"
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: 72
                                    borderRadius: 4
                                    backgroundColor: ThemeUI.primaryColor
                                    Layout.alignment: Qt.AlignHCenter
                                    onClicked: {
                                        var modelData = {
                                            phoneName: model.name,
                                            imgVersion: model.image,
                                            androidVersion: "Android " + (model?.aospVersion ?? ""),
                                            hostIp: model.hostIp,
                                            dbId: model.dbId || model.db_id || model.id || model.name || ""
                                        }
                                        clonePhonePopup.modelData = modelData
                                        clonePhonePopup.open()
                                    }
                                }

                                FluIcon{
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    visible: model.state === "running"
                                    iconSource: FluentIcons.More
                                    color: ThemeUI.primaryColor
                                    iconSize: 14
                                    rotation: 90

                                    MouseArea{
                                        anchors.fill: parent
                                        onClicked: {
                                            clickMenuItem(model)
                                        }
                                    }
                                }

                                Item{
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                    FluDivider{
                        Layout.fillWidth: true
                    }
                }
            }
        }
        
        // 底部分页条容器（无数据时不显示）
        // Item{
        //     Layout.fillWidth: true
        //     Layout.preferredHeight: 32
        //     Layout.leftMargin: 10
        //     Layout.rightMargin: 10
        //     Layout.bottomMargin: 10
        //     visible: root.totalCount > 0
        //     // radius: 8
        //     // color: "white"
        //     // border.color: "#E5E5E5"
        //     // border.width: 1

        //     Item{
        //         anchors.fill: parent
        //         anchors.leftMargin: 16
        //         anchors.rightMargin: 16
        //         Row{
        //             anchors.right: parent.right
        //             anchors.verticalCenter: parent.verticalCenter
        //             spacing: 12

        //             FluPagination{
        //                 id: pagination
        //                 itemCount: root.totalCount
        //                 pageCurrent: root.currentPage
        //                 __itemPerPage: root.pageSize
        //                 pageButtonCount: 7
        //                 previousText: "<"
        //                 nextText: ">"
        //                 footer: Row {
        //                     spacing: 8

        //                     FluComboBox{
        //                         id: pageSizeCombo
        //                         width: 110
        //                         height: 32
        //                         model: [10, 20, 30, 50]
        //                         // 展开列表背景改为白色
        //                         popup.background: Rectangle { color: "white"; border.color: "#E5E5E5"; radius: 4 }
        //                         delegate: ItemDelegate {
        //                             width: parent ? parent.width : 110
        //                             background: Rectangle { color: (hovered || highlighted) ? "#F5F5F5" : "white" }
        //                             contentItem: Text {
        //                                 text: modelData + qsTr("条/页")
        //                                 horizontalAlignment: Text.AlignHCenter
        //                                 verticalAlignment: Text.AlignVCenter
        //                                 color: "#222222"
        //                             }
        //                             onClicked: {
        //                                 pageSizeCombo.currentIndex = index
        //                                 pageSizeCombo.popup.close()
        //                             }
        //                         }
        //                         contentItem: Text {
        //                             text: (pageSizeCombo.currentIndex >= 0 ? (pageSizeCombo.model[pageSizeCombo.currentIndex] + qsTr("条/页")) : (root.pageSize + qsTr("条/页")))
        //                             verticalAlignment: Text.AlignVCenter
        //                             horizontalAlignment: Text.AlignHCenter
        //                             elide: Text.ElideRight
        //                         }
        //                         Component.onCompleted: {
        //                             let idx = model.indexOf(root.pageSize)
        //                             currentIndex = idx >= 0 ? idx : 0
        //                         }
        //                         onCurrentIndexChanged: {
        //                             const newSize = model[currentIndex]
        //                             if (root.pageSize !== newSize) {
        //                                 root.pageSize = newSize
        //                                 root.currentPage = 1
        //                             }
        //                         }
        //                     }
        //                 }
        //                 onRequestPage: function(page, count){
        //                     root.currentPage = page
        //                     if (root.pageSize !== count) {
        //                         root.pageSize = count
        //                     }
        //                 }
        //             }
        //         }
        //     }
        // }
    }

    CloneCloudPhonePopup {
        id: clonePhonePopup
    }
}

