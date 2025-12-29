#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QThread>
#include <QTimer>
#include <QTimerEvent>

#include "server.h"

#define DEVICE_NAME_FIELD_LENGTH 64
#define SOCKET_NAME_PREFIX "scrcpy"
#define MAX_CONNECT_COUNT 30
#define MAX_RESTART_COUNT 1

static quint32 bufferRead32be(quint8 *buf)
{
    return static_cast<quint32>((buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3]);
}

Server::Server(QObject *parent) : QObject(parent)
{
    connect(&m_workProcess, &qsc::AdbProcess::adbProcessResult, this, &Server::onWorkProcessResult);
    connect(&m_serverProcess, &qsc::AdbProcess::adbProcessResult, this, &Server::onWorkProcessResult);

    connect(&m_serverSocket, &QTcpServer::newConnection, this, [this]() {
        QTcpSocket *tmp = m_serverSocket.nextPendingConnection();
        if (dynamic_cast<VideoSocket *>(tmp)) {
            m_videoSocket = dynamic_cast<VideoSocket *>(tmp);
            if (!m_videoSocket->isValid() || !readInfo(m_videoSocket, m_deviceName, m_deviceSize)) {
                stop();
                emit serverStarted(false);
            }
        } else {
            m_controlSocket = tmp;
            if (m_controlSocket && m_controlSocket->isValid()) {
                // we don't need the server socket anymore
                // just m_videoSocket is ok
                m_serverSocket.close();
                // we don't need the adb tunnel anymore
                disableTunnelReverse();
                m_tunnelEnabled = false;
                emit serverStarted(true, m_deviceName, m_deviceSize);
            } else {
                stop();
                emit serverStarted(false);
            }
            stopAcceptTimeoutTimer();
        }
    });
}

Server::~Server() {}

bool Server::pushServer()
{
    if (m_workProcess.isRuning()) {
        m_workProcess.kill();
    }
    m_workProcess.push(m_params.serial, m_params.serverLocalPath, m_params.serverRemotePath);
    return true;
}

bool Server::enableTunnelReverse()
{
    if (m_workProcess.isRuning()) {
        m_workProcess.kill();
    }
    m_workProcess.reverse(m_params.serial, QString(SOCKET_NAME_PREFIX "_%1").arg(m_params.scid, 8, 16, QChar('0')), m_params.localPort);
    return true;
}

bool Server::disableTunnelReverse()
{
    qsc::AdbProcess *adb = new qsc::AdbProcess();
    if (!adb) {
        return false;
    }
    connect(adb, &qsc::AdbProcess::adbProcessResult, this, [this](qsc::AdbProcess::ADB_EXEC_RESULT processResult) {
        if (qsc::AdbProcess::AER_SUCCESS_START != processResult) {
            sender()->deleteLater();
        }
    });
    adb->reverseRemove(m_params.serial, QString(SOCKET_NAME_PREFIX "_%1").arg(m_params.scid, 8, 16, QChar('0')));
    return true;
}

bool Server::enableTunnelForward()
{
    if (m_workProcess.isRuning()) {
        m_workProcess.kill();
    }
    m_workProcess.forward(m_params.serial, m_params.localPort, QString(SOCKET_NAME_PREFIX "_%1").arg(m_params.scid, 8, 16, QChar('0')));
    return true;
}
bool Server::disableTunnelForward()
{
    qsc::AdbProcess *adb = new qsc::AdbProcess();
    if (!adb) {
        return false;
    }
    connect(adb, &qsc::AdbProcess::adbProcessResult, this, [this](qsc::AdbProcess::ADB_EXEC_RESULT processResult) {
        if (qsc::AdbProcess::AER_SUCCESS_START != processResult) {
            sender()->deleteLater();
        }
    });
    adb->forwardRemove(m_params.serial, m_params.localPort);
    return true;
}

