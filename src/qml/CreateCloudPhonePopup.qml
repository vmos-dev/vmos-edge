import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Utils

FluPopup {
    id: root
    implicitWidth: 480
    padding: 0
    closePolicy: Popup.CloseOnEscape
    focus: true
    property var modelData: null
    property int maxPhones: 12
    property int remainingPhones: 10
    property int phoneCount: 1
    property int downloadProgress: 0
    property bool isDownloading: false
    property var createDeviceParams: null
    property bool isChaining: false
    property var pendingCreate: null
    property int adiPollLeft: 0
    property var hostConfig: null
    property bool isResolutionManuallyChanged: false  // 标记用户是否手动修改过分辨率
    property bool isApplyingTemplateResolution: false  // 标记是否正在程序自动应用模板分辨率
    property bool boolStart: false  // 是否立即启动云机
    property bool boolGMS: false  // 是否启动GMS
    property int runningDeviceCount: 0  // 当前主机运行中的云机数量
    property real lon: 0.0  // 经度
    property real lat: 0.0  // 纬度
    property string deviceLocale: "en-US"  // 语言
    property string timezone: "UTC"  // 时区
    property string country: "CN"  // 国家
    property string macvlan_start_ip: ""  // 时区
    property string currVersion: "" // 当前选中镜像版本
    property bool isIdle: true

    ListModel {
        id: localImagesModel
    }

    Timer {
        id: adiPollTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.pendingCreate) {
                reqAdiList(root.pendingCreate.ip)
            }
        }
    }

    // property var androidVersions: ["10", "13", "14", "15"]
    // property int selectedAndroidVersion: 1

    // 合并分辨率与 DPI，格式：宽x高xDPI
    property var resolutionModel: [
        "720x1280x320",
        "1080x1920x420",
        "1080x2160x420",
        "1080x2340x440",
        "1080x2400x440",
        "1080x2460x440",
        "1440x2560x560",
        "1440x3200x640"
    ]


    property var dnsTypeModel: [qsTr("Google DNS(8.8.8.8)"), "阿里 DNS(223.5.5.5)", qsTr("自定义 DNS")]

    property var brandModel: []
    property var brandModelData: {}
    property var downloadedAdiList: []

    signal createResult(string hostIp, var list)
    signal openImageList()

    function processChunkData(data) {
        var lines = data.split('\n')
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "") continue

            try {
                console.log("=============", line)
                const res = JSON.parse(line)
                if(res.stage){
                    if(res.stage == "Uploading"){
                        stateText.text = qsTr("镜像上传中...")
                        const match = res.upload_progress
                        if(match){
                            root.isDownloading = true
                            root.downloadProgress = match
                        }
                    }else if(res.stage == "Loading"){
                        stateText.text = qsTr("镜像加载中...")
                        const match = res.load_progress
                        if(match){
                            root.isDownloading = true
                            root.downloadProgress = match
                            if (match === 100 && root.createDeviceParams) {
                                if (root.createDeviceParams.needUploadAdi && root.createDeviceParams.adiPath) {
                                    // 镜像已加载，需先上传ADI
                                    root.pendingCreate = Object.assign({}, root.createDeviceParams)
                                    root.adiPollLeft = 15
                                    reqImportAdi(root.createDeviceParams.ip, root.createDeviceParams.adiPath)
                                } else {
                                    // 直接创建，携带 adiName/adiPass
                                    reqCreateDevice(
                                        root.createDeviceParams.ip,
                                        root.createDeviceParams.name,
                                        root.createDeviceParams.repoName,
                                        root.createDeviceParams.resolution,
                                        root.createDeviceParams.selinux,
                                        root.createDeviceParams.dns,
                                        root.createDeviceParams.num,
                                        root.createDeviceParams.adiName || "",
                                        root.createDeviceParams.adiPass || "",
                                        root.createDeviceParams.adiPass || "",
                                        root.createDeviceParams.macvlan_start_ip || "",
                                        root.createDeviceParams.boolMacvlan || false
                                    );
                                    root.createDeviceParams = null;
                                }
                            }
                        }
                    }else if(res.stage == "Creating"){
                        stateText.text = qsTr("创建中...")
                    }else if(res.stage == "Failed"){
                        stateText.text = qsTr("创建失败...")
                        showError(res.message)
                        hideLoading()
                        isIdle = true  // 恢复按钮状态
                    }else if(res.stage == "Success"){
                        stateText.text = qsTr("镜像加载成功")
                        const match = res.load_progress
                        if(match){
                            root.isDownloading = true
                            root.downloadProgress = match
                            if (match === 100 && root.createDeviceParams) {
                                if (root.createDeviceParams.needUploadAdi && root.createDeviceParams.adiPath) {
                                    root.pendingCreate = Object.assign({}, root.createDeviceParams)
                                    root.adiPollLeft = 15
                                    reqImportAdi(root.createDeviceParams.ip, root.createDeviceParams.adiPath)
                                } else {
                                    reqCreateDevice(
                                        root.createDeviceParams.ip,
                                        root.createDeviceParams.name,
                                        root.createDeviceParams.repoName,
                                        root.createDeviceParams.resolution,
                                        root.createDeviceParams.selinux,
                                        root.createDeviceParams.dns,
                                        root.createDeviceParams.num,
                                        root.createDeviceParams.adiName || "",
                                        root.createDeviceParams.adiPass || "",
                                        root.createDeviceParams.macvlan_start_ip || "",
                                        root.createDeviceParams.boolMacvlan || false
                                    );
                                    root.createDeviceParams = null;
                                }
                            }
                        }
                    }
                }else if(res.code || res.code == 0){

                }else{
                    console.log("============", res.code, res.msg)
                    console.log("==================== not found")
                }
            } catch (e) {
                console.warn("无法将行解析为JSON:", line, e)
            }
        }
    }

    function updateDnsInput(index) {
        if (index === 2) { // "自定义 DNS"
            dnsInput.text = ""
            dnsInput.readOnly = false
            dnsInput.placeholderText = qsTr("请输入DNS地址")
        } else {
            var currentItemText = dnsTypeModel[index]
            var match = currentItemText.match(/\(([^)]+)\)/)
            if (match && match[1]) {
                dnsInput.text = match[1]
            } else {
                dnsInput.text = "" // Fallback
            }
            dnsInput.readOnly = true
        }
    }

    function resetBrandModelSelection() {
        brandComboBox.currentIndex = -1
        modelComboBox.currentIndex = -1
        modelComboBox.model = []
    }

    // 判断主机是否已存在指定ADI文件
    function isAdiFileExists(adiName) {
        if (!adiName) return false
        return root.downloadedAdiList.indexOf(adiName) !== -1
    }

    //  获取adi项
    function getAdiItem(inVersion, inBrand, inModelName) {
        for (var i = 0; i < tempLateModel.rowCount(); i++) {
            var index = tempLateModel.index(i, 0);
            var tempBrand = tempLateModel.data(index, TemplateModel.BrandRole).toString();
            var tempModel = tempLateModel.data(index, TemplateModel.ModelRole).toString();
            var tempVersion = tempLateModel.data(index, TemplateModel.AsopVersionRole).toString();
            if (tempBrand === inBrand && tempModel === inModelName && tempVersion === inVersion) {
                return {
                    brand: tempBrand,
                    model: tempModel,
                    version: tempVersion,
                    name: tempLateModel.data(index, TemplateModel.NameRole).toString(),
                    layout: tempLateModel.data(index, TemplateModel.LayoutRole).toString(),
                    pwd: tempLateModel.data(index, TemplateModel.PwdRole).toString()
                };
            }
        }
        return "";
    }

    function parseLayoutToResolution(layout) {
        if (!layout) return null
        var m = ("" + layout).match(/(\d+)x(\d+)x(\d+)/)
        if (!m) return null
        var fpsSelected = fpsComboBox.currentText;
        return {
            width: parseInt(m[1]),
            height: parseInt(m[2]),
            dpi: parseInt(m[3]),
            fps: parseInt(fpsSelected)
        }
    }

    // 根据模板 layout 文本，选中分辨率下拉框对应项；若无则追加一项并选中
    function applyLayoutToResolution(layout) {
        if (!layout) return
        // 标记正在程序自动应用模板分辨率
        root.isApplyingTemplateResolution = true
        var text = "" + layout
        var index = root.resolutionModel.indexOf(text)
        if (index !== -1) {
            resolutionComboBox.currentIndex = index
        } else {
            // 追加到 model 并选中
            var newList = root.resolutionModel.slice()
            newList.push(text)
            root.resolutionModel = newList
            resolutionComboBox.model = root.resolutionModel
            resolutionComboBox.currentIndex = root.resolutionModel.length - 1
        }
        // 延迟清除标志，确保 onCurrentIndexChanged 能够检测到
        Qt.callLater(function() {
            root.isApplyingTemplateResolution = false
        })
    }

    function updateBrandModelFromTemplate() {
        try {
            // 从 templateModel 获取品牌和机型数据
            var newBrandModel = [];
            var newModelData = {};
            
            for (var i = 0; i < tempLateModel.rowCount(); i++) {
                var index = tempLateModel.index(i, 0);
                var brand = tempLateModel.data(index, TemplateModel.BrandRole).toString();
                var model = tempLateModel.data(index, TemplateModel.ModelRole).toString();
                var adiPath = tempLateModel.data(index, TemplateModel.FilePathRole).toString();
                
                if (brand && model) {
                    // 如果品牌不存在，添加到品牌列表
                    if (newBrandModel.indexOf(brand) === -1) {
                        newBrandModel.push(brand);
                        newModelData[brand] = [];
                    }
                    // 添加机型到对应品牌
                    if (newModelData[brand].indexOf(model) === -1) {
                        newModelData[brand].push(model);
                    }
                }
            }
            
            // 更新品牌和机型数据
            if (newBrandModel.length > 0) {
                root.brandModel = newBrandModel;
                root.brandModelData = newModelData;
                
                // 更新品牌下拉框
                brandComboBox.model = newBrandModel;
                console.log("Updated brand model from template:", newBrandModel);
                console.log("Updated model data from template:", newModelData);
                brandComboBox.currentIndex = -1
                brandComboBox.currentIndex = 0
            }
        } catch (e) {
            console.error("Error updating brand model from template:", e);
        }
    }

    function normalizeAndroidVersion(v){
        var s = (v === undefined || v === null) ? "" : ("" + v)
        var m = s.match(/(\d{1,2})/)
        return m && m[1] ? m[1] : ""
    }

    // 根据 Android 版本更新品牌和机型列表（只显示匹配该版本的品牌和机型）
    function updateBrandModelByAndroidVersion(androidVersion) {
        try {
            if (!androidVersion) {
                // 如果没有 Android 版本，显示所有品牌
                updateBrandModelFromTemplate()
                return
            }
            
            var normalizedVersion = normalizeAndroidVersion(androidVersion)
            var newBrandModel = [];
            var newModelData = {};
            
            // 从 templateModel 获取匹配该 Android 版本的品牌和机型数据
            for (var i = 0; i < tempLateModel.rowCount(); i++) {
                var index = tempLateModel.index(i, 0);
                var brand = tempLateModel.data(index, TemplateModel.BrandRole).toString();
                var model = tempLateModel.data(index, TemplateModel.ModelRole).toString();
                var templateVersion = tempLateModel.data(index, TemplateModel.AsopVersionRole).toString();
                var normalizedTemplateVersion = normalizeAndroidVersion(templateVersion);
                
                // 只添加匹配 Android 版本的品牌和机型
                if (brand && model && normalizedTemplateVersion === normalizedVersion) {
                    // 如果品牌不存在，添加到品牌列表
                    if (newBrandModel.indexOf(brand) === -1) {
                        newBrandModel.push(brand);
                        newModelData[brand] = [];
                    }
                    // 添加机型到对应品牌
                    if (newModelData[brand].indexOf(model) === -1) {
                        newModelData[brand].push(model);
                    }
                }
            }
            
            // 更新品牌和机型数据
            if (newBrandModel.length > 0) {
                root.brandModel = newBrandModel;
                root.brandModelData = newModelData;
                
                // 更新品牌下拉框
                brandComboBox.model = newBrandModel;
                console.log("Updated brand model by Android version:", androidVersion, "brands:", newBrandModel);
                
                // 如果当前选择的品牌不在新列表中，重置选择
                var currentBrand = brandComboBox.currentText;
                if (currentBrand && newBrandModel.indexOf(currentBrand) === -1) {
                    brandComboBox.currentIndex = -1;
                    modelComboBox.model = [];
                    modelComboBox.currentIndex = -1;
                }
                
                brandComboBox.currentIndex = -1;
                brandComboBox.currentIndex = 0
            } else {
                // 如果没有匹配的品牌，清空列表
                root.brandModel = [];
                root.brandModelData = {};
                brandComboBox.model = [];
                brandComboBox.currentIndex = -1;
                modelComboBox.model = [];
                modelComboBox.currentIndex = -1;
                console.log("No brands found for Android version:", androidVersion);
            }
        } catch (e) {
            console.error("Error updating brand model by Android version:", e);
        }
    }

    // 根据本地镜像条目（name/fileName）查找 Android 版本
    function getAndroidVersionForImage(imageName, fileName) {
        for (var i = 0; i < imagesModel.rowCount(); i++) {
            var idx = imagesModel.index(i, 0)
            var n = imagesModel.data(idx, ImagesModel.NameRole).toString()
            var fn = imagesModel.data(idx, ImagesModel.FileNameRole).toString()
            var v = imagesModel.data(idx, ImagesModel.VersionRole).toString()
            if ((imageName && n === imageName) || (fileName && fn === fileName)) {
                return normalizeAndroidVersion(v)
            }
        }
        // 兼容主机仓库名：尝试从仓库名/文件名中解析 android 版本，例如 vcloud_android13_...
        var source = (imageName || "") + "_" + (fileName || "")
        var m = source.match(/android\s*(\d{1,2})/i)
        if (m && m[1]) return m[1]
        return ""
    }

    // 依据安卓版本从模板中选择默认模板
    function findDefaultTemplateByVersion(androidVersion) {
        if (!androidVersion)
            return null
        for (var i = 0; i < tempLateModel.rowCount(); i++) {
            var idx = tempLateModel.index(i, 0)
            var v = tempLateModel.data(idx, TemplateModel.AsopVersionRole).toString()
            if (normalizeAndroidVersion(v) === normalizeAndroidVersion(androidVersion)) {
                return {
                    brand: tempLateModel.data(idx, TemplateModel.BrandRole).toString(),
                    model: tempLateModel.data(idx, TemplateModel.ModelRole).toString(),
                    layout: tempLateModel.data(idx, TemplateModel.LayoutRole).toString(),
                    name: tempLateModel.data(idx, TemplateModel.NameRole).toString(),
                    filePath: tempLateModel.data(idx, TemplateModel.FilePathRole).toString(),
                    version: v,
                    pwd: tempLateModel.data(idx, TemplateModel.PwdRole).toString()
                }
            }
        }
        return null
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

    function isValidIp(ip) {
        var regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
        return regex.test(ip);
    }

    property var downloadedImages: []

    // 存储空间检查（单位按返回值理解为MB，32G=32768MB）
    function toNumberMb(v){
        // 处理空字符串、null、undefined 等情况
        if (v === "" || v === null || v === undefined) {
            return 0
        }
        var n = Number(v)
        return isFinite(n) ? n : 0
    }
    function isStorageInsufficient(){
        if (!root.hostConfig)
            return false
        var mmc = toNumberMb(root.hostConfig.mmc_total)
        var ssd = toNumberMb(root.hostConfig.ssd_total)
        
        // 只有当 MMC 和 SSD 都小于 32G 时才阻止
        // 即：至少有一个大于等于 32G 才允许操作
        return (mmc < 32768 && ssd < 32768)
    }
    function guardStorageOrWarn(){
        if (isStorageInsufficient()){
            showError(qsTr("存储空间不足，请插入SSD固态盘之后进行操作！"), 3000)
            root.isChaining = false
            isIdle = true
            return false
        }
        return true
    }

    Component.onCompleted: {
        updateDnsInput(dnsTypeComboBox.currentIndex)
        // filterImages()
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
        root.downloadedAdiList = []
        root.isDownloading = false
        root.isResolutionManuallyChanged = false  // 重置标志
        root.boolStart = false  // 重置立即启动选项
        hideLoading()

        // 获取当前主机运行中的云机数量
        if (root.modelData && root.modelData.ip && typeof treeModel !== 'undefined') {
            root.runningDeviceCount = treeModel.getRunningDeviceCount(root.modelData.ip)
        }

        root.remainingPhones = root.maxPhones - root.runningDeviceCount
        if(root.remainingPhones < 0){
            root.remainingPhones = 0
        }

        root.phoneCount = Math.min(1, root.remainingPhones)
        phoneCountSpinBox.value = root.phoneCount
        macvlanToggle.checked = false
        isIdle =true
        
        // 清空品牌和机型列表，等待镜像选择后再根据 Android 版本过滤
        root.brandModel = []
        root.brandModelData = {}
        brandComboBox.model = []
        brandComboBox.currentIndex = -1
        modelComboBox.model = []
        modelComboBox.currentIndex = -1
        
        // 拉取主机硬件配置（用于存储空间检查）
        reqHardwareCfg(modelData.ip)
        
        reqDeviceImageList(modelData.ip)
        reqAdiList(modelData.ip)
        
        // 从本地存储加载位置信息（不再调用接口，由 MainWindow 统一更新）
        loadIpInfoFromStorage()
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
                text: qsTr("创建云机（不限创建总数）")
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
                text: qsTr("主机地址：%1 （同时运行上限 %2 台）").arg(root.modelData?.ip ?? "").arg(root.maxPhones)
                color: ThemeUI.primaryColor
            }

            RowLayout{
                FluText {
                    text: qsTr("选择镜像");
                    font.bold: true
                }

                Item{
                    Layout.fillWidth: true
                }

                FluTextButton{
                    text: qsTr("前往镜像管理")
                    font.pixelSize: 12
                    textColor: ThemeUI.primaryColor
                    onClicked: {
                        root.openImageList()
                    }
                }
            }

            FluComboBox {
                id: imageComboBox
                Layout.fillWidth: true
                model: localImagesModel
                textRole: "displayText"
                delegate: FluItemDelegate {
                    id: itemDelegate
                    width: imageComboBox.width
                    text: imageComboBox.textRole ? (Array.isArray(imageComboBox.model) ? modelData[imageComboBox.textRole] : model[imageComboBox.textRole]) : modelData
                    palette.text: imageComboBox.palette.text
                    font: imageComboBox.font
                    palette.highlightedText: imageComboBox.palette.highlightedText
                    highlighted: imageComboBox.highlightedIndex === index
                    hoverEnabled: imageComboBox.hoverEnabled
                    contentItem: FluText {
                        text: itemDelegate.text
                        font: itemDelegate.font
                        color: {
                            var isDownloaded = false
                            if (imageComboBox.model) {
                                var idx = index
                                if (idx >= 0 && idx < localImagesModel.count) {
                                    var item = localImagesModel.get(idx)
                                    isDownloaded = item.isDownloaded || false
                                }
                            }
                            if (isDownloaded) {
                                return "#00AA00"  // 绿色
                            }
                            // 使用默认颜色逻辑
                            if (itemDelegate.down) {
                                return FluTheme.dark ? FluColors.Grey80 : FluColors.Grey120
                            }
                            return FluTheme.dark ? FluColors.White : FluColors.Grey220
                        }
                    }
                }
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < localImagesModel.count) {
                        var it = localImagesModel.get(currentIndex)
                        var fileName = it.fileName
                        var imageName = it.name
                        var v = getAndroidVersionForImage(imageName, fileName)
                        currVersion = v;
                        
                        // 根据 Android 版本更新品牌和机型列表（只显示匹配该版本的品牌）
                        updateBrandModelByAndroidVersion(v)
                        
                        var tpl = findDefaultTemplateByVersion(v)
                        if (tpl && tpl.layout) {
                            applyLayoutToResolution(tpl.layout)
                        }
                    } else {
                        // 如果没有选择镜像，显示所有品牌
                        updateBrandModelFromTemplate()
                    }
                }
            }

            RowLayout{
                FluText { text: qsTr("DNS类型"); font.bold: true }
                FluComboBox {
                    id: dnsTypeComboBox
                    Layout.fillWidth: true
                    model: root.dnsTypeModel
                    onCurrentIndexChanged: {
                        updateDnsInput(currentIndex)
                    }
                }

                Item{
                    Layout.preferredWidth: 20
                }

                FluText { text: qsTr("DNS地址"); font.bold: true }
                FluTextBox {
                    id: dnsInput
                    Layout.fillWidth: true
                    placeholderText: qsTr("请输入DNS地址")
                }
            }

            RowLayout{
                FluText {
                    text: qsTr("指定机型");
                    font.bold: true
                }

                Item{
                    Layout.fillWidth: true
                }
            }

            RowLayout{
                Layout.topMargin: 8
                
                FluText { 
                    text: qsTr("品牌"); 
                    font.bold: true 
                }
                
                FluComboBox {
                    id: brandComboBox
                    Layout.fillWidth: true
                    model: root.brandModel
                    onCurrentTextChanged: {
                        // 当品牌改变时，更新机型列表（兼容 brandModelData 未初始化的场景）
                        const map = root.brandModelData || {};
                        if (currentText && map[currentText]) {
                            modelComboBox.model = map[currentText]
                            modelComboBox.currentIndex = -1
                            modelComboBox.currentIndex = 0
                        } else {
                            modelComboBox.model = []
                            modelComboBox.currentIndex = -1
                        }
                    }
                }

                Item{
                    Layout.preferredWidth: 20
                }

                FluText { 
                    text: qsTr("机型");
                    font.bold: true 
                }
                
                FluComboBox {
                    id: modelComboBox
                    Layout.fillWidth: true
                    model: []
                    onCurrentTextChanged: {
                        if (brandComboBox.currentText && currentText) {
                            var currAdi = getAdiItem(currVersion, brandComboBox.currentText, currentText)
                            var lay = currAdi.layout
                            if (lay) {
                                applyLayoutToResolution(lay)
                            }
                        }
                    }
                }
            }

            RowLayout{
                Layout.topMargin: 5
                RowLayout {
                    spacing: 5

                    FluText {
                        text: qsTr("局域网IP");
                        font.bold: true
                    }

                    Image {
                        id: macvlanIcon
                        source: "qrc:/res/pad/help.svg"
                        width: 10
                        height: 10

                        FluTooltip {
                            parent: macvlanIcon
                            visible: macvlanMouseArea.containsMouse
                            text: qsTr("拥有局域网内的独立IP")
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
                        id: macvlanToggle
                        checkColor: ThemeUI.primaryColor
                        onCheckedChanged:{
                             if (checked) 
                             {
                                reqNetServiceInfo(modelData.ip)
                             } else {
                                startIpInput.text = ""
                                gatewayInput.text = ""
                                subnetMaskInput.text = ""
                                subnetCidrInput.text = ""
                             }
                        }
                    }
                }
            }

            ColumnLayout {
                id: networkConfigArea
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 15
                visible: macvlanToggle.checked

                // 使用两个并行的列布局，确保垂直对齐
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    // 左侧列：起始IP和默认网关
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 15

                        // 起始IP
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            FluText {
                                text: "起始IP"
                                font.pixelSize: 12
                                color: "#666"
                                Layout.preferredWidth: 60
                                Layout.alignment: Qt.AlignVCenter
                            }

                            FluTextBox {
                                id: startIpInput
                                Layout.fillWidth: true
                                font.pixelSize: 12
                                placeholderText: "192.168.10.20"
                                property bool isValid: false
                                onEditingFinished: {
                                    isValid = isValidIp(text.trim())
                                    if (text.length > 0 && !isValid) {
                                        showError(qsTr("请输入正确的IP地址"))
                                        text = macvlan_start_ip
                                    } 
                                }
                            }
                        }

                        // 默认网关
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            FluText {
                                text: "默认网关"
                                font.pixelSize: 12
                                color: "#666"
                               
                                Layout.preferredWidth: 60  // 与起始IP标签相同宽度
                                Layout.alignment: Qt.AlignVCenter
                            }

                            FluTextBox {
                                id: gatewayInput
                                font.pixelSize: 12
                                Layout.fillWidth: true
                                readOnly: true
                                placeholderText: "192.168.0.1"
                            }
                        }
                    }

                    // 右侧列：子网掩码和Subnet
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 15

                        // 子网掩码
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            FluText {
                                text: "子网掩码"
                                font.pixelSize: 12
                                color: "#666"
                                Layout.preferredWidth: 60
                                Layout.alignment: Qt.AlignVCenter
                            }

                            FluTextBox {
                                id: subnetMaskInput
                                font.pixelSize: 12
                                Layout.fillWidth: true
                                readOnly: true
                                placeholderText: "255.255.254.5"
                            }
                        }

                        // Subnet
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            FluText {
                                text: "Subnet"
                                font.pixelSize: 12
                                color: "#666"
                                Layout.preferredWidth: 60  // 与子网掩码标签相同宽度
                                Layout.alignment: Qt.AlignVCenter
                            }

                            FluTextBox {
                                id: subnetCidrInput
                                Layout.fillWidth: true
                                font.pixelSize: 12
                                readOnly: true
                                placeholderText: "192.168.10.0/23"
                                validator: IntValidator {
                                    bottom: 0
                                    top: 32
                                }
                            }
                        }
                    }
                }
            }


            RowLayout{
                
                FluText {
                    text: qsTr("分辨率");
                    font.bold: true
                }
                
                FluComboBox {
                    id: resolutionComboBox
                    Layout.fillWidth: true
                    model: root.resolutionModel
                    onCurrentIndexChanged: {
                        // 只有当不是程序自动应用模板时，才标记为用户手动修改
                        if (currentIndex >= 0 && root.modelData && !root.isApplyingTemplateResolution) {
                            root.isResolutionManuallyChanged = true
                            console.log("[创建云机] 用户手动修改了分辨率")
                        }
                    }
                }

                Item{
                    Layout.preferredWidth: 20
                }

                FluText {
                    text: qsTr("帧率(fps)");
                    font.bold: true
                }

                FluComboBox {
                    id: fpsComboBox
                    implicitWidth: 65
                    model: [30, 60]
                    onCurrentTextChanged: {
                        console.log("select index ", currentIndex)
                    }
                }

                Item{
                    Layout.preferredWidth: 20
                }

                VCheckBox{
                    id: gmsChekcBox
                    text: qsTr("启用GMS")
                    textColor: ThemeUI.blackColor
                    checked: root.boolGMS
                    onClicked: {
                        root.boolGMS = checked
                    }
                }

            }

            RowLayout{
                Layout.topMargin: 5

                FluText {
                    id: textName
                    text: phoneCountSpinBox.value > 1 ? qsTr("云机名称前缀") : qsTr("云机名称");
                    font.bold: true
                }
                FluTextBox {
                    id: nameInput
                    Layout.fillWidth: true
                    text: "vmos"
                    placeholderText: qsTr("请输入云机名称")
                    maximumLength: 196
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
                        onValueChanged: {
                            let max_left = Math.max(root.remainingPhones, root.maxPhones)
                            if (root.boolStart) {
                                max_left = Math.min(root.remainingPhones, root.maxPhones - root.runningDeviceCount)
                            }

                            if (value > max_left) {
                                showError(qsTr("剩余可创建云机数：%1").arg(max_left))
                                root.phoneCount = max_left
                            } else {
                                root.phoneCount = Math.max(value, 0)
                            }
                        }
                    }

                    FluText{
                        text: qsTr("单次可创建云机数量不超过 12 台")
                        color: "#999"
                    }

                    VCheckBox{
                        id: boolStartCheckBox
                        text: qsTr("自动启动")
                        checked: root.boolStart
                        textColor: ThemeUI.blackColor
                        // selectedImage: ThemeUI.loadRes("common/option_selected.png")
                        // unselectedImag: ThemeUI.loadRes("common/option_unselected.png")
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
                            text: nameInput.text + (phoneCountSpinBox.value > 1 ? `-${(index + 1).toString().padStart(3, '0')}` : "")
                            elide: Text.ElideMiddle
                            width: Math.min(200, implicitWidth)
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 10 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                visible: root.isDownloading

                RowLayout{
                    Layout.fillWidth: true
                    FluText {
                        id: stateText
                        text: qsTr("镜像上传中..")
                        Layout.alignment: Qt.AlignLeft
                    }
                    Item{Layout.fillWidth: true}
                    FluText {
                        text: root.downloadProgress + "%"
                        Layout.alignment: Qt.AlignRight
                    }
                }
                FluProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    indeterminate: false
                    value: root.downloadProgress
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
                id: btnOk
                text: qsTr("确定")
                normalColor: ThemeUI.primaryColor
                onPressed: phoneCountSpinBox.focus = false
                enabled: root.phoneCount > 0 && root.isIdle
                onClicked: {
                    if (imageComboBox.currentIndex < 0) {
                        console.log("No image selected.")
                        return;
                    }

                    const num = Number(phoneCountSpinBox.value)
                    if(num <= 0){
                        showError(qsTr("创建云机数量必须大于0"))
                        return
                    }

                    // if(num > root.remainingPhones){
                    //     showError(qsTr("超过了还能创建的最大数量") + root.remainingPhones)
                    //     return
                    // }

                    const name = validateName(nameInput.text)
                    if(!name){
                        return
                    }

                    var item = localImagesModel.get(imageComboBox.currentIndex);
                    var fileName = item.fileName;
                    var imageName = item.name; // 镜像版本
                    var path = item.path;
                    // 解析 Android 版本，选择默认模板
                    var androidVersion = getAndroidVersionForImage(imageName, fileName)
                    var defaultTpl = findDefaultTemplateByVersion(androidVersion)
                    var adiName = defaultTpl ? defaultTpl.name : ""
                    var defaultAdiPath = defaultTpl ? defaultTpl.filePath : ""
                    var adiPass = ""  // 初始化密码
                    var start_ip = startIpInput.text
                    console.log("[创建云机] 解析版本:", androidVersion, "默认模板:", JSON.stringify(defaultTpl), "初始adiName:", adiName)
                    
                    // 使用镜像版本与主机已存在的镜像列表比较
                    var isDownloaded = root.downloadedImages.indexOf(imageName) !== -1;
                    console.log("[创建云机] 镜像是否存在:", isDownloaded, "image=", imageName, "path=", path)
                    
                    // 首先从用户选择的分辨率下拉框获取分辨率
                    var resolutionParts = resolutionComboBox.currentText.split('x');
                    var fpsSelected = fpsComboBox.currentText;
                    var resolution = {
                        width: parseInt(resolutionParts[0]),
                        height: parseInt(resolutionParts[1]),
                        dpi: parseInt(resolutionParts[2]),
                        fps: parseInt(fpsSelected)
                    };

                    var dnsList = [];
                    if (dnsInput.text) {
                        dnsList = dnsInput.text.split(/[\s,;\n]+/).filter(function(s) { return s.trim() !== "" });
                    }

                    // 禁用按钮，防止重复点击
                    root.isIdle = false
                    
                    // 检查是否需要上传 ADI（优先默认模板；若选择"指定机型"则使用选择项）
                    var needUploadAdi = false;
                    var adiPath = "";
                    if (brandComboBox.currentText && modelComboBox.currentText) {
                        var selectedBrand = brandComboBox.currentText;
                        var selectedModel = modelComboBox.currentText;
                        var currAdiItem = getAdiItem(androidVersion, selectedBrand, selectedModel)
                        // 从模板获取真实的 ADI 文件名和密码
                        adiName = currAdiItem.name
                        adiPass = currAdiItem.pwd
                        var layoutStr = currAdiItem.layout
                        // 只有当用户没有手动修改过分辨率时，才使用模板中的分辨率
                        if (!root.isResolutionManuallyChanged) {
                            var layoutResolution = parseLayoutToResolution(layoutStr)
                            if (layoutResolution) {
                                resolution = layoutResolution
                                console.log("[创建云机] 用户未手动修改分辨率，使用模板分辨率:", JSON.stringify(resolution))
                            }
                        } else {
                            console.log("[创建云机] 用户已手动修改分辨率，使用用户选择:", JSON.stringify(resolution))
                        }
                        console.log("[创建云机] 指定机型:", selectedBrand, selectedModel, "layout=", layoutStr, "最终分辨率=", JSON.stringify(resolution), "adiName=", adiName, "adiPass=", adiPass ? "***" : "")
                        if (!isAdiFileExists(adiName)) {
                            needUploadAdi = true;
                            adiPath = adiName;
                            // 若模板仅返回文件名，拼接到可执行目录/adi
                            if (adiPath && adiPath.indexOf('/') === -1 && adiPath.indexOf('\\') === -1) {
                                adiPath = FluTools.getApplicationDirPath() + "/adi/" + adiPath
                            }
                            console.log("[创建云机] 主机不存在该ADI, 将上传:", adiPath)
                            if (!adiPath || adiPath === "") {
                                showError(qsTr("找不到对应的 ADI 文件路径"), 3000);
                                isIdle = true;
                                return;
                            }
                        } else {
                            console.log("[创建云机] 主机已存在该ADI, 跳过上传:", adiName)
                        }
                        // 如果模板中也未找到名称，则保持空字符串
                    } else if (defaultTpl) {
                        // 从默认模板获取密码（优先使用 defaultTpl.pwd，如果没有则从模板中查找）
                        adiPass = defaultTpl.pwd
                        // 只有当用户没有手动修改过分辨率时，才使用默认模板中的布局
                        if (!root.isResolutionManuallyChanged) {
                            var tplResolution = parseLayoutToResolution(defaultTpl.layout)
                            if (tplResolution) {
                                resolution = tplResolution
                                console.log("[创建云机] 用户未手动修改分辨率，使用默认模板分辨率:", JSON.stringify(resolution))
                            }
                        } else {
                            console.log("[创建云机] 用户已手动修改分辨率，使用用户选择:", JSON.stringify(resolution))
                        }
                        console.log("[创建云机] 使用默认模板: layout=", defaultTpl.layout, "最终分辨率=", JSON.stringify(resolution), "adiName=", adiName, "adiPass=", adiPass ? "***" : "")
                        if (!isAdiFileExists(defaultTpl.name)) {
                            needUploadAdi = true;
                            // 模型中保存的是文件名，这里拼接可执行目录/adi/文件名
                            adiPath = FluTools.getApplicationDirPath() + "/adi/" + defaultTpl.name;
                            console.log("[创建云机] 主机不存在该ADI, 将上传:", adiPath)
                            if (!adiPath || adiPath === "") {
                                showError(qsTr("找不到默认模板的 ADI 文件路径"), 3000);
                                isIdle = true;
                                return;
                            }
                        } else {
                            console.log("[创建云机] 主机已存在该ADI, 跳过上传:", adiName)
                        }
                    }
                    
                    // 如果是主机镜像（没有本地路径），直接创建云机
                    if (!path || path === "") {
                        console.log("[创建云机] 主机镜像，无需上传镜像。needUploadAdi=", needUploadAdi)
                        if (needUploadAdi) {
                            // 需要先上传 ADI，然后创建云机
                            root.isChaining = true
                            root.createDeviceParams = {
                                "ip": root.modelData.ip,
                                "name": name,
                                "repoName": imageName,
                                "resolution": resolution,
                                "selinux": true,
                                "dns": dnsList,
                                "num": num,
                                "adiName": adiName,
                                "adiPass": adiPass || "",
                                "macvlan_start_ip" : start_ip,
                                "boolMacvlan": macvlanToggle.checked
                            }
                            // 保存待创建参数，供 ADI 列表可见后触发创建
                            root.pendingCreate = Object.assign({}, root.createDeviceParams)
                            root.adiPollLeft = 15
                            console.log("[创建云机] 发起上传 ADI:", adiPath)
                            reqImportAdi(root.modelData.ip, adiPath);
                        } else {
                            console.log("[创建云机] 直接创建云机(主机镜像)")
                            reqCreateDevice(root.modelData.ip, name, imageName, resolution, true, dnsList, num, adiName, adiPass || "", start_ip, macvlanToggle.checked);
                        }
                        return;
                    }

                    if (dnsTypeComboBox.currentIndex === 2) { // Custom DNS
                        if (dnsList.length === 0) {
                            showError(qsTr("自定义DNS不能为空"), 3000);
                            isIdle = true  // 恢复按钮状态
                            return;
                        }
                        for (var i = 0; i < dnsList.length; i++) {
                            if (!isValidIp(dnsList[i])) {
                                showError(qsTr("无效的DNS地址: ") + dnsList[i], 3000);
                                isIdle = true  // 恢复按钮状态
                                return;
                            }
                        }
                    }

                    if (isDownloaded) {
                        console.log("[创建云机] 主机已存在该镜像，无需上传。needUploadAdi=", needUploadAdi)
                        if (needUploadAdi) {
                            // 需要先上传 ADI，然后创建云机
                            root.isChaining = true
                            root.createDeviceParams = {
                                "ip": root.modelData.ip,
                                "name": name,
                                "repoName": imageName,
                                "resolution": resolution,
                                "selinux": true,
                                "dns": dnsList,
                                "num": num,
                                "adiName": adiName,
                                "adiPass": adiPass || "",
                                "macvlan_start_ip" : start_ip,
                                "boolMacvlan": macvlanToggle.checked
                            }
                            // 保存待创建参数，供 ADI 列表可见后触发创建
                            root.pendingCreate = Object.assign({}, root.createDeviceParams)
                            root.adiPollLeft = 15
                            console.log("[创建云机] 发起上传 ADI:", adiPath)
                            reqImportAdi(root.modelData.ip, adiPath);
                        } else {
                            console.log("[创建云机] 直接创建云机(主机已有镜像)")
                            reqCreateDevice(root.modelData.ip, name, imageName, resolution, true, dnsList, num, adiName, adiPass || "", start_ip, macvlanToggle.checked);
                        }
                    } else {
                        console.log("[创建云机] 主机不存在该镜像，将上传:", path, "needUploadAdi=", needUploadAdi)
                        root.isChaining = true
                        root.createDeviceParams = {
                            "ip": root.modelData.ip,
                            "name": name,
                            "repoName": imageName, // 使用镜像版本作为repoName
                            "resolution": resolution,
                            "selinux": true,
                            "dns": dnsList,
                            "num": num,
                            "needUploadAdi": needUploadAdi,
                            "adiPath": adiPath,
                            "adiName": adiName,
                            "adiPass": adiPass || "",
                            "macvlan_start_ip" : start_ip,
                            "boolMacvlan": macvlanToggle.checked
                        }
                        reqUploadImage(root.modelData.ip, path);
                    }
                }
            }
        }
    }



    // 从镜像名中提取时间戳（支持多种格式）
    function extractTimeFromFileName(fileName) {
        if (!fileName) return 0
        
        // 格式1: yyyyMMddHHmmss (14位数字)
        var match1 = fileName.match(/(\d{14})/)
        if (match1) {
            var timeStr = match1[1]
            var year = parseInt(timeStr.substring(0, 4))
            var month = parseInt(timeStr.substring(4, 6))
            var day = parseInt(timeStr.substring(6, 8))
            var hour = parseInt(timeStr.substring(8, 10))
            var minute = parseInt(timeStr.substring(10, 12))
            var second = parseInt(timeStr.substring(12, 14))
            return new Date(year, month - 1, day, hour, minute, second).getTime()
        }
        
        // 格式2: yyyyMMddHHmmsszzz (17位数字，包含毫秒)
        var match2 = fileName.match(/(\d{17})/)
        if (match2) {
            var timeStr2 = match2[1]
            var year2 = parseInt(timeStr2.substring(0, 4))
            var month2 = parseInt(timeStr2.substring(4, 6))
            var day2 = parseInt(timeStr2.substring(6, 8))
            var hour2 = parseInt(timeStr2.substring(8, 10))
            var minute2 = parseInt(timeStr2.substring(10, 12))
            var second2 = parseInt(timeStr2.substring(12, 14))
            var millisecond2 = parseInt(timeStr2.substring(14, 17))
            return new Date(year2, month2 - 1, day2, hour2, minute2, second2, millisecond2).getTime()
        }
        
        // 格式3: yyyy-MM-dd_HH:mm:ss 或 yyyy-MM-dd HH:mm:ss
        var match3 = fileName.match(/(\d{4})-(\d{2})-(\d{2})[_\s](\d{2}):(\d{2}):(\d{2})/)
        if (match3) {
            var year3 = parseInt(match3[1])
            var month3 = parseInt(match3[2])
            var day3 = parseInt(match3[3])
            var hour3 = parseInt(match3[4])
            var minute3 = parseInt(match3[5])
            var second3 = parseInt(match3[6])
            return new Date(year3, month3 - 1, day3, hour3, minute3, second3).getTime()
        }
        
        // 格式4: yyyyMMdd (8位数字，日期)
        var match4 = fileName.match(/(\d{8})/)
        if (match4) {
            var timeStr4 = match4[1]
            var year4 = parseInt(timeStr4.substring(0, 4))
            var month4 = parseInt(timeStr4.substring(4, 6))
            var day4 = parseInt(timeStr4.substring(6, 8))
            return new Date(year4, month4 - 1, day4).getTime()
        }
        
        // 如果找不到时间，返回0（会排到最后）
        return 0
    }

    NetworkCallable {
        id: deviceImageList
        onSuccess:
            (result, userData) => {
                try {
                    localImagesModel.clear()
                    var hostRepos = []
                    var res = JSON.parse(result)
                    if(res.code === 200 && res.data && Array.isArray(res.data)){
                        hostRepos = res.data.map(function(img) { return img.repository; });
                        root.downloadedImages = hostRepos;
                    } else {
                        console.debug("get_img_list returned error or no data:", res.msg);
                        root.downloadedImages = [];
                    }

                    // 先收集所有镜像数据到数组
                    var imageList = []

                    // 首先添加本地模型中的镜像
                    for (var i = 0; i < imagesModel.rowCount(); i++) {
                        var index = imagesModel.index(i, 0);

                        var name = imagesModel.data(index, ImagesModel.NameRole).toString(); // 镜像版本
                        var fileName = imagesModel.data(index, ImagesModel.FileNameRole).toString(); // 镜像文件名
                        var version = imagesModel.data(index, ImagesModel.VersionRole).toString(); // Android版本
                        var path = imagesModel.data(index, ImagesModel.PathRole).toString();

                        // repository是镜像版本，应该与本地模型中的镜像版本（NameRole）比较
                        var isDownloaded = hostRepos.indexOf(name) !== -1;

                        // 显示格式：镜像文件名（已上传）- 安卓版本
                        var displayText = fileName;
                        if (isDownloaded) {
                            displayText += qsTr(" (已上传)");
                        }
                        // if (version) {
                        //     displayText += " - " + version;
                        // }

                        imageList.push({
                            "displayText": displayText,
                            "fileName": fileName,
                            "name": name, // 镜像版本，用于与主机比较
                            "path": path,
                            "isDownloaded": isDownloaded
                        });
                    }

                    // 然后添加主机中存在但本地模型中没有的镜像
                    for (var j = 0; j < hostRepos.length; j++) {
                        var hostRepo = hostRepos[j];
                        var isInLocalModel = false;
                        
                        // 检查是否已在本地模型中
                        for (var k = 0; k < imagesModel.rowCount(); k++) {
                            var localIndex = imagesModel.index(k, 0);
                            var localName = imagesModel.data(localIndex, ImagesModel.NameRole).toString();
                            if (localName === hostRepo) {
                                isInLocalModel = true;
                                break;
                            }
                        }
                        
                        // 如果主机镜像不在本地模型中，添加到列表
                        if (!isInLocalModel) {
                            var displayText = hostRepo + qsTr(" (已上传)");
                            imageList.push({
                                "displayText": displayText,
                                "fileName": hostRepo, // 使用镜像版本作为文件名
                                "name": hostRepo, // 镜像版本
                                "path": "", // 主机镜像没有本地路径
                                "isDownloaded": true
                            });
                        }
                    }

                    // 按镜像名中的时间降序排序
                    imageList.sort((a, b) => {
                        var timeA = extractTimeFromFileName(a.fileName)
                        var timeB = extractTimeFromFileName(b.fileName)
                        if (timeA === 0 && timeB === 0) {
                            // 如果都没有时间，按文件名排序
                            return b.fileName.localeCompare(a.fileName)
                        }
                        if (timeA === 0) return 1  // 没有时间的排到最后
                        if (timeB === 0) return -1
                        return timeB - timeA  // 降序
                    })

                    // 将排序后的数据添加到模型
                    for (var m = 0; m < imageList.length; m++) {
                        localImagesModel.append(imageList[m])
                    }

                    if (localImagesModel.count > 0) {
                        imageComboBox.currentIndex = 0;
                        var v = getAndroidVersionForImage(imageList[0].name)
                        root.currVersion = normalizeAndroidVersion(v)
                    } else {
                        imageComboBox.currentIndex = -1;
                    }
                } catch (e) {
                    console.error("Error in deviceImageList.onSuccess:", e);
                }
            }
        onError: (status, errorString, result, userData) => {
                     console.error("deviceImageList error:", errorString);
                     root.downloadedImages = [];
                 }
    }

    NetworkCallable {
        id: adiList
        onSuccess:
            (result, userData) => {
                try {
                    console.log("ADI List response:", result);
                    var res = JSON.parse(result);
                    if(res.code === 200 && res.data){
                        if (Array.isArray(res.data.list)) {
                            root.downloadedAdiList = res.data.list.map(function(item){
                                return item.adiName
                            })
                        } else if (Array.isArray(res.data.files)) {
                            root.downloadedAdiList = res.data.files.slice();        // 新返回结构：data.files 为文件名数组
                        } else if (Array.isArray(res.data)) {
                            // 兼容旧结构：直接数组，元素可能是对象
                            root.downloadedAdiList = res.data.map(function(item){
                                if (typeof item === 'string') return item;
                                if (item && item.name) return item.name;
                                if (item && item.brand && item.model) return item.brand + '_' + item.model;
                                return '';
                            }).filter(function(s){ return !!s; });
                        } else {
                            root.downloadedAdiList = [];
                        }
                        console.log("Downloaded ADI list:", root.downloadedAdiList);
                        // 如果正在等待新上传的 ADI 可见，则轮询直到可见再创建
                        if (root.pendingCreate) {
                            var need = root.pendingCreate.adiName || ""
                            if (need && root.downloadedAdiList.indexOf(need) !== -1) {
                                // 可见了，发起创建
                                var p = root.pendingCreate
                                root.pendingCreate = null
                                reqCreateDevice(p.ip, p.name, p.repoName, p.resolution, p.selinux, p.dns, p.num, p.adiName, p.adiPass, p.macvlan_start_ip, p.boolMacvlan || false)
                            } else if (root.adiPollLeft > 0) {
                                root.adiPollLeft -= 1
                                adiPollTimer.start()
                            } else {
                                // 超时也尝试创建一次（有些后端不暴露列表，但已可用）
                                var p2 = root.pendingCreate
                                root.pendingCreate = null
                                reqCreateDevice(p2.ip, p2.name, p2.repoName, p2.resolution, p2.selinux, p2.dns, p2.num, p2.adiName, p2.adiPass, p.macvlan_start_ip, p2.boolMacvlan || false)
                            }
                        }
                    } else {
                        console.debug("get_adi_list returned error or no data:", res.msg);
                        root.downloadedAdiList = [];
                    }
                } catch (e) {
                    console.error("Error in adiList.onSuccess:", e);
                    root.downloadedAdiList = [];
                }
            }
        onError: (status, errorString, result, userData) => {
                     console.error("adiList error:", errorString);
                 }
    }

    // 获取云机内已下载镜像列表
    function reqDeviceImageList(ip){
        console.log("reqDeviceImageList called with ip:", ip);
        if (!ip) {
            console.error("reqDeviceImageList: IP address is null or empty. Aborting request.");
            return;
        }
        Network.get(`http://${ip}:18182/v1` + "/get_img_list")
        .setUserData(ip)
        .bind(root)
        .go(deviceImageList)
    }

    // 获取 ADI 列表
    function reqAdiList(ip){
        console.log("reqAdiList called with ip:", ip);
        if (!ip) {
            console.error("reqAdiList: IP address is null or empty. Aborting request.");
            return;
        }
        Network.get(`http://${ip}:18182/v1` + "/get_adi_list")
        .setUserData(ip)
        .bind(root)
        .go(adiList)
    }

    NetworkCallable {
        id: createDevice
        onStart: {
            showLoading(qsTr("正在创建云机..."))
        }
        onFinish: {
            hideLoading()
            root.isChaining = false
            isIdle = true  // 恢复按钮状态
        }
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
                isIdle = true  // 恢复按钮状态
                root.createResult(false)
                root.close()
            }
        onSuccess:
            (result, userData) => {
                try {
                    const res = JSON.parse(result)
                    if(res.code === 200){
                        // 创建成功
                        root.createResult(res.data.host_ip, res.data.list)
                        root.close()
                    }else if(res.code === -1){
                        showError("创建任务正在执行中，请稍后再试", 3000)
                        isIdle = true  // 恢复按钮状态
                    }else{
                        showError(res.msg, 3000)
                        isIdle = true  // 恢复按钮状态
                    }
                } catch (e) {
                    console.warn("无法将行解析为JSON:", result, e)
                    isIdle = true  // 恢复按钮状态
                }
            }
    }

    // 创建云机
    function reqCreateDevice(ip, padName, image_url, resolution, selinux, dns, count, adiName, adiPass, start_ip, boolMacvlan){
        if (!guardStorageOrWarn()) return
        console.log("create with adiName:", adiName, "boolMacvlan:", boolMacvlan, "fps:", resolution.fps, "bool_gms_disabled:", !root.boolGMS)
        
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/create")
        .add("user_name", padName)
        .add("count", count)
        .add("image_repository", image_url)
        .addMap("resolution", resolution)
        .add("selinux", selinux)
        .addList("dns", dns)
        .add("adiName", adiName || "")
        .add("adiPass", adiPass || "")
        .add("bool_start", root.boolStart)
        .add("bool_macvlan", boolMacvlan || false)
        .add("lon", root.lon)
        .add("lat", root.lat)
        .add("locale", root.deviceLocale)
        .add("macvlan_start_ip", start_ip || "")
        .add("timezone", root.timezone)
        .add("country", root.country)
        .add("bool_gms_disabled", !root.boolGMS)
        .setUserData(ip)
        .bind(root)
        .go(createDevice)
    }

    NetworkCallable {
        id: uploadImage
        property string _buffer: ""

        onStart: {
            _buffer = ""
            showLoading(qsTr("镜像上传中..."))
            root.isDownloading = true
        }
        onFinish: {
            if(_buffer.length > 0){
                processChunkData(_buffer)
                _buffer = ""
            }
            if (!root.isChaining) {
                hideLoading()
                isIdle = true  // 恢复按钮状态
            }
            root.isDownloading = false
        }
        onChunck:
            (chunk, userData) => {
                _buffer += chunk
                var separator = '\n'
                var lastIndex = _buffer.lastIndexOf(separator)

                if (lastIndex !== -1) {
                    var processable = _buffer.substring(0, lastIndex)
                    _buffer = _buffer.substring(lastIndex + 1)
                    processChunkData(processable)
                }
            }

        onError:
            (status, errorString, result, userData) => {
                hideLoading()
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
                isIdle = true  // 恢复按钮状态
                root.createResult(false)
                root.close()
            }
        onSuccess:
            (result, userData) => {
                hideLoading()
                var res = JSON.parse(result)
                if(res.code !== 200) {
                    showError(res.msg)
                }
            }
        onUploadProgress:
            (sent,total)=>{
                stateText.text = qsTr("镜像上传中...")
                root.downloadProgress = (sent * 1.0 / total) * 100
            }
    }

    // 上传镜像
    function reqUploadImage(ip, path){
        if (!guardStorageOrWarn()) return
        console.log("[创建云机] 准备上传镜像:", path, "size=", fileCopyManager.getFileSize(path))
        Network.postForm(`http://${ip}:18182/v1` + "/import_image")
        .setRetry(1)
        .addFile("file", path)
        .setUserData(ip)
        .setTimeout(400000)
        .bind(root)
        .go(uploadImage)
    }

    NetworkCallable {
        id: importAdi

        onStart: {
            showLoading(qsTr("ADI 导入中..."))
        }
        onFinish: {
            if (!root.isChaining) {
                hideLoading()
                isIdle = true  // 恢复按钮状态
            }
        }
        onError:
            (status, errorString, result, userData) => {
                hideLoading()
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
                isIdle = true  // 恢复按钮状态
                root.createResult(false)
                root.close()
            }
        onSuccess:
            (result, userData) => {
                console.log("[创建云机] ADI 上传成功, result=", result)
                if (userData) {
                    console.log("[创建云机] 上传后主动拉取 ADI 列表校验, ip=", userData)
                    reqAdiList(userData)
                }
            }
        onUploadProgress:
            (sent,total)=>{
                console.log("=====", (sent * 1.0 / total) * 100)
            }
    }

    // 导入 ADI
    function reqImportAdi(ip, adiPath){
        if (!guardStorageOrWarn()) return
        console.log("[创建云机] 准备上传 ADI:", adiPath, "size=", fileCopyManager.getFileSize(adiPath))
        Network.postForm(`http://${ip}:18182/v1` + "/import_adi")
        .setRetry(1)
        .addFile("adiZip", adiPath)
        .setUserData(ip)
        .bind(root)
        .go(importAdi)
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
                    console.log("=========", result)
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


    // 从本地存储加载位置信息
    function loadIpInfoFromStorage() {
        var saved = SettingsHelper.get("ipInfo_called", false)
        if (saved) {
            root.lon = SettingsHelper.get("ipInfo_lon", 0.0)
            root.lat = SettingsHelper.get("ipInfo_lat", 0.0)
            root.deviceLocale = SettingsHelper.get("ipInfo_deviceLocale", "en-US")
            root.timezone = SettingsHelper.get("ipInfo_timezone", "UTC")
            root.country = SettingsHelper.get("ipInfo_country", "CN")
            console.log("从本地存储加载IP信息 - lon:", root.lon, "lat:", root.lat, "locale:", root.deviceLocale, "timezone:", root.timezone, "country:", root.country)
        } else {
            // 如果没有保存的数据，使用默认值
            root.lon = 0.0
            root.lat = 0.0
            root.deviceLocale = "en-US"
            root.timezone = "UTC"
            root.country = "CN"
            console.log("本地存储中没有IP信息，使用默认值")
        }
    }

    // 获取主机网络配置
    function reqNetServiceInfo(ip){
        Network.get(`http://${ip}:18182/v1` + "/net_info")
        .bind(root)
        .go(net_info)
    }

    NetworkCallable {
        id: net_info
        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                // showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                var res = JSON.parse(result)
                //todo 解析数据
                if(res.code === 200) {
                    startIpInput.text = res.data.host_ip
                    gatewayInput.text = res.data.gateway
                    subnetMaskInput.text = res.data.netmask
                    subnetCidrInput.text = res.data.subnet
                    macvlan_start_ip = res.data.host_ip
                }else{
                    showError(res.msg)
                }
            }
    }
}
