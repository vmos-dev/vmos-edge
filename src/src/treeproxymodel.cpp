#include "treeproxymodel.h"
#include "structs.h"
#include "treemodel.h"
#include <QSet>

TreeProxyModel::TreeProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_showRunningOnly(false)
    , m_showAllDevices(true) {
    collator.setLocale(QLocale::system());  // 使用系统语言
    collator.setNumericMode(true);          // 开启数字感知：名字(2) < 名字(11)
    collator.setCaseSensitivity(Qt::CaseInsensitive);
}

void TreeProxyModel::setSourceModel(QAbstractItemModel *sourceModel)
{
    // 断开旧源模型的信号连接
    if (QSortFilterProxyModel::sourceModel()) {
        disconnect(QSortFilterProxyModel::sourceModel(), &QAbstractItemModel::dataChanged,
                   this, &TreeProxyModel::onSourceDataChanged);
    }
    
    // 设置新源模型
    QSortFilterProxyModel::setSourceModel(sourceModel);
    
    // 连接新源模型的信号
    if (sourceModel) {
        connect(sourceModel, &QAbstractItemModel::dataChanged,
                this, &TreeProxyModel::onSourceDataChanged);
    }
}

void TreeProxyModel::onSourceDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight, const QVector<int> &roles)
{
    // 如果设备状态改变，需要确保主机的 HostPadCountRole 也会更新
    if (roles.contains(DeviceRoles::StateRole)) {
        // 处理批量更新的情况：遍历所有改变的设备
        QSet<QModelIndex> affectedHosts;
        QSet<QModelIndex> affectedGroups;
        
        for (int row = topLeft.row(); row <= bottomRight.row(); ++row) {
            QModelIndex sourceIndex = topLeft.sibling(row, topLeft.column());
            if (!sourceIndex.isValid()) continue;
            
            // 检查是否是设备节点
            int itemType = sourceModel()->data(sourceIndex, DeviceRoles::ItemTypeRole).toInt();
            if (itemType == TreeModel::TypeDevice) {
                // 获取父主机节点
                QModelIndex hostIndex = sourceIndex.parent();
                if (hostIndex.isValid()) {
                    affectedHosts.insert(hostIndex);
                    
                    // 获取父分组节点
                    QModelIndex groupIndex = hostIndex.parent();
                    if (groupIndex.isValid()) {
                        affectedGroups.insert(groupIndex);
                    }
                }
            }
        }
        
        // 触发所有受影响的主机和分组更新
        for (const QModelIndex &hostIndex : affectedHosts) {
            QModelIndex proxyHostIndex = mapFromSource(hostIndex);
            if (proxyHostIndex.isValid()) {
                emit dataChanged(proxyHostIndex, proxyHostIndex, {DeviceRoles::HostPadCountRole});
            }
        }
        
        for (const QModelIndex &groupIndex : affectedGroups) {
            QModelIndex proxyGroupIndex = mapFromSource(groupIndex);
            if (proxyGroupIndex.isValid()) {
                emit dataChanged(proxyGroupIndex, proxyGroupIndex, {DeviceRoles::GroupPadCountRole});
            }
        }
    }
}

bool TreeProxyModel::lessThan(const QModelIndex& left, const QModelIndex& right) const {
    QModelIndex leftParent = left.parent();
    QModelIndex rightParent = right.parent();

    // 只比较相同 parent 的子项
    if (leftParent != rightParent)
        return false;

    QVariant leftData, rightData;
    int itemType = sourceModel()->data(left, DeviceRoles::ItemTypeRole).toInt();

    switch(itemType){
    case TreeModel::TypeGroup:
        leftData = sourceModel()->data(left, DeviceRoles::GroupNameRole);
        rightData = sourceModel()->data(right, DeviceRoles::GroupNameRole);
        break;
    case TreeModel::TypeHost:
        leftData = sourceModel()->data(left, DeviceRoles::IpRole);
        rightData = sourceModel()->data(right, DeviceRoles::IpRole);
        break;
    case TreeModel::TypeDevice:
        leftData = sourceModel()->data(left, DeviceRoles::DisplayNameRole);
        rightData = sourceModel()->data(right, DeviceRoles::DisplayNameRole);
        break;
    default:
        return false;
    }

    return collator.compare(leftData.toString(), rightData.toString()) < 0;
}

// 过滤属性实现
QString TreeProxyModel::searchFilter() const {
    return m_searchFilter;
}

