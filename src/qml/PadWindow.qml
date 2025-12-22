import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.platform
import FluentUI
import Utils

FluWindow {
    id: root
    width: (savedWindowWidth > 0 && savedWindowHeight > 0) ? savedWindowWidth : (initWidth + spaceWidth)
    height: (savedWindowWidth > 0 && savedWindowHeight > 0) ? savedWindowHeight : ((initWidth * aspectRatio) + spaceHeight)
    fitsAppBarWindows: true
    launchMode: FluWindowType.Standard
    useSystemAppBar: false
    autoCenter: true
    showClose: false
    showMinimize: false
    showMaximize: false
    minimumWidth: (direction === 0 ? 160 : 284) + spaceWidth
    minimumHeight: (direction === 0 ? 284 : 160) + spaceHeight -40
    title: root.argument.displayName

    // minimumHeight: (width - spaceHeight) / aspectRatio
    // maximumHeight: (width - spaceWidth) / aspectRatio

    property int initWidth: 160
    property string _fingerprint: ""
    property int direction: 0 // 0、竖屏 1、横屏
    property int lastDirection: 0
    property var client: null
    property bool isConnect: false
    property int remoteDirection: 0
    property real aspectRatio : (16.0 / 9.0)
    property int spaceWidth: 40
    property int spaceHeight: 80
    // 设备实际屏幕大小（从onScreenInfo信号获取）
    property int deviceScreenWidth: 0
    property int deviceScreenHeight: 0
    property bool isRestoringWindow: false  // 标记是否正在恢复窗口大小
    property int savedWindowWidth: 0  // 保存的窗口宽度（用于恢复时）
    property int savedWindowHeight: 0  // 保存的窗口高度（用于恢复时）
    // property bool isEventSyncMaster: groupControl.isEventSyncMaster(root.argument.padCode)
    property var videoList: []
    property var audioList: []
    property var videoFileListModel: []
    property string currentInjectFile: ""
    property real startTime: Utils.milliseconds()
    property var joystickStatus: []
    property var joystickState: ({ active: false, x: 0.0, y: 0.0, keys: [] })
    property real joystickUpdateInterval: 50 // ms
    property real lon: 0.0  // 经度
    property real lat: 0.0  // 纬度
    property string deviceLocale: "en-US"  // 语言
    property string timezone: "UTC"  // 时区
    property string country: "CN"  // 国家
    property bool wipeData: true  // 是否清理数据
    // 根据配置动态计算设备标识（已废弃，改为根据配置动态获取）
    // property string deviceAddress: `${root.argument.hostIp}:${root.argument.adb}`

    function getFileSize(size) {
        const KB = 1024;
        const MB = KB * 1024;
        const GB = MB * 1024;

        if (size < KB) {
            return `${size} B`;
        } else if (size < MB) {
            return `${(size / KB).toFixed(2)} KB`;
        } else if (size < GB) {
            return `${(size / MB).toFixed(2)} MB`;
        } else {
            return `${(size / GB).toFixed(2)} GB`;
        }
    }

    // 生成8位随机字符串（字母和数字）
    function generateRandomStreamName() {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
        let result = ''
        for (let i = 0; i < 8; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length))
        }
        return result
    }

    function getVideoFile(fileName){
        for (var i = 0; i < videoFileListModel.length; i++) {
            if (videoFileListModel[i].downloadUrl.includes(fileName)) {
                return videoFileListModel[i]
            }
        }
        return null
    }

    function mapMouseToVideo(mouseX, mouseY, viewWidth, viewHeight, aspectRatio) {
        // console.log("=== mapMouseToVideo 开始 ===")
        // console.log("输入参数: mouseX=", mouseX, "mouseY=", mouseY, "viewWidth=", viewWidth, "viewHeight=", viewHeight, "aspectRatio=", aspectRatio)
        // console.log("方向信息: direction=", direction, "(0=竖屏,1=横屏)", "remoteDirection=", remoteDirection, "(0=竖屏,1=横屏)")
        
        const isPortrait = (direction === 0 || direction === 180)
        const viewRatio = isPortrait ? (viewHeight / viewWidth) : (viewWidth / viewHeight)
        // console.log("isPortrait=", isPortrait, "viewRatio=", viewRatio)

        let contentRatio = aspectRatio
        let displayWidth, displayHeight, offsetX, offsetY

        // 根据方向确定裁剪方式
        if ((isPortrait && viewRatio > contentRatio) || (!isPortrait && viewRatio < contentRatio)) {
            // 黑边在上下
            displayWidth = viewWidth
            displayHeight = isPortrait
                    ? viewWidth * contentRatio
                    : viewWidth / contentRatio
            offsetX = 0
            offsetY = (viewHeight - displayHeight) / 2
            // console.log("黑边在上下: displayWidth=", displayWidth, "displayHeight=", displayHeight, "offsetX=", offsetX, "offsetY=", offsetY)
        } else {
            // 黑边在左右
            displayHeight = viewHeight
            displayWidth = isPortrait
                    ? viewHeight / contentRatio
                    : viewHeight * contentRatio
            offsetX = (viewWidth - displayWidth) / 2
            offsetY = 0
            // console.log("黑边在左右: displayWidth=", displayWidth, "displayHeight=", displayHeight, "offsetX=", offsetX, "offsetY=", offsetY)
        }

        // 映射坐标（去除黑边）
        let x = mouseX - offsetX
        let y = mouseY - offsetY
        // console.log("去除黑边后: x=", x, "y=", y)

        // 当本地画布方向与云机实际方向不一致时，需要旋转坐标
        // remoteDirection: 云机的实际方向（0=竖屏，1=横屏）
        // direction: 本地画布的显示方向（0=竖屏，1=横屏）
        // 当 direction !== remoteDirection 时，说明本地画布被旋转了，需要将坐标转换回云机的坐标系
        if (direction !== remoteDirection) {
            // console.log("需要旋转坐标: direction != remoteDirection")
            if(remoteDirection == 0){
                // 情况：云机竖屏，本地横屏显示
                // 需要将横屏坐标转换为竖屏坐标
                // 坐标旋转：逆时针旋转90度 (x, y) -> (height - y, x)
                // console.log("情况：云机竖屏，本地横屏显示")
                // console.log("旋转前: x=", x, "y=", y, "displayWidth=", displayWidth, "displayHeight=", displayHeight)
                const rotatedX = displayHeight - y
                const rotatedY = x
                x = rotatedX
                y = rotatedY

                // 交换宽高，因为旋转后显示区域的宽高与云机屏幕相反
                const tmp = displayWidth
                displayWidth = displayHeight
                displayHeight = tmp
                // console.log("旋转后: x=", x, "y=", y, "displayWidth=", displayWidth, "displayHeight=", displayHeight)
            }else{
                // 情况：云机横屏，本地竖屏显示
                // 需要将竖屏坐标转换为横屏坐标
                // 坐标旋转：顺时针旋转90度 (x, y) -> (y, width - x)
                // console.log("情况：云机横屏，本地竖屏显示")
                // console.log("旋转前: x=", x, "y=", y, "displayWidth=", displayWidth, "displayHeight=", displayHeight)
                const rotatedX = y
                const rotatedY = displayWidth - x
                x = rotatedX
                y = rotatedY

                // 交换宽高，因为旋转后显示区域的宽高与云机屏幕相反
                const tmp = displayWidth
                displayWidth = displayHeight
                displayHeight = tmp
                // console.log("旋转后: x=", x, "y=", y, "displayWidth=", displayWidth, "displayHeight=", displayHeight)
            }
        } else {
            // console.log("不需要旋转坐标: direction == remoteDirection")
        }
        // 当 direction === remoteDirection 时，本地和云机方向一致，不需要旋转坐标

        // console.log("最终结果: x=", x, "y=", y, "videoWidth=", displayWidth, "videoHeight=", displayHeight)
        // console.log("=== mapMouseToVideo 结束 ===")

        return {
            x: x,
            y: y,
            videoWidth: displayWidth,
            videoHeight: displayHeight
        }
    }

    function stop(){
        // client.stop()
        // 根据配置选择使用哪种serial格式断开连接
        var deviceSerial = ""
        if (AppConfig.useDirectTcp) {
            // TCP直连模式：使用dbId作为serial
            deviceSerial = root.argument.dbId || root.argument.db_id || root.argument.id || root.argument.name || ""
        } else {
            // ADB模式：使用hostIp:adb格式
            deviceSerial = `${root.argument.hostIp}:${root.argument.adb}`
        }
        
        if (deviceSerial) {
            deviceManager.disconnectDevice(deviceSerial)
        } else {
            console.warn("无法断开设备，serial为空")
        }
        
        isConnect = false
        ReportHelper.reportLog("phone_play_stop", root.argument.padCode, {duration: Utils.milliseconds() - startTime})
    }

    function start(token){
        startTime = Utils.milliseconds()
    }

    // 设备序列号（根据配置动态确定）
    property string deviceSerial: {
        if (AppConfig.useDirectTcp) {
            return root.argument.dbId || root.argument.db_id || root.argument.id || root.argument.name || ""
        } else {
            return `${root.argument.hostIp}:${root.argument.adb}`
        }
    }
    
    // 设备observer对象（用于连接信号）
    property var deviceObserver: null
    
    // 连接DeviceManager的信号
    Connections {
        target: deviceManager
        
        function onScreenInfo(serial, width, height) {
            if (serial !== root.deviceSerial) return
            
            // 保存设备实际屏幕大小
            root.deviceScreenWidth = width
            root.deviceScreenHeight = height
            
            const rotation = height > width ? 0 : 1
            console.log("Screen changed: ", width, height, rotation)

            aspectRatio = rotation === 0 ? (height / width) : (width / height)
            console.log("云机实际比例", aspectRatio)
            remoteDirection = rotation === 0 ? 0 : 1

            // 如果正在恢复窗口大小，只更新方向和旋转，不改变窗口大小
            if(isRestoringWindow){
                if(direction !== remoteDirection){
                    direction = remoteDirection
                    if(direction == 0){
                        videoItem.rotation = 0
                    }else{
                        videoItem.rotation = 270
                    }
                }
                return
            }

            if(direction !== remoteDirection){
                direction = remoteDirection
                console.log("云机方向", direction == 0 ? "竖屏" : "横屏")
                if(direction == 0){
                    // 竖屏
                    const realWidth = root.width - spaceWidth
                    const realHeight = root.height - spaceHeight

                    root.width = realHeight + spaceWidth
                    root.height= (realHeight * aspectRatio) + spaceHeight
                }else if(direction == 1){
                    // 横屏
                    const realWidth = root.width - spaceWidth
                    const realHeigth = root.height - spaceHeight

                    root.width= (realWidth * aspectRatio) + spaceWidth
                    root.height= realWidth + spaceHeight
                }
                if(direction == 0){
                    // 竖屏
                    videoItem.rotation = 0

                }else{
                    // 横屏
                    videoItem.rotation = 270
                }
            }
        }
        
        function onDeviceConnected(serial, deviceName, size) {
            if (serial !== root.deviceSerial) return
            
            console.log("========onDeviceConnected", serial, deviceName, size, new Date())
            
            // 设置连接状态为已连接
            root.isConnect = true
            
            // 保存设备实际屏幕大小（从size参数获取）
            if (size && size.width > 0 && size.height > 0) {
                root.deviceScreenWidth = size.width
                root.deviceScreenHeight = size.height
                console.log("onDeviceConnected: 保存设备屏幕大小", root.deviceScreenWidth, root.deviceScreenHeight)
            }
            
            // 设备连接成功后，设置userData和注册observer
            if (root.deviceSerial) {
                // 设置videoItem为设备的userData，这样observer可以直接调用onFrame
                deviceManager.setUserData(root.deviceSerial, videoItem)
                
                // 注册observer以接收视频帧和事件
                if (deviceManager.registerObserver(root.deviceSerial)) {
                    // 获取observer对象并连接信号（如果需要直接连接信号）
                    root.deviceObserver = deviceManager.getObserver(root.deviceSerial)
                    if (root.deviceObserver) {
                        // 可以在这里直接连接observer的信号（如果需要）
                        // root.deviceObserver.screenInfo.connect(...)
                    }
                    console.log("设备连接后已注册observer，serial:", root.deviceSerial)
                    
                    // 初始化剪贴板同步：启用从电脑到云主机的同步
                    //deviceManager.setDeviceClipboard(root.deviceSerial, false)
                } else {
                    console.warn("设备连接后无法注册observer，serial:", root.deviceSerial)
                }
            }
        }
        
        function onDeviceDisconnected(serial) {
            if (serial !== root.deviceSerial) return
            
            // 设置连接状态为未连接
            root.isConnect = false
            deviceManager.setUserData(root.deviceSerial, null)
            deviceManager.deRegisterObserver(root.deviceSerial)
            
            dialog.title = qsTr("系统提示")
            dialog.message = qsTr("连接已断开，请稍后重连")
            dialog.negativeText = qsTr("退出")
            dialog.onNegativeClickListener = function(){
                root.close()
            }
            dialog.positiveText = qsTr("确定")
            dialog.onPositiveClickListener = function(){
                root.close()
                dialog.close()
            }
            dialog.open()
        }
    }

    Component.onCompleted: {
        console.log(root.argument.status, root.argument.cvmStatus)
        root.appBar.height = 40
        setHitTestVisible(layout_appbar)
        setHitTestVisible(btnExtraReturn)
        setHitTestVisible(btnHideTool)
        setHitTestVisible(textHostIp)
        console.log("云机初始比例", aspectRatio)

        initWidth = 0
        const windowModify = SettingsHelper.get("windowModify", 1)
        if(windowModify == 0){
            // 读取窗口上次记录
            const savedDirection = windowSizeHelper.get(root.argument.dbId, "direction", 0)
            initWidth = windowSizeHelper.get(root.argument.dbId, "w", 0)
            const savedHeight = windowSizeHelper.get(root.argument.dbId, "h", 0)
            const savedX = windowSizeHelper.get(root.argument.dbId, "x", -1)
            const savedY = windowSizeHelper.get(root.argument.dbId, "y", -1)
            
            // 如果读取到了有效的位置信息，恢复窗口位置
            if(savedX >= 0 && savedY >= 0){
                Qt.callLater(function() {
                    root.x = savedX
                    root.y = savedY
                })
            }
            
            // 如果读取到了大小信息，恢复窗口大小（根据保存时的方向）
            if(savedHeight > 0 && initWidth > 0){
                // 先设置方向，避免 onScreenInfo 触发时重新计算窗口大小
                direction = savedDirection
                // 标记正在恢复窗口，避免 onScreenInfo 改变窗口大小
                isRestoringWindow = true
                // 根据恢复的大小更新aspectRatio
                if(savedDirection == 0){
                    // 竖屏：realWidth = initWidth, realHeight = savedHeight
                    aspectRatio = savedHeight / initWidth
                    // 设置保存的窗口大小，绑定属性会使用这些值
                    savedWindowWidth = initWidth + spaceWidth
                    savedWindowHeight = savedHeight + spaceHeight
                }else{
                    // 横屏：realWidth = savedHeight, realHeight = initWidth
                    aspectRatio = initWidth / savedHeight
                    // 设置保存的窗口大小，绑定属性会使用这些值
                    savedWindowWidth = savedHeight + spaceWidth
                    savedWindowHeight = initWidth + spaceHeight
                }
                // 使用延迟确保窗口大小正确设置
                Qt.callLater(function() {
                    if(savedDirection == 0){
                        videoItem.rotation = 0
                    }else{
                        videoItem.rotation = 270
                    }
                    // 再次延迟确认窗口大小，然后清除保存的大小标志，恢复绑定属性
                    Qt.callLater(function() {
                        // 延迟恢复标志，确保窗口大小设置完成后再允许 onScreenInfo 改变窗口
                        Qt.callLater(function() {
                            // 清除保存的大小，允许后续使用绑定属性
                            savedWindowWidth = 0
                            savedWindowHeight = 0
                            isRestoringWindow = false
                        })
                    })
                })
            }
        }

        if(initWidth == 0){
            // 读取设置
            const windowSize = SettingsHelper.get("windowSize", 1)
            if(windowSize == 3){
                // 自定义
                initWidth = SettingsHelper.get("customWidth", 160)
            }else{
                initWidth = AppConfig.windowSize[windowSize].width
            }
        }

        console.log("屏幕比例", aspectRatio)
        // reqStsToken(root.argument.supplierType, root.argument.equipmentId)
        
        // 从本地存储加载位置信息（不再调用接口，由 MainWindow 统一更新）
        loadIpInfoFromStorage()

        // 注意：在Component.onCompleted时设备可能还没连接
        // 所以先尝试注册observer，如果失败则在onDeviceConnected信号中再注册
        if (root.deviceSerial) {
            // 先尝试设置userData（如果设备已存在）
            deviceManager.setUserData(root.deviceSerial, videoItem)
            
            // 尝试注册observer（如果设备已连接）
            if (deviceManager.registerObserver(root.deviceSerial)) {
                root.deviceObserver = deviceManager.getObserver(root.deviceSerial)
                console.log("Component.onCompleted: 已注册设备observer，serial:", root.deviceSerial)
                
                // 如果 observer 注册成功，说明设备已连接，设置连接状态
                root.isConnect = true
                
                // 初始化剪贴板同步：启用从电脑到云主机的同步
                //deviceManager.setDeviceClipboard(root.deviceSerial, false)
            } else {
                console.log("Component.onCompleted: 设备尚未连接，将在onDeviceConnected时注册observer，serial:", root.deviceSerial)
            }
        } else {
            console.warn("设备序列号为空，无法设置userData和注册observer")
        }
        
        // 恢复视频注入开关状态
        Qt.callLater(function() {
            const savedVideoInject = windowSizeHelper.get(root.argument.dbId, "videoInject", 0)
            console.log("恢复视频注入开关状态，保存的状态:", savedVideoInject, "推流状态:", cameraStreamManager ? cameraStreamManager.isStreaming : false, "RTSP URL:", cameraStreamManager ? cameraStreamManager.rtspUrl : "")
            if(savedVideoInject === 1){
                // 如果之前是开启状态，恢复开关状态（但不自动注入，因为可能已经在注入了）
                if(cameraStreamManager && cameraStreamManager.isStreaming && cameraStreamManager.rtspUrl){
                    videoInjectSwitch.checked = true
                    console.log("恢复视频注入开关状态：开启（推流正在进行）")
                } else {
                    // 即使推流还没开始，也先恢复开关状态，等推流开始后再同步
                    videoInjectSwitch.checked = true
                    console.log("恢复视频注入开关状态：开启（等待推流开始）")
                }
            } else {
                videoInjectSwitch.checked = false
                console.log("恢复视频注入开关状态：关闭")
            }
        })
    }

    Component.onDestruction: {
        // if(groupControl.isEventSync() && groupControl.isEventSyncMaster(root.argument.padCode)){
        //     groupControl.setEventSyncMaster("")
        // }

        // 注销observer
        if (root.deviceSerial && root.deviceObserver) {
            deviceManager.deRegisterObserver(root.deviceSerial)
        }
        
        // 保存视频注入开关状态
        if(videoInjectSwitch){
            windowSizeHelper.save(root.argument.dbId, "videoInject", videoInjectSwitch.checked ? 1 : 0)
            console.log("保存视频注入开关状态:", videoInjectSwitch.checked ? "开启" : "关闭")
        }
        
        // 窗口关闭时不再自动取消视频注入，保持注入状态以便继续直播任务
        
        stop()
    }

    FileDialog {
        id: fileDialog
        fileMode: FileDialog.OpenFiles
        nameFilters: [
            "All files(*)",
            "APK (*.apk)",
            "XAPK (*.xapk)",
            "APK/XAPK (*.apk *.xapk)",
            "Images (*.png *.jpg *.jpeg *.gif *.bmp *.webp *.heic *.tif *.tiff)",
            "Videos (*.mp4 *.avi *.mkv *.mov *.webm *.flv *.3gp)",
            "Audio (*.mp3 *.aac *.wav *.flac *.m4a *.ogg)",
            "Documents (*.pdf *.doc *.docx *.xls *.xlsx *.ppt *.pptx *.txt *.md)"
        ]
        property string actionType: "upload"  // "apk" 或 "upload"，用于区分操作类型
        
        onAccepted: {
            console.log("onAccepted", fileDialog.files, "actionType:", actionType)
            
            fileDialog.files.forEach(
                        item => {
                            console.log("处理文件:", item, "类型:", typeof item)
                            // 使用FluTools转换本地路径
                            const localPath = FluTools.toLocalPath(item)
                            console.log("转换后的本地路径:", localPath)
                            const lower = localPath.toLowerCase()
                            const fileName = localPath.split("/").pop()
                            console.log("文件名:", fileName, "文件类型:", lower)

                            if (actionType === "apk") {
                                // APK 安装按钮：安装 APK 或 XAPK 文件
                                if (lower.endsWith(".apk")) {
                        const hostIp = root.argument.hostIp || ""
                        const dbId = root.argument.dbId || ""
                        const serial = root.deviceSerial || ""
                        console.log("开始安装APK，设备信息:", {hostIp, dbId, serial, fileName})
                        if(hostIp && dbId){
                            showLoading(qsTr("安装中..."))
                            // 使用新的批量安装APK接口
                            const url = `http://${hostIp}:18182/android_api/v1/upload_file_android_batch`
                            console.log("APK安装请求URL:", url, "dbId:", dbId)
                            Network.postForm(url)
                            .add("db_ids", dbId)  // 实例ID列表，支持单个或多个（逗号分隔）
                            .addFile("file", localPath)  // APK文件
                            .setTimeout(3600000)
                            .bind(root)
                            .go(installApk)
                        }
                    } else if (lower.endsWith(".xapk")) {
                        const hostIp = root.argument.hostIp || ""
                        const dbId = root.argument.dbId || ""
                        const serial = root.deviceSerial || ""
                        console.log("开始安装XAPK，设备信息:", {hostIp, dbId, serial, fileName})
                        if(hostIp && dbId){
                            showLoading(qsTr("XAPK安装中..."))
                            const url = `http://${hostIp}:18182/container_api/v1/install_xapk/${dbId}`
                            console.log("XAPK安装请求URL:", url)
                            Network.postForm(url)
                            .addFile("file", localPath)
                            .bind(root)
                            .go(installXapk)
                        }
                    } else {
                        console.warn("APK按钮选择了非APK/XAPK文件，忽略:", localPath)
                        showError(qsTr("只能选择APK或XAPK文件"))
                    }
                            } else {
                                // 导入按钮：所有文件（包括APK）都上传到云机，不执行安装
                                const hostIp = root.argument.hostIp || ""
                                const dbId = root.argument.dbId || ""
                                const serial = root.deviceSerial || ""
                                const targetPath = ""//"/sdcard/Download"
                                console.log("开始上传文件，设备信息:", {hostIp, dbId, serial, fileName, targetPath})
                                if(hostIp && dbId){
                                    showLoading(qsTr("文件上传中..."))
                                    // 使用新的批量上传文件接口
                                    const url = `http://${hostIp}:18182/android_api/v1/upload_file_android_upload`
                                    console.log("文件上传请求URL:", url, "dbId:", dbId, "targetPath:", targetPath)
                                    Network.postForm(url)
                                    .add("db_ids", dbId)  // 实例ID列表，支持单个或多个（逗号分隔）
                                    .addFile("file", localPath)  // 上传的文件
                                    // .add("path", targetPath)  // 可选，目标目录，默认 /storage/emulated/0/Download
                                    .bind(root)
                                    .go(uploadFile)
                                }
                            }
                        })
        }

        onRejected: {
            console.log("onRejected", fileDialog.files)
        }
    }


    GenericDialog {
        id:dialog
        title: qsTr("系统提示")
    }

    OneKeyNewDevicePopup{
        id: oneKeyNewDevicePopup

        modal: true
        z: 999
        width: parent ? Math.max(360, parent.width - 80) : implicitWidth
        //width:400
        onOneKeyNewDeviceRequest: (hostIp, dbIds, adiName, adiPass, wipeData) => {
            reqOneKeyNewDevice(hostIp, dbIds, adiName, adiPass, wipeData)
        }
    }

    // SharePopup{
    //     id: sharePopup
    // }

    // SessionObserver{
    //     id: sessionObserver
    //     onWsStatusChanged:
    //         (status) => {
    //             console.log("WebSocket Status:", status)
    //         }
    //     onConnected: {
    //         isConnect = true
    //         console.log("Connected to session")
    //     }
    //     onDisconnected: {
    //         isConnect = false
    //         console.log("Disconnected from session")
    //     }
    //     onClosed: {
    //         isConnect = false
    //         console.log("Session closed")
    //     }
    //     onScreenChanged:
    //         (width, height,rotation) => {
    //             console.log("Screen changed: ", width, height, rotation)

    //             aspectRatio = rotation === 0 ? (height / width) : (width / height)
    //             console.log("云机实际比例", aspectRatio)
    //             remoteDirection = rotation === 0 ? 0 : 1

    //             if(direction !== remoteDirection){
    //                 direction = remoteDirection
    //                 console.log("云机方向", direction == 0 ? "竖屏" : "横屏")
    //                 if(direction == 0){
    //                     // 竖屏
    //                     const realWidth = root.width - spaceWidth
    //                     const realHeight = root.height - spaceHeight

    //                     root.width = realHeight + spaceWidth
    //                     root.height= (realHeight * aspectRatio) + spaceHeight
    //                 }else if(direction == 1){
    //                     // 横屏
    //                     const realWidth = root.width - spaceWidth
    //                     const realHeigth = root.height - spaceHeight

    //                     root.width= (realWidth * aspectRatio) + spaceWidth
    //                     root.height= realWidth + spaceHeight
    //                 }
    //                 if(direction == 0){
    //                     // 竖屏
    //                     videoItem.rotation = 0

    //                 }else{
    //                     // 横屏
    //                     videoItem.rotation = 270
    //                 }
    //             }
    //         }
    //     onClipboardMessageReceived:
    //         (text) => {
    //             console.log("Clipboard message: ", text)
    //             FluTools.clipText(text)
    //         }
    //     onFirstVideoFrameReceived: {
    //         isConnect = true
    //         console.log("First video frame received")
    //         ReportHelper.reportLog("phone_play", root.argument.padCode, {label: "success", duration: Utils.milliseconds() - startTime})
    //     }
    //     onNetworkQualityChanged:
    //         (rtt) => {
    //             // console.log("Network quality: RTT =", rtt)
    //             textDelay.text = rtt + "ms"
    //             if(rtt < 90){
    //                 imageDelay.source = "qrc:/res/pad/pad_delay_green.png"
    //                 textDelay.color = "#30BF8F"
    //             }else if(rtt < 150){
    //                 imageDelay.source = "qrc:/res/pad/pad_delay_yellow.png"
    //                 textDelay.color = "#FFAC00"
    //             }else{
    //                 imageDelay.source = "qrc:/res/pad/pad_delay_red.png"
    //                 textDelay.color = "#FF4D4D"

    //                 ReportHelper.reportLog("phone_delay_ge_150", root.argument.padCode)
    //             }
    //         }
    //     onIdleTimeout: {
    //         isConnect = false
    //         dialog.title = qsTr("系统提示")
    //         dialog.message = qsTr("长时间未操作云机，已自动托管到云端(云机内应用仍在运行)")
    //         dialog.negativeText = qsTr("退出")
    //         dialog.onNegativeClickListener = function(){
    //             root.close()
    //             ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "idleQuit"})
    //         }
    //         dialog.positiveText = qsTr("重连")
    //         dialog.onPositiveClickListener = function(){
    //             if(!isConnect){
    //                 reqStsToken(root.argument.supplierType, root.argument.equipmentId)
    //                 ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "idleReconnect"})
    //             }
    //             dialog.close()
    //         }
    //         dialog.open()

    //         ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "idlePopup", duration: Utils.milliseconds() - startTime})
    //     }
    //     onErrorOccurred:
    //         (error, msg) => {
    //             console.log("Error:", error, msg)
    //             dialog.title = qsTr("系统提示")
    //             dialog.message = msg
    //             dialog.buttonFlags = FluContentDialogType.PositiveButton
    //             dialog.positiveText = qsTr("确定")
    //             dialog.onPositiveClickListener = function(){
    //                 root.close()
    //                 dialog.close()
    //             }
    //             dialog.open()

    //             ReportHelper.reportLog("phone_play", root.argument.padCode, {label: "failed", str1: error, str2: msg, duration: Utils.milliseconds() - startTime})
    //         }
    //     onRoomErrorOccurred:
    //         (error) => {
    //             console.log("onRoomErrorOccurred", error)
    //             isConnect = false
    //             dialog.title = qsTr("系统提示")
    //             dialog.message = qsTr("长时间未操作云机，已自动托管到云端(云机内应用仍在运行)")
    //             dialog.negativeText = qsTr("退出")
    //             dialog.onNegativeClickListener = function(){
    //                 root.close()
    //                 ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "idleQuit"})
    //             }
    //             dialog.positiveText = qsTr("重连")
    //             dialog.onPositiveClickListener = function(){
    //                 if(!isConnect){
    //                     reqStsToken(root.argument.supplierType, root.argument.equipmentId)
    //                     ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "idleReconnect"})
    //                 }
    //                 dialog.close()
    //             }
    //             dialog.open()
    //             ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "expiredPopup", str1: error, duration: Utils.milliseconds() - startTime})
    //         }
    //     onCameraChanged:
    //         (isFront, isOpen)=> {
    //             console.log("Camera changed: Front =", isFront, " Open =", isOpen)
    //             const cameraId = SettingsHelper.get("cameraId", 0)
    //             const microphoneId = SettingsHelper.get("microphoneId", 0)
    //             if (isOpen) {
    //                 if(client){
    //                     client.startVideoCapture(cameraId)
    //                     client.publishStream(0)

    //                     client.startAudioCapture(microphoneId)
    //                     client.publishStream(1)
    //                 }
    //             }
    //             else {
    //                 if(client){
    //                     client.unPublishStream(0)
    //                     client.stopVideoCapture()

    //                     client.unPublishStream(1)
    //                     client.stopAudioCapture()
    //                 }
    //             }
    //         }

    //     onMicrophoneChanged:
    //         (isOpen) => {
    //             console.log("Microphone changed: Open =", isOpen)
    //             const microphoneId = SettingsHelper.get("microphoneId", 0)
    //             if (isOpen) {
    //                 if(client){
    //                     client.startAudioCapture(microphoneId)
    //                     client.publishStream(1)
    //                 }
    //             }
    //             else {
    //                 if(client){
    //                     client.unPublishStream(1)
    //                     client.stopAudioCapture()
    //                 }
    //             }
    //         }

    //     onInjectVideoStreamResult:
    //         (action, result, code, msg)=>{
    //             console.log("onInjectVideoStreamResult", action, result, code, msg)
    //             if(result){
    //                 if(action == "start"){
    //                     if(client){
    //                         client.injectVideoStats()
    //                     }
    //                 }else if(action == "stop"){
    //                     currentInjectFile = ""
    //                 }
    //             }else{
    //                 showError(msg)
    //             }
    //         }

    //     onInjectVideoStats:
    //         (path) => {
    //             console.log("onInjectVideoStats", path)
    //             currentInjectFile = path.split("/").pop()
    //         }

    //     onVideoCaptureResult:
    //         (code, msg) => {
    //             console.log("onVideoCaptureResult", code, msg)
    //         }

    //     onAudioCaptureResult:
    //         (code, msg) => {
    //             console.log("onAudioCaptureResult", code, msg)
    //         }

    //     onImeInputState:
    //         (isOpen, option)=>{
    //             console.log("ime state changed: isOpen =", isOpen, " option =", option)
    //             if(isOpen){
    //                 inputField.focus = true
    //             }else{
    //                 rootContainer.focus = true
    //             }
    //         }
    // }

    onWindowStateChanged:
        (windowState) => {
            if (windowState === Qt.WindowMaximized) {
                console.log("窗口最大化")
                btn_restore.visible = true
                btn_max.visible = false
                // 记录最后的状态
                lastDirection = direction
            } else if (windowState === Qt.WindowNoState) {
                console.log("窗口从最大化状态还原了")
                btn_restore.visible = false
                btn_max.visible = true
                // 恢复为最后的状态
                direction = lastDirection
                if(direction == 0){
                    // 竖屏
                    videoItem.rotation = 0
                }else{
                    // 横屏
                    videoItem.rotation = 270
                }
            }
        }

    onVisibleChanged: {
        // 当窗口变为可见且选择"保持不变"时，确保窗口居中显示
        if (visible) {
            const windowModify = SettingsHelper.get("windowModify", 1)
            if (windowModify == 1) {
                Qt.callLater(function() {
                    root.moveWindowToDesktopCenter()
                })
            }
        }
    }

    function findJoystickModel() {
        for (var i = 0; i < keymapperModel.rowCount(); ++i) {
            if (keymapperModel.get(i).type === 1) {
                return { model: keymapperModel.get(i), index: i };
            }
        }
        return null;
    }

    function calculateJoystickPosition(joystick) {
        let dx = 0;
        let dy = 0;
        const keys = joystick.model.key.split('|');

        const keysToProcess = joystickState.keys.slice(0, 2);

        if (keysToProcess.indexOf(keys[0]) > -1) dy -= 1; // W
        if (keysToProcess.indexOf(keys[1]) > -1) dy += 1; // S
        if (keysToProcess.indexOf(keys[2]) > -1) dx -= 1; // A
        if (keysToProcess.indexOf(keys[3]) > -1) dx += 1; // D

        const len = Math.sqrt(dx * dx + dy * dy);
        if (len > 0) {
            dx /= len;
            dy /= len;
        }

        const radiusX = (joystick.model.cx / 2) / maskRect.width;
        const radiusY = (joystick.model.cy / 2) / maskRect.height;

        return {
            x: joystick.model.px + dx * radiusX,
            y: joystick.model.py + dy * radiusY
        };
    }

    function updateJoystickState(joystick) {
        const hasActiveKeys = joystickState.keys.length > 0;

        if (hasActiveKeys && !joystickState.active) {
            // First key was pressed: Start the touch gesture (simplified version).
            joystickState.active = true;

            // 1. Send a `touchDown` at the joystick's CENTER.
            const centerX = joystick.model.px;
            const centerY = joystick.model.py;
            client.sendMultiEvent("AWSD", 0, centerX * width, centerY * height, width, height)
            console.log("joystick down", centerX * width, centerY * height)


            // 2. Immediately send a `touchMove` to the key's direction.
            const newPos = calculateJoystickPosition(joystick);
            joystickState.lastSentX = newPos.x;
            joystickState.lastSentY = newPos.y;
            Qt.callLater(
                        () => {
                            client.sendMultiEvent("AWSD", 2, newPos.x * width, newPos.y * height, width, height)
                            console.log("joystick move 1", newPos.x * width, newPos.y * width)
                        })


        } else if (hasActiveKeys && joystickState.active) {
            // Keys changed while gesture is active: Send a move event ONLY if position changes.
            const newPos = calculateJoystickPosition(joystick);
            if (newPos.x !== joystickState.lastSentX || newPos.y !== joystickState.lastSentY) {
                joystickState.lastSentX = newPos.x;
                joystickState.lastSentY = newPos.y;
                client.sendMultiEvent("AWSD", 2, newPos.x * width, newPos.y * height, width, height)
                console.log("joystick move 2", newPos.x * width, newPos.y * height)
            }

        } else if (!hasActiveKeys && joystickState.active) {
            // Last key was released: End the touch gesture.
            joystickState.active = false;
            client.sendMultiEvent("AWSD", 1, joystickState.lastSentX * width, joystickState.lastSentY * height, width, height)
            console.log("joystick up", joystickState.lastSentX * width, joystickState.lastSentY * height)
        }
    }

    function handleKeyPress(key, isPressed) {
        console.log("handleKeyPress", key, isPressed)

        const joystick = findJoystickModel();
        if (joystick) {
            const keys = joystick.model.key.split('|');
            const keyIndex = keys.indexOf(key);
            if (keyIndex !== -1) {
                // The pressed key belongs to the joystick. Handle it and exit.
                const keyWasPressed = joystickState.keys.indexOf(key) > -1;
                if (isPressed && !keyWasPressed) {
                    joystickState.keys.push(key);
                } else if (!isPressed && keyWasPressed) {
                    joystickState.keys.splice(joystickState.keys.indexOf(key), 1);
                }
                updateJoystickState(joystick);
                return; // IMPORTANT: Stop processing after handling the joystick key.
            }
        }

        const action = isPressed ? 0 : 1;
        for (var i = 0; i < keymapperModel.rowCount(); ++i) {
            var itemModel = keymapperModel.get(i);
            console.log("======================", itemModel.key, itemModel.type, key, action)
            if(itemModel.type === 2 && itemModel.key === key){
                client.sendMultiEvent(key, action, itemModel.px * width, itemModel.py * height, width, height)
                return;
            }
        }
    }

    DropArea{
        anchors.fill: parent

        onEntered: (drag) => {
                       console.log("有文件拖动")
                       drag.accepted = true
                   }

        onDropped: (drop) => {
                       if (drop.hasUrls) {
                           console.log("拖入文件路径:", drop.urls)
                           drop.urls.forEach(item => {
                                                 console.log("拖拽文件处理:", item, "类型:", typeof item)
                                                 // 使用FluTools转换本地路径
                                                 const localPath = FluTools.toLocalPath(item)
                                                 console.log("拖拽文件转换后的本地路径:", localPath)
                                                 const lower = localPath.toLowerCase()
                                                 const fileName = localPath.split("/").pop()
                                                 console.log("拖拽文件名:", fileName, "文件类型:", lower)

                                                 if (lower.endsWith(".apk")){
                                                     if(root.deviceSerial){
                                                         // 根据连接模式确定ADB设备地址
                                                         let adbDeviceAddress = ""
                                                         const networkMode = root.argument.networkMode || ""
                                                         if (networkMode === "macvlan") {
                                                             // Macvlan模式：使用 ip:5555 作为ADB设备地址
                                                             const ip = root.argument.ip || ""
                                                             if (ip) {
                                                                 adbDeviceAddress = `${ip}:5555`
                                                             }
                                                         } else if (AppConfig.useDirectTcp) {
                                                             // TCP直连模式：使用 hostIp:adb 作为ADB设备地址
                                                             const hostIp = root.argument.hostIp || ""
                                                             const adb = root.argument.adb || 0
                                                             if (hostIp && adb > 0) {
                                                                 adbDeviceAddress = `${hostIp}:${adb}`
                                                             }
                                                         }
                                                         // 使用API方式安装APK
                                                         const hostIp = root.argument.hostIp || ""
                                                         const dbId = root.argument.dbId || ""
                                                         if(hostIp && dbId){
                                                             showLoading(qsTr("安装中..."))
                                                             // 使用新的批量安装APK接口
                                                             Network.postForm(`http://${hostIp}:18182/android_api/v1/upload_file_android_batch`)
                                                             .add("db_ids", dbId)  // 实例ID列表，支持单个或多个（逗号分隔）
                                                             .addFile("file", localPath)  // APK文件
                                                             .setTimeout(3600000)
                                                             .bind(root)
                                                             .go(installApk)
                                                         }
                                                     }
                                                 } else if (lower.endsWith(".xapk")){
                                                     const hostIp = root.argument.hostIp || ""
                                                     const dbId = root.argument.dbId || ""
                                                     if(hostIp && dbId){
                                                         showLoading(qsTr("XAPK安装中..."))
                                                         Network.postForm(`http://${hostIp}:18182/container_api/v1/install_xapk/${dbId}`)
                                                         .addFile("file", localPath)
                                                         .bind(root)
                                                         .go(installXapk)
                                                     }
                                                 } else {
                                                     const hostIp = root.argument.hostIp || ""
                                                     const dbId = root.argument.dbId || ""
                                                     if(hostIp && dbId){
                                                         showLoading(qsTr("文件上传中..."))
                                                         // 使用新的批量上传文件接口
                                                         Network.postForm(`http://${hostIp}:18182/android_api/v1/upload_file_android_upload`)
                                                         .add("db_ids", dbId)  // 实例ID列表，支持单个或多个（逗号分隔）
                                                         .addFile("file", localPath)  // 上传的文件
                                                        //  .add("path", "/sdcard/Download")  // 可选，目标目录，默认 /storage/emulated/0/Download
                                                         .bind(root)
                                                         .go(uploadFile)
                                                     }
                                                 }
                                             })
                       }
                   }
    }

    Item{
        id: rootContainer
        anchors.fill: parent
        focus: true

        // 窗口级别的键盘事件监听：当检测到键盘输入但 inputField 没有焦点时，恢复焦点
        Keys.onPressed: (event) => {
            if (event.key >= Qt.Key_Space && event.key <= Qt.Key_ydiaeresis) {
                if (!inputField.focus) {
                    inputField.forceActiveFocus()
                }
            }
            event.accepted = false
        }

        TextInput {
            id: inputField
            width: parent.width
            height: 50
            focus: true

            function eventToVariant(event, eventType) {
                return {
                    "type": eventType,
                    "key": event.key,
                    "text": event.text,
                    "modifiers ": event.modifiers
                };
            }


            onTextChanged: {
                if(!inputField.text){
                    return
                }

                if (root.deviceSerial) {
                    deviceManager.textInput(root.deviceSerial, inputField.text);
                    inputField.text = ""
                }
            }

            Keys.onPressed:
                (event) => {
                    if (event.key >= Qt.Key_Space && event.key <= Qt.Key_ydiaeresis) {
                        // 可打印字符交给 onTextChanged 处理
                        return
                    }

                    const newKey = KeyMapper.getAndroidKeyCode(event.key)
                    if(newKey !== -1 && root.deviceSerial){
                        deviceManager.sendKeyEvent(root.deviceSerial, 6, event.key, event.modifiers, event.text)
                    }
                    event.accepted = true
                }

            Keys.onReleased:
                (event) => {
                    if (event.key >= Qt.Key_Space && event.key <= Qt.Key_ydiaeresis) {
                        return
                    }
                    const newKey = KeyMapper.getAndroidKeyCode(event.key)
                    if(newKey !== -1 && root.deviceSerial){
                        deviceManager.sendKeyEvent(root.deviceSerial, 7, event.key, event.modifiers, event.text)
                    }
                }
        }

        RowLayout{
            anchors.fill: parent
            spacing: 0

            ColumnLayout{
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle{
                    Layout.preferredHeight: 40
                    Layout.fillWidth: true
                    color: "#FF0B2F52"

                    RowLayout{
                        id: layout_title
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 10

                        // Image {
                        //     source: root.argument.androidVersionAvatar
                        //     Layout.preferredHeight: 20
                        //     Layout.preferredWidth: implicitWidth * (height / implicitHeight)
                        //     fillMode: Image.PreserveAspectFit
                        // }

                        Column{
                            visible: root.width >= 300
                            FluText{
                                text: root.argument.displayName
                                textColor: "#FF637199"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: 100
                            }
                            FluText{
                                id: textHostIp
                                text: {
                                    if (root.argument.networkMode === "macvlan"){
                                        if (root.argument.state !== "running"){
                                            return "-"
                                        }
                                    }
                                    return root.argument.networkMode === "macvlan" ? `${root.argument.ip ?? ""}:5555` : `${root.argument.hostIp ?? ""}:${root.argument.adb ?? ""}`
                                }

                                textColor: "#FFB7BCCC"
                                font.pixelSize: 10

                                MouseArea{
                                    anchors.fill: parent
                                    onClicked: {
                                        FluTools.clipText(textHostIp.text)
                                        showSuccess(qsTr("复制成功"))
                                    }
                                }
                            }
                        }

                    }

                    RowLayout{
                        id: layout_appbar
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        implicitWidth: childrenRect.width
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4

                        Item{
                            implicitWidth: 24
                            implicitHeight: 24

                            Image {
                                source: root.stayTop ? "qrc:/res/pad/pad_top_selected.png" : "qrc:/res/pad/pad_top.png"
                            }

                            MouseArea{
                                anchors.fill: parent
                                onClicked: {
                                    root.stayTop = !root.stayTop
                                }
                            }
                        }

                        FluImageButton{
                            implicitWidth: 24
                            implicitHeight: 24
                            normalImage: "qrc:/res/pad/pad_min.png"
                            hoveredImage: "qrc:/res/pad/pad_min.png"
                            pushedImage: "qrc:/res/pad/pad_min.png"
                            onClicked: {
                                root.showMinimized()
                            }
                        }

                        FluImageButton{
                            id: btn_restore
                            implicitWidth: 24
                            implicitHeight: 24
                            visible: false
                            normalImage: "qrc:/res/pad/pad_restore.png"
                            hoveredImage: "qrc:/res/pad/pad_restore.png"
                            pushedImage: "qrc:/res/pad/pad_restore.png"
                            onClicked: {
                                btn_restore.visible = false
                                btn_max.visible = true
                                root.showNormal()
                            }
                        }
                        FluImageButton{
                            id: btn_max
                            implicitWidth: 24
                            implicitHeight: 24
                            normalImage: "qrc:/res/pad/pad_max.png"
                            hoveredImage: "qrc:/res/pad/pad_max.png"
                            pushedImage: "qrc:/res/pad/pad_max.png"
                            onClicked: {
                                btn_restore.visible = true
                                btn_max.visible = false
                                root.showMaximized()
                            }
                        }

                        FluImageButton{
                            implicitWidth: 24
                            implicitHeight: 24
                            normalImage: "qrc:/res/pad/pad_close.png"
                            hoveredImage: "qrc:/res/pad/pad_close.png"
                            pushedImage: "qrc:/res/pad/pad_close.png"
                            onClicked: {
                                ReportHelper.reportLog("phone_play", root.argument.padCode, {label: "close"})
                                // 保存窗口大小
                                const windowModify = SettingsHelper.get("windowModify", 1)
                                if(windowModify == 0 && (root.visibility != Window.Maximized)){
                                    // 记录上次
                                    const realWidth = root.width - spaceWidth
                                    const realHeigth = root.height - spaceHeight

                                    windowSizeHelper.save(root.argument.dbId, "x", root.x)
                                    windowSizeHelper.save(root.argument.dbId, "y", root.y)
                                    windowSizeHelper.save(root.argument.dbId, "w", direction == 0 ? realWidth : realHeigth)
                                    windowSizeHelper.save(root.argument.dbId, "h", direction == 0 ? realHeigth : realWidth)
                                    windowSizeHelper.save(root.argument.dbId, "direction", direction)  // 保存方向
                                }
                                
                                // 保存视频注入开关状态
                                if(videoInjectSwitch){
                                    windowSizeHelper.save(root.argument.dbId, "videoInject", videoInjectSwitch.checked ? 1 : 0)
                                }

                                root.close()
                            }
                        }

                        FluImageButton{
                            id: btnShowTool
                            implicitWidth: 24
                            implicitHeight: 24
                            visible: false
                            normalImage: "qrc:/res/pad/pad_show.png"
                            hoveredImage: "qrc:/res/pad/pad_show.png"
                            pushedImage: "qrc:/res/pad/pad_show.png"
                            onClicked: {
                                if(expandableToolBar.expanded){
                                    expandableToolBar.expanded = false
                                }
                                const realWidth = root.width - spaceWidth
                                spaceWidth = 40
                                root.width = realWidth + spaceWidth
                                layoutTool.visible = true
                                btnShowTool.visible = false
                            }
                        }
                    }
                }

                Rectangle{
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    color: "black"

                    VideoRenderItem {
                        id: videoItem
                        anchors.fill: parent
                        property bool isPressed: false
                        property real lastMoveTime: 0

                        MouseArea{
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.AllButtons

                            function mouseEventToVariant(mouse, eventType, newX, newY) {
                                return {
                                    "type": eventType,
                                    "x": newX,
                                    "y": newY,
                                    "button": mouse.button,
                                    "buttons": mouse.buttons
                                };
                            }

                            onPressed:
                                (mouse)=> {
                                    // console.log("=== 鼠标按下事件 ===")
                                    // console.log("鼠标坐标: mouse.x=", mouse.x, "mouse.y=", mouse.y)
                                    // console.log("视频区域大小: parent.width=", parent.width, "parent.height=", parent.height)
                                    // console.log("设备屏幕大小: deviceScreenWidth=", root.deviceScreenWidth, "deviceScreenHeight=", root.deviceScreenHeight)
                                    
                                    // 如果按下的是鼠标滚轮（中键），发送HOME键
                                    if (mouse.button === Qt.MiddleButton) {
                                        if(root.deviceSerial){
                                            deviceManager.goHome(root.deviceSerial)
                                        }
                                        return
                                    }
                                    
                                    // 如果按下的是鼠标右键，发送返回键
                                    if (mouse.button === Qt.RightButton) {
                                        if(root.deviceSerial){
                                            deviceManager.goBack(root.deviceSerial)
                                        }
                                        return
                                    }
                                    
                                    videoItem.isPressed = true
                                    const result = mapMouseToVideo(mouse.x, mouse.y, parent.width, parent.height, aspectRatio)
                                    // console.log("mapMouseToVideo 返回结果: x=", result.x, "y=", result.y, "videoWidth=", result.videoWidth, "videoHeight=", result.videoHeight)
                                    
                                    var mappedEvent = mouseEventToVariant(mouse, 2, result.x, result.y)
                                    if(root.deviceSerial){
                                        // 使用设备实际屏幕大小作为frameSize，而不是显示区域大小
                                        const frameWidth = root.deviceScreenWidth > 0 ? root.deviceScreenWidth : result.videoWidth
                                        const frameHeight = root.deviceScreenHeight > 0 ? root.deviceScreenHeight : result.videoHeight
                                        
                                        // 直接使用计算后的尺寸，当方向不一致时，mapMouseToVideo内部有做宽高交换
                                        // 这样 InputConvertNormal 才能正确缩放坐标
                                        let showWidth = result.videoWidth
                                        let showHeight = result.videoHeight
                                        
                                        // console.log("发送鼠标事件到云机: x=", mappedEvent.x, "y=", mappedEvent.y, "frameWidth=", frameWidth, "frameHeight=", frameHeight, "showWidth=", showWidth, "showHeight=", showHeight)
                                        deviceManager.sendMouseEvent(root.deviceSerial, mappedEvent.type, mappedEvent.x, mappedEvent.y,
                                                                     mappedEvent.button, mappedEvent.buttons, 0,
                                                                     frameWidth, frameHeight, showWidth, showHeight)
                                    }
                                    // console.log("=== 鼠标按下事件结束 ===")
                                }

                            onPositionChanged:
                                (mouse)=> {
                                    if(!videoItem.isPressed || !mouse.buttons){
                                        return
                                    }
                                    // const now = Utils.milliseconds()
                                    // if (now - videoItem.lastMoveTime >= 10) {
                                    const result = mapMouseToVideo(mouse.x, mouse.y, parent.width, parent.height, aspectRatio)
                                    var mappedEvent = mouseEventToVariant(mouse, 5, result.x, result.y)
                                    if(root.deviceSerial){
                                        // 使用设备实际屏幕大小作为frameSize，而不是显示区域大小
                                        const frameWidth = root.deviceScreenWidth > 0 ? root.deviceScreenWidth : result.videoWidth
                                        const frameHeight = root.deviceScreenHeight > 0 ? root.deviceScreenHeight : result.videoHeight
                                        
                                        // 直接使用计算后的尺寸，当方向不一致时，mapMouseToVideo内部有做宽高交换
                                        let showWidth = result.videoWidth
                                        let showHeight = result.videoHeight
                                        
                                        deviceManager.sendMouseEvent(root.deviceSerial, mappedEvent.type, mappedEvent.x, mappedEvent.y,
                                                                     mappedEvent.button, mappedEvent.buttons, 0,
                                                                     frameWidth, frameHeight, showWidth, showHeight)
                                    }
                                    // videoItem.lastMoveTime = now
                                    // }
                                }

                            onReleased:
                                (mouse)=> {
                                    const result = mapMouseToVideo(mouse.x, mouse.y, parent.width, parent.height, aspectRatio)
                                    var mappedEvent = mouseEventToVariant(mouse, 3, result.x, result.y)
                                    if(root.deviceSerial){
                                        // 使用设备实际屏幕大小作为frameSize，而不是显示区域大小
                                        const frameWidth = root.deviceScreenWidth > 0 ? root.deviceScreenWidth : result.videoWidth
                                        const frameHeight = root.deviceScreenHeight > 0 ? root.deviceScreenHeight : result.videoHeight
                                        
                                        // 直接使用计算后的尺寸，当方向不一致时，mapMouseToVideo内部有做宽高交换
                                        let showWidth = result.videoWidth
                                        let showHeight = result.videoHeight
                                        
                                        deviceManager.sendMouseEvent(root.deviceSerial, mappedEvent.type, mappedEvent.x, mappedEvent.y,
                                                                     mappedEvent.button, mappedEvent.buttons, 0,
                                                                     frameWidth, frameHeight, showWidth, showHeight)
                                    }
                                    videoItem.isPressed = false
                                    
                                    // 点击视频区域后，立即恢复 inputField 焦点
                                    // 这样当用户点击云机输入框时，窗口输入框也会立即获得焦点
                                    // 使用短延迟确保鼠标事件处理完成，但尽量快速
                                    Qt.callLater(function() {
                                        // 检查是否有其他组件有焦点（如按钮）
                                        const activeFocusItem = root.activeFocusItem
                                        // 如果焦点不在按钮上，则恢复 inputField 焦点
                                        let shouldRestoreFocus = true
                                        if (activeFocusItem && activeFocusItem !== inputField) {
                                            // 检查焦点是否在工具栏区域的按钮上
                                            let item = activeFocusItem
                                            while (item && item !== root) {
                                                // 如果焦点在工具栏区域，可能是按钮，不恢复焦点
                                                if (item.parent === layoutTool || item.parent === layoutExtra) {
                                                    shouldRestoreFocus = false
                                                    console.log("焦点在工具栏，不恢复 inputField 焦点")
                                                    break
                                                }
                                                item = item.parent
                                            }
                                        }
                                        
                                        if (shouldRestoreFocus) {
                                            if (inputField && !inputField.focus) {
                                                console.log("点击视频区域后，恢复 inputField 焦点（可能点击了云机输入框）")
                                                inputField.forceActiveFocus()
                                            }
                                            // 确保窗口激活，以便接收键盘事件
                                            if (!root.active) {
                                                root.requestActivate()
                                            }
                                        }
                                    })
                                }

                            onCanceled:
                                (mouse)=> {
                                    videoItem.isPressed = false
                                }
                        }

                        WheelHandler{
                            onWheel:
                                (event) => {
                                    const result = mapMouseToVideo(event.x, event.y, parent.width, parent.height, aspectRatio)
                                    var wheelEventData = {
                                        "x": result.x,
                                        "y": result.y,
                                        "angleDelta": event.angleDelta,
                                        "buttons": event.buttons,
                                        "modifiers": event.modifiers
                                    };
                                    if(root.deviceSerial){
                                        // 使用设备实际屏幕大小作为frameSize，而不是显示区域大小
                                        const frameWidth = root.deviceScreenWidth > 0 ? root.deviceScreenWidth : result.videoWidth
                                        const frameHeight = root.deviceScreenHeight > 0 ? root.deviceScreenHeight : result.videoHeight
                                        
                                        // 直接使用计算后的尺寸，当方向不一致时，mapMouseToVideo内部有做宽高交换
                                        let showWidth = result.videoWidth
                                        let showHeight = result.videoHeight
                                        
                                        deviceManager.sendWheelEvent(root.deviceSerial, wheelEventData.angleDelta.x, wheelEventData.angleDelta.y,
                                                                     wheelEventData.x, wheelEventData.y, wheelEventData.modifiers,
                                                                     frameWidth, frameHeight, showWidth, showHeight)
                                    }
                                }
                        }

                        Rectangle{
                            anchors.fill: parent
                            color: "white"
                            visible: videoItem.hasVideo ? false : true

                            Image {
                                anchors.centerIn: parent
                                source: ThemeUI.loadRes("pad/logo-head.png")
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    Rectangle{
                        id: maskRect
                        anchors.fill: parent
                        visible: false
                        color: "#A0000000"

                        MouseArea{
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                        }

                        Repeater{
                            id: keymapperRepeater
                            model: keymapperModel

                            delegate: Loader {
                                sourceComponent: model.type === 1 ? joystickComponent : buttonComponent
                                property var modelData: model
                                property real containerWidth: maskRect.width
                                property real containerHeight: maskRect.height

                                onLoaded: {
                                    if (model.type === 1) {
                                        item.radius = model.cx / 2;
                                    } else {
                                        item.width = model.cx;
                                        item.height = model.cy;
                                    }

                                    item.x = Qt.binding(() => (model.px * parent.width) - (item.width / 2))
                                    item.y = Qt.binding(() => (model.py * parent.height) - (item.height / 2))

                                    // Set type-specific properties and connect their signals.
                                    if (model.type === 1) { // Joystick
                                        item.radiusChanged.connect(() => {
                                                                       model.cx = item.radius * 2
                                                                       model.cy = item.radius * 2
                                                                   });
                                        var keys = model.key.split('|');
                                        if (keys.length === 4) {
                                            item.keyW.keyText = keys[0];
                                            item.keyS.keyText = keys[1];
                                            item.keyA.keyText = keys[2];
                                            item.keyD.keyText = keys[3];
                                        }
                                        function updateJoystickKey() {
                                            var newKey = [item.keyW.keyText, item.keyS.keyText, item.keyA.keyText, item.keyD.keyText].join('|')
                                            model.key = newKey
                                        }
                                        item.keyW.keyTextChanged.connect(updateJoystickKey);
                                        item.keyS.keyTextChanged.connect(updateJoystickKey);
                                        item.keyA.keyTextChanged.connect(updateJoystickKey);
                                        item.keyD.keyTextChanged.connect(updateJoystickKey);
                                    } else { // Button
                                        item.width = model.cx; item.height = model.cy;
                                        item.keyText = model.key;
                                        item.keyTextChanged.connect(() => {
                                                                        model.key = item.keyText
                                                                    });
                                    }
                                    item.deleteRequested.connect(() => {
                                                                     keymapperModel.deleteItem(model.key)
                                                                 });
                                }
                            }
                        }

                        // Component { id: buttonComponent; KeyMappingButton {} }
                        // Component { id: joystickComponent; JoystickMapping {} }
                    }
                }

                Rectangle{
                    Layout.preferredHeight: 40
                    Layout.fillWidth: true
                    color: "#FF0B2F52"

                    RowLayout{
                        anchors.fill: parent

                        Item{
                            Layout.fillWidth: true
                        }

                        FluImageButton{
                            implicitWidth: 32
                            implicitHeight: 32
                            normalImage: "qrc:/res/pad/pad_back.png"
                            hoveredImage: "qrc:/res/pad/pad_back.png"
                            pushedImage: "qrc:/res/pad/pad_back.png"
                            onClicked: {
                                if(root.deviceSerial){
                                    deviceManager.goBack(root.deviceSerial)
                                }
                            }
                        }
                        Item{
                            Layout.fillWidth: true
                        }
                        FluImageButton{
                            implicitWidth: 32
                            implicitHeight: 32
                            normalImage: "qrc:/res/pad/pad_home.png"
                            hoveredImage: "qrc:/res/pad/pad_home.png"
                            pushedImage: "qrc:/res/pad/pad_home.png"
                            onClicked: {
                                if(root.deviceSerial){
                                    deviceManager.goHome(root.deviceSerial)
                                }
                            }
                        }
                        Item{
                            Layout.fillWidth: true
                        }
                        FluImageButton{
                            implicitWidth: 32
                            implicitHeight: 32
                            normalImage: "qrc:/res/pad/pad_task.png"
                            hoveredImage: "qrc:/res/pad/pad_task.png"
                            pushedImage: "qrc:/res/pad/pad_task.png"
                            onClicked: {
                                if(root.deviceSerial){
                                    deviceManager.appSwitch(root.deviceSerial)
                                }
                            }
                        }
                        Item{
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Rectangle{
                id: layoutTool
                Layout.preferredWidth: root.spaceWidth
                Layout.fillHeight: true
                color: "#FF0B2F52"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item{
                        id: btnHideTool
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Image{
                            anchors.centerIn: parent
                            source: "qrc:/res/pad/pad_hide.png"
                        }

                        MouseArea{
                            anchors.fill: parent
                            onClicked: {
                                const realWidth = root.width - root.spaceWidth
                                root.spaceWidth = 0
                                root.width = realWidth + root.spaceWidth
                                layoutTool.visible = false
                                btnShowTool.visible = true
                            }
                        }
                    }

                    // 视频注入开关
                    Item{
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 50
                        ColumnLayout{
                            anchors.fill: parent
                            spacing: 4
                            
                            FluText{
                                text: qsTr("直播")
                                color: "white"
                                font.pixelSize: 9
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: 40
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            FluToggleSwitch{
                                id: videoInjectSwitch
                                Layout.alignment: Qt.AlignHCenter
                                checkColor: ThemeUI.primaryColor
                                checked: false
                                scale: 0.8
                                // enabled: cameraStreamManager && cameraStreamManager.isStreaming && cameraStreamManager.rtspUrl
                                onClicked: {
                                    if(checked){
                                        // 开启视频注入
                                        if(cameraStreamManager && cameraStreamManager.isStreaming && cameraStreamManager.rtspUrl){
                                            console.log("手动开启视频注入，RTSP URL:", cameraStreamManager.rtspUrl)
                                            // 先关闭注入（如果已注入），然后再开启，避免重复注入错误
                                            reqVideoInjectOffAndThenInject(cameraStreamManager.rtspUrl)
                                            // 注意：状态会在注入成功时保存，这里不提前保存
                                        } else {
                                            console.warn("无法开启视频注入：推流未开始或RTSP URL为空")
                                            checked = false
                                            windowSizeHelper.save(root.argument.dbId, "videoInject", 0)
                                            showError(qsTr("请先开启推流后再开启直播"))
                                        }
                                    } else {
                                        // 关闭视频注入
                                        console.log("手动关闭视频注入")
                                        reqVideoInjectOff()
                                        // 注意：状态会在关闭成功时保存，这里不提前保存
                                    }
                                }
                            }
                            
                            Item{
                                Layout.fillHeight: true
                            }
                        }
                    }

                    // Item{
                    //     Layout.preferredWidth: 40
                    //     Layout.preferredHeight: 50
                    //     ColumnLayout{
                    //         anchors.fill: parent
                    //         spacing: 0
                    //         Image {
                    //             id: imageDelay
                    //             source: "qrc:/res/pad/pad_delay_green.png"
                    //             Layout.alignment: Qt.AlignHCenter
                    //         }
                    //         Text {
                    //             id: textDelay
                    //             text: "0ms"
                    //             color: "#30BF8F"
                    //             font.pixelSize: 10
                    //             Layout.maximumWidth: 40
                    //             wrapMode: Text.WordWrap
                    //             horizontalAlignment: Text.AlignHCenter
                    //             Layout.alignment: Qt.AlignHCenter
                    //         }
                    //         Item{
                    //             Layout.fillHeight: true
                    //         }
                    //     }
                    // }

                    ExpandableToolBar {
                        id: expandableToolBar
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        onExpandedChanged: {
                            const realWidth = root.width - root.spaceWidth
                            root.spaceWidth = expandableToolBar.expanded ? 80 : 40
                            layoutTool.Layout.preferredWidth = root.spaceWidth
                            root.width = realWidth + root.spaceWidth
                        }

                        onToolClicked:
                            (modelData) => {
                                console.log("点击了按钮", modelData.name)
                                if(modelData.name === "apk"){
                                    fileDialog.title = qsTr("选择安装文件")
                                    fileDialog.nameFilters = ["APK/XAPK (*.apk *.xapk)", "APK (*.apk)", "XAPK (*.xapk)"]
                                    fileDialog.actionType = "apk"  // 标记为 APK 安装操作
                                    fileDialog.folder = StandardPaths.writableLocation(StandardPaths.HomeLocation)
                                    fileDialog.open()
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "apk"})
                                }else if(modelData.name === "upload"){
                                    fileDialog.title = qsTr("选择上传文件")
                                    fileDialog.nameFilters = [
                                        "All files(*)",
                                        "APK (*.apk)",
                                        "Images (*.png *.jpg *.jpeg *.gif *.bmp *.webp *.heic *.tif *.tiff)",
                                        "Videos (*.mp4 *.avi *.mkv *.mov *.webm *.flv *.3gp)",
                                        "Audio (*.mp3 *.aac *.wav *.flac *.m4a *.ogg)",
                                        "Documents (*.pdf *.doc *.docx *.xls *.xlsx *.ppt *.pptx *.txt *.md)"
                                    ]
                                    fileDialog.actionType = "upload"  // 标记为文件上传操作
                                    fileDialog.folder = StandardPaths.writableLocation(StandardPaths.HomeLocation)
                                    fileDialog.open()
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "upload"})
                                }else if(modelData.name === "volume_up"){
                                    // client.volumeUp()
                                    if(root.deviceSerial){
                                        deviceManager.volumeUp(root.deviceSerial)
                                    }
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "volUp"})
                                }else if(modelData.name === "volume_down"){
                                    // client.volumeDown()
                                    if(root.deviceSerial){
                                        deviceManager.volumeDown(root.deviceSerial)
                                    }
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "volDown"})
                                }else if(modelData.name === "rotation"){
                                    direction += 1
                                    direction %= 2
                                    console.log("云机方向", remoteDirection == 0 ? "竖屏" : "横屏")
                                    console.log("本地方向", direction == 0 ? "竖屏" : "横屏")
                                    console.log("是否最大化", root.visibility, Window.Maximized)
                                    if(root.visibility == Window.Maximized){
                                        // 最大化窗口大小不变
                                    }else{
                                        if(direction == 0){
                                            // 竖屏
                                            const realWidth = root.width - spaceWidth
                                            const realHeight = root.height - spaceHeight

                                            root.width = realHeight + spaceWidth
                                            root.height= (realHeight * aspectRatio) + spaceHeight
                                        }else if(direction == 1){
                                            // 横屏
                                            const realWidth = root.width - spaceWidth
                                            const realHeight = root.height - spaceHeight

                                            root.width= (realWidth * aspectRatio) + spaceWidth
                                            root.height= realWidth + spaceHeight
                                        }
                                    }
                                    if(direction == 0){
                                        // 竖屏
                                        videoItem.rotation = 0
                                    }else{
                                        // 横屏
                                        videoItem.rotation = 270
                                    }
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "rotation"})
                                }else if(modelData.name === "reboot"){
                                    dialog.title = qsTr("操作确认")
                                    dialog.message = qsTr("确定要重启云机？")
                                    dialog.negativeText = qsTr("取消")
                                    dialog.onNegativeClickListener = function(){
                                        dialog.close()
                                    }
                                    dialog.positiveText = qsTr("确定")
                                    dialog.onPositiveClickListener = function(){
                                        const padName = root.argument.name || root.argument.displayName
                                        reqRebootDevice(root.argument.hostIp, [padName])
                                        dialog.close()
                                    }
                                    dialog.open()
                                }else if(modelData.name === "onekey"){
                                    const padDisplayName = root.argument.displayName || root.argument.name
                                    const padDbId = root.argument.dbId || root.argument.db_id || root.argument.name
                                    const padHostIp = root.argument.hostIp || root.argument.ip
                                    if(!padHostIp || !padDbId){
                                        showError(qsTr("缺少云机必要信息，无法执行一键新机"))
                                        return
                                    }

                                    oneKeyNewDevicePopup.modelData = {
                                        name: root.argument.name || padDbId,
                                        displayName: padDisplayName,
                                        hostIp: padHostIp,
                                        hostId: root.argument.hostId || root.argument.host_id || "",
                                        dbId: padDbId,
                                        image: (root.argument.image || "").split(":")[0],
                                        aospVersion: root.argument.aospVersion || ""
                                    }
                                    oneKeyNewDevicePopup.open()
                                }else if(modelData.name === "change_machine"){

                                    dialog.title = qsTr("操作确认")
                                    dialog.message = qsTr("当前云机换机后，将会清空云机全部数据，无法恢复，确定进行换机？")
                                    dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                    dialog.negativeText = qsTr("取消")
                                    dialog.positiveText = qsTr("确定")
                                    dialog.onPositiveClickListener = function(){
                                        FluEventBus.post("reqBatchExchange", {equipmentId: root.argument.equipmentId})
                                        dialog.close()
                                        FluRouter.removeWindow(root)
                                    }
                                    dialog.open()
                                    // ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "reset"})
                                }else if(modelData.name === "reset"){

                                    dialog.title = qsTr("操作确认")
                                    dialog.message = qsTr("确定要关闭云手机吗？")
                                    dialog.buttonFlags = FluContentDialogType.PositiveButton | FluContentDialogType.NegativeButton
                                    dialog.negativeText = qsTr("取消")
                                    dialog.positiveText = qsTr("确定")
                                    dialog.onPositiveClickListener = function(){
                                        const padName = root.argument.name || root.argument.displayName
                                        reqStopDevice(root.argument.hostIp, [padName])
                                        dialog.close()
                                        FluRouter.removeWindow(root)
                                    }
                                    dialog.open()
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "stop"})
                                }else if(modelData.name === "clipboard"){
                                    FluRouter.navigate("/clipboard", {control: client})
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "clipboard"})
                                }else if(modelData.name === "share"){
                                    sharePopup.padInfo = root.argument
                                    sharePopup.open()
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "share"})
                                }else if(modelData.name === "screenshot_remote"){
                                    if(root.deviceSerial){
                                        deviceManager.screenshot(root.deviceSerial)
                                    }
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "screenshot_remote"})
                                }else if(modelData.name === "screenshot_local"){
                                    if(root.deviceSerial){
                                        deviceManager.screenshot(root.deviceSerial)
                                    }
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "screenshot_local"})
                                }else if(modelData.name === "screenshot_dir"){
                                    // 截图目录改为使用 vmosedge 目录
                                    const downloadPath = StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/vmosedge"
                                    Qt.openUrlExternally(downloadPath)
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "screenshot_dir"})
                                }else if(modelData.name === "keymap"){
                                    const realWidth = root.width - spaceWidth
                                    spaceWidth = 240
                                    root.width = realWidth + spaceWidth
                                    layoutTool.visible = false
                                    layoutExtra.visible = true
                                    stackLayoutExtra.currentIndex = 2
                                    maskRect.visible = true
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "keymap"})
                                }else if(modelData.name === "keyboard"){

                                }else if(modelData.name === "adb"){
                                    const realWidth = root.width - spaceWidth
                                    spaceWidth = 240
                                    root.width = realWidth + spaceWidth
                                    layoutTool.visible = false
                                    layoutExtra.visible = true
                                    stackLayoutExtra.currentIndex = 1
                                    // 查询ADB信息
                                    reqCheckADB(root.argument.padCode)
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "adb"})
                                }else if(modelData.name === "blow"){
                                    client.enableBlow(true)
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "blow"})
                                }else if(modelData.name === "shake"){
                                    client.shake()
                                    ReportHelper.reportLog("phone_play_action", root.argument.padCode, {label: "shake"})
                                }else if(modelData.name === "more"){

                                }
                            }
                    }
                }
            }

            Rectangle{
                id: layoutExtra
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                color: "#FF0B2F52"
                visible: false

                ColumnLayout{
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 1

                    RowLayout{
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40

                        Item{
                            id: btnExtraReturn
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 40

                            RowLayout{
                                anchors.fill: parent

                                Image{
                                    source: "qrc:/res/pad/btn_hide_normal.png"
                                }

                                FluText{
                                    text: qsTr("返回")
                                    color: "white"
                                }

                                Item{
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea{
                                anchors.fill: parent

                                onClicked: {
                                    const realWidth = root.width - spaceWidth
                                    spaceWidth = 40
                                    root.width = realWidth + spaceWidth
                                    layoutTool.visible = true
                                    layoutExtra.visible = false
                                    maskRect.visible = false
                                }
                            }
                        }

                        Item{
                            Layout.fillWidth: true
                        }
                    }

                    StackLayout{
                        id: stackLayoutExtra
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: 0

                        // adb
                        Item{

                            ColumnLayout{
                                anchors.fill: parent
                                spacing: 10

                                RowLayout{
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    FluText{
                                        text: qsTr("连接命令")
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: "white"
                                    }

                                    Item{
                                        Layout.fillWidth: true
                                    }

                                    TextButtonEx{
                                        text: qsTr("复制")
                                        textColor: "#FF30BF8F"
                                        onClicked: {
                                            FluTools.clipText(textCmd.text)
                                            showSuccess(qsTr("已复制到剪贴板"))
                                        }
                                    }
                                }
                                FluText{
                                    id: textCmd
                                    Layout.preferredWidth: 220
                                    text: "未开启"
                                    wrapMode: Text.WrapAnywhere
                                    color: "white"
                                }
                                RowLayout{
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    FluText{
                                        text: qsTr("连接密钥")
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: "white"
                                    }

                                    Item{
                                        Layout.fillWidth: true
                                    }

                                    TextButtonEx{
                                        text: qsTr("复制")
                                        textColor: "#FF30BF8F"
                                        onClicked: {
                                            FluTools.clipText(textPass.text)
                                            showSuccess(qsTr("已复制到剪贴板"))
                                        }
                                    }
                                }

                                FluText{
                                    id: textPass
                                    Layout.preferredWidth: 220
                                    text: "未开启"
                                    wrapMode: Text.WrapAnywhere
                                    color: "white"
                                }

                                RowLayout{
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    FluText{
                                        text: qsTr("ADB地址")
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: "white"
                                    }

                                    Item{
                                        Layout.fillWidth: true
                                    }

                                    TextButtonEx{
                                        text: qsTr("复制")
                                        textColor: "#FF30BF8F"
                                        onClicked: {
                                            FluTools.clipText(textADB.text)
                                            showSuccess(qsTr("已复制到剪贴板"))
                                        }
                                    }
                                }

                                FluText{
                                    id: textADB
                                    text: "未开启"
                                    wrapMode: Text.WrapAnywhere
                                    color: "white"
                                }

                                FluText{
                                    text: qsTr("ADB过期时间")
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: "white"
                                }
                                FluText{
                                    id: textADBExpireTime
                                    text: "未开启"
                                    color: "white"
                                }

                                RowLayout{
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    FluText{
                                        text: qsTr("开启ADB")
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: "white"
                                    }

                                    Item{
                                        Layout.fillWidth: true
                                    }

                                    FluToggleSwitch{
                                        id: btnADBSwitch
                                        onClicked: {
                                            reqOpenADB(root.argument.padCode, checked)
                                        }
                                    }
                                }
                                Item{
                                    Layout.fillHeight: true
                                }
                            }
                        }
                        // 键盘映射
                        Item{

                            ColumnLayout{
                                anchors.fill: parent
                                spacing: 10

                                Rectangle{
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    radius: 8
                                    color: "#EFF3FF"

                                    RowLayout{
                                        anchors.fill: parent
                                        anchors.margins: 8

                                        Image{
                                            source: "qrc:/res/pad/btn_onekey.png"
                                        }

                                        ColumnLayout{

                                            FluText{
                                                text: qsTr("新增按键")
                                            }

                                            FluText{
                                                text: qsTr("使用“鼠标左键”新增按键")
                                                wrapMode: Text.WordWrap
                                                Layout.maximumWidth: 140
                                                color: "#637199"
                                                font.pixelSize: 10
                                            }
                                        }
                                    }

                                    MouseArea{
                                        anchors.fill: parent
                                        onClicked: {
                                            keymapperModel.addItem(2, "J")
                                        }
                                    }
                                }


                                Rectangle{
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    radius: 8
                                    color: "#EFF3FF"

                                    RowLayout{
                                        anchors.fill: parent
                                        anchors.margins: 8

                                        Image{
                                            source: "qrc:/res/pad/btn_joystick.png"
                                        }

                                        ColumnLayout{

                                            FluText{
                                                text: qsTr("方向摇杆")
                                            }

                                            FluText{
                                                text: qsTr("使用“AWSD”控制人物移动")
                                                wrapMode: Text.WordWrap
                                                Layout.maximumWidth: 140
                                                color: "#637199"
                                                font.pixelSize: 10
                                            }
                                        }
                                    }

                                    MouseArea{
                                        anchors.fill: parent
                                        onClicked: {
                                            keymapperModel.addItem(1, "W|S|A|D")
                                        }
                                    }
                                }

                                RowLayout{
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    FluText{
                                        text: qsTr("键盘映射开关")
                                        // font.pixelSize: 16
                                        // font.bold: true
                                        color: "white"
                                    }

                                    Item{
                                        Layout.fillWidth: true
                                    }

                                    FluToggleSwitch{
                                        checked: 1 == SettingsHelper.get("keymap", 0)
                                        onClicked: {
                                            SettingsHelper.save("keymap", checked ? 1 : 0)
                                        }
                                    }
                                }

                                // 底部按钮栏
                                RowLayout {
                                    Layout.topMargin: 24
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 20

                                    TextButton{
                                        Layout.preferredHeight: 40
                                        Layout.fillWidth: true
                                        backgroundColor: "lightgray"
                                        borderRadius: 4
                                        textColor: "black"
                                        text: qsTr("还原")
                                        onClicked: {
                                            keymapperModel.loadConfig()
                                        }
                                    }

                                    TextButton{
                                        Layout.preferredHeight: 40
                                        Layout.fillWidth: true
                                        borderRadius: 4
                                        textColor: "white"
                                        backgroundColor: ThemeUI.primaryColor
                                        text: qsTr("保存")
                                        onClicked: {
                                            keymapperModel.saveConfig()

                                            const realWidth = root.width - spaceWidth
                                            spaceWidth = 40
                                            root.width = realWidth + spaceWidth
                                            layoutTool.visible = true
                                            layoutExtra.visible = false
                                            maskRect.visible = false
                                        }
                                    }
                                }

                                Item{
                                    Layout.fillHeight: true
                                }
                            }

                        }
                    }
                }
            }

        }
    }

    NetworkCallable {
        id: checkADB
        onError:
            (status, errorString, result) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            result => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    if(res.data){
                        btnADBSwitch.checked = !!res.data?.enable
                        textCmd.text = res.data?.command
                        textPass.text = res.data.key
                        textADB.text = res.data.adb
                        textADBExpireTime.text = res.data.expireTime
                    }else{
                        btnADBSwitch.checked = false
                        textCmd.text = qsTr("未开启")
                        textPass.text = qsTr("未开启")
                        textADB.text = qsTr("未开启")
                        textADBExpireTime.text = qsTr("未开启")
                    }
                }else{
                    showError(res.msg)
                }
            }
    }
    // 查询ADB状态
    function reqCheckADB(padCode){
        Network.postJson(AppConfig.apiHost + "/userEquipment/padAdb")
        .add("padCode", padCode)
        .add("enabled", true)
        .bind(root)
        .go(checkADB)
    }

    NetworkCallable {
        id: openADB
        onError:
            (status, errorString, result) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            result => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    reqCheckADB(root.argument.padCode)
                }else{
                    showError(res.msg)
                }
            }
    }

    // 打开ADB
    function reqOpenADB(padCode, isOpen){
        Network.postJson(AppConfig.apiHost + "/userEquipment/openOnlineAdb")
        .add("padCode", padCode)
        .add("enabled", isOpen)
        .bind(root)
        .go(openADB)
    }

    NetworkCallable {
        id: videoFileList
        onError:
            (status, errorString, result) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            result => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    videoFileListModel = res.data
                }else{
                    showError(res.msg)
                }
            }
    }

    // 获取云空间视频文件
    function reqVideoFileList(){
        Network.postJson(AppConfig.apiHost + "/cloudFile/selectFilesByUserId?operType=2&fileType=6")
        .bind(root)
        .go(videoFileList)
    }

    NetworkCallable {
        id: deletevideoFile
        onError:
            (status, errorString, result) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            result => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    reqVideoFileList()
                }else{
                    showError(res.msg)
                }
            }
    }

    // 删除云空间视频文件
    function reqDeleteVideoFile(fileId){
        Network.postBody(AppConfig.apiHost + "/cloudFile/deleteUploadFiles")
        .setBody(JSON.stringify([fileId]))
        .bind(root)
        .go(deletevideoFile)
    }

    NetworkCallable {
        id: stsToken
        onError:
            (status, errorString, result) => {
                console.debug(status + ";" + errorString + ";" + result)
                showError(errorString)
            }
        onSuccess:
            result => {
                var res = JSON.parse(result)
                if(res.code === 200){
                    const token = res.data.token
                    root.start(token)
                }else{
                    dialog.title = qsTr("系统提示")
                    dialog.message = res.msg
                    dialog.buttonFlags = FluContentDialogType.PositiveButton
                    dialog.positiveText = qsTr("确定")
                    dialog.onPositiveClickListener = function(){
                        root.close()
                        dialog.close()
                    }
                    dialog.open()
                }
            }
    }

    // 获取token
    function reqStsToken(supplierType, equipmentId){
        Network.get(AppConfig.apiHost + `/padManage/getStsToken?supplierType=${supplierType}&equipmentId=${equipmentId}`)
        .bind(root)
        .go(stsToken)
    }

    NetworkCallable {
        id: installApk
        onStart: {
            showLoading(qsTr("安装中..."))
        }
        onFinish: {
            hideLoading()
        }
        onError: (status, errorString, result, userData) => {
            console.error("APK安装失败，状态:", status, "错误信息:", errorString)
            showError(qsTr("安装失败") + ": " + errorString)
        }
        onSuccess: (result, userData) => {
            console.log("APK安装成功，返回结果:", result)
            const res = JSON.parse(result)
            if(res.code === 200){
               if (Array.isArray(res.data.list)) {
                   var errString = ""
                   for (let i = 0; i < res.data.list.length; i++) {
                       var item = res.data.list[i]
                       var info = qsTr("%1:%2").arg(item.db_id).arg(item.msg)
                       if ("0" === item.code) {
                           errString += info + "\n"
                       }
                   }

                   if ("" === errString) {
                       showSuccess(qsTr("安装成功"))
                   } else {
                       showError(errString)
                   }
               } else {
                   showError(res.msg)
               }
            } else {
                showError(res.msg || qsTr("安装失败"))
            }
        }
        onUploadProgress: (sent, total) => {
            const progress = Math.round((sent / total) * 100)
            console.log("APK安装进度:", progress + "%", sent, "/", total)
        }
    }
    
    NetworkCallable {
        id: installXapk
        onStart: {
            showLoading(qsTr("XAPK安装中..."))
        }
        onFinish: {
            hideLoading()
        }
        onError: (status, errorString, result, userData) => {
            console.error("XAPK安装失败，状态:", status, "错误信息:", errorString)
            showError(qsTr("XAPK安装失败") + ": " + errorString)
        }
        onSuccess: (result, userData) => {
            console.log("XAPK安装成功，返回结果:", result)
            const res = JSON.parse(result)
            if(res.code === 200){
                showSuccess(qsTr("XAPK安装成功"))
            } else {
                showError(res.msg || qsTr("XAPK安装失败"))
            }
        }
        onUploadProgress: (sent, total) => {
            const progress = Math.round((sent / total) * 100)
            console.log("XAPK安装进度:", progress + "%", sent, "/", total)
        }
    }
    
    NetworkCallable {
        id: uploadFile
        onStart: {
            showLoading(qsTr("文件上传中..."))
        }
        onFinish: {
            hideLoading()
        }
        onError: (status, errorString, result, userData) => {
            console.error("文件上传失败，状态:", status, "错误信息:", errorString)
            showError(qsTr("文件上传失败") + ": " + errorString)
        }
        onSuccess: (result, userData) => {
            console.log("文件上传成功，返回结果:", result)
            // 检查返回结果是否为空或无效
            if (!result || result.trim() === "") {
                // 返回结果为空，通常表示上传成功（某些接口可能不返回内容）
                console.log("文件上传成功（返回结果为空，视为成功）")
                showSuccess(qsTr("文件上传成功"))
                return
            }
            // 尝试解析 JSON
            try {
                const res = JSON.parse(result)
                if(res.code === 200){
                    showSuccess(qsTr("文件上传成功"))
                } else {
                    showError(res.msg || qsTr("文件上传失败"))
                }
            } catch(e) {
                // JSON 解析失败，但上传进度已到 100%，通常表示上传成功
                console.warn("文件上传返回结果无法解析为 JSON，但上传进度已到 100%，视为成功:", e)
                showSuccess(qsTr("文件上传成功"))
            }
        }
        onUploadProgress: (sent, total) => {
            const progress = Math.round((sent / total) * 100)
            console.log("文件上传进度:", progress + "%", sent, "/", total)
        }
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
                    showSuccess(qsTr("重启云机成功"))
                    // 重启后可能需要关闭窗口或重新连接
                    FluRouter.removeWindow(root)
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
                    showSuccess(qsTr("关闭云机成功"))
                    // 关闭后需要关闭窗口
                    FluRouter.removeWindow(root)
                }else{
                    showError(res.msg)
                }
            }
    }

    // 关闭云机
    function reqStopDevice(ip, padNames){
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/stop")
        .addList("db_ids", padNames)
        .bind(root)
        .setUserData(ip)
        .go(stopDevice)
    }

    NetworkCallable {
        id: oneKeyNewDevice
        onStart: {
            showLoading(qsTr("正在一键新机..."))
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
                    showSuccess(qsTr("一键新机成功"))
                    // 新机后需要关闭窗口
                    FluRouter.removeWindow(root)
                }else{
                    showError(res.msg)
                }
            }
    }

    // 一键新机
    function reqOneKeyNewDevice(ip, padNames, adiName, adiPass, wipeData){
        if(!ip){
            showError(qsTr("缺少主机IP，无法执行一键新机"))
            return
        }
        if(!padNames){
            showError(qsTr("未指定云机，无法执行一键新机"))
            return
        }
        const dbIdList = Array.isArray(padNames) ? padNames : [padNames]
        Network.postJson(`http://${ip}:18182/container_api/v1` + "/replace_devinfo")
        .addList("db_ids", dbIdList)
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


    // 从本地存储加载位置信息
    function loadIpInfoFromStorage() {
        var saved = SettingsHelper.get("ipInfo_called", false)
        if (saved) {
            root.lon = SettingsHelper.get("ipInfo_lon", 0.0)
            root.lat = SettingsHelper.get("ipInfo_lat", 0.0)
            root.deviceLocale = SettingsHelper.get("ipInfo_deviceLocale", "en-US")
            root.timezone = SettingsHelper.get("ipInfo_timezone", "UTC")
            console.log("从本地存储加载IP信息 - lon:", root.lon, "lat:", root.lat, "locale:", root.deviceLocale, "timezone:", root.timezone)
        } else {
            // 如果没有保存的数据，使用默认值
            root.lon = 0.0
            root.lat = 0.0
            root.deviceLocale = "en-US"
            root.timezone = "UTC"
            console.log("本地存储中没有IP信息，使用默认值")
        }
    }
    
    NetworkCallable {
        id: videoInject
        property string pendingRtspUrl: ""  // 保存待注入的RTSP URL
        onError:
            (status, errorString, result) => {
                console.debug("视频注入错误: " + status + ";" + errorString + ";" + result)
                // 检查是否是"视频注入中"的错误
                try {
                    var res = JSON.parse(result)
                    console.log("视频注入错误响应:", res)
                    if(res.message && res.message.indexOf("视频注入中") >= 0){
                        // 如果返回"视频注入中"的错误，先关闭注入，然后再开启
                        const urlToRetry = pendingRtspUrl
                        pendingRtspUrl = ""
                        console.log("检测到视频注入中，先关闭注入，然后再开启，URL:", urlToRetry)
                        if(urlToRetry && urlToRetry.length > 0){
                            reqVideoInjectOffAndThenInject(urlToRetry)
                        }
                        return
                    }
                } catch(e) {
                    // 解析失败，忽略
                    console.warn("解析错误响应失败:", e)
                }
                console.warn("发送RTSP地址到CBS失败:", errorString)
                pendingRtspUrl = ""
            }
        onSuccess:
            (result) => {
                console.log("RTSP地址已成功发送到CBS:", result)
                try {
                    var res = JSON.parse(result)
                    console.log("视频注入响应:", res)
                    if(res.code === 200 || res.code === 0){
                        console.log("视频注入成功，code:", res.code)
                        // 注入成功，保存状态并更新开关
                        if(videoInjectSwitch){
                            videoInjectSwitch.checked = true
                            windowSizeHelper.save(root.argument.dbId, "videoInject", 1)
                            console.log("视频注入成功，已保存状态并更新开关")
                        }
                    } else {
                        // 检查是否是"视频注入中"的错误
                        if(res.message && res.message.indexOf("视频注入中") >= 0){
                            const urlToRetry = pendingRtspUrl
                            pendingRtspUrl = ""
                            console.log("检测到视频注入中，先关闭注入，然后再开启，URL:", urlToRetry)
                            if(urlToRetry && urlToRetry.length > 0){
                                reqVideoInjectOffAndThenInject(urlToRetry)
                            }
                            return
                        }
                        console.warn("视频注入返回非成功状态，code:", res.code, "message:", res.msg || res.message)
                        // 注入失败，更新开关状态
                        if(videoInjectSwitch){
                            videoInjectSwitch.checked = false
                            windowSizeHelper.save(root.argument.dbId, "videoInject", 0)
                        }
                    }
                } catch(e) {
                    // 如果返回的不是JSON，也认为成功（某些API可能返回空或纯文本）
                    console.log("视频注入请求完成（非JSON响应）")
                    // 假设成功，保存状态并更新开关
                    if(videoInjectSwitch){
                        videoInjectSwitch.checked = true
                        windowSizeHelper.save(root.argument.dbId, "videoInject", 1)
                    }
                }
                // 清空待注入的URL
                pendingRtspUrl = ""
            }
    }

    // 发送RTSP地址到CBS进行视频注入
    function reqVideoInject(rtspUrl){
        console.log("reqVideoInject 被调用，rtspUrl:", rtspUrl)
        if(!rtspUrl || rtspUrl.length === 0){
            console.warn("RTSP URL为空，无法发送到CBS")
            return
        }
        
        const hostIp = root.argument.hostIp
        if(!hostIp){
            console.warn("hostIp为空，无法发送RTSP地址到CBS")
            return
        }
        
        // 保存待注入的URL，以便在错误处理中使用
        videoInject.pendingRtspUrl = rtspUrl
        
        const apiUrl = `http://${hostIp}:18182/android_api/v1/video_inject/${root.argument.dbId}`
        console.log("发送RTSP地址到CBS:", apiUrl, "URL:", rtspUrl)
        
        Network.postJson(apiUrl)
        .add("url", rtspUrl)
        .bind(root)
        .go(videoInject)
    }
    
    // 用于先关闭注入再开启注入的 NetworkCallable
    NetworkCallable {
        id: videoInjectOffAndThenInject
        property string pendingRtspUrl: ""  // 保存待注入的RTSP URL
        
        onError:
            (status, errorString, result) => {
                console.warn("关闭注入失败，但仍尝试开启注入:", errorString)
                // 即使关闭失败，也尝试开启注入
                const urlToInject = pendingRtspUrl  // 保存到局部变量，避免闭包问题
                pendingRtspUrl = ""  // 先清空
                if(urlToInject && urlToInject.length > 0){
                    console.log("关闭注入失败后，尝试开启注入，URL:", urlToInject)
                    Qt.callLater(function() {
                        reqVideoInject(urlToInject)
                    })
                } else {
                    console.warn("待注入的RTSP URL为空")
                }
            }
        onSuccess:
            (result) => {
                console.log("关闭注入成功，现在开启注入")
                try {
                    var res = JSON.parse(result)
                    console.log("关闭注入接口返回:", res)
                } catch(e) {
                    console.log("关闭注入接口返回（非JSON）:", result)
                }
                // 延迟一小段时间，确保关闭操作完成
                const urlToInject = pendingRtspUrl  // 保存到局部变量，避免闭包问题
                pendingRtspUrl = ""  // 先清空
                if(urlToInject && urlToInject.length > 0){
                    console.log("关闭注入成功后，开启注入，URL:", urlToInject)
                    // 延迟一下，确保关闭操作完全完成
                    Qt.callLater(function() {
                        Qt.callLater(function() {
                            reqVideoInject(urlToInject)
                        })
                    })
                } else {
                    console.warn("待注入的RTSP URL为空")
                }
            }
    }
    
    // 先关闭注入，然后再开启注入（用于处理"视频注入中"的情况）
    function reqVideoInjectOffAndThenInject(rtspUrl){
        if(!rtspUrl || rtspUrl.length === 0){
            console.warn("RTSP URL为空，无法发送到CBS")
            return
        }
        
        const hostIp = root.argument.hostIp
        if(!hostIp){
            console.warn("hostIp为空，无法发送RTSP地址到CBS")
            return
        }
        
        console.log("先关闭注入，然后再开启注入")
        
        // 保存待注入的URL
        videoInjectOffAndThenInject.pendingRtspUrl = rtspUrl
        
        // 先关闭注入
        const apiUrlOff = `http://${hostIp}:18182/android_api/v1/video_inject_off/${root.argument.dbId}`
        Network.get(apiUrlOff)
        .bind(root)
        .go(videoInjectOffAndThenInject)
    }
    
    NetworkCallable {
        id: videoInjectOff
        onError:
            (status, errorString, result) => {
                console.debug("取消视频注入错误: " + status + ";" + errorString + ";" + result)
                // 不显示错误提示，避免干扰用户体验
                console.warn("取消视频注入失败:", errorString)
            }
        onSuccess:
            (result) => {
                console.log("取消视频注入成功:", result)
                try {
                    var res = JSON.parse(result)
                    if(res.code === 200 || res.code === 0){
                        console.log("取消视频注入成功")
                        // 取消注入成功，保存状态并更新开关
                        if(videoInjectSwitch){
                            videoInjectSwitch.checked = false
                            windowSizeHelper.save(root.argument.dbId, "videoInject", 0)
                            console.log("取消视频注入成功，已保存状态并更新开关")
                        }
                    } else {
                        console.warn("取消视频注入返回非成功状态:", res.msg || res.message)
                    }
                } catch(e) {
                    // 如果返回的不是JSON，也认为成功（某些API可能返回空或纯文本）
                    console.log("取消视频注入请求完成")
                    // 假设成功，保存状态并更新开关
                    if(videoInjectSwitch){
                        videoInjectSwitch.checked = false
                        windowSizeHelper.save(root.argument.dbId, "videoInject", 0)
                    }
                }
            }
    }

    // 取消视频注入
    function reqVideoInjectOff(){
        const hostIp = root.argument.hostIp
        if(!hostIp){
            console.warn("hostIp为空，无法取消视频注入")
            return
        }
        
        const apiUrl = `http://${hostIp}:18182/android_api/v1/video_inject_off/${root.argument.dbId}`
        console.log("取消视频注入:", apiUrl)
        
        Network.get(apiUrl)
        .bind(root)
        .go(videoInjectOff)
    }
    
    // 监听推流状态变化，恢复视频注入开关状态
    Connections {
        target: cameraStreamManager
        function onStreamingStarted() {
            console.log("摄像头推流已开始，RTSP URL:", cameraStreamManager.rtspUrl)
            // 推流开始时，如果之前保存的状态是开启的，恢复开关状态（但不自动注入，因为可能已经在注入了）
            if(videoInjectSwitch && cameraStreamManager.rtspUrl){
                const savedVideoInject = windowSizeHelper.get(root.argument.dbId, "videoInject", 0)
                if(savedVideoInject === 1){
                    videoInjectSwitch.checked = true
                    console.log("推流开始，恢复视频注入开关状态：开启")
                }
            }
        }
        function onStreamingStopped() {
            console.log("摄像头推流已停止")
            // 推流停止时，关闭开关
            if(videoInjectSwitch){
                videoInjectSwitch.checked = false
                // 保存状态
                windowSizeHelper.save(root.argument.dbId, "videoInject", 0)
            }
        }
        function onErrorOccurred(error) {
            console.error("摄像头推流错误:", error)
            // 推流错误时，关闭开关
            if(videoInjectSwitch){
                videoInjectSwitch.checked = false
                // 保存状态
                windowSizeHelper.save(root.argument.dbId, "videoInject", 0)
            }
        }
    }
    
}
