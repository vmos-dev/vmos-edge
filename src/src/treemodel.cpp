#include "treemodel.h"
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDebug>
#include <QFile>
#include <QStandardPaths>
#include <QDateTime>

TreeModel::TreeModel(QObject *parent)
    : QAbstractItemModel(parent)
    , m_rootItem(new RootItem())
{
    m_configPath = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/treemodel.json";
    loadConfig();
}

TreeModel::~TreeModel()
{
    delete m_rootItem;
}

void TreeModel::loadConfig()
{
    QFile file(m_configPath);
    if (file.exists() && file.open(QIODevice::ReadOnly)) {
        QByteArray data = file.readAll();
        if (!data.isEmpty()) {
            m_groups.clear();
            m_hostsByGroup.clear();
            m_devicesByHost.clear();
            parseData(data, m_groups, m_hostsByGroup, m_devicesByHost);
        }
    }

    if (m_groups.isEmpty()) {
        initDefaultGroup();
        saveConfig();
    }

    rebuildTree();
}

void TreeModel::initDefaultGroup()
{
    m_groups.clear();
    m_hostsByGroup.clear();
    m_devicesByHost.clear();

    GroupData defaultGroup;
    defaultGroup.groupId = 1;
    defaultGroup.groupName = tr("默认分组");
    defaultGroup.groupPadCount = 0;
    m_groups.append(defaultGroup);
}

void TreeModel::saveConfig()
{
    if (m_configPath.isEmpty()) return;
    QFile file(m_configPath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(toJson());
    }
}

QByteArray TreeModel::toJson() const
{
    QJsonArray groupsArray;
    for (const auto& groupData : m_groups) {
        QJsonObject groupObject;
        groupObject["groupId"] = groupData.groupId;
        groupObject["groupName"] = groupData.groupName;
        groupObject["groupPadCount"] = groupData.groupPadCount;

        QJsonArray hostsArray;
        if (m_hostsByGroup.contains(groupData.groupId)) {
            for (const auto& hostData : m_hostsByGroup.value(groupData.groupId)) {
                QJsonObject hostObject;
                hostObject["groupId"] = hostData.groupId;
                hostObject["hostId"] = hostData.hostId;
                hostObject["hostName"] = hostData.hostName;
                hostObject["ip"] = hostData.ip;
                hostObject["hostPadCount"] = hostData.hostPadCount;
                hostObject["updateTime"] = hostData.updateTime.isEmpty() ? QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss") : hostData.updateTime;
                hostObject["state"] = hostData.state.isEmpty() ? "online" : hostData.state;
                hostObject["selected"] = hostData.selected;

                QJsonArray devicesArray;
                if (m_devicesByHost.contains(hostData.hostId)) {
                    for (const auto& deviceData : m_devicesByHost.value(hostData.hostId)) {
                        QJsonObject deviceObject;
                        deviceObject["id"] = deviceData.id;
                        deviceObject["name"] = deviceData.name;
                        deviceObject["displayName"] = deviceData.displayName;
                        deviceObject["shortId"] = deviceData.shortId;
                        deviceObject["dbId"] = deviceData.dbId;
                        deviceObject["image"] = deviceData.image;
                        deviceObject["state"] = deviceData.state;
                        deviceObject["adb"] = deviceData.adb;
                        deviceObject["data"] = deviceData.data;
                        deviceObject["dns"] = deviceData.dns;
                        deviceObject["dpi"] = deviceData.dpi;
                        deviceObject["fps"] = deviceData.fps;
                        deviceObject["height"] = deviceData.height;
                        deviceObject["ip"] = deviceData.ip;
                        deviceObject["memory"] = deviceData.memory;
                        deviceObject["created"] = deviceData.created;
                        deviceObject["width"] = deviceData.width;
                        deviceObject["aospVersion"] = deviceData.aospVersion;
                        deviceObject["hostIp"] = deviceData.hostIp;
                        deviceObject["tcpVideoPort"] = deviceData.tcpVideoPort;
                        deviceObject["tcpAudioPort"] = deviceData.tcpAudioPort;
                        deviceObject["tcpControlPort"] = deviceData.tcpControlPort;
                        deviceObject["macvlanIp"] = deviceData.macvlanIp;
                        deviceObject["timezone"] = deviceData.timezone;
                        deviceObject["locale"] = deviceData.locale;
                        devicesArray.append(deviceObject);
                    }
                }
                hostObject["userPads"] = devicesArray;
                hostsArray.append(hostObject);
            }
        }
        groupObject["hosts"] = hostsArray;
        groupsArray.append(groupObject);
    }
    return QJsonDocument(groupsArray).toJson();
}

void TreeModel::rebuildTree()
{
    beginResetModel();
    
    // 安全地删除旧的根节点
    if (m_rootItem) {
        delete m_rootItem;
        m_rootItem = nullptr;
    }
    
    // 清理所有缓存
    m_deviceIndexCache.clear();
    m_checkedDeviceIds.clear();
    m_selectedDeviceIds.clear();
    // 注意：不要清理 m_checkedGroupIds 和 m_checkedHostIds，它们表示用户对空分组/空主机的勾选意图
    
    // 创建新的根节点
    m_rootItem = new RootItem();
    
    for(const auto& groupData : m_groups){
        auto groupItem = new GroupItem(groupData, m_rootItem);
        m_rootItem->appendChild(groupItem);
        if(m_hostsByGroup.contains(groupData.groupId)){
            for(auto& hostData : m_hostsByGroup[groupData.groupId]){
                hostData.hostPadCount = m_devicesByHost.value(hostData.hostId).size();
                auto hostItem = new HostItem(hostData, groupItem);
                groupItem->appendChild(hostItem);
                if(m_devicesByHost.contains(hostData.hostId)){
                    for(const auto& deviceData : m_devicesByHost.value(hostData.hostId)){
                        hostItem->appendChild(new DeviceItem(deviceData, hostItem));
                    }
                }
            }
        }
    }
    endResetModel();
}

bool TreeModel::addGroup(const QString &name)
{
    for (const auto& group : m_groups) {
        if (group.groupName == name) {
            qWarning() << "Group with name" << name << "already exists.";
            return false;
        }
    }

    GroupData newGroup;
    newGroup.groupId = generateNewGroupId();
    newGroup.groupName = name;
    newGroup.groupPadCount = 0;

    int newRow = m_groups.size();
    beginInsertRows(QModelIndex(), newRow, newRow);
    m_groups.append(newGroup);
    m_rootItem->appendChild(new GroupItem(newGroup, m_rootItem));
    endInsertRows();

    saveConfig();
    return true;
}

bool TreeModel::removeGroup(int groupId)
{
    if (groupId == 1) { // Assuming 1 is the default group ID
        qWarning() << "Cannot remove the default group.";
        return false;
    }

    int sourceGroupRow = -1;
    int defaultGroupRow = -1;
    for (int i = 0; i < m_groups.size(); ++i) {
        if (m_groups[i].groupId == groupId) sourceGroupRow = i;
        if (m_groups[i].groupId == 1) defaultGroupRow = i;
    }

    if (sourceGroupRow == -1) {
        qWarning() << "Group to remove not found:" << groupId;
        return false;
    }
    if (defaultGroupRow == -1) {
        qWarning() << "Default group not found, cannot move hosts.";
        rebuildTree(); // Fallback to old behavior
        return false;
    }

    // --- Move hosts to default group ---
    if (m_hostsByGroup.contains(groupId)) {
        QModelIndex sourceParent = index(sourceGroupRow, 0, QModelIndex());
        // The destination row might change if the source is before the destination, but move handles this.
        if(defaultGroupRow > sourceGroupRow){
            defaultGroupRow--;
        }
        QModelIndex destParent = index(defaultGroupRow, 0, QModelIndex());
        GroupItem* sourceGroupItem = static_cast<GroupItem*>(sourceParent.internalPointer());
        GroupItem* destGroupItem = static_cast<GroupItem*>(destParent.internalPointer());

        if (sourceGroupItem && destGroupItem && sourceGroupItem->childCount() > 0) {
            int count = sourceGroupItem->childCount();
            beginMoveRows(sourceParent, 0, count - 1, destParent, destGroupItem->childCount());

            QList<HostData> hostsToMove = m_hostsByGroup.take(groupId);
            for(auto& host : hostsToMove) host.groupId = 1;
            m_hostsByGroup[1].append(hostsToMove);

            QList<TreeItem*> itemsToMove;
            while(sourceGroupItem->childCount() > 0){
                itemsToMove.append(sourceGroupItem->takeChild(0));
            }

            for (auto* item : itemsToMove) {
                item->setParentItem(destGroupItem);
                destGroupItem->appendChild(item);
            }
            endMoveRows();
        }
    }

    // --- Remove the now-empty group ---
    int finalSourceRow = -1;
    for(int i=0; i<m_groups.size(); ++i){
        if(m_groups.at(i).groupId == groupId){
            finalSourceRow = i;
            break;
        }
    }

    if(finalSourceRow != -1){
        beginRemoveRows(QModelIndex(), finalSourceRow, finalSourceRow);
        m_groups.removeAt(finalSourceRow);
        delete m_rootItem->takeChild(finalSourceRow);
        endRemoveRows();
    }

    saveConfig();
    return true;
}

bool TreeModel::renameGroup(int groupId, const QString& newName)
{
    // Check for duplicate name
    for (const auto& group : m_groups) {
        if (group.groupId != groupId && group.groupName == newName) {
            qWarning() << "Group with name" << newName << "already exists.";
            return false;
        }
    }

    int groupIndex = -1;
    for (int i = 0; i < m_groups.size(); ++i) {
        if (m_groups[i].groupId == groupId) {
            groupIndex = i;
            break;
        }
    }

    if (groupIndex == -1) {
        qWarning() << "Group to rename not found:" << groupId;
        return false;
    }

    // Update the name
    m_groups[groupIndex].groupName = newName;

    QModelIndex modelIndex = index(groupIndex, 0, QModelIndex());
    if (modelIndex.isValid()) {
        GroupItem* groupItem = static_cast<GroupItem*>(modelIndex.internalPointer());
        groupItem->groupData().groupName = newName;
        emit dataChanged(modelIndex, modelIndex, {GroupNameRole});
    } else {
        // Fallback for safety, though it shouldn't be reached.
        rebuildTree();
    }

    saveConfig();

    return true;
}

QVariantList TreeModel::hostList() const
{
    QVariantList hosts;
    for (const auto& hostList : m_hostsByGroup) {
        for (const auto& host : hostList) {
            QVariantMap hostMap;
            hostMap["groupId"] = host.groupId;
            hostMap["hostId"] = host.hostId;
            hostMap["hostName"] = host.hostName;
            hostMap["ip"] = host.ip;
            hostMap["hostPadCount"] = host.hostPadCount;
            hostMap["updateTime"] = host.updateTime;
            hostMap["state"] = host.state;
            hostMap["checked"] = false;
            hosts.append(hostMap);
        }
    }
    return hosts;
}

bool TreeModel::addHost(const QVariantMap &hostDataMap)
{
    const int defaultGroupId = 1;
    QString hostId = hostDataMap["id"].toString();

    // 如果该主机已存在，则更新主机信息而不是直接返回失败
    for (auto it = m_hostsByGroup.begin(); it != m_hostsByGroup.end(); ++it) {
        QList<HostData>& hostListRef = it.value();
        for (int i = 0; i < hostListRef.size(); ++i) {
            if (hostListRef[i].hostId == hostId) {
                HostData& existingHost = hostListRef[i];

                QVector<int> changedRoles;

                // ip 更新
                const QString newIp = hostDataMap.value("ip").toString();
                if (!newIp.isEmpty() && existingHost.ip != newIp) {
                    existingHost.ip = newIp;
                    changedRoles.append(IpRole);
                }

                // hostName 更新（默认与 ip 一致）
                const QString newHostName = hostDataMap.value("hostName").toString().isEmpty() ? newIp : hostDataMap.value("hostName").toString();
                if (!newHostName.isEmpty() && existingHost.hostName != newHostName) {
                    existingHost.hostName = newHostName;
                    changedRoles.append(HostNameRole);
                }

                // 在线状态 & 更新时间
                const QString newUpdateTime = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
                if (existingHost.updateTime != newUpdateTime) {
                    existingHost.updateTime = newUpdateTime;
                    changedRoles.append(UpdateTimeRole);
                }
                if (existingHost.state != "online") {
                    existingHost.state = "online";
                    changedRoles.append(StateRole);
                }

                // 回写到树节点并通知 UI
                QModelIndex hostIndex = findIndex(hostId, TypeHost);
                if (hostIndex.isValid()) {
                    HostItem* hostItem = static_cast<HostItem*>(hostIndex.internalPointer());
                    hostItem->hostData() = existingHost;
                    if (!changedRoles.isEmpty()) {
                        emit dataChanged(hostIndex, hostIndex, changedRoles);
                    }
                } else {
                    // 找不到节点时退化到重建树
                    rebuildTree();
                }

                saveConfig();
                return true;
            }
        }
    }

    QModelIndex parentIndex = findIndex(defaultGroupId, TypeGroup);
    if (!parentIndex.isValid()) {
        qWarning() << "Default group not found. Cannot add host.";
        return false;
    }

    GroupItem* parentItem = static_cast<GroupItem*>(parentIndex.internalPointer());
    int newRow = parentItem->childCount();

    beginInsertRows(parentIndex, newRow, newRow);

    HostData hostData;
    hostData.groupId = defaultGroupId;
    hostData.hostId = hostId;
    hostData.hostName = hostDataMap["ip"].toString();
    hostData.ip = hostDataMap["ip"].toString();
    hostData.hostPadCount = 0;
    hostData.updateTime = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
    hostData.state = "online";
    hostData.selected = false;

    m_hostsByGroup[defaultGroupId].append(hostData);
    parentItem->appendChild(new HostItem(hostData, parentItem));

    endInsertRows();

    // 如果该分组先前被勾选但还没有主机，继承分组勾选到新主机（主机无设备）
    if (m_checkedGroupIds.contains(defaultGroupId)) {
        m_checkedHostIds.insert(hostData.hostId);
        QModelIndex hostIndex = index(newRow, 0, parentIndex);
        emit dataChanged(hostIndex, hostIndex, {CheckedRole});
        emit dataChanged(parentIndex, parentIndex, {CheckedRole});
    }

    // 更新分组的设备数量显示
    emit dataChanged(parentIndex, parentIndex, {GroupPadCountRole});

    saveConfig();
    return true;
}

