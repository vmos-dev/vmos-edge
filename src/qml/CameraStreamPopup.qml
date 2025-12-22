import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import FluentUI
import Utils

FluPopup {
    id: root
    implicitWidth: 600
    implicitHeight: 550
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    property var cameraDeviceScanner: null
    property var cameraStreamManager: null
    
    // 分辨率选项
    property var resolutionOptions: [
        {width: 640, height: 480, label: "640x480"},
        {width: 1280, height: 720, label: "1280x720"},
        {width: 1920, height: 1080, label: "1920x1080"}
    ]
    
    // 帧率选项
    property var fpsOptions: [15, 20, 24, 30, 60]
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15
        
        // 标题
        Text {
            Layout.fillWidth: true
            text: qsTr("摄像头推流设置")
            font.pixelSize: 18
            font.bold: true
        }
        
        // 摄像头选择区域
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                text: qsTr("选择摄像头:")
                font.pixelSize: 14
            }
            
            ComboBox {
                id: cameraComboBox
                Layout.fillWidth: true
                model: cameraDeviceScanner
                textRole: "deviceName"
                enabled: !cameraStreamManager.isStreaming
                
                onActivated: {
                    console.log("Selected camera:", currentIndex)
                }
            }
            
            RowLayout {
                Layout.fillWidth: true
                
                Button {
                    text: qsTr("刷新设备列表")
                    enabled: !cameraStreamManager.isStreaming
                    onClicked: {
                        if (cameraDeviceScanner) {
                            cameraDeviceScanner.scanDevices()
                        }
                    }
                }
                
                Item {
                    Layout.fillWidth: true
                }
            }
        }
        
        // 推流参数设置区域
        GroupBox {
            Layout.fillWidth: true
            title: qsTr("推流参数")
            
            GridLayout {
                anchors.fill: parent
                columns: 2
                columnSpacing: 10
                rowSpacing: 10
                
                Text {
                    text: qsTr("分辨率:")
                    font.pixelSize: 14
                }
                
                ComboBox {
                    id: resolutionComboBox
                    Layout.fillWidth: true
                    model: resolutionOptions
                    textRole: "label"
                    currentIndex: 1  // 默认1280x720
                    enabled: !cameraStreamManager.isStreaming
                }
                
                Text {
                    text: qsTr("帧率:")
                    font.pixelSize: 14
                }
                
                ComboBox {
                    id: fpsComboBox
                    Layout.fillWidth: true
                    model: fpsOptions
                    currentIndex: 3  // 默认30fps
                    enabled: !cameraStreamManager.isStreaming
                }
                
                Text {
                    text: qsTr("流名称:")
                    font.pixelSize: 14
                }
                
                TextField {
                    id: streamNameField
                    Layout.fillWidth: true
                    text: "camera"
                    enabled: !cameraStreamManager.isStreaming
                    placeholderText: qsTr("输入流名称")
                }
            }
        }
        
        // RTSP URL显示区域
        GroupBox {
            Layout.fillWidth: true
            title: qsTr("RTSP地址")
            
            ColumnLayout {
                anchors.fill: parent
                spacing: 5
                
                TextField {
                    id: rtspUrlField
                    Layout.fillWidth: true
                    readOnly: true
                    text: cameraStreamManager ? cameraStreamManager.rtspUrl : ""
                    placeholderText: qsTr("推流开始后显示RTSP地址")
                }
                
                Button {
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("复制地址")
                    enabled: rtspUrlField.text !== ""
                    onClicked: {
                        if (rtspUrlField.text) {
                            // 复制到剪贴板
                            // 注意：需要确保在main.cpp中注册了剪贴板相关的功能
                            console.log("Copy RTSP URL:", rtspUrlField.text)
                        }
                    }
                }
            }
        }
        
        // 状态显示
        Rectangle {
            Layout.fillWidth: true
            height: 40
            color: cameraStreamManager && cameraStreamManager.isStreaming ? "#E8F5E9" : "#F5F5F5"
            border.color: cameraStreamManager && cameraStreamManager.isStreaming ? "#4CAF50" : "#D9D9D9"
            border.width: 1
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: cameraStreamManager && cameraStreamManager.isStreaming ? "#4CAF50" : "#9E9E9E"
                }
                
                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!cameraStreamManager) {
                            return qsTr("未初始化")
                        }
                        if (cameraStreamManager.isStreaming) {
                            return qsTr("推流中...")
                        }
                        if (cameraStreamManager.errorMessage) {
                            return qsTr("错误: ") + cameraStreamManager.errorMessage
                        }
                        return qsTr("已停止")
                    }
                    color: cameraStreamManager && cameraStreamManager.isStreaming ? "#2E7D32" : "#616161"
                    font.pixelSize: 13
                }
            }
        }
        
        // 控制按钮区域
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            
            Button {
                id: startStopButton
                Layout.fillWidth: true
                text: cameraStreamManager && cameraStreamManager.isStreaming ? qsTr("停止推流") : qsTr("开始推流")
                enabled: cameraComboBox.currentIndex >= 0 && cameraDeviceScanner && cameraDeviceScanner.count > 0
                
                onClicked: {
                    if (!cameraStreamManager || !cameraDeviceScanner) {
                        return
                    }
                    
                    if (cameraStreamManager.isStreaming) {
                        cameraStreamManager.stopStreaming()
                    } else {
                        var device = cameraDeviceScanner.getDevice(cameraComboBox.currentIndex)
                        if (!device || !device.deviceId) {
                            console.error("Invalid device selected")
                            return
                        }
                        
                        var resolution = resolutionOptions[resolutionComboBox.currentIndex]
                        var fps = fpsOptions[fpsComboBox.currentIndex]
                        var streamName = streamNameField.text.trim() || "camera"
                        
                        console.log("Starting stream:", {
                            deviceId: device.deviceId,
                            streamName: streamName,
                            width: resolution.width,
                            height: resolution.height,
                            fps: fps
                        })
                        
                        cameraStreamManager.startStreaming(
                            device.deviceId,
                            streamName,
                            resolution.width,
                            resolution.height,
                            fps
                        )
                    }
                }
            }
            
            Button {
                text: qsTr("关闭")
                onClicked: root.close()
            }
        }
    }
    
    // 监听推流状态变化
    Connections {
        target: cameraStreamManager
        function onStreamingStarted() {
            console.log("Streaming started, RTSP URL:", cameraStreamManager.rtspUrl)
        }
        function onStreamingStopped() {
            console.log("Streaming stopped")
        }
        function onErrorOccurred(error) {
            console.error("Streaming error:", error)
        }
    }
    
    // 监听扫描完成
    Connections {
        target: cameraDeviceScanner
        function onScanFinished() {
            console.log("Camera scan finished, found", cameraDeviceScanner.count, "devices")
            if (cameraDeviceScanner.count > 0 && cameraComboBox.currentIndex < 0) {
                cameraComboBox.currentIndex = 0
            }
        }
        function onScanError(error) {
            console.error("Camera scan error:", error)
        }
    }
    
    // 弹窗打开时自动扫描设备
    onOpened: {
        if (cameraDeviceScanner) {
            cameraDeviceScanner.scanDevices()
        }
    }
}