bool Server::execute()
{
    if (m_serverProcess.isRuning()) {
        m_serverProcess.kill();
    }
    QStringList args;
    args << "shell";
    args << QString("CLASSPATH=%1").arg(m_params.serverRemotePath);
    args << "app_process";

#ifdef SERVER_DEBUGGER
#define SERVER_DEBUGGER_PORT "5005"

    args <<
#ifdef SERVER_DEBUGGER_METHOD_NEW
        /* Android 9 and above */
        "-XjdwpProvider:internal -XjdwpOptions:transport=dt_socket,suspend=y,server=y,address="
#else
        /* Android 8 and below */
        "-agentlib:jdwp=transport=dt_socket,suspend=y,server=y,address="
#endif
        SERVER_DEBUGGER_PORT,
#endif

        args << "/"; // unused;
    args << "com.genymobile.scrcpy.Server";
    args << m_params.serverVersion;

    args << QString("video_bit_rate=%1").arg(QString::number(m_params.bitRate));
    if (!m_params.logLevel.isEmpty()) {
        args << QString("log_level=%1").arg(m_params.logLevel);
    }
    if (m_params.maxSize > 0) {
        args << QString("max_size=%1").arg(QString::number(m_params.maxSize));
    }
    if (m_params.maxFps > 0) {
        args << QString("max_fps=%1").arg(QString::number(m_params.maxFps));
    }

    // capture_orientation=@90
    // 有@表示锁定，没@不锁定
    // 有值表示指定方向，没值表示原始方向
    if (1 == m_params.captureOrientationLock) {
        args << QString("capture_orientation=@%1").arg(m_params.captureOrientation);
    } else if (2 == m_params.captureOrientationLock) {
        args << QString("capture_orientation=@");
    } else {
        args << QString("capture_orientation=%1").arg(m_params.captureOrientation);
    }
    if (m_tunnelForward) {
        args << QString("tunnel_forward=true");
    }
    if (!m_params.crop.isEmpty()) {
        args << QString("crop=%1").arg(m_params.crop);
    }
    if (!m_params.control) {
        args << QString("control=false");
    }
    // 默认是0，不需要设置
    // args << "display_id=0";
    // 默认是false，不需要设置
    // args << "show_touches=false";
    if (m_params.stayAwake) {
        args << QString("stay_awake=true");
    }
    // code option
    // https://github.com/Genymobile/scrcpy/commit/080a4ee3654a9b7e96c8ffe37474b5c21c02852a
    // <https://d.android.com/reference/android/media/MediaFormat>
    if (!m_params.codecOptions.isEmpty()) {
        args << QString("codec_options=%1").arg(m_params.codecOptions);
    }
    if (!m_params.codecName.isEmpty()) {
        args << QString("encoder_name=%1").arg(m_params.codecName);
    }
    args << "audio=false";
    // 服务端默认-1，可不传
    if (-1 != m_params.scid) {
        args << QString("scid=%1").arg(m_params.scid, 8, 16, QChar('0'));
    }

    // 默认是false，不需要设置
    // args << "power_off_on_close=false";

    // 下面的参数都用服务端默认值即可，尽量减少参数传递，传参太长导致三星手机报错：stack corruption detected (-fstack-protector)
    /*
    args << "clipboard_autosync=true";    
    args << "downsize_on_error=true";
    args << "cleanup=true";
    args << "power_on=true";
    
    args << "send_device_meta=true";
    args << "send_frame_meta=true";
    args << "send_dummy_byte=true";
    args << "raw_video_stream=false";
    */

#ifdef SERVER_DEBUGGER
    qInfo("Server debugger waiting for a client on device port " SERVER_DEBUGGER_PORT "...");
    // From the computer, run
    //     adb forward tcp:5005 tcp:5005
    // Then, from Android Studio: Run > Debug > Edit configurations...
    // On the left, click on '+', "Remote", with:
    //     Host: localhost
    //     Port: 5005
    // Then click on "Debug"
#endif

    // adb -s P7C0218510000537 shell CLASSPATH=/data/local/tmp/scrcpy-server app_process / com.genymobile.scrcpy.Server 0 8000000 false
    // mark: crop input format: "width:height:x:y" or "" for no crop, for example: "100:200:0:0"
    // 这条adb命令是阻塞运行的，m_serverProcess进程不会退出了
    m_serverProcess.execute(m_params.serial, args);
    return true;
}

bool Server::start(Server::ServerParams params)
{
    // 先停止并清理之前的连接（如果存在）
    if (m_serverStartStep != SSS_NULL) {
        stop();
    }
    
    m_params = params;
    // 如果使用直接TCP连接模式，跳过adb步骤，直接进入TCP连接
    if (params.useDirectTcp) {
        m_serverStartStep = SSS_DIRECT_TCP_CONNECT;
    } else {
        m_serverStartStep = SSS_CONNECT;
    }
    
    // 重置连接计数和状态
    m_connectCount = 0;
    m_asyncState = ACS_IDLE;
    
    return startServerByStep();
}

bool Server::connectTo()
{
    if (SSS_RUNNING != m_serverStartStep) {
        qWarning("server not run");
        return false;
    }

    if (!m_tunnelForward && !m_videoSocket) {
        startAcceptTimeoutTimer();
        return true;
    }

    startConnectTimeoutTimer();
    return true;
}

bool Server::isReverse()
{
    return !m_tunnelForward;
}

Server::ServerParams Server::getParams()
{
    return m_params;
}

void Server::timerEvent(QTimerEvent *event)
{
    if (event && m_acceptTimeoutTimer == event->timerId()) {
        stopAcceptTimeoutTimer();
        emit serverStarted(false);
    } else if (event && m_connectTimeoutTimer == event->timerId()) {
        onConnectTimer();
    }
}

bool Server::connectDevice()
{
    if (m_workProcess.isRuning()) {
        m_workProcess.kill();
    }
    m_workProcess.connectDevice(m_params.serial);
    return true;
}

VideoSocket* Server::removeVideoSocket()
{
    VideoSocket* socket = m_videoSocket;
    m_videoSocket = Q_NULLPTR;
    if (socket) {
        // 移除 parent，允许 socket 被移动到其他线程
        socket->setParent(nullptr);
    }
    return socket;
}

QTcpSocket *Server::getControlSocket()
{
    return m_controlSocket;
}

