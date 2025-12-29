import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Utils

FluPopup {
    id: root
    implicitWidth: 500
    padding: 20
    spacing: 15
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property var modelData: null
    property string deviceBrand: ""  // 品牌
    property string deviceModel: ""   // 机型
    property bool isEditingMacvlan: false // 是否正在编辑局域网络
    property string tempMacvlanIp: "" // 临时存储编辑中的局域网络IP

    onOpened: {
        // 重置品牌和机型
        root.deviceBrand = ""
        root.deviceModel = ""
        
        // 重置编辑状态
        root.isEditingMacvlan = false
        root.tempMacvlanIp = modelData?.macvlanIp || ""
        
        // 如果有 hostIp 和 dbId，获取品牌和机型
        if (modelData && modelData.hostIp && (modelData.dbId || modelData.id || modelData.name)) {
            var dbId = modelData.dbId || modelData.id || modelData.name
            reqGetDeviceBrandModel(modelData.hostIp, dbId)
        }
    }

    // 规范化 Android 版本
    function normalizeAndroidVersion(v) {
        var s = (v === undefined || v === null) ? "" : ("" + v)
        var m = s.match(/(\d{1,2})/)
        return m && m[1] ? m[1] : ""
    }

    // 从镜像名称获取 Android 版本
    function getAndroidVersionFromImage(imageName) {
        if (!imageName) return ""
        
        // 首先尝试从 imagesModel 中查找
        if (typeof imagesModel !== 'undefined') {
            for (var i = 0; i < imagesModel.rowCount(); i++) {
                var idx = imagesModel.index(i, 0)
                var n = imagesModel.data(idx, ImagesModel.NameRole).toString()
                var fn = imagesModel.data(idx, ImagesModel.FileNameRole).toString()
                var v = imagesModel.data(idx, ImagesModel.VersionRole).toString()
                if ((imageName && n === imageName) || (imageName && fn === imageName)) {
                    return normalizeAndroidVersion(v)
                }
            }
        }
        
        // 如果找不到，尝试从镜像名称中提取
        var m = imageName.match(/android\s*(\d{1,2})/i)
        if (m && m[1]) return normalizeAndroidVersion(m[1])
        
        return ""
    }

    // 获取镜像版本显示文本
    function getImageVersionText() {
        if (!modelData) return ""
        var image = modelData.image || ""
        if (image) {
            // 如果包含冒号，取冒号后的部分作为版本
            var parts = image.split(":")
            if (parts.length > 1) {
                return parts[0]
            }
            return image
        }
        return ""
    }

    // 获取 Android 版本显示文本
    function getAndroidVersionText() {
        if (!modelData) return ""
        // 优先使用 aospVersion
        if (modelData.aospVersion) {
            return normalizeAndroidVersion(modelData.aospVersion)
        }
        // 其次从镜像名称中提取
        var image = modelData.image || ""
        if (image) {
            // 如果 image 包含冒号，取冒号前的部分
            var imageName = image.split(":")[0]
            return getAndroidVersionFromImage(imageName)
        }
        return ""
    }

    // 调用 shell 接口获取云机品牌和机型
    function reqGetDeviceBrandModel(hostIp, dbId) {
        if (!hostIp || !dbId) {
            console.warn("[云机详情] 获取品牌机型: hostIp 或 dbId 为空")
            return
        }

        // console.log("[云机详情] 请求获取品牌:", hostIp, dbId)
        Network.postJson(`http://${hostIp}:18182/container_api/v1/get_db`)
        .add("name", dbId)
        .add("fields", "brand,model_name")
        .bind(root)
        .go(getDBBrandModel)
    }

    // 修改局域网络
    function reqUpdateMacvlan() {
        if (!modelData) {
            console.warn("[云机详情] 修改局域网络: modelData 为空")
            return
        }
        
        var hostIp = modelData.hostIp
        var dbId = modelData.dbId || modelData.id || modelData.name
        
        if (!hostIp || !dbId) {
            console.warn("[云机详情] 修改局域网络: hostIp 或 dbId 为空")
            showError(qsTr("缺少必要参数"))
            return
        }
        
        if (!root.tempMacvlanIp.trim()) {
            showError(qsTr("请输入局域网络IP地址"))
            return
        }
        
        // IP地址格式验证（简单验证）
        var ipPattern = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
        if (!ipPattern.test(root.tempMacvlanIp.trim())) {
            showError(qsTr("请输入有效的IP地址格式"))
            return
        }
        
        console.log("[云机详情] 请求修改局域网络:", hostIp, dbId, root.tempMacvlanIp)
        
        // 发送修改请求
        Network.postJson(`http://${hostIp}:18182/container_api/v1/set_ip`)
        .add("db_id", dbId)
        .add("ip", root.tempMacvlanIp.trim())
        .bind(root)
        .go(updateMacvlanCallback)
    }

    //  获取品牌机型回调（DB）
    NetworkCallable {
        id: getDBBrandModel
        onError:
            (status, errorString, result, userData) => {
                console.debug("[云机详情] DB获取品牌机型失败:", status, errorString, result)
            }
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result)
                    if(res.code === 200){
                        if (res.data.count > 0 && Array.isArray(res.data.list)) {
                            root.deviceBrand = res.data.list[0].brand
                            root.deviceModel = res.data.list[0].model_name
                        }
                    } else {
                        console.error("[云机详情] 请求品牌机型数据响应失败：", res.msg)
                    }
                } catch (e) {
                    console.error("[云机详情] 解析品牌机型数据失败:", e)
                }
            }
    }

    // 修改局域网络回调
    NetworkCallable {
        id: updateMacvlanCallback
        onStart: {
            showLoading(qsTr("正在修改IP"))
        }
        onFinish: {
            hideLoading()
        }
        onError:
            (status, errorString, result, userData) => {
                console.error("[云机详情] 修改局域网络失败:", status, errorString, result)
                showError(qsTr("修改局域网络失败: ") + errorString)
            }
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result)
                    if(res.code === 200){
                        console.log("[云机详情] 修改局域网络成功")
                        showSuccess(qsTr("修改局域网络成功"))
                        // 更新本地数据
                        if (modelData) {
                            modelData.ip = root.tempMacvlanIp.trim()
                        }
                        
                        // 退出编辑模式
                        root.isEditingMacvlan = false
                    } else {
                        console.error("[云机详情] 修改局域网络返回错误:", res.msg || res.message)
                        // 根据错误代码显示对应的错误信息
                        if (res.code === 1001) {
                            showError(qsTr("修改局域网络失败: 实例不存在"))
                        } else if (res.code === 1002) {
                            showError(qsTr("修改局域网络失败: IP被占用"))
                        } else {
                            showError(qsTr("修改局域网络失败: 未知错误"))
                        }
                    }
                } catch (e) {
                    console.error("[云机详情] 解析修改局域网络返回数据失败:", e)
                    showError(qsTr("解析返回数据失败"))
                }
            }
    }

    ColumnLayout {
        width: parent.width

        // 标题栏
        RowLayout {
            Layout.fillWidth: true
            FluText {
                text: qsTr("云机详情")
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

        // 详情信息
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            // 云机ID
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("云机ID：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: modelData?.dbId ?? modelData?.id ?? ""
                    Layout.fillWidth: true
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var textToCopy = modelData?.dbId ?? modelData?.id ?? ""
                            if (textToCopy) {
                                FluTools.clipText(textToCopy)
                                showSuccess(qsTr("复制成功"))
                            }
                        }
                    }
                }
            }

            // 云机名称
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("云机名称：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: modelData?.displayName ?? modelData?.name ?? ""
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var textToCopy = modelData?.displayName ?? modelData?.name ?? ""
                            if (textToCopy) {
                                FluTools.clipText(textToCopy)
                                showSuccess(qsTr("复制成功"))
                            }
                        }
                    }
                }
            }

            // 镜像版本
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("镜像版本：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: root.getImageVersionText()
                    Layout.fillWidth: true
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var textToCopy = root.getImageVersionText()
                            if (textToCopy) {
                                FluTools.clipText(textToCopy)
                                showSuccess(qsTr("复制成功"))
                            }
                        }
                    }
                }
            }

            // Android版本
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("Android版本：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: root.getAndroidVersionText() ? ("Android " + root.getAndroidVersionText()) : ""
                    Layout.fillWidth: true
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var textToCopy = root.getAndroidVersionText()
                            if (textToCopy) {
                                FluTools.clipText(textToCopy)
                                showSuccess(qsTr("复制成功"))
                            }
                        }
                    }
                }
            }

            // 品牌
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("品牌：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: root.deviceBrand || ""
                    Layout.fillWidth: true
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.deviceBrand) {
                                FluTools.clipText(root.deviceBrand)
                                showSuccess(qsTr("复制成功"))
                            }
                        }
                    }
                }
            }

            // 机型
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("机型：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    text: root.deviceModel || ""
                    Layout.fillWidth: true
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.deviceModel) {
                                FluTools.clipText(root.deviceModel)
                                showSuccess(qsTr("复制成功"))
                            }
                        }
                    }
                }
            }

            // ADB
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("ADB：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }
                FluText {
                    id: adbAddress
                    text: {
                        if (modelData?.networkMode === "macvlan") {
                            if (modelData?.state !== "running") {
                                return "-"
                            }
                        }
                        return modelData?.networkMode === "macvlan" ? `${modelData?.ip ?? ""}:5555` : `${modelData?.hostIp ?? ""}:${modelData?.adb ?? ""}`
                    }

                    Layout.fillWidth: true

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (adbAddress.text) {
                                FluTools.clipText(adbAddress.text)
                                showSuccess(qsTr("复制成功"))
                            }
                        }
                    }
                }
            }

            // 容器网络
            //RowLayout {
            //    Layout.fillWidth: true
            //    spacing: 10
            //    FluText {
            //        text: qsTr("容器网络：")
            //        color: "#666"
            //        Layout.preferredWidth: 120
            //        horizontalAlignment: Text.AlignRight
            //    }
            //    FluText {
            //        text: modelData?.ip ?? modelData?.containerNetwork ?? ""
            //        Layout.fillWidth: true
                    
            //        MouseArea {
            //           anchors.fill: parent
            //            cursorShape: Qt.PointingHandCursor
            //            onClicked: {
            //                var textToCopy = modelData?.ip ?? modelData?.containerNetwork ?? ""
            //                if (textToCopy) {
            //                    FluTools.clipText(textToCopy)
            //                    showSuccess(qsTr("复制成功"))
            //                }
            //            }
            //        }
            //    }
            //}

            // 局域网络 - 修改为可编辑模式
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                FluText {
                    text: qsTr("局域网络：")
                    color: "#666"
                    Layout.preferredWidth: 120
                    horizontalAlignment: Text.AlignRight
                }

                // 显示/编辑 两种模式的紧凑元素，使用 visible 控制切换
                FluText {
                    id: macvlanText
                    text: modelData?.networkMode === "macvlan" ? (modelData?.ip || "") : "-"
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    visible: !root.isEditingMacvlan
                }

                Image {
                    id: btnEditLanIP_detail
                    width: 20
                    height: 20
                    source: "qrc:/res/pad/yunji_edit.svg"
                    visible: !root.isEditingMacvlan && modelData?.networkMode === "macvlan"
                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            // 检查是否有该设备的窗口已打开
                            var dbId = modelData?.dbId || modelData?.id || modelData?.name || ""
                            if (dbId && FluRouter.hasWindowByFingerprint(dbId)) {
                                console.log("[云机详情] 检测到设备窗口已打开，询问用户是否关闭，dbId:", dbId)
                                // 显示确认对话框
                                closeWindowDialog.title = qsTr("操作确认")
                                closeWindowDialog.message = qsTr("当前云机正在投屏，修改网络 IP 会导致投屏中断并退出。是否继续？")
                                closeWindowDialog.positiveText = qsTr("确定")
                                closeWindowDialog.negativeText = qsTr("取消")
                                closeWindowDialog.onNegativeClickListener = function(){
                                    closeWindowDialog.close()
                                }
                                closeWindowDialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                closeWindowDialog.onPositiveClickListener = function(){
                                    var dbId = modelData?.dbId || modelData?.id || modelData?.name || ""
                                    if (dbId) {
                                        console.log("[云机详情] 用户确认关闭窗口，dbId:", dbId)
                                        FluRouter.closeWindowByFingerprint(dbId)
                                        // 等待窗口关闭完成
                                        Qt.callLater(function() {
                                            root.tempMacvlanIp = modelData?.macvlanIp || ""
                                            root.isEditingMacvlan = true
                                        })
                                    }
                                    closeWindowDialog.close()
                                }
                                closeWindowDialog.open()
                            } else {
                                // 没有窗口打开，直接进入编辑模式
                                root.tempMacvlanIp = modelData?.macvlanIp || ""
                                root.isEditingMacvlan = true
                            }
                        }
                    }
                }

                // 编辑模式的紧凑控件
                FluTextBox {
                    id: macvlanInput
                    Layout.preferredWidth: 220
                    Layout.maximumWidth: 360
                    cleanEnabled: false
                    placeholderText: qsTr("请输入局域网络IP")
                    text: root.tempMacvlanIp
                    visible: root.isEditingMacvlan
                    onTextChanged: root.tempMacvlanIp = text
                    Keys.onReturnPressed: reqUpdateMacvlan()
                    Keys.onEscapePressed: root.isEditingMacvlan = false
                }
                FluFilledButton {
                    text: qsTr("确定")
                    visible: root.isEditingMacvlan
                    onClicked: {
                        closeWindowDialog.title = qsTr("操作确认")
                        closeWindowDialog.message = qsTr("修改IP需要重启云机，是否继续操作")
                        closeWindowDialog.positiveText = qsTr("确定")
                        closeWindowDialog.negativeText = qsTr("取消")
                        closeWindowDialog.onNegativeClickListener = function(){
                            closeWindowDialog.close()
                        }
                        closeWindowDialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                        closeWindowDialog.onPositiveClickListener = function(){
                            reqUpdateMacvlan()
                            closeWindowDialog.close()
                        }
                        closeWindowDialog.open()
                    }
                }

                // 填充剩余空间，确保上面的元素靠左紧凑显示
                Item { Layout.fillWidth: true }
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

    // 确认关闭窗口对话框
    GenericDialog {
        id: closeWindowDialog
        title: qsTr("操作确认")
        message: qsTr("检测到该设备的窗口已打开，编辑IP前需要先关闭窗口。是否继续？")
        positiveText: qsTr("确定")
        negativeText: qsTr("取消")
        buttonFlags: FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
        onPositiveClickListener: function() {
            var dbId = modelData?.dbId || modelData?.id || modelData?.name || ""
            if (dbId) {
                console.log("[云机详情] 用户确认关闭窗口，dbId:", dbId)
                FluRouter.closeWindowByFingerprint(dbId)
                // 等待窗口关闭完成
                Qt.callLater(function() {
                    root.tempMacvlanIp = modelData?.macvlanIp || ""
                    root.isEditingMacvlan = true
                })
            }
            closeWindowDialog.close()
        }
        onNegativeClickListener: function() {
            console.log("[云机详情] 用户取消关闭窗口")
            closeWindowDialog.close()
        }
    }
}