void TreeProxyModel::setSearchFilter(const QString &filter) {
    if (m_searchFilter != filter) {
        m_searchFilter = filter;
        emit searchFilterChanged();

        auto real_mode = dynamic_cast<TreeModel*>(sourceModel());
        if (real_mode)
        {
            real_mode->setSearchFlag(true);
        }

        // 根据搜索条件处理设备勾选状态
        if (!m_searchFilter.isEmpty()) {
            // 有搜索条件时，只勾选匹配的设备
            autoCheckMatchingDevices();
        } else {
            // 搜索条件为空时，取消所有设备的勾选状态
            clearAllDeviceChecks();
        }

        if (real_mode)
        {
            real_mode->setSearchFlag(false);
        }

        invalidateFilter();
    }
}

// 核心筛选逻辑
bool TreeProxyModel::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const {
    QModelIndex sourceIndex = sourceModel()->index(source_row, 0, source_parent);
    
    if (!sourceIndex.isValid()) {
        return false;
    }
    
    // 获取项目类型
    int itemType = sourceModel()->data(sourceIndex, DeviceRoles::ItemTypeRole).toInt();
    // 根据项目类型进行过滤
    switch (itemType) {
    case TreeModel::TypeGroup:
    {
        if (m_searchFilter.isEmpty())       //  无搜索条件，默认保留分组标签项 2025-12-15
        {
            return true;
        }
        else
        {
            return hasMatchingChildren(sourceIndex);
        }
    }
    case TreeModel::TypeHost:
    {
        if (m_searchFilter.isEmpty())       //  无搜索条件，默认保留分组标签项 2025-12-15
        {
            return true;
        }
        else
        {
            //  尝试匹配主机IP
            QString hostIp = sourceModel()->data(sourceIndex, DeviceRoles::HostIpRole).toString();
            if (hostIp.contains(m_searchFilter))
            {
                qDebug() << "m_searchFilter=" << m_searchFilter << " & hostIp=" << hostIp;
                if (m_showAllDevices)
                {
                    return true;
                }

                QString hostState = sourceModel()->data(sourceIndex, DeviceRoles::StateRole).toString();
                if (hostState != "offline")
                {
                    return true;
                }
            }
            return hasMatchingChildren(sourceIndex);
        }
    }
    case TreeModel::TypeDevice:
    {
        // 设备节点：检查搜索过滤和状态过滤
        bool searchMatch = matchesSearchFilter(sourceIndex);
        bool stateMatch = matchesStateFilter(sourceIndex);
        return searchMatch && stateMatch;
    }
        
    default:
        return true;
    }
}

// 检查是否有匹配的子项
bool TreeProxyModel::hasMatchingChildren(const QModelIndex &parent) const {
    int rowCount = sourceModel()->rowCount(parent);
    for (int i = 0; i < rowCount; ++i) {
        QModelIndex child = sourceModel()->index(i, 0, parent);
        if (filterAcceptsRow(i, parent)) {
            return true;
        }
    }
    return false;
}

// 统一搜索过滤匹配（只匹配设备节点）
bool TreeProxyModel::matchesSearchFilter(const QModelIndex &sourceIndex) const {
    if (m_searchFilter.isEmpty()) {
        return true;
    }
    
    // 只对设备节点进行名称匹配
    QString displayName = sourceModel()->data(sourceIndex, DeviceRoles::DisplayNameRole).toString();
    QString hostIp = sourceModel()->data(sourceIndex, DeviceRoles::HostIpRole).toString();
    return displayName.contains(m_searchFilter, Qt::CaseInsensitive) || hostIp.contains(m_searchFilter, Qt::CaseInsensitive);
}

// 状态过滤匹配（只匹配设备节点）
bool TreeProxyModel::matchesStateFilter(const QModelIndex &sourceIndex) const {
    // 如果显示所有设备，则不过滤
    if (m_showAllDevices) {
        return true;
    }
    
    // 如果只显示运行中的设备，检查设备状态
    if (m_showRunningOnly) {
        QString state = sourceModel()->data(sourceIndex, DeviceRoles::StateRole).toString();
        // 只显示运行中的设备，排除关机设备（stopped, exited等）
        return state == "running";
    }
    
    // 默认显示所有设备
    return true;
}

// 状态过滤属性实现
bool TreeProxyModel::showRunningOnly() const {
    return m_showRunningOnly;
}

void TreeProxyModel::setShowRunningOnly(bool show) {
    if (m_showRunningOnly != show) {
        m_showRunningOnly = show;
        if (show) {
            // 如果选择只显示运行中的设备，则取消显示所有设备
            m_showAllDevices = false;
            emit showAllDevicesChanged();
        } else {
            // 如果取消只显示运行中的设备，则自动选中显示所有设备
            if (!m_showAllDevices) {
                m_showAllDevices = true;
                emit showAllDevicesChanged();
            }
        }
        emit showRunningOnlyChanged();
        invalidateFilter();
        this->invalidate();
    }
}