void Server::stop()
{
    if (m_tunnelForward) {
        stopConnectTimeoutTimer();
    } else {
        stopAcceptTimeoutTimer();
    }

    // 清理异步连接
    stopAsyncTimers();
    cleanupAsyncSockets();
    m_asyncState = ACS_IDLE;

    // 清理已连接的sockets
    if (m_videoSocket) {
        m_videoSocket->disconnect();
        if (m_videoSocket->state() != QAbstractSocket::UnconnectedState) {
            m_videoSocket->abort();
        }
        m_videoSocket->deleteLater();
        m_videoSocket = nullptr;
    }
    if (m_controlSocket) {
        m_controlSocket->disconnect();
        if (m_controlSocket->state() != QAbstractSocket::UnconnectedState) {
            m_controlSocket->abort();
        }
        m_controlSocket->deleteLater();
        m_controlSocket = nullptr;
    }
    
    // ignore failure
    m_serverProcess.kill();
    if (m_tunnelEnabled) {
        if (m_tunnelForward) {
            disableTunnelForward();
        } else {
            disableTunnelReverse();
        }
        m_tunnelForward = false;
        m_tunnelEnabled = false;
    }
    m_serverSocket.close();
    
    // 重置连接计数和状态，以便下次重连
    m_connectCount = 0;
    m_serverStartStep = SSS_NULL;
}

bool Server::startServerByStep()
{
    bool stepSuccess = false;
    // push, enable tunnel et start the server
    if (SSS_NULL != m_serverStartStep) {
        switch (m_serverStartStep) {
        case SSS_CONNECT:
            stepSuccess = connectDevice();
            break;
        case SSS_PUSH:
            stepSuccess = pushServer();
            break;
        case SSS_ENABLE_TUNNEL_REVERSE:
            stepSuccess = enableTunnelReverse();
            break;
        case SSS_ENABLE_TUNNEL_FORWARD:
            stepSuccess = enableTunnelForward();
            break;
        case SSS_EXECUTE_SERVER:
            // server will connect to our server socket
            stepSuccess = execute();
            break;
        case SSS_DIRECT_TCP_CONNECT:
            // 直接TCP连接模式，跳过所有adb步骤
            stepSuccess = connectDirectTcp();
            break;
        default:
            break;
        }
    }

    if (!stepSuccess) {
        emit serverStarted(false);
    }
    return stepSuccess;
}

bool Server::readInfo(VideoSocket *videoSocket, QString &deviceName, QSize &size)
{
    QElapsedTimer timer;
    timer.start();
    unsigned char buf[DEVICE_NAME_FIELD_LENGTH + 12];
    while (videoSocket->bytesAvailable() <= (DEVICE_NAME_FIELD_LENGTH + 12)) {
        videoSocket->waitForReadyRead(300);
        if (timer.elapsed() > 3000) {
            qInfo("readInfo timeout");
            return false;
        }
    }
    qDebug() << "readInfo wait time:" << timer.elapsed();

    qint64 len = videoSocket->read((char *)buf, sizeof(buf));
    if (len < DEVICE_NAME_FIELD_LENGTH + 12) {
        qInfo("Could not retrieve device information");
        return false;
    }
    buf[DEVICE_NAME_FIELD_LENGTH - 1] = '\0'; // in case the client sends garbage
    deviceName = QString::fromUtf8((const char *)buf);

    // 前4个字节是AVCodecID,当前只支持H264,所以先不解析
    size.setWidth(bufferRead32be(&buf[DEVICE_NAME_FIELD_LENGTH + 4]));
    size.setHeight(bufferRead32be(&buf[DEVICE_NAME_FIELD_LENGTH + 8]));

    return true;
}

bool Server::readInfoAsync(VideoSocket *videoSocket)
{
    // 异步版本：直接读取可用数据，不阻塞等待
    const int requiredBytes = DEVICE_NAME_FIELD_LENGTH + 12;
    
    if (videoSocket->bytesAvailable() < requiredBytes) {
        // 数据还没完全到达，返回false，等待下次readyRead信号
        return false;
    }

    unsigned char buf[DEVICE_NAME_FIELD_LENGTH + 12];
    qint64 len = videoSocket->read((char *)buf, sizeof(buf));
    if (len < requiredBytes) {
        qInfo("Could not retrieve device information");
        return false;
    }
    
    // 调试：打印原始数据的前16字节和关键位置的数据
    qDebug("readInfoAsync: Raw data (first 16 bytes): %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
           buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7],
           buf[8], buf[9], buf[10], buf[11], buf[12], buf[13], buf[14], buf[15]);
    qDebug("readInfoAsync: Codec offset[64-67]: %02x %02x %02x %02x",
           buf[DEVICE_NAME_FIELD_LENGTH], buf[DEVICE_NAME_FIELD_LENGTH+1], 
           buf[DEVICE_NAME_FIELD_LENGTH+2], buf[DEVICE_NAME_FIELD_LENGTH+3]);
    qDebug("readInfoAsync: Width offset[68-71]: %02x %02x %02x %02x",
           buf[DEVICE_NAME_FIELD_LENGTH+4], buf[DEVICE_NAME_FIELD_LENGTH+5],
           buf[DEVICE_NAME_FIELD_LENGTH+6], buf[DEVICE_NAME_FIELD_LENGTH+7]);
    qDebug("readInfoAsync: Height offset[72-75]: %02x %02x %02x %02x",
           buf[DEVICE_NAME_FIELD_LENGTH+8], buf[DEVICE_NAME_FIELD_LENGTH+9],
           buf[DEVICE_NAME_FIELD_LENGTH+10], buf[DEVICE_NAME_FIELD_LENGTH+11]);
    
    buf[DEVICE_NAME_FIELD_LENGTH - 1] = '\0'; // in case the client sends garbage
    m_pendingDeviceName = QString::fromUtf8((const char *)buf);

    // 前4个字节是AVCodecID,当前只支持H264,所以先不解析
    quint32 codecId = bufferRead32be(&buf[DEVICE_NAME_FIELD_LENGTH]);
    quint32 width = bufferRead32be(&buf[DEVICE_NAME_FIELD_LENGTH + 4]);
    quint32 height = bufferRead32be(&buf[DEVICE_NAME_FIELD_LENGTH + 8]);
    
    qDebug("readInfoAsync: Parsed - codecId=%u, width=%u, height=%u", codecId, width, height);
    
    m_pendingDeviceSize.setWidth(width);
    m_pendingDeviceSize.setHeight(height);

    qDebug() << "readInfoAsync success, device:" << m_pendingDeviceName 
             << "size:" << m_pendingDeviceSize;
    return true;
}

