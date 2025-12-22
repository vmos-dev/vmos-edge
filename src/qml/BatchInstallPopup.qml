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
    property var tobeInstallList:{"":[]}     //  记录选中的主机：云机
    property bool runStatus: false // 空闲
    property var selectedApkList: [] // 选中的文件，执行安装后删除
    property int compCounts: 0
    property int failedCounts: 0

    //  自定义数据
    ListModel {
        id: customModel
        readonly property int statPending: 0
        readonly property int statProgress: 1
        readonly property int statCompleted: 2
        readonly property int statFailed: 3
        function addItem(name, progress, status) {
            append({"name": name, "progress": progress, "status": status, "count": 0, "failed": 0})
        }

        function removeItem(index) {
            remove(index)
        }

        function modifyItem(index, progress, status) {
            if (index >= 0 && index < count) {
                if (progress > get(index).progress) {
                    get(index).progress = progress
                    console.log("index item = ", index, " progress = ", progress)
                }

                if (statCompleted === status) {
                    get(index).count++;
                    get(index).status = statCompleted
                } else if (statFailed === status) {
                    get(index).failed++
                    get(index).status = statCompleted
                } else if (status >= get(index).status)
                {
                    get(index).status = status
                }

                // 触发视图更新
                set(index, get(index))
            }
        }

        function findItem(name) {
            for (let i = 0; i < count; i++) {
                if (get(i).name === name) {
                    return i
                }
            }
            return -1
        }
    }

    Timer {
        id: closeTimer
        interval: 2000
        onTriggered: root.close()
    }

    onOpened: {
        runStatus = false
        customModel.clear()
        selectedApkList = []
        compCounts = 0
        failedCounts = 0
    }

    onClosed: {
        runStatus = false
        customModel.clear()
        selectedApkList = []
    }

    function appendApkFile(file) {
        if (customModel.findItem(file) >= 0) {
            showError(qsTr("[%1] 已存在, 不可重复添加").arg(file))
            return
        }

        btnInstall.enabled = true
        selectedApkList.push(file)
        customModel.addItem(file, 0, customModel.statPending)
    }

    //  尝试退出窗口，若安装正在进行，弹出提示框
    function tryClose() {
        if (!root.runStatus) {
            root.close()
        }
        else {
            showInfo(qsTr("正在安装应用，请稍后..."))
        }
    }

    FileDialog {
        id: fileDialog
        title: qsTr("选择安装包")
        fileMode: FileDialog.OpenFiles
        nameFilters: [ "APK/XAPK (*.apk *.xapk)" ]
        onAccepted: {
            fileDialog.files.forEach(
                        item => {
                            const localPath = FluTools.toLocalPath(item)
                            console.log("select file ", localPath)
                            appendApkFile(localPath)
                        })
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                event.accepted = true
                tryClose()
            }
        }

        //  标题栏
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.leftMargin: 20

            FluText {
                text: {
                    let groupCount = 0;
                    let devCount = 0;
                    for (const key in tobeInstallList) {
                        const devList = tobeInstallList[key];
                        groupCount++;
                        devCount+= devList.length;
                    }
                    return qsTr("批量安装（主机数量：%1，云机数量：%2）").arg(groupCount).arg(devCount)
                }
                font.bold: true
                font.pixelSize: 16
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                width: Math.min(implicitWidth, parent.width * 0.9)
            }
        }

        //  选择文件
        RowLayout {
            Layout.leftMargin: 20
            spacing: 20
            FluText {
                text: qsTr("选择安装包")
                font.pixelSize: 16
            }

            Rectangle {
                Layout.preferredWidth: 400
                Layout.preferredHeight: 180
                border.color: "#409EFF"
                border.width: 1
                radius: 4

                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    anchors.centerIn: parent
                    spacing: 12

                    Item {
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: 200
                    }

                    Item {
                        Layout.alignment: Qt.AlignCenter
                        Layout.preferredHeight: 50
                        Layout.preferredWidth: 300

                        FluFilledButton {
                            anchors.centerIn: parent
                            enabled: !runStatus
                            text: qsTr("拖拽文件到此处或点击上传")
                            Layout.preferredWidth: 300
                            normalColor: ThemeUI.blueColor
                            onClicked: fileDialog.open()
                        }
                    }

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: 200

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("仅支持.apk .xapk文件")
                            font.pixelSize: 14
                            color: "#666666"
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent
                    enabled: !runStatus
                    onDropped: (drop) => {
                                   if (drop.hasUrls && drop.urls.length > 0) {
                                        drop.urls.forEach(url => {
                                            var localPath = FluTools.toLocalPath(url)
                                            if (localPath.endsWith('.apk') || localPath.endsWith('.xapk')) {
                                                console.log("Dropped file:", localPath)
                                                appendApkFile(localPath)
                                            } else {
                                                console.log("Invalid file type dropped:", localPath)
                                                showError(qsTr("无效的文件 [%1], 仅支持导入 .apk .xapk 格式文件").arg(localPath))
                                            }
                                        })
                                    }
                    }
                }
            }
        }

        //  文件列表
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(200, customModel.count * 50) // 动态计算高度
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            ListView {
                id: listView
                Layout.fillHeight: true
                Layout.fillWidth: true
                spacing: 2
                model: customModel
                ScrollBar.vertical: ScrollBar { }

                delegate: Rectangle {
                    width: listView.width
                    height: 50
                    color: index % 2 === 0 ? "#f8f9fa" : "#ffffff"
                    border.color: "#dee2e6"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        anchors.rightMargin: 15

                        Item {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 32
                            Image {
                                source: "qrc:/res/pad/pad_file.png"
                                anchors.centerIn: parent
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            FluText {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                text: model.name                //  文件名
                                font.pixelSize: 14
                                elide: Text.ElideLeft
                                wrapMode: Text.NoWrap
                                width: Math.min(implicitWidth, progressItem.visible ? 200 : 400)
                            }
                        }

                        Item {
                            id: progressItem
                            Layout.fillHeight: true
                            Layout.preferredWidth: 180
                            visible: model.progress > 0

                            FluProgressBar {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                width: parent.width
                                from: 0
                                to: 100
                                indeterminate: false
                                value: model.progress
                                visible: model.progress > 0
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 80
                            visible: model.status !== customModel.statPending

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                text: {
                                    switch(model.status) {
                                        case customModel.statPending: return "Pending"
                                        case customModel.statProgress: {
                                            if (model.progress < 100) {
                                                return model.progress + "%"
                                            }
                                            else
                                            {
                                                return qsTr("正在安装")
                                            }
                                        }
                                        case customModel.statCompleted: {
                                            return qsTr("%1/%2").arg(model.count).arg(Object.keys(root.tobeInstallList).length)
                                        }

                                        default: return "Unknown"
                                    }
                                }

                                font.pixelSize: 14
                                color: {
                                    switch(model.status) {
                                        case customModel.statPending: return "gray"
                                        case customModel.statProgress: return "blue"
                                        case customModel.statCompleted: return model.failed === 0 ? "green" : "red"
                                        case customModel.statFailed: return "red"
                                        default: return "black"
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 40
                            visible: model.status === customModel.statPending

                            Image {
                                id: delFile
                                anchors.centerIn: parent
                                source: "qrc:/res/pad/delete_normal@1.5x.png"
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.runStatus
                                hoverEnabled: true // 启用悬停事件
                                onEntered: {
                                    delFile.source = "qrc:/res/pad/btn_delete_video@1.5x.png"
                                }
                                onExited: {
                                    delFile.source = "qrc:/res/pad/delete_normal@1.5x.png"
                                }

                                onClicked: {
                                    for (let i = 0; i < selectedApkList.length; i++) {
                                        if (selectedApkList[i] === model.name) {
                                            selectedApkList.splice(i, 1);
                                            console.log(model.name, "已删除");
                                            break;
                                        }
                                    }

                                    if (selectedApkList.length === 0) {
                                        btnInstall.enabled = false
                                    }

                                    let index = customModel.findItem(model.name)
                                    customModel.removeItem(index)
                                }
                            }
                        }
                    }
                }
            }
        }

        //  最下方按钮
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            spacing: 60

            Item { Layout.fillWidth: true }

            FluButton {
                text: qsTr("取消")
                Layout.preferredWidth: 180
                normalColor: ThemeUI.grayColor
                onClicked: tryClose()
            }

            Item { Layout.fillWidth: true }

            FluFilledButton {
                id: btnInstall
                text: qsTr("一键安装")
                Layout.preferredWidth: 180
                normalColor: ThemeUI.blueColor
                enabled: false
                onClicked: {
                    runStatus = true
                    btnInstall.enabled = false
                    for (const deviceIp in root.tobeInstallList) {
                        let dev_ids = "";
                        const deviceList = root.tobeInstallList[deviceIp]
                        for (const dev in deviceList)
                        {
                            dev_ids += deviceList[dev]
                            dev_ids += ","
                        }

                        const callable = networkCallableComponent.createObject(concurrent)
                        callable.hostIp = deviceIp
                        for (let i = 0; i < selectedApkList.length; i++) {
                            callable.filelist.push(selectedApkList[i]);
                        }
                        callable.devlist = dev_ids
                        concurrent.batchInstall(callable)
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        //  并行安装
        Item {
            id: concurrent
            // 定义NetworkCallable组件
            Component {
                id: networkCallableComponent
                NetworkCallable {
                    property string hostIp: ""
                    property var filelist: []
                    property var devlist: []
                    property string currfile: ""

                    onSuccess: (result, userData) => {
                                   var res = JSON.parse(result)
                                   if(res.code === 200) {
                                       if (Array.isArray(res.data.list)) {
                                           var errString = ""
                                           for (let i = 0; i < res.data.list.length; i++) {
                                               var item = res.data.list[i]
                                               var info = qsTr("%1:%2").arg(item.db_id).arg(item.msg)
                                               console.log("item.code =", item.code, "hostIp=", hostIp, info)
                                               if ("0" === item.code) {
                                                   errString += info + "\n"
                                               }
                                           }
                                           concurrent.handleFileProgress(hostIp, userData, errString)
                                       } else {
                                           concurrent.handleFileProgress(hostIp, userData, res.msg)
                                       }
                                   }else{
                                       concurrent.handleFileProgress(hostIp, userData, res.msg)
                                   }

                                   if (filelist.length > 0) {
                                       concurrent.batchInstall(this)
                                   }
                    }
                    onError: (status, errorString, result, userData) => {
                                    concurrent.handleFileProgress(hostIp, userData, errorString)
                    }
                    onUploadProgress: (sent, total) => {
                                    concurrent.handleBytesProgress(hostIp, currfile, sent, total)
                    }
                }
            }

            //  批量安装
            function batchInstall(callback) {
                const url = `http://${callback.hostIp}:18182/android_api/v1/upload_file_android_batch`
                callback.currfile = callback.filelist.shift();
                console.log(callback.hostIp, " try install ", callback.currfile, " db_list : ", callback.devlist)
                Network.postForm(url)
                    .add("db_ids", callback.devlist)
                    .addFile("file", callback.currfile)
                    .bind(this)
                    .setUserData(callback.currfile)
                    .setTimeout(3600000)
                    .go(callback)
            }

            //  安装完成
            function handleFileProgress(deviceIp, currfile, errinfo) {
                let index = customModel.findItem(currfile);
                if ("" !== errinfo) {
                    showError(qsTr("%1 %2 install failed, %3").arg(deviceIp).arg(currfile).arg(errinfo))
                    customModel.modifyItem(index, 100, customModel.statFailed)
                } else {
                    customModel.modifyItem(index, 100, customModel.statCompleted)
                }

                var model = customModel.get(index)
                if (model.count + model.failed === Object.keys(root.tobeInstallList).length) {
                    //  所有主机已回应
                    if (0 === model.failed) {
                        root.compCounts++
                    } else {
                        root.failedCounts++
                    }

                    //  所有文件已安装完毕
                    if (root.failedCounts + root.compCounts === root.selectedApkList.length) {
                        root.runStatus = false
                        if (root.compCounts === root.selectedApkList.length) {
                            showInfo(qsTr("所有应用安装成功！"))
                            closeTimer.start()          //  所有文件安装成功，自动关闭窗口
                        }
                    }
                }
            }

            //  上传进度
            function handleBytesProgress(deviceIp, currfile, sent, total) {
                let sentPersent = Math.round((sent * 100 / total))
                let index = customModel.findItem(currfile);
                customModel.modifyItem(index, sentPersent, customModel.statProgress)
            }
        }
    }
}
