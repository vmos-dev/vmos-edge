#ifndef TREEMODEL_H
#define TREEMODEL_H

#include <QAbstractItemModel>
#include <QSet>
#include <QPersistentModelIndex>
#include "treeitem.h"

// Forward declarations from structs.h
struct GroupData;
struct HostData;
struct DeviceData;

class TreeModel : public QAbstractItemModel
{
    Q_OBJECT

signals:
    void deviceAdded(QString hostIp);

public:
    enum ItemType { TypeGroup, TypeHost, TypeDevice };
    Q_ENUM(ItemType)

    Q_PROPERTY(ItemType typeGroup READ typeGroup CONSTANT)
    Q_PROPERTY(ItemType typeHost READ typeHost CONSTANT)
    Q_PROPERTY(ItemType typeDevice READ typeDevice CONSTANT)

    explicit TreeModel(QObject *parent = nullptr);
    ~TreeModel() override;


    QVariant data(const QModelIndex &index, int role) const override;
    bool setData(const QModelIndex &index, const QVariant &value, int role = Qt::EditRole) override;
    Qt::ItemFlags flags(const QModelIndex &index) const override;
    QModelIndex index(int row, int column, const QModelIndex &parent = QModelIndex()) const override;
    QModelIndex parent(const QModelIndex &index) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool hasChildren(const QModelIndex &parent = QModelIndex()) const override;

    Q_INVOKABLE bool addGroup(const QString& name);
    Q_INVOKABLE bool addHost(const QVariantMap& hostData);
    Q_INVOKABLE void addDevice(const QString& hostIp, const QVariantMap& deviceData);
    Q_INVOKABLE void moveHost(const QString& hostId, int newGroupId);
    Q_INVOKABLE bool removeHost(const QString& hostId);
    Q_INVOKABLE bool removeGroup(int groupId);
    Q_INVOKABLE bool removeDevice(const QString& deviceName);
    Q_INVOKABLE bool renameGroup(int groupId, const QString& newName);
    Q_INVOKABLE void removeDevicesByHostIp(const QString &hostIp);
    Q_INVOKABLE void modifyDevice(const QString& name, const QVariantMap& newData);
    Q_INVOKABLE void modifyDeviceEx(const QString& shortId, const QVariantMap& newData);
    Q_INVOKABLE void updateDevice(const QString& dbId, const QVariantMap& device);
    Q_INVOKABLE void modifyHost(const QString& hostIp, const QVariantMap& newData);
    Q_INVOKABLE void updateDeviceList(const QString &hostIp, const QVariantList &devices);
    Q_INVOKABLE void updateDeviceListV3(const QString &hostIp, const QVariantList &devices);
    Q_INVOKABLE QVariantList hostList() const;
    Q_INVOKABLE int getRunningDeviceCount(const QString& hostIp) const;

    Q_INVOKABLE void selectGroup(int groupId, bool selected);
    Q_INVOKABLE void selectDevice(const QString& dbId, bool selected);
    Q_INVOKABLE void checkGroup(int groupId, bool checked);
    Q_INVOKABLE void checkHost(const QString& hostId, bool checked);
    Q_INVOKABLE void checkDevice(const QString& dbId, bool checked);
    bool isDeviceSelected(const QString& dbId) const;
    bool isDeviceChecked(const QString& dbId) const;
    ItemType typeGroup() const { return TypeGroup; }
    ItemType typeHost() const { return TypeHost; }
    ItemType typeDevice() const { return TypeDevice; }

public:
    void setSearchFlag(bool searching){m_searching = searching;}

private:
    void initDefaultGroup();
    void rebuildTree();
    void rebuildHost(const QString& hostId);
    QByteArray toJson() const;
    void saveConfig();
    void loadConfig();
    int generateNewGroupId();
    void parseData(const QByteArray& data, QList<GroupData>& groups, QMap<int, QList<HostData>>& hostsByGroup, QMap<QString, QList<DeviceData>>& devicesByHost);
    void parseDevice(const QJsonObject& padObject, DeviceData& device);
    void parseGroup(const QJsonObject& groupObject, GroupData& group);
    void parseHost(const QJsonObject& hostObject, HostData& host);
    void checkDevice(const QString& dbId, bool checked, bool updateParents);
    QModelIndex findIndex(const QVariant& id, int type) const;

    TreeItem *m_rootItem;
    QSet<QString> m_selectedDeviceIds;  // 存储选中的设备dbId（因为id在创建过程中为空）
    QSet<QString> m_checkedDeviceIds;   // 存储勾选的设备dbId（因为id在创建过程中为空）
    mutable QMap<QString, QPersistentModelIndex> m_deviceIndexCache;  // 设备ID到持久索引的缓存
    QSet<int> m_checkedGroupIds;        // 存储分组的勾选状态（在无主机时生效）
    QSet<QString> m_checkedHostIds;     // 存储主机的勾选状态（在无设备时生效）

    QString m_configPath;
    QList<GroupData> m_groups;
    QMap<int, QList<HostData>> m_hostsByGroup;
    QMap<QString, QList<DeviceData>> m_devicesByHost;

private:
    bool m_searching = false;

    bool isSearching()const {return m_searching;}
};

#endif // TREEMODEL_H
