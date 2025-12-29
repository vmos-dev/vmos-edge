import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Utils

FluPopup {
    id: root
    implicitWidth: 420
    padding: 0
    closePolicy: Popup.CloseOnEscape
    focus: true
    
    property var modelData: null
    property string cloudMachineName: ""
    property var selectedDeviceList: [] // 用于存储批量操作时选中的云机列表
    
    signal proxySettingsResult(bool success, var settings)
    
    property var proxyProtocols: [
        "HTTP",
        "HTTPS",
        "SOCKS5"
    ]
    
    // 当前显示的页面：0-设置页面，1-信息页面
    property int currentPage: 0
    
    // 代理信息
    property string proxyInfo: ""
    property string proxyStatus: ""
    property string domainResolutionMode: ""
    property string proxyIp: ""
    property string proxyLocation: ""
    
    function validateServerAddress(address) {
        if (!address || address.trim() === "") {
            showError(qsTr("服务器地址不能为空"))
            return false
        }
        if (!AppUtils.isValidIp(address) && !AppUtils.isValidDomain(address)) {
            showError(qsTr("无效的服务器地址: ") + address, 3000);
            return false;
        }
        return true
    }
    
    function validatePort(port) {
        if (!port || port.trim() === "") {
            showError(qsTr("服务器端口不能为空"))
            return false
        }
        var portNum = parseInt(port)
        if (isNaN(portNum) || portNum < 1 || portNum > 65535) {
            showError(qsTr("请输入正确的端口号(1-65535)"))
            return false
        }
        return true
    }

    function validateAccount(account) {
        // if (!account || account.trim() === "") {
        //     showError(qsTr("账号不能为空"))
        //     return false
        // }
        return true
    }
    
    function validatePassword(password) {
        // if (!password || password.trim() === "") {
        //     showError(qsTr("密码不能为空"))
        //     return false
        // }
        return true
    }
    
    function testNetwork() {
        // 验证输入参数
        if (!validateServerAddress(serverAddressInput.text)) {
            return
        }
        
        if (!validatePort(portInput.text)) {
            return
        }
        
        if (!validateAccount(accountInput.text)) {
            return
        }
        
        if (!validatePassword(passwordInput.text)) {
            return
        }
        
        showLoading(qsTr("正在检测代理连接..."))
        
        // 获取协议类型
        var protocol = "socks5"
        if("HTTP" === root.proxyProtocols[protocolComboBox.currentIndex] || "HTTPS" === root.proxyProtocols[protocolComboBox.currentIndex]){
            protocol = "http"
        }
        // // 获取协议类型
        // var protocol = root.proxyProtocols[protocolComboBox.currentIndex].toLowerCase()

        // 调用C++网络检测
        proxyTester.testProxy(
                    serverAddressInput.text.trim(),
                    parseInt(portInput.text),
                    accountInput.text.trim(),
                    passwordInput.text,
                    protocol,
                    "https://www.baidu.com"
                    )
    }

    onAboutToShow: {
        // 先清空输入框
        serverAddressInput.text = ""
        portInput.text = ""
        accountInput.text = ""
        passwordInput.text = ""
        
        // 重置开关状态
        udpEnabledSwitch.checked = true
        dnsOverProxyEnabledSwitch.checked = true
        
        // 重置到设置页面
        root.currentPage = 0

        // 如果是批量操作，不需要获取单个设备的代理信息
        if (root.selectedDeviceList && root.selectedDeviceList.length > 0) {
            console.log("批量设置代理模式，共选中" + root.selectedDeviceList.length + "台云机")
        } else if (modelData) {
            // 获取单个设备代理信息
            reqGetDeviceProxy(modelData.hostIp, modelData.dbId)
        }
    }
    

    // 页面1：代理设置页面
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
                    text: root.selectedDeviceList && root.selectedDeviceList.length > 0 ? 
                          qsTr("批量设置代理（选中云机数量：%1）").arg(root.selectedDeviceList.length) : 
                          qsTr("设置代理（云机名称：%1）").arg(root.modelData?.displayName ?? "")
                    font.bold: true
                    font.pixelSize: 16
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    Layout.preferredWidth: 320
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

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentPage


            ColumnLayout {
                spacing: 0
                
                ColumnLayout{
                    Layout.margins: 20

                    // 代理协议
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        FluText {
                            text: qsTr("代理协议")
                            font.bold: true
                        }

                        FluComboBox {
                            id: protocolComboBox
                            Layout.fillWidth: true
                            model: root.proxyProtocols
                            currentIndex: 2 // 默认选择SOCKS5
                        }
                    }

                    // 服务器地址
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        FluText {
                            text: qsTr("服务器地址")
                            font.bold: true
                        }

                        FluTextBox {
                            id: serverAddressInput
                            Layout.fillWidth: true
                            placeholderText: qsTr("请输入服务器地址")
                        }
                    }

                    // 服务端口
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        FluText {
                            text: qsTr("服务端口")
                            font.bold: true
                        }

                        FluTextBox {
                            id: portInput
                            Layout.fillWidth: true
                            placeholderText: qsTr("请输入正确的端口")
                            validator: IntValidator {
                                bottom: 1
                                top: 65535
                            }
                        }
                    }

                    // 账号选择
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        FluText {
                            text: qsTr("账号")
                            font.bold: true
                        }

                        FluTextBox {
                            id: accountInput
                            Layout.fillWidth: true
                            placeholderText: qsTr("请输入账号")
                        }
                    }

                    // 密码
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        FluText {
                            text: qsTr("密码")
                            font.bold: true
                        }

                        FluTextBox {
                            id: passwordInput
                            Layout.fillWidth: true
                            placeholderText: qsTr("请输入密码")
                            echoMode: TextInput.Password
                        }
                    }

                    //是否禁用DNS走代理
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            FluText {
                                text: qsTr("代理DNS")
                                font.bold: true
                            }

                            Image {
                                id: macvlanIcon
                                source: "qrc:/res/pad/help.svg"
                                scale: 0.8

                                FluTooltip {
                                    parent: macvlanIcon
                                    visible: macvlanMouseArea.containsMouse
                                    text: qsTr("开启代理DNS需要确保您的代理IP支持DNS解析，\n否则云手机将无法联网；关闭代理DNS可能会导致DNS泄露。")
                                    delay: 500
                                    timeout: 3000
                                }

                                MouseArea {
                                    id: macvlanMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }
                            }

                            FluToggleSwitch{
                                id: dnsOverProxyEnabledSwitch
                                checkColor: ThemeUI.primaryColor
                            }

                            FluText{
                                text: qsTr("注意：如果开启后云手机无网络，请关闭代理DNS。")
                                color: ThemeUI.primaryColor
                                font.pixelSize: 10
                            }
                        }

                    }

                    // 是否禁用UDP
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        FluText {
                            text: qsTr("开启UDP")
                            font.bold: true
                        }

                        Image {
                            id: udpIcon
                            source: "qrc:/res/pad/help.svg"
                            scale: 0.8

                            FluTooltip {
                                parent: udpIcon
                                visible: udpMouseArea.containsMouse
                                text: qsTr("启用 UDP 通道传输")
                                delay: 500
                                timeout: 3000
                            }

                            MouseArea {
                                id: udpMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }

                        FluToggleSwitch{
                            id: udpEnabledSwitch
                            checkColor: ThemeUI.primaryColor
                        }
                    }

                    Item { Layout.preferredHeight: 10 }
                    RowLayout {
                        Layout.preferredHeight: 33
                    // 网络检测链接
                        FluText {
                            Layout.leftMargin: 0
                            text: qsTr("检查代理")
                            color: ThemeUI.primaryColor
                            font.underline: true
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    testNetwork()
                                }
                            }
                        }
                        // Item { Layout.fillWidth: true }
                        // FluButton {
                        //     Layout.rightMargin: 0
                        //     text: (root.selectedDeviceList && root.selectedDeviceList.length > 0) ?
                        //           qsTr("一键关闭所有代理") : qsTr("关闭代理")
                        //     textColor: "#FF3F42"
                        //     normalColor: "#FFF0F1"
                        //     onClicked: {
                        //         // 显示二次确认弹窗
                        //         var isBatch = root.selectedDeviceList && root.selectedDeviceList.length > 0
                        //         dialog.title = qsTr("操作确认")
                        //         dialog.message = isBatch ?
                        //             qsTr("确定要清除所有选中云机的代理设置吗？") :
                        //             qsTr("确定要清除该云机的代理设置吗？")
                        //         dialog.positiveText = qsTr("确定")
                        //         dialog.negativeText = qsTr("取消")
                        //         dialog.showPrompt = false
                        //         dialog.onNegativeClickListener = function(){
                        //             dialog.close()
                        //         }
                        //         dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                        //         dialog.onPositiveClickListener = function(){
                        //             clearAllProxies()
                        //             dialog.close()
                        //         }
                        //         dialog.open()
                        //     }
                        // }
                     } 

                    Item { Layout.fillHeight: true }

                    // 操作按钮
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        Layout.rightMargin: 20
                        spacing: 30

                        Item { Layout.fillWidth: true }

                        FluButton {
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 32
                            text: qsTr("取消")
                            onClicked: root.close()
                        }

                        

                        FluFilledButton {
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 32
                            text: qsTr("确定")
                            normalColor: ThemeUI.primaryColor
                            onClicked: {
                                // 验证输入
                                if (!validateServerAddress(serverAddressInput.text)) {
                                    return
                                }

                                if (!validatePort(portInput.text)) {
                                    return
                                }

                                if (!validateAccount(accountInput.text)) {
                                    return
                                }

                                if (!validatePassword(passwordInput.text)) {
                                    return
                                }

                                // 协议
                                var protocol = "socks5"
                                if("HTTP" === root.proxyProtocols[protocolComboBox.currentIndex] || "HTTPS" === root.proxyProtocols[protocolComboBox.currentIndex]){
                                    protocol = "http-relay"
                                }

                                // 构建设置对象
                                var settings = {
                                    protocol: protocol,
                                    serverAddress: serverAddressInput.text.trim(),
                                    port: parseInt(portInput.text),
                                    account: accountInput.text.trim(),
                                    password: passwordInput.text.trim(),
                                    // udpDisabled: false,  // 默认值：UDP启用
                                    // dnsOverProxyDisabled: false  // 默认值：DNS走代理启用
                                    udpDisabled: !udpEnabledSwitch.checked,
                                    dnsOverProxyDisabled: !dnsOverProxyEnabledSwitch.checked
                                }

                                // 判断是批量设置还是单个设置
                                if (root.selectedDeviceList && root.selectedDeviceList.length > 0) {
                                    // 批量设置代理
                                    batchSetProxies(settings)
                                } else if (root.modelData) {
                                    // 单个设置代理
                                    reqSetDeviceProxy(root.modelData.hostIp, root.modelData.dbId, protocol,
                                                     settings.serverAddress, settings.port, 
                                                     settings.account, settings.password, 
                                                     settings.dnsOverProxyDisabled, settings.udpDisabled)
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
            

            // 页面2：代理信息页面
            ColumnLayout {
                spacing: 0

                // 代理信息内容
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    spacing: 20

                    // S5地址
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        FluText {
                            text: qsTr("代理地址")
                            Layout.preferredWidth: 120
                            font.bold: true
                        }

                        FluTextBox {
                            Layout.fillWidth: true
                            text: root.proxyInfo
                            readOnly: true
                            background: Rectangle {
                                color: "#F5F5F5"
                                border.color: "#E0E0E0"
                                border.width: 1
                                radius: 4
                            }
                        }
                    }

                    // 代理IP
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        FluText {
                            text: qsTr("代理IP")
                            Layout.preferredWidth: 120
                            font.bold: true
                        }

                        FluTextBox {
                            Layout.fillWidth: true
                            text: root.proxyIp || ""
                            readOnly: true
                            background: Rectangle {
                                color: "#F5F5F5"
                                border.color: "#E0E0E0"
                                border.width: 1
                                radius: 4
                            }
                        }
                    }

                    // 状态
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        FluText {
                            text: qsTr("状态")
                            Layout.preferredWidth: 120
                            font.bold: true
                        }

                        FluTextBox {
                            Layout.fillWidth: true
                            text: root.proxyStatus
                            readOnly: true
                            background: Rectangle {
                                color: "#F5F5F5"
                                border.color: "#E0E0E0"
                                border.width: 1
                                radius: 4
                            }
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
                            text: qsTr("关闭代理")
                            normalColor: ThemeUI.primaryColor
                            onClicked: {
                                reqCloseDeviceProxy(root.modelData.hostIp, root.modelData.dbId)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // 网络检测组件
    ProxyTester {
        id: proxyTester
        
        onTestCompleted: function(success, message, latency) {
            hideLoading()
            if (success) {
                showSuccess(message, 3000)
            } else {
                showError(message)
            }
        }
        
        onTestProgress: function(message) {
            // 可以在这里显示进度信息
            console.log("代理检测进度:", message)
        }
    }

    NetworkCallable {
        id: getDeviceProxy
        onStart: {
            showLoading(qsTr("查询代理信息..."))
        }
        onFinish: {
            hideLoading()
            root.forceActiveFocus()
        }
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                try {
                    const res = JSON.parse(result)
                    if(res.code == 200){
                        // 检查是否有代理配置信息
                        if(res.data && res.data.proxy_config) {
                            // 有代理配置信息，切换到信息页面
                            const proxyConfig = res.data.proxy_config
                            
                            // 构建代理信息字符串
                            root.proxyInfo = `${proxyConfig.proxyType}://${proxyConfig.ip}:${proxyConfig.port}`
                            root.proxyStatus = qsTr("已启动")
                            root.domainResolutionMode = qsTr("服务端域名解析 (默认)")
                            
                            // 设置代理IP和位置信息
                            root.proxyIp = proxyConfig.ip
                            // root.proxyLocation = `${proxyConfig.city}, ${proxyConfig.region}, ${proxyConfig.country}`
                            
                            // 填充输入框（用于编辑）
                            serverAddressInput.text = proxyConfig.ip
                            portInput.text = proxyConfig.port
                            if(proxyConfig.account) {
                                accountInput.text = proxyConfig.account
                            }
                            if(proxyConfig.password) {
                                passwordInput.text = proxyConfig.password
                            }
                            
                            // 设置开关状态
                            // if(proxyConfig.udpDisabled !== undefined) {
                            //     udpDisabledSwitch.checked = proxyConfig.udpDisabled
                            // }
                            // if(proxyConfig.dnsOverProxyDisabled !== undefined) {
                            //     dnsOverProxyDisabledSwitch.checked = proxyConfig.dnsOverProxyDisabled
                            // }
                            
                            // 切换到代理信息页面
                            root.currentPage = 1
                        } else {
                            // 没有代理配置信息，显示设置页面
                            root.currentPage = 0
                        }
                    }else{
                        showError(res.msg, 3000)
                    }
                } catch (e) {
                    console.warn("无法将行解析为JSON:", result, e)
                }
            }
    }

    // 获取代理
    function reqGetDeviceProxy(ip, dbId){
        Network.get(`http://${ip}:18182/android_api/v1` + "/proxy_get/" + dbId)
        .setUserData(ip)
        .bind(root)
        .go(getDeviceProxy)
    }

    NetworkCallable {
        id: setDeviceProxy
        onStart: {
            showLoading(qsTr("正在设置代理..."))
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
                try {
                    const res = JSON.parse(result)
                    if(res.code == 200){
                        // 设置代理成功，显示成功消息
                        showSuccess(qsTr("操作成功！"))
                        root.close()
                    }else{
                        showError(res.msg, 3000)
                    }
                } catch (e) {
                    console.warn("无法将行解析为JSON:", result, e)
                    showError(qsTr("设置代理失败，请重试！"))
                }
            }
    }

    // 设置代理
    function reqSetDeviceProxy(hostIp, dbId, protocol, ip, port, account, password, dnsOverProxyDisabled = false, udpDisabled = false){
        Network.postJson(`http://${hostIp}:18182/android_api/v1` + "/proxy_set/" + dbId)
        .add("ip", ip)
        .add("port", port)  // 接口要求使用port参数
        .add("account", account)
        .add("password", password)
        .add("proxyName", protocol)
        .add("dnsOverProxyDisabled", dnsOverProxyDisabled)
        .add("udpDisabled", udpDisabled)
        .setUserData(hostIp)
        .bind(root)
        .go(setDeviceProxy)
    }
    
    // 批量设置代理
    function batchSetProxies(settings) {
        showLoading(qsTr("正在批量设置代理..."))
        
        var failedDevices = []
        var completedCount = 0
        var totalDevices = root.selectedDeviceList.length
        
        // 按hostIp分组
        var devicesByHost = {}
        root.selectedDeviceList.forEach(device => {
            if (!devicesByHost[device.hostIp]) {
                devicesByHost[device.hostIp] = []
            }
            devicesByHost[device.hostIp].push(device)
        })
        
        // 对每组设备进行批量设置
        for (var hostIp in devicesByHost) {
            const devices = devicesByHost[hostIp]
            
            devices.forEach(function(device) {
                // 使用闭包捕获 device 信息
                var deviceName = device.displayName
                var deviceHostIp = hostIp
                
                // 创建临时的 NetworkCallable 对象
                var batchCallable = Qt.createQmlObject('
                    import Utils
                    NetworkCallable {}
                ', root)
                
                // 设置成功回调（使用闭包捕获变量）
                batchCallable.onSuccess.connect(function(result, userData) {
                    completedCount++
                    try {
                        const res = JSON.parse(result)
                        if (res.code !== 200) {
                            failedDevices.push(deviceName)
                        }
                    } catch (e) {
                        failedDevices.push(deviceName)
                    }
                    checkBatchComplete()
                    // 延迟清理对象
                    Qt.callLater(function() {
                        if (batchCallable) {
                            batchCallable.destroy()
                        }
                    })
                })
                
                // 设置错误回调
                batchCallable.onError.connect(function(status, errorString, result, userData) {
                    completedCount++
                    failedDevices.push(deviceName)
                    checkBatchComplete()
                    // 延迟清理对象
                    Qt.callLater(function() {
                        if (batchCallable) {
                            batchCallable.destroy()
                        }
                    })
                })
                
                Network.postJson(`http://${deviceHostIp}:18182/android_api/v1` + "/proxy_set/" + device.dbId)
                .add("ip", settings.serverAddress)
                .add("port", settings.port)  // 接口要求使用port参数
                .add("account", settings.account)
                .add("password", settings.password)
                .add("proxyName", "")  // 保留proxyName参数
                .add("dnsOverProxyDisabled", settings.dnsOverProxyDisabled)
                .add("udpDisabled", settings.udpDisabled)
                .setUserData({hostIp: deviceHostIp, deviceName: deviceName})
                .bind(root)
                .go(batchCallable)
            })
        }
        
        function checkBatchComplete() {
            if (completedCount >= totalDevices) {
                hideLoading()
                if (failedDevices.length === 0) {
                    showSuccess(qsTr("操作成功！"))
                    root.close()
                } else {
                    showError(qsTr("云机：") + failedDevices.join(qsTr("、")) + qsTr("设置代理失败，请重试！"))
                }
            }
        }
    }
    
    // 清除所有代理
    function clearAllProxies() {
        showLoading(qsTr("正在清除代理..."))
        
        var failedCount = 0
        var completedCount = 0
        var deviceList = []
        
        // 判断是批量操作还是单台操作
        if (root.selectedDeviceList && root.selectedDeviceList.length > 0) {
            // 批量操作：使用 selectedDeviceList
            deviceList = root.selectedDeviceList
        } else if (root.modelData) {
            // 单台操作：使用 modelData
            deviceList = [root.modelData]
        } else {
            // 没有设备，直接结束
            hideLoading()
            showError(qsTr("没有可操作的设备"))
            return
        }
        
        var totalDevices = deviceList.length
        
        // 如果没有设备，直接结束
        if (totalDevices === 0) {
            hideLoading()
            return
        }
        
        // 按hostIp分组
        var devicesByHost = {}
        deviceList.forEach(device => {
            if (!devicesByHost[device.hostIp]) {
                devicesByHost[device.hostIp] = []
            }
            devicesByHost[device.hostIp].push(device)
        })
        
        // 对每组设备进行批量清除
        for (var hostIp in devicesByHost) {
            const devices = devicesByHost[hostIp]
            
            devices.forEach(function(device) {
                // 使用闭包捕获 hostIp
                var deviceHostIp = hostIp
                
                // 创建临时的 NetworkCallable 对象
                var clearCallable = Qt.createQmlObject('
                    import Utils
                    NetworkCallable {}
                ', root)
                
                // 设置成功回调
                clearCallable.onSuccess.connect(function(result, userData) {
                    completedCount++
                    try {
                        const res = JSON.parse(result)
                        if (res.code !== 200) {
                            failedCount++
                        }
                    } catch (e) {
                        failedCount++
                    }
                    checkClearComplete()
                    // 延迟清理对象
                    Qt.callLater(function() {
                        if (clearCallable) {
                            clearCallable.destroy()
                        }
                    })
                })
                
                // 设置错误回调
                clearCallable.onError.connect(function(status, errorString, result, userData) {
                    completedCount++
                    failedCount++
                    checkClearComplete()
                    // 延迟清理对象
                    Qt.callLater(function() {
                        if (clearCallable) {
                            clearCallable.destroy()
                        }
                    })
                })
                
                Network.get(`http://${deviceHostIp}:18182/android_api/v1` + "/proxy_stop/" + device.dbId)
                .setUserData(deviceHostIp)
                .bind(root)
                .go(clearCallable)
            })
        }
        
        function checkClearComplete() {
            if (completedCount >= totalDevices) {
                hideLoading()
                if (failedCount === 0) {
                    showSuccess(qsTr("操作成功！"))
                } else {
                    showError(qsTr("操作失败，请重试！"))
                }
            }
        }
    }

    NetworkCallable {
        id: closeDeviceProxy
        onStart: {
            showLoading(qsTr("正在关闭代理..."))
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
                try {
                    const res = JSON.parse(result)
                    if(res.code == 200){
                        // 关闭代理成功，显示成功消息
                        showSuccess(qsTr("操作成功！"))
                        
                        // 调用查询代理接口获取最新状态
                        reqGetDeviceProxy(root.modelData.hostIp, root.modelData.dbId)
                    }else{
                        showError(res.msg, 3000)
                    }
                } catch (e) {
                    console.warn("无法将行解析为JSON:", result, e)
                }
            }
    }

    // 取消代理
    function reqCloseDeviceProxy(hostIp, dbId){
        Network.get(`http://${hostIp}:18182/android_api/v1` + "/proxy_stop/" + dbId)
        .setUserData(hostIp)
        .bind(root)
        .go(closeDeviceProxy)
    }
}