void TreeModel::addDevice(const QString& hostIp, const QVariantMap &deviceDataMap)
{
    int groupId = -1;
    QString hostId = "";
    bool hostExists = false;
    for(auto it = m_hostsByGroup.constBegin(); it != m_hostsByGroup.constEnd(); ++it){
        for(const auto& host : it.value()){
            if(host.ip == hostIp){
                hostExists = true;
                groupId = host.groupId;
                hostId = host.hostId;
                break;
            }
        }
        if(hostExists) break;
    }

    if (!hostExists) {
        qWarning() << "Attempted to add device to non-existent host" << hostId;
        return;
    }

    DeviceData deviceData;
    deviceData.groupId = groupId;
    deviceData.hostId = hostId;
    deviceData.adb = deviceDataMap["adb"].toInt();
    deviceData.data = deviceDataMap["data"].toString();
    deviceData.dbId = deviceDataMap["dbId"].toString();
    deviceData.dns = deviceDataMap["dns"].toString();
    deviceData.dpi = deviceDataMap["dpi"].toString();
    deviceData.fps = deviceDataMap["fps"].toString();
    deviceData.height = deviceDataMap["height"].toString();
    deviceData.id = deviceDataMap["id"].toString();
    deviceData.image = deviceDataMap["image"].toString();
    deviceData.ip = deviceDataMap["ip"].toString();
    deviceData.memory = deviceDataMap["memory"].toInt();
    deviceData.name = deviceDataMap["name"].toString();
    deviceData.displayName = deviceDataMap["user_name"].toString();
    deviceData.shortId = deviceDataMap["short_id"].toString();
    deviceData.state = deviceDataMap["state"].toString();
    deviceData.created = deviceDataMap["created"].toString();
    deviceData.width = deviceDataMap["width"].toString();
    deviceData.aospVersion = deviceDataMap["aosp_version"].toString();
    deviceData.hostIp = hostIp;
    deviceData.checked = false;
    deviceData.selected = false;
    deviceData.refresh = false;
    deviceData.networkMode = deviceDataMap["network_mode"].toString();
    deviceData.timezone = deviceDataMap["timezone"].toString();
    deviceData.locale = deviceDataMap["locale"].toString();

    deviceData.macvlanIp = deviceDataMap.contains("macvlan_ip") ? deviceDataMap["macvlan_ip"].toString() : (deviceDataMap.contains("macvlanIp") ? deviceDataMap["macvlanIp"].toString() : "");

    qDebug() << "add device" << deviceData.groupId << deviceData.hostId << deviceData.name;

    // Prevent adding duplicate devices under the same host, update if exists.
    if (m_devicesByHost.contains(hostId)) {
        auto& devices = m_devicesByHost[hostId];
        for (auto& existingDevice : devices) {
            if (existingDevice.name == deviceData.name) {
                qDebug() << "Device with id" << deviceData.id << "already exists under host" << hostId << ". Updating fields.";
                // Preserve UI-related states
                bool checked = existingDevice.checked;
                bool selected = existingDevice.selected;

                if (deviceDataMap.contains("adb")) existingDevice.adb = deviceDataMap["adb"].toInt();
                if (deviceDataMap.contains("data")) existingDevice.data = deviceDataMap["data"].toString();
                if (deviceDataMap.contains("dns")) existingDevice.dns = deviceDataMap["dns"].toString();
                if (deviceDataMap.contains("dpi")) existingDevice.dpi = deviceDataMap["dpi"].toString();
                if (deviceDataMap.contains("fps")) existingDevice.fps = deviceDataMap["fps"].toString();
                if (deviceDataMap.contains("height")) existingDevice.height = deviceDataMap["height"].toString();
                if (deviceDataMap.contains("id")) existingDevice.id = deviceDataMap["id"].toString();
                if (deviceDataMap.contains("image")) existingDevice.image = deviceDataMap["image"].toString();
                if (deviceDataMap.contains("ip")) existingDevice.ip = deviceDataMap["ip"].toString();
                if (deviceDataMap.contains("memory")) existingDevice.memory = deviceDataMap["memory"].toInt();
                if (deviceDataMap.contains("name")) existingDevice.name = deviceDataMap["name"].toString();
                if (deviceDataMap.contains("user_name")) existingDevice.displayName = deviceDataMap["user_name"].toString();
                if (deviceDataMap.contains("displayName")) existingDevice.displayName = deviceDataMap["displayName"].toString();
                if (deviceDataMap.contains("short_id")) existingDevice.shortId = deviceDataMap["short_id"].toString();
                if (deviceDataMap.contains("shortId")) existingDevice.shortId = deviceDataMap["shortId"].toString();
                if (deviceDataMap.contains("state")) existingDevice.state = deviceDataMap["state"].toString();
                if (deviceDataMap.contains("created")) existingDevice.created = deviceDataMap["created"].toString();
                if (deviceDataMap.contains("width")) existingDevice.width = deviceDataMap["width"].toString();
                if (deviceDataMap.contains("aosp_version")) existingDevice.aospVersion = deviceDataMap["aosp_version"].toString();
                if (deviceDataMap.contains("aospVersion")) existingDevice.aospVersion = deviceDataMap["aospVersion"].toString();
                if (deviceDataMap.contains("host_ip")) existingDevice.hostIp = deviceDataMap["host_ip"].toString();
                if (deviceDataMap.contains("hostIp")) existingDevice.hostIp = deviceDataMap["hostIp"].toString();
                if (deviceDataMap.contains("macvlan_ip")) existingDevice.macvlanIp = deviceDataMap["macvlan_ip"].toString();
                if (deviceDataMap.contains("network_mode")) existingDevice.networkMode = deviceDataMap["network_mode"].toString();
                if (deviceDataMap.contains("macvlanIp")) existingDevice.macvlanIp = deviceDataMap["macvlanIp"].toString();
                if (deviceDataMap.contains("timezone")) existingDevice.timezone = deviceDataMap["timezone"].toString();
                if (deviceDataMap.contains("locale")) existingDevice.locale = deviceDataMap["locale"].toString();
                existingDevice.checked = checked;
                existingDevice.selected = selected;

                QModelIndex deviceIndex = findIndex(existingDevice.name, TypeDevice);
                if (deviceIndex.isValid()) {
                    static_cast<DeviceItem*>(deviceIndex.internalPointer())->deviceData() = existingDevice;
                    emit dataChanged(deviceIndex, deviceIndex);
                } else {
                    rebuildTree(); // Fallback
                }
                saveConfig();
                return;
            }
        }
    }

    QModelIndex hostIndex = findIndex(hostId, TypeHost);
    if (!hostIndex.isValid()) {
        qWarning() << "Host item not found in tree for hostId:" << hostId << ". Falling back to rebuild.";
        rebuildTree();
        saveConfig();
        return;
    }

    HostItem* hostItem = static_cast<HostItem*>(hostIndex.internalPointer());
    int newRow = hostItem->childCount();

    beginInsertRows(hostIndex, newRow, newRow);
    m_devicesByHost[hostId].append(deviceData);
    hostItem->appendChild(new DeviceItem(deviceData, hostItem));
    endInsertRows();
    
    // 更新设备索引缓存
    QModelIndex newDeviceIndex = index(newRow, 0, hostIndex);
    m_deviceIndexCache[deviceData.dbId] = QPersistentModelIndex(newDeviceIndex);

    // 一旦该主机新增了设备，如果之前主机是“空主机勾选”，清理空主机勾选状态，转为设备级别
    if (m_checkedHostIds.contains(hostId)) {
        // 将主机的勾选意图下放到刚添加的设备
        const QList<DeviceData>& devices = m_devicesByHost.value(hostId);
        for (const auto& d : devices) {
            m_checkedDeviceIds.insert(d.dbId);
        }
        m_checkedHostIds.remove(hostId);
        emit dataChanged(hostIndex, hostIndex, {CheckedRole});
        QModelIndex groupIndex2 = parent(hostIndex);
        if (groupIndex2.isValid()) emit dataChanged(groupIndex2, groupIndex2, {CheckedRole});
    }

    // Update host's device count
    for (auto& hostList : m_hostsByGroup) {
        for (auto& host : hostList) {
            if (host.hostId == hostId) {
                host.hostPadCount = m_devicesByHost.value(hostId).size();
                break;
            }
        }
    }
    hostItem->hostData().hostPadCount = m_devicesByHost.value(hostId).size();
    emit dataChanged(hostIndex, hostIndex, {HostPadCountRole});

    // 更新分组的设备数量显示
    QModelIndex groupIndex = parent(hostIndex);
    if (groupIndex.isValid()) {
        emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
    }

    saveConfig();
}

void TreeModel::moveHost(const QString& hostId, int newGroupId)
{
    if (hostId.isEmpty()) {
        qWarning() << "moveHost called with an empty hostId.";
        return;
    }

    QModelIndex hostModelIndex = findIndex(hostId, TypeHost);
    if (!hostModelIndex.isValid()) {
        qWarning() << "Host not found for moving:" << hostId;
        return;
    }

    HostItem* hostItem = static_cast<HostItem*>(hostModelIndex.internalPointer());
    GroupItem* sourceGroupItem = static_cast<GroupItem*>(hostItem->parentItem());
    int oldGroupId = sourceGroupItem->groupData().groupId;

    if (oldGroupId == newGroupId) {
        return; // Nothing to do
    }

    QModelIndex sourceParentIndex = parent(hostModelIndex);
    int sourceRow = hostModelIndex.row();

    QModelIndex destParentIndex = findIndex(newGroupId, TypeGroup);
    if (!destParentIndex.isValid()) {
        qWarning() << "Destination group not found:" << newGroupId;
        rebuildTree(); // Fallback
        return;
    }
    GroupItem* destGroupItem = static_cast<GroupItem*>(destParentIndex.internalPointer());
    int destRow = destGroupItem->childCount();

    // --- Signal the move ---
    beginMoveRows(sourceParentIndex, sourceRow, sourceRow, destParentIndex, destRow);

    // --- Move the item in the tree structure ---
    sourceGroupItem->takeChild(sourceRow);
    hostItem->setParentItem(destGroupItem);
    destGroupItem->appendChild(hostItem);
    hostItem->hostData().groupId = newGroupId;

    // --- Update the backing data store to match ---
    int hostIndexInOldList = -1;
    for(int i=0; i < m_hostsByGroup[oldGroupId].size(); ++i) {
        if (m_hostsByGroup[oldGroupId][i].hostId == hostId) {
            hostIndexInOldList = i;
            break;
        }
    }
    if (hostIndexInOldList != -1) {
        HostData hostToMove = m_hostsByGroup[oldGroupId].takeAt(hostIndexInOldList);
        hostToMove.groupId = newGroupId;
        m_hostsByGroup[newGroupId].append(hostToMove);
    }

    // Update devices in backing store and tree
    if (m_devicesByHost.contains(hostId)) {
        for (auto& device : m_devicesByHost[hostId]) {
            device.groupId = newGroupId;
        }
        for (int i = 0; i < hostItem->childCount(); ++i) {
            static_cast<DeviceItem*>(hostItem->child(i))->deviceData().groupId = newGroupId;
        }
    }

    endMoveRows();

    emit dataChanged(sourceParentIndex, sourceParentIndex, {GroupPadCountRole});
    emit dataChanged(destParentIndex, destParentIndex, {GroupPadCountRole});

    saveConfig();
}

