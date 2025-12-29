import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Qt.labs.platform
import Utils


FluPopup {
    id: root
    implicitWidth: 600
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string filePath: ""
    property string destinationPath: ""
    property string importState: "idle" // idle, selected, extracting, validating, copying, success, failed
    property string failedReason: "" // 失败原因
    property string validationStep: "" // 校验步骤
    property int validationProgress: 0 // 校验进度
    property string extractedImageName: "" // 提取的镜像名称
    property string extractedAndroidVersion: "" // 提取的Android版本
    readonly property int maxFileSizeGB: 5 // 最大文件大小（GB）
    readonly property real maxFileSizeBytes: root.maxFileSizeGB * 1024 * 1024 * 1024 // 最大文件大小（字节）

    onFilePathChanged: {
        importState = filePath ? "selected" : "idle"
        if (filePath) {
            // 从文件名中提取临时镜像名称（仅作为初始显示）
            var fullFileName = filePath.substring(filePath.lastIndexOf('/') + 1);
            var fileName = fullFileName;
            if (fileName.endsWith('.tar.zst')) {
                fileName = fileName.substring(0, fileName.length - 8);
            } else {
                var lastDotIndex = fileName.lastIndexOf('.');
                if (lastDotIndex !== -1) {
                    fileName = fileName.substring(0, lastDotIndex);
                }
            }
            // 设置临时显示，等待从meta文件中提取真实名称
            imageNameInput.text = fileName;
        } else {
            root.extractedImageName = "";
            root.extractedAndroidVersion = "";
            root.validationStep = "";
            root.validationProgress = 0;
            imageNameInput.text = "";
        }
    }

    onAboutToShow: {
        root.filePath = ""
        root.destinationPath = ""
        root.failedReason = ""
        root.validationStep = ""
        root.validationProgress = 0
        root.extractedImageName = ""
        root.extractedAndroidVersion = ""
        imageNameInput.text = ""
        importState = "idle"
    }

    Timer {
        id: closeTimer
        interval: 2000
        onTriggered: root.close()
    }

    Connections {
        target: fileCopyManager

        function onCopySucceeded() {
            console.log("ImportImagePopup: Copy succeeded. Adding to model.");
            hideLoading()

            var name = root.extractedImageName; // 镜像版本（从vcloud.meta中提取）
            var path = root.destinationPath;
            var fileName = imageNameInput.text.trim(); // 使用用户修改后的镜像文件名
            var version = root.extractedAndroidVersion;
            var fileSize = formatBytes(fileCopyManager.totalSize);

            if (!name || !path || !fileName || !version) {
                console.log("Cannot add to model, some data is missing.");
                importState = "failed"
                return;
            }

            imagesModel.addItem(path, name, fileName, version, fileSize);
            imagesModel.saveConfig();
            importState = "success"
            closeTimer.start()
        }

        function onCopyFailed(reason) {
            console.log("ImportImagePopup: Copy failed: " + reason);
            hideLoading()
            importState = "failed"
        }

        function onValidationProgress(step, progress) {
            console.log("Validation progress:", step, progress + "%");
            root.validationStep = step
            root.validationProgress = progress
        }

        function onValidationSucceeded(imageName, tarFilePath) {
            console.log("Image validation succeeded:", imageName, "Tar file:", tarFilePath);
            hideLoading()
            // 校验成功后开始复制镜像 tar 文件
            importState = "copying"
            // 使用验证成功后的tar文件路径作为源文件，目标路径为镜像存放目录
            root.destinationPath = SettingsHelper.get("imagesPath", "") + "/" + imageName + ".tar.gz"
            
            // 从tarFilePath中提取临时目录路径（去掉最后的文件名）
            var tempDir = tarFilePath.substring(0, tarFilePath.lastIndexOf("/"))
            tempDir = tempDir.substring(0, tempDir.lastIndexOf("/"))  // 去掉process子目录
            console.log("Extracted temp directory:", tempDir)
            
            showLoading("导入中...")
            fileCopyManager.startCopy(tarFilePath, root.destinationPath, tempDir)
        }

        function onValidationFailed(reason) {
            console.log("Image validation failed:", reason);
            hideLoading()
            root.failedReason = reason
            importState = "failed"
        }

        function onImageInfoExtracted(success, imageName, androidVersion, errorMessage) {
            console.log("Image info extracted:", success, imageName, androidVersion, errorMessage);
            
            if (success) {
                root.extractedImageName = imageName
                root.extractedAndroidVersion = androidVersion
                
                // 更新输入框显示从meta文件中提取的真实镜像名称
                // imageNameInput.text = imageName
                
                // 检查镜像版本是否已存在
                if (checkImageVersionExists(imageName, androidVersion)) {
                    hideLoading()
                    root.failedReason = qsTr("镜像版本已存在")
                    importState = "failed"
                    return
                }
                
                // 没有重复，继续验证过程
                console.log("No duplicate found, continuing with validation...")
                showLoading(qsTr("验证镜像中..."))
                fileCopyManager.startImageValidation(root.filePath)
            } else {
                hideLoading()
                root.failedReason = errorMessage || qsTr("镜像信息提取失败")
                importState = "failed"
            }
        }

    }

    function formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    function checkFileSize(filePath) {
        // 使用 FileCopyManager 来获取文件大小
        // 这里我们假设 FileCopyManager 有获取文件大小的方法
        // 如果没有，我们需要在 C++ 端添加这个方法
        try {
            // 临时方案：使用 FileCopyManager 的 totalSize 属性
            // 实际实现需要在 C++ 端添加获取文件大小的方法
            console.log("Checking file size for:", filePath)
            
            // 这里应该调用 C++ 方法来获取文件大小
            // 暂时返回 true，实际项目中需要实现真正的文件大小检查
            return true
        } catch (error) {
            console.log("File size check error:", error)
            return false
        }
    }

    function checkImageVersionExists(imageName, androidVersion) {
        // 检查镜像版本是否已存在于模型中
        try {
            console.log("Checking if image version exists:", imageName, androidVersion)
            
            // 遍历imagesModel检查是否存在相同的镜像版本
            for (var i = 0; i < imagesModel.rowCount(); i++) {
                var index = imagesModel.index(i, 0);
                var existingName = imagesModel.data(index, ImagesModel.NameRole).toString(); // 镜像版本
                var existingVersion = imagesModel.data(index, ImagesModel.VersionRole).toString(); // Android版本
                
                console.log("Comparing with existing:", existingName, existingVersion)
                
                // 检查镜像版本是否相同
                if (existingName === imageName) {
                    console.log("Found duplicate image version:", imageName)
                    return true
                }
            }
            
            console.log("No duplicate image version found")
            return false
        } catch (error) {
            console.log("Image version check error:", error)
            return false
        }
    }

    FileDialog {
        id: fileDialog
        title: qsTr("选择镜像文件")
        fileMode: FileDialog.OpenFile
        nameFilters: [ "Image files (*.tar.zst)" ]
        onAccepted: {
            root.filePath = FluTools.toLocalPath(fileDialog.file)
            console.log("You chose: " + root.filePath)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.leftMargin: 20
            Layout.rightMargin: 10

            FluText {
                text: qsTr("导入镜像")
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
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.bottomMargin: 20
            spacing: 20

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                FluText {
                    text: qsTr("选择镜像文件")
                    font.pixelSize: 14
                    font.bold: false
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    color: importState === 'idle' ? "#F7FAFF" : "#FFFFFF"
                    border.color: "#409EFF"
                    border.width: 1
                    radius: 4

                    StackLayout {
                        anchors.fill: parent
                        currentIndex: {
                            if (importState === 'idle') return 0;
                            if (importState === 'selected') return 1;
                            if (importState === 'validating') return 2;
                            if (importState === 'copying') return 3;
                            if (importState === 'success') return 4;
                            if (importState === 'failed') return 5;
                            return 0;
                        }

                        // Idle state (0)
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12
                                FluIcon {
                                    iconSource: FluentIcons.CloudDownload
                                    iconSize: 48
                                    color: "#409EFF"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 4
                                    FluText {
                                        text: qsTr("拖放文件到此处, 或")
                                        color: "#606266"
                                    }
                                    TextButtonEx {
                                        text: qsTr("浏览文件")
                                        textColor: "#409EFF"
                                        onClicked: fileDialog.open()
                                    }
                                }
                                FluText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: qsTr("仅支持导入官方发布的 .tar.zst 格式文件，文件大小不得超过 %1GB").arg(root.maxFileSizeGB)
                                    color: "#909399"
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // Selected state (1)
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12
                                FluIcon {
                                    iconSource: FluentIcons.Page
                                    iconSize: 48
                                    color: "#409EFF"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                FluText {
                                    text: root.filePath.substring(root.filePath.lastIndexOf('/') + 1)
                                    font.pixelSize: 16
                                    color: "#303133"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                TextButtonEx {
                                    text: qsTr("删除文件")
                                    textColor: "#F56C6C"
                                    Layout.alignment: Qt.AlignHCenter
                                    onClicked: root.filePath = ""
                                }
                            }
                        }

                        // Validating state (2)
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12

                                FluProgressRing {
                                    Layout.alignment: Qt.AlignHCenter
                                    indeterminate: false
                                    progressVisible: true
                                    from: 0
                                    to: 100
                                    value: root.validationProgress
                                }

                                FluText {
                                    text: root.validationStep || qsTr("校验镜像中...")
                                    font.pixelSize: 14
                                    color: "#606266"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        // Copying state (3)
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12

                                FluProgressRing {
                                    Layout.alignment: Qt.AlignHCenter
                                    indeterminate: false
                                    progressVisible: true
                                    from: 0
                                    to: 100
                                    value: fileCopyManager.totalSize > 0 ? (fileCopyManager.copiedSize / fileCopyManager.totalSize) * 100 : 0
                                }

                                FluText {
                                    text: qsTr("导入中...")
                                    font.pixelSize: 14
                                    color: "#606266"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        // Success state (4)
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12
                                FluIcon {
                                    iconSource: FluentIcons.Completed
                                    iconSize: 64
                                    color: "#409EFF"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                FluText {
                                    text: qsTr("导入成功!")
                                    font.pixelSize: 16
                                    color: "#303133"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        // Failed state (5)
                        Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12
                                FluIcon {
                                    iconSource: FluentIcons.Error
                                    iconSize: 64
                                    color: "#F56C6C"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                FluText {
                                    text: root.failedReason || qsTr("文件格式不支持!")
                                    font.pixelSize: 16
                                    color: "#303133"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                FluText {
                                    text: root.failedReason ? qsTr("请选择符合要求的文件") : qsTr("请拖拽 .tar.zst 格式的文件")
                                    font.pixelSize: 12
                                    color: "#909399"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                TextButtonEx {
                                    text: qsTr("重新选择文件")
                                    textColor: "#409EFF"
                                    Layout.alignment: Qt.AlignHCenter
                                    onClicked: {
                                        root.filePath = ""
                                        root.failedReason = ""
                                        root.validationStep = ""
                                        root.validationProgress = 0
                                        root.extractedImageName = ""
                                        root.extractedAndroidVersion = ""
                                        imageNameInput.text = ""
                                        importState = "idle"
                                    }
                                }
                            }
                        }
                    }

                    DropArea {
                        anchors.fill: parent
                        enabled: importState === 'idle' || importState === 'failed'
                        onDropped: (drop) => {
                            if (drop.hasUrls && drop.urls.length > 0) {
                                var fileUrl = drop.urls[0]
                                var localPath = FluTools.toLocalPath(fileUrl)
                                if (localPath.endsWith('.tar.zst')) {
                                    console.log("Dropped file:", fileUrl)
                                    root.filePath = localPath
                                    root.failedReason = "" // 清除之前的失败原因
                                    root.validationStep = "" // 重置校验步骤
                                    root.validationProgress = 0 // 重置校验进度
                                    root.extractedImageName = "" // 重置提取的镜像名称
                                    root.extractedAndroidVersion = "" // 重置提取的Android版本
                                    importState = "selected" // 重置状态为已选择
                                } else {
                                    console.log("Invalid file type dropped:", fileUrl)
                                    root.failedReason = qsTr("仅支持导入官方发布的 .tar.zst 格式文件，文件大小不得超过 %1G").arg(root.maxFileSizeGB)
                                    importState = "failed"
                                }
                            }
                        }
                    }
                }
            }

            Rectangle{
                Layout.preferredHeight: 22
                Layout.fillWidth: true
                color: "#FEF8F3"
                radius: 4
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    FluIcon {
                        iconSource: FluentIcons.Info
                        iconSize: 14
                        color: "#E6A23C"
                    }
                    FluText {
                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        text: qsTr("温馨提示: 请确认上传文件为<a href=\"#user_agreement_link\" style=\"text-decoration: none;color: #E6A23C;\">vmos edge官方</a>发布下载镜像, 导入过程需要进行完整性及签名校验, 请耐心等待!")
                        onLinkActivated: (link) => {}
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                enabled: importState !== 'copying' && importState !== 'success'

                FluText { 
                    text: qsTr("镜像名称")
                    font.pixelSize: 14
                    font.bold: false
                }

                FluTextBox {
                    id: imageNameInput
                    Layout.fillWidth: true
                    maximumLength: 50
                    placeholderText: qsTr("输入镜像名称")
                    enabled: importState === 'selected' || importState === 'failed'
                }
            }

            Item { Layout.fillHeight: true }

            FluFilledButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                text: {
                    if (importState === 'validating') return qsTr("处理中...")
                    if (importState === 'copying') return qsTr("导入中...")
                    return qsTr("开始导入")
                }
                enabled: (importState === 'selected' || importState === 'failed') && root.filePath && imageNameInput.text.trim() !== ""
                onClicked: {
                    // 校验文件大小
                    console.log("Checking file size for:", root.filePath)
                    
                    var fileSize = fileCopyManager.getFileSize(root.filePath)
                    
                    if (fileSize === -1) {
                        root.failedReason = "无法获取文件大小，请检查文件是否存在"
                        importState = "failed"
                        return
                    }
                    console.log("============", fileSize, root.maxFileSizeBytes)
                    if (fileSize > root.maxFileSizeBytes) {
                        var fileSizeGB = (fileSize / (1024 * 1024 * 1024)).toFixed(2)
                        root.failedReason = "文件大小 " + fileSizeGB + "GB 超过" + root.maxFileSizeGB + "GB限制，无法导入"
                        importState = "failed"
                        return
                    }

                    // 镜像存储空间大小
                    var spaceSize = fileCopyManager.getAvailableSpace(SettingsHelper.get("imagesPath", ""))
                    console.log("=============space size", spaceSize)
                    if(spaceSize < root.maxFileSizeBytes){
                        var spaceSizeGB = (spaceSize / (1024 * 1024 * 1024)).toFixed(2)
                        root.failedReason = qsTr("镜像存储空间不足（当前 %1 G，最低要求 %2 G）。请设置合适的存储路径").arg(spaceSizeGB).arg(root.maxFileSizeGB)
                        importState = "failed"
                        return
                    }
                    
                    // 文件大小检查通过，先提取镜像信息检查重复
                    importState = "validating"
                    showLoading("提取镜像信息...")
                    fileCopyManager.startImageInfoExtraction(root.filePath)
                }
            }
        }
    }
}
