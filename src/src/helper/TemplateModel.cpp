#include "TemplateModel.h"
#include "FileCopyManager.h"
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDateTime>
#include <QStandardPaths>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QApplication>
#include <algorithm>

TemplateModel::TemplateModel(QObject* parent)
    : QAbstractListModel(parent)
{

    m_filePath = QCoreApplication::applicationDirPath() + "/adi/template.json";
    
    // 确保目录存在
    QDir configDir = QFileInfo(m_filePath).dir();
    if (!configDir.exists()) {
        configDir.mkpath(".");
    }
    
    loadConfig();
}

TemplateModel::~TemplateModel()
{
    saveConfig();
}

int TemplateModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;

    return m_items.size();
}

QVariant TemplateModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return QVariant();

    const TemplateItem& item = m_items.at(index.row());

    switch (role) {
    case BrandRole:
        return item.brand;
    case ModelRole:
        return item.model;
    case LayoutRole:
        return item.layout;
    case NameRole:
        return item.name;
    case FilePathRole:
        return item.filePath;
    case AsopVersionRole:
        return item.asopVersion;
    case UpdateTimeRole:
        return item.updateTime;
    case IdRole:
        return item.id;
    case PwdRole:
        return item.pwd;
    default:
        return QVariant();
    }
}

bool TemplateModel::setData(const QModelIndex& index, const QVariant& value, int role)
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return false;

    TemplateItem& item = m_items[index.row()];

    switch (role) {
    case BrandRole:
        item.brand = value.toString();
        break;
    case ModelRole:
        item.model = value.toString();
        break;
    case LayoutRole:
        item.layout = value.toString();
        break;
    case NameRole:
        item.name = value.toString();
        break;
    case FilePathRole:
        item.filePath = value.toString();
        break;
    case AsopVersionRole:
        item.asopVersion = value.toString();
        break;
    case UpdateTimeRole:
        item.updateTime = value.toString();
        break;
    case IdRole:
        item.id = value.toString();
        break;
    case PwdRole:
        item.pwd = value.toString();
        break;
    default:
        return false;
    }

    emit dataChanged(index, index, {role});
    return true;
}

QHash<int, QByteArray> TemplateModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[BrandRole] = "brand";
    roles[ModelRole] = "model";
    roles[LayoutRole] = "layout";
    roles[NameRole] = "name";
    roles[FilePathRole] = "filePath";
    roles[AsopVersionRole] = "asopVersion";
    roles[UpdateTimeRole] = "updateTime";
    roles[IdRole] = "id";
    roles[PwdRole] = "pwd";
    return roles;
}

Qt::ItemFlags TemplateModel::flags(const QModelIndex& index) const
{
    if (!index.isValid())
        return Qt::NoItemFlags;

    return Qt::ItemIsEnabled | Qt::ItemIsSelectable | Qt::ItemIsEditable;
}

void TemplateModel::addItem(const QString& brand, const QString& model, const QString& layout, const QString& name, const QString& filePath, const QString& asopVersion)
{
    TemplateItem newItem;
    newItem.brand = brand;
    newItem.model = model;
    newItem.layout = layout;
    newItem.name = name;
    newItem.filePath = filePath;
    newItem.asopVersion = asopVersion;
    newItem.updateTime = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");

    auto parseVersion = [](const QString& s)->int{
        QString digits;
        for (const QChar& ch : s) { if (ch.isDigit()) digits.append(ch); }
        return digits.isEmpty() ? 0 : digits.toInt();
    };

    // 计算按更新时倒序、同时间按安卓版本升序的插入位置
    int pos = 0;
    for (; pos < m_items.size(); ++pos) {
        const TemplateItem& cur = m_items.at(pos);
        if (newItem.updateTime > cur.updateTime) {
            break; // 更新时更新更晚，应该排在前面
        }
        if (newItem.updateTime < cur.updateTime) {
            continue; // 新项更早，继续往后找
        }
        // 时间相同，按安卓版本升序
        if (parseVersion(newItem.asopVersion) < parseVersion(cur.asopVersion)) {
            break;
        }
    }

    beginInsertRows(QModelIndex(), pos, pos);
    m_items.insert(pos, newItem);
    endInsertRows();

    saveConfig();
}