void Server::startAcceptTimeoutTimer()
{
    stopAcceptTimeoutTimer();
    m_acceptTimeoutTimer = startTimer(1000);
}

void Server::stopAcceptTimeoutTimer()
{
    if (m_acceptTimeoutTimer) {
        killTimer(m_acceptTimeoutTimer);
        m_acceptTimeoutTimer = 0;
    }
}

void Server::startConnectTimeoutTimer()
{
    stopConnectTimeoutTimer();
    m_connectTimeoutTimer = startTimer(300);
}

void Server::stopConnectTimeoutTimer()
{
    if (m_connectTimeoutTimer) {
        killTimer(m_connectTimeoutTimer);
        m_connectTimeoutTimer = 0;
    }
    m_connectCount = 0;
}

void Server::onConnectTimer()
{
    // device server need time to start
    // 这里连接太早时间不够导致安卓监听socket还没有建立，readInfo会失败，所以采取定时重试策略
    // 每隔100ms尝试一次，最多尝试MAX_CONNECT_COUNT次
    // 使用异步连接，避免阻塞UI线程
    if (m_asyncState != ACS_IDLE) {
        // 如果上一次异步连接还在进行中，跳过这次重试
        return;
    }
    startAsyncConnect();
}

void Server::startAsyncConnect()
{
    if (m_asyncState != ACS_IDLE) {
        qWarning() << "Server::startAsyncConnect - asyncState is not IDLE, current state:" << m_asyncState << ", cleaning up and resetting";
        // 如果状态不是IDLE，先清理并重置
        stopAsyncTimers();
        cleanupAsyncSockets();
        m_asyncState = ACS_IDLE;
    }

    // 清理之前的连接
    cleanupAsyncSockets();

    // 创建新的sockets，使用 this 作为 parent 确保在正确的线程中
    m_pendingVideoSocket = new VideoSocket(this);
    m_pendingControlSocket = new QTcpSocket(this);

    // 连接信号，使用 DirectConnection 因为都在同一线程
    connect(m_pendingVideoSocket, &VideoSocket::connected, this, &Server::onVideoSocketConnected, Qt::DirectConnection);
    connect(m_pendingVideoSocket, QOverload<QAbstractSocket::SocketError>::of(&VideoSocket::errorOccurred),
            this, &Server::onVideoSocketError, Qt::DirectConnection);
    connect(m_pendingVideoSocket, &VideoSocket::readyRead, this, &Server::onVideoDataReady, Qt::DirectConnection);

    connect(m_pendingControlSocket, &QTcpSocket::connected, this, &Server::onControlSocketConnected, Qt::DirectConnection);
    connect(m_pendingControlSocket, QOverload<QAbstractSocket::SocketError>::of(&QTcpSocket::errorOccurred),
            this, &Server::onControlSocketError, Qt::DirectConnection);

    // 设置连接超时定时器（总超时时间）
    if (!m_asyncConnectTimeoutTimer) {
        m_asyncConnectTimeoutTimer = new QTimer(this);
        m_asyncConnectTimeoutTimer->setSingleShot(true);
        connect(m_asyncConnectTimeoutTimer, &QTimer::timeout, this, &Server::handleConnectTimeout);
    }
    // TCP直连模式可能需要更长时间，特别是网络延迟较高时
    int timeoutMs = m_params.useDirectTcp ? 15000 : 5000; // TCP直连15秒，ADB模式5秒
    m_asyncConnectTimeoutTimer->start(timeoutMs);

    // 开始异步连接video socket
    m_asyncState = ACS_CONNECTING_VIDEO;
    
    // 根据连接模式选择目标地址和端口
    QHostAddress targetHost;
    quint16 targetPort;
    if (m_params.useDirectTcp) {
        // 直接TCP连接模式：使用指定的主机和端口
        QString hostStr = m_params.tcpHost.isEmpty() ? "localhost" : m_params.tcpHost;
        if (hostStr == "localhost" || hostStr == "127.0.0.1") {
            targetHost = QHostAddress::LocalHost;
        } else {
            targetHost = QHostAddress(hostStr);
        }
        targetPort = m_params.tcpVideoPort;
    } else {
        // ADB模式：使用本地端口
        targetHost = QHostAddress::LocalHost;
        targetPort = m_params.localPort;
    }
    
    qDebug("Connecting video socket to %s:%d", targetHost.toString().toStdString().c_str(), targetPort);
    
    // 验证目标地址
    if (targetHost.isNull()) {
        qCritical("Invalid target host address: %s", m_params.tcpHost.toStdString().c_str());
        handleConnectFailure();
        return;
    }
    
    // 设置socket选项，提高连接成功率
    m_pendingVideoSocket->setSocketOption(QAbstractSocket::LowDelayOption, 1);
    // 对于远程连接，可能需要更长的超时时间
    if (m_params.useDirectTcp) {
        // TCP直连模式：设置socket为非阻塞模式，由异步机制处理超时
        m_pendingVideoSocket->setSocketOption(QAbstractSocket::KeepAliveOption, 1);
    }
    
    qDebug("Attempting to connect video socket...");
    m_pendingVideoSocket->connectToHost(targetHost, targetPort);
    
    // 立即检查连接状态（用于调试）
    QTimer::singleShot(100, this, [this, targetHost, targetPort]() {
        if (m_pendingVideoSocket) {
            qDebug("Video socket state after 100ms: %d, error: %d", 
                   m_pendingVideoSocket->state(), m_pendingVideoSocket->error());
        }
    });
    // control socket会在video socket连接成功后再连接
}

