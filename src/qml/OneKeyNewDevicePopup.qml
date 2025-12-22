import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Utils

FluPopup {
    id: root
    implicitWidth: 480
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property var modelData: null  // 可以是单个云机对象，也可以是云机对象数组
    property var downloadedAdiList: []  // 当前主机的 ADI 列表
    property var brandModel: []
    property var brandModelData: ({})
    property string currentDeviceBrand: ""  // 当前云机的品牌
    property string currentDeviceModel: ""  // 当前云机的机型
    property var pendingHosts: []  // 待处理的主机列表，每个元素包含 {hostIp, dbIds, adiName, adiPass, adiPath, needUpload}
    property int currentHostIndex: -1  // 当前正在处理的主机索引
    property bool isProcessing: false  // 是否正在处理中
    property real lon: 0.0  // 经度
    property real lat: 0.0  // 纬度
    property string deviceLocale: "en-US"  // 语言
    property string timezone: "UTC"  // 时区
    property string country: "CN"  // 国家


    signal oneKeyNewDeviceResult(string hostIp, var list)
    signal oneKeyNewDeviceRequest(string hostIp, var dbIds, string adiName, string adiPass, bool wipeData)

    onOpened: {
        // 重置清除数据选项为默认开启（直接操作开关）
        if (typeof wipeDataSwitch !== 'undefined') {
            wipeDataSwitch.checked = true
            console.log("[一键新机] onOpened: 设置 wipeDataSwitch.checked =", wipeDataSwitch.checked)
        }
        
        // 清空品牌和机型列表，等待选择
        root.brandModel = []
        root.brandModelData = {}
        root.currentDeviceBrand = ""
        root.currentDeviceModel = ""
        if (typeof brandComboBox !== 'undefined') {
            brandComboBox.model = []
            brandComboBox.currentIndex = -1
        }
        if (typeof modelComboBox !== 'undefined') {
            modelComboBox.model = []
            modelComboBox.currentIndex = -1
        }
        
        // 从本地存储加载位置信息（不再调用接口，由 MainWindow 统一更新）
        loadIpInfoFromStorage()
        
        // 判断是单云机还是批量
        var deviceList = getDeviceList()
        if (deviceList.length === 1) {
            // 单云机：获取主机 ADI 列表
            var hostIp = getHostIp()
            if (hostIp) {
                reqAdiList(hostIp)
            }
            // 单云机：根据镜像的 Android 版本过滤品牌和机型，并获取当前品牌和机型
            var device = deviceList[0]
            if (device.hostIp && device.dbId) {
                // 获取当前云机的品牌和机型
                reqGetDeviceBrandModel(device.hostIp, device.dbId)
            }
            
            // 获取镜像的 Android 版本并过滤品牌和机型
            var imageName = device.image || ""
            var androidVersion = getAndroidVersionFromImage(imageName)
            if (androidVersion) {
                updateBrandModelByAndroidVersion(androidVersion)
            } else {
                // 如果没有 Android 版本，显示所有品牌
                updateBrandModelFromTemplate()
            }
        } else {
            // 批量：显示所有品牌和机型，默认不选择
            updateBrandModelFromTemplate()
        }
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

    // 获取主机 IP（从 modelData 中提取）
    function getHostIp() {
        if (!root.modelData) return ""
        if (Array.isArray(root.modelData)) {
            return root.modelData.length > 0 ? root.modelData[0].hostIp : ""
        }
        return root.modelData.hostIp || ""
    }

    // 获取云机列表
    function getDeviceList() {
        if (!root.modelData) return []
        if (Array.isArray(root.modelData)) {
            return root.modelData
        }
        return [root.modelData]
    }

    // 获取所有云机的 dbId 列表
    function getDbIds() {
        var deviceList = getDeviceList()
        var dbIds = []
        for (var i = 0; i < deviceList.length; i++) {
            var dbId = deviceList[i].dbId || deviceList[i].name
            if (dbId) {
                dbIds.push(dbId)
            }
        }
        return dbIds
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
                text: qsTr("一键新机")
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
            Layout.margins: 20
            spacing: 15

            Rectangle{
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                color: "#E3F2FD"
                radius: 8

                FluText {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("一键新机后云手机参数会重新生成，请谨慎操作！")
                    color: "#1976D2"
                }
            }

            // 品牌和机型选择（仅单云机时显示）
            RowLayout{
                visible: getDeviceList().length === 1
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
                visible: getDeviceList().length === 1
                
                FluText { 
                    text: qsTr("品牌"); 
                    font.bold: true 
                }
                
                FluComboBox {
                    id: brandComboBox
                    Layout.fillWidth: true
                    model: root.brandModel
                    onCurrentTextChanged: {
                        // 当品牌改变时，更新机型列表
                        const map = root.brandModelData || {};
                        if (currentText && currentText !== qsTr("未选定") && map[currentText]) {
                            modelComboBox.model = map[currentText]
                            // 默认选择第一个机型
                            if (modelComboBox.model.length > 0) {
                                modelComboBox.currentIndex = 0
                            } else {
                                modelComboBox.currentIndex = -1
                            }
                        } else {
                            // 如果选择的是"未选定"或没有匹配的品牌，清空机型列表
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
                }
            }

            RowLayout {
                FluText {
                    text: qsTr("清理数据")
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                }

                FluToggleSwitch {
                    id: wipeDataSwitch
                    checked: true  // 默认开启
                    checkColor: ThemeUI.primaryColor
                    onCheckedChanged: {
                        console.log("[一键新机] wipeDataSwitch.checked 改变为:", checked)
                    }
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
                enabled: true  // 批量时允许不选择品牌和机型
                onClicked: {
                    btnOk.enabled = false

                    var selectedBrand = brandComboBox.currentIndex >= 0 ? brandComboBox.currentText : ""
                    var selectedModel = modelComboBox.currentIndex >= 0 ? modelComboBox.currentText : ""
                    var adiName = ""
                    var adiPass = ""
                    var adiPath = ""
                    
                    // 如果选择的是"未选定"，清空品牌和机型
                    if (selectedBrand === qsTr("未选定")) {
                        selectedBrand = ""
                        selectedModel = ""
                    }
                    
                    // 如果选择了品牌和机型，获取对应的 ADI 信息
                    if (selectedBrand && selectedModel) {
                        var adiItem = getAdiItem(modelData[0].aospVersion, selectedBrand, selectedModel)
                        adiName = adiItem.name
                        adiPass = adiItem.pwd
                        adiPath = adiItem.name
                        console.log("modelData.aospVersion=", modelData[0].aospVersion, "modelData.image=", modelData[0].image)
                        console.log("[一键新机] 指定机型:", selectedBrand, selectedModel, "adiName=", adiName, "adiPass=", adiPass ? "***" : "")
                        
                        if (!adiName) {
                            showError(qsTr("找不到对应的 ADI 配置"), 3000)
                            btnOk.enabled = true
                            return
                        }
                        
                        // 若模板仅返回文件名，拼接到可执行目录/adi
                        if (adiPath && adiPath.indexOf('/') === -1 && adiPath.indexOf('\\') === -1) {
                            adiPath = FluTools.getApplicationDirPath() + "/adi/" + adiPath
                        }
                        
                        if (!adiPath || adiPath === "") {
                            showError(qsTr("找不到对应的 ADI 文件路径"), 3000)
                            btnOk.enabled = true
                            return
                        }
                    } else {
                        console.log("[一键新机] 未选择品牌和机型，将使用默认值")
                    }

                    // 获取所有云机列表
                    var deviceList = getDeviceList()
                    if (deviceList.length === 0) {
                        showError(qsTr("未找到有效的云机"), 3000)
                        btnOk.enabled = true
                        return
                    }

                    // 按主机分组
                    var groups = {}
                    for (var i = 0; i < deviceList.length; i++) {
                        var item = deviceList[i]
                        var hostIp = item.hostIp
                        var dbId = item.dbId || item.name
                        if (!hostIp || !dbId) continue
                        
                        if (!groups[hostIp]) {
                            groups[hostIp] = []
                        }
                        groups[hostIp].push(dbId)
                    }

                    // 每个主机调用一次 API
                    var hostIps = Object.keys(groups)
                    if (hostIps.length === 0) {
                        showError(qsTr("未找到有效的主机 IP"), 3000)
                        btnOk.enabled = true
                        return
                    }

                    // 如果未选择品牌和机型，直接调用 API（不传 adiName 和 adiPass）
                    if (!adiName) {
                        console.log("[一键新机] 未选择品牌和机型，直接调用 API")
                        for (var k = 0; k < hostIps.length; k++) {
                            var ip = hostIps[k]
                            var dbIds = groups[ip]
                            var wipeDataValue = typeof wipeDataSwitch !== 'undefined' ? wipeDataSwitch.checked : true
                            root.oneKeyNewDeviceRequest(ip, dbIds, "", "", wipeDataValue)
                        }
                        root.close()
                        btnOk.enabled = true
                        return
                    }
                    
                    // 如果选择了品牌和机型，需要检查每个主机是否需要上传 ADI
                    // 构建待处理的主机列表，检查每个主机是否需要上传 ADI
                    root.pendingHosts = []
                    root.currentHostIndex = 0
                    root.isProcessing = true
                    
                    for (var j = 0; j < hostIps.length; j++) {
                        var ip = hostIps[j]
                        var dbIds = groups[ip]
                        // 检查该主机是否已有 ADI（需要为每个主机分别获取 ADI 列表）
                        // 先假设需要上传，后续在获取 ADI 列表后更新
                        root.pendingHosts.push({
                            hostIp: ip,
                            dbIds: dbIds,
                            adiName: adiName,
                            adiPass: adiPass || "",
                            adiPath: adiPath,
                            needUpload: true  // 默认需要上传，获取 ADI 列表后更新
                        })
                    }
                    
                    // 开始处理第一个主机：获取其 ADI 列表
                    processNextHost()
                }
            }
        }
    }

    // 判断主机是否已存在指定ADI文件
    function isAdiFileExists(adiName) {
        if (!adiName) return false
        return root.downloadedAdiList.indexOf(adiName) !== -1
    }

    // 规范化 Android 版本
    function normalizeAndroidVersion(v){
        var s = (v === undefined || v === null) ? "" : ("" + v)
        var m = s.match(/(\d{1,2})/)
        return m && m[1] ? m[1] : ""
    }

    // 从镜像名称获取 Android 版本
    function getAndroidVersionFromImage(imageName) {
        if (!imageName) return ""
        
        // 首先尝试从 imagesModel 中查找
        for (var i = 0; i < imagesModel.rowCount(); i++) {
            var idx = imagesModel.index(i, 0)
            var n = imagesModel.data(idx, ImagesModel.NameRole).toString()
            var fn = imagesModel.data(idx, ImagesModel.FileNameRole).toString()
            var v = imagesModel.data(idx, ImagesModel.VersionRole).toString()
            if ((imageName && n === imageName) || (imageName && fn === imageName)) {
                return normalizeAndroidVersion(v)
            }
        }
        
        // 如果找不到，尝试从镜像名称中提取
        var m = imageName.match(/android\s*(\d{1,2})/i)
        if (m && m[1]) return normalizeAndroidVersion(m[1])
        
        return ""
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
                if (typeof brandComboBox !== 'undefined') {
                    brandComboBox.model = newBrandModel;
                    console.log("[一键新机] 根据 Android 版本更新品牌列表:", androidVersion, "brands:", newBrandModel);
                    
                    // 如果当前选择的品牌不在新列表中，重置选择
                    var currentBrand = brandComboBox.currentText;
                    if (currentBrand && newBrandModel.indexOf(currentBrand) === -1) {
                        brandComboBox.currentIndex = -1;
                        if (typeof modelComboBox !== 'undefined') {
                            modelComboBox.model = [];
                            modelComboBox.currentIndex = -1;
                        }
                    }
                    
                    // 如果已有获取到的品牌和机型，优先选中；否则选择第一个
                    if (root.currentDeviceBrand && root.currentDeviceModel) {
                        selectBrandAndModel(root.currentDeviceBrand, root.currentDeviceModel)
                    } else if (brandComboBox.currentIndex < 0 && newBrandModel.length > 0) {
                        brandComboBox.currentIndex = 0
                    }
                }
            } else {
                // 如果没有匹配的品牌，清空列表
                root.brandModel = [];
                root.brandModelData = {};
                if (typeof brandComboBox !== 'undefined') {
                    brandComboBox.model = [];
                    brandComboBox.currentIndex = -1;
                }
                if (typeof modelComboBox !== 'undefined') {
                    modelComboBox.model = [];
                    modelComboBox.currentIndex = -1;
                }
                console.log("[一键新机] 未找到匹配 Android 版本的品牌:", androidVersion);
            }
        } catch (e) {
            console.error("[一键新机] 根据 Android 版本更新品牌机型列表失败:", e);
        }
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
                // 判断是单云机还是批量
                var deviceList = getDeviceList()
                if (deviceList.length > 1) {
                    // 批量：在品牌列表开头添加"未选定"项
                    newBrandModel.unshift(qsTr("未选定"))
                    newModelData[qsTr("未选定")] = []
                }
                
                root.brandModel = newBrandModel;
                root.brandModelData = newModelData;
                
                // 更新品牌下拉框
                if (typeof brandComboBox !== 'undefined') {
                    brandComboBox.model = newBrandModel;
                    console.log("[一键新机] 更新品牌列表:", newBrandModel);
                    console.log("[一键新机] 更新机型数据:", newModelData);
                    
                    if (deviceList.length === 1) {
                        // 单云机：如果已有获取到的品牌和机型，优先选中；否则选择第一个
                        if (root.currentDeviceBrand && root.currentDeviceModel) {
                            selectBrandAndModel(root.currentDeviceBrand, root.currentDeviceModel)
                        } else if (brandComboBox.currentIndex < 0 && newBrandModel.length > 0) {
                            brandComboBox.currentIndex = 0
                        }
                    } else {
                        // 批量：默认选中"未选定"
                        brandComboBox.currentIndex = 0
                        if (typeof modelComboBox !== 'undefined') {
                            modelComboBox.model = []
                            modelComboBox.currentIndex = -1
                        }
                    }
                }
            }
        } catch (e) {
            console.error("Error updating brand model from template:", e);
        }
    }

    // 选择指定的品牌和机型
    function selectBrandAndModel(brand, model) {
        if (!brand || !model) return
        
        try {
            // 查找品牌在列表中的索引
            var brandIndex = root.brandModel.indexOf(brand)
            if (brandIndex >= 0 && typeof brandComboBox !== 'undefined') {
                brandComboBox.currentIndex = brandIndex
                // currentIndex 改变会触发 onCurrentTextChanged，自动更新机型列表
                
                // 等待机型列表更新后，选中对应的机型
                Qt.callLater(function() {
                    if (typeof modelComboBox !== 'undefined' && modelComboBox.model) {
                        var modelList = modelComboBox.model
                        var modelIndex = -1
                        // 兼容数组和 ListModel 两种格式
                        if (Array.isArray(modelList)) {
                            modelIndex = modelList.indexOf(model)
                        } else {
                            // 如果是 ListModel，遍历查找
                            for (var i = 0; i < modelList.length; i++) {
                                if (modelList[i] === model) {
                                    modelIndex = i
                                    break
                                }
                            }
                        }
                        if (modelIndex >= 0) {
                            modelComboBox.currentIndex = modelIndex
                            console.log("[一键新机] 已选中品牌和机型:", brand, model)
                        } else {
                            console.log("[一键新机] 未找到机型:", model, "在品牌", brand, "的机型列表中")
                        }
                    }
                })
            } else {
                console.log("[一键新机] 未找到品牌:", brand, "在品牌列表中")
            }
        } catch (e) {
            console.error("[一键新机] 选择品牌和机型失败:", e)
        }
    }

    // 处理下一个主机
    function processNextHost() {
        if (root.currentHostIndex >= root.pendingHosts.length) {
            // 所有主机处理完成
            root.isProcessing = false
            root.pendingHosts = []
            root.currentHostIndex = -1
            btnOk.enabled = true
            root.close()
            return
        }
        
        var hostInfo = root.pendingHosts[root.currentHostIndex]
        // 获取该主机的 ADI 列表
        reqAdiListForHost(hostInfo.hostIp)
    }

    // 检查并处理当前主机的 ADI
    function checkAndProcessHostAdi(hostIp, adiList) {
        if (root.currentHostIndex >= root.pendingHosts.length) return
        
        var hostInfo = root.pendingHosts[root.currentHostIndex]
        if (hostInfo.hostIp !== hostIp) return
        
        // 检查该主机是否已有 ADI
        var needUpload = adiList.indexOf(hostInfo.adiName) === -1
        hostInfo.needUpload = needUpload
        
        if (needUpload) {
            console.log("[一键新机] 主机", hostIp, "不存在 ADI", hostInfo.adiName, "，将上传:", hostInfo.adiPath)
            // 需要上传 ADI
            reqImportAdi(hostIp, hostInfo.adiPath)
        } else {
            console.log("[一键新机] 主机", hostIp, "已存在 ADI", hostInfo.adiName, "，跳过上传")
            // 直接执行一键新机
            var wipeDataValue = typeof wipeDataSwitch !== 'undefined' ? wipeDataSwitch.checked : true
            root.oneKeyNewDeviceRequest(hostInfo.hostIp, hostInfo.dbIds, hostInfo.adiName, hostInfo.adiPass, wipeDataValue)
            // 处理下一个主机
            root.currentHostIndex++
            processNextHost()
        }
    }

    // 主机 ADI 列表（用于初始化时获取）
    NetworkCallable {
        id: adiList
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result);
                    if(res.code === 200 && res.data){
                        if (Array.isArray(res.data.files)) {
                            root.downloadedAdiList = res.data.files.slice();
                        } else if (Array.isArray(res.data)) {
                            root.downloadedAdiList = res.data.map(function(item){
                                if (typeof item === 'string') return item;
                                if (item && item.name) return item.name;
                                if (item && item.brand && item.model) return item.brand + '_' + item.model;
                                return '';
                            }).filter(function(s){ return !!s; });
                        } else {
                            root.downloadedAdiList = [];
                        }
                    } else {
                        root.downloadedAdiList = [];
                    }
                } catch (e) {
                    root.downloadedAdiList = [];
                }
            }
        onError: (status, errorString, result, userData) => {
                     // ignore
                 }
    }

    // 主机 ADI 列表（用于处理时获取）
    NetworkCallable {
        id: adiListForHost
        onSuccess:
            (result, userData) => {
                try {
                    var hostIp = userData
                    var adiList = []
                    var res = JSON.parse(result);
                    if(res.code === 200 && res.data){
                        if (Array.isArray(res.data.files)) {
                            adiList = res.data.files.slice();
                        } else if (Array.isArray(res.data)) {
                            adiList = res.data.map(function(item){
                                if (typeof item === 'string') return item;
                                if (item && item.name) return item.name;
                                if (item && item.brand && item.model) return item.brand + '_' + item.model;
                                return '';
                            }).filter(function(s){ return !!s; });
                        }
                    }
                    checkAndProcessHostAdi(hostIp, adiList)
                } catch (e) {
                    console.error("[一键新机] 解析 ADI 列表失败:", e)
                    // 出错时假设需要上传
                    if (root.currentHostIndex < root.pendingHosts.length) {
                        var hostInfo = root.pendingHosts[root.currentHostIndex]
                        checkAndProcessHostAdi(hostInfo.hostIp, [])
                    }
                }
            }
        onError: (status, errorString, result, userData) => {
                     console.error("[一键新机] 获取 ADI 列表失败:", errorString)
                     // 出错时假设需要上传
                     if (root.currentHostIndex < root.pendingHosts.length) {
                         var hostInfo = root.pendingHosts[root.currentHostIndex]
                         checkAndProcessHostAdi(hostInfo.hostIp, [])
                     }
                 }
    }

    function reqAdiList(ip){
        if (!ip) return;
        Network.get(`http://${ip}:18182/v1` + "/get_adi_list")
        .setUserData(ip)
        .bind(root)
        .go(adiList)
    }

    function reqAdiListForHost(ip){
        if (!ip) return;
        Network.get(`http://${ip}:18182/v1` + "/get_adi_list")
        .setUserData(ip)
        .bind(root)
        .go(adiListForHost)
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
                            root.currentDeviceBrand = res.data.list[0].brand
                            root.currentDeviceModel = res.data.list[0].model_name
                        }
                    } else {
                        console.error("[云机详情] 请求品牌机型数据响应失败：", res.msg)
                    }
                } catch (e) {
                    console.error("[云机详情] 解析品牌机型数据失败:", e)
                }
            }
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

    // 一键新机 API
    NetworkCallable {
        id: oneKeyNewDevice
        onStart: {
            showLoading(qsTr("正在执行一键新机..."))
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
                    var res = JSON.parse(result)
                    if(res.code === 200){
                        var deviceList = res.data && res.data.list ? res.data.list : []
                        root.oneKeyNewDeviceResult(res.data.host_ip, deviceList)
                        root.close()
                    } else {
                        showError(res.msg || qsTr("一键新机失败"), 3000)
                    }
                } catch (e) {
                    console.warn("无法将行解析为JSON:", result, e)
                    showError(qsTr("解析响应失败"), 3000)
                }
            }
    }

    function reqOneKeyNewDevice(ip, dbIds, adiName, adiPass){
        var wipeDataValue = typeof wipeDataSwitch !== 'undefined' ? wipeDataSwitch.checked : true
        console.log("[一键新机] 请求一键新机", "ip=", ip, "dbIds=", dbIds, "adiName=", adiName, "adiPass=", adiPass ? "***" : "", "wipeData=", wipeDataValue, "wipeDataSwitch.checked=", typeof wipeDataSwitch !== 'undefined' ? wipeDataSwitch.checked : "undefined")
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/replace_devinfo")
        .addList("db_ids", dbIds)
        .add("adiName", adiName || "")
        .add("adiPass", adiPass || "")
        .add("lon", root.lon)
        .add("lat", root.lat)
        .add("locale", "")
        .add("timezone", "")
        .add("country", "")
        .add("wipeData", wipeDataValue)
        .setUserData(ip)
        .bind(root)
        .go(oneKeyNewDevice)
    }

    // 导入 ADI
    NetworkCallable {
        id: importAdi
        onStart: { 
            if (root.currentHostIndex < root.pendingHosts.length) {
                var hostInfo = root.pendingHosts[root.currentHostIndex]
                showLoading(qsTr("正在为主机 %1 导入 ADI...").arg(hostInfo.hostIp))
            } else {
                showLoading(qsTr("ADI 导入中..."))
            }
        }
        onFinish: { hideLoading() }
        onError:
            (status, errorString, result, userData) => {
                hideLoading()
                showError(errorString)
                btnOk.enabled = true
                root.isProcessing = false
                root.pendingHosts = []
                root.currentHostIndex = -1
            }
        onSuccess:
            (result, userData) => {
                // ADI 上传成功，直接执行一键新机
                if (root.currentHostIndex < root.pendingHosts.length) {
                    var hostInfo = root.pendingHosts[root.currentHostIndex]
                    console.log("[一键新机] ADI 上传成功，执行一键新机", "ip=", hostInfo.hostIp)
                    var wipeDataValue = typeof wipeDataSwitch !== 'undefined' ? wipeDataSwitch.checked : true
                    root.oneKeyNewDeviceRequest(hostInfo.hostIp, hostInfo.dbIds, hostInfo.adiName, hostInfo.adiPass, wipeDataValue)
                    // 处理下一个主机
                    root.currentHostIndex++
                    processNextHost()
                }
            }
    }

    function reqImportAdi(ip, adiPath){
        console.log("[一键新机] 请求导入 ADI", "ip=", ip, "adiPath=", adiPath)
        Network.postForm(`http://${ip}:18182/v1` + "/import_adi")
        .setRetry(1)
        .addFile("adiZip", adiPath)
        .setUserData(ip)
        .bind(root)
        .go(importAdi)
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
            console.log("[一键新机] 从本地存储加载IP信息 - lon:", root.lon, "lat:", root.lat, "locale:", root.deviceLocale, "timezone:", root.timezone, "country:", root.country)
        } else {
            // 如果没有保存的数据，使用默认值
            root.lon = 0.0
            root.lat = 0.0
            root.deviceLocale = "en-US"
            root.timezone = "UTC"
            root.country = "CN"
            console.log("[一键新机] 本地存储中没有IP信息，使用默认值")
        }
    }
}

