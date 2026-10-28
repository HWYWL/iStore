#ifndef LIBSSH2_SSHSESSION_H
#define LIBSSH2_SSHSESSION_H

#include <libssh2.h>
#include <queue>
#include <thread>
#include <sys/socket.h>
#include <future>
#include <string>
#include <hilog/log.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <filemanagement/environment/oh_environment.h>
#include <filemanagement/fileio/oh_fileio.h>
#include <unistd.h>
#include <cstring>
#include <algorithm>
#include <regex>
#include <sstream>
#include <vector>
#include <numeric>
#include <mutex>
#include <list>
#include <chrono>
#include <atomic>
#include <functional>
#include <sys/types.h>
#include <condition_variable>
#include <deque>

#include "protocol/Session.h"
#include "jsonAnalyse/jsonAnalyse.h"
#include "protocol/SessionManager/SessionManager.h"
#include "command.h"
#include "SftpSession.h"
#include "SshPortForward.h"
#include <memory>
#include "LogManager.h"

using std::string;
using std::vector;

#define READ_MAX_BUFF_SIZE  4096
#define SSH_TIME_OUT        600

#undef LOG_DOMAIN 
#undef LOG_TAG 
#define LOG_DOMAIN 0x3200 // 全局domain宏，标识业务领域 
#define LOG_TAG "MY_TAG"  // 全局tag宏，标识模块日志tag

// OSC7 目录跟踪相关定义
#define OSC7_PREFIX "\033]7;file://"  // ESC + ]7;file://
#define OSC7_SUFFIX "\007"            // BEL 结束符

class SshPortForward;  // 前向声明

class ThreadPool {
public:
    ThreadPool(size_t numThreads)
        : stop(false)
    {
        for (size_t i = 0; i < numThreads; ++i) {
            workers.emplace_back([this] {
                for (;;) {
                    std::function<void()> task;
                    {
                        std::unique_lock<std::mutex> lock(this->queueMutex);
                        this->condition.wait(lock, [this] {
                            return this->stop || !this->tasks.empty();
                        });
                        if (this->stop && this->tasks.empty())
                            return;
                        task = std::move(this->tasks.front());
                        this->tasks.pop();
                    }
                    task();
                }
            });
        }
    }

    ~ThreadPool() {
        {
            std::unique_lock<std::mutex> lock(queueMutex);
            stop = true;
        }
        condition.notify_all();
        for (std::thread &worker : workers)
            worker.join();
    }

    template<class F, class... Args>
    auto enqueue(F&& f, Args&&... args)-> std::future<std::invoke_result_t<F, Args...>>
    {
        using return_type = std::invoke_result_t<F, Args...>;

        auto task = std::make_shared<std::packaged_task<return_type()>>(
            std::bind(std::forward<F>(f), std::forward<Args>(args)...)
        );

        std::future<return_type> res = task->get_future();
        {
            std::unique_lock<std::mutex> lock(queueMutex);
            if (stop)
                throw std::runtime_error("enqueue on stopped ThreadPool");
            tasks.emplace([task]() { (*task)(); });
        }
        condition.notify_one();
        return res;
    }

private:
    std::vector<std::thread> workers;
    std::queue<std::function<void()>> tasks;
    std::mutex queueMutex;
    std::condition_variable condition;
    bool stop;
};

class SshSession : public Session {
private:
    std::unique_ptr<LIBSSH2_SESSION, decltype(&libssh2_session_free)> session;
    std::unique_ptr<LIBSSH2_CHANNEL, decltype(&libssh2_channel_free)> channelShell;
    std::unique_ptr<LIBSSH2_KNOWNHOSTS, decltype(&libssh2_knownhost_free)> knownHosts;
    std::unique_ptr<libssh2_socket_t> sock;
    std::unique_ptr<ThreadPool> threadPool;
    std::atomic<bool> stopThread {false};
    std::atomic<bool> statusChange {false};
    std::recursive_mutex libssh2Mutex;
    
    // --- 新增：日志缓冲成员 ---
    std::string initialBuffer;
    std::mutex bufferMutex;
    std::atomic<bool> logManagerInitialized{false};
    static const size_t MAX_INITIAL_BUFFER_SIZE = 16 * 1024; // 限制初始缓冲区大小，例如16KB
    // -------------------------
    
    // 认证相关信息
    std::string hostname;
    int port;
    std::string username;
    std::string password;
    bool useKeyAuth = false;
    std::string privateKeyPath;
    std::string privateKeyData;
    std::string passphrase;
    
    // 保活相关参数
    int keepAliveInterval = 60;  // 保活时间间隔（秒）
    
    int waitSocket();
    
    void runAsyncInThreadPool(std::function<void()> task);
    
    void receiveData();
    
    // --- 新增：keepAliveThread方法声明 ---
    void keepAliveThread();
    // ----------------------------
    
    void inline pendingCallData(std::string data, bool status);
    
    void callBackSendData();
    
    std::mutex callBackDataMutex;
    std::mutex statusMutex;
    std::condition_variable callBackDataCV;
    
    std::list<std::pair<std::string, bool>> dataCallBackList;
    