void Server::onVideoSocketConnected()
{
    if (m_asyncState != ACS_CONNECTING_VIDEO) {
        return;
    }

    qDebug("Video socket connected successfully to %s:%d", 
           m_params.useDirectTcp ? m_params.tcpHost.toStdString().c_str() : "localhost",
           m_params.useDirectTcp ? m_params.tcpVideoPort : m_params.localPort);

    // Video socket连接成功，继续连接control socket
    m_asyncState = ACS_CONNECTING_CONTROL;
    
    // 根据连接模式选择目标地址和端口
    QHostAddress targetHost;
    quint16 targetPort;
    if (m_params.useDirectTcp) {
        // 直接TCP连接模式：使用指定的主机和控制端口
        QString hostStr = m_params.tcpHost.isEmpty() ? "localhost" : m_params.tcpHost;
        if (hostStr == "localhost" || hostStr == "127.0.0.1") {
            targetHost = QHostAddress::LocalHost;
        } else {
            targetHost = QHostAddress(hostStr);
        }
        targetPort = m_params.tcpControlPort;
    } else {
        // ADB模式：使用本地端口
        targetHost = QHostAddress::LocalHost;
        targetPort = m_params.localPort;
    }
    
    qDebug("Connecting control socket to %s:%d", targetHost.toString().toStdString().c_str(), targetPort);
    m_pendingControlSocket->connectToHost(targetHost, targetPort);
}

void Server::onVideoSocketError(QAbstractSocket::SocketError error)
{
    if (m_asyncState == ACS_IDLE) {
        return;
    }

    QString hostStr = m_params.useDirectTcp ? m_params.tcpHost : "localhost";
    quint16 port = m_params.useDirectTcp ? m_params.tcpVideoPort : m_params.localPort;
    
    QString errorString;
    switch(error) {
        case QAbstractSocket::ConnectionRefusedError:
            errorString = "Connection refused (端口可能未监听或防火墙阻止)";
            break;
        case QAbstractSocket::RemoteHostClosedError:
            errorString = "Remote host closed";
            break;
        case QAbstractSocket::HostNotFoundError:
            errorString = "Host not found";
            break;
        case QAbstractSocket::NetworkError:
            errorString = "Network error (网络不可达)";
            break;
        case QAbstractSocket::SocketAccessError:
            errorString = "Socket access error";
            break;
        case QAbstractSocket::SocketResourceError:
            errorString = "Socket resource error";
            break;
        case QAbstractSocket::SocketTimeoutError:
            errorString = "Connection timeout";
            break;
        case QAbstractSocket::UnknownSocketError:
            errorString = "Unknown socket error";
            break;
        default:
            errorString = QString("Error code: %1").arg(static_cast<int>(error));
            break;
    }
    
    qWarning("video socket connect to server failed: %s:%d, %s", 
             hostStr.toStdString().c_str(), port, errorString.toStdString().c_str());
    
    // 连接失败，等待下次重试
    handleConnectFailure();
}

void Server::onControlSocketConnected()
{
    if (m_asyncState != ACS_CONNECTING_CONTROL) {
        return;
    }

    qDebug("Control socket connected successfully to %s:%d", 
           m_params.useDirectTcp ? m_params.tcpHost.toStdString().c_str() : "localhost",
           m_params.useDirectTcp ? m_params.tcpControlPort : m_params.localPort);

    // 两个socket都连接成功，开始读取设备信息
    m_asyncState = ACS_READING_INFO;

    // 检查是否有数据可读
    if (m_pendingVideoSocket->bytesAvailable() > 0) {
        onVideoDataReady();
    } else {
        // 设置读取超时定时器
        if (!m_readInfoTimeoutTimer) {
            m_readInfoTimeoutTimer = new QTimer(this);
            m_readInfoTimeoutTimer->setSingleShot(true);
            connect(m_readInfoTimeoutTimer, &QTimer::timeout, this, [this]() {
                if (m_asyncState == ACS_READING_INFO) {
                    qWarning("read device info timeout");
                    handleConnectFailure();
                }
            });
        }
        m_readInfoTimeoutTimer->start(3000); // 3秒读取超时
    }
}

