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
    property var modelData: null
    property int maxPhones: 16
    property int remainingPhones: 10
    property int phoneCount: 1
    property int downloadProgress: 0
    property bool isDownloading: false
    property var createDeviceParams: null
    property bool isChaining: false
    // 主机已有的 ADI 列表
    property var downloadedAdiList: []
    property var brandModel: []
    property var brandModelData: {}
    property string currentDeviceBrand: ""  // 当前云机的品牌
    property string currentDeviceModel: ""  // 当前云机的机型

    ListModel {
        id: localImagesModel
    }

    // property var androidVersions: ["10", "13", "14", "15"]
    // property int selectedAndroidVersion: 1

    // property var resolutionModel: [
    //     "720x1280",
    //     "1080x1920",
    //     "1080x2160",
    //     "1080x2340",
    //     "1080x2400",
    //     "1080x2460",
    //     "1440x2560",
    //     "1440x3200"
    // ]

    // property var dpiModel: [
    //     "320",
    //     "420",
    //     "420",
    //     "440",
    //     "440",
    //     "440",
    //     "560",
    //     "640"
    // ]


    // property var dnsTypeModel: [qsTr("Google DNS(8.8.8.8)"), "阿里 DNS(223.5.5.5)", qsTr("自定义 DNS")]

    signal upgradeResult(string hostIp, var list)

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
                                reqUpgradDeviceImage(root.createDeviceParams.hostIp,
                                                     root.createDeviceParams.dbId,
                                                     root.createDeviceParams.repoName,
                                                     root.createDeviceParams.adiName || "",
                                                     root.createDeviceParams.adiPass || "")
                                root.createDeviceParams = null;
                            }
                        }
                    }else if(res.stage == "Creating"){
                        stateText.text = qsTr("创建中...")
                    }else if(res.stage == "Failed"){
                        stateText.text = qsTr("创建失败...")
                        showError(res.message)
                        hideLoading()
                    }else if(res.stage == "Success"){
                        stateText.text = qsTr("镜像加载成功")
                        const match = res.load_progress
                        if(match){
                            root.isDownloading = true
                            root.downloadProgress = match
                            if (match === 100 && root.createDeviceParams) {
                                reqUpgradDeviceImage(root.createDeviceParams.hostIp,
                                                     root.createDeviceParams.dbId,
                                                     root.createDeviceParams.repoName,
                                                     root.createDeviceParams.adiName || "",
                                                     root.createDeviceParams.adiPass || "")
                                root.createDeviceParams = null;
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

    // function updateDnsInput(index) {
    //     if (index === 2) { // "自定义 DNS"
    //         dnsInput.text = ""
    //         dnsInput.readOnly = false
    //         dnsInput.placeholderText = qsTr("请输入DNS地址")
    //     } else {
    //         var currentItemText = dnsTypeModel[index]
    //         var match = currentItemText.match(/\(([^)]+)\)/)
    //         if (match && match[1]) {
    //             dnsInput.text = match[1]
    //         } else {
    //             dnsInput.text = "" // Fallback
    //         }
    //         dnsInput.readOnly = true
    //     }
    // }

    // function validateName(name){
    //     name = name.trim()
    //     if (name.length < 2 || name.length > 11) {
    //         showError(qsTr("长度限制：2-11字符"))
    //         return ""
    //     }
    //     if (/[^a-zA-Z0-9_.-]/.test(name)) {
    //         showError(qsTr("支持字符：[a-zA-Z0-9_.-]"))
    //         return ""
    //     }
    //     if (!/^[a-zA-Z0-9]/.test(name) || !/[a-zA-Z0-9]$/.test(name)) {
    //         showError(qsTr("首字符和尾字符必须为[a-zA-Z0-9]"))
    //         return ""
    //     }
    //     return name
    // }

    // function isValidIp(ip) {
    //     var regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
    //     return regex.test(ip);
    // }

    property var downloadedImages: []

    Component.onCompleted: {
        // updateDnsInput(dnsTypeComboBox.currentIndex)
        // filterImages()
    }

    onOpened: {
        root.isDownloading = false
        // root.remainingPhones = root.maxPhones - root.modelData.hostPadCount
        // if(root.remainingPhones < 0){
        //     root.remainingPhones = 0
        // }
        // root.phoneCount = Math.min(1, root.remainingPhones)
        // phoneCountSpinBox.value = root.phoneCount
        
        // 清空品牌和机型列表，等待镜像选择后再根据 Android 版本过滤
        root.brandModel = []
        root.brandModelData = {}
        if (typeof brandComboBox !== 'undefined') {
            brandComboBox.model = []
            brandComboBox.currentIndex = -1
        }
        if (typeof modelComboBox !== 'undefined') {
            modelComboBox.model = []
            modelComboBox.currentIndex = -1
        }
        
        reqDeviceImageList(root.modelData.hostIp)
        reqAdiList(root.modelData.hostIp)
        
        // 获取云机当前品牌和机型
        if (root.modelData && root.modelData.hostIp && root.modelData.dbId) {
            reqGetDeviceBrandModel(root.modelData.hostIp, root.modelData.dbId)
        }
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
                text: qsTr("修改镜像")
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

            FluText {
                text: qsTr("云机名称：%1").arg(root.modelData?.displayName ?? "")
                color: "#666666"
            }

            FluText {
                text: qsTr("镜像版本：%1").arg(root.modelData?.image ?? "")
                color: "#666666"
            }

            FluText {
                text: qsTr("Android版本：Android %1").arg(root.modelData?.aospVersion ?? "")
                color: "#666666"
            }

            FluText {
                text: qsTr("选择镜像");
                font.bold: true
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
                        
                        // 根据 Android 版本更新品牌和机型列表（只显示匹配该版本的品牌）
                        updateBrandModelByAndroidVersion(v)
                    } else {
                        // 如果没有选择镜像，显示所有品牌
                        updateBrandModelFromTemplate()
                    }
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
                            root.currentDeviceBrand = brandComboBox.currentText
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
                        root.currentDeviceModel = modelComboBox.currentText
                    }
                }
            }

            // ColumnLayout{

            //     FluText {
            //         text: qsTr("分辨率");
            //         font.bold: true
            //     }

            //     FluComboBox {
            //         id: resolutionComboBox
            //         Layout.fillWidth: true
            //         model: root.resolutionModel
            //     }
            // }

            // RowLayout{
            //     FluText { text: qsTr("DNS类型"); font.bold: true }
            //     FluComboBox {
            //         id: dnsTypeComboBox
            //         Layout.fillWidth: true
            //         model: root.dnsTypeModel
            //         onCurrentIndexChanged: {
            //             updateDnsInput(currentIndex)
            //         }
            //     }

            //     Item{
            //         Layout.preferredWidth: 20
            //     }

            //     FluText { text: qsTr("DNS地址"); font.bold: true }
            //     FluTextBox {
            //         id: dnsInput
            //         Layout.fillWidth: true
            //         placeholderText: qsTr("请输入DNS地址")
            //     }
            // }

            // RowLayout{

            //     FluText {
            //         id: textName
            //         text: phoneCountSpinBox.value > 1 ? qsTr("云机名称前缀") : qsTr("云机名称");
            //         font.bold: true
            //     }
            //     FluTextBox {
            //         id: nameInput
            //         Layout.fillWidth: true
            //         text: "vmos"
            //         placeholderText: qsTr("请输入云机名称")
            //         maximumLength: 11
            //     }
            // }


            // ColumnLayout{

            //     FluText {
            //         text: qsTr("云机数量");
            //         font.bold: true
            //     }

            //     RowLayout {
            //         spacing: 20

            //         FluSpinBox{
            //             id: phoneCountSpinBox
            //             Layout.alignment: Qt.AlignLeft
            //             editable: true
            //             from: root.remainingPhones >= 1 ? 1 : 0
            //             to: root.remainingPhones
            //             value: root.phoneCount
            //         }

            //         FluText{
            //             text: qsTr("剩余可创建云机数: %1").arg(root.remainingPhones)
            //             color: "#999"
            //         }
            //     }

            //     FluText{
            //         text: phoneCountSpinBox.value > 1 ? qsTr("将按前缀自动编号生成%1个云机：").arg(phoneCountSpinBox.value) :  qsTr("将创建%1台云机：").arg(phoneCountSpinBox.value)
            //     }

            //     Flow {
            //         Layout.fillWidth: true
            //         spacing: 10
            //         layoutDirection: Qt.LeftToRight

            //         Repeater{
            //             model: phoneCountSpinBox.value

            //             delegate: FluText{
            //                 font.pixelSize: 12
            //                 text: nameInput.text + (phoneCountSpinBox.value > 1 ? `-${(index + 1).toString().padStart(3, '0')}` : "")
            //             }
            //         }
            //     }
            // }

            Rectangle{
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                color: "#FEF8F3"

                RowLayout{
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.topMargin: 6

                    ColumnLayout{
                        Layout.preferredWidth: 70
                        Layout.fillHeight: true

                        RowLayout{
                            FluIcon {
                                Layout.alignment: Qt.AlignTop
                                iconSource: FluentIcons.Info
                                iconSize: 14
                                color: "#E6A23C"
                            }
                            FluText {
                                Layout.alignment: Qt.AlignTop
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                                text: qsTr("注意事项: ")
                            }
                        }

                        Item{
                            Layout.fillHeight: true
                        }
                    }
                    ColumnLayout{
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        FluText {
                            Layout.fillWidth: true
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            text: qsTr("1、升级到相同 Android 版本时，将保留现有数据。")
                        }

                        FluText {
                            Layout.fillWidth: true
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            color: "red"
                            text: qsTr("2、升级到不同 Android 版本时，将清除所有数据。")
                        }

                        Item{
                            Layout.fillHeight: true
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
                enabled: root.phoneCount > 0
                onClicked: {
                    if (imageComboBox.currentIndex < 0) {
                        console.log("No image selected.")
                        return;
                    }

                    btnOk.enabled = false

                    var item = localImagesModel.get(imageComboBox.currentIndex);
                    var fileName = item.fileName;
                    var imageName = item.name; // 镜像版本
                    var path = item.path;

                    // 使用镜像版本与主机已存在的镜像列表比较
                    var isDownloaded = root.downloadedImages.indexOf(imageName) !== -1;

                    // 解析 Android 版本，选择对应 ADI 模板
                    var androidVersion = getAndroidVersionForImage(imageName, fileName)
                    var defaultTpl = findDefaultTemplateByVersion(androidVersion)
                    var adiName = defaultTpl ? defaultTpl.name : ""
                    var adiPass = ""  // 初始化密码
                    var needUploadAdi = false
                    var adiPath = ""
                    
                    // 如果选择了指定机型，优先使用选择的品牌和机型
                    if (typeof brandComboBox !== 'undefined' && typeof modelComboBox !== 'undefined' && 
                        brandComboBox.currentText && modelComboBox.currentText) {
                        var selectedBrand = brandComboBox.currentText;
                        var selectedModel = modelComboBox.currentText;
                        // 从模板获取真实的 ADI 文件名和密码
                        var adiItem = getAdiItem(androidVersion, selectedBrand, selectedModel)
                        adiName = adiItem.name
                        adiPass = adiItem.pwd
                        console.log("[升级云机] 指定机型:", selectedBrand, selectedModel, "adiName=", adiName, "adiPass=", adiPass ? "***" : "")
                        if (!isAdiFileExists(adiName)) {
                            needUploadAdi = true;
                            adiPath = adiName
                            // 若模板仅返回文件名，拼接到可执行目录/adi
                            if (adiPath && adiPath.indexOf('/') === -1 && adiPath.indexOf('\\') === -1) {
                                adiPath = FluTools.getApplicationDirPath() + "/adi/" + adiPath
                            }
                            console.log("[升级云机] 主机不存在该ADI, 将上传:", adiPath)
                            if (!adiPath || adiPath === "") {
                                showError(qsTr("找不到对应的 ADI 文件路径"), 3000);
                                btnOk.enabled = true;
                                return;
                            }
                        } else {
                            console.log("[升级云机] 主机已存在该ADI, 跳过上传:", adiName)
                        }
                    } else if (defaultTpl && adiName) {
                        // 从默认模板获取密码
                        adiPass = defaultTpl.pwd
                        needUploadAdi = root.downloadedAdiList.indexOf(adiName) === -1
                        if (needUploadAdi) {
                            adiPath = defaultTpl.filePath || (FluTools.getApplicationDirPath() + "/adi/" + adiName)
                            if (adiPath.indexOf('/') === -1 && adiPath.indexOf('\\') === -1) {
                                adiPath = FluTools.getApplicationDirPath() + "/adi/" + adiName
                            }
                        }
                        console.log("[升级云机] 使用默认模板: adiName=", adiName, "adiPass=", adiPass ? "***" : "")
                    }

                    // 如果是主机镜像（没有本地路径），直接升级镜像（必要时先上传 ADI）
                    if (!path || path === "") {
                        if (needUploadAdi) {
                            root.isChaining = true
                            root.createDeviceParams = {
                                "hostIp": root.modelData.hostIp,
                                "dbId": root.modelData?.dbId,
                                "name": root.modelData?.name, // 向后兼容
                                "repoName": imageName,
                                "adiName": adiName,
                                "adiPass": adiPass || ""
                            }
                            console.log("[升级云机] 需先上传ADI:", adiPath, "adiName=", adiName)
                            reqImportAdi(root.modelData.hostIp, adiPath)
                        } else {
                            console.log("[升级云机] 直接升级(主机镜像)", "repo=", imageName, "adiName=", adiName)
                            reqUpgradDeviceImage(root.modelData?.hostIp, root.modelData?.dbId, imageName, adiName, adiPass || "");
                        }
                        btnOk.enabled = true
                        return;
                    }

                    if (isDownloaded) {
                        if (needUploadAdi) {
                            root.isChaining = true
                            root.createDeviceParams = {
                                "hostIp": root.modelData.hostIp,
                                "dbId": root.modelData?.dbId,
                                "name": root.modelData?.name, // 向后兼容
                                "repoName": imageName,
                                "adiName": adiName,
                                "adiPass": adiPass || ""
                            }
                            console.log("[升级云机] 镜像已存在, 需先上传ADI:", adiPath, "adiName=", adiName)
                            reqImportAdi(root.modelData.hostIp, adiPath)
                        } else {
                            console.log("[升级云机] 镜像已存在, 直接升级", "repo=", imageName, "adiName=", adiName)
                            reqUpgradDeviceImage(root.modelData?.hostIp, root.modelData?.dbId, imageName, adiName, adiPass || "");
                        }
                    } else {
                        root.isChaining = true
                        root.createDeviceParams = {
                            "hostIp": root.modelData.hostIp,
                            "dbId": root.modelData?.dbId,
                            "name": root.modelData?.name, // 向后兼容
                            "repoName": imageName,
                            "needUploadAdi": needUploadAdi,
                            "adiPath": adiPath,
                            "adiName": adiName,
                            "adiPass": adiPass || ""
                        }
                        console.log("[升级云机] 镜像需上传, needUploadAdi=", needUploadAdi, "adiPath=", adiPath, "adiName=", adiName)
                        reqUploadImage(root.modelData.hostIp, path);
                    }
                    btnOk.enabled = true
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
                        // 优先显示云机当前镜像版本
                        var currentImage = root.modelData?.image || ""
                        var foundIndex = -1
                        
                        // 查找匹配当前镜像版本的项
                        if (currentImage) {
                            // 先尝试精确匹配镜像版本（name）
                            for (var n = 0; n < localImagesModel.count; n++) {
                                var item = localImagesModel.get(n)
                                if (item.name === currentImage) {
                                    foundIndex = n
                                    break
                                }
                            }
                            
                            // 如果精确匹配失败，尝试匹配文件名
                            if (foundIndex === -1) {
                                for (var p = 0; p < localImagesModel.count; p++) {
                                    var item2 = localImagesModel.get(p)
                                    if (item2.fileName === currentImage || item2.fileName.indexOf(currentImage) !== -1) {
                                        foundIndex = p
                                        break
                                    }
                                }
                            }
                        }
                        
                        // 如果找到匹配项，选中它；否则选中第一个
                        imageComboBox.currentIndex = foundIndex >= 0 ? foundIndex : 0
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

    NetworkCallable {
        id: upgradDeviceImage
        onStart: {
            showLoading(qsTr("正在升级云机镜像..."))
        }
        onFinish: {
            hideLoading()
            root.isChaining = false
        }

        onError:
            (status, errorString, result, userData) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
                root.upgradeResult(false)
                root.close()
            }
        onSuccess:
            (result, userData) => {
                try {
                    const res = JSON.parse(result)
                    if(res.code == 200){
                        // 创建成功
                        root.upgradeResult(res.data.host_ip, res.data.list)
                        root.close()
                    }else if(res.code == 202){
                        showError("正在执行镜像更新，请稍后再试", 3000)
                    }
                    else{
                        showError(res.msg, 3000)
                    }
                } catch (e) {
                    console.warn("无法将行解析为JSON:", result, e)
                }
            }
    }

    // 升级云机镜像
    function reqUpgradDeviceImage(ip, dbId, image_url, adiName, adiPass){
        console.log("[升级云机] 请求升级", "ip=", ip, "dbId=", dbId, "repo=", image_url, "adiName=", adiName, "adiPass=", adiPass ? "***" : "")
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/upgrade_image")
        .add("repository", image_url)
        .addList("db_ids", [dbId])
        .add("adiName", adiName || "")
        .add("adiPass", adiPass || "")
        .setUserData(ip)
        .bind(root)
        .setTimeout(600000)
        .go(upgradDeviceImage)
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
                root.upgradeResult(false)
                root.close()
            }
        onSuccess:
            (result, userData) => {
                // 镜像上传完毕后，如需要也上传 ADI，然后再执行升级
                if (root.createDeviceParams && root.isChaining) {
                    if (root.createDeviceParams.needUploadAdi && root.createDeviceParams.adiPath) {
                        reqImportAdi(root.createDeviceParams.hostIp, root.createDeviceParams.adiPath)
                    } else {
                        reqUpgradDeviceImage(root.createDeviceParams.hostIp,
                                             root.createDeviceParams.dbId || root.createDeviceParams.name,
                                             root.createDeviceParams.repoName,
                                             root.createDeviceParams.adiName || "",
                                             root.createDeviceParams.adiPass || "")
                        root.createDeviceParams = null
                        root.isChaining = false
                    }
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
        Network.postForm(`http://${ip}:18182/v1` + "/import_image")
        .setRetry(1)
        .addFile("file", path)
        .bind(root)
        .go(uploadImage)
    }

    // 解析本地镜像的 Android 版本，用于匹配 ADI 模板
    function normalizeAndroidVersion(v){
        var s = (v === undefined || v === null) ? "" : ("" + v)
        var m = s.match(/(\d{1,2})/)
        return m && m[1] ? m[1] : ""
    }

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
        var source = (imageName || "") + "_" + (fileName || "")
        var m = source.match(/android\s*(\d{1,2})/i)
        if (m && m[1]) return m[1]
        return ""
    }

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

    // 判断主机是否已存在指定ADI文件
    function isAdiFileExists(adiName) {
        if (!adiName) return false
        return root.downloadedAdiList.indexOf(adiName) !== -1
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
                root.brandModel = newBrandModel;
                root.brandModelData = newModelData;
                
                // 更新品牌下拉框
                if (typeof brandComboBox !== 'undefined') {
                    brandComboBox.model = newBrandModel;
                    console.log("Updated brand model from template:", newBrandModel);
                    console.log("Updated model data from template:", newModelData);
                    
                    // 如果已有获取到的品牌和机型，优先选中；否则选择第一个
                    if (root.currentDeviceBrand && root.currentDeviceModel) {
                        selectBrandAndModel(root.currentDeviceBrand, root.currentDeviceModel)
                    } else if (brandComboBox.currentIndex < 0) {
                        brandComboBox.currentIndex = 0
                    }
                }
            }
        } catch (e) {
            console.error("Error updating brand model from template:", e);
        }
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
                    console.log("Updated brand model by Android version:", androidVersion, "brands:", newBrandModel);
                    
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
                    } else if (brandComboBox.currentIndex < 0) {
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
                console.log("No brands found for Android version:", androidVersion);
            }
        } catch (e) {
            console.error("Error updating brand model by Android version:", e);
        }
    }

    // 主机 ADI 列表
    NetworkCallable {
        id: adiList
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result);
                    if(res.code === 200 && res.data){
                        if (Array.isArray(res.data.list)) {
                            root.downloadedAdiList = res.data.list.map(function(item){
                                return item.adiName
                            })
                        }
                        else if (Array.isArray(res.data.files)) {
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

    function reqAdiList(ip){
        if (!ip) return;
        Network.get(`http://${ip}:18182/v1` + "/get_adi_list")
        .setUserData(ip)
        .bind(root)
        .go(adiList)
    }

    // 导入 ADI（沿用创建弹窗相同接口）
    NetworkCallable {
        id: importAdi
        onStart: { showLoading(qsTr("ADI 导入中...")) }
        onFinish: { hideLoading() }
        onError:
            (status, errorString, result, userData) => {
                hideLoading()
                showError(errorString)
            }
        onSuccess:
            (result, userData) => {
                // 成功后直接执行升级
                if (root.createDeviceParams) {
                    reqUpgradDeviceImage(root.createDeviceParams.hostIp,
                                         root.createDeviceParams.dbId || root.createDeviceParams.name,
                                         root.createDeviceParams.repoName,
                                         root.createDeviceParams.adiName || "",
                                         root.createDeviceParams.adiPass || "")
                    root.createDeviceParams = null
                    root.isChaining = false
                }
            }
    }

    function reqImportAdi(ip, adiPath){
        Network.postForm(`http://${ip}:18182/v1` + "/import_adi")
        .setRetry(1)
        .addFile("adiZip", adiPath)
        .setUserData(ip)
        .bind(root)
        .go(importAdi)
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
                            selectBrandAndModel(root.currentDeviceBrand, root.currentDeviceModel)
                        }
                    } else {
                        console.error("[云机详情] 请求品牌机型数据响应失败：", res.msg)
                    }
                } catch (e) {
                    console.error("[云机详情] 解析品牌机型数据失败:", e)
                }
            }
    }

    // 选择指定的品牌和机型
    function selectBrandAndModel(brand, model) {
        if (!brand || !model) return
        
        try {
            // 查找品牌在列表中的索引
            var brandIndex = root.brandModel.indexOf(brand)
            if (brandIndex >= 0 && typeof brandComboBox !== 'undefined') {
                if (brandComboBox.currentIndex === brandIndex) {
                    brandComboBox.currentIndex = -1
                }

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
                            console.log("[升级云机] 已选中品牌和机型:", brand, model)
                        } else {
                            console.log("[升级云机] 未找到机型:", model, "在品牌", brand, "的机型列表中")
                        }
                    }
                })
            } else {
                console.log("[升级云机] 未找到品牌:", brand, "在品牌列表中")
            }
        } catch (e) {
            console.error("[升级云机] 选择品牌和机型失败:", e)
        }
    }

    // 调用 shell 接口获取云机品牌和机型
    function reqGetDeviceBrandModel(hostIp, dbId) {
        if (!hostIp || !dbId) {
            console.warn("[升级云机] 获取品牌机型: hostIp 或 dbId 为空")
            return
        }

        Network.postJson(`http://${hostIp}:18182/container_api/v1/get_db`)
        .add("name", dbId)
        .add("fields", "brand,model_name")
        .bind(root)
        .go(getDBBrandModel)
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
}