bool TreeModel::removeHost(const QString& hostId)
{
    if (hostId.isEmpty()) {
        qWarning() << "removeHost called with empty hostId";
        return false;
    }

    QModelIndex hostIndex = findIndex(hostId, TypeHost);
    if (!hostIndex.isValid()) {
        qWarning() << "removeHost: Host not found in tree for hostId:" << hostId;
        return false;
    }

    HostItem* hostItem = static_cast<HostItem*>(hostIndex.internalPointer());
    if (!hostItem) return false;

    const int groupId = hostItem->hostData().groupId;

    // 先移除该主机下的所有设备（树 + 后备存储 + 缓存）
    if (m_devicesByHost.contains(hostId)) {
        QList<DeviceData> devices = m_devicesByHost.value(hostId);
        const int deviceCount = hostItem->childCount();
        if (deviceCount > 0) {
            beginRemoveRows(hostIndex, 0, deviceCount - 1);
            for (const auto& d : devices) {
                m_selectedDeviceIds.remove(d.dbId);
                m_checkedDeviceIds.remove(d.dbId);
                m_deviceIndexCache.remove(d.dbId);
            }
            while (hostItem->childCount() > 0) {
                delete hostItem->takeChild(0);
            }
            endRemoveRows();
        }
        m_devicesByHost.remove(hostId);
    }

    // 从分组中移除此主机（树 + 后备存储）
    QModelIndex groupIndex = parent(hostIndex);
    GroupItem* groupItem = static_cast<GroupItem*>(groupIndex.internalPointer());
    const int hostRow = hostIndex.row();

    beginRemoveRows(groupIndex, hostRow, hostRow);
    // 从后端数据删除
    if (m_hostsByGroup.contains(groupId)) {
        QList<HostData>& list = m_hostsByGroup[groupId];
        for (int i = 0; i < list.size(); ++i) {
            if (list[i].hostId == hostId) { list.removeAt(i); break; }
        }
    }
    delete groupItem->takeChild(hostRow);
    endRemoveRows();

    // 清理主机勾选集
    m_checkedHostIds.remove(hostId);

    // 通知分组（主机数量变化）
    if (groupIndex.isValid()) {
        emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
    }

    saveConfig();
    return true;
}

bool TreeModel::removeDevice(const QString& deviceName)
{
    QString hostId;
    int deviceRowInList = -1;
    bool found = false;

    // Find device in backing store
    for (auto it = m_devicesByHost.begin(); it != m_devicesByHost.end(); ++it) {
        QList<DeviceData>& deviceList = it.value();
        for (int i = 0; i < deviceList.size(); ++i) {
            if (deviceList.at(i).name == deviceName) {
                hostId = it.key();
                deviceRowInList = i;
                found = true;
                break;
            }
        }
        if (found) break;
    }

    if (!found) {
        qWarning() << "Device to remove not found:" << deviceName;
        return false;
    }

    // Find parent HostItem's index
    QModelIndex hostIndex = findIndex(hostId, TypeHost);
    if (!hostIndex.isValid()) {
        qWarning() << "Parent host not found in tree for device:" << deviceName;
        rebuildTree(); // Fallback
        saveConfig();
        return false;
    }

    HostItem* hostItem = static_cast<HostItem*>(hostIndex.internalPointer());
    int deviceRowInTree = -1;
    for (int i = 0; i < hostItem->childCount(); ++i) {
        DeviceItem* deviceItem = static_cast<DeviceItem*>(hostItem->child(i));
        if (deviceItem->deviceData().name == deviceName) {
            deviceRowInTree = i;
            break;
        }
    }

    if (deviceRowInTree == -1) {
        qWarning() << "Device item not found in tree for device:" << deviceName;
        rebuildTree(); // Fallback
        saveConfig();
        return false;
    }

    // Remove the item using begin/end
    beginRemoveRows(hostIndex, deviceRowInTree, deviceRowInTree);
    QString deviceDbId = m_devicesByHost[hostId][deviceRowInList].dbId;
    m_devicesByHost[hostId].removeAt(deviceRowInList);
    delete hostItem->takeChild(deviceRowInTree);
    endRemoveRows();
    
    // 清理设备索引缓存
    m_deviceIndexCache.remove(deviceDbId);

    // Update host's device count
    int newDeviceCount = m_devicesByHost.value(hostId).size();
    hostItem->hostData().hostPadCount = newDeviceCount;
    for (auto& hostList : m_hostsByGroup) {
        bool foundHost = false;
        for (auto& host : hostList) {
            if (host.hostId == hostId) {
                host.hostPadCount = newDeviceCount;
                foundHost = true;
                break;
            }
        }
        if(foundHost) break;
    }
    emit dataChanged(hostIndex, hostIndex, {HostPadCountRole});

    // 更新分组的设备数量显示
    QModelIndex groupIndex = parent(hostIndex);
    if (groupIndex.isValid()) {
        emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
    }

    // 清理选中和勾选状态（使用 dbId 更稳妥）
    m_selectedDeviceIds.remove(deviceDbId);
    m_checkedDeviceIds.remove(deviceDbId);

    saveConfig();

    return true;
}

void TreeModel::modifyDevice(const QString& name, const QVariantMap& newData)
{
    DeviceData* devicePtr = nullptr;
    QString deviceId;
    bool deviceFound = false;

    for (auto& deviceList : m_devicesByHost) {
        for (auto& device : deviceList) {
            if (device.name == name) {
                devicePtr = &device;
                deviceId = device.id;
                deviceFound = true;
                break;
            }
        }
        if (deviceFound) break;
    }

    if (!deviceFound) {
        qWarning() << "modifyDevice: Device with name" << name << "not found.";
        return;
    }

    QVector<int> changedRoles;
    QMapIterator<QString, QVariant> it(newData);
    while (it.hasNext()) {
        it.next();
        const QString& key = it.key();
        const QVariant& value = it.value();

        if (key == "displayName" && devicePtr->displayName != value.toString()) { devicePtr->displayName = value.toString(); changedRoles.append(DisplayNameRole); }
        else if (key == "name" && devicePtr->name != value.toString()) { devicePtr->name = value.toString(); changedRoles.append(NameRole); }
        else if (key == "image" && devicePtr->image != value.toString()) { devicePtr->image = value.toString(); changedRoles.append(ImageRole); }
        else if (key == "dpi" && devicePtr->dpi != value.toString()) { devicePtr->dpi = value.toString(); changedRoles.append(DpiRole); }
        else if (key == "fps" && devicePtr->fps != value.toString()) { devicePtr->fps = value.toString(); changedRoles.append(FpsRole); }
        else if (key == "state" && devicePtr->state != value.toString()) { devicePtr->state = value.toString(); changedRoles.append(StateRole); }
        else if (key == "refresh" && devicePtr->refresh != value.toBool()) { devicePtr->refresh = value.toBool(); changedRoles.append(RefreshRole); }
        else if (key == "adb" && devicePtr->adb != value.toInt()) { devicePtr->adb = value.toInt(); changedRoles.append(AdbRole); }
        else if (key == "data" && devicePtr->data != value.toString()) { devicePtr->data = value.toString(); changedRoles.append(DataRole); }
        else if (key == "dbId" && devicePtr->dbId != value.toString()) { devicePtr->dbId = value.toString(); changedRoles.append(DbIdRole); }
        else if (key == "dns" && devicePtr->dns != value.toString()) { devicePtr->dns = value.toString(); changedRoles.append(DnsRole); }
        else if (key == "height" && devicePtr->height != value.toString()) { devicePtr->height = value.toString(); changedRoles.append(HeightRole); }
        else if (key == "ip" && devicePtr->ip != value.toString()) { devicePtr->ip = value.toString(); changedRoles.append(IpRole); }
        else if (key == "memory" && devicePtr->memory != value.toInt()) { devicePtr->memory = value.toInt(); changedRoles.append(MemoryRole); }
        else if (key == "shortId" && devicePtr->shortId != value.toString()) { devicePtr->shortId = value.toString(); changedRoles.append(ShortIdRole); }
        else if (key == "width" && devicePtr->width != value.toString()) { devicePtr->width = value.toString(); changedRoles.append(WidthRole); }
        else if (key == "aospVersion" && devicePtr->aospVersion != value.toString()) { devicePtr->aospVersion = value.toString(); changedRoles.append(AospVersionRole); }
        else if (key == "hostIp" && devicePtr->hostIp != value.toString()) { devicePtr->hostIp = value.toString(); changedRoles.append(HostIpRole); }
        else if (key == "macvlanIp" && devicePtr->macvlanIp != value.toString()) { devicePtr->macvlanIp = value.toString(); changedRoles.append(MacvlanIpRole); }
        else if (key == "network_mode" && devicePtr->networkMode != value.toString()) { devicePtr->networkMode = value.toString(); changedRoles.append(NetworkModeRole); }
        else if (key == "macvlan_ip" && devicePtr->macvlanIp != value.toString()) { devicePtr->macvlanIp = value.toString(); changedRoles.append(MacvlanIpRole); }
        else if (key == "timezone" && devicePtr->timezone != value.toString()) { devicePtr->timezone = value.toString(); changedRoles.append(TimeZoneRole); }
        else if (key == "locale" && devicePtr->locale != value.toString()) { devicePtr->locale = value.toString(); changedRoles.append(LocaleRole); }
    }

    if (!changedRoles.isEmpty()) {
        QModelIndex deviceIndex = findIndex(name, TypeDevice);
        if (deviceIndex.isValid()) {
            DeviceItem* deviceItem = static_cast<DeviceItem*>(deviceIndex.internalPointer());
            if (deviceItem) {
                deviceItem->deviceData() = *devicePtr;
                emit dataChanged(deviceIndex, deviceIndex, changedRoles);
            }
        }
        saveConfig();
    }
}

void TreeModel::modifyDeviceEx(const QString &shortId, const QVariantMap &newData)
{
    DeviceData* devicePtr = nullptr;
    bool deviceFound = false;

    for (auto& deviceList : m_devicesByHost) {
        for (auto& device : deviceList) {
            if (device.shortId == shortId) {
                devicePtr = &device;
                deviceFound = true;
                break;
            }
        }
        if (deviceFound) break;
    }

    if (!deviceFound) {
        qWarning() << "modifyDeviceEx: Device with shortId" << shortId << "not found.";
        return;
    }

    QVector<int> changedRoles;
    QMapIterator<QString, QVariant> it(newData);
    while (it.hasNext()) {
        it.next();
        const QString& key = it.key();
        const QVariant& value = it.value();

        if (key == "displayName" && devicePtr->displayName != value.toString()) { devicePtr->displayName = value.toString(); changedRoles.append(DisplayNameRole); }
        else if (key == "name" && devicePtr->name != value.toString()) { devicePtr->name = value.toString(); changedRoles.append(NameRole); }
        else if (key == "image" && devicePtr->image != value.toString()) { devicePtr->image = value.toString(); changedRoles.append(ImageRole); }
        else if (key == "dpi" && devicePtr->dpi != value.toString()) { devicePtr->dpi = value.toString(); changedRoles.append(DpiRole); }
        else if (key == "fps" && devicePtr->fps != value.toString()) { devicePtr->fps = value.toString(); changedRoles.append(FpsRole); }
        else if (key == "state" && devicePtr->state != value.toString()) { devicePtr->state = value.toString(); changedRoles.append(StateRole); }
        else if (key == "refresh" && devicePtr->refresh != value.toBool()) { devicePtr->refresh = value.toBool(); changedRoles.append(RefreshRole); }
        else if (key == "adb" && devicePtr->adb != value.toInt()) { devicePtr->adb = value.toInt(); changedRoles.append(AdbRole); }
        else if (key == "data" && devicePtr->data != value.toString()) { devicePtr->data = value.toString(); changedRoles.append(DataRole); }
        else if (key == "dbId" && devicePtr->dbId != value.toString()) { devicePtr->dbId = value.toString(); changedRoles.append(DbIdRole); }
        else if (key == "dns" && devicePtr->dns != value.toString()) { devicePtr->dns = value.toString(); changedRoles.append(DnsRole); }
        else if (key == "height" && devicePtr->height != value.toString()) { devicePtr->height = value.toString(); changedRoles.append(HeightRole); }
        else if (key == "ip" && devicePtr->ip != value.toString()) { devicePtr->ip = value.toString(); changedRoles.append(IpRole); }
        else if (key == "memory" && devicePtr->memory != value.toInt()) { devicePtr->memory = value.toInt(); changedRoles.append(MemoryRole); }
        else if (key == "shortId" && devicePtr->shortId != value.toString()) { devicePtr->shortId = value.toString(); changedRoles.append(ShortIdRole); }
        else if (key == "width" && devicePtr->width != value.toString()) { devicePtr->width = value.toString(); changedRoles.append(WidthRole); }
        else if (key == "aospVersion" && devicePtr->aospVersion != value.toString()) { devicePtr->aospVersion = value.toString(); changedRoles.append(AospVersionRole); }
        else if (key == "hostIp" && devicePtr->hostIp != value.toString()) { devicePtr->hostIp = value.toString(); changedRoles.append(HostIpRole); }
        else if (key == "macvlanIp" && devicePtr->macvlanIp != value.toString()) { devicePtr->macvlanIp = value.toString(); changedRoles.append(MacvlanIpRole); }
        else if (key == "macvlan_ip" && devicePtr->macvlanIp != value.toString()) { devicePtr->macvlanIp = value.toString(); changedRoles.append(MacvlanIpRole); }
        else if (key == "timezone" && devicePtr->timezone != value.toString()) { devicePtr->timezone = value.toString(); changedRoles.append(TimeZoneRole); }
        else if (key == "locale" && devicePtr->locale != value.toString()) { devicePtr->locale = value.toString(); changedRoles.append(LocaleRole); }
    }

    if (!changedRoles.isEmpty()) {
        QModelIndex deviceIndex;
        bool indexFound = false;
        for(int i=0; i<m_rootItem->childCount(); ++i){
            auto groupItem = static_cast<GroupItem*>(m_rootItem->child(i));
            for(int j=0; j<groupItem->childCount(); ++j){
                auto hostItem = static_cast<HostItem*>(groupItem->child(j));
                for(int k=0; k<hostItem->childCount(); ++k){
                    auto deviceItem = static_cast<DeviceItem*>(hostItem->child(k));
                    if(deviceItem->deviceData().shortId == shortId){
                        deviceIndex = index(k, 0, index(j, 0, index(i, 0, QModelIndex())));
                        indexFound = true;
                        break;
                    }
                }
                if(indexFound) break;
            }
            if(indexFound) break;
        }

        if (deviceIndex.isValid()) {
            DeviceItem* deviceItem = static_cast<DeviceItem*>(deviceIndex.internalPointer());
            if (deviceItem) {
                deviceItem->deviceData() = *devicePtr;
                emit dataChanged(deviceIndex, deviceIndex, changedRoles);
            }
        }
        saveConfig();
    }
}