void Server::onControlSocketError(QAbstractSocket::SocketError error)
{
    if (m_asyncState == ACS_IDLE) {
        return;
    }

    QString hostStr = m_params.useDirectTcp ? m_params.tcpHost : "localhost";
    quint16 port = m_params.useDirectTcp ? m_params.tcpControlPort : m_params.localPort;
    
    QString errorString;
    switch(error) {
        case QAbstractSocket::ConnectionRefusedError:
            errorString = "Connection refused (端口可能未监听或防火墙阻止)";
            break;
        case QAbstractSocket::RemoteHostClosedError:
            errorString = "Remote host closed";
            break;
        case QAbstractSocket::HostNotFoundError:
            errorString = "Host not found";
            break;
        case QAbstractSocket::NetworkError:
            errorString = "Network error (网络不可达)";
            break;
        case QAbstractSocket::SocketAccessError:
            errorString = "Socket access error";
            break;
        case QAbstractSocket::SocketResourceError:
            errorString = "Socket resource error";
            break;
        case QAbstractSocket::SocketTimeoutError:
            errorString = "Connection timeout";
            break;
        case QAbstractSocket::UnknownSocketError:
            errorString = "Unknown socket error";
            break;
        default:
            errorString = QString("Error code: %1").arg(static_cast<int>(error));
            break;
    }
    
    qWarning("control socket connect to server failed: %s:%d, %s", 
             hostStr.toStdString().c_str(), port, errorString.toStdString().c_str());
    
    handleConnectFailure();
}

void Server::onVideoDataReady()
{
    if (m_asyncState != ACS_READING_INFO) {
        return;
    }

    // 根据连接模式决定数据格式
    // tunnel_forward模式：先发送1字节，然后设备信息
    // TCP直连模式：可能直接发送设备信息（类似reverse模式）
    bool needFirstByte = m_tunnelForward && !m_params.useDirectTcp;
    const int baseBytes = DEVICE_NAME_FIELD_LENGTH + 12;
    const int requiredTotalBytes = needFirstByte ? (1 + baseBytes) : baseBytes;
    
    qint64 available = m_pendingVideoSocket->bytesAvailable();
    qDebug("onVideoDataReady: bytesAvailable=%lld, required=%d, needFirstByte=%d", 
           available, requiredTotalBytes, needFirstByte);
    
    // 对于TCP直连模式，如果数据比预期多，可能是前面有额外的字节
    // 先检查并打印前几个字节看看
    if (m_params.useDirectTcp && available > baseBytes) {
        QByteArray peekData = m_pendingVideoSocket->peek(qMin(available, (qint64)20));
        QString hexStr;
        for (int i = 0; i < peekData.size(); i++) {
            hexStr += QString::asprintf("%02x ", (unsigned char)peekData[i]);
        }
        qDebug("onVideoDataReady: TCP直连模式，前%d字节: %s", peekData.size(), hexStr.toStdString().c_str());
        
        // 如果数据比预期多1字节，可能是前面有标识字节，需要跳过
        if (available == baseBytes + 1) {
            QByteArray extraByte = m_pendingVideoSocket->read(1);
            qDebug("onVideoDataReady: TCP直连模式，跳过前导字节: 0x%02x", 
                   static_cast<unsigned char>(extraByte[0]));
        }
    }
    
    if (m_pendingVideoSocket->bytesAvailable() < requiredTotalBytes) {
        // 数据还没完全到达，等待下次readyRead信号
        // 确保读取超时定时器在运行
        if (m_readInfoTimeoutTimer && !m_readInfoTimeoutTimer->isActive()) {
            m_readInfoTimeoutTimer->start(3000);
        }
        return;
    }

    // 如果需要，读取第一个字节（tunnel forward模式的标识）
    if (needFirstByte) {
        QByteArray firstByte = m_pendingVideoSocket->read(1);
        if (firstByte.isEmpty()) {
            qWarning("Failed to read first byte");
            handleConnectFailure();
            return;
        }
        qDebug("Read first byte: 0x%02x", static_cast<unsigned char>(firstByte[0]));
    }

    // 现在读取设备信息（异步版本）
    if (readInfoAsync(m_pendingVideoSocket)) {
        // 停止读取超时定时器
        if (m_readInfoTimeoutTimer) {
            m_readInfoTimeoutTimer->stop();
        }
        // 读取成功
        qDebug("Device info read successfully");
        handleConnectSuccess();
        return;
    }

    // readInfoAsync返回false说明数据还不够（理论上不应该发生，因为我们已经检查了）
    qWarning("readInfoAsync failed even though enough bytes are available");
    handleConnectFailure();
}

void Server::handleConnectSuccess()
{
    if (m_asyncState == ACS_IDLE) {
        return;
    }

    stopConnectTimeoutTimer();
    stopAsyncTimers();

    // 设置最终sockets
    m_videoSocket = m_pendingVideoSocket;
    m_controlSocket = m_pendingControlSocket;

    // devices will send 1 byte first on tunnel forward mode
    // 对于TCP直连模式，control socket可能不需要读取第一个字节
    // 因为TCP直连模式类似reverse模式，不需要这个标识字节
    //if (m_tunnelForward && !m_params.useDirectTcp) {
    if (true) {
        // tunnel_forward模式：读取control socket的第一个字节
        if (m_controlSocket->bytesAvailable() > 0) {
            m_controlSocket->read(1);
        }
    }

    // we don't need the adb tunnel anymore (only for ADB mode)
    if (!m_params.useDirectTcp) {
        if (m_tunnelForward) {
            disableTunnelForward();
        } else {
            disableTunnelReverse();
        }
        m_tunnelEnabled = false;
    }
    m_restartCount = 0;

    m_asyncState = ACS_COMPLETE;
    emit serverStarted(true, m_pendingDeviceName, m_pendingDeviceSize);

    // 清理临时指针（对象已经转移）
    m_pendingVideoSocket = nullptr;
    m_pendingControlSocket = nullptr;
    m_asyncState = ACS_IDLE;
}

