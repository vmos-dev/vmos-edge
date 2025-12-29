import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine
import QtWebChannel
import FluentUI
import Qt.labs.platform
import Utils

FluWindow {
    id: root
    visible: true
    width: 1180
    height: 700
    fitsAppBarWindows: true
    title: AppConfig.projectTitle
    useSystemAppBar: false
    showClose: false
    showMinimize: false
    showMaximize: false
    showDark: false


    property var groupList: []
    property int refreshCount: 0
    property var batchControlVideo: null
    property var batchControlVideoWebrtc: null
    property var activeBannerList: []
    property var activityListModel: []
    property var proxyCountryModel: []
    property var existCountrySet: null
    property string androidDownloadUrl: ""
    property real cloudUsedPercent: 0.0
    readonly property int tokenTimestamp: 12 * 60 * 60 * 1000
    property int previousIndexBeforeTemplate: 0
    property real lon: 0.0  // 经度
    property real lat: 0.0  // 纬度
    property string deviceLocale: "en-US"  // 语言
    property string timezone: "UTC"  // 时区
    property string country: "CN"  // 国家
    property bool wipeData: true  // 是否清理数据


    onWindowStateChanged:
        (windowState) => {
            if (windowState === Qt.WindowNoState) {
                console.log("窗口从最大化状态还原了")
                btnRestore.visible = false
                btnMax.visible = true
            } else if (windowState === Qt.WindowMaximized) {
                console.log("窗口最大化")
                btnRestore.visible = true
                btnMax.visible = false
            }
        }

    Component.onCompleted: {
        existCountrySet = new Set()
        root.appBar.height = 56
        setHitTestVisible(layout_appbar)
        // setHitTestVisible(leftPage)
        setHitTestVisible(layout_title)



        // 设置上传域名和headers
        const headers = {
            pcVersion: AppConfig.versionCode,
            clientType: AppConfig.client,
            channel: AppConfig.channel,
            supplierType: "0",
            terminalType: "win",
            userId: SettingsHelper.get("userId"),
            token: SettingsHelper.get("token")
        };

        // uploadManager.setUserId(SettingsHelper.get("userId"))
        // uploadManager.setApiBaseUrl(AppConfig.apiHost)
        // uploadManager.setHeaders(headers)

        ReportHelper.reportLog("active")
        ReportHelper.reportLog("home_style", { label: "stream", str1: SettingsHelper.get("viewDirection", 0) == 0 ? "vertical" : "horizontal", str2: SettingsHelper.get("viewSize", 2) == 2 ? "big" : SettingsHelper.get("viewSize", 2) == 1 ? "middle" : "small"})

        // 扫描主机
        scanner.startDiscovery(3000)
        phoneListTimer.start()
        deviceListTimer.start()
        
        // 初始化CBS文件
        initCbsFile()
        
        // 查询位置信息（每次启动都调用接口更新）
        console.log("启动时调用IP信息接口进行更新")
        reqIpInfo()
    }

    Component.onDestruction: {

        // clipboardModel.saveConfig()
    }

    function checkIsEventSync(){
        return false
    }

    // 连接设备（根据配置选择TCP直接连接或ADB模式）
    function connectDeviceSmart(model) {
        if (!model || model.state !== "running") {
            return false
        }
        
        const hostIp = model.hostIp || ""
        const adb = model.adb || 0
        const dbId = model.dbId || model.db_id || model.name || ""
        const useDirectTcp = model.networkMode === "macvlan"
        // 根据配置选择连接模式
        if (AppConfig.useDirectTcp) {
            // TCP直接连接模式：先启动 scrcpy_server，再连接

            const tcpVideoPort = useDirectTcp ? 9999 : (model.tcpVideoPort || 0)
            const tcpAudioPort = useDirectTcp ? 9998 : (model.tcpAudioPort || 0)
            const tcpControlPort = useDirectTcp ? 9997 : (model.tcpControlPort || 0)
            const realIP = useDirectTcp ? model.ip : hostIp;
            console.log("使用TCP直接连接模式 (networkMode=" + model.networkMode + "):", hostIp, dbId, "ports:", tcpVideoPort, tcpAudioPort, tcpControlPort)
            

            console.log("scrcpy_server 启动成功，开始连接设备")
            deviceManager.connectDeviceDirectTcp(
                dbId,           // serial
                realIP,         // host
                tcpVideoPort,   // videoPort
                tcpAudioPort,   // audioPort
                tcpControlPort  // controlPort
            )

        } else {
            // ADB连接模式（bridge 或默认模式）
            const deviceAddress = `${realIP}:${adb}`
            console.log("使用ADB连接模式 (networkMode=" + networkMode + "):", deviceAddress)
            deviceManager.connectDevice(deviceAddress)
        }
        
        return true
    }
    function checkAtLeastOne(podList, flag, num){
        num = num || 1
        if(podList.length < num){
            if(num === 1){
                showError(qsTr("至少选择1台云机"))
            }else if(num === 2){
                showError(qsTr("至少选择2台云机"))
            }
            return false
        }

        let totalCount = 0
        let powerOffCount = 0
        let normalCount = 0
        let exceptionCount = 0
        let offlineCount = 0
        var creatingCount = 0
        for(let i = 0; i < podList.length; ++i){
            totalCount++
            if(podList[i].state === "running"){
                normalCount++
            }
            else if(podList[i].state === "exited" || podList[i].state === "stopped"){
                powerOffCount++
            }
            else if(podList[i].state === "offline"){
                offlineCount++
            }
            else{
                if(podList[i].state === "creating"){
                    creatingCount++
                }
                exceptionCount++
            }
        }

        console.log(totalCount, powerOffCount, normalCount, exceptionCount, offlineCount)
        // flag 1、正常设备 2、关机设备 3、正常和关机设备 4、不包含创建中设备
        if(flag === 0){
            if(offlineCount > 0){
                showError(qsTr("不能包含离线设备，请重新选择"))
                return false
            }
        }
        else if(flag === 1){
            if(offlineCount > 0){
                showError(qsTr("不能包含离线设备，请重新选择"))
                return false
            }
            if(powerOffCount > 0){
                showError(qsTr("不能包含关机设备，请重新选择"))
                return false
            }
            if(exceptionCount > 0){
                showError(qsTr("不能包含异常设备，请重新选择"))
                return false
            }
        }else if(flag === 2){
            if(offlineCount > 0){
                showError(qsTr("不能包含离线设备，请重新选择"))
                return false
            }
            if(normalCount > 0){
                showError(qsTr("不能包含已开机设备，请重新选择"))
                return false
            }
            if(exceptionCount > 0){
                showError(qsTr("不能包含异常设备，请重新选择"))
                return false
            }
        }else if(flag === 3){
            if(offlineCount > 0){
                showError(qsTr("不能包含离线设备，请重新选择"))
                return false
            }
            if(exceptionCount > 0){
                showError(qsTr("不能包含异常设备，请重新选择"))
                return false
            }
        }else if(flag === 4){
            if(creatingCount > 0){
                showError(qsTr("不能包含创建中设备，请重新选择"))
                return false
            }
        }

        return true
    }

    // 是否小于3天
    function isLessThan3Days(milliseconds) {
        var currentDate = new Date();  // 当前时间
        var currentTimestamp = currentDate.getTime();  // 当前时间戳（单位为毫秒）

        // 计算时间戳差值
        var timeDiff = milliseconds - currentTimestamp;  // 毫秒差值

        // 3天的毫秒数（3天 * 24小时 * 60分钟 * 60秒 * 1000毫秒）
        var threeDaysInMilliseconds = 3 * 24 * 60 * 60 * 1000;

        // 判断差值是否小于3天
        if (timeDiff < threeDaysInMilliseconds) {
            return true;  // 差值小于3天
        } else {
            return false;  // 差值不小于3天
        }
    }

    // 还剩多少时间
    function formatRemainingTime(milliseconds) {
        var currentDate = new Date();  // 当前时间
        var targetDate = new Date(milliseconds);  // 目标时间

        // 计算剩余时间（毫秒数）
        var timeDiff = targetDate - currentDate;  // 目标时间减去当前时间，单位为毫秒

        if (timeDiff <= 0) {
            return "云机已过期";
        }

        // 将剩余时间转换为天、小时、分钟、秒
        var days = Math.floor(timeDiff / (1000 * 60 * 60 * 24));
        var hours = Math.floor((timeDiff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
        var minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));
        var seconds = Math.floor((timeDiff % (1000 * 60)) / 1000);

        // 根据剩余时间生成数组，按优先级添加时间单位
        var timeParts = [];

        if (days > 0) timeParts.push(days + qsTr("天"));
        if (hours > 0 || timeParts.length > 0) timeParts.push(hours + qsTr("时"));
        if (minutes > 0 || timeParts.length > 0) timeParts.push(minutes + qsTr("分"));
        if (seconds > 0 || timeParts.length > 0) timeParts.push(seconds + qsTr("秒"));

        // 保留前三部分
        return timeParts.slice(0, 2).join("");
    }

    // 用了多少时间
    function formatStartupTime(milliseconds) {
        var currentDate = new Date();  // 当前时间
        var startupDate = new Date(milliseconds);  // 开机时间

        // 计算剩余时间（毫秒数）
        var timeDiff = currentDate - startupDate;  // 单位为毫秒

        if (timeDiff <= 0) {
            return "已关机";
        }

        // 将剩余时间转换为天、小时、分钟、秒
        var days = Math.floor(timeDiff / (1000 * 60 * 60 * 24));
        var hours = Math.floor((timeDiff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
        var minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));
        var seconds = Math.floor((timeDiff % (1000 * 60)) / 1000);

        // 根据剩余时间生成数组，按优先级添加时间单位
        var timeParts = [];

        if (days > 0) timeParts.push(days + qsTr("天"));
        if (hours > 0 || timeParts.length > 0) timeParts.push(hours + qsTr("时"));
        if (minutes > 0 || timeParts.length > 0) timeParts.push(minutes + qsTr("分"));
        if (seconds > 0 || timeParts.length > 0) timeParts.push(seconds + qsTr("秒"));

        // 保留前三部分
        return timeParts.slice(0, 3).join("");
    }

    // 是否位包月设备
    function isMonthlyDevice(supplierType){
        if(supplierType == "5" || supplierType == "9"){
            return true
        }else if(supplierType == "6"){
            return false
        }

        return true
    }

    function updateDeviceList(){
        const hostList = treeModel.hostList()
        hostList.forEach(
                    item=>{
                        reqDeviceListWithoutLoading(item.ip)
                    })
    }

    function validateName(name){
        name = name.trim()
        if (name.length < 2 || name.length > 200) {
            showError(qsTr("长度限制：2-200字符"))
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

    function openAdbCommandLine(deviceAddress) {
        // 构建adb connect命令
        // 优先使用应用程序目录下的adb.exe，如果不存在则使用PATH中的adb
        var adbPath = FluTools.getApplicationDirPath() + "/adb.exe"
        var command
        // 检查应用程序目录中是否有adb.exe，如果有则使用完整路径
        if (Qt.platform.os === "windows") {
            // Windows系统，使用完整路径或PATH中的adb
            command = "\"" + adbPath + "\" connect " + deviceAddress
        } else {
            // 其他系统，使用PATH中的adb
            command = "adb connect " + deviceAddress
        }
        // 使用Utils执行命令，打开cmd窗口并执行adb connect命令
        Utils.executeCommandInTerminal(command)
    }

    Connections{
        target: treeModel

        function onDeviceAdded(hostIp){
            reqDeviceListWithoutLoading(hostIp)
        }
    }

    DeviceScanner{
        id: scanner
        property var lastHostList: []
        property var specificIpsToScan: []

        onDiscoveryStarted: {
            console.log("=================start scan")
            showLoading(qsTr("开始扫描主机..."))
            scanner.lastHostList = treeModel.hostList()
        }

        onDeviceFound:
            (host) => {
                const previouslyExistingIps = new Set(scanner.lastHostList.map(function(host) { return host.ip; }));
                if (!previouslyExistingIps.has(host.ip)) {
                    treeModel.addHost(host)
                }
            }

        onDiscoveryFinished: {
            console.log("========== scan finished", JSON.stringify(scanner.discoveredDevices))
            updateDeviceList()

            if (scanner.specificIpsToScan.length > 0) {
                const previouslyExistingIps = new Set(scanner.lastHostList.map(function(host) { return host.ip; }));
                const existingIpsInRequest = scanner.specificIpsToScan.filter(function(ip) {
                    return previouslyExistingIps.has(ip);
                });

                if (existingIpsInRequest.length > 0) {
                    showError(qsTr("主机 %1 已存在").arg(existingIpsInRequest.join(", ")));
                }
                scanner.specificIpsToScan = []; // Reset
            }

            // 无缝衔接：扫描完成后立即开始CBS升级检查，不隐藏loading
            // 更新loading文本，让用户知道正在进行CBS版本检查
            showLoading(qsTr("正在检查CBS版本..."))
            // 立即启动CBS升级检查，不延迟，让扫描和升级成为一个连续的过程
            autoCbsUpgradeTimer.interval = 100
            autoCbsUpgradeTimer.start()
        }

        onDiscoveryFailed:
            (ips) => {
                console.log("========== scan failed", JSON.stringify(ips))
                showError(qsTr("IP地址访问异常！"), 3000, JSON.stringify(ips))
                scanner.specificIpsToScan = [] // Reset
            }
    }

    SystemTrayIcon {
        id: system_tray
        visible: false
        icon.source: AppConfig.projectIcon
        tooltip: AppConfig.projectTitle
        menu : Menu {
            id: systemMenu
            // width: 120
            MenuItem {
                text: qsTr("显示主面板")
                onTriggered: {
                    root.show()
                }
            }
            MenuItem {
                text: qsTr("退出")
                onTriggered: {
                    FluRouter.exit()
                }
            }
        }
        onActivated:
            (reason)=>{
                if(reason === SystemTrayIcon.Trigger){
                    root.show()
                    root.raise()
                    root.requestActivate()
                }else if(reason === SystemTrayIcon.Context){
                    systemMenu.open()
                }
            }
    }

    AddBoxPopup{
        id: addBoxPopup

        onAddHost:
            (ips) => {
                var ipArray = ips.split(',').map(function(ip) { return ip.trim(); }).filter(function(ip) { return ip; });
                if (ipArray.length === 0) {
                    return;
                }
                scanner.specificIpsToScan = ipArray;
                scanner.startDiscoveryWithIps(ips, 3000);
            }
    }

    CreateCloudPhonePopup{
        id: createCloudPhonePopup

        onCreateResult:
            (hostIp, list) => {
                reqDeviceListWithoutLoading(hostIp)
            }
            
        onOpenImageList: {
            // 关闭创建云机弹窗
            createCloudPhonePopup.close()
            // 切换到镜像页面
            mainStackLayout.currentIndex = 2
            iconTabBar.currentIndex = 2
        }
    }

    UpgradeCloudPhonePopup{
        id: upgradeCloudPhonePopup

        // onCreateResult:
        //     (hostIp, list) => {
        //         reqDeviceListWithoutLoading(hostIp)
        //     }
    }

    TimeZoneCloudPhonePopup{
        id: timeZoneCloudPhonePopup
    }

    OneKeyNewDevicePopup{
        id: oneKeyNewDevicePopup
        onOneKeyNewDeviceResult: (hostIp, list) => {
            treeModel.updateDeviceListV3(hostIp, list)
        }
        onOneKeyNewDeviceRequest: (hostIp, dbIds, adiName, adiPass, wipeData) => {
            reqOneKeyNewDeviceWithAdi(hostIp, dbIds, adiName, adiPass, wipeData)
        }
    }

    ProxySettingsPopup{
        id: proxySettingsPopup
    }

    AddProxyPopup{
        id: addProxyPopup
    }

    BoxDetailPopup{
        id: boxDetailPopup
    }

    DeviceDetailPopup{
        id: deviceDetailPopup
    }

    //  批量安装
    BatchInstallPopup{
        id: batchInstallPopup
    }

    // 重命名窗口
    RenamePopup{
        id: renameDialog
        title: qsTr("重命名")
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onAboutToShow: {
            renameDialog.inputName = ""
            renameDialog.number = false
        }

        negativeText: qsTr("取消")
        positiveText :qsTr("确定")
    }

    // 通用提示框
    GenericDialog{
        id: dialog
        z: 100
        property bool checked: false
        property bool showPrompt: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        contentDelegate: showPrompt ? promptCompontent : null

        Component{
            id: promptCompontent
            Item{
                implicitWidth: parent.width
                implicitHeight: 30

                RowLayout{
                    anchors.fill: parent
                    anchors.leftMargin: 20

                    VCheckBox{
                        text: qsTr("下次不再提示")
                        textColor: "black"
                        checked: dialog.checked
                        onClicked: {
                            if(dialog.checked !== checked){
                                dialog.checked = checked
                            }
                        }
                    }

                    Item{
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    ChangeGroupPopup{
        id: changeGroupPopup
        onChangeGroup:
            (podIdList, groupId) => {
                console.log("=====", podIdList, groupId)
                for(var i = 0; i < podIdList.length; ++i){
                    treeModel.moveHost(podIdList[i], groupId)
                }
                ReportHelper.reportLog("phone_action_click", {label: "changePadGroup", fromx: "batch"})
            }
    }

    ImportImagePopup{
        id: importImagePopup
        onClosed: {
            imageListView.updateAvailableVersions()
            imageListView.updateFilteredModel()
        }
    }

    FileDialog {
        id: fileDialog
        fileMode: FileDialog.OpenFiles
        property var request: null

        onAccepted: {
            request.dialogAccept(fileDialog.files)
        }

        onRejected: {
            request.dialogReject()
        }
    }

    // 批量操作菜单
    FluMenu{
        id:menuBatch
        width: 120
        parent: btnBatch

        FluMenuItem{
            text:qsTr("启动云机")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 2)){
                    return
                }
                const groups = podList.reduce(
                                 (acc, item) => {
                                     const key = item.hostIp;
                                     if (!acc[key]) acc[key] = [];
                                     acc[key].push(item.dbId);
                                     return acc;
                                 }, {});

                for (const key in groups) {
                    console.log(key, groups[key]);
                    reqRunDevice(key,  groups[key])
                }
            }
        }

        FluMenuItem{
            text:qsTr("重置云机")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 1)){
                    return
                }
                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("重置云机将清除云手机上的所有数据，云手机参数不会改变，请谨慎操作！")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    const groups = podList.reduce(
                                     (acc, item) => {
                                         const key = item.hostIp;
                                         if (!acc[key]) acc[key] = [];
                                         acc[key].push(item.dbId);
                                         return acc;
                                     }, {});

                    for (const key in groups) {
                        console.log(key, groups[key]);
                        reqResetDevice(key,  groups[key])
                    }
                    dialog.close()
                }
                dialog.open()

            }
        }

        FluMenuItem{
            text:qsTr("关闭云机")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 1)){
                    return
                }

                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("确定要关闭云手机吗？")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    const groups = podList.reduce(
                                     (acc, item) => {
                                         const key = item.hostIp;
                                         if (!acc[key]) acc[key] = [];
                                         acc[key].push(item.dbId);
                                         return acc;
                                     }, {});

                    for (const key in groups) {
                        console.log(key, groups[key]);
                        reqStopDevice(key,  groups[key])
                    }
                    dialog.close()
                }
                dialog.open()
            }
        }

        // FluMenuItem{
        //     text:qsTr("设置代理")
        //     onClicked: {
        //         let podList = proxyModel.getPadList()
        //         if(podList.length === 0){
        //             showError(qsTr("请先选择云机"))
        //             return
        //         }
                
        //         // 检查是否有未开机的设备
        //         for(let i = 0; i < podList.length; ++i){
        //             if(podList[i].state !== "running"){
        //                 showError(qsTr("不能对关机设备进行该操作，请重新选择"))
        //                 return
        //             }
        //         }
                
        //         // 将选中的云机列表传递给代理设置弹窗
        //         proxySettingsPopup.selectedDeviceList = podList
        //         proxySettingsPopup.open()
        //     }
        // }

        FluMenuItem{
            text:qsTr("删除云机")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 0)){           //  fix：支持删除“创建中”状态的云机
                    return
                }

                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("删除云机将清除云手机及其所有数据，操作后无法恢复，请谨慎操作！")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){

                    const groups = podList.reduce(
                                     (acc, item) => {
                                         const key = item.hostIp;
                                         if (!acc[key]) acc[key] = [];
                                         acc[key].push(item.dbId);
                                         return acc;
                                     }, {});

                    for (const key in groups) {
                        console.log(key, groups[key]);
                        reqDeleteDevice(key,  groups[key])
                    }
                    dialog.close()
                }
                dialog.open()
            }
        }

        FluMenuItem{
            text:qsTr("修改名称")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 3)){
                    return
                }
                renameDialog.title = qsTr("修改名称")
                renameDialog.tips = qsTr("长度限制 2–200 个字符，仅允许使用 [a–zA–Z0–9_.-]，且首尾字符不得为[._-]")
                renameDialog.onPositiveClickListener = function(){
                    const name = validateName(renameDialog.inputName)
                    if(!name){
                        return
                    }

                    const padList = proxyModel.getPadList()
                    padList.forEach(
                                (item, index) => {
                                    var nameSuffix = index + 1
                                    var displayName = name + `-${nameSuffix.toString().padStart(3, '0')}`
                                    if(item.displayName !== displayName){
                                        reqRenameDevice(item.hostIp, item.dbId, displayName)
                                    }
                                })

                    renameDialog.close()
                }
                renameDialog.open()
            }
        }

        // FluMenuItem{
        //     text:qsTr("升级镜像")
        //     onClicked: {

        //     }
        // }

        // FluMenuItem{
        //     text:qsTr("设置代理")
        //     onClicked: {

        //     }
        // }

        FluMenuItem{
            text:qsTr("一键新机")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 3)){
                    return
                }
                
                // 统一处理逻辑：即使是单云机，也按数组处理
                // 转换为 popup 需要的格式
                var deviceList = podList.map(function(item) {
                    return {
                        name: item.name,
                        displayName: item.displayName,
                        hostIp: item.hostIp,
                        hostId: item.hostId,
                        dbId: item.dbId,
                        image: item.image ? item.image.split(":")[0] : "",
                        aospVersion: item.aospVersion
                    }
                })
                oneKeyNewDevicePopup.modelData = deviceList
                oneKeyNewDevicePopup.open()
            }
        }

        FluMenuItem{
            text:qsTr("重启云机")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 1)){
                    return
                }

                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("重启云机将重新启动云手机系统，运行中的任务可能会中断，请谨慎操作！")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    const groups = podList.reduce(
                                     (acc, item) => {
                                         const key = item.hostIp;
                                         if (!acc[key]) acc[key] = [];
                                         acc[key].push(item.dbId);
                                         return acc;
                                     }, {});

                    for (const key in groups) {
                        console.log(key, groups[key]);
                        reqRebootDevice(key,  groups[key])
                    }
                    dialog.close()
                }
                dialog.open()
            }
        }

        FluMenuSeparator { }

        FluMenuItem{
            text:qsTr("一键投屏")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 1)){
                    return
                }
                
                // 批量打开云机窗口
                podList.forEach(function(item) {
                    if(item.state === "running") {
                        // 智能连接设备（TCP直接连接或ADB模式）
                        root.connectDeviceSmart(item)
                        FluRouter.navigate("/pad", item, undefined, item.dbId || item.id || item.name)
                    }
                })
            }
        }

        FluMenuItem{
            text:qsTr("一键排序")
            onClicked: {
                // 使用默认排序方式，对全部云机进行排序
                FluRouter.arrangeWindows("/pad", root.screen)
                showSuccess(qsTr("已按默认排序"))
            }
        }

        FluMenuItem{
            text:qsTr("一键关闭")
            onClicked: {
                // 关闭所有打开的云机窗口
                FluRouter.closeAllWindows("/pad")
                showSuccess(qsTr("已关闭所有云机窗口"))
            }
        }

        //  批量安装
        FluMenuItem{
            text:qsTr("安装应用")
            onClicked: {
                let podList = proxyModel.getPadList()
                if(!checkAtLeastOne(podList, 1)){
                    return
                }

                const groups = podList.reduce(
                                 (acc, item) => {
                                     const key = item.hostIp;
                                     if (!acc[key]) acc[key] = [];
                                     acc[key].push(item.dbId);
                                     return acc;
                                 }, {});
                batchInstallPopup.tobeInstallList = groups
                batchInstallPopup.open()
            }
        }
    }

    // 设备排序
    FluMenu{
        id: menuSort
        width: 120

        FluMenuItem{
            text:qsTr("默认排序")
            onClicked: {
                proxyModel.setSortType(0)
            }
        }
        FluMenuItem{
            text:qsTr("按创建时间降序")
            onClicked: {
                proxyModel.setSortType(1)
            }
        }
        FluMenuItem{
            text:qsTr("按创建时间升序")
            onClicked: {
                proxyModel.setSortType(2)
            }
        }

        FluMenuItem{
            text:qsTr("按剩余时长降序")
            onClicked: {
                proxyModel.setSortType(3)
            }

        }
        FluMenuItem{
            text:qsTr("按剩余时长升序")
            onClicked: {
                proxyModel.setSortType(4)
            }
        }
    }

    // 视图菜单
    FluMenu{
        id:viewMenu
        width: 120
        parent: btnView
        property int viewSize: 0
        property int viewType: 0
        property int viewDirection: 0

        onAboutToShow: {
            viewMenu.viewType = SettingsHelper.get("viewType", 0)
            viewMenu.viewSize = SettingsHelper.get("viewSize", 2)
            viewMenu.viewDirection = SettingsHelper.get("viewDirection", 0)
        }

        FluMenuItem{
            id: listModel
            text: qsTr("列表模式")
            checked: viewMenu.viewType == 1
            checkable: true
            onClicked: {
                if (viewMenu.viewType == 1) {
                    listModel.checked = true
                    return
                }
                viewMenu.viewType = 1
                SettingsHelper.save("viewType", 1)
                stackLayoutView.currentIndex = 1
                previewModel.checked = false
            }
        }
        FluMenuItem{
            id: previewModel
            text: qsTr("窗口模式")
            checked: viewMenu.viewType == 0
            checkable: true
            onClicked: {
                if (viewMenu.viewType == 0) {
                    previewModel.checked = true
                    return
                }
                viewMenu.viewType = 0
                SettingsHelper.save("viewType", 0)
                stackLayoutView.currentIndex = 0
                listModel.checked = false
            }
        }
        FluMenuSeparator { }

        FluMenuItem{
            id: landMenuItem
            text:qsTr("横屏")
            enabled: viewMenu.viewType == 0
            checked: viewMenu.viewDirection == 270
            checkable: true
            onClicked: {
                if (viewMenu.viewDirection == 270) {
                    landMenuItem.checked = true
                    return
                }
                explorer.viewDirection = 270
                SettingsHelper.save("viewDirection", 270)
                ReportHelper.reportLog("home_style", {label: "stream", str1: "vertical", str2: SettingsHelper.get("viewSize", 2) == 2 ? "big" : SettingsHelper.get("viewSize", 2) == 1 ? "middle" : "small"})
                porMenuItem.checked = false
            }
        }

        FluMenuItem{
            id: porMenuItem
            text:qsTr("竖屏")
            enabled: viewMenu.viewType == 0
            checked: viewMenu.viewDirection == 0
            checkable: true
            onClicked: {
                if (viewMenu.viewDirection == 0) {
                    porMenuItem.checked = true
                    return
                }
                explorer.viewDirection = 0
                SettingsHelper.save("viewDirection", 0)
                ReportHelper.reportLog("home_style", {label: "stream", str1: "horizontal", str2: SettingsHelper.get("viewSize", 2) == 2 ? "big" : SettingsHelper.get("viewSize", 2) == 1 ? "middle" : "small"})
                landMenuItem.checked = false
            }
        }

        FluMenuSeparator { }
        FluMenuItem{
            id: bigViewMenuItem
            text:qsTr("大视图")
            enabled: viewMenu.viewType == 0
            checked: viewMenu.viewSize == 2
            checkable: true
            onClicked: {
                if (viewMenu.viewSize == 2) {
                    bigViewMenuItem.checked = true
                    return
                }
                explorer.itemWidth = 195
                explorer.itemHeight = 349
                SettingsHelper.save("viewSize", 2)
                ReportHelper.reportLog("home_style", {label: "stream", str1: SettingsHelper.get("viewDirection", 0) == 0 ? "vertical" : "horizontal", str2: "big"})
                middleViewMenuItem.checked = false
                smallViewMenuItem.checked = false
            }
        }
        FluMenuItem{
            id: middleViewMenuItem
            text:qsTr("中视图")
            enabled: viewMenu.viewType == 0
            checked: viewMenu.viewSize == 1
            checkable: true
            onClicked: {
                if (viewMenu.viewSize == 1) {
                    middleViewMenuItem.checked = true
                    return
                }
                explorer.itemWidth = 137
                explorer.itemHeight = 244
                SettingsHelper.save("viewSize", 1)
                ReportHelper.reportLog("home_style", {label: "stream", str1: SettingsHelper.get("viewDirection", 0) == 0 ? "vertical" : "horizontal", str2: "middle"})
                bigViewMenuItem.checked = false
                smallViewMenuItem.checked = false
            }
        }
        FluMenuItem{
            id: smallViewMenuItem
            text:qsTr("小视图")
            enabled: viewMenu.viewType == 0
            checked: viewMenu.viewSize == 0
            checkable: true
            onClicked: {
                if (viewMenu.viewSize == 0) {
                    smallViewMenuItem.checked = true
                    return
                }
                explorer.itemWidth = 78
                explorer.itemHeight = 139
                SettingsHelper.save("viewSize", 0)
                ReportHelper.reportLog("home_style", {label: "stream", str1: SettingsHelper.get("viewDirection", 0) == 0 ? "vertical" : "horizontal", str2: "small"})
                bigViewMenuItem.checked = false
                middleViewMenuItem.checked = false
            }
        }

    }

    Connections{
        target: deviceManager

        function onDeviceConnected(serial, deviceName, size){
            console.log("========onDeviceConnected", serial, deviceName, size, new Date())
            groupController.addDevice(serial)
            groupController.updateDeviceState(serial)
            try{
                var ip = (serial||"").split(":")[0]
                if (!root.streamingHostIps) root.streamingHostIps = ({})
                if (ip){ root.streamingHostIps[ip] = true; console.log('[SESSION] mark streaming host', ip)}
            }catch(e){
            }
        }

        function onDeviceDisconnected(serial){
            console.log("=============onDeviceDisconnected", serial, new Date())
            groupController.removeDevice(serial)
            // showError("云机连接断开")
            try{
                var ip = (serial||"").split(":")[0]
                if (root.streamingHostIps && ip && root.streamingHostIps[ip]){ delete root.streamingHostIps[ip]; console.log('[SESSION] unmark streaming host', ip)}
            }catch(e){}
        }

        function onDeviceConnectFailed(serial){
            console.log("============onDeviceConnectFailed", serial, new Date())
            // showError("云机连接失败")
        }
    }

    Component {
        id: groupComponent

        Rectangle {
            id: groupItem
            implicitWidth: parent.width
            implicitHeight: 30
            color: modelData?.selected ? "#e0e0e0" : "white"

            RowLayout{
                anchors.fill: parent
                anchors.rightMargin: 10
                spacing: 0

                Image {
                    source: (modelData && treeView.isExpanded(modelData.index)) ? "qrc:/res/pad/tree_open.png" : "qrc:/res/pad/tree_close.png"

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData) {
                                if (treeView.isExpanded(modelData.index)){
                                    treeView.collapse(modelData.index)
                                }
                                else{
                                    treeView.expand(modelData.index)
                                }
                            }
                        }
                    }
                }

                VCheckBox {
                    tristate: true
                    checkState: modelData?.checked === true
                                ? Qt.Checked
                                : (modelData?.checked === false ? Qt.Unchecked : Qt.PartiallyChecked)
                    onClicked: {
                        if(modelData){
                            const prev = modelData.checked
                            modelData.checked = (prev === true) ? false : true
                        }
                    }
                }

                Text {
                    text: modelData?.groupName ?? ""
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.maximumWidth: 120
                }

                Text{
                    text: `(${modelData?.groupPadCount ?? 0})`
                    font.pixelSize: 13
                }

                Item {
                    Layout.fillWidth: true
                }

                FluIcon{
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    iconSource: FluentIcons.Add
                    visible: mouseArea.hovered
                    iconSize: 16

                    MouseArea{
                        anchors.fill: parent
                        onClicked: {
                            changeGroupPopup.groupModel = modelData
                            changeGroupPopup.open()
                        }
                    }
                }

                FluIcon{
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    iconSource: FluentIcons.Edit
                    visible: mouseArea.hovered
                    iconSize: 14

                    MouseArea{
                        anchors.fill: parent
                        onClicked: {
                            renameDialog.title = qsTr("修改分组名称")
                            renameDialog.number = false
                            renameDialog.tips = ""
                            renameDialog.onPositiveClickListener = function(){
                                const name = renameDialog.inputName
                                if(!name || name.length < 2 || name.length > 15){
                                    showError(qsTr("名称长度为2-15字符"))
                                    return
                                }

                                treeModel.renameGroup(modelData.groupId, renameDialog.inputName)
                                renameDialog.close()
                            }
                            renameDialog.open()
                        }
                    }
                }

                FluIcon{
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    iconSource: FluentIcons.Delete
                    visible: modelData?.groupId !== 1 && mouseArea.hovered
                    iconSize: 14

                    MouseArea{
                        anchors.fill: parent
                        onClicked: {

                            dialog.title = qsTr("操作确认")
                            dialog.message = qsTr("确定要删除分组吗？")
                            dialog.positiveText = qsTr("确定")
                            dialog.negativeText = qsTr("取消")
                            dialog.showPrompt = false
                            dialog.onNegativeClickListener = function(){
                                dialog.close()
                            }
                            dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                            dialog.onPositiveClickListener = function(){
                                treeModel.removeGroup(modelData.groupId)
                                dialog.close()
                            }
                            dialog.open()
                        }
                    }
                }
            }

            HoverHandler {
                id: mouseArea
                acceptedDevices: PointerDevice.Mouse
            }
        }
    }

    Component {
        id: hostComponent

        Rectangle {
            implicitWidth: parent.width
            implicitHeight: 32
            color: "white"

            RowLayout{
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 10
                spacing: 2

                Image {
                    source: (modelData && treeView.isExpanded(modelData.index)) ? "qrc:/res/pad/tree_open.png" : "qrc:/res/pad/tree_close.png"

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData) {
                                if (treeView.isExpanded(modelData.index)){
                                    treeView.collapse(modelData.index)
                                }
                                else{
                                    treeView.expand(modelData.index)
                                }
                            }
                        }
                    }
                }

                VCheckBox {
                    tristate: true
                    checkState: modelData?.checked === true
                                ? Qt.Checked
                                : (modelData?.checked === false ? Qt.Unchecked : Qt.PartiallyChecked)
                    onClicked: {
                        if(modelData){
                            const prev = modelData.checked
                            modelData.checked = (prev === true) ? false : true
                        }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 8
                    Layout.preferredWidth: 8
                    radius: 4
                    color: modelData?.state === "online" ? "green" : "red"
                }

                Text {
                    text: modelData?.hostName ?? ""
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.maximumWidth: 110
                }

                Text{
                    text: {
                        // 如果是主机节点，使用 modelData.hostPadCount（代理模型已经重写了这个属性来返回过滤后的数量）
                        if (modelData?.itemType === TreeModel.TypeHost) {
                            // modelData 是从代理模型的 model 复制过来的，所以 hostPadCount 已经是过滤后的数量
                            // 这样当设备状态改变时，代理模型会触发 dataChanged，QML 绑定会自动更新
                            return `(${modelData?.hostPadCount ?? 0})`
                        }
                        // 其他情况显示原始数量
                        return `(${modelData?.hostPadCount ?? 0})`
                    }
                    font.pixelSize: 13
                    color: "#666"
                }

                Item {
                    Layout.fillWidth: true
                }

                FluIcon{
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    iconSource: FluentIcons.PowerButton
                    visible: modelData?.state === "online" && mouseArea.hovered
                    iconSize: 14

                    MouseArea{
                        anchors.fill: parent
                        onClicked: {
                            dialog.title = qsTr("操作确认")
                            dialog.message = qsTr("重启主机会将该主机上所有的云机重启，确认重启吗？")
                            dialog.positiveText = qsTr("确定")
                            dialog.negativeText = qsTr("取消")
                            dialog.showPrompt = false
                            dialog.onNegativeClickListener = function(){
                                dialog.close()
                            }
                            dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                            dialog.onPositiveClickListener = function(){
                                reqRebootForArm(modelData.ip)
                                dialog.close()
                            }
                            dialog.open()
                        }
                    }
                }

                FluIcon{
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    iconSource: FluentIcons.Add
                    visible: modelData?.state === "online" && mouseArea.hovered
                    iconSize: 16

                    MouseArea{
                        anchors.fill: parent
                        onClicked: {
                            var modelDataCopy = {
                                ip: modelData.ip,
                                hostName: modelData.hostName,
                                hostPadCount: modelData.hostPadCount,
                                hostId: modelData.hostId
                            };
                            createCloudPhonePopup.modelData = modelDataCopy
                            createCloudPhonePopup.open()
                        }
                    }
                }
            }

            HoverHandler {
                id: mouseArea
                acceptedDevices: PointerDevice.Mouse
            }
        }
    }

    Component {
        id: deviceCheckedComponent

        Item{
            width: parent.width
            implicitHeight: 46

            RowLayout{
                anchors.fill: parent
                anchors.leftMargin: 30

                VCheckBox {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    checked: modelData?.checked ?? false
                    onClicked: {
                        if(modelData && modelData.checked != checked){
                            modelData.checked = checked
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: modelData?.selected ? "#e0e0e0" : "white"
                    radius: 8
                    border.color: "#e0e0e0"

                    MouseArea{
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked:
                            (mouse) => {
                                if (mouse.button === Qt.LeftButton) {
                                } else if (mouse.button === Qt.RightButton) {
                                    if(modelData.state === "offline" || modelData.state === "creating"){
                                        return
                                    }

                                    root.showDeviceContextMenu(modelData)
                                }
                            }
                    }

                    RowLayout{
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6

                        Rectangle {
                            Layout.preferredHeight: 8
                            Layout.preferredWidth: 8
                            radius: 4
                            color: AppUtils.getStateColorBystate(modelData.state).text
                        }

                        ColumnLayout{
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: modelData?.displayName ?? ""
                                    font.pixelSize: 12
                                    color: modelData?.color ?? ""
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Item{
                                    Layout.fillWidth: true
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    id: adbAddress
                                    text: {
                                        if (modelData.networkMode === "macvlan") {
                                            if (modelData.state !== "running") {
                                                return "-"
                                            }
                                        }
                                        return modelData?.networkMode === "macvlan" ? `${modelData?.ip ?? ""}:5555` : `${modelData?.hostIp ?? ""}:${modelData?.adb ?? ""}`
                                    }
                                    font.pixelSize : 12
                                    color: "#888"

                                    MouseArea{
                                        anchors.fill: parent

                                        onClicked: {
                                            FluTools.clipText(adbAddress.text)
                                            showSuccess(qsTr("复制成功"))
                                        }
                                    }
                                }

                                Item{
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        FluIcon{
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            iconSource: FluentIcons.More
                            visible: mouseArea.hovered && modelData.state !== "offline" && modelData.state !== "creating"
                            iconSize: 14
                            rotation: 90

                            MouseArea{
                                anchors.fill: parent
                                onClicked: {
                                    root.showDeviceContextMenu(modelData)
                                }
                            }
                        }
                    }

                    HoverHandler {
                        id: mouseArea
                        acceptedDevices: PointerDevice.Mouse
                    }
                }
            }
        }
    }

    function showDeviceContextMenu(model) {
        if (!model) return;
        deviceContextMenu.currentModel = model;
        deviceContextMenu.popup();
    }

    FluMenu {
        id: deviceContextMenu
        width: 120
        property var currentModel: null
        property int replacementCount: 0

        onOpened: {
            if(!deviceContextMenu.currentModel){
                return
            }
            deviceContextMenu.replacementCount = SettingsHelper.get("replacementCount", 0)
        }

        FluMenuItem{
            text:qsTr("启动云机")
            visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "stopped" : false
            onClicked: {
                reqRunDevice(deviceContextMenu.currentModel.hostIp, [deviceContextMenu.currentModel.dbId])
            }
        }

        FluMenuItem{
            text:qsTr("重置云机")
            visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "running" : false
            onClicked: {
                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("重置云机将清除云手机上的所有数据，云手机参数不会改变，请谨慎操作！")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    reqResetDevice(deviceContextMenu.currentModel.hostIp, [deviceContextMenu.currentModel.dbId])
                    dialog.close()
                }
                dialog.open()
            }
        }

        FluMenuItem{
            text:qsTr("关闭云机")
            visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "running" : false
            onClicked: {
                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("确定要关闭云手机吗？")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    reqStopDevice(deviceContextMenu.currentModel.hostIp, [deviceContextMenu.currentModel.dbId])
                    dialog.close()
                }
                dialog.open()
            }
        }

        FluMenuItem{
            text:qsTr("删除云机")
            visible: deviceContextMenu.currentModel ? true : false
            onClicked: {
                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("删除云机将清除云手机及其所有数据，操作后无法恢复，请谨慎操作！")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    reqDeleteDevice(deviceContextMenu.currentModel.hostIp, [deviceContextMenu.currentModel.dbId])
                    dialog.close()
                }
                dialog.open()
            }
        }


        FluMenuItem{
            text:qsTr("修改名称")
            visible: deviceContextMenu.currentModel ? (deviceContextMenu.currentModel.state === "running" || deviceContextMenu.currentModel.state === "stopped") : false
            onClicked: {
                renameDialog.title = qsTr("修改名称")
                renameDialog.number = false
                renameDialog.tips = qsTr("长度限制 2–200 个字符，仅允许使用 [a–zA–Z0–9_.-]，且首尾字符不得为[._-]")
                renameDialog.onPositiveClickListener = function(){
                    const name = validateName(renameDialog.inputName)
                    if(!name){
                        return
                    }

                    if(deviceContextMenu.currentModel.displayName !== name){
                        reqRenameDevice(deviceContextMenu.currentModel.hostIp, deviceContextMenu.currentModel.dbId, name)
                    }
                    renameDialog.close()
                }
                renameDialog.open()
            }
        }

        FluMenuItem{
            text:qsTr("修改镜像")
            visible: deviceContextMenu.currentModel ? (deviceContextMenu.currentModel.state === "running" || deviceContextMenu.currentModel.state === "stopped") : false
            onClicked: {
                var modelDataCopy = {
                    name: deviceContextMenu.currentModel.name,
                    displayName: deviceContextMenu.currentModel.displayName,
                    hostIp: deviceContextMenu.currentModel.hostIp,
                    hostId: deviceContextMenu.currentModel.hostId,
                    dbId: deviceContextMenu.currentModel.dbId,
                    image: deviceContextMenu.currentModel.image.split(":")[0],
                    aospVersion: deviceContextMenu.currentModel.aospVersion
                }

                upgradeCloudPhonePopup.modelData = modelDataCopy
                upgradeCloudPhonePopup.open()
            }
        }

        FluMenuItem{
            text:qsTr("语言时区")
            visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "running" : false
            onClicked: {
                var modelDataCopy = {
                    name: deviceContextMenu.currentModel.name,
                    displayName: deviceContextMenu.currentModel.displayName,
                    hostIp: deviceContextMenu.currentModel.hostIp,
                    hostId: deviceContextMenu.currentModel.hostId,
                    dbId: deviceContextMenu.currentModel.dbId,
                    image: deviceContextMenu.currentModel.image.split(":")[0],
                    aospVersion: deviceContextMenu.currentModel.aospVersion,
                    locale: deviceContextMenu.currentModel.locale,
                    timeZone: deviceContextMenu.currentModel.timezone
                }

                timeZoneCloudPhonePopup.modelData = modelDataCopy
                timeZoneCloudPhonePopup.open()
            }
        }

        FluMenuItem{
            text:qsTr("设置代理")
            visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "running" : false
            onClicked: {
                var modelDataCopy = {
                    name: deviceContextMenu.currentModel.name,
                    displayName: deviceContextMenu.currentModel.displayName,
                    hostIp: deviceContextMenu.currentModel.hostIp,
                    hostId: deviceContextMenu.currentModel.hostId,
                    dbId: deviceContextMenu.currentModel.dbId,
                    image: deviceContextMenu.currentModel.image.split(":")[0],
                    aospVersion: deviceContextMenu.currentModel.aospVersion
                }
                proxySettingsPopup.modelData = modelDataCopy
                proxySettingsPopup.selectedDeviceList = []  // 显式清空，确保单独设置时显示主机名称
                proxySettingsPopup.open()
            }
        }

        FluMenuItem{
            text:qsTr("一键新机")
            visible: deviceContextMenu.currentModel ? (deviceContextMenu.currentModel.state === "running" || deviceContextMenu.currentModel.state === "stopped") : false
            onClicked: {
                // 统一处理逻辑：即使是单云机，也按数组处理
                var podList = [deviceContextMenu.currentModel]
                
                // 转换为 popup 需要的格式
                var deviceList = podList.map(function(item) {
                    return {
                        name: item.name,
                        displayName: item.displayName,
                        hostIp: item.hostIp,
                        hostId: item.hostId,
                        dbId: item.dbId,
                        image: item.image ? item.image.split(":")[0] : "",
                        aospVersion: item.aospVersion
                    }
                })
                oneKeyNewDevicePopup.modelData = deviceList
                oneKeyNewDevicePopup.open()
            }
        }

        FluMenuItem{
            text:qsTr("重启云机")
            visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "running" : false
            onClicked: {
                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("重启云机将重新启动云手机系统，运行中的任务可能会中断，请谨慎操作！")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.showPrompt = false
                dialog.onNegativeClickListener = function(){
                    dialog.close()
                }
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    reqRebootDevice(deviceContextMenu.currentModel.hostIp, [deviceContextMenu.currentModel.dbId])
                    dialog.close()
                }
                dialog.open()
            }
        }

        // FluMenuItem{
        //     text:qsTr("adb命令行")
        //     visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "running" : false
        //     onClicked: {
        //         if (!deviceContextMenu.currentModel) return
        //         var hostIp = deviceContextMenu.currentModel.hostIp || ""
        //         var adb = deviceContextMenu.currentModel.adb || 0
        //         if (!hostIp || !adb) {
        //             showError(qsTr("无法获取设备地址信息"))
        //             return
        //         }
        //         var deviceAddress = hostIp + ":" + adb
        //         openAdbCommandLine(deviceAddress)
        //     }
        // }

        FluMenuItem{
            text:qsTr("API接口")
            onClicked: {
                Qt.openUrlExternally(qsTr("http://%1:18182/docs").arg(deviceContextMenu.currentModel?.hostIp ?? ""))
            }
        }

        FluMenuItem{
            text:qsTr("云机详情")
            visible: deviceContextMenu.currentModel ? deviceContextMenu.currentModel.state === "running" : false
            onClicked: {
                if (!deviceContextMenu.currentModel) return
                deviceDetailPopup.modelData = deviceContextMenu.currentModel
                deviceDetailPopup.open()
            }
        }
    }

    FluMenu {
        id: hostBatchMenu
        width: 120
        property var hostList: null

        FluMenuItem{
            text: qsTr("重启主机")
            onClicked: {
                if(hostBatchMenu.hostList.length <= 0){
                    showError("请勾选主机后进行操作")
                    return
                }

                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("确定要重启主机吗？")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    hostBatchMenu.hostList.forEach(
                                item=>{
                                    reqRebootForArm(item.ip)
                                })
                    dialog.close()
                }
                dialog.open()
            }
        }
        FluMenuItem{
            text:qsTr("重置主机")
            onClicked: {
                if(hostBatchMenu.hostList.length <= 0){
                    showError("请勾选主机后进行操作")
                    return
                }

                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("重置主机将删除该主机上的全部云机及相关数据，确认执行此操作吗？")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    hostBatchMenu.hostList.forEach(
                                item=>{
                                    reqReset(item.ip)
                                })
                    dialog.close()
                }
                dialog.open()
            }
        }
        FluMenuItem{
            text:qsTr("清理镜像")
            onClicked: {
                if(hostBatchMenu.hostList.length <= 0){
                    showError("请勾选主机后进行操作")
                    return
                }

                dialog.title = qsTr("操作确认")
                dialog.message = qsTr("清理未使用的镜像将释放存储空间，确认执行此操作吗？")
                dialog.positiveText = qsTr("确定")
                dialog.negativeText = qsTr("取消")
                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                dialog.onPositiveClickListener = function(){
                    hostBatchMenu.hostList.forEach(
                                item=>{
                                    reqCleanImage(item.ip)
                                })
                    dialog.close()
                }
                dialog.open()
            }
        }
    }

    // 主布局：左栏 + 右侧内容
    RowLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout{
            Layout.fillWidth: true
            Layout.fillHeight: true

            // 标题栏
            Rectangle{
                Layout.preferredHeight: 56
                Layout.fillWidth: true
                color: "white"

                RowLayout{
                    id: layout_title
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    Rectangle{
                        width: 32
                        height: width
                        radius: width / 2
                        Layout.alignment: Qt.AlignVCenter

                        Image{
                            anchors.fill: parent
                            source: ThemeUI.loadRes("main/logo.png")

                        }
                    }

                    FluText{
                        text: qsTr("VMOS Edge")
                        font.pixelSize: 16
                        font.bold: true
                        color: ThemeUI.primaryColor
                    }

                    IconTabBar {
                        id: iconTabBar
                        Layout.preferredHeight: 56
                        Layout.preferredWidth: 240
                        model: [
                            { name: "device", icon: ThemeUI.loadRes("main/cloud.svg"), text: qsTr("云机") },
                            { name: "host", icon: ThemeUI.loadRes("main/box.svg"), text: qsTr("主机") },
                            { name: "image", icon: ThemeUI.loadRes("main/images.svg"), text: qsTr("镜像") },
                            // { name: "store", icon: ThemeUI.loadRes("main/store.svg"), text: qsTr("主机商城") },
                            // { name: "vmoscloud", icon: ThemeUI.loadRes("main/vmos.svg"), text: qsTr("VMOSCloud云手机") },
                        ]

                        onMenuSelected:
                            (name) => {
                                if(name === "device"){
                                    mainStackLayout.currentIndex = 0
                                }else if(name === "host"){
                                    mainStackLayout.currentIndex = 1
                                }else if(name === "image"){
                                    mainStackLayout.currentIndex = 2
                                }else if(name === "store"){
                                    if("en" == SettingsHelper.getLanguage()){
                                        Qt.openUrlExternally(`https://www.vmoscloud.com/shop`)
                                    }else{
                                        Qt.openUrlExternally(`https://www.vmoscloud.com/${SettingsHelper.getLanguage()}/shop`)
                                    }
                                }else if(name === "vmoscloud"){
                                    Qt.openUrlExternally("https://www.vmoscloud.com")
                                }
                            }
                    }

                }

                Item{
                    Layout.fillWidth: true
                }

                RowLayout{
                    id: layout_appbar
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    MultiLanguage{
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 24
                        languageId: TranslateHelper.current
                        onMenuSelected:
                            name=>{
                                console.log("多语言选择", name)

                                dialog.title = qsTr("操作确认")
                                dialog.message = qsTr("修改语言需要重启程序，是否立即重启？")
                                dialog.negativeText = qsTr("取消")
                                dialog.onNegativeClickListener = function(){
                                    dialog.close()
                                }
                                dialog.positiveText = qsTr("确定")
                                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                dialog.onPositiveClickListener = function(){
                                    SettingsHelper.saveLanguage(name)
                                    FluRouter.exit(931)
                                    dialog.close()
                                }
                                dialog.open()
                            }
                    }

                    FluIconButton{
                        id: btnSettings
                        Layout.preferredHeight: 32
                        // Layout.preferredWidth: 80
                        iconSource: FluentIcons.Settings
                        display: Button.TextBesideIcon
                        iconSize: 14
                        text: qsTr("设置")
                        onClicked: {
                            settingsMenu.x = -(settingsMenu.width - btnSettings.width) / 2
                            settingsMenu.y = 40
                            settingsMenu.open()
                        }
                    }

                    FluText{
                        text: qsTr("v%1").arg(AppConfig.versionName)
                        font.pixelSize: 12
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // 设置下拉菜单
                    FluMenu{
                        id: settingsMenu
                        width: 120
                        parent: btnSettings

                        FluMenuItem{
                            text: qsTr("帮助中心")
                            onClicked: {
                                Qt.openUrlExternally("https://help.vmosedge.com")
                            }
                        }
                        FluMenuItem{
                            text: qsTr("通用设置")
                            onClicked: {
                                // 跳转到设置页
                                previousIndexBeforeTemplate = mainStackLayout.currentIndex
                                mainStackLayout.currentIndex = 4
                                iconTabBar.currentIndex = -1
                            }
                        }
                        FluMenuItem{
                            text: qsTr("机型设置")
                            onClicked: {
                                // 跳转到设置页
                                previousIndexBeforeTemplate = mainStackLayout.currentIndex
                                mainStackLayout.currentIndex = 3
                                iconTabBar.currentIndex = -1
                            }
                        }
                        // FluMenuItem{
                        //     text: qsTr("版本：v%1").arg(AppConfig.versionName)
                        // }
                    }


                    Rectangle{
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 20
                        color: ThemeUI.primary
                    }

                    FluImageButton{
                        implicitWidth: 24
                        implicitHeight: 24
                        normalImage: "qrc:/res/main/btn_min_normal.png"
                        hoveredImage: "qrc:/res/main/btn_min_normal.png"
                        pushedImage: "qrc:/res/main/btn_min_normal.png"
                        onClicked: {
                            root.showMinimized()
                        }
                    }
                    FluImageButton{
                        id: btnRestore
                        implicitWidth: 24
                        implicitHeight: 24
                        visible: false
                        normalImage: "qrc:/res/main/btn_restore.png"
                        hoveredImage: "qrc:/res/main/btn_restore.png"
                        pushedImage: "qrc:/res/main/btn_restore.png"
                        onClicked: {
                            root.showNormal()
                            btnRestore.visible = false
                            btnMax.visible = true
                        }
                    }
                    FluImageButton{
                        id: btnMax
                        implicitWidth: 24
                        implicitHeight: 24
                        normalImage: "qrc:/res/main/btn_max_normal.png"
                        hoveredImage: "qrc:/res/main/btn_max_normal.png"
                        pushedImage: "qrc:/res/main/btn_max_normal.png"
                        onClicked: {
                            root.showMaximized()
                            btnRestore.visible = true
                            btnMax.visible = false
                        }
                    }
                    FluImageButton{
                        implicitWidth: 24
                        implicitHeight: 24
                        normalImage: "qrc:/res/main/btn_close_normal.png"
                        hoveredImage: "qrc:/res/main/btn_close_normal.png"
                        pushedImage: "qrc:/res/main/btn_close_normal.png"
                        onClicked: {
                            if(!Boolean(SettingsHelper.get("exitPrompt", false))){
                                // 提示
                                dialog.title = qsTr("操作确认")
                                dialog.showPrompt = true
                                dialog.checked = false
                                dialog.message = qsTr(`是否退出${AppConfig.projectTitle}？`)
                                dialog.neutralText = qsTr("取消")
                                dialog.negativeText = qsTr("退出程序")
                                dialog.onNegativeClickListener = function(){
                                    SettingsHelper.save("exitPrompt", dialog.checked)
                                    SettingsHelper.save("exitApp", 0)
                                    dialog.close()
                                    FluRouter.closeAllWindows("/pad")
                                    Qt.quit()
                                }
                                dialog.positiveText = qsTr("最小化到托盘")
                                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton | FluContentDialogType.NeutralButton
                                dialog.onPositiveClickListener = function(){
                                    SettingsHelper.save("exitPrompt", dialog.checked)
                                    SettingsHelper.save("exitApp", 1)
                                    dialog.close()
                                    root.hide()
                                    system_tray.visible = true
                                    // system_tray.showMessage(qsTr("Friendly Reminder"),qsTr("FluentUI is hidden from the tray, click on the tray to activate the window again"));
                                }
                                dialog.open()
                            }else{
                                // 不提示
                                const exitApp = SettingsHelper.get("exitApp", 0)
                                if(0 == exitApp){
                                    // 退出程序
                                    FluRouter.closeAllWindows("/pad")
                                    Qt.quit()
                                }else if(1 == exitApp){
                                    // 最小化托盘
                                    root.hide()
                                    system_tray.visible = true
                                }
                            }
                        }
                    }
                }


            }

            // 功能区
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StackLayout{
                    id: mainStackLayout
                    anchors.fill: parent

                    // 1、云机
                    Item{
                        id: deviceContainer
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.fill: parent

                            // 分组列表
                            Rectangle {
                                id: groupListContainer
                                Layout.preferredWidth: 280
                                Layout.minimumWidth: 280
                                Layout.maximumWidth: 280
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.topMargin: 10
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10

                                    SearchTextField {
                                        id: filterTextField
                                        Layout.preferredHeight: 32
                                        Layout.fillWidth: true
                                        placeholderText: qsTr("请输入云机名称、IP")
                                        onSearchTextChanged: function(text) {
                                            treeProxyModel.searchFilter = filterTextField.text
                                        }
                                        onSearchTextFinished: {
                                            //  中文输入或粘贴时，需再次输入回车才能触发
                                            treeProxyModel.searchFilterChanged()
                                        }
                                    }

                                    // 分组列表
                                    Item{
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        ColumnLayout{
                                            anchors.fill: parent
                                            spacing: 0

                                            RowLayout{
                                                Layout.preferredHeight: 24

                                                IconButton {
                                                    Layout.preferredHeight: 24
                                                    backgroundColor: "white"
                                                    textColor: "black"
                                                    iconSource: "qrc:/res/main/btn_add_group_normal.png"
                                                    text: qsTr("添加分组")
                                                    onClicked: {
                                                        if(checkIsEventSync()){
                                                            return
                                                        }

                                                        renameDialog.title = qsTr("添加分组")
                                                        renameDialog.number = false
                                                        renameDialog.tips = ""
                                                        renameDialog.onPositiveClickListener = function(){
                                                            const name = renameDialog.inputName
                                                            if(!name || name.length < 2 || name.length > 15){
                                                                showError(qsTr("名称长度为2-15字符"))
                                                                return
                                                            }

                                                            treeModel.addGroup(renameDialog.inputName)
                                                            renameDialog.close()
                                                        }
                                                        renameDialog.open()
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                }

                                                IconButton {
                                                    Layout.preferredHeight: 24
                                                    backgroundColor: "white"
                                                    textColor: "black"
                                                    iconSource: "qrc:/res/main/btn_add_group_normal.png"
                                                    text: qsTr("添加主机")
                                                    onClicked: {
                                                        if(checkIsEventSync()){
                                                            return
                                                        }

                                                        addBoxPopup.open()
                                                    }
                                                }

                                            }

                                            TreeView {
                                                id: groupTreeView
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                model: treeProxyModel
                                                clip: true
                                                boundsBehavior: Flickable.StopAtBounds
                                                ScrollBar.vertical: ScrollBar { }
                                                delegate: ItemDelegate {
                                                    id: itemDelegate2
                                                    implicitWidth: groupTreeView.width
                                                    background: Item{}
                                                    contentItem: Loader {
                                                        width: itemDelegate2.width
                                                        sourceComponent: model.itemType === TreeModel.TypeGroup ? groupComponent : (model.itemType === TreeModel.TypeHost ? hostComponent : deviceCheckedComponent)
                                                        property var modelData: model
                                                        property var treeView: groupTreeView
                                                        property int filteredDeviceCount: {
                                                            // 如果是主机节点，使用 model.hostPadCount（代理模型已经重写了这个属性来返回过滤后的数量）
                                                            if (model.itemType === TreeModel.TypeHost) {
                                                                // 直接使用 model.hostPadCount，因为代理模型已经重写了这个属性来返回过滤后的数量
                                                                // 这样当设备状态改变时，代理模型会触发 dataChanged，QML 绑定会自动更新
                                                                return model.hostPadCount ?? 0
                                                            }
                                                            // 其他情况返回原始数量
                                                            return modelData?.hostPadCount ?? 0
                                                        }
                                                    }
                                                }
                                            }

                                            // 分割线
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 1
                                                color: "#e0e0e0"
                                            }

                                            // 状态过滤复选框区域
                                            Item {
                                                Layout.preferredHeight: 40
                                                Layout.fillWidth: true

                                                RowLayout {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 10
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 20

                                                    VCheckBox {
                                                        id: checkBoxRunningOnly
                                                        text: qsTr("运行中云机")
                                                        textColor: ThemeUI.blackColor
                                                        fontSize: 12
                                                        checked: treeProxyModel.showRunningOnly
                                                        onClicked: {
                                                            treeProxyModel.showRunningOnly = checked
                                                        }
                                                    }

                                                    VCheckBox {
                                                        id: checkBoxAllDevices
                                                        text: qsTr("所有云机")
                                                        textColor: ThemeUI.blackColor
                                                        fontSize: 12
                                                        checked: treeProxyModel.showAllDevices
                                                        onClicked: {
                                                            treeProxyModel.showAllDevices = checked
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    // }
                                }
                            }

                            // 预览列表
                            Item{
                                id: devicePreviewContainer
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout{
                                    anchors.fill: parent
                                    anchors.rightMargin: 10

                                    Rectangle{
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 56

                                        RowLayout{
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 6

                                            VCheckBox{
                                                id: checkBoxAllSelect
                                                text: qsTr("全选")
                                                textColor: ThemeUI.blackColor
                                                fontSize: 13
                                                checked: proxyModel.isSelectAll
                                                // enabled: !groupControl.eventSync
                                                onClicked: {
                                                    if(checkIsEventSync()){
                                                        return
                                                    }

                                                    checkBoxInvertSelection.checked = false
                                                    proxyModel.selectAll(checked)
                                                }
                                            }

                                            VCheckBox{
                                                id: checkBoxInvertSelection
                                                text: qsTr("反选")
                                                textColor: ThemeUI.blackColor
                                                fontSize: 13
                                                // enabled: !groupControl.eventSync
                                                onClicked: {
                                                    if(checkIsEventSync()){
                                                        return
                                                    }

                                                    if(proxyModel.checkedCount === 0){
                                                        showError(qsTr("您还未勾选云手机"))
                                                        checked = false
                                                        return
                                                    }else{
                                                        if(proxyModel.isSelectAll){
                                                            showError(qsTr("没有可以反选的云手机"))
                                                            checked = false
                                                            return
                                                        }
                                                    }

                                                    proxyModel.invertSelection()
                                                }
                                            }

                                            FluText{
                                                text: proxyModel.checkedCount
                                                Layout.preferredWidth: 32
                                                horizontalAlignment: Text.AlignRight
                                                color: ThemeUI.primaryColor
                                            }

                                            FluText{
                                                text: qsTr("已选")
                                            }


                                            TextButton{
                                                backgroundColor: "white"
                                                borderColor: "lightgray"
                                                borderRadius: 16
                                                borderSize: 1
                                                textColor: "black"
                                                text: qsTr("取消选择")
                                                onClicked: {
                                                    if(checkIsEventSync()){
                                                        return
                                                    }

                                                    checkBoxInvertSelection.checked = false
                                                    proxyModel.selectAll(false)
                                                }
                                            }


                                            IconButton {
                                                id: btnBatch
                                                backgroundColor: "white"
                                                borderColor: "lightgray"
                                                borderRadius: 16
                                                borderSize: 1
                                                textColor: "black"
                                                iconSource: "qrc:/res/icon/icon_batch.png"
                                                text: qsTr("批量操作")
                                                onClicked: {
                                                    if(checkIsEventSync()){
                                                        return
                                                    }

                                                    menuBatch.x = -(menuBatch.width - btnBatch.width) / 2
                                                    menuBatch.y = 40
                                                    menuBatch.open()
                                                }
                                            }

                                            Item{
                                                Layout.fillWidth: true
                                            }

                                            IconButton {
                                                id: btnSync
                                                Layout.preferredHeight: 32
                                                backgroundColor: "white"
                                                borderColor: "lightgray"
                                                visible: false
                                                borderRadius: 16
                                                borderSize: 1
                                                textColor: "black"
                                                // iconSource: groupControl.eventSync ? "qrc:/res/pad/checkbox_selected.png" : "qrc:/res/pad/checkbox_normal.png"
                                                text: qsTr("同步操作")
                                                onClicked: {

                                                    if(groupControl.isEventSync()){
                                                        // 群控中
                                                        if(!Boolean(SettingsHelper.get("stopSyncPrompt", false))){
                                                            dialog.title = qsTr("操作确认")
                                                            dialog.showPrompt = true
                                                            dialog.checked = false
                                                            dialog.message = qsTr("是否要关闭同步操作模式")
                                                            dialog.negativeText = qsTr("取消")
                                                            dialog.onNegativeClickListener = function(){
                                                                SettingsHelper.save("stopSyncPrompt", dialog.checked)
                                                                dialog.close()
                                                            }
                                                            dialog.positiveText = qsTr("确定")
                                                            dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                                            dialog.onPositiveClickListener = function(){
                                                                dialog.close()
                                                                SettingsHelper.save("stopSyncPrompt", dialog.checked)
                                                                groupControl.stopEventSync()
                                                                FluRouter.closeAllWindows("/pad")
                                                            }
                                                            dialog.open()
                                                        }else {
                                                            groupControl.stopEventSync()
                                                            FluRouter.closeAllWindows("/pad")
                                                        }

                                                        ReportHelper.reportLog("phone_action_click", {label: "StopGroupPlay", fromx: "batch"})
                                                    }else{
                                                        // 是否已打开播放窗口
                                                        if(FluRouter.hasWindow("/pad")){
                                                            showError(qsTr("云机播放窗口已打开，请先关闭后同步操作"))
                                                            return
                                                        }

                                                        // 开启群控
                                                        let podList = proxyModel.getPadList()
                                                        if(!checkAtLeastOne(podList, 1, 2)){
                                                            return
                                                        }

                                                        // 不能混用
                                                        let monthCount = 0
                                                        let boxCount = 0
                                                        for(let i = 0; i < podList.length; ++i){
                                                            if(podList[i].supplierType === "5" || podList[i].supplierType === "6"){
                                                                monthCount++
                                                            }else if(podList[i].supplierType === "9"){
                                                                boxCount++
                                                            }
                                                        }
                                                        if(monthCount > 0 && boxCount > 0){
                                                            showError(qsTr("魔盒设备不能和云机设备一起同步操作，请分开进行同步操作"))
                                                            return
                                                        }


                                                        if(!Boolean(SettingsHelper.get("startSyncPrompt", false))){
                                                            dialog.title = qsTr("操作确认")
                                                            dialog.showPrompt = true
                                                            dialog.checked = false
                                                            dialog.message = qsTr("开启同步操作，则操作任意一台云手机的同时可同步操作至其它勾选的云手机")
                                                            dialog.negativeText = qsTr("取消")
                                                            dialog.onNegativeClickListener = function(){
                                                                SettingsHelper.save("startSyncPrompt", dialog.checked)
                                                                dialog.close()
                                                            }
                                                            dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                                            dialog.positiveText = qsTr("确定")
                                                            dialog.onPositiveClickListener = function(){
                                                                SettingsHelper.save("startSyncPrompt", dialog.checked)
                                                                var config = {
                                                                    userId: `pc_${Utils.getMachineId()}_${SettingsHelper.get("userId")}`,
                                                                    token: SettingsHelper.get("armcloudToken"),
                                                                    uuid: Utils.getMachineId(),
                                                                    level: {resolution: 15,fps: 1,bitrate: 3},
                                                                    expireTime: 3600,
                                                                    podIdList: podList.map(item => item.padCode)
                                                                };
                                                                groupControl.setStreamType(monthCount > 0 ? 1 : 2)
                                                                groupControl.startEventSync(config)
                                                                dialog.close()
                                                            }
                                                            dialog.open()
                                                        }else {
                                                            var config = {
                                                                userId: `pc_${Utils.getMachineId()}_${SettingsHelper.get("userId")}`,
                                                                token: SettingsHelper.get("armcloudToken"),
                                                                uuid: Utils.getMachineId(),
                                                                level: {resolution: 15,fps: 1,bitrate: 3},
                                                                expireTime: 3600,
                                                                podIdList: podList.map(item => item.padCode)
                                                            };
                                                            groupControl.setStreamType(monthCount > 0 ? 1 : 2)
                                                            groupControl.startEventSync(config)
                                                        }

                                                        ReportHelper.reportLog("phone_action_click", {label: "StartGroupPlay", fromx: "batch"})
                                                    }
                                                }
                                            }

                                            IconButton {
                                                id: btnRefresh
                                                backgroundColor: "white"
                                                borderColor: "lightgray"
                                                borderRadius: 16
                                                borderSize: 1
                                                textColor: "black"
                                                iconSource: "qrc:/res/icon/icon_refresh.png"
                                                text: qsTr("刷新")
                                                
                                                property var lastRefreshTime: Date.now()
                                                
                                                onClicked: {
                                                    if(checkIsEventSync()){
                                                        return
                                                    }
                                                    
                                                    // 检查时间戳，2秒内只能刷新一次
                                                    var currentTime = Date.now()
                                                    if (currentTime - btnRefresh.lastRefreshTime < 2000) {
                                                        showWarning(qsTr("刷新过于频繁，请稍后再试"))
                                                        return
                                                    }
                                                    
                                                    btnRefresh.lastRefreshTime = currentTime
                                                    scanner.startDiscovery(3000)
                                                }
                                            }

                                            IconButton {
                                                id: btnView
                                                backgroundColor: "white"
                                                borderColor: "lightgray"
                                                borderRadius: 16
                                                borderSize: 1
                                                textColor: "black"
                                                iconSource: "qrc:/res/icon/icon_view.png"
                                                text: qsTr("视图模式")
                                                onClicked: {
                                                    if(checkIsEventSync()){
                                                        return
                                                    }
                                                    viewMenu.y = 40
                                                    viewMenu.open()
                                                }
                                            }
                                        }
                                    }

                                    StackLayout{
                                        id: stackLayoutView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        currentIndex: SettingsHelper.get("viewType", 0)

                                        function getViewWidth(viewSize){
                                            if(viewSize == 2){
                                                return 195
                                            }else if(viewSize == 1){
                                                return 137
                                            }else if(viewSize == 0){
                                                return 78
                                            }

                                            return 195
                                        }

                                        function getViewHeight(viewSize){
                                            if(viewSize == 2){
                                                return 349
                                            }else if(viewSize == 1){
                                                return 244
                                            }else if(viewSize == 0){
                                                return 139
                                            }

                                            return 349
                                        }

                                        GridTileLayout {
                                            id: explorer
                                            viewDirection: SettingsHelper.get("viewDirection", 0)
                                            itemWidth: stackLayoutView.getViewWidth(SettingsHelper.get("viewSize", 2))
                                            itemHeight: stackLayoutView.getViewHeight(SettingsHelper.get("viewSize", 2))
                                            groupsModel: groupList
                                            model: proxyModel

                                            onShowContextMenuForItem:
                                                (model) => {
                                                    root.showDeviceContextMenu(model)
                                                }

                                            onVisibleItemsChanged:
                                                (podList) => {
                                                    console.log("onVisibleItemsChanged", JSON.stringify(podList))
                                                }

                                            onItemDestroy:
                                                (padCode) => {
                                                }
                                        }

                                        // 列表
                                        CloudListView{
                                            model: proxyModel

                                            onClickMenuItem:
                                                (model)=>{
                                                    root.showDeviceContextMenu(model)
                                                }
                                        }
                                    }

                                }

                                Rectangle {
                                    id: selectionRectangle
                                    visible: false
                                    color: FluTheme.primaryColor
                                    opacity: 0.2
                                    border.color: FluTheme.primaryColor
                                    border.width: 1
                                    radius: 4
                                }

                                MouseArea {
                                    id: selectionMouseArea
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton

                                    property bool isSelectionDrag: false
                                    property point startPoint: Qt.point(0, 0)

                                    onPressed:
                                        (mouse) => {
                                            if (mouse.modifiers & Qt.ShiftModifier) {
                                                isSelectionDrag = true;
                                                mouse.accepted = true;

                                                startPoint = Qt.point(mouse.x, mouse.y)
                                                selectionRectangle.x = mouse.x;
                                                selectionRectangle.y = mouse.y;
                                                selectionRectangle.width = 0;
                                                selectionRectangle.height = 0;
                                                selectionRectangle.visible = true;
                                            } else {
                                                isSelectionDrag = false;
                                                mouse.accepted = false;
                                            }
                                        }

                                    onPositionChanged:
                                        (mouse) => {
                                            if (!isSelectionDrag) {
                                                return;
                                            }
                                            selectionRectangle.x = Math.min(mouse.x, startPoint.x)
                                            selectionRectangle.y = Math.min(mouse.y, startPoint.y)
                                            selectionRectangle.width = Math.abs(mouse.x - startPoint.x)
                                            selectionRectangle.height = Math.abs(mouse.y - startPoint.y)
                                        }

                                    onReleased:
                                        (mouse) => {
                                            if (!isSelectionDrag) {
                                                return;
                                            }
                                            isSelectionDrag = false;
                                            selectionRectangle.visible = false;

                                            if (selectionRectangle.width < 10 && selectionRectangle.height < 10) {
                                                return;
                                            }

                                            explorer.selectItemsInRect(selectionRectangle.x, selectionRectangle.y, selectionRectangle.width, selectionRectangle.height, devicePreviewContainer);
                                        }
                                }

                            }
                        }

                    }
                    // 2、主机
                    Item{
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        BoxListView{
                            anchors.fill: parent

                            onOpenDetail:
                                (hostIp) => {
                                    boxDetailPopup.hostIp = hostIp
                                    boxDetailPopup.open()
                                }

                            onOpenBatchMenu:
                                (hostList, button) => {
                                    hostBatchMenu.parent = button
                                    hostBatchMenu.hostList = hostList
                                    hostBatchMenu.y = 40
                                    hostBatchMenu.x = (button.width - hostBatchMenu.width) / 2
                                    hostBatchMenu.open()
                                }

                            onOpenClean:
                                (hostIp) => {
                                    dialog.title = qsTr("操作确认")
                                    dialog.message = qsTr("确定要清理未使用的镜像获取更多的存储空间吗？")
                                    dialog.positiveText = qsTr("确定")
                                    dialog.negativeText = qsTr("取消")
                                    dialog.showPrompt = false
                                    dialog.onNegativeClickListener = function(){
                                        dialog.close()
                                    }
                                    dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                    dialog.onPositiveClickListener = function(){
                                        reqCleanImage(hostIp)
                                        dialog.close()
                                    }
                                    dialog.open()
                                }

                            onOpenReboot:
                                (hostIp) => {
                                    dialog.title = qsTr("操作确认")
                                    dialog.message = qsTr("确定要重启主机吗？")
                                    dialog.positiveText = qsTr("确定")
                                    dialog.negativeText = qsTr("取消")
                                    dialog.showPrompt = false
                                    dialog.onNegativeClickListener = function(){
                                        dialog.close()
                                    }
                                    dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                    dialog.onPositiveClickListener = function(){
                                        reqRebootForArm(hostIp)
                                        dialog.close()
                                    }
                                    dialog.open()

                                }
                            onOpenReset:
                                (hostIp) => {
                                    dialog.title = qsTr("操作确认")
                                    dialog.message = qsTr("重置主机会将该主机上所有的云机和数据清除，确认重置吗？")
                                    dialog.positiveText = qsTr("确定")
                                    dialog.negativeText = qsTr("取消")
                                    dialog.showPrompt = false
                                    dialog.onNegativeClickListener = function(){
                                        dialog.close()
                                    }
                                    dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                    dialog.onPositiveClickListener = function(){
                                        reqReset(hostIp)
                                        dialog.close()
                                    }
                                    dialog.open()
                                }

                            onOpenDelete:
                                (hostId) => {
                                    dialog.title = qsTr("操作确认")
                                    dialog.message = qsTr("删除主机仅适用于永久离线或IP已变更的主机。若主机恢复在线，系统的自动发现功能会重新将其添加至列表。")
                                    dialog.positiveText = qsTr("确定")
                                    dialog.negativeText = qsTr("取消")
                                    dialog.showPrompt = false
                                    dialog.onNegativeClickListener = function(){
                                        dialog.close()
                                    }
                                    dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                    dialog.onPositiveClickListener = function(){
                                        treeModel.removeHost(hostId)
                                        dialog.close()
                                    }
                                    dialog.open()
                                }
                        }
                    }

                    // 3、镜像
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ImageListView{
                            id: imageListView
                            anchors.fill: parent

                            onOpenImportImagePopup: {
                                importImagePopup.open()
                            }

                            onDeleteImage: function(imageName, imageIndex) {
                                dialog.title = qsTr("确认删除")
                                dialog.message = qsTr("确定要删除镜像 \"%1\" 吗？此操作将永久删除镜像文件，无法恢复。").arg(imageName)
                                dialog.positiveText = qsTr("删除")
                                dialog.negativeText = qsTr("取消")
                                dialog.showPrompt = false
                                dialog.onNegativeClickListener = function(){
                                    dialog.close()
                                }
                                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                dialog.onPositiveClickListener = function(){
                                    imagesModel.remove(imageIndex)
                                    imageListView.updateAvailableVersions()
                                    imageListView.updateFilteredModel()
                                    dialog.close()
                                }
                                dialog.open()
                            }

                            onChangeImagePath: function(newPath) {
                                dialog.title = qsTr("确认更改路径")
                                dialog.message = qsTr("确定要将镜像存储路径更改为：%1 更改后，新导入的镜像将存储在新路径中。").arg(newPath)
                                dialog.positiveText = qsTr("确定")
                                dialog.negativeText = qsTr("取消")
                                dialog.showPrompt = false
                                dialog.onNegativeClickListener = function(){
                                    dialog.close()
                                }
                                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                dialog.onPositiveClickListener = function(){
                                    SettingsHelper.save("imagesPath", newPath)
                                    imageListView.currentImagePath = newPath
                                    dialog.close()
                                }
                                dialog.open()
                            }
                        }
                    }

                    // 4、模板
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TemplateListView{
                            id: templateListView
                            anchors.fill: parent

                            onGoBack: {
                                mainStackLayout.currentIndex = previousIndexBeforeTemplate
                                if(previousIndexBeforeTemplate === 0){
                                    iconTabBar.currentIndex = 0
                                }else if(previousIndexBeforeTemplate === 1){
                                    iconTabBar.currentIndex = 1
                                }else if(previousIndexBeforeTemplate === 2){
                                    iconTabBar.currentIndex = 2
                                }else{
                                    iconTabBar.currentIndex = -1
                                }
                            }

                            onOpenImportImagePopup: {
                                importImagePopup.open()
                            }

                            onDeleteImage: function(imageName, imageIndex) {
                                dialog.title = qsTr("确认删除")
                                dialog.message = qsTr("确定要删除镜像 \"%1\" 吗？此操作将永久删除镜像文件，无法恢复。").arg(imageName)
                                dialog.positiveText = qsTr("删除")
                                dialog.negativeText = qsTr("取消")
                                dialog.showPrompt = false
                                dialog.onNegativeClickListener = function(){
                                    dialog.close()
                                }
                                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                dialog.onPositiveClickListener = function(){
                                    imagesModel.remove(imageIndex)
                                    imageListView.updateAvailableVersions()
                                    imageListView.updateFilteredModel()
                                    dialog.close()
                                }
                                dialog.open()
                            }

                            onChangeImagePath: function(newPath) {
                                dialog.title = qsTr("确认更改路径")
                                dialog.message = qsTr("确定要将镜像存储路径更改为：%1 更改后，新导入的镜像将存储在新路径中。").arg(newPath)
                                dialog.positiveText = qsTr("确定")
                                dialog.negativeText = qsTr("取消")
                                dialog.showPrompt = false
                                dialog.onNegativeClickListener = function(){
                                    dialog.close()
                                }
                                dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                dialog.onPositiveClickListener = function(){
                                    SettingsHelper.save("imagesPath", newPath)
                                    imageListView.currentImagePath = newPath
                                    dialog.close()
                                }
                                dialog.open()
                            }
                        }
                    }

                    // 5、设置
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        SettingsView {
                            id: settingsView
                            anchors.fill: parent

                            onGoBack: {
                                mainStackLayout.currentIndex = previousIndexBeforeTemplate
                                if(previousIndexBeforeTemplate === 0){
                                    iconTabBar.currentIndex = 0
                                }else if(previousIndexBeforeTemplate === 1){
                                    iconTabBar.currentIndex = 1
                                }else if(previousIndexBeforeTemplate === 2){
                                    iconTabBar.currentIndex = 2
                                }else{
                                    iconTabBar.currentIndex = -1
                                }
                            }
                        }
                    }
                }

            }
        }
    }



    NetworkCallable {
        id: downloadScreenshot
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                // showError(errorString)
            }
        onDownloadProgress:
            (recv,total)=>{
                console.log("========下载进度=========", recv, total, Math.trunc(recv/total * 100))
            }
        onSuccess:
            (result, userData) => {

            }
    }

    // 批量截图
    function reqDownloadScreenshot(path, url){
        Network.get(url)
        .toDownload(path)
        .bind(root)
        .go(downloadScreenshot)
    }

    function getFormatFromUrl(url) {
        var match = url.match(/(?:\?|&)format=([^&]+)/)
        return match ? match[1] : ""
    }

    NetworkCallable {
        id: batchScreenshot
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    const downloadPath = StandardPaths.writableLocation(StandardPaths.PicturesLocation) + `/${AppConfig.projectName}/`
                    res.data?.forEach(
                        (item, index) => {
                            let fileName = Qt.formatDateTime(new Date(), "yyyyMMddHHmmsszzz") + `${index}.` + getFormatFromUrl(item.accessUrl)
                            reqDownloadScreenshot(FluTools.toLocalPath(downloadPath) + fileName, item.accessUrl)
                        })
                }else{
                    showError(res.msg)
                }
            }
    }

    // 批量截图
    function reqBatchScreenshot(podList){
        Network.postJson(AppConfig.apiHost + "/padManage/padScreenshotsNew")
        .addList("padCodes", podList)
        .bind(root)
        .go(batchScreenshot)
    }

    NetworkCallable {
        id: checkVersion
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    if(res.data && res.data.versionCode > AppConfig.versionCode){
                        upgradePopup.upgradeInfo = res.data
                        upgradePopup.open()
                    }else{
                        showSuccess(qsTr("当前已经是最新版本"))
                    }
                }else{
                    showError(res.msg)
                }
            }
    }
    // 检查更新
    function reqCheckVersion(channel, versionCode){
        Network.get(AppConfig.apiHost + "/pcVersion/pcCheckForceUpdateInfo?channelName=" + channel + "&versionCode=" + versionCode)
        .bind(root)
        .setUserData(ip)
        .go(checkVersion)
    }

    NetworkCallable {
        id: hardwareCfg
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

    // 获取主机配置
    function reqHardwareCfg(ip){
        Network.get(`http://${ip}:18182/v1` + "/get_hardware_cfg")
        .bind(root)
        .setUserData(ip)
        .go(hardwareCfg)
    }

    NetworkCallable {
        id: rebootForArm
        onStart: {
            showLoading(qsTr("正在重启主机..."))
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
                    treeModel.modifyHost(res.data.host_ip, {state:"restarting"})
                    // reqDeviceList(res.data.host_ip)
                }else{
                    showError(res.msg)
                }
            }
    }

    // 重启主机
    function reqRebootForArm(ip){
        Network.get(`http://${ip}:18182/v1` + "/reboot_for_arm")
        .bind(root)
        .setUserData(ip)
        .go(rebootForArm)
    }

    NetworkCallable {
        id: reset
        onStart: {
            showLoading(qsTr("正在重置主机..."))
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
                    // treeModel.removeDevicesByHostIp(userData)
                }else{
                    showError(res.msg)
                }
            }
    }

    // 重置主机
    function reqReset(ip){
        Network.get(`http://${ip}:18182/v1` + "/reset")
        .bind(root)
        .setUserData(ip)
        .setTimeout(300000)
        .go(reset)
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

                }else{
                    showError(res.msg)
                }
            }
    }

    // 获取主机状态
    function reqSystemInfo(ip){
        Network.get(`http://${ip}:18182/v1` + "/systeminfo")
        .bind(root)
        .setUserData(ip)
        .go(systemInfo)
    }

    NetworkCallable {
        id: swapEnable
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
        .setUserData(ip)
        .go(swapEnable)
    }

    NetworkCallable {
        id: deviceList
        onStart: {
            showLoading(qsTr("正在更新中..."))
        }
        onFinish: {
            hideLoading()
        }
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    treeModel.updateDeviceList(res.data.host_ip, res.data.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 获取云机列表
    function reqDeviceList(ip){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/get_db")
        .bind(root)
        .openLog(false)
        .setTimeout(2000)
        .setUserData(ip)
        .go(deviceList)
    }

    NetworkCallable {
        id: deviceListWithoutLoading
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                treeModel.modifyHost(userData, {state:"offline"})
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    treeModel.modifyHost(res.data.host_ip, {state:"online"})
                    treeModel.updateDeviceList(res.data.host_ip, res.data.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 获取云机列表
    function reqDeviceListWithoutLoading(ip){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/get_db")
        .bind(root)
        .openLog(false)
        .setTimeout(2000)
        .setUserData(ip)
        .go(deviceListWithoutLoading)
    }

    NetworkCallable {
        id: deleteDevice
        onStart: {
            showLoading(qsTr("正在删除云机..."))
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
                    treeModel.updateDeviceListV3(res.data.host_ip, res.data?.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 删除云机
    function reqDeleteDevice(ip, padNames){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/delete")
        .addList("db_ids", padNames)
        .bind(root)
        .setTimeout(300000)
        .setUserData(ip)
        .go(deleteDevice)
    }

    NetworkCallable {
        id: rebootDevice
        onStart: {
            showLoading(qsTr("正在重启云机..."))
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
                    treeModel.updateDeviceListV3(res.data.host_ip, res.data?.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 重启云机
    function reqRebootDevice(ip, padNames){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/reboot")
        .addList("db_ids", padNames)
        .bind(root)
        .setUserData(ip)
        .go(rebootDevice)
    }

    NetworkCallable {
        id: resetDevice
        onStart: {
            showLoading(qsTr("正在重置云机..."))
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
                    treeModel.updateDeviceListV3(res.data.host_ip, res.data?.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 重置云机
    function reqResetDevice(ip, padNames){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/reset")
        .addList("db_ids", padNames)
        .bind(root)
        .setUserData(ip)
        .go(resetDevice)
    }

    NetworkCallable {
        id: runDevice
        onStart: {
            showLoading(qsTr("正在启动云机..."))
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
                    treeModel.updateDeviceListV3(res.data.host_ip, res.data?.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 启动云机
    function reqRunDevice(ip, padNames){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/run")
        .addList("db_ids", padNames)
        .bind(root)
        .setUserData(ip)
        .go(runDevice)
    }

    NetworkCallable {
        id: stopDevice
        onStart: {
            showLoading(qsTr("正在停止云机..."))
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
                if(res.code === 200 && res.data){
                    treeModel.updateDeviceListV3(res.data.host_ip, res.data?.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 停止云机
    function reqStopDevice(ip, padNames){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/stop")
        .addList("db_ids", padNames)
        .bind(root)
        .setUserData(ip)
        .go(stopDevice)
    }

    NetworkCallable {
        id: screenshots
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

    // 获取截图
    function reqScreenshots(ip, dbId){
        Network.get(`http://${ip}:18182/container_api/v1` + "/screenshots/" + dbId)
        .bind(root)
        .setUserData(ip)
        .go(screenshots)
    }

    NetworkCallable {
        id: deviceDetail
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    // treeModel.addDevice(res.data)
                }else{
                    showError(res.msg)
                }
            }
    }

    // 云机详情
    function reqDeviceDetail(ip, dbId){
        Network.get(`http://${ip}:18182/container_api/v1` + "/get_android_detail/" + dbId)
        .bind(root)
        .setUserData(ip)
        .go(deviceDetail)
    }

    NetworkCallable {
        id: deviceAdb
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

    // ADB启动
    function reqDeviceAdb(ip, dbId){
        Network.get(`http://${ip}:18182/container_api/v1` + "/adb_start/" + dbId)
        .bind(root)
        .setUserData(ip)
        .go(deviceAdb)
    }

    NetworkCallable {
        id: cleanImage
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

    // 清理镜像
    function reqCleanImage(ip){
        Network.get(`http://${ip}:18182/v1` + "/prune_images")
        .bind(root)
        .setUserData(ip)
        .go(cleanImage)
    }

    NetworkCallable {
        id: checkHost
        onStart: {
            showLoading()
        }
        onFinish: {
            hideLoading()
        }
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                // 离线
                treeModel.modifyHost(userData, {state:"offline"})
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    if(res.data.docker_status && res.data.http_status && res.data.ping_status){
                        // 在线
                        treeModel.modifyHost(userData, {state:"online"})
                    }else{
                        // 离线
                        treeModel.modifyHost(userData, {state:"offline"})
                    }
                }else{
                    showError(res.msg)
                }
            }
    }

    // 检查主机状态
    function reqCheckHost(ip){
        Network.get(`http://${ip}:18182/v1` + "/heartbeat")
        .bind(root)
        .setUserData(ip)
        .go(checkHost)
    }


    NetworkCallable {
        id: renameDevice
        onStart: {
            showLoading()
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
                    treeModel.updateDevice(res.data.db_id, {displayName: res.data.user_name, name: res.data.name})
                }
                else if(res.code == 0){

                }
                else{
                    showError(res.msg)
                }
            }
    }

    // 重命名（仅修改展示名称）
    function reqRenameDevice(ip, dbId, newUserName){
        Network.get(`http://${ip}:18182/container_api/v1` + `/rename/${dbId}/${newUserName}`)
        .bind(root)
        .setUserData(ip)
        .go(renameDevice)
    }

    NetworkCallable {
        id: deviceListByDB
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    treeModel.updateDeviceList(res.data.host_ip, res.data.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 获取云机列表(DB)
    function reqDeviceListByDB(ip){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/get_db")
        .bind(root)
        .openLog(false)
        .setUserData(ip)
        .go(deviceListByDB)
    }

    NetworkCallable {
        id: oneKeyNewDevice
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    treeModel.updateDeviceListV3(res.data.host_ip, res.data?.list ?? [])
                }else{
                    showError(res.msg)
                }
            }
    }

    // 一键新机（不带 ADI 参数，使用默认值）
    function reqOneKeyNewDevice(ip, padNames){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/replace_devinfo")
        .addList("db_ids", padNames)
        .add("lon", root.lon)
        .add("lat", root.lat)
        .add("locale", "")
        .add("timezone", "")
        .add("country", "")
        .add("wipeData", root.wipeData)
        .bind(root)
        .setUserData(ip)
        .go(oneKeyNewDevice)
    }

    // 一键新机（带 ADI 参数）
    function reqOneKeyNewDeviceWithAdi(ip, padNames, adiName, adiPass, wipeData){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/replace_devinfo")
        .addList("db_ids", padNames)
        .add("adiName", adiName || "")
        .add("adiPass", adiPass || "")
        .add("lon", root.lon)
        .add("lat", root.lat)
        .add("locale", "")
        .add("timezone", "")
        .add("country", "")
        .add("wipeData", wipeData !== undefined ? wipeData : root.wipeData)
        .bind(root)
        .setUserData(ip)
        .go(oneKeyNewDevice)
    }

    Timer{
        id: phoneListTimer
        repeat: true
        interval: 2000
        onTriggered: {
            explorer.updateScreenshotImage()
        }
    }

    Timer{
        id: deviceListTimer
        repeat: true
        interval: 5000
        onTriggered: {
            updateDeviceList()
        }
    }

    Timer{
        id: scannerTimer
        repeat: false
        interval: 1000
        onTriggered: {
            hideLoading()
        }
    }

    // 自动CBS升级相关变量
    property var hostsToUpgrade: []
    property int currentUpgradeIndex: 0
    property bool isAutoUpgrading: false

    // 自动CBS升级定时器
    Timer{
        id: autoCbsUpgradeTimer
        repeat: false
        interval: 100  // 短暂延迟，让UI有时间更新loading文本
        onTriggered: {
            checkAndUpgradeCbs()
        }
    }

    // CBS配置信息
    property var cbsConfig: null

    // 初始化CBS文件
    function initCbsFile() {
        const cbsDir = FluTools.getApplicationDirPath() + "/cbs"
        
        // 创建CBS目录
        Utils.createDirectory(cbsDir)
        
        // 读取CBS配置文件
        loadCbsConfig()
        
        // 验证CBS配置
        if (!validateCbsConfig()) {
            console.log("CBS配置验证失败，使用默认配置")
        }
        
        console.log("CBS目录:", cbsDir)
        console.log("CBS配置文件路径:", AppConfig.cbsConfigPath)
        console.log("CBS文件路径:", AppConfig.cbsFilePath)
    }

    // 加载CBS配置
    function loadCbsConfig() {
        try {
            const configContent = FluTools.readFile(AppConfig.cbsConfigPath)
            if (configContent) {
                cbsConfig = JSON.parse(configContent)
                console.log("CBS配置加载成功:", cbsConfig)
                
                // 更新AppConfig中的CBS信息
                if (cbsConfig && cbsConfig.cbsConfig) {
                    AppConfig.cbsVersion = cbsConfig.cbsConfig.version || "1.0.21"
                    AppConfig.cbsFileName = cbsConfig.cbsConfig.fileName || "latest.cbs"
                    console.log("CBS版本:", AppConfig.cbsVersion)
                    console.log("CBS文件名:", AppConfig.cbsFileName)
                }
            } else {
                console.log("CBS配置文件不存在，使用默认配置")
                // 使用默认配置
                cbsConfig = {
                    cbsConfig: {
                        version: "1.0.21",
                        fileName: "latest.cbs",
                        description: "默认CBS配置"
                    }
                }
            }
        } catch (e) {
            console.log("加载CBS配置失败:", e)
            // 使用默认配置
            cbsConfig = {
                cbsConfig: {
                    version: "1.0.21",
                    fileName: "latest.cbs",
                    description: "默认CBS配置"
                }
            }
        }
    }

    // 验证CBS配置
    function validateCbsConfig() {
        if (!cbsConfig || !cbsConfig.cbsConfig) {
            console.log("CBS配置无效")
            return false
        }
        
        const config = cbsConfig.cbsConfig
        
        // 检查必要字段
        if (!config.version || !config.fileName) {
            console.log("CBS配置缺少必要字段")
            return false
        }
        
        // 检查CBS文件是否存在
        const cbsPath = AppConfig.cbsFilePath
        console.log("检查CBS文件是否存在:", cbsPath)
        
        return true
    }

    // 更新CBS配置
    function updateCbsConfig(newConfig) {
        try {
            cbsConfig = newConfig
            if (cbsConfig && cbsConfig.cbsConfig) {
                AppConfig.cbsVersion = cbsConfig.cbsConfig.version
                AppConfig.cbsFileName = cbsConfig.cbsConfig.fileName
                console.log("CBS配置已更新:", AppConfig.cbsVersion, AppConfig.cbsFileName)
            }
        } catch (e) {
            console.log("更新CBS配置失败:", e)
        }
    }

    // 版本比较函数
    function compareVersions(version1, version2) {
        if (!version1 || !version2) return 0
        
        const v1Parts = version1.split('.').map(Number)
        const v2Parts = version2.split('.').map(Number)
        
        const maxLength = Math.max(v1Parts.length, v2Parts.length)
        
        for (let i = 0; i < maxLength; i++) {
            const v1Part = v1Parts[i] || 0
            const v2Part = v2Parts[i] || 0
            
            if (v1Part > v2Part) return 1
            if (v1Part < v2Part) return -1
        }
        
        return 0
    }

    // 检查并升级CBS
    property int checkedHostsCount: 0
    property int onlineHostsCount: 0
    function checkAndUpgradeCbs() {
        if (isAutoUpgrading) {
            // 如果正在升级中，不重复检查
            return
        }
        
        const hostList = treeModel.hostList()
        if (hostList.length === 0) {
            // 如果没有主机，隐藏loading并结束
            hideLoading()
            return
        }
        
        // 过滤出只有在线的主机
        const onlineHosts = hostList.filter(function(host) {
            return host.state === "online"
        })
        
        if (onlineHosts.length === 0) {
            // 如果没有在线主机，隐藏loading并结束
            console.log("没有在线主机，跳过CBS升级检查")
            hideLoading()
            return
        }
        
        console.log(`开始检查CBS版本... (共 ${onlineHosts.length} 台在线主机，跳过 ${hostList.length - onlineHosts.length} 台离线主机)`)
        // loading已经在扫描完成时显示，这里保持显示状态
        hostsToUpgrade = []
        currentUpgradeIndex = 0
        checkedHostsCount = 0
        onlineHostsCount = onlineHosts.length
        
        // 只检查在线主机的CBS版本
        onlineHosts.forEach(function(host) {
            reqHardwareCfgForUpgrade(host.ip)
        })
    }

    // 为升级检查获取主机配置
    function reqHardwareCfgForUpgrade(ip) {
        Network.get(`http://${ip}:18182/v1` + "/get_hardware_cfg")
        .bind(root)
        .setUserData(ip)
        .setTimeout(1500)
        .go(hardwareCfgForUpgrade)
    }

    // 主机配置检查回调
    NetworkCallable {
        id: hardwareCfgForUpgrade
        onError: (status, errorString, result, userData) => {
            console.log("获取主机配置失败:", userData, errorString)
            checkedHostsCount++
            checkAllHostsChecked()
        }
        onSuccess: (result, userData) => {
            try {
                var res = JSON.parse(result)
                if (res.code === 200 && res.data) {
                    const hostVersion = res.data.version || ""
                    const localVersion = AppConfig.cbsVersion
                    
                    console.log(`主机 ${userData} CBS版本: ${hostVersion}, 本地版本: ${localVersion}`)
                    
                    if (compareVersions(hostVersion, localVersion) < 0) {
                        console.log(`主机 ${userData} 需要升级CBS`)
                        hostsToUpgrade.push({
                            ip: userData,
                            currentVersion: hostVersion,
                            targetVersion: localVersion
                        })

                        scanner.startProcess(userData)
                    }
                }
            } catch (e) {
                console.log("解析主机配置失败:", e)
            }
            
            checkedHostsCount++
            checkAllHostsChecked()
        }
    }

    // 检查是否所有主机都已检查完毕
    function checkAllHostsChecked() {
        if (checkedHostsCount >= onlineHostsCount) {
            // 所有在线主机检查完成，开始升级或隐藏loading
            if (hostsToUpgrade.length === 0) {
                // 没有需要升级的主机，隐藏loading
                console.log("所有在线主机CBS版本都是最新的")
                hideLoading()
            } else {
                // 有需要升级的主机，开始升级
                startAutoUpgrade()
            }
        }
    }

    // 开始自动升级
    function startAutoUpgrade() {
        if (hostsToUpgrade.length === 0) {
            console.log("所有主机CBS版本都是最新的")
            hideLoading()
            return
        }
        
        console.log(`发现 ${hostsToUpgrade.length} 台主机需要升级CBS`)
        isAutoUpgrading = true
        currentUpgradeIndex = 0
        
        // 更新loading文本，告知用户正在进行CBS升级
        showLoading(qsTr("正在更新CBS程序，请稍候..."))
        upgradeNextHost()
    }

    // 升级下一台主机
    function upgradeNextHost() {
        if (currentUpgradeIndex >= hostsToUpgrade.length) {
            // 所有主机升级完成
            isAutoUpgrading = false
            console.log("CBS自动升级完成，共升级了", hostsToUpgrade.length, "台主机")
            // 升级完成，隐藏loading
            hideLoading()
            return
        }
        
        const host = hostsToUpgrade[currentUpgradeIndex]
        console.log(`正在升级主机 ${host.ip} 的CBS...`)
        
        // 使用定时器延迟执行，避免连续操作造成UI卡顿
        // 给UI一些时间处理事件，让界面保持响应
        upgradeDelayTimer.restart()
    }
    
    // 升级延迟定时器，避免连续操作造成卡顿
    Timer {
        id: upgradeDelayTimer
        interval: 100  // 100ms延迟，让UI有时间处理事件
        repeat: false
        onTriggered: {
            if (currentUpgradeIndex < hostsToUpgrade.length) {
                const host = hostsToUpgrade[currentUpgradeIndex]
                reqUpdateCbsAuto(host.ip, AppConfig.cbsFilePath)
            }
        }
    }

    // 自动更新CBS
    function reqUpdateCbsAuto(ip, cbsPath) {
        Network.postForm(`http://${ip}:18182/v1` + "/update_cbs")
        .setRetry(1)
        .addFile("file", cbsPath)
        .bind(root)
        .setUserData(ip)
        .setTimeout(600000)
        .go(updateCbsAuto)
    }

    // 自动CBS更新回调
    NetworkCallable {
        id: updateCbsAuto
        onError: (status, errorString, result, userData) => {
            console.log(`主机 ${userData} CBS升级失败:`, errorString)
            currentUpgradeIndex++
            // 使用定时器延迟执行下一个升级，避免连续操作造成UI卡顿
            upgradeNextHost()
        }
        onSuccess: (result, userData) => {
            console.log(`主机 ${userData} CBS升级成功`)
            currentUpgradeIndex++
            // 使用定时器延迟执行下一个升级，避免连续操作造成UI卡顿
            upgradeNextHost()
        }
    }


    NetworkCallable {
        id: ipInfo
        onError:
            (status, errorString, result, userData) => {
                console.debug("ipinfo.io error:", status + ";" + errorString + ";" + result)
                // 失败时使用默认值
                root.lon = 0.0
                root.lat = 0.0
                root.deviceLocale = "en-US"
                root.timezone = "UTC"
                root.country = "CN"
                // 保存位置信息到本地存储
                SettingsHelper.save("ipInfo_lon", root.lon)
                SettingsHelper.save("ipInfo_lat", root.lat)
                SettingsHelper.save("ipInfo_deviceLocale", root.deviceLocale)
                SettingsHelper.save("ipInfo_timezone", root.timezone)
                SettingsHelper.save("ipInfo_country", root.country)
                SettingsHelper.save("ipInfo_called", true)
            }
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result)
                    console.log("ipinfo.io response:", result)
                    
                    // 解析经纬度 (loc 格式: "lat,lon")
                    if (res.loc) {
                        var locParts = res.loc.split(",")
                        if (locParts.length === 2) {
                            root.lat = parseFloat(locParts[0])
                            root.lon = parseFloat(locParts[1])
                            // 验证范围
                            if (root.lat < -90 || root.lat > 90) {
                                console.warn("Invalid latitude:", root.lat, "using default 0.0")
                                root.lat = 0.0
                            }
                            if (root.lon < -180 || root.lon > 180) {
                                console.warn("Invalid longitude:", root.lon, "using default 0.0")
                                root.lon = 0.0
                            }
                            console.log("Parsed location - lat:", root.lat, "lon:", root.lon, "from loc:", res.loc)
                        } else {
                            console.warn("Invalid loc format:", res.loc)
                        }
                    } else {
                        console.warn("No loc field in response")
                    }
                    
                    // 获取时区
                    if (res.timezone && res.timezone.indexOf('/') !== -1) {
                        var tz = res.timezone.trim()
                        if (tz.length > 0 && tz.length <= 64) {
                            root.timezone = tz
                            console.log("Parsed timezone:", root.timezone)
                        } else {
                            console.warn("Invalid timezone length:", tz.length, "value:", tz)
                        }
                    } else {
                        console.warn("Invalid timezone format or missing:", res.timezone)
                    }
                    
                    // 根据国家代码获取 locale
                    if (res.country) {
                        root.country = res.country.toString().trim()
                        var locale = AppUtils.getLocaleFromCountry(root.country)
                        console.log("Country:", root.country, "mapped to locale:", locale)
                        // 验证 locale: 1-32字符，必须包含字母，允许 a-zA-Z0-9_-
                        if (locale && locale.length > 0 && locale.length <= 32 && /[a-zA-Z]/.test(locale) && /^[a-zA-Z0-9_-]+$/.test(locale)) {
                            root.deviceLocale = locale
                            console.log("Set deviceLocale:", root.deviceLocale)
                        } else {
                            console.warn("Invalid locale format:", locale)
                        }
                    } else {
                        console.warn("No country field in response, using default: CN")
                    }
                    
                    console.log("Final location info - lon:", root.lon, "lat:", root.lat, "locale:", root.deviceLocale, "timezone:", root.timezone, "country:", country)
                    
                    // 保存位置信息到本地存储
                    SettingsHelper.save("ipInfo_lon", root.lon)
                    SettingsHelper.save("ipInfo_lat", root.lat)
                    SettingsHelper.save("ipInfo_deviceLocale", root.deviceLocale)
                    SettingsHelper.save("ipInfo_timezone", root.timezone)
                    SettingsHelper.save("ipInfo_country", country)
                    SettingsHelper.save("ipInfo_called", true)
                    console.log("IP信息已保存到本地存储")
                } catch (e) {
                    console.error("Error parsing ipinfo.io response:", e)
                    // 失败时使用默认值
                    root.lon = 0.0
                    root.lat = 0.0
                    root.deviceLocale = "en-US"
                    root.timezone = "UTC"
                    // 保存位置信息到本地存储
                    SettingsHelper.save("ipInfo_lon", root.lon)
                    SettingsHelper.save("ipInfo_lat", root.lat)
                    SettingsHelper.save("ipInfo_deviceLocale", root.deviceLocale)
                    SettingsHelper.save("ipInfo_timezone", root.timezone)
                    SettingsHelper.save("ipInfo_country", "CN")
                    SettingsHelper.save("ipInfo_called", true)
                }
            }
    }

    // 从本地存储加载位置信息
    function loadIpInfoFromStorage() {
        var saved = SettingsHelper.get("ipInfo_called", false)
        if (saved) {
            root.lon = SettingsHelper.get("ipInfo_lon", 0.0)
            root.lat = SettingsHelper.get("ipInfo_lat", 0.0)
            root.deviceLocale = SettingsHelper.get("ipInfo_deviceLocale", "en-US")
            root.timezone = SettingsHelper.get("ipInfo_timezone", "UTC")
            console.log("从本地存储加载IP信息 - lon:", root.lon, "lat:", root.lat, "locale:", root.deviceLocale, "timezone:", root.timezone)
            return true
        }
        return false
    }

    // 查询位置信息
    function reqIpInfo(){
        Network.get("https://ipinfo.io/json?token=a41754d21f8c63")
        .bind(root)
        .go(ipInfo)
    }
}