void TreeModel::updateDevice(const QString& dbId, const QVariantMap& device)
{
    if (dbId.isEmpty()) {
        qWarning() << "updateDevice: Empty dbId";
        return;
    }

    DeviceData* devicePtr = nullptr;
    QString hostId;
    int deviceRow = -1;

    // 在后备容器中查找设备
    for (auto it = m_devicesByHost.begin(); it != m_devicesByHost.end(); ++it) {
        QList<DeviceData>& list = it.value();
        for (int i = 0; i < list.size(); ++i) {
            if (list[i].dbId == dbId) {
                devicePtr = &list[i];
                deviceRow = i;
                hostId = it.key();
                break;
            }
        }
        if (devicePtr) break;
    }

    if (!devicePtr) {
        qWarning() << "updateDevice: Device with dbId" << dbId << "not found.";
        return;
    }

    // 记录旧的勾选/选中状态
    const bool wasChecked = m_checkedDeviceIds.contains(dbId);
    const bool wasSelected = m_selectedDeviceIds.contains(dbId);

    QVector<int> changedRoles;
    QMapIterator<QString, QVariant> it(device);
    while (it.hasNext()) {
        it.next();
        const QString& key = it.key();
        const QVariant& value = it.value();

        if (key == "displayName" && devicePtr->displayName != value.toString()) { devicePtr->displayName = value.toString(); changedRoles.append(DisplayNameRole); }
        else if (key == "name" && devicePtr->name != value.toString()) { devicePtr->name = value.toString(); changedRoles.append(NameRole); }
        else if (key == "image" && devicePtr->image != value.toString()) { devicePtr->image = value.toString(); changedRoles.append(ImageRole); }
        else if (key == "dpi" && devicePtr->dpi != value.toString()) { devicePtr->dpi = value.toString(); changedRoles.append(DpiRole); }
        else if (key == "fps" && devicePtr->fps != value.toString()) { devicePtr->fps = value.toString(); changedRoles.append(FpsRole); }
        else if (key == "state" && devicePtr->state != value.toString()) { devicePtr->state = value.toString(); changedRoles.append(StateRole); }
        else if (key == "refresh" && devicePtr->refresh != value.toBool()) { devicePtr->refresh = value.toBool(); changedRoles.append(RefreshRole); }
        else if (key == "adb" && devicePtr->adb != value.toInt()) { devicePtr->adb = value.toInt(); changedRoles.append(AdbRole); }
        else if (key == "data" && devicePtr->data != value.toString()) { devicePtr->data = value.toString(); changedRoles.append(DataRole); }
        else if (key == "dbId" && devicePtr->dbId != value.toString()) { devicePtr->dbId = value.toString(); changedRoles.append(DbIdRole); }
        else if (key == "dns" && devicePtr->dns != value.toString()) { devicePtr->dns = value.toString(); changedRoles.append(DnsRole); }
        else if (key == "height" && devicePtr->height != value.toString()) { devicePtr->height = value.toString(); changedRoles.append(HeightRole); }
        else if (key == "ip" && devicePtr->ip != value.toString()) { devicePtr->ip = value.toString(); changedRoles.append(IpRole); }
        else if (key == "memory" && devicePtr->memory != value.toInt()) { devicePtr->memory = value.toInt(); changedRoles.append(MemoryRole); }
        else if (key == "shortId" && devicePtr->shortId != value.toString()) { devicePtr->shortId = value.toString(); changedRoles.append(ShortIdRole); }
        else if (key == "width" && devicePtr->width != value.toString()) { devicePtr->width = value.toString(); changedRoles.append(WidthRole); }
        else if (key == "aospVersion" && devicePtr->aospVersion != value.toString()) { devicePtr->aospVersion = value.toString(); changedRoles.append(AospVersionRole); }
        else if (key == "hostIp" && devicePtr->hostIp != value.toString()) { devicePtr->hostIp = value.toString(); changedRoles.append(HostIpRole); }
        else if (key == "macvlanIp" && devicePtr->macvlanIp != value.toString()) { devicePtr->macvlanIp = value.toString(); changedRoles.append(MacvlanIpRole); }
        else if (key == "macvlan_ip" && devicePtr->macvlanIp != value.toString()) { devicePtr->macvlanIp = value.toString(); changedRoles.append(MacvlanIpRole); }
        else if (key == "timezone" && devicePtr->timezone != value.toString()) { devicePtr->timezone = value.toString(); changedRoles.append(TimeZoneRole); }
        else if (key == "locale" && devicePtr->locale != value.toString()) { devicePtr->locale = value.toString(); changedRoles.append(LocaleRole); }
    }

    // 恢复勾选/选中状态
    if (wasChecked) m_checkedDeviceIds.insert(devicePtr->dbId); else m_checkedDeviceIds.remove(devicePtr->dbId);
    if (wasSelected) m_selectedDeviceIds.insert(devicePtr->dbId); else m_selectedDeviceIds.remove(devicePtr->dbId);

    if (!changedRoles.isEmpty()) {
        QModelIndex deviceIndex = findIndex(dbId, TypeDevice);
        QModelIndex hostIndex;
        if (!hostId.isEmpty()) {
            hostIndex = findIndex(hostId, TypeHost);
        }
        
        if (deviceIndex.isValid()) {
            DeviceItem* deviceItem = static_cast<DeviceItem*>(deviceIndex.internalPointer());
            if (deviceItem) {
                deviceItem->deviceData() = *devicePtr;
                emit dataChanged(deviceIndex, deviceIndex, changedRoles);
            }
            // 如果设备状态改变，需要通知主机节点更新 HostPadCountRole（用于显示过滤后的设备数量）
            // 同时需要通知分组节点更新 GroupPadCountRole
            if (changedRoles.contains(StateRole) && hostIndex.isValid()) {
                emit dataChanged(hostIndex, hostIndex, {HostPadCountRole});
                QModelIndex groupIndex = parent(hostIndex);
                if (groupIndex.isValid()) {
                    emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
                }
            }
        } else if (hostIndex.isValid()) {
            // 索引缺失时，尝试通过父节点发出粗粒度变更
            emit dataChanged(hostIndex, hostIndex, changedRoles);
            // 如果设备状态改变，也需要更新 HostPadCountRole 和 GroupPadCountRole
            if (changedRoles.contains(StateRole)) {
                emit dataChanged(hostIndex, hostIndex, {HostPadCountRole});
                QModelIndex groupIndex = parent(hostIndex);
                if (groupIndex.isValid()) {
                    emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
                }
            }
        }
        saveConfig();
    }
}

void TreeModel::modifyHost(const QString& hostIp, const QVariantMap& newData)
{
    HostData* hostPtr = nullptr;
    QString hostId;
    bool hostFound = false;

    for (auto& hostList : m_hostsByGroup) {
        for (auto& host : hostList) {
            if (host.ip == hostIp) {
                hostPtr = &host;
                hostId = host.hostId;
                hostFound = true;
                break;
            }
        }
        if (hostFound) break;
    }

    if (!hostFound) {
        qWarning() << "modifyHost: Host with ip" << hostIp << "not found.";
        return;
    }

    QVector<int> changedRoles;
    bool stateDidChange = false;

    QMapIterator<QString, QVariant> it(newData);
    while (it.hasNext()) {
        it.next();
        const QString& key = it.key();
        const QVariant& value = it.value();

        if (key == "hostName" && hostPtr->hostName != value.toString()) {
            hostPtr->hostName = value.toString();
            changedRoles.append(HostNameRole);
        } else if (key == "ip" && hostPtr->ip != value.toString()) {
            hostPtr->ip = value.toString();
            changedRoles.append(IpRole);
        } else if (key == "state" && hostPtr->state != value.toString()) {
            hostPtr->state = value.toString();
            changedRoles.append(StateRole);
            stateDidChange = true;
        } else if (key == "selected" && hostPtr->selected != value.toBool()) {
            hostPtr->selected = value.toBool();
            changedRoles.append(SelectedRole);
        } else if (key == "updateTime" && hostPtr->updateTime != value.toString()) {
            hostPtr->updateTime = value.toString();
            changedRoles.append(UpdateTimeRole);
        }
    }

    if (!changedRoles.isEmpty()) {
        QModelIndex hostIndex = findIndex(hostId, TypeHost);
        if (hostIndex.isValid()) {
            HostItem* hostItem = static_cast<HostItem*>(hostIndex.internalPointer());
            if (hostItem) {
                hostItem->hostData() = *hostPtr;
                emit dataChanged(hostIndex, hostIndex, changedRoles);

                if (stateDidChange) {
                    QString newDeviceState = (hostPtr->state == "offline") ? "offline" : "running";
                    
                    if (m_devicesByHost.contains(hostId)) {
                        for (auto& device : m_devicesByHost[hostId]) {
                            device.state = newDeviceState;
                        }
                    }
                    
                    for (int i = 0; i < hostItem->childCount(); ++i) {
                        DeviceItem* deviceItem = static_cast<DeviceItem*>(hostItem->child(i));
                        if (deviceItem->deviceData().state != newDeviceState) {
                            deviceItem->deviceData().state = newDeviceState;
                            QModelIndex deviceIndex = index(i, 0, hostIndex);
                            emit dataChanged(deviceIndex, deviceIndex, {StateRole});
                        }
                    }
                    
                    // 主机状态改变时，需要通知分组更新 GroupPadCountRole（用于显示过滤后的设备数量）
                    QModelIndex groupIndex = parent(hostIndex);
                    if (groupIndex.isValid()) {
                        emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
                    }
                }
            }
        }
        saveConfig();
    }
}