void Server::handleConnectFailure()
{
    if (m_asyncState == ACS_IDLE) {
        return;
    }

    stopAsyncTimers();
    cleanupAsyncSockets();

    if (MAX_CONNECT_COUNT <= m_connectCount++) {
        stopConnectTimeoutTimer();
        stop();
        if (MAX_RESTART_COUNT > m_restartCount++) {
            qWarning("restart server auto");
            // 重置连接计数，以便重试
            m_connectCount = 0;
            start(m_params);
        } else {
            m_restartCount = 0;
            m_connectCount = 0;  // 重置连接计数，以便下次手动重连
            emit serverStarted(false);
        }
    } else {
        // 未达到最大重试次数，重置状态以便重试
        m_asyncState = ACS_IDLE;
    }
}

void Server::handleConnectTimeout()
{
    if (m_asyncState == ACS_IDLE) {
        return;
    }

    QString hostStr = m_params.useDirectTcp ? m_params.tcpHost : "localhost";
    quint16 videoPort = m_params.useDirectTcp ? m_params.tcpVideoPort : m_params.localPort;
    quint16 controlPort = m_params.useDirectTcp ? m_params.tcpControlPort : m_params.localPort;
    
    qWarning("async connect timeout after 15s. Host: %s, Video port: %d, Control port: %d, State: %d", 
             hostStr.toStdString().c_str(), videoPort, controlPort, m_asyncState);
    
    // 输出socket状态信息以便调试
    if (m_pendingVideoSocket) {
        QString stateStr;
        switch(m_pendingVideoSocket->state()) {
            case QAbstractSocket::UnconnectedState: stateStr = "Unconnected"; break;
            case QAbstractSocket::HostLookupState: stateStr = "HostLookup"; break;
            case QAbstractSocket::ConnectingState: stateStr = "Connecting"; break;
            case QAbstractSocket::ConnectedState: stateStr = "Connected"; break;
            case QAbstractSocket::BoundState: stateStr = "Bound"; break;
            case QAbstractSocket::ListeningState: stateStr = "Listening"; break;
            case QAbstractSocket::ClosingState: stateStr = "Closing"; break;
            default: stateStr = QString("Unknown(%1)").arg(m_pendingVideoSocket->state()); break;
        }
        
        QString errorStr;
        QAbstractSocket::SocketError err = m_pendingVideoSocket->error();
        switch(err) {
            case QAbstractSocket::ConnectionRefusedError: errorStr = "ConnectionRefused"; break;
            case QAbstractSocket::RemoteHostClosedError: errorStr = "RemoteHostClosed"; break;
            case QAbstractSocket::HostNotFoundError: errorStr = "HostNotFound"; break;
            case QAbstractSocket::NetworkError: errorStr = "NetworkError"; break;
            case QAbstractSocket::SocketAccessError: errorStr = "SocketAccessError"; break;
            case QAbstractSocket::SocketResourceError: errorStr = "SocketResourceError"; break;
            case QAbstractSocket::SocketTimeoutError: errorStr = "SocketTimeoutError"; break;
            case QAbstractSocket::UnknownSocketError: errorStr = "UnknownError"; break;
            default: errorStr = QString("Error(%1)").arg(static_cast<int>(err)); break;
        }
        
        qWarning("Video socket state: %s, error: %s", stateStr.toStdString().c_str(), errorStr.toStdString().c_str());
    }
    if (m_pendingControlSocket) {
        QString stateStr;
        switch(m_pendingControlSocket->state()) {
            case QAbstractSocket::UnconnectedState: stateStr = "Unconnected"; break;
            case QAbstractSocket::HostLookupState: stateStr = "HostLookup"; break;
            case QAbstractSocket::ConnectingState: stateStr = "Connecting"; break;
            case QAbstractSocket::ConnectedState: stateStr = "Connected"; break;
            default: stateStr = QString("Unknown(%1)").arg(m_pendingControlSocket->state()); break;
        }
        qWarning("Control socket state: %s", stateStr.toStdString().c_str());
    }
    
    handleConnectFailure();
}

void Server::cleanupAsyncSockets()
{
    if (m_pendingVideoSocket) {
        m_pendingVideoSocket->disconnect();
        // 先关闭socket，避免在清理时产生线程警告
        if (m_pendingVideoSocket->state() != QAbstractSocket::UnconnectedState) {
            m_pendingVideoSocket->abort();
        }
        m_pendingVideoSocket->deleteLater();
        m_pendingVideoSocket = nullptr;
    }
    if (m_pendingControlSocket) {
        m_pendingControlSocket->disconnect();
        // 先关闭socket，避免在清理时产生线程警告
        if (m_pendingControlSocket->state() != QAbstractSocket::UnconnectedState) {
            m_pendingControlSocket->abort();
        }
        m_pendingControlSocket->deleteLater();
        m_pendingControlSocket = nullptr;
    }
}

void Server::stopAsyncTimers()
{
    if (m_asyncConnectTimeoutTimer) {
        m_asyncConnectTimeoutTimer->stop();
    }
    if (m_readInfoTimeoutTimer) {
        m_readInfoTimeoutTimer->stop();
    }
}