    std::unique_ptr<SftpSession> interactiveSftpSession; // 用于交互式操作的 SFTP 会话
    std::unique_ptr<SftpSession> transferSftpSession;    // 用于文件传输的 SFTP 会话
    std::unique_ptr<SshPortForward> portForward;
    
    // 提供给SshPortForward的友元接口
    friend class SshPortForward;
    LIBSSH2_SESSION* getLibssh2Session() const { return session.get(); }
    libssh2_socket_t getSocket() const { return *sock.get(); }
    
    // 每个会话独立的日志管理器，避免多会话并发覆盖同一 fd 和状态
    LogManager logManager;
    
    // --- 日志就绪同步（已被移除） ---
    // std::atomic<bool> logManagerReady{false}; // REMOVED
    // std::mutex logReadyMutex; // REMOVED
    // std::condition_variable logReadyCV; // REMOVED
    // --------------------------
    
    // 添加OSC7目录跟踪相关成员
    std::string currentDirectory;
    // std::regex osc7Regex; // 不再使用正则表达式
    std::function<void(const std::string&)> directoryChangeCallback;
    std::atomic<bool> followTerminalDirectory{false};

    std::atomic<bool> isConfiguringShell{false};
    
    void parseOSC7Sequence(const std::string& data);
    
public:
    // 移动到 public 区域
    bool isConnected() const { return status == SessionStatus::CONNECTED; }

    SshSession();
    
    ~SshSession() override;
    
    bool openConnect(const std::string& napiInput) override;
    
    bool disconnect() override;
    
    bool sendData(const std::string& command) override;

    /** channel exec 模式执行命令（独立 channel，EOF 立即返回），返回输出文本 */
    std::string execCommand(const std::string& command, int timeoutMs);
    
    // 获取SFTP连接配置
    SftpConfig getSftpConfig() const {
        SftpConfig config;
        config.host = hostname;
        config.port = port;
        config.username = username;
        config.password = password;
        config.useKeyAuth = useKeyAuth;
        config.privateKeyData = privateKeyData;
        config.passphrase = passphrase;
        config.keepAliveInterval = keepAliveInterval;
        return config;
    }
    
    // SFTP相关方法
    bool initSftp();
    bool listDirectory(const std::string& path, std::function<void(const FileInfo&)> callback);
    bool uploadFile(int localFd, const std::string& remotePath, std::function<void(int)> progressCallback = nullptr);
    bool downloadFile(const std::string& remotePath, int localFd, std::function<void(off_t)> progressCallback);
    bool deleteFile(const std::string& path);
    bool createDirectory(const std::string& path);
    bool deleteDirectory(const std::string& path);
    bool rename(const std::string& oldPath, const std::string& newPath);
    
    // SFTP 文件属性操作
    bool setFileTime(const std::string& path, uint64_t mtime, uint64_t atime);
    
    // 获取文件信息
    bool getFileInfo(const std::string& path, FileInfo& info);
    
    // 设置文件权限
    bool setPermissions(const std::string& path, uint32_t permissions);
    
    // 辅助函数 - 为napiInterface.cpp提供
    std::string getPermissionString(uint32_t permissions);
    std::string getTimeString(uint64_t timestamp);
    
    // 端口转发相关方法 - 转发到portForward成员
    bool startLocalPortForwarding(int localPort, const std::string& targetHost, int targetPort, bool anyInterface = false);
    bool startRemotePortForwarding(int remotePort, const std::string& targetHost, int targetPort);
    bool startDynamicPortForwarding(int localPort, bool anyInterface = false);
    bool stopPortForwarding(int port, bool isRemote = false);
    bool isPortForwardingActive(int port, bool isRemote = false);
    std::vector<std::tuple<int, std::string, int, bool, bool>> listActivePortForwardings();
    
    // 设置日志
    bool setLogging(int fd, int logType, int existOperation, bool includeHeader = false, bool omitKnownPassword = false, bool omitSessionData = false) override;

    std::recursive_mutex& getLibssh2Mutex() { return libssh2Mutex; }
    LIBSSH2_SESSION* getInternalSession() { return session.get(); }

    /**
     * @brief 调整远程伪终端 (PTY) 的大小。
     *
     * @param width 新的终端宽度（字符数）。
     * @param height 新的终端高度（行数）。
     * @return 如果成功调整大小则返回 true，否则返回 false。
     */
    bool resizePty(int width, int height);

    /**
     * @brief 请求取消当前正在进行的 SFTP 文件传输。
     *
     * @return 如果成功发送取消请求则返回 true，否则返回 false (例如，SFTP 会话未初始化)。
     */
    bool cancelTransfer();

    // OSC7目录跟踪相关方法
    bool enableDirectoryTracking(bool enable);
    void setDirectoryChangeCallback(std::function<void(const std::string&)> callback);
    std::string getCurrentTrackedDirectory() const { return currentDirectory; }
    bool configureRemoteShell();

    // --- 修改：添加 override (实现基类的纯虚函数) ---
    bool resizeTerminal(int width, int height) override;

    // --- 新增：获取线程池指针 ---
    ThreadPool* getThreadPool() { return threadPool.get(); }
    // --------------------------
};

#endif //LIBSSH2_SSHSESSION_H
