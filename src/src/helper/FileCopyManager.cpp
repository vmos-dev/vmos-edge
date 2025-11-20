#include "FileCopyManager.h"
#include "filecopyworker.h"
#include <QThread>
#include <QDebug>
#include <QFileInfo>
#include <QDir>
#include <QStorageInfo>

// Singleton instance provider
FileCopyManager *FileCopyManager::instance()
{
    static FileCopyManager inst; // C++11 thread-safe static local
    return &inst;
}

FileCopyManager::FileCopyManager(QObject *parent)
    : QObject(parent)
{
}

int FileCopyManager::progressPercent() const
{
    if (m_totalSize <= 0) {
        return 0;
    }
    return static_cast<int>((m_copiedSize * 100) / m_totalSize);
}

bool FileCopyManager::startCopy(const QString &source, const QString &destination, const QString &tempDirToCleanup)
{
    if (m_isCopying) {
        m_status = "Already copying...";
        emit statusChanged();
        return false;
    }

    QFileInfo destInfo(destination);
    QDir destDir = destInfo.dir();
    if (!destDir.exists()) {
        if (!destDir.mkpath(".")) {
            m_status = "Failed to create destination directory.";
            emit statusChanged();
            emit copyFailed(m_status);
            return false;
        }
    }

    // 存储临时目录路径，用于复制完成后清理
    m_tempDirToCleanup = tempDirToCleanup;

    m_isCopying = true;
    m_status = "Starting copy...";
    m_copiedSize = 0;
    m_totalSize = 0;
    emit isCopyingChanged();
    emit statusChanged();
    emit progressChanged();
    emit totalSizeChanged();

    QThread* thread = new QThread(this); // Set parent to enable auto-deletion if manager is destroyed
    FileCopyWorker* worker = new FileCopyWorker();
    worker->moveToThread(thread);

    // When the thread starts, call the worker's doCopy method.
    // The lambda is needed to pass arguments to the slot.
    connect(thread, &QThread::started, worker, [worker, source, destination](){
        worker->doCopy(source, destination);
    });

    // Connect worker signals to manager slots
    connect(worker, &FileCopyWorker::progress, this, &FileCopyManager::onCopyProgress);
    connect(worker, &FileCopyWorker::finished, this, &FileCopyManager::onCopyFinished);

    // Automatically quit the thread when the worker is finished
    connect(worker, &FileCopyWorker::finished, thread, &QThread::quit);

    // Automatically delete the worker and the thread when the thread has finished its event loop
    connect(thread, &QThread::finished, worker, &FileCopyWorker::deleteLater);
    connect(thread, &QThread::finished, thread, &QThread::deleteLater);

    thread->start();

    return true;
}

bool FileCopyManager::startDelete(const QString &filePath)
{
    m_deletingFilePath = filePath;
    m_status = "Starting delete...";
    emit statusChanged();

    QThread* thread = new QThread(this);
    FileCopyWorker* worker = new FileCopyWorker();
    worker->moveToThread(thread);

    // When the thread starts, call the worker's doDelete method
    connect(thread, &QThread::started, worker, [worker, filePath](){
        worker->doDelete(filePath);
    });

    // Connect worker signals to manager slots
    connect(worker, &FileCopyWorker::deleteFinished, this, &FileCopyManager::onDeleteFinished);

    // Automatically quit the thread when the worker is finished
    connect(worker, &FileCopyWorker::deleteFinished, thread, &QThread::quit);

    // Automatically delete the worker and the thread when the thread has finished its event loop
    connect(thread, &QThread::finished, worker, &FileCopyWorker::deleteLater);
    connect(thread, &QThread::finished, thread, &QThread::deleteLater);

    thread->start();

    return true;
}

void FileCopyManager::onDeleteFinished(bool success, const QString &message)
{
    m_status = message;
    emit statusChanged();

    if (success) {
        emit deleteSucceeded(m_deletingFilePath);
    } else {
        emit deleteFailed(message);
    }
}

