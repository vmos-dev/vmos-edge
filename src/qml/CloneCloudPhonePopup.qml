import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Utils

/*
modelData
{
    "phoneName": "云机名称",
    "imgVersion": "镜像版本",
    "androidVersion": "Android版本",
    "hostIp": "主机ip"
    "dbId" : "云机id"
}
*/ 

FluPopup {
    id: root
    implicitWidth: 480
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onClosed: {
        // popup关闭时停止定时器，防止内存泄漏
        cloneStatusTimer.stop()
    }

    Component.onDestruction: {
        // 组件销毁时确保定时器停止
        cloneStatusTimer.stop()
    }

    property var modelData: null
    property int maxPhones: 12
    property int remainingPhones: 10
    property int phoneCount: 1

    property bool boolStart: false  // 是否立即启动云机
    property int runningDeviceCount: 0  // 当前主机运行中的云机数量

    Timer {
        id: cloneStatusTimer
        interval: 1000
        repeat: true
        onTriggered: {
            // if (root.modelData) {
            //     reqGetCloneStatus(root.modelData.hostIp)
            // }
        }
    }

    Timer {
        id: cloneTimeoutTimer
        interval: 1000 * 60 * 3
        repeat: false
        onTriggered: {

        }
    }

    function validateName(name){
        name = name.trim()
        if (name.length < 2 || name.length > 36) {
            showError(qsTr("长度限制：2-36字符"))
            return ""
        }
        if (/[^a-zA-Z0-9_.-]/.test(name)) {
            showError(qsTr("支持字符：[a-zA-Z0-9_.-]"))
            return ""
        }
        if (!/^[a-zA-Z0-9]/.test(name) || !/[a-zA-Z0-9]$/.test(name)) {
            showError(qsTr("首字符和尾字符必须为[a-zA-Z0-9]"))
            return ""
        }
        return name
    }

    Component.onCompleted: {
    }

    // 显示启动限制提示
    function showStartLimitMessage() {
        var totalCount = phoneCountSpinBox.value
        var maxCanStart = Math.max(0, root.maxPhones - root.runningDeviceCount)  // 最多可以启动的数量
        var willStartCount = Math.min(totalCount, maxCanStart)  // 实际将启动的数量
        var willStayOffCount = totalCount - willStartCount  // 保持关机状态的数量
        
        var message = qsTr("当前主机可同时运行的云机上限为 %1 台，已有 %2 台正在运行。").arg(root.maxPhones).arg(root.runningDeviceCount)
        if (willStartCount > 0 && willStayOffCount > 0) {
            message += "\n" + qsTr("系统将自动启动其中 %1 台，其余 %2 台将创建完成后保持关机状态。").arg(willStartCount).arg(willStayOffCount)
        } else if (willStartCount > 0) {
            message += "\n" + qsTr("系统将自动启动所有 %1 台。").arg(willStartCount)
        } else {
            message += "\n" + qsTr("所有 %1 台将创建完成后保持关机状态。").arg(willStayOffCount)
        }
        
        showInfo(message, 3000)
    }

    onOpened: {
        root.boolStart = false  // 重置立即启动选项
        root.phoneCount = Math.min(1, root.remainingPhones)
        phoneCountSpinBox.value = root.phoneCount
        nameInput.text = "vmos"
        
        // 重置自动更新安卓属性开关为关闭状态
        if (typeof update_prop_switch !== 'undefined') {
            update_prop_switch.checked = false
        }

        if (root.modelData) {
            console.log("[Debug] hostIp is: ", root.modelData.hostIp)
        }
        btnOk.enabled = true
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
                text: qsTr("克隆云机（不限创建总数）")
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

        ColumnLayout {
            width: parent.width
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            // Layout.margins: 20
            spacing: 15

            FluText {
                text: qsTr("主机地址：%1 （同时运行上限 %2 台）").arg(root.modelData ? root.modelData.hostIp : "").arg(root.maxPhones)
                color: ThemeUI.primaryColor
            }

            ColumnLayout {
                spacing: 5

                FluText {
                    text: qsTr("云机名称：%1").arg(root.modelData ? root.modelData.phoneName : "")
                }

                FluText {
                    text: qsTr("镜像版本：%1").arg(root.modelData ? root.modelData.imgVersion : "")
                }

                FluText {
                    text: qsTr("Android版本：%1").arg(root.modelData ? root.modelData.androidVersion : "")
                }
            }

            RowLayout{
                Layout.topMargin: 5

                FluText {
                    id: textName
                    text: phoneCountSpinBox.value > 1 ? qsTr("克隆名称前缀") : qsTr("克隆名称");
                    font.bold: true
                }
                FluTextBox {
                    id: nameInput
                    Layout.fillWidth: true
                    text: "vmos"
                    placeholderText: qsTr("请输入克隆名称")
                    maximumLength: 11
                }
            }

            ColumnLayout{
                Layout.topMargin: 5

                FluText {
                    text: qsTr("云机数量");
                    font.bold: true
                }

                RowLayout {
                    spacing: 20

                    FluSpinBox{
                        id: phoneCountSpinBox
                        Layout.alignment: Qt.AlignLeft
                        editable: true
                        from: root.remainingPhones >= 1 ? 1 : 0
                        // 根据 boolStart 状态确定最大数值
                        // 如果勾选立即启动，最大数量受限于可运行的槽位（maxPhones - runningDeviceCount）
                        // 如果不勾选立即启动，可以创建更多，最大为 maxPhones
                        to: root.boolStart
                            ? Math.min(root.remainingPhones, root.maxPhones - root.runningDeviceCount)
                            : Math.max(root.remainingPhones, root.maxPhones)
                        value: root.phoneCount
                    }

                    FluText{
                        text: qsTr("单次可克隆云机数量不超过 12 台")
                        color: "#999"
                    }

                    VCheckBox{
                        visible: false
                        id: boolStartCheckBox
                        text: qsTr("自动启动")
                        checked: root.boolStart
                        textColor: ThemeUI.blackColor
                        onClicked: {
                            root.boolStart = checked
                            // 当 boolStart 状态改变时，重新计算并限制数量范围
                            if (checked && phoneCountSpinBox.value > phoneCountSpinBox.to) {
                                phoneCountSpinBox.value = phoneCountSpinBox.to
                                root.phoneCount = phoneCountSpinBox.value
                            }
                        }
                    }
                }

                FluText{
                    text: phoneCountSpinBox.value > 1 ? qsTr("将按前缀自动编号生成%1个云机：").arg(phoneCountSpinBox.value) :  qsTr("将创建%1台云机：").arg(phoneCountSpinBox.value)
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    layoutDirection: Qt.LeftToRight

                    Repeater{
                        model: phoneCountSpinBox.value

                        delegate: FluText{
                            font.pixelSize: 12
                            // 预览显示的名称应该与实际创建后的名称一致
                            // 服务器端会自动添加编号（如果数量>1）和"-clone"后缀
                            text: {
                                var baseName = nameInput.text
                                var suffix = phoneCountSpinBox.value > 1 ? `-${(index + 1).toString().padStart(3, '0')}` : ""
                                // 服务器端会在名称后添加 "-clone" 后缀
                                return baseName + "-clone" + suffix 
                            }
                        }
                    }
                }
            }

            RowLayout {
                FluText {
                    text: qsTr("修改云机参数")
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                }

                FluToggleSwitch {
                    id: update_prop_switch
                    checkColor: ThemeUI.primaryColor
                }
            }

            Item { Layout.preferredHeight: 10 }
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
                id: btnOk
                text: qsTr("确定")
                normalColor: ThemeUI.primaryColor
                onPressed: phoneCountSpinBox.focus = false
                enabled: root.phoneCount > 0
                onClicked: {
                    const num = Number(phoneCountSpinBox.value)
                    if(num <= 0){
                        showError(qsTr("创建云机数量必须大于0"))
                        return
                    }

                    const name = validateName(nameInput.text)
                    if(!name){
                        return
                    }

                    // 禁用按钮，防止重复点击
                    btnOk.enabled = false

                    reqCreateCloneTask(root.modelData?.hostIp ?? "", num, root.modelData?.dbId ?? "", name)
                }
            }
        }
    }

    NetworkCallable {
        id: createCloneTask
        onStart: () => {
                     showLoading(qsTr("克隆中..."))
                 }
        onFinish: () => {
                      hideLoading()
                  }

        onSuccess:
            (result, userData) => {
                btnOk.enabled = true
                try {
                    console.log("[克隆云机]创建克隆云机任务成功！", result);
                    var res = JSON.parse(result);
                    if (res.code === 200) {
                        showSuccess(qsTr("克隆云机任务执行成功"))
                        root.close()
                    }else {
                        showError(res.msg)
                    }
                } catch (e) {
                    hideLoading()
                    showError(qsTr("克隆失败，请重试!"))
                    console.log("[克隆云机]创建克隆云机任务失败！", result);
                    root.close()
                }
            }
        onError: (status, errorString, result, userData) => {
                     hideLoading()
                     showError(qsTr("克隆失败，请重试!"))
                     console.log("[克隆云机]创建克隆云机任务失败！", result, errorString);
                     root.close()
                 }
    }

    function reqCreateCloneTask(ip, count, db_id, user_name) {
        console.log("reqCreateCloneTask, ip: ", ip, " count: ", count, " db_id: ", db_id, " user_name: ", user_name);

        Network.postJson(`http://${ip}:18182/container_api/v1` + "/clone")
        .add("count", count)
        .add("db_id", db_id)
        .add("user_name", user_name)
        .add("update_prop", update_prop_switch.checked)
        .bind(root)
        .go(createCloneTask)
    }

    NetworkCallable {
        id: getCloneStatus
        onSuccess:
            (result, userData) => {
                try {
                    console.log("[查询克隆状态]", result);
                    var res = JSON.parse(result);
                    if (res.code === -1) {
                        console.log("[查询克隆状态]当前主机没有克隆任务！");
                        return
                    }

                    if (res.code === -2) {
                        hideLoading()
                        showError(qsTr("克隆失败，请重试!"))
                        console.log("[查询克隆状态]克隆失败！");
                        cloneStatusTimer.stop()
                        root.close()
                        return
                    }

                    if(res.code === 200 && res.data){
                        // 判断res.data里是否有list
                        if(!res.data.list || res.data.list.length === 0){
                            console.log("[查询克隆状态]正在克隆中...");
                            return
                        }

                        hideLoading()
                        showSuccess(qsTr("云机克隆成功！"))
                        console.log("[查询克隆状态]克隆成功！");

                        cloneStatusTimer.stop()
                        root.close()

                    } else {
                        console.debug("getCloneStatus returned error or no data:", res.msg);
                    }
                } catch (e) {
                    console.error("Error in getCloneStatus.onSuccess:", e);
                }
            }
        onError:
            (status, errorString, result, userData) => {
                console.log("[查询克隆状态]", result);
                var res = JSON.parse(result);
                if (res.code === -1) {
                    console.log("[查询克隆状态]当前主机没有克隆任务！");
                    return
                }

                if (res.code === -2) {
                    hideLoading()
                    showError(qsTr("克隆失败，请重试!"))
                    console.log("[查询克隆状态]克隆失败！");
                    cloneStatusTimer.stop()
                    root.close()
                    return
                }

                hideLoading()
                showError(qsTr("克隆失败，请重试!"))
                console.log("[克隆云机]查询克隆任务失败！", result)
                cloneStatusTimer.stop()
                root.close()
                return
            }
    }

    function reqGetCloneStatus(ip) {
        console.log("reqGetCloneStatus, ip: ", ip);

        Network.get(`http://${ip}:18182/container_api/v1` + "/clone_status")
        .bind(root)
        .go(getCloneStatus)
    }
}