void TreeModel::removeDevicesByHostIp(const QString& hostIp)
{
    QString hostId = "";
    bool hostFound = false;
    for (const auto& hostList : m_hostsByGroup) {
        for (const auto& host : hostList) {
            if (host.ip == hostIp) {
                hostId = host.hostId;
                hostFound = true;
                break;
            }
        }
        if (hostFound) {
            break;
        }
    }

    if (!hostFound) {
        qWarning() << "Host with IP not found for removing devices:" << hostIp;
        return;
    }

    if (!m_devicesByHost.contains(hostId)) {
        qWarning() << "Host" << hostId << "found but has no devices to remove.";
        return;
    }

    // Find the host index in the tree
    QModelIndex hostIndex = findIndex(hostId, TypeHost);
    if (!hostIndex.isValid()) {
        qWarning() << "Host item not found in tree for hostId:" << hostId;
        return;
    }

    HostItem* hostItem = static_cast<HostItem*>(hostIndex.internalPointer());
    int deviceCount = hostItem->childCount();

    if (deviceCount == 0) {
        qWarning() << "Host" << hostId << "has no devices in tree to remove.";
        return;
    }

    // Clean up selection and checked states for the devices being removed
    const QList<DeviceData>& devicesToRemove = m_devicesByHost.value(hostId);
    for (const auto& device : devicesToRemove) {
        m_selectedDeviceIds.remove(device.dbId);
        m_checkedDeviceIds.remove(device.dbId);
    }

    // Remove all device items from the tree
    beginRemoveRows(hostIndex, 0, deviceCount - 1);
    while (hostItem->childCount() > 0) {
        delete hostItem->takeChild(0);
    }
    endRemoveRows();

    // Remove all devices from backing store
    // 同时清理持久索引缓存中属于该主机的条目
    if (m_devicesByHost.contains(hostId)) {
        const QList<DeviceData> toRemove = m_devicesByHost.value(hostId);
        for (const auto& d : toRemove) {
            m_deviceIndexCache.remove(d.dbId);
        }
        m_devicesByHost.remove(hostId);
    }

    // 对于成为“空主机”的情况，保持之前的勾选语义：如果所在分组在 m_checkedGroupIds 中，则将该空主机设为勾选
    if (m_checkedGroupIds.contains(hostItem->hostData().groupId)) {
        m_checkedHostIds.insert(hostId);
        emit dataChanged(hostIndex, hostIndex, {CheckedRole});
    }

    // Update host's device count
    hostItem->hostData().hostPadCount = 0;
    for (auto& hostList : m_hostsByGroup) {
        for (auto& host : hostList) {
            if (host.hostId == hostId) {
                host.hostPadCount = 0;
                break;
            }
        }
    }
    emit dataChanged(hostIndex, hostIndex, {HostPadCountRole});

    // 更新分组的设备数量显示
    QModelIndex groupIndex = parent(hostIndex);
    if (groupIndex.isValid()) {
        emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
    }

    saveConfig();
}

int TreeModel::generateNewGroupId()
{
    int maxId = 0;
    for(const auto& group : m_groups) {
        if (group.groupId > maxId) {
            maxId = group.groupId;
        }
    }
    return maxId + 1;
}

void TreeModel::parseData(const QByteArray& data, QList<GroupData>& groups, QMap<int, QList<HostData>>& hostsByGroup, QMap<QString, QList<DeviceData>>& devicesByHost)
{
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray()) {
        qWarning() << "JSON is not an array.";
        return;
    }
    QJsonArray jsonArray = doc.array();

    for (const QJsonValue &groupValue : jsonArray) {
        QJsonObject groupObject = groupValue.toObject();
        GroupData group;
        parseGroup(groupObject, group);
        groups.append(group);

        QList<HostData> hostList;
        if (groupObject.contains("hosts") && groupObject["hosts"].isArray()) {
            for (const QJsonValue &hostValue : groupObject["hosts"].toArray()) {
                QJsonObject hostObject = hostValue.toObject();
                HostData host;
                parseHost(hostObject, host);
                host.groupId = group.groupId;
                hostList.append(host);

                qDebug() << host.hostId << host.groupId << host.hostName << host.ip;

                QList<DeviceData> deviceList;
                if (hostObject.contains("userPads") && hostObject["userPads"].isArray()) {
                    for (const QJsonValue &padValue : hostObject["userPads"].toArray()) {
                        DeviceData device;
                        parseDevice(padValue.toObject(), device);
                        device.groupId = group.groupId;
                        device.hostId = host.hostId;
                        deviceList.append(device);
                    }
                }
                devicesByHost.insert(host.hostId, deviceList);
            }
        }
        hostsByGroup.insert(group.groupId, hostList);
    }
}

void TreeModel::parseGroup(const QJsonObject& groupObject, GroupData& group)
{
    group.groupId = groupObject["groupId"].toInt();
    group.groupName = groupObject["groupName"].toString();
    group.groupPadCount = groupObject["groupPadCount"].toInt();
}

void TreeModel::parseHost(const QJsonObject& hostObject, HostData& host)
{
    host.hostId = hostObject["hostId"].toString();
    host.hostName = hostObject["hostName"].toString();
    host.ip = hostObject["ip"].toString();
    host.hostPadCount = hostObject["hostPadCount"].toInt(0);
    host.updateTime = hostObject["updateTime"].toString();
    host.state = hostObject["state"].toString();
    host.selected = hostObject["selected"].toBool(false);
}

void TreeModel::parseDevice(const QJsonObject& padObject, DeviceData& device)
{
    auto displayName = padObject["displayName"].toString();
    auto shortId = padObject["shortId"].toString();
    auto aospVersion = padObject["aospVersion"].toString();
    auto hostIp = padObject["hostIp"].toString();
    auto dbId = padObject["dbId"].toString();

    device.id = padObject["id"].toString();
    device.name = padObject["name"].toString();
    device.displayName = displayName.isEmpty() ? padObject["user_name"].toString() : displayName;
    device.shortId = shortId.isEmpty() ? padObject["short_id"].toString() : shortId;
    device.dbId = dbId.isEmpty() ? padObject["db_id"].toString() : dbId;
    device.image = padObject["image"].toString();
    device.state = padObject["state"].toString();
    device.adb = padObject["adb"].toInt();
    device.data = padObject["data"].toString();
    device.dns = padObject["dns"].toString();
    device.dpi = padObject["dpi"].toString();
    device.fps = padObject["fps"].toString();
    device.height = padObject["height"].toString();
    device.ip = padObject["ip"].toString();
    device.memory = padObject["memory"].toInt();
    device.created = padObject["created"].toString();
    device.width = padObject["width"].toString();
    device.timezone = padObject["timezone"].toString();
    device.locale = padObject["locale"].toString();

    device.aospVersion = aospVersion.isEmpty() ? padObject["aosp_version"].toString() : aospVersion;
    device.hostIp = hostIp.isEmpty() ? padObject["host_ip"].toString() : hostIp;
    // Macvlan IP字段
    // 接口返回的字段名为 macvlan_ip
    // 配置文件保存的字段名为 macvlanIp
    // 优先使用接口字段名（下划线），如果不存在则使用配置文件字段名（驼峰）
    QJsonValue macvlanIpValue;
    if (padObject.contains("macvlan_ip")) {
        // 从接口数据读取（下划线命名）
        macvlanIpValue = padObject["macvlan_ip"];
    } else {
        // 从配置文件读取（驼峰命名）
        macvlanIpValue = padObject["macvlanIp"];
    }
    device.macvlanIp = macvlanIpValue.toString();
    // TCP端口字段
    // 接口返回的字段名为 tcp_port, tcp_audio_port, tcp_control_port
    // 配置文件保存的字段名为 tcpVideoPort, tcpAudioPort, tcpControlPort
    // 优先使用接口字段名（下划线），如果不存在则使用配置文件字段名（驼峰）
    QJsonValue tcpPortValue;
    QJsonValue tcpAudioPortValue;
    QJsonValue tcpControlPortValue;
    
    if (padObject.contains("tcp_port")) {
        // 从接口数据读取（下划线命名）
        tcpPortValue = padObject["tcp_port"];
        tcpAudioPortValue = padObject["tcp_audio_port"];
        tcpControlPortValue = padObject["tcp_control_port"];
    } else {
        // 从配置文件读取（驼峰命名）
        tcpPortValue = padObject["tcpVideoPort"];
        tcpAudioPortValue = padObject["tcpAudioPort"];
        tcpControlPortValue = padObject["tcpControlPort"];
    }
    
    device.tcpVideoPort = tcpPortValue.isDouble() ? tcpPortValue.toInt() : (tcpPortValue.isString() ? tcpPortValue.toString().toInt() : 0);
    device.tcpAudioPort = tcpAudioPortValue.isDouble() ? tcpAudioPortValue.toInt() : (tcpAudioPortValue.isString() ? tcpAudioPortValue.toString().toInt() : 0);
    device.tcpControlPort = tcpControlPortValue.isDouble() ? tcpControlPortValue.toInt() : (tcpControlPortValue.isString() ? tcpControlPortValue.toString().toInt() : 0);
    
    // 网络模式字段
    // 接口返回的字段名为 network_mode
    // 配置文件保存的字段名为 networkMode
    // 优先使用接口字段名（下划线），如果不存在则使用配置文件字段名（驼峰）
    if (padObject.contains("network_mode")) {
        device.networkMode = padObject["network_mode"].toString();
    } else {
        device.networkMode = "bridge"; // 默认值为空，若不指定则使用配置的连接方式
    }

    device.checked = false;
    device.selected = false;
    device.refresh = false;
}

QModelIndex TreeModel::index(int row, int column, const QModelIndex &parent) const
{
    if (!hasIndex(row, column, parent)) return QModelIndex();
    TreeItem *parentItem = !parent.isValid() ? m_rootItem : static_cast<TreeItem*>(parent.internalPointer());
    if (!parentItem) return QModelIndex();
    
    TreeItem *childItem = parentItem->child(row);
    if (childItem) return createIndex(row, column, childItem);
    return QModelIndex();
}

QModelIndex TreeModel::parent(const QModelIndex &index) const
{
    if (!index.isValid()) return QModelIndex();
    TreeItem *childItem = static_cast<TreeItem*>(index.internalPointer());
    if (!childItem) return QModelIndex();
    
    TreeItem *parentItem = childItem->parentItem();
    if (!parentItem || parentItem == m_rootItem) return QModelIndex();
    
    return createIndex(parentItem->row(), 0, parentItem);
}

int TreeModel::rowCount(const QModelIndex &parent) const
{
    if (parent.column() > 0) return 0;
    TreeItem *parentItem = !parent.isValid() ? m_rootItem : static_cast<TreeItem*>(parent.internalPointer());
    if (!parentItem) return 0;
    return parentItem->childCount();
}

int TreeModel::columnCount(const QModelIndex &parent) const {
    Q_UNUSED(parent);
    return 1;
}