void FileCopyManager::onCopyProgress(qint64 copiedSize, qint64 totalSize)
{
    if (m_totalSize != totalSize) {
        m_totalSize = totalSize;
        emit totalSizeChanged();
    }
    m_copiedSize = copiedSize;
    emit progressChanged();
}

void FileCopyManager::onCopyFinished(bool success, const QString &message)
{
    m_isCopying = false;
    m_status = message;
    emit isCopyingChanged();
    emit statusChanged();

    // 复制完成后清理临时目录
    if (!m_tempDirToCleanup.isEmpty()) {
        qDebug() << "Cleaning up temporary directory after copy completion:" << m_tempDirToCleanup;
        cleanupTempDirectory(m_tempDirToCleanup);
        m_tempDirToCleanup.clear();
    }

    if (success) {
        emit copySucceeded();
    } else {
        emit copyFailed(message);
    }
}

qint64 FileCopyManager::getFileSize(const QString &filePath)
{
    QFileInfo fileInfo(filePath);
    if (!fileInfo.exists()) {
        return -1; // 文件不存在
    }
    return fileInfo.size();
}

qint64 FileCopyManager::getAvailableSpace(const QString &path)
{
    QString rootPath;
#ifdef Q_OS_WIN
    // 强制解析盘符根路径，如 C:/
    QString p = QDir::fromNativeSeparators(path);
    if (p.size() >= 2 && p.at(1) == ':') {
        rootPath = p.left(2) + "/";
    } else {
        QFileInfo fi(p);
        QString abs = QDir::fromNativeSeparators(fi.absoluteFilePath());
        if (abs.size() >= 2 && abs.at(1) == ':') {
            rootPath = abs.left(2) + "/";
        } else {
            rootPath = QDir::rootPath();
        }
    }
#else
    // 非 Windows：使用所在卷根路径；若不可用则直接用系统根路径
    QStorageInfo info(path.isEmpty() ? QDir::rootPath() : path);
    rootPath = info.rootPath();
    if (rootPath.isEmpty()) {
        rootPath = QDir::rootPath();
    }
#endif

    QStorageInfo storageInfo(rootPath);

    if (!storageInfo.isValid() || !storageInfo.isReady()) {
        qDebug() << "磁盘路径(查询根)无效:" << rootPath;
        return 0; // 避免返回负数
    }

    qint64 availableSize = static_cast<qint64>(storageInfo.bytesAvailable());

    qDebug() << "磁盘路径(查询根):" << rootPath;
    qDebug() << "可用空间:" << availableSize << "bytes (" << (availableSize / 1024.0 / 1024.0 / 1024.0) << "GB)";

    return availableSize;
}

bool FileCopyManager::startImageValidation(const QString &imagePath)
{
    m_status = "Starting image validation...";
    emit statusChanged();
    emit validationProgress("开始校验", 0);

    QThread* thread = new QThread(this);
    FileCopyWorker* worker = new FileCopyWorker();
    worker->moveToThread(thread);

    connect(thread, &QThread::started, worker, [worker, imagePath](){
        worker->doValidateImage(imagePath);
    });

    connect(worker, &FileCopyWorker::validationProgress, this, &FileCopyManager::validationProgress);
    connect(worker, &FileCopyWorker::validationFinished, this, &FileCopyManager::onValidationFinished);
    connect(worker, &FileCopyWorker::validationFinished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &FileCopyWorker::deleteLater);
    connect(thread, &QThread::finished, thread, &QThread::deleteLater);

    thread->start();
    return true;
}

void FileCopyManager::onValidationFinished(bool success, const QString &message, const QString &imageName, const QString &tarFilePath)
{
    m_status = message;
    emit statusChanged();

    if (success) {
        emit validationSucceeded(imageName, tarFilePath);
    } else {
        emit validationFailed(message);
    }
}