bool TreeProxyModel::showAllDevices() const {
    return m_showAllDevices;
}

void TreeProxyModel::setShowAllDevices(bool show) {
    if (m_showAllDevices != show) {
        m_showAllDevices = show;
        if (show) {
            // 如果选择显示所有设备，则取消只显示运行中的设备
            m_showRunningOnly = false;
            emit showRunningOnlyChanged();
        } else {
            // 如果取消显示所有设备，则自动选中只显示运行中的设备
            if (!m_showRunningOnly) {
                m_showRunningOnly = true;
                emit showRunningOnlyChanged();
            }
        }
        emit showAllDevicesChanged();
        invalidateFilter();
        this->invalidate();
    }
}

// 自动勾选匹配搜索条件的设备，取消勾选不匹配的设备
void TreeProxyModel::autoCheckMatchingDevices() {
    if (!sourceModel()) return;
    
    // 遍历所有设备，根据匹配情况设置勾选状态
    for (int i = 0; i < sourceModel()->rowCount(QModelIndex()); ++i) { // Groups
        QModelIndex groupIndex = sourceModel()->index(i, 0, QModelIndex());
        for (int j = 0; j < sourceModel()->rowCount(groupIndex); ++j) { // Hosts
            QModelIndex hostIndex = sourceModel()->index(j, 0, groupIndex);
            for (int k = 0; k < sourceModel()->rowCount(hostIndex); ++k) { // Devices
                QModelIndex deviceIndex = sourceModel()->index(k, 0, hostIndex);
                if (sourceModel()->data(deviceIndex, DeviceRoles::ItemTypeRole) == TreeModel::TypeDevice) {
                    // 检查设备是否匹配搜索条件
                    QString displayName = sourceModel()->data(deviceIndex, DeviceRoles::DisplayNameRole).toString();
                    QString hostIp = sourceModel()->data(deviceIndex, DeviceRoles::HostIpRole).toString();
                    bool matches = displayName.contains(m_searchFilter, Qt::CaseInsensitive) || 
                                  hostIp.contains(m_searchFilter, Qt::CaseInsensitive);
                    
                    // 根据匹配情况设置勾选状态
                    sourceModel()->setData(deviceIndex, matches, DeviceRoles::CheckedRole);
                }
            }
        }
    }
}

// 取消所有设备的勾选状态
void TreeProxyModel::clearAllDeviceChecks() {
    if (!sourceModel()) return;
    
    // 遍历所有设备，取消勾选状态
    for (int i = 0; i < sourceModel()->rowCount(QModelIndex()); ++i) { // Groups
        QModelIndex groupIndex = sourceModel()->index(i, 0, QModelIndex());
        for (int j = 0; j < sourceModel()->rowCount(groupIndex); ++j) { // Hosts
            QModelIndex hostIndex = sourceModel()->index(j, 0, groupIndex);
            for (int k = 0; k < sourceModel()->rowCount(hostIndex); ++k) { // Devices
                QModelIndex deviceIndex = sourceModel()->index(k, 0, hostIndex);
                if (sourceModel()->data(deviceIndex, DeviceRoles::ItemTypeRole) == TreeModel::TypeDevice) {
                    // 取消勾选所有设备
                    sourceModel()->setData(deviceIndex, false, DeviceRoles::CheckedRole);
                }
            }
        }
    }
}

// 计算过滤后的设备数量（通过代理索引）
int TreeProxyModel::getFilteredDeviceCountForHost(const QModelIndex& proxyIndex) const {
    if (!sourceModel() || !proxyIndex.isValid()) return 0;
    
    // 将代理索引映射到源模型索引
    QModelIndex sourceIndex = mapToSource(proxyIndex);
    if (!sourceIndex.isValid()) return 0;
    
    // 检查是否是主机节点
    int itemType = sourceModel()->data(sourceIndex, DeviceRoles::ItemTypeRole).toInt();
    if (itemType != TreeModel::TypeHost) {
        return 0;
    }
    
    // 遍历主机下的所有设备，统计符合过滤条件的设备数量
    int count = 0;
    int rowCount = sourceModel()->rowCount(sourceIndex);
    for (int i = 0; i < rowCount; ++i) {
        QModelIndex deviceIndex = sourceModel()->index(i, 0, sourceIndex);
        if (sourceModel()->data(deviceIndex, DeviceRoles::ItemTypeRole).toInt() == TreeModel::TypeDevice) {
            // 检查设备是否符合过滤条件
            bool searchMatch = m_searchFilter.isEmpty() || matchesSearchFilter(deviceIndex);
            bool stateMatch = matchesStateFilter(deviceIndex);
            if (searchMatch && stateMatch) {
                count++;
            }
        }
    }
    
    return count;
}