void TemplateModel::remove(int index)
{
    if (index < 0 || index >= m_items.size())
        return;

    // 删除实际的模板文件（异步操作，在后台线程执行）
    const TemplateItem& item = m_items.at(index);
    if (!item.filePath.isEmpty()) {
        FileCopyManager::instance()->startDelete(item.filePath);
    }

    // 立即从模型中移除（不等待文件删除完成）
    beginRemoveRows(QModelIndex(), index, index);
    m_items.removeAt(index);
    endRemoveRows();

    saveConfig();
}

void TemplateModel::reloadConfig()
{
    loadConfig();
}

void TemplateModel::setFilePath(const QString& filePath)
{
    if (filePath.isEmpty())
        return;

    if (m_filePath == filePath)
        return;

    m_filePath = filePath;
    loadConfig();
}

void TemplateModel::saveConfig()
{
    //  模板只读，不需要保存
    return;
    QJsonArray jsonArray;

    for (const TemplateItem& item : m_items) {
        QJsonObject jsonObj;
        jsonObj["brand"] = item.brand;
        jsonObj["model"] = item.model;
        jsonObj["layout"] = item.layout;
        jsonObj["name"] = item.name;
        jsonObj["filePath"] = item.filePath;
        jsonObj["asopVersion"] = item.asopVersion;
        jsonObj["updateTime"] = item.updateTime;
        jsonObj["id"] = item.id;
        jsonObj["pwd"] = item.pwd;

        jsonArray.append(jsonObj);
    }

    QJsonDocument doc(jsonArray);
    QFile file(m_filePath);

    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
    }
}

void TemplateModel::loadConfig()
{
    QFile file(m_filePath);
    if (!file.exists()) {
        return;
    }
    
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }

    QByteArray data = file.readAll();
    file.close();
    
    if (data.isEmpty()) {
        return;
    }

    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    
    if (parseError.error != QJsonParseError::NoError) {
        return;
    }
    
    if (!doc.isArray()) {
        return;
    }

    QJsonArray jsonArray = doc.array();

    beginResetModel();
    m_items.clear();

    auto readWithAliases = [](const QJsonObject& o, std::initializer_list<const char*> keys) -> QString {
        for (const char* k : keys) {
            const QJsonValue v = o.value(k);
            if (!v.isUndefined() && v.isString()) {
                return v.toString();
            }
        }
        // 若存在非字符串但可转字符串的值
        for (const char* k : keys) {
            const QJsonValue v = o.value(k);
            if (!v.isUndefined() && !v.isNull()) {
                return v.toVariant().toString();
            }
        }
        return QString();
    };

    for (const QJsonValue& value : jsonArray) {
        QJsonObject jsonObj = value.toObject();

        TemplateItem item;
        item.brand = readWithAliases(jsonObj, {"brand", "brandName", "manufacturer"});
        item.model = readWithAliases(jsonObj, {"model_name", "model", "deviceModel", "device", "modelName"});
        item.layout = readWithAliases(jsonObj, {"layout", "layoutName"});
        item.name = readWithAliases(jsonObj, {"name", "templateName", "displayName", "title"});
        item.filePath = readWithAliases(jsonObj, {"filePath", "path", "file", "layoutPath"});
        // asopVersion 历史别名：aospVersion/androidVersion/version
        item.asopVersion = readWithAliases(jsonObj, {"asopVersion", "aospVersion", "androidVersion", "version"});
        item.updateTime = readWithAliases(jsonObj, {"updateTime", "createTime", "importTime", "updatedAt", "createdAt"});
        item.id = readWithAliases(jsonObj, {"id", "templateId", "deviceId"});
        item.pwd = readWithAliases(jsonObj, {"pwd", "password", "pass", "devicePassword"});

        // 推断缺省值
        if (item.name.isEmpty() && !item.filePath.isEmpty()) {
            QFileInfo fi(item.filePath);
            item.name = fi.completeBaseName();
        }
        if (item.updateTime.isEmpty()) {
            item.updateTime = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
        }
        m_items.append(item);
    }

    // 默认按导入时间倒序；导入时间相同按安卓版本升序
    auto parseVersion = [](const QString& s)->int{
        QString digits;
        for (const QChar& ch : s) { if (ch.isDigit()) digits.append(ch); }
        return digits.isEmpty() ? 0 : digits.toInt();
    };
    std::sort(m_items.begin(), m_items.end(), [&](const TemplateItem& a, const TemplateItem& b){
        if (a.updateTime != b.updateTime) return a.updateTime > b.updateTime;
        return parseVersion(a.asopVersion) < parseVersion(b.asopVersion);
    });

    endResetModel();
}