bool FileCopyManager::startImageInfoExtraction(const QString &imagePath)
{
    if (m_isCopying) {
        m_status = "Already processing...";
        emit statusChanged();
        return false;
    }

    m_status = "Extracting image info...";
    emit statusChanged();

    QThread* thread = new QThread(this);
    FileCopyWorker* worker = new FileCopyWorker();
    worker->moveToThread(thread);

    connect(thread, &QThread::started, worker, [worker, imagePath](){
        worker->doExtractImageInfo(imagePath);
    });

    connect(worker, &FileCopyWorker::imageInfoExtracted, this, &FileCopyManager::onImageInfoExtracted);
    connect(worker, &FileCopyWorker::imageInfoExtracted, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &FileCopyWorker::deleteLater);
    connect(thread, &QThread::finished, thread, &QThread::deleteLater);

    thread->start();
    return true;
}

void FileCopyManager::onImageInfoExtracted(bool success, const QString &imageName, const QString &androidVersion, const QString &errorMessage)
{
    m_status = success ? "Image info extracted successfully" : "Failed to extract image info";
    emit statusChanged();

    emit imageInfoExtracted(success, imageName, androidVersion, errorMessage);
}

bool FileCopyManager::startImageInfoAndValidation(const QString &imagePath)
{
    if (m_isCopying) {
        m_status = "Already processing...";
        emit statusChanged();
        return false;
    }

    m_status = "Processing image info and validation...";
    emit statusChanged();
    emit validationProgress("开始处理", 0);

    QThread* thread = new QThread(this);
    FileCopyWorker* worker = new FileCopyWorker();
    worker->moveToThread(thread);

    connect(thread, &QThread::started, worker, [worker, imagePath](){
        worker->doExtractAndValidateImage(imagePath);
    });

    connect(worker, &FileCopyWorker::validationProgress, this, &FileCopyManager::validationProgress);
    connect(worker, &FileCopyWorker::imageInfoAndValidationCompleted, this, &FileCopyManager::onImageInfoAndValidationCompleted);
    connect(worker, &FileCopyWorker::imageInfoAndValidationCompleted, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &FileCopyWorker::deleteLater);
    connect(thread, &QThread::finished, thread, &QThread::deleteLater);

    thread->start();
    return true;
}

void FileCopyManager::onImageInfoAndValidationCompleted(bool success, const QString &message, const QString &imageName, const QString &androidVersion, const QString &tarFilePath)
{
    m_status = success ? "Image processing completed successfully" : "Failed to process image";
    emit statusChanged();

    emit imageInfoAndValidationCompleted(success, message, imageName, androidVersion, tarFilePath);
}

void FileCopyManager::cleanupTempDirectory(const QString &tempDir)
{
    QDir dir(tempDir);
    if (!dir.exists()) {
        qDebug() << "Temporary directory does not exist:" << tempDir;
        return;
    }
    
    // 首先尝试删除所有文件
    QStringList files = dir.entryList(QDir::Files);
    for (const QString &file : files) {
        QString filePath = dir.absoluteFilePath(file);
        if (!QFile::remove(filePath)) {
            qDebug() << "Failed to remove file:" << filePath;
        }
    }
    
    // 然后删除所有子目录
    QStringList dirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &subDir : dirs) {
        QString subDirPath = dir.absoluteFilePath(subDir);
        QDir subDirObj(subDirPath);
        if (!subDirObj.removeRecursively()) {
            qDebug() << "Failed to remove subdirectory:" << subDirPath;
        }
    }
    
    // 最后尝试删除主目录
    if (!dir.removeRecursively()) {
        qDebug() << "Failed to remove temporary directory:" << tempDir;
        // 尝试强制删除
        QDir parentDir = dir;
        parentDir.cdUp();
        QString dirName = QFileInfo(tempDir).fileName();
        if (!parentDir.rmdir(dirName)) {
            qDebug() << "Force removal also failed for:" << tempDir;
        } else {
            qDebug() << "Force removal succeeded for:" << tempDir;
        }
    } else {
        qDebug() << "Successfully cleaned up temporary directory:" << tempDir;
    }
}