bool Server::connectDirectTcp()
{
    // 验证TCP连接参数，如果host为空，使用默认值localhost
    QString host = m_params.tcpHost.isEmpty() ? "localhost" : m_params.tcpHost;
    
    if (m_params.tcpVideoPort == 0) {
        qCritical("TCP direct connect: tcpVideoPort is invalid");
        emit serverStarted(false);
        return false;
    }
    
    if (m_params.tcpControlPort == 0) {
        qCritical("TCP direct connect: tcpControlPort is invalid");
        emit serverStarted(false);
        return false;
    }
    
    // 更新host参数（如果使用了默认值）
    if (m_params.tcpHost.isEmpty()) {
        m_params.tcpHost = host;
    }
    
    qInfo("TCP direct connect: connecting to %s:%d (video) and %d (control) and %d (audio)", 
          m_params.tcpHost.toStdString().c_str(), 
          m_params.tcpVideoPort, 
          m_params.tcpControlPort,
          m_params.tcpAudioPort);
    
    // 设置状态为运行中，然后开始连接
    m_serverStartStep = SSS_RUNNING;
    m_tunnelEnabled = false;  // 直接TCP模式不使用adb隧道
    m_tunnelForward = false;  // 不使用forward模式
    
    // 启动异步连接
    startConnectTimeoutTimer();
    
    return true;
}

void Server::onWorkProcessResult(qsc::AdbProcess::ADB_EXEC_RESULT processResult)
{
    if (sender() == &m_workProcess) {
        if (SSS_NULL != m_serverStartStep) {
            switch (m_serverStartStep) {
            case SSS_CONNECT:
                if (qsc::AdbProcess::AER_SUCCESS_EXEC == processResult) {
                    m_serverStartStep = SSS_PUSH;
                    startServerByStep();
                } else if (qsc::AdbProcess::AER_SUCCESS_START != processResult) {
                    qCritical("adb connect failed");
                    m_serverStartStep = SSS_NULL;
                    emit serverStarted(false);
                }
                break;
            case SSS_PUSH:
                if (qsc::AdbProcess::AER_SUCCESS_EXEC == processResult) {
                    if (m_params.useReverse) {
                        m_serverStartStep = SSS_ENABLE_TUNNEL_REVERSE;
                    } else {
                        m_tunnelForward = true;
                        m_serverStartStep = SSS_ENABLE_TUNNEL_FORWARD;
                    }
                    startServerByStep();
                } else if (qsc::AdbProcess::AER_SUCCESS_START != processResult) {
                    qCritical("adb push failed");
                    m_serverStartStep = SSS_NULL;
                    emit serverStarted(false);
                }
                break;
            case SSS_ENABLE_TUNNEL_REVERSE:
                if (qsc::AdbProcess::AER_SUCCESS_EXEC == processResult) {
                    // At the application level, the device part is "the server" because it
                    // serves video stream and control. However, at the network level, the
                    // client listens and the server connects to the client. That way, the
                    // client can listen before starting the server app, so there is no need to
                    // try to connect until the server socket is listening on the device.
                    m_serverSocket.setMaxPendingConnections(2);
                    if (!m_serverSocket.listen(QHostAddress::LocalHost, m_params.localPort)) {
                        qCritical() << QString("Could not listen on port %1").arg(m_params.localPort).toStdString().c_str();
                        m_serverStartStep = SSS_NULL;
                        disableTunnelReverse();
                        emit serverStarted(false);
                        break;
                    }

                    m_serverStartStep = SSS_EXECUTE_SERVER;
                    startServerByStep();
                } else if (qsc::AdbProcess::AER_SUCCESS_START != processResult) {
                    // 有一些设备reverse会报错more than o'ne device，adb的bug
                    // https://github.com/Genymobile/scrcpy/issues/5
                    qCritical("adb reverse failed");
                    m_tunnelForward = true;
                    m_serverStartStep = SSS_ENABLE_TUNNEL_FORWARD;
                    startServerByStep();
                }
                break;
            case SSS_ENABLE_TUNNEL_FORWARD:
                if (qsc::AdbProcess::AER_SUCCESS_EXEC == processResult) {
                    m_serverStartStep = SSS_EXECUTE_SERVER;
                    startServerByStep();
                } else if (qsc::AdbProcess::AER_SUCCESS_START != processResult) {
                    qCritical("adb forward failed");
                    m_serverStartStep = SSS_NULL;
                    emit serverStarted(false);
                }
                break;
            default:
                break;
            }
        }
    }
    if (sender() == &m_serverProcess) {
        if (SSS_EXECUTE_SERVER == m_serverStartStep) {
            if (qsc::AdbProcess::AER_SUCCESS_START == processResult) {
                m_serverStartStep = SSS_RUNNING;
                m_tunnelEnabled = true;
                connectTo();
            } else if (qsc::AdbProcess::AER_ERROR_START == processResult) {
                if (!m_tunnelForward) {
                    m_serverSocket.close();
                    disableTunnelReverse();
                } else {
                    disableTunnelForward();
                }
                qCritical("adb shell start server failed");
                m_serverStartStep = SSS_NULL;
                emit serverStarted(false);
            }
        } else if (SSS_RUNNING == m_serverStartStep) {
            m_serverStartStep = SSS_NULL;
            emit serverStoped();
        }
    }
}