// 计算过滤后的设备数量（通过hostId）
int TreeProxyModel::getFilteredDeviceCountByHostId(const QString& hostId) const {
    if (!sourceModel() || hostId.isEmpty()) return 0;
    
    // 遍历所有分组和主机，找到匹配的hostId
    for (int i = 0; i < sourceModel()->rowCount(QModelIndex()); ++i) {
        QModelIndex groupIndex = sourceModel()->index(i, 0, QModelIndex());
        for (int j = 0; j < sourceModel()->rowCount(groupIndex); ++j) {
            QModelIndex hostIndex = sourceModel()->index(j, 0, groupIndex);
            QString currentHostId = sourceModel()->data(hostIndex, DeviceRoles::HostIdRole).toString();
            if (currentHostId == hostId) {
                // 找到匹配的主机，计算过滤后的设备数量
                int count = 0;
                int rowCount = sourceModel()->rowCount(hostIndex);
                for (int k = 0; k < rowCount; ++k) {
                    QModelIndex deviceIndex = sourceModel()->index(k, 0, hostIndex);
                    if (sourceModel()->data(deviceIndex, DeviceRoles::ItemTypeRole).toInt() == TreeModel::TypeDevice) {
                        // 检查设备是否符合过滤条件
                        bool searchMatch = m_searchFilter.isEmpty() || matchesSearchFilter(deviceIndex);
                        bool stateMatch = matchesStateFilter(deviceIndex);
                        if (searchMatch && stateMatch) {
                            count++;
                        }
                    }
                }
                return count;
            }
        }
    }
    
    return 0;
}