QVariant TreeModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid()) return QVariant();
    TreeItem *item = static_cast<TreeItem*>(index.internalPointer());
    if (!item) return QVariant();
    
    switch (item->type()) {
        case TypeGroup: {
            GroupItem* groupItem = static_cast<GroupItem*>(item);
            const GroupData& group = groupItem->groupData();
            switch (role) {
                case ItemTypeRole: return TypeGroup;
                case GroupNameRole: return group.groupName;
                case GroupIdRole: return group.groupId;
                case GroupPadCountRole: return item->childCount();
                case CheckedRole: {
                    int totalHosts = item->childCount();
                    if (totalHosts == 0) {
                        return m_checkedGroupIds.contains(group.groupId);
                    }

                    int checkedHostCount = 0;
                    int partialHostCount = 0;
                    // 检查每个主机的勾选状态
                    for(int i = 0; i < totalHosts; ++i) {
                        HostItem* childHostItem = static_cast<HostItem*>(item->child(i));
                        bool hostChecked = true;
                        bool hasCheckedDevice = false;

                        const int childDeviceCount = childHostItem->childCount();
                        if (childDeviceCount == 0) {
                            // 无设备时，使用主机的勾选状态集
                            hostChecked = m_checkedHostIds.contains(childHostItem->hostData().hostId);
                            hasCheckedDevice = hostChecked;
                        } else {
                            // 有设备时，检查设备勾选状态
                            int checkedDeviceCount = 0;
                            for(int j = 0; j < childDeviceCount; ++j){
                                DeviceItem* deviceItem = static_cast<DeviceItem*>(childHostItem->child(j));
                                if(m_checkedDeviceIds.contains(deviceItem->deviceData().dbId)){
                                    checkedDeviceCount++;
                                    hasCheckedDevice = true;
                                }
                            }
                            // 完全选中：所有设备都选中
                            hostChecked = (checkedDeviceCount == childDeviceCount);
                            // 部分选中：有选中设备但不是全部
                            if (hasCheckedDevice && !hostChecked) {
                                partialHostCount++;
                            }
                        }

                        if (hostChecked) {
                            checkedHostCount++;
                        }
                    }

                    // 如果有任何主机是部分选中，分组应该是部分选中
                    if (partialHostCount > 0) {
                        return QVariant(); // Indeterminate
                    }
                    // 所有主机都完全选中
                    if (checkedHostCount == totalHosts) {
                        return true;
                    }
                    // 有部分主机完全选中，其他未选中
                    if (checkedHostCount > 0) {
                        return QVariant(); // Indeterminate
                    }
                    // 所有主机都未选中
                    return false;
                }
                default: return QVariant();
            }
        }
        case TypeHost: {
            HostItem* hostItem = static_cast<HostItem*>(item);
            const HostData& host = hostItem->hostData();
            switch (role) {
                case ItemTypeRole: return TypeHost;
                case GroupIdRole: return host.groupId;
                case HostNameRole: return host.hostName;
                case HostIdRole: return host.hostId;
                case IpRole: return host.ip;
                case HostPadCountRole: return item->childCount();
                case UpdateTimeRole: return host.updateTime;
                case StateRole: return host.state;
                case SelectedRole: return host.selected;
                case CheckedRole: {
                    const int deviceCount = item->childCount();
                    if (deviceCount == 0) {
                        return m_checkedHostIds.contains(host.hostId);
                    }
                    int checkedCount = 0;
                    for(int i = 0; i < deviceCount; ++i) {
                        DeviceItem* deviceItem = static_cast<DeviceItem*>(item->child(i));
                        if(m_checkedDeviceIds.contains(deviceItem->deviceData().dbId)){
                            checkedCount++;
                        }
                    }
                    if (checkedCount == 0) return false;
                    if (checkedCount == deviceCount) return true;
                    return QVariant(); // Indeterminate
                }
                default: return QVariant();
            }
        }
        case TypeDevice: {
            DeviceItem* deviceItem = static_cast<DeviceItem*>(item);
            const DeviceData& device = deviceItem->deviceData();
            switch (role) {
                case ItemTypeRole: return TypeDevice;
                case ItemDataRole: return QVariant::fromValue(device);
                case AdbRole: return device.adb;
                case CreatedRole: return device.created;
                case DataRole: return device.data;
                case DbIdRole: return device.dbId;
                case DisplayNameRole: return device.displayName;
                case DnsRole: return device.dns;
                case DpiRole: return device.dpi;
                case FpsRole: return device.fps;
                case GroupIdRole: return device.groupId;
                case HeightRole: return device.height;
                case HostIdRole: return device.hostId;
                case IdRole: return device.id;
                case ImageRole: return device.image;
                case IpRole: return device.ip;
                case MemoryRole: return device.memory;
                case NameRole: return device.name;
                case RefreshRole: return device.refresh;
                case ShortIdRole: return device.shortId;
                case StateRole: return device.state;
                case WidthRole: return device.width;
                case CheckedRole: return m_checkedDeviceIds.contains(device.dbId);
                case SelectedRole: return m_selectedDeviceIds.contains(device.dbId);
                case AospVersionRole: return device.aospVersion;
                case HostIpRole: return device.hostIp;
                case TcpVideoPortRole: {
                    qDebug() << "data() TcpVideoPortRole for" << device.dbId << "=" << device.tcpVideoPort;
                    return device.tcpVideoPort;
                }
                case TcpAudioPortRole: {
                    qDebug() << "data() TcpAudioPortRole for" << device.dbId << "=" << device.tcpAudioPort;
                    return device.tcpAudioPort;
                }
                case TcpControlPortRole: {
                    qDebug() << "data() TcpControlPortRole for" << device.dbId << "=" << device.tcpControlPort;
                    return device.tcpControlPort;
                }
                case MacvlanIpRole: return device.macvlanIp;
                case NetworkModeRole: 
                {
                    return device.networkMode;
                }
                case TimeZoneRole: return device.timezone;
                case LocaleRole: return device.locale;
                default: return QVariant();
            }
        }
        default:
            return QVariant();
    }
}

bool TreeModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    if (!index.isValid()) return false;

    TreeItem *item = static_cast<TreeItem*>(index.internalPointer());
    if (!item) return false;
    
    bool success = false;

    switch (item->type()) {
        case TypeGroup: {
            GroupItem* groupItem = static_cast<GroupItem*>(item);
            GroupData& group = groupItem->groupData();
            switch (role) {
                case CheckedRole:
                    checkGroup(group.groupId, value.toBool());
                    return true;
                case GroupNameRole:
                    return renameGroup(group.groupId, value.toString());
                default:
                    return false;
            }
            break;
        }
        case TypeHost: {
            HostItem* hostItem = static_cast<HostItem*>(item);
            HostData& host = hostItem->hostData();
            switch (role) {
                case CheckedRole:
                    checkHost(host.hostId, value.toBool());
                    return true;
                case SelectedRole:
                    host.selected = value.toBool();
                    success = true;
                    break;
                case UpdateTimeRole:
                    host.updateTime = value.toString();
                    success = true;
                    break;
                case StateRole:
                    host.state = value.toString();
                    success = true;
                    break;
                default:
                    return false;
            }
            break;
        }
        case TypeDevice: {
            DeviceItem* deviceItem = static_cast<DeviceItem*>(item);
            DeviceData& device = deviceItem->deviceData();
            switch (role) {
                case CheckedRole:
                    checkDevice(device.dbId, value.toBool());
                    return true;
                case SelectedRole:
                    selectDevice(device.dbId, value.toBool());
                    return true;
                case DisplayNameRole:
                    device.displayName = value.toString();
                    success = true;
                    break;
                case NameRole:
                    device.name = value.toString();
                    success = true;
                    break;
                case ImageRole:
                    device.image = value.toString();
                    success = true;
                    break;
                case DpiRole:
                    device.dpi = value.toString();
                    success = true;
                    break;
                case FpsRole:
                    device.fps = value.toString();
                    success = true;
                    break;
                case StateRole:
                    device.state = value.toString();
                    success = true;
                    break;
                case RefreshRole:
                    device.refresh = value.toBool();
                    success = true;
                    break;
                case AdbRole:
                    device.adb = value.toInt();
                    success = true;
                    break;
                case DataRole:
                    device.data = value.toString();
                    success = true;
                    break;
                case DbIdRole:
                    device.dbId = value.toString();
                    success = true;
                    break;
                case DnsRole:
                    device.dns = value.toString();
                    success = true;
                    break;
                case HeightRole:
                    device.height = value.toString();
                    success = true;
                    break;
                case IpRole:
                    device.ip = value.toString();
                    success = true;
                    break;
                case MemoryRole:
                    device.memory = value.toInt();
                    success = true;
                    break;
                case ShortIdRole:
                    device.shortId = value.toString();
                    success = true;
                    break;
                case WidthRole:
                    device.width = value.toString();
                    success = true;
                    break;
                case AospVersionRole:
                    device.aospVersion = value.toString();
                    success = true;
                    break;
                case HostIpRole:
                    device.hostIp = value.toString();
                    success = true;
                    break;
                case MacvlanIpRole:
                    device.macvlanIp = value.toString();
                    success = true;
                    break;
                case NetworkModeRole:
                    device.networkMode = value.toString();
                    success = true;
                    break;
                case LocaleRole:
                    device.locale = value.toString();
                    success = true;
                    break;
                case TimeZoneRole:
                    device.timezone = value.toString();
                    success = true;
                    break;
                default:
                    return false;
            }
            break;
        }
        default:
            return false;
    }

    if (success) {
        emit dataChanged(index, index, {role});
        saveConfig();
    }

    return success;
}


Qt::ItemFlags TreeModel::flags(const QModelIndex &index) const
{
    if (!index.isValid()) return Qt::NoItemFlags;
    return Qt::ItemIsEditable | QAbstractItemModel::flags(index);
}

QHash<int, QByteArray> TreeModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[ItemTypeRole] = "itemType";
    roles[ItemDataRole] = "itemData";
    roles[AdbRole] = "adb";
    roles[CheckedRole] = "checked";
    roles[CreatedRole] = "created";
    roles[DataRole] = "data";
    roles[DbIdRole] = "dbId";
    roles[DisplayNameRole] = "displayName";
    roles[DnsRole] = "dns";
    roles[DpiRole] = "dpi";
    roles[FpsRole] = "fps";
    roles[GroupIdRole] = "groupId";
    roles[GroupNameRole] = "groupName";
    roles[GroupPadCountRole] = "groupPadCount";
    roles[HeightRole] = "height";
    roles[HostIdRole] = "hostId";
    roles[HostNameRole] = "hostName";
    roles[HostPadCountRole] = "hostPadCount";
    roles[IdRole] = "id";
    roles[ImageRole] = "image";
    roles[IpRole] = "ip";
    roles[MemoryRole] = "memory";
    roles[NameRole] = "name";
    roles[RefreshRole] = "refresh";
    roles[SelectedRole] = "selected";
    roles[ShortIdRole] = "shortId";
    roles[StateRole] = "state";
    roles[UpdateTimeRole] = "updateTime";
    roles[WidthRole] = "width";
    roles[AospVersionRole] = "aospVersion";
    roles[HostIpRole] = "hostIp";
    roles[TcpVideoPortRole] = "tcpVideoPort";
    roles[TcpAudioPortRole] = "tcpAudioPort";
    roles[TcpControlPortRole] = "tcpControlPort";
    roles[MacvlanIpRole] = "macvlanIp";
    roles[NetworkModeRole] = "networkMode";
    roles[TimeZoneRole] = "timezone";
    roles[LocaleRole] = "locale";

    return roles;
}

bool TreeModel::hasChildren(const QModelIndex &parent) const{
    if (parent.isValid() && parent.column() != 0) return false;
    TreeItem* parentItem = !parent.isValid() ? m_rootItem : static_cast<TreeItem*>(parent.internalPointer());
    if (!parentItem) return false;
    return parentItem->childCount() > 0;
}

void TreeModel::selectGroup(int groupId, bool selected)
{
    // In a 3-level model, selecting a group might not be a primary action.
    // This function could be adapted to select all devices in a group if needed.
    // For now, we leave it, but it might need reconsideration based on UX.
}

void TreeModel::selectDevice(const QString& dbId, bool selected)
{
    if (dbId.isEmpty()) {
        qWarning() << "selectDevice: Empty device dbId provided.";
        return;
    }
    
    if (selected) {
        m_selectedDeviceIds.insert(dbId);
    } else {
        m_selectedDeviceIds.remove(dbId);
    }
    
    // 通过设备ID找到设备的ModelIndex
    QModelIndex deviceIndex;
    for(int i=0; i<m_rootItem->childCount(); ++i){
        auto groupItem = static_cast<GroupItem*>(m_rootItem->child(i));
        for(int j=0; j<groupItem->childCount(); ++j){
            auto hostItem = static_cast<HostItem*>(groupItem->child(j));
            for(int k=0; k<hostItem->childCount(); ++k){
                auto deviceItem = static_cast<DeviceItem*>(hostItem->child(k));
                if(deviceItem->deviceData().dbId == dbId){
                    deviceIndex = index(k, 0, index(j, 0, index(i, 0, QModelIndex())));
                    goto found;
                }
            }
        }
    }
    found:
    
    if(deviceIndex.isValid()){
        emit dataChanged(deviceIndex, deviceIndex, {SelectedRole});
        // Also notify parent group/host if their state depends on child selection
        QModelIndex hostIndex = parent(deviceIndex);
        if(hostIndex.isValid()){
            emit dataChanged(hostIndex, hostIndex, {SelectedRole});
            QModelIndex groupIndex = parent(hostIndex);
            if(groupIndex.isValid()){
                 emit dataChanged(groupIndex, groupIndex, {SelectedRole});
            }
        }
    }
}

void TreeModel::checkGroup(int groupId, bool checked)
{
    QModelIndex groupIndex = findIndex(groupId, TypeGroup);
    if(!groupIndex.isValid()) return;
    TreeItem* groupItem = static_cast<TreeItem*>(groupIndex.internalPointer());
    if (!groupItem) return;
    
    const int hostCount = groupItem->childCount();
    for(int i=0; i < hostCount; ++i){
        TreeItem* childItem = groupItem->child(i);
        if (!(childItem && childItem->type() == TypeHost)) continue;
        HostItem* hostItem = static_cast<HostItem*>(childItem);

        QModelIndex hostIndex = index(i, 0, groupIndex);
        const int deviceCount = hostItem->childCount();

        if (deviceCount == 0) {
            const QString hostId = hostItem->hostData().hostId;
            if (checked) m_checkedHostIds.insert(hostId); else m_checkedHostIds.remove(hostId);
        } else {
            for(int k=0; k<deviceCount; ++k){
                DeviceItem* deviceItem = static_cast<DeviceItem*>(hostItem->child(k));
                const QString dbId = deviceItem->deviceData().dbId;
                if (checked) m_checkedDeviceIds.insert(dbId); else m_checkedDeviceIds.remove(dbId);
            }
            // 合并通知该主机下所有设备的变更
            emit dataChanged(index(0, 0, hostIndex), index(deviceCount - 1, 0, hostIndex), {CheckedRole});
        }
    }
    // 若分组没有主机，直接记录分组的勾选状态
    if (hostCount == 0) {
        if (checked) m_checkedGroupIds.insert(groupId);
        else m_checkedGroupIds.remove(groupId);
    }
    // 批量通知主机层（范围）以更新三态
    if (hostCount > 0) {
        emit dataChanged(index(0, 0, groupIndex), index(hostCount - 1, 0, groupIndex), {CheckedRole});
    }
    emit dataChanged(groupIndex, groupIndex, {CheckedRole});
}

