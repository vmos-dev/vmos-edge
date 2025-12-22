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

    // 添加属性来存储原始时区和语言
    property string originalTimeZone: ""
    property string originalLocale: ""
    property string originalCountry: ""
    property string selectedTimeZone: ""
    property string selectedLanguageCode: ""
    property string  selectedCountry : ""
    property string selectedCountryInfoCode: ""
    property string selectedCountryInfoName: ""
    property string selectedLanguageCountry: ""
    property bool updatingFromModel: false

    ListModel {
        id: localImagesModel
    }

    property var downloadedImages: []

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
                id: timeTitle
                text: qsTr("修改语言时区")
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

        ColumnLayout {
            width: parent.width
            Layout.margins: 20
            spacing: 15

            RowLayout{
                FluText {
                    text: qsTr("选择国家/地区");
                    font.bold: true
                }
            }

            FluComboBox {
                id: countryComboBox
                Layout.fillWidth: true
                editable: true
                model: CountryListModel {}
                textRole: "countryName"
                onCurrentIndexChanged: {
                    if (currentIndex >= 0) {
                        var item = model.get(currentIndex)
                        selectedCountryInfoName = item.countryName
                        selectedCountryInfoCode = item.countryCode
                        
                        // Linkage logic: Update Language and Timezone based on Country
                        if (!updatingFromModel && selectedCountryInfoCode !== "") {
                            var i;
                            // Update Language
                            for (i = 0; i < languageComboBox.model.count; i++) {
                                if (languageComboBox.model.get(i).country === selectedCountryInfoCode) {
                                    languageComboBox.currentIndex = i;
                                    break;
                                }
                            }
                            
                            // Update Timezone
                            for (i = 0; i < timeZoneComboBox.model.count; i++) {
                                if (timeZoneComboBox.model.get(i).country === selectedCountryInfoCode) {
                                    timeZoneComboBox.currentIndex = i;
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            FluText {
                text: qsTr("选择时区");
                font.bold: true
            }

            FluComboBox {
                id: timeZoneComboBox
                editable: true
                Layout.fillWidth: true
                model: ListModel {
                    ListElement { timeZone: "Europe/London"; displayText: qsTr("格林尼治标准时间 GMT+0（伦敦）"); gmt: "GMT+0"; country: "GB" }
                    ListElement { timeZone: "Europe/Lisbon"; displayText: qsTr("格林尼治标准时间 GMT+0（里斯本）"); gmt: "GMT+0"; country: "PT" }
                    ListElement { timeZone: "Europe/Paris"; displayText: qsTr("中欧时间 GMT+1（巴黎）"); gmt: "GMT+1"; country: "FR" }
                    ListElement { timeZone: "Europe/Berlin"; displayText: qsTr("中欧标准时间 GMT+1（柏林）"); gmt: "GMT+1"; country: "DE" }
                    ListElement { timeZone: "Europe/Helsinki"; displayText: qsTr("东欧时间 GMT+2（赫尔辛基）"); gmt: "GMT+2"; country: "FI" }
                    ListElement { timeZone: "America/New_York"; displayText: qsTr("美国东部时间 GMT-5（纽约）"); gmt: "GMT-5"; country: "US" }
                    ListElement { timeZone: "America/Chicago"; displayText: qsTr("美国中部时间 GMT-6（芝加哥）"); gmt: "GMT-6"; country: "US" }
                    ListElement { timeZone: "America/Denver"; displayText: qsTr("美国山地时间 GMT-7（丹佛）"); gmt: "GMT-7"; country: "US" }
                    ListElement { timeZone: "America/Los_Angeles"; displayText: qsTr("美国太平洋时间 GMT-8（洛杉矶）"); gmt: "GMT-8"; country: "US" }
                    ListElement { timeZone: "America/Anchorage"; displayText: qsTr("阿拉斯加时间 GMT-9（安克雷奇）"); gmt: "GMT-9"; country: "US" }
                    ListElement { timeZone: "Pacific/Honolulu"; displayText: qsTr("夏威夷时间 GMT-10（檀香山）"); gmt: "GMT-10"; country: "US" }
                    ListElement { timeZone: "Asia/Tokyo"; displayText: qsTr("日本标准时间 GMT+9（东京）"); gmt: "GMT+9"; country: "JP" }
                    ListElement { timeZone: "Asia/Shanghai"; displayText: qsTr("中国标准时间 GMT+8（上海）"); gmt: "GMT+8"; country: "CN" }
                    ListElement { timeZone: "Asia/Hong_Kong"; displayText: qsTr("香港时间 GMT+8（香港）"); gmt: "GMT+8"; country: "HK" }
                    ListElement { timeZone: "Asia/Taipei"; displayText: qsTr("台北时间 GMT+8（台北）"); gmt: "GMT+8"; country: "TW" }
                    ListElement { timeZone: "Asia/Seoul"; displayText: qsTr("韩国标准时间 GMT+9（首尔）"); gmt: "GMT+9"; country: "KR" }
                    ListElement { timeZone: "Asia/Kolkata"; displayText: qsTr("印度标准时间 GMT+5:30（孟买）"); gmt: "GMT+5:30"; country: "IN" }
                    ListElement { timeZone: "Australia/Sydney"; displayText: qsTr("澳大利亚东部时间 GMT+11（悉尼）"); gmt: "GMT+11"; country: "AU" }
                    ListElement { timeZone: "Australia/Adelaide"; displayText: qsTr("澳大利亚中部时间 GMT+10:30（阿德莱德）"); gmt: "GMT+10:30"; country: "AU" }
                    ListElement { timeZone: "Australia/Perth"; displayText: qsTr("澳大利亚西部时间 GMT+8（珀斯）"); gmt: "GMT+8"; country: "AU" }
                    ListElement { timeZone: "Pacific/Auckland"; displayText: qsTr("新西兰时间 GMT+13（奥克兰）"); gmt: "GMT+13"; country: "NZ" }
                    ListElement { timeZone: "America/Sao_Paulo"; displayText: qsTr("巴西利亚时间 GMT-3（巴西利亚）"); gmt: "GMT-3"; country: "BR" }
                    ListElement { timeZone: "America/Argentina/Buenos_Aires"; displayText: qsTr("阿根廷时间 GMT-3（布宜诺斯艾利斯）"); gmt: "GMT-3"; country: "AR" }
                    ListElement { timeZone: "America/Toronto"; displayText: qsTr("加拿大东部时间 GMT-5（多伦多）"); gmt: "GMT-5"; country: "CA" }
                    ListElement { timeZone: "America/Halifax"; displayText: qsTr("加拿大大西洋时间 GMT-4（哈利法克斯）"); gmt: "GMT-4"; country: "CA" }
                    ListElement { timeZone: "Europe/Moscow"; displayText: qsTr("莫斯科时间 GMT+3（莫斯科）"); gmt: "GMT+3"; country: "RU" }
                    ListElement { timeZone: "Europe/Istanbul"; displayText: qsTr("土耳其时间 GMT+3（伊斯坦布尔）"); gmt: "GMT+3"; country: "TR" }
                    ListElement { timeZone: "Asia/Jerusalem"; displayText: qsTr("以色列时间 GMT+2（耶路撒冷）"); gmt: "GMT+2"; country: "IL" }
                    ListElement { timeZone: "Asia/Dubai"; displayText: qsTr("阿联酋时间 GMT+4（迪拜）"); gmt: "GMT+4"; country: "AE" }
                    ListElement { timeZone: "Africa/Johannesburg"; displayText: qsTr("南非时间 GMT+2（约翰内斯堡）"); gmt: "GMT+2"; country: "ZA" }
                    ListElement { timeZone: "Africa/Cairo"; displayText: qsTr("埃及时间 GMT+2（开罗）"); gmt: "GMT+2"; country: "EG" }
                    ListElement { timeZone: "Africa/Lagos"; displayText: qsTr("西非时间 GMT+1（拉各斯）"); gmt: "GMT+1"; country: "NG" }
                    ListElement { timeZone: "Asia/Ulaanbaatar"; displayText: qsTr("蒙古时间 GMT+8（乌兰巴托）"); gmt: "GMT+8"; country: "MN" }
                    ListElement { timeZone: "Asia/Jakarta"; displayText: qsTr("印度尼西亚西部时间 GMT+7（雅加达）"); gmt: "GMT+7"; country: "ID" }
                    ListElement { timeZone: "Asia/Manila"; displayText: qsTr("菲律宾时间 GMT+8（马尼拉）"); gmt: "GMT+8"; country: "PH" }
                    ListElement { timeZone: "Asia/Ho_Chi_Minh"; displayText: qsTr("越南时间 GMT+7（胡志明市）"); gmt: "GMT+7"; country: "VN" }
                    ListElement { timeZone: "Asia/Singapore"; displayText: qsTr("新加坡时间 GMT+8（新加坡）"); gmt: "GMT+8"; country: "SG" }
                    ListElement { timeZone: "Asia/Kuala_Lumpur"; displayText: qsTr("马来西亚时间 GMT+8（吉隆坡）"); gmt: "GMT+8"; country: "MY" }
                    ListElement { timeZone: "Asia/Bangkok"; displayText: qsTr("泰国时间 GMT+7（曼谷）"); gmt: "GMT+7"; country: "TH" }
                    ListElement { timeZone: "Asia/Yangon"; displayText: qsTr("缅甸时间 GMT+6:30（仰光）"); gmt: "GMT+6:30"; country: "MM" }
                    ListElement { timeZone: "Asia/Dhaka"; displayText: qsTr("孟加拉时间 GMT+6（达卡）"); gmt: "GMT+6"; country: "BD" }
                    ListElement { timeZone: "Asia/Tashkent"; displayText: qsTr("乌兹别克斯坦时间 GMT+5（塔什干）"); gmt: "GMT+5"; country: "UZ" }
                    ListElement { timeZone: "Asia/Tehran"; displayText: qsTr("伊朗时间 GMT+3:30（德黑兰）"); gmt: "GMT+3:30"; country: "IR" }
                    ListElement { timeZone: "Asia/Baghdad"; displayText: qsTr("伊拉克时间 GMT+3（巴格达）"); gmt: "GMT+3"; country: "IQ" }
                    ListElement { timeZone: "America/Caracas"; displayText: qsTr("委内瑞拉时间 GMT-4（加拉加斯）"); gmt: "GMT-4"; country: "VE" }
                    ListElement { timeZone: "America/Mexico_City"; displayText: qsTr("墨西哥时间 GMT-6（墨西哥城）"); gmt: "GMT-6"; country: "MX" }
                    ListElement { timeZone: "America/Lima"; displayText: qsTr("秘鲁时间 GMT-5（利马）"); gmt: "GMT-5"; country: "PE" }
                    ListElement { timeZone: "America/Bogota"; displayText: qsTr("哥伦比亚时间 GMT-5（波哥大）"); gmt: "GMT-5"; country: "CO" }
                    ListElement { timeZone: "America/Santiago"; displayText: qsTr("智利时间 GMT-3（圣地亚哥）"); gmt: "GMT-3"; country: "CL" }
                    ListElement { timeZone: "America/La_Paz"; displayText: qsTr("玻利维亚时间 GMT-4（拉巴斯）"); gmt: "GMT-4"; country: "BO" }
                    ListElement { timeZone: "America/Costa_Rica"; displayText: qsTr("哥斯达黎加时间 GMT-6（圣何塞）"); gmt: "GMT-6"; country: "CR" }
                    ListElement { timeZone: "America/Havana"; displayText: qsTr("古巴时间 GMT-5（哈瓦那）"); gmt: "GMT-5"; country: "CU" }
                    ListElement { timeZone: "America/Montevideo"; displayText: qsTr("乌拉圭时间 GMT-3（蒙得维的亚）"); gmt: "GMT-3"; country: "UY" }
                    ListElement { timeZone: "America/El_Salvador"; displayText: qsTr("萨尔瓦多时间 GMT-6（圣萨尔瓦多）"); gmt: "GMT-6"; country: "SV" }
                }
                textRole: "displayText"
            }

            RowLayout{
                FluText {
                    text: qsTr("选择语言");
                    font.bold: true
                }
            }

            FluComboBox {
                id: languageComboBox
                Layout.fillWidth: true
                editable: true
                model: ListModel {
                    ListElement { languageCode: "en"; displayText: qsTr("英语"); country: "US" }
                    ListElement { languageCode: "es"; displayText: qsTr("西班牙语"); country: "ES" }
                    ListElement { languageCode: "tl"; displayText: qsTr("菲律宾语"); country: "PH" }
                    ListElement { languageCode: "fr"; displayText: qsTr("法语"); country: "FR" }
                    ListElement { languageCode: "km"; displayText: qsTr("柬埔寨语"); country: "KH" }
                    ListElement { languageCode: "de"; displayText: qsTr("德语"); country: "DE" }
                    ListElement { languageCode: "it"; displayText: qsTr("意大利语"); country: "IT" }
                    ListElement { languageCode: "pt"; displayText: qsTr("葡萄牙语（巴西）"); country: "BR" }
                    ListElement { languageCode: "pt"; displayText: qsTr("葡萄牙语"); country: "PT" }
                    ListElement { languageCode: "ru"; displayText: qsTr("俄语"); country: "RU" }
                    ListElement { languageCode: "ja"; displayText: qsTr("日语"); country: "JP" }
                    ListElement { languageCode: "zh"; displayText: qsTr("中文简体"); country: "CN" }
                    ListElement { languageCode: "zh"; displayText: qsTr("中文繁体（香港）"); country: "HK" }
                    ListElement { languageCode: "zh"; displayText: qsTr("中文繁体（台湾）"); country: "TW" }
                    ListElement { languageCode: "ko"; displayText: qsTr("韩语"); country: "KR" }
                    ListElement { languageCode: "ar"; displayText: qsTr("阿拉伯语"); country: "SA" }
                    ListElement { languageCode: "hi"; displayText: qsTr("印地语"); country: "IN" }
                    ListElement { languageCode: "bn"; displayText: qsTr("孟加拉语"); country: "BD" }
                    ListElement { languageCode: "ur"; displayText: qsTr("乌尔都语"); country: "PK" }
                    ListElement { languageCode: "id"; displayText: qsTr("印尼语"); country: "ID" }
                    ListElement { languageCode: "ms"; displayText: qsTr("马来语"); country: "MY" }
                    ListElement { languageCode: "tr"; displayText: qsTr("土耳其语"); country: "TR" }
                    ListElement { languageCode: "vi"; displayText: qsTr("越南语"); country: "VN" }
                    ListElement { languageCode: "th"; displayText: qsTr("泰语"); country: "TH" }
                    ListElement { languageCode: "pl"; displayText: qsTr("波兰语"); country: "PL" }
                    ListElement { languageCode: "nl"; displayText: qsTr("荷兰语"); country: "NL" }
                    ListElement { languageCode: "sv"; displayText: qsTr("瑞典语"); country: "SE" }
                    ListElement { languageCode: "fi"; displayText: qsTr("芬兰语"); country: "FI" }
                    ListElement { languageCode: "da"; displayText: qsTr("丹麦语"); country: "DK" }
                    ListElement { languageCode: "no"; displayText: qsTr("挪威语"); country: "NO" }
                    ListElement { languageCode: "cs"; displayText: qsTr("捷克语"); country: "CZ" }
                    ListElement { languageCode: "hu"; displayText: qsTr("匈牙利语"); country: "HU" }
                    ListElement { languageCode: "ro"; displayText: qsTr("罗马尼亚语"); country: "RO" }
                    ListElement { languageCode: "sk"; displayText: qsTr("斯洛伐克语"); country: "SK" }
                    ListElement { languageCode: "bg"; displayText: qsTr("保加利亚语"); country: "BG" }
                    ListElement { languageCode: "sl"; displayText: qsTr("斯洛文尼亚语"); country: "SI" }
                    ListElement { languageCode: "et"; displayText: qsTr("爱沙尼亚语"); country: "EE" }
                    ListElement { languageCode: "lv"; displayText: qsTr("拉脱维亚语"); country: "LV" }
                    ListElement { languageCode: "lt"; displayText: qsTr("立陶宛语"); country: "LT" }
                    ListElement { languageCode: "sr"; displayText: qsTr("塞尔维亚语"); country: "RS" }
                    ListElement { languageCode: "hy"; displayText: qsTr("亚美尼亚语"); country: "AM" }
                    ListElement { languageCode: "az"; displayText: qsTr("阿塞拜疆语"); country: "AZ" }
                    ListElement { languageCode: "mn"; displayText: qsTr("蒙古语"); country: "MN" }
                    ListElement { languageCode: "sw"; displayText: qsTr("斯瓦希里语"); country: "KE" }
                    ListElement { languageCode: "sw"; displayText: qsTr("斯瓦希里语"); country: "TZ" }
                    ListElement { languageCode: "zu"; displayText: qsTr("祖鲁语"); country: "ZA" }
                    ListElement { languageCode: "jv"; displayText: qsTr("爪哇语"); country: "ID" }
                    ListElement { languageCode: "yi"; displayText: qsTr("意第绪语"); country: "IL" }
                    ListElement { languageCode: "pa"; displayText: qsTr("旁遮普语"); country: "IN" }
                    ListElement { languageCode: "gu"; displayText: qsTr("古吉拉特语"); country: "IN" }
                    ListElement { languageCode: "te"; displayText: qsTr("泰卢固语"); country: "IN" }
                    ListElement { languageCode: "ta"; displayText: qsTr("泰米尔语"); country: "LK" }
                    ListElement { languageCode: "ml"; displayText: qsTr("马拉雅拉姆语"); country: "IN" }
                    ListElement { languageCode: "kn"; displayText: qsTr("卡纳达语"); country: "IN" }
                }
                textRole: "displayText"
                onCurrentIndexChanged: {

                }
            }

            FluText {
                Layout.fillWidth: true
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                text: qsTr("语言时区IP不同,可能存在风控风险，请谨慎选择。")
                color: "red"
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
                onClicked: {
                    // 检查是否有选择
                    if (timeZoneComboBox.currentIndex < 0 || languageComboBox.currentIndex < 0) {
                        console.log("请选择时区和语言")
                        return
                    }

                    // 获取当前选择的时区和语言
                    selectedTimeZone = timeZoneComboBox.model.get(timeZoneComboBox.currentIndex).timeZone
                    var selectedLanguageItem = languageComboBox.model.get(languageComboBox.currentIndex)
                    selectedLanguageCode = selectedLanguageItem.languageCode
                    
                    // 语言更新时使用语言项中定义的国家代码，而不是选择的国家
                    // 例如：英语使用 US，而不是用户选择的国家
                    selectedLanguageCountry = selectedLanguageItem.country

                    // 检查是否与原始值不同
                    var timeZoneChanged = (selectedTimeZone !== originalTimeZone)
                    var languageChanged = (selectedLanguageCode !== originalLocale)
                    var countryChanged = (selectedCountryInfoCode !== originalCountry)

                    if (timeZoneChanged || languageChanged || countryChanged) {
                        // 分别发送HTTP请求更新时区和语言
                        if (timeZoneChanged) {
                            updateTimeZone(selectedTimeZone)
                        }
                        
                        if (languageChanged) {
                            // 使用语言项中定义的国家代码，而不是选择的国家代码
                            updateLanguage(selectedLanguageCountry, selectedLanguageCode)
                        }

                        if (countryChanged) {
                            updateCountry(selectedCountryInfoCode)
                        }
                    } else {
                        // 没有变化，直接关闭弹窗
                        root.close()
                    }
                }
            }
        }
    }

    function refreshComboBoxData () {
        updatingFromModel = true
        
        // 更新时区
        if (modelData && modelData.timeZone) {
            originalTimeZone = modelData.timeZone
            var timeZoneMatched = false
            // 处理 GMT 时区，映射到 GMT+0 的时区
            var timeZoneToMatch = modelData.timeZone
            if (timeZoneToMatch === "GMT" || timeZoneToMatch === "UTC") {
                timeZoneToMatch = "Europe/London" // 默认使用伦敦时区
            }
            
            for (var i = 0; i < timeZoneComboBox.model.count; i++) {
                if (timeZoneComboBox.model.get(i).timeZone === timeZoneToMatch) {
                    timeZoneComboBox.currentIndex = i
                    timeZoneMatched = true
                    break
                }
            }
            
            // 如果没有精确匹配，尝试通过 editable 设置文本
            if (!timeZoneMatched && timeZoneComboBox.editable) {
                timeZoneComboBox.editText = modelData.timeZone
            }
        } else {
            originalTimeZone = ""
            timeZoneComboBox.currentIndex = -1
        }

        console.log(`时区设置 timeZone: ${modelData?.timeZone || 'undefined'}  locale: ${modelData?.locale || 'undefined'}  country: ${modelData?.country || 'undefined'}`)

        // 确定国家代码 - 优先使用 modelData.country
        var countryCode = ""
        if (modelData && modelData.country && modelData.country !== "") {
            countryCode = modelData.country
            originalCountry = modelData.country
        } else if (modelData && modelData.locale) {
            // 从locale中提取国家代码
            var parts = modelData.locale.split("-")
            if (parts.length > 1) {
                countryCode = parts[1]
            }
            originalCountry = countryCode
        } else {
            originalCountry = ""
        }

        // 更新国家
        if (countryCode !== "") {
            var countryMatched = false
            for (var k = 0; k < countryComboBox.model.count; k++) {
                if (countryComboBox.model.get(k).countryCode === countryCode) {
                    countryComboBox.currentIndex = k
                    countryMatched = true
                    break
                }
            }
            // 如果没有匹配到，且可编辑，设置文本
            if (!countryMatched && countryComboBox.editable) {
                countryComboBox.editText = countryCode
            }
        } else {
            countryComboBox.currentIndex = -1
        }

        // 更新语言 - 优先使用 locale 中的国家代码来匹配
        if (modelData && modelData.locale) {
            originalLocale = modelData.locale
            // 解析locale字符串，例如 "en-US" -> languageCode: "en", localeCountry: "US"
            var parts = modelData.locale.split("-")
            var langCode = parts[0]
            var localeCountry = parts.length > 1 ? parts[1] : ""
            
            var languageMatched = false
            // 首先尝试用 locale 中的国家代码匹配（更准确）
            if (localeCountry !== "") {
                for (var j = 0; j < languageComboBox.model.count; j++) {
                    var item = languageComboBox.model.get(j)
                    if (item.languageCode === langCode && item.country === localeCountry) {
                        languageComboBox.currentIndex = j
                        languageMatched = true
                        break
                    }
                }
            }
            
            // 如果没匹配到，尝试只匹配语言代码
            if (!languageMatched) {
                for (var j = 0; j < languageComboBox.model.count; j++) {
                    var item = languageComboBox.model.get(j)
                    if (item.languageCode === langCode) {
                        languageComboBox.currentIndex = j
                        languageMatched = true
                        break
                    }
                }
            }
            
            // 如果还是没有匹配到，且可编辑，设置文本
            if (!languageMatched && languageComboBox.editable) {
                languageComboBox.editText = modelData.locale
            }
        } else {
            originalLocale = ""
            languageComboBox.currentIndex = -1
        }
        
        updatingFromModel = false
    }


    onAboutToShow: {
        // 设置时区默认选项
        timeTitle.text = qsTr("修改语言时区") + "(" + modelData.displayName + ")"
        getTimeZoneLangue()
    }

    // 更新时区的函数
    function updateTimeZone(newTimeZone) {
        var hostIp = modelData.hostIp
        var dbId = modelData.dbId || modelData.id || modelData.name
        if (!hostIp || !dbId) {
            console.warn("[云机详情] 修改局域网络: hostIp 或 dbId 为空")
            showError(qsTr("缺少必要参数"))
            return
        }

        Network.postJson(`http://${hostIp}:18182/android_api/v1/timezone_set/${dbId}`)
        .add("timeZone", newTimeZone)
        .bind(root)
        .setUserData(hostIp)
        .go(setTimeZone)
    }


    function getTimeZoneLangue() {
        var hostIp = modelData.hostIp
        var dbId = modelData.dbId || modelData.id || modelData.name
        if (!hostIp || !dbId) {
            console.warn("[云机详情] 修改局域网络: hostIp 或 dbId 为空")
            showError(qsTr("缺少必要参数"))
            return
        }

        Network.get(`http://${hostIp}:18182/android_api/v1/get_timezone_locale/${dbId}`)
        .bind(root)
        .setUserData(hostIp)
        .go(getTimeZoneLang)
    }

    // 更新语言的函数
    function updateLanguage(country, lang) {
        var hostIp = modelData.hostIp
        var dbId = modelData.dbId || modelData.id || modelData.name
        if (!hostIp || !dbId) {
            console.warn("[云机详情] 修改局域网络: hostIp 或 dbId 为空")
            showError(qsTr("缺少必要参数"))
            return
        }

        Network.postJson(`http://${hostIp}:18182/android_api/v1/language_set/${dbId}`)
        .add("country", country)
        .add("language", lang)
        .bind(root)
        .setUserData(hostIp)
        .go(setDevLanguage)
    }

    // 更新国家的函数
    function updateCountry(country) {
        var hostIp = modelData.hostIp
        var dbId = modelData.dbId || modelData.id || modelData.name
        if (!hostIp || !dbId) {
            console.warn("[云机详情] 修改局域网络: hostIp 或 dbId 为空")
            showError(qsTr("缺少必要参数"))
            return
        }

        Network.postJson(`http://${hostIp}:18182/android_api/v1/country_set/${dbId}`)
        .add("country", country)
        .bind(root)
        .setUserData(hostIp)
        .go(setCountry)
    }

    NetworkCallable {
        id: setTimeZone
        onError:
            (status, errorString, result, userData) => {
                console.debug("[设置时区] 设置时区失败:", status, errorString, result)
                // 失败不影响功能，静默处理
            }
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result)
                    if(res.code === 200){
                        showSuccess(qsTr("更新时区成功"))
                        modelData.timeZone = selectedTimeZone
                        root.close()
                    }
                    else {
                        showError(res.msg)
                    }
                } catch (e) {
                    console.error("[设置时区] 解析设置时区数据失败:", e)
                }
            }
    }
    
    NetworkCallable {
        id: setDevLanguage
        onError:
            (status, errorString, result, userData) => {
                console.debug("[设置语言] 解析设置语言失败:", status, errorString, result)
                // 失败不影响功能，静默处理
            }
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result)
                    if(res.code === 200){
                        showSuccess(qsTr("更新语言成功"))
                        // 使用语言项中定义的国家代码，而不是选择的国家代码
                        modelData.locale = selectedLanguageCode + "-" + selectedLanguageCountry
                        root.close()
                    }else {
                        showError(res.msg)
                    }
                } catch (e) {
                    console.error("[设置语言] 解析设置语言数据失败:", e)
                }
            }
    }

    NetworkCallable {
        id: setCountry
        onError:
            (status, errorString, result, userData) => {
                console.debug("[设置国家] 解析设置国家失败:", status, errorString, result)
                // 失败不影响功能，静默处理
            }
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result)
                    if(res.code === 200){
                        showSuccess(qsTr("更新国家成功"))
                        modelData.country = selectedCountryInfoCode
                        root.close()
                    }else {
                        showError(res.msg)
                    }
                } catch (e) {
                    console.error("[设置国家] 解析设置国家数据失败:", e)
                }
            }
    }

    NetworkCallable {
        id: getTimeZoneLang
        onError:
            (status, errorString, result, userData) => {
                console.debug("[设置时区] 设置时区失败:", status, errorString, result)
                // 失败不影响功能，静默处理
            }
        onSuccess:
            (result, userData) => {
                try {
                    var res = JSON.parse(result)
                    if(res.code === 200){
                        modelData.timeZone = res.data.timezone;
                        modelData.locale = res.data.locale;
                        modelData.country = res.data.country;
                        refreshComboBoxData()
                    }
                } catch (e) {
                    console.error("[设置时区] 解析设置时区数据失败:", e)
                }
            }
    }
    
}
