pragma Singleton

import QtQuick
import FluentUI

QtObject  {
    // 是否测试环境
    property bool develop: false

    // 渠道
    property string channel: channelName ? channelName : "pc"
    // 终端
    property string client: FluTools.isMacos() ? "mac" : FluTools.isLinux() ? "linux" : "win"
    // 版本
    property int versionCode: 100000037
    // 版本

    property string versionName: "1.0.37.4"
    // CBS版本信息
    property string cbsConfigPath: FluTools.getApplicationDirPath() + "/cbs/cbs_config.json"
    property string cbsVersion: "1.0.12.9.2"
    property string cbsFileName: "latest.cbs"
    property string cbsFilePath: FluTools.getApplicationDirPath() + "/cbs/" + cbsFileName

    // 窗口配置
    property var windowSize: [
        {width:480, height:853},
        {width:320, height:568},
        {width:160, height:284}
    ]
    // 视频配置
    property var videoLevel: [
        {resolution: 15,fps: 1,bitrate: 3},
        {resolution: 12,fps: 8,bitrate: 1},
        {resolution: 10,fps: 8,bitrate: 15},
        {resolution: 9,fps: 8,bitrate: 15},
        {resolution: 9,fps: 5,bitrate: 13}
    ]
    // 项目名称
    property string projectName: "vmosedge"

    // 项目标题
    property string projectTitle: "VMOS Edge"
    // 项目图标
    property string projectIcon: "qrc:/res/vmosedge.ico"
    // 颜色配置
    property var deviceColorList: ["", "#141619", "#FF4C4C", "#F49322", "#18CECF", "#30BF8F", "#0079F2", "#7549F2"]
    
    // 连接模式配置：true=TCP直连模式，false=ADB模式
    property bool useDirectTcp: true
}