void TreeModel::checkHost(const QString& hostId, bool checked)
{
    QModelIndex hostIndex = findIndex(hostId, TypeHost);
    if(!hostIndex.isValid()) return;
    TreeItem* hostItem = static_cast<TreeItem*>(hostIndex.internalPointer());
    if (!hostItem) return;
    
    qDebug() << "checkHost called for hostId:" << hostId << "checked:" << checked << "device count:" << hostItem->childCount();
    
    const int deviceCount = hostItem->childCount();

    // 批量更新设备选中状态，合并触发 dataChanged
    for(int i=0; i < deviceCount; ++i){
        TreeItem* childItem = hostItem->child(i);
        if (!(childItem && childItem->type() == TypeDevice)) continue;
        DeviceItem* deviceItem = static_cast<DeviceItem*>(childItem);
        const QString dbId = deviceItem->deviceData().dbId;

        if (checked) {
            m_checkedDeviceIds.insert(dbId);
        } else {
            m_checkedDeviceIds.remove(dbId);
        }
    }

    // 一次性通知该主机下设备的勾选变化，避免逐条信号引发的 QML 重绘抖动
    if (deviceCount > 0) {
        emit dataChanged(index(0, 0, hostIndex), index(deviceCount - 1, 0, hostIndex), {CheckedRole});
    }
    // 若主机没有设备，记录主机的勾选状态
    if (deviceCount == 0) {
        if (checked) m_checkedHostIds.insert(hostId);
        else m_checkedHostIds.remove(hostId);
    }
    
    qDebug() << "checkHost finished, total checked devices:" << m_checkedDeviceIds.size();
    
    emit dataChanged(hostIndex, hostIndex, {CheckedRole});
    QModelIndex groupIndex = parent(hostIndex);
    if(groupIndex.isValid()){
        emit dataChanged(groupIndex, groupIndex, {CheckedRole});
    }
}

void TreeModel::checkDevice(const QString& dbId, bool checked)
{
    checkDevice(dbId, checked, true);
}

void TreeModel::checkDevice(const QString& dbId, bool checked, bool updateParents)
{
    if (dbId.isEmpty()) {
        qWarning() << "checkDevice: Empty device dbId provided.";
        return;
    }
    
    qDebug() << "checkDevice called for dbId:" << dbId << "checked:" << checked << "updateParents:" << updateParents;
    
    if (checked) {
        m_checkedDeviceIds.insert(dbId);
    } else {
        m_checkedDeviceIds.remove(dbId);
    }
    
    // 通过设备ID找到设备的ModelIndex - 使用缓存优化
    QModelIndex deviceIndex;
    if (m_deviceIndexCache.contains(dbId)) {
        const QPersistentModelIndex persisted = m_deviceIndexCache.value(dbId);
        if (persisted.isValid()) {
            deviceIndex = persisted;
            qDebug() << "Using cached persistent index for device:" << dbId;
        } else {
            m_deviceIndexCache.remove(dbId);
        }
    }
    if (!deviceIndex.isValid()) {
        deviceIndex = findIndex(dbId, TypeDevice);
        if (deviceIndex.isValid()) {
            m_deviceIndexCache[dbId] = QPersistentModelIndex(deviceIndex);
            qDebug() << "Found and cached persistent index for device:" << dbId;
        } else {
            qWarning() << "Could not find index for device:" << dbId;
        }
    }

    if(deviceIndex.isValid() && !isSearching()){
        emit dataChanged(deviceIndex, deviceIndex, {CheckedRole});
        if(updateParents){
            QModelIndex hostIndex = parent(deviceIndex);
            if(hostIndex.isValid()){
                qDebug() << "Emitting dataChanged for host parent";
                emit dataChanged(hostIndex, hostIndex, {CheckedRole});
                QModelIndex groupIndex = parent(hostIndex);
                if(groupIndex.isValid()){
                    qDebug() << "Emitting dataChanged for group parent";
                    emit dataChanged(groupIndex, groupIndex, {CheckedRole});
                }
            }
        }
    }
}


bool TreeModel::isDeviceSelected(const QString& dbId) const
{
    return m_selectedDeviceIds.contains(dbId);
}

bool TreeModel::isDeviceChecked(const QString& dbId) const
{
    return m_checkedDeviceIds.contains(dbId);
}

QModelIndex TreeModel::findIndex(const QVariant& id, int type) const
{
    for(int i=0; i<m_rootItem->childCount(); ++i){
        auto groupItem = static_cast<GroupItem*>(m_rootItem->child(i));
        if(type == TypeGroup && groupItem->groupData().groupId == id.toInt()){
            return index(i, 0, QModelIndex());
        }
        for(int j=0; j<groupItem->childCount(); ++j){
            auto hostItem = static_cast<HostItem*>(groupItem->child(j));
            if(type == TypeHost && hostItem->hostData().hostId == id.toString()){
                return index(j, 0, index(i, 0, QModelIndex()));
            }
            for(int k=0; k<hostItem->childCount(); ++k){
                auto deviceItem = static_cast<DeviceItem*>(hostItem->child(k));
                if(type == TypeDevice && deviceItem->deviceData().dbId == id.toString()){
                    return index(k, 0, index(j, 0, index(i, 0, QModelIndex())));
                }
            }
        }
    }
    return QModelIndex();
}

void TreeModel::updateDeviceList(const QString &hostIp, const QVariantList &newDevicesVariant)
{
    QString hostId;
    for (const auto& h_list : m_hostsByGroup) {
        for (const auto& h : h_list) {
            if (h.ip == hostIp) {
                hostId = h.hostId;
                break;
            }
        }
        if (!hostId.isEmpty()) break;
    }

    if (hostId.isEmpty()) {
        qDebug() << "updateDeviceList: Host with IP not found:" << hostIp;
        return;
    }

    QModelIndex hostIndex = findIndex(hostId, TypeHost);
    if (!hostIndex.isValid()) {
        qWarning() << "updateDeviceList: Host with id" << hostId << "not found in tree structure.";
        return;
    }
    HostItem *hostItem = static_cast<HostItem*>(hostIndex.internalPointer());

    QList<DeviceData>& backingDeviceList = m_devicesByHost[hostId];
    
    QMap<QString, QVariantMap> newDevicesByDbId;
    for (const QVariant& v : newDevicesVariant) {
        QVariantMap m = v.toMap();
        QString dbId = m["db_id"].toString();
        if (!dbId.isEmpty()) {
            newDevicesByDbId.insert(dbId, m);
        }
    }

    // --- Step 1: Remove devices that no longer exist ---
    bool anyDeviceRemoved = false;
    for (int i = backingDeviceList.size() - 1; i >= 0; --i) {
        const DeviceData& localDevice = backingDeviceList[i];
        bool existsInNewList = newDevicesByDbId.contains(localDevice.dbId);
        if (!existsInNewList) {
            beginRemoveRows(hostIndex, i, i);
            m_checkedDeviceIds.remove(backingDeviceList[i].dbId);
            m_selectedDeviceIds.remove(backingDeviceList[i].dbId);
            delete hostItem->takeChild(i);
            backingDeviceList.removeAt(i);
            endRemoveRows();
            m_deviceIndexCache.remove(localDevice.dbId);
            anyDeviceRemoved = true;
        }
    }

    // --- Step 2: Update existing and add new devices ---
    for (const QVariant& deviceVariant : newDevicesVariant) {
        QVariantMap newDeviceMap = deviceVariant.toMap();
        QString dbId = newDeviceMap["db_id"].toString();
        DeviceData* oldDevicePtr = nullptr;
        int oldDeviceRow = -1;

        // 通过dbId查找
        for(int i = 0; i < backingDeviceList.size(); ++i) {
            if (backingDeviceList[i].dbId == dbId) {
                oldDevicePtr = &backingDeviceList[i];
                oldDeviceRow = i;
                break;
            }
        }

        if (oldDevicePtr) {
            // --- UPDATE ---
            DeviceData& oldDevice = *oldDevicePtr;
            
            // 保持勾选状态
            bool wasChecked = m_checkedDeviceIds.contains(oldDevice.dbId);
            bool wasSelected = m_selectedDeviceIds.contains(oldDevice.dbId);
            
            DeviceData newDeviceFromServer;
            parseDevice(QJsonObject::fromVariantMap(newDeviceMap), newDeviceFromServer);
            if (newDeviceFromServer.hostIp.isEmpty())
            {
                newDeviceFromServer.hostIp = hostIp;
            }

            if (newDeviceFromServer.hostId.isEmpty())
            {
                newDeviceFromServer.hostId = hostId;
            }

            QVector<int> changedRoles;

            if (oldDevice.id.isEmpty() && !dbId.isEmpty()) {
                oldDevice.id = dbId;  // 使用dbId作为id
                changedRoles.append(IdRole);
            }
            // 确保hostIp不为空，如果为空则使用传入的hostIp
            if (oldDevice.hostIp.isEmpty()) {
                oldDevice.hostIp = hostIp;
                changedRoles.append(HostIpRole);
            }
            if (oldDevice.displayName != newDeviceFromServer.displayName) { oldDevice.displayName = newDeviceFromServer.displayName; changedRoles.append(DisplayNameRole); }
            if (oldDevice.state != newDeviceFromServer.state) { oldDevice.state = newDeviceFromServer.state; changedRoles.append(StateRole); }
            if (oldDevice.image != newDeviceFromServer.image) { oldDevice.image = newDeviceFromServer.image; changedRoles.append(ImageRole); }
            if (oldDevice.adb != newDeviceFromServer.adb) { oldDevice.adb = newDeviceFromServer.adb; changedRoles.append(AdbRole); }
            if (oldDevice.data != newDeviceFromServer.data) { oldDevice.data = newDeviceFromServer.data; changedRoles.append(DataRole); }
            if (oldDevice.dbId != newDeviceFromServer.dbId) {
                oldDevice.dbId = newDeviceFromServer.dbId;
                changedRoles.append(DbIdRole);
            }
            if (oldDevice.dns != newDeviceFromServer.dns) { oldDevice.dns = newDeviceFromServer.dns; changedRoles.append(DnsRole); }
            if (oldDevice.dpi != newDeviceFromServer.dpi) { oldDevice.dpi = newDeviceFromServer.dpi; changedRoles.append(DpiRole); }
            if (oldDevice.fps != newDeviceFromServer.fps) { oldDevice.fps = newDeviceFromServer.fps; changedRoles.append(FpsRole); }
            if (oldDevice.height != newDeviceFromServer.height) { oldDevice.height = newDeviceFromServer.height; changedRoles.append(HeightRole); }
            if (oldDevice.ip != newDeviceFromServer.ip) { oldDevice.ip = newDeviceFromServer.ip; changedRoles.append(IpRole); }
            if (oldDevice.memory != newDeviceFromServer.memory) { oldDevice.memory = newDeviceFromServer.memory; changedRoles.append(MemoryRole); }
            if (oldDevice.name != newDeviceFromServer.name) { oldDevice.name = newDeviceFromServer.name; changedRoles.append(NameRole); }
            if (oldDevice.shortId != newDeviceFromServer.shortId) { oldDevice.shortId = newDeviceFromServer.shortId; changedRoles.append(ShortIdRole); }
            if (oldDevice.width != newDeviceFromServer.width) { oldDevice.width = newDeviceFromServer.width; changedRoles.append(WidthRole); }
            if (oldDevice.aospVersion != newDeviceFromServer.aospVersion) { oldDevice.aospVersion = newDeviceFromServer.aospVersion; changedRoles.append(AospVersionRole); }
            // 只有当新数据中的hostIp不为空时才更新，避免清空hostIp
            if (!newDeviceFromServer.hostIp.isEmpty() && oldDevice.hostIp != newDeviceFromServer.hostIp) { 
                oldDevice.hostIp = newDeviceFromServer.hostIp; 
                changedRoles.append(HostIpRole); 
            }
            if (oldDevice.created != newDeviceFromServer.created) { oldDevice.created = newDeviceFromServer.created; changedRoles.append(CreatedRole); }
            if (oldDevice.tcpVideoPort != newDeviceFromServer.tcpVideoPort) { oldDevice.tcpVideoPort = newDeviceFromServer.tcpVideoPort; changedRoles.append(TcpVideoPortRole); }
            if (oldDevice.tcpAudioPort != newDeviceFromServer.tcpAudioPort) { oldDevice.tcpAudioPort = newDeviceFromServer.tcpAudioPort; changedRoles.append(TcpAudioPortRole); }
            if (oldDevice.tcpControlPort != newDeviceFromServer.tcpControlPort) { oldDevice.tcpControlPort = newDeviceFromServer.tcpControlPort; changedRoles.append(TcpControlPortRole); }
            if (oldDevice.macvlanIp != newDeviceFromServer.macvlanIp) { oldDevice.macvlanIp = newDeviceFromServer.macvlanIp; changedRoles.append(MacvlanIpRole); }
            if (oldDevice.networkMode != newDeviceFromServer.networkMode) { oldDevice.networkMode = newDeviceFromServer.networkMode; changedRoles.append(NetworkModeRole); }
            if (oldDevice.timezone != newDeviceFromServer.timezone) { oldDevice.timezone = newDeviceFromServer.timezone; changedRoles.append(TimeZoneRole); }
            if (oldDevice.locale != newDeviceFromServer.locale) { oldDevice.locale = newDeviceFromServer.locale; changedRoles.append(LocaleRole); }

            if (!changedRoles.isEmpty()) {
                // 同步更新 backingDeviceList（m_devicesByHost 的引用），这样 toJson() 才能正确序列化
                backingDeviceList[oldDeviceRow] = oldDevice;
                
                QModelIndex deviceIndex = index(oldDeviceRow, 0, hostIndex);
                static_cast<DeviceItem*>(deviceIndex.internalPointer())->deviceData() = oldDevice;
                emit dataChanged(deviceIndex, deviceIndex, changedRoles);
            }
            
            // 恢复勾选状态
            if (wasChecked) {
                m_checkedDeviceIds.insert(oldDevice.dbId);
            }
            if (wasSelected) {
                m_selectedDeviceIds.insert(oldDevice.dbId);
            }
        } else {
            // --- ADD ---
            DeviceData deviceToAdd;
            parseDevice(QJsonObject::fromVariantMap(newDeviceMap), deviceToAdd);
            deviceToAdd.hostId = hostId;
            deviceToAdd.groupId = hostItem->hostData().groupId;
            deviceToAdd.hostIp = hostIp;  // 设置传入的hostIp
            
            // 检查设备状态，如果是 creating 状态则默认勾选
            bool shouldCheck = m_checkedDeviceIds.contains(deviceToAdd.dbId);
            if (!shouldCheck && deviceToAdd.state == "creating") {
                shouldCheck = true;
                m_checkedDeviceIds.insert(deviceToAdd.dbId);
            }
            
            deviceToAdd.checked = shouldCheck;
            deviceToAdd.selected = m_selectedDeviceIds.contains(deviceToAdd.dbId);
            deviceToAdd.refresh = false;
            
            int newRow = backingDeviceList.size();
            beginInsertRows(hostIndex, newRow, newRow);
            backingDeviceList.append(deviceToAdd);
            hostItem->appendChild(new DeviceItem(deviceToAdd, hostItem));
            endInsertRows();

            // 新增设备后，主机的三态可能已变化（尤其是空主机被分组/主机级意图勾选后新增设备）
            emit dataChanged(hostIndex, hostIndex, {CheckedRole});
            QModelIndex groupIndexAfterAdd = parent(hostIndex);
            if (groupIndexAfterAdd.isValid()) {
                emit dataChanged(groupIndexAfterAdd, groupIndexAfterAdd, {CheckedRole});
            }
        }
    }

    if (hostItem->hostData().hostPadCount != backingDeviceList.size()) {
        hostItem->hostData().hostPadCount = backingDeviceList.size();
        emit dataChanged(hostIndex, hostIndex, {HostPadCountRole});
        
        // 更新分组的设备数量显示
        QModelIndex groupIndex = parent(hostIndex);
        if (groupIndex.isValid()) {
            emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
        }
    }

    // 删除设备后也需要刷新主机与分组的三态，以便在未展开时正确更新复选框
    if (anyDeviceRemoved) {
        emit dataChanged(hostIndex, hostIndex, {CheckedRole});
        QModelIndex groupIndexAfterRemove = parent(hostIndex);
        if (groupIndexAfterRemove.isValid()) {
            emit dataChanged(groupIndexAfterRemove, groupIndexAfterRemove, {CheckedRole});
        }
    }

    // 当主机从空->有设备：若之前主机为“空主机勾选”，则将所有设备置为勾选并清理该主机标记
    if (hostItem->childCount() > 0 && m_checkedHostIds.contains(hostId)) {
        for (const auto& d : backingDeviceList) {
            if (!d.dbId.isEmpty()) m_checkedDeviceIds.insert(d.dbId);
        }
        m_checkedHostIds.remove(hostId);
        emit dataChanged(hostIndex, hostIndex, {CheckedRole});
        QModelIndex groupIndex = parent(hostIndex);
        if (groupIndex.isValid()) emit dataChanged(groupIndex, groupIndex, {CheckedRole});
    }

    // 当主机变为无设备：若父分组曾被勾选，则将该空主机设置为勾选
    if (hostItem->childCount() == 0 && m_checkedGroupIds.contains(hostItem->hostData().groupId)) {
        m_checkedHostIds.insert(hostId);
        emit dataChanged(hostIndex, hostIndex, {CheckedRole});
        QModelIndex groupIndex = parent(hostIndex);
        if (groupIndex.isValid()) emit dataChanged(groupIndex, groupIndex, {CheckedRole});
    }

    saveConfig();
}