QVariant TreeProxyModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid()) {
        return QSortFilterProxyModel::data(index, role);
    }
    
    QModelIndex sourceIndex = mapToSource(index);
    if (!sourceIndex.isValid()) {
        return QSortFilterProxyModel::data(index, role);
    }
    
    int itemType = sourceModel()->data(sourceIndex, DeviceRoles::ItemTypeRole).toInt();
    
    // 对于 HostPadCountRole，返回过滤后的设备数量
    if (role == DeviceRoles::HostPadCountRole && itemType == TreeModel::TypeHost) {
        int count = 0;
        int rowCount = sourceModel()->rowCount(sourceIndex);
        for (int i = 0; i < rowCount; ++i) {
            QModelIndex deviceIndex = sourceModel()->index(i, 0, sourceIndex);
            if (sourceModel()->data(deviceIndex, DeviceRoles::ItemTypeRole).toInt() == TreeModel::TypeDevice) {
                // 检查设备是否符合过滤条件
                bool searchMatch = m_searchFilter.isEmpty() || matchesSearchFilter(deviceIndex);
                bool stateMatch = matchesStateFilter(deviceIndex);
                if (searchMatch && stateMatch) {
                    count++;
                }
            }
        }
        return count;
    }
    
    // 对于 GroupPadCountRole，返回过滤后的主机数量
    if (role == DeviceRoles::GroupPadCountRole && itemType == TreeModel::TypeGroup) {
        // 如果选中"所有云机"，返回所有主机数量（包括离线主机）
        if (m_showAllDevices && m_searchFilter.isEmpty())
        {
            return sourceModel()->rowCount(sourceIndex);
        }
        
        // 如果选中"运行中云机"，只统计非离线状态的主机
        int visibleHostCount = 0;
        int hostCount = sourceModel()->rowCount(sourceIndex);
        for (int i = 0; i < hostCount; ++i) {
            QModelIndex hostIndex = sourceModel()->index(i, 0, sourceIndex);
            if (!hostIndex.isValid()) {
                continue;
            }

            // 检查主机是否可见（不是离线状态）
            if (hasMatchingChildren(hostIndex))
            {
                visibleHostCount++;
            }
        }
        return visibleHostCount;
    }
    
    // 对于 CheckedRole，需要特殊处理主机和分组
    if (role == DeviceRoles::CheckedRole) {
        if (itemType == TreeModel::TypeHost) {
            // 计算符合过滤条件的设备的勾选状态
            int visibleDeviceCount = 0;
            int checkedVisibleDeviceCount = 0;
            
            int rowCount = sourceModel()->rowCount(sourceIndex);
            for (int i = 0; i < rowCount; ++i) {
                QModelIndex deviceIndex = sourceModel()->index(i, 0, sourceIndex);
                if (sourceModel()->data(deviceIndex, DeviceRoles::ItemTypeRole).toInt() == TreeModel::TypeDevice) {
                    // 检查设备是否符合过滤条件
                    bool searchMatch = m_searchFilter.isEmpty() || matchesSearchFilter(deviceIndex);
                    bool stateMatch = matchesStateFilter(deviceIndex);
                    if (searchMatch && stateMatch) {
                        // 设备符合过滤条件，计入可见设备
                        visibleDeviceCount++;
                        if (sourceModel()->data(deviceIndex, DeviceRoles::CheckedRole).toBool()) {
                            checkedVisibleDeviceCount++;
                        }
                    }
                }
            }
            
            // 如果没有可见设备，返回源模型的原始值
            if (visibleDeviceCount == 0) {
                return sourceModel()->data(sourceIndex, role);
            }
            
            // 根据可见设备的勾选状态返回结果
            if (checkedVisibleDeviceCount == 0) {
                return false;
            }
            if (checkedVisibleDeviceCount == visibleDeviceCount) {
                return true;
            }
            return QVariant(); // Indeterminate
        }
        else if (itemType == TreeModel::TypeGroup) {
            // 计算分组的勾选状态，基于过滤后的主机勾选状态
            int totalHosts = sourceModel()->rowCount(sourceIndex);
            if (totalHosts == 0) {
                return sourceModel()->data(sourceIndex, role);
            }
            
            int checkedHostCount = 0;
            int partialHostCount = 0;
            int hostsWithVisibleDevices = 0; // 有可见设备的主机数量
            
            // 检查每个主机的勾选状态（使用代理模型的索引来获取过滤后的勾选状态）
            for (int i = 0; i < totalHosts; ++i) {
                QModelIndex hostSourceIndex = sourceModel()->index(i, 0, sourceIndex);
                if (!hostSourceIndex.isValid()) {
                    continue;
                }
                
                // 检查主机是否有可见设备
                bool hasVisibleDevices = false;
                int visibleDeviceCount = 0;
                int checkedVisibleDeviceCount = 0;
                
                int deviceRowCount = sourceModel()->rowCount(hostSourceIndex);
                for (int j = 0; j < deviceRowCount; ++j) {
                    QModelIndex deviceIndex = sourceModel()->index(j, 0, hostSourceIndex);
                    if (sourceModel()->data(deviceIndex, DeviceRoles::ItemTypeRole).toInt() == TreeModel::TypeDevice) {
                        bool searchMatch = m_searchFilter.isEmpty() || matchesSearchFilter(deviceIndex);
                        bool stateMatch = matchesStateFilter(deviceIndex);
                        if (searchMatch && stateMatch) {
                            hasVisibleDevices = true;
                            visibleDeviceCount++;
                            if (sourceModel()->data(deviceIndex, DeviceRoles::CheckedRole).toBool()) {
                                checkedVisibleDeviceCount++;
                            }
                        }
                    }
                }
                
                // 如果主机没有可见设备，忽略它（不参与分组状态计算）
                if (!hasVisibleDevices) {
                    continue;
                }
                
                // 主机有可见设备，计入统计
                hostsWithVisibleDevices++;
                
                // 根据可见设备的勾选状态判断主机状态
                if (checkedVisibleDeviceCount == 0) {
                    // 主机未勾选，不增加任何计数
                } else if (checkedVisibleDeviceCount == visibleDeviceCount) {
                    // 主机完全勾选
                    checkedHostCount++;
                } else {
                    // 主机部分勾选
                    partialHostCount++;
                }
            }
            
            // 如果没有任何主机有可见设备，返回源模型的原始值
            if (hostsWithVisibleDevices == 0) {
                return sourceModel()->data(sourceIndex, role);
            }
            
            // 如果有任何主机是部分选中，分组应该是部分选中
            if (partialHostCount > 0) {
                return QVariant(); // Indeterminate
            }
            // 所有有可见设备的主机都完全选中
            if (checkedHostCount == hostsWithVisibleDevices) {
                return true;
            }
            // 有部分主机完全选中，其他未选中
            if (checkedHostCount > 0) {
                return QVariant(); // Indeterminate
            }
            // 所有有可见设备的主机都未选中
            return false;
        }
    }
    
    // 对于其他情况，使用基类的默认实现
    return QSortFilterProxyModel::data(index, role);
}