import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Qt.labs.platform
import Utils

FluPopup {
    id: root
    implicitWidth: 600
    padding: 20
    spacing: 15
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property string hostIp: ""
    property var hostData: null
    property var hostConfig: null

    onOpened: {
        reqHardwareCfg(root.hostIp)

        updateTimer.restart()
    }

    onClosed: {
        updateTimer.stop()
    }


    ColumnLayout {
        width: parent.width

        // 标题栏
        RowLayout {
            Layout.fillWidth: true
            FluText {
                text: qsTr("主机详情")
                font.bold: true
                font.pixelSize: 16
            }

            Item { Layout.fillWidth: true }

            FluImageButton {
                implicitWidth: 24
                implicitHeight: 24
                normalImage: "qrc:/res/common/btn_close_normal.png"
                hoveredImage: "qrc:/res/common/btn_close_normal.png"
                pushedImage: "qrc:/res/common/btn_close_normal.png"
                onClicked: root.close()
            }
        }

        // 基础信息
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("主机ID:")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: hostConfig?.device_id ?? ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("主机IP:")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: root.hostIp
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("型号:")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: hostConfig?.model ?? ""
                }
            }
        }

        // 资源使用情况
        GridLayout {
            Layout.topMargin: 15
            Layout.bottomMargin: 15
            Layout.fillWidth: true
            columns: 5
            columnSpacing: 10
            rowSpacing: 18

            // CPU
            FluText {
                text: qsTr("CPU:")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            FluProgressBar {
                value: hostData?.cpu ?? 0
                from: 0
                to: 100
                indeterminate: false
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${hostData?.cpu ?? 0}%`
                Layout.preferredWidth: 40
                Layout.alignment: Qt.AlignVCenter
            }
            Item {
                Layout.preferredWidth: 120
            }
            Item {}

            // 内存
            FluText {
                text: qsTr("内存:")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            FluProgressBar {
                value: hostData?.mem_percent ?? 0
                from: 0
                to: 100
                indeterminate: false
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${hostData?.mem_percent ?? 0}%`
                Layout.preferredWidth: 40
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${AppUtils.mbToGB((hostData?.mem_total ?? 0) * ((hostData?.mem_percent ?? 0) / 100.00))}GB/${AppUtils.mbToGB(hostData?.mem_total ?? 0)}GB`
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            Item {}

            // 虚拟内存
            FluText {
                text: qsTr("虚拟内存 (swap):")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            FluProgressBar {
                value: hostData?.swap_percent ?? 0
                from: 0
                to: 100
                indeterminate: false
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${hostData?.swap_percent ?? 0}%`
                Layout.preferredWidth: 40
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${AppUtils.mbToGB((hostData?.swap_total ?? 0) * ((hostData?.swap_percent ?? 0) / 100.00))}GB/${AppUtils.mbToGB(hostData?.swap_total ?? 0)}GB`
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            Item {}
            // FluText {
            //     text: qsTr("是否启用:")
            //     color: "#666"
            //     Layout.preferredWidth: 120
            //     horizontalAlignment: Text.AlignRight
            //     Layout.alignment: Qt.AlignVCenter
            // }

            // FluToggleSwitch{
            //     checked: (hostData?.swap_total ?? 0) > 0
            //     onClicked: {
            //         if(checked){
            //             reqSwapEnable(root.hostIp, true)
            //         }else{
            //             reqSwapEnable(root.hostIp, false)
            //         }
            //     }
            // }
            // Item {}
            // Item {}
            // Item {}

            // 本地存储
            FluText {
                text: qsTr("本地存储:")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            FluProgressBar {
                value: hostData?.mmc_percent ?? 0
                from: 0
                to: 100
                indeterminate: false
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${hostData?.mmc_percent ?? 0}%`
                Layout.preferredWidth: 40
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${AppUtils.mbToGB((hostData?.mmc_total ?? 0) * ((hostData?.mmc_percent ?? 0) / 100.00))}GB/${AppUtils.mbToGB(hostData?.mmc_total ?? 0)}GB`
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            Item {}

            // 硬盘存储
            FluText {
                text: qsTr("硬盘存储:")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }
            FluProgressBar {
                value: hostData?.ssd_percent ?? 0
                from: 0
                to: 100
                indeterminate: false
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${hostData?.ssd_percent ?? 0}%`
                Layout.preferredWidth: 40
                Layout.alignment: Qt.AlignVCenter
            }
            FluText {
                text: `${AppUtils.mbToGB((hostData?.ssd_total ?? 0) * ((hostData?.ssd_percent ?? 0) / 100.00))}GB/${AppUtils.mbToGB(hostData?.ssd_total ?? 0)}GB`
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
            }

            Item {}
        }

        // 版本信息
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            FluText {
                text: qsTr("Debian系统版本:")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
            }
            FluText {
                text: hostConfig?.os_version ?? ""
            }
        }

        // 版本信息
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            FluText {
                text: qsTr("Debian内核版本:")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
            }
            FluText {
                text: hostConfig?.kernel_version ?? ""
            }
        }

        // 版本信息
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            FluText {
                text: qsTr("CBS版本:")
                color: "#666"
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignRight
            }
            FluText {
                text: hostConfig?.version ?? ""
            }
            FluTextButton{
                text: qsTr("更新")
                textColor: ThemeUI.primaryColor
                onClicked: {
                    cbsFileDialog.open()
                }
            }
        }

        Item { Layout.fillHeight: true }

        // 关闭按钮
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            FluButton {
                text: qsTr("关闭")
                onClicked: root.close()
            }
        }
    }

    FileDialog {
        id: cbsFileDialog
        title: qsTr("选择CBS安装包")
        fileMode: FileDialog.OpenFile
        nameFilters: [ "cbs files (*.cbs)" ]
        onAccepted: {
            const localPath = FluTools.toLocalPath(cbsFileDialog.file)
            if(localPath && root.hostIp){
                reqUpdateCbs(root.hostIp, localPath)
            }
        }
    }

    NetworkCallable {
        id: systemInfo
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    root.hostData = res.data
                }else{
                    showError(res.msg)
                }
            }
    }

    // 获取主机状态
    function reqSystemInfo(ip){
        Network.get(`http://${ip}:18182/v1` + "/systeminfo")
        .bind(root)
        .go(systemInfo)
    }

    NetworkCallable {
        id: hardwareCfg
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                // showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    root.hostConfig = res.data
                }else{
                    showError(res.msg)
                }
            }
    }

    // 获取主机配置
    function reqHardwareCfg(ip){
        Network.get(`http://${ip}:18182/v1` + "/get_hardware_cfg")
        .bind(root)
        .go(hardwareCfg)
    }

    NetworkCallable {
        id: swapEnable
        onStart: {
            showLoading(qsTr("正在修改中..."))
        }
        onFinish: {
            hideLoading()
        }
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){

                }else{
                    showError(res.msg)
                }
            }
    }

    // swap开关
    function reqSwapEnable(ip, enable){
        Network.get(`http://${ip}:18182/v1` + (enable ? "/swap/1" : "/swap/0"))
        .bind(root)
        .setTimeout(180000)
        .go(swapEnable)
    }

    NetworkCallable {
        id: updateCbs
        onStart: {
            showLoading(qsTr("正在更新中..."))
        }
        onFinish: {
            hideLoading()
        }
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                console.log("=================onError")
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                console.log("=================onSuccess", result, userData)
                showSuccess(qsTr("已下发更新，请等待10s主机重新连接后查看"), 3000)
                hardwareTimer.restart()
            }
        onUploadProgress:
            (sent, total) => {
                // 可按需扩展进度UI
                console.log("=================", sent*1.0/total*100)
            }
    }

    // 更新CBS
    function reqUpdateCbs(ip, path){
        Network.postForm(`http://${ip}:18182/v1` + "/update_cbs")
        .setRetry(1)
        .addFile("file", path)
        .bind(root)
        .setUserData(ip)
        .setTimeout(600000)
        .go(updateCbs)
    }

    Timer{
        id: updateTimer
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            reqSystemInfo(root.hostIp)
        }
    }

    Timer{
        id: hardwareTimer
        interval: 10000
        repeat: false
        onTriggered: {
            reqHardwareCfg(root.hostIp)
        }
    }
}