int TreeModel::getRunningDeviceCount(const QString& hostIp) const
{
    QString hostId;
    for (const auto& h_list : m_hostsByGroup) {
        for (const auto& h : h_list) {
            if (h.ip == hostIp) {
                hostId = h.hostId;
                break;
            }
        }
        if (!hostId.isEmpty()) break;
    }

    if (hostId.isEmpty()) {
        return 0;
    }

    int runningCount = 0;
    if (m_devicesByHost.contains(hostId)) {
        const QList<DeviceData>& devices = m_devicesByHost.value(hostId);
        for (const auto& device : devices) {
            if (device.state == "running") {
                runningCount++;
            }
        }
    }
    return runningCount;
}

void TreeModel::updateDeviceListV3(const QString &hostIp, const QVariantList &partialDevices)
{
    QString hostId;
    for (const auto& h_list : m_hostsByGroup) {
        for (const auto& h : h_list) {
            if (h.ip == hostIp) { hostId = h.hostId; break; }
        }
        if (!hostId.isEmpty()) break;
    }

    if (hostId.isEmpty()) {
        qWarning() << "updateDeviceListV3: Host with IP not found:" << hostIp;
        return;
    }

    QModelIndex hostIndex = findIndex(hostId, TypeHost);
    if (!hostIndex.isValid()) {
        qWarning() << "updateDeviceListV3: Host with id" << hostId << "not found in tree structure.";
        return;
    }
    HostItem *hostItem = static_cast<HostItem*>(hostIndex.internalPointer());

    QList<DeviceData>& devices = m_devicesByHost[hostId];

    auto findDeviceRow = [&](const QVariantMap &m) -> int {
        const QString dbId = m.value("db_id").toString();
        for (int i = 0; i < devices.size(); ++i) {
            const DeviceData &d = devices.at(i);
            if (!dbId.isEmpty() && d.dbId == dbId) return i;
        }
        return -1;
    };

    bool anyChanged = false;

    for (const QVariant &v : partialDevices) {
        QVariantMap m = v.toMap();
        int row = findDeviceRow(m);
        if (row < 0) {
            // 只更新，不新增/不删除
            continue;
        }

        DeviceData &dev = devices[row];
        QVector<int> changedRoles;

        auto updateIf = [&](const char *key, const QVariant &val, QString &field, int role){
            if (m.contains(key)) {
                const QString nv = val.toString();
                if (field != nv) { field = nv; changedRoles.append(role); }
            }
        };
        auto updateIfInt = [&](const char *key, const QVariant &val, int &field, int role){
            if (m.contains(key)) {
                int nv = val.toInt();
                if (field != nv) { field = nv; changedRoles.append(role); }
            }
        };
        auto updateIfBool = [&](const char *key, const QVariant &val, bool &field, int role){
            if (m.contains(key)) {
                bool nv = val.toBool();
                if (field != nv) { field = nv; changedRoles.append(role); }
            }
        };

        // 兼容多种键名
        // if (m.contains("displayName")) updateIf("displayName", m.value("displayName"), dev.displayName, DisplayNameRole);
        if (m.contains("user_name")) updateIf("user_name", m.value("user_name"), dev.displayName, DisplayNameRole);
        if (m.contains("name")) updateIf("name", m.value("name"), dev.name, NameRole);
        if (m.contains("image")) updateIf("image", m.value("image"), dev.image, ImageRole);
        if (m.contains("dpi")) updateIf("dpi", m.value("dpi"), dev.dpi, DpiRole);
        if (m.contains("fps")) updateIf("fps", m.value("fps"), dev.fps, FpsRole);
        if (m.contains("state")) updateIf("state", m.value("state"), dev.state, StateRole);
        if (m.contains("refresh")) updateIfBool("refresh", m.value("refresh"), dev.refresh, RefreshRole);
        if (m.contains("adb")) updateIfInt("adb", m.value("adb"), dev.adb, AdbRole);
        if (m.contains("data")) updateIf("data", m.value("data"), dev.data, DataRole);
        if (m.contains("dbId")) updateIf("dbId", m.value("dbId"), dev.dbId, DbIdRole);
        if (m.contains("db_id")) updateIf("db_id", m.value("db_id"), dev.dbId, DbIdRole);
        if (m.contains("tcp_port")) updateIfInt("tcp_port", m.value("tcp_port"), dev.tcpVideoPort, TcpVideoPortRole);
        if (m.contains("tcp_audio_port")) updateIfInt("tcp_audio_port", m.value("tcp_audio_port"), dev.tcpAudioPort, TcpAudioPortRole);
        if (m.contains("tcp_control_port")) updateIfInt("tcp_control_port", m.value("tcp_control_port"), dev.tcpControlPort, TcpControlPortRole);
        if (m.contains("dns")) updateIf("dns", m.value("dns"), dev.dns, DnsRole);
        if (m.contains("height")) updateIf("height", m.value("height"), dev.height, HeightRole);
        if (m.contains("ip")) updateIf("ip", m.value("ip"), dev.ip, IpRole);
        if (m.contains("memory")) updateIfInt("memory", m.value("memory"), dev.memory, MemoryRole);
        // if (m.contains("shortId")) updateIf("shortId", m.value("shortId"), dev.shortId, ShortIdRole);
        if (m.contains("short_id")) updateIf("short_id", m.value("short_id"), dev.shortId, ShortIdRole);
        if (m.contains("width")) updateIf("width", m.value("width"), dev.width, WidthRole);
        // if (m.contains("aospVersion")) updateIf("aospVersion", m.value("aospVersion"), dev.aospVersion, AospVersionRole);
        if (m.contains("aosp_version")) updateIf("aosp_version", m.value("aosp_version"), dev.aospVersion, AospVersionRole);
        // if (m.contains("hostIp")) updateIf("hostIp", m.value("hostIp"), dev.hostIp, HostIpRole);
        if (m.contains("host_ip")) updateIf("host_ip", m.value("host_ip"), dev.hostIp, HostIpRole);
        if (m.contains("macvlan_ip")) updateIf("macvlan_ip", m.value("macvlan_ip"), dev.macvlanIp, MacvlanIpRole);
        if (m.contains("macvlanIp")) updateIf("macvlanIp", m.value("macvlanIp"), dev.macvlanIp, MacvlanIpRole);
        if (m.contains("network_mode")) updateIf("network_mode", m.value("network_mode"), dev.networkMode, NetworkModeRole);
        if (m.contains("locale")) updateIf("locale", m.value("locale"), dev.locale, LocaleRole);
        if (m.contains("timezone")) updateIf("timezone", m.value("timezone"), dev.timezone, TimeZoneRole);
        if (m.contains("created")) updateIf("created", m.value("created"), dev.created, CreatedRole);
        if (m.contains("id")) updateIf("id", m.value("id"), dev.id, IdRole);

        if (!changedRoles.isEmpty()) {
            QModelIndex deviceIndex = index(row, 0, hostIndex);
            static_cast<DeviceItem*>(deviceIndex.internalPointer())->deviceData() = dev;
            emit dataChanged(deviceIndex, deviceIndex, changedRoles);
            anyChanged = true;
            
            // 如果设备状态改变，需要通知主机节点更新 HostPadCountRole（用于显示过滤后的设备数量）
            // 同时需要通知分组节点更新 GroupPadCountRole
            if (changedRoles.contains(StateRole)) {
                emit dataChanged(hostIndex, hostIndex, {HostPadCountRole});
                QModelIndex groupIndex = parent(hostIndex);
                if (groupIndex.isValid()) {
                    emit dataChanged(groupIndex, groupIndex, {GroupPadCountRole});
                }
            }
        }
    }

    if (anyChanged) {
        saveConfig();
    }
}


