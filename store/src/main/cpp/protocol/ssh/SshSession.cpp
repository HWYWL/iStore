#include "SshSession.h"
#include <numeric>
#include <sys/stat.h>
#include <sys/time.h>
#include "LogManager.h"
#include <fcntl.h> // Include for fcntl, F_GETFL, F_SETFL, O_NONBLOCK
#include <errno.h> // Likely needed for error checking with fcntl/sockets
#include <sys/socket.h> // For socket operations if not already included
#include <functional> // Ensure functional is included
#include <sys/types.h> // For off_t
#include <sstream>     // 添加 sstream 用于 URL 解码 (虽然当前实现可能不需要，但保留)
#include <string>      // 确保 string 包含
#include <atomic> // 需要包含 atomic 头文件
#include <netdb.h> // For getaddrinfo and gai_strerror

SshSession::SshSession()
    : session(nullptr, &libssh2_session_free),
      channelShell(nullptr, &libssh2_channel_free),
      knownHosts(nullptr, &libssh2_knownhost_free),
      sock(std::make_unique<libssh2_socket_t>(-1)), // 恢复初始化
      threadPool(std::make_unique<ThreadPool>(8)) // 恢复初始化 - Increase size to 8
{
    OH_LOG_INFO(LOG_APP, "SshSession构造函数: 初始化 (已移除 osc7Regex 初始化)");
    // 其他初始化代码...
}

// --- 新增 RAII Helper ---
namespace {
    class ShellConfigGuard {
        std::atomic<bool>& flag_;
    public:
        explicit ShellConfigGuard(std::atomic<bool>& flag) : flag_(flag) {
            OH_LOG_INFO(LOG_APP, "ShellConfigGuard: Setting config flag to true.");
            flag_.store(true);
        }
        ~ShellConfigGuard() {
            OH_LOG_INFO(LOG_APP, "ShellConfigGuard: Setting config flag to false.");
            flag_.store(false);
        }
        // Prevent copying/moving
        ShellConfigGuard(const ShellConfigGuard&) = delete;
        ShellConfigGuard& operator=(const ShellConfigGuard&) = delete;
        ShellConfigGuard(ShellConfigGuard&&) = delete;
        ShellConfigGuard& operator=(ShellConfigGuard&&) = delete;
    };
}
// ----------------------

void SshSession::runAsyncInThreadPool(std::function<void()> task) {
    std::thread([future = threadPool->enqueue(std::move(task))]() mutable {
        future.get();
    }).detach();
}

SshSession::~SshSession() {
    OH_LOG_INFO(LOG_APP, "SshSession destructor started.");

    // 首先停止所有线程
    OH_LOG_INFO(LOG_APP, "Setting stopThread flag in destructor.");
    stopThread.store(true);
    callBackDataCV.notify_one(); // 确保 callBackSendData 也能退出

    // 清理资源前加锁
    {
        std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
        OH_LOG_INFO(LOG_APP, "Acquired libssh2Mutex in destructor.");

        // --- 新增：在 session 之前清理 knownHosts ---
        if (knownHosts) {
             OH_LOG_INFO(LOG_APP, "Resetting knownHosts in destructor.");
             knownHosts.reset();
        }
        // -----------------------------------------

        // 重置并确保 SFTP 会话清理
        if (interactiveSftpSession) {
            OH_LOG_INFO(LOG_APP, "Resetting interactive SFTP session in destructor.");
            interactiveSftpSession.reset();
        }
        if (transferSftpSession) {
            OH_LOG_INFO(LOG_APP, "Resetting transfer SFTP session in destructor.");
            transferSftpSession.reset();
        }

        // 重置端口转发
        if (portForward) {
            portForward.reset();
        }

        // 关闭并清理 channelShell
        if (channelShell) {
            try {
                if (!libssh2_channel_eof(channelShell.get())) {
                    // 尝试正常关闭通道
                    int closeAttempts = 0;
                    while (closeAttempts < 3 &&
                           libssh2_channel_close(channelShell.get()) == LIBSSH2_ERROR_EAGAIN) {
                        waitSocket();
                        closeAttempts++;
                    }
                }
            } catch (...) {
                OH_LOG_ERROR(LOG_APP, "关闭Shell通道时出现异常");
            }
            channelShell.reset();
        }

        // 关闭SSH会话
        if (session) {
            try {
                int disconnectAttempts = 0;
                while (disconnectAttempts < 3 &&
                       libssh2_session_disconnect(session.get(), "Normal shutdown") == LIBSSH2_ERROR_EAGAIN) {
                    waitSocket();
                    disconnectAttempts++;
                }
            } catch (...) {
                OH_LOG_ERROR(LOG_APP, "断开SSH会话时发生异常");
            }
            session.reset(); // session 现在在 knownHosts 之后 reset
        }

        // 关闭SSH会话
        if (session) {
            try {
                int disconnectAttempts = 0;
                while (disconnectAttempts < 3 &&
                       libssh2_session_disconnect(session.get(), "Normal shutdown") == LIBSSH2_ERROR_EAGAIN) {
                    waitSocket();
                    disconnectAttempts++;
                }
            } catch (...) {
                OH_LOG_ERROR(LOG_APP, "断开SSH会话时出现异常");
            }
            session.reset(); // session 现在在 knownHosts 之后 reset
        }

         OH_LOG_INFO(LOG_APP, "Releasing libssh2Mutex in destructor.");
    } // 锁在这里释放

    // 关闭socket
    if (sock && *sock != LIBSSH2_INVALID_SOCKET) {
        try {
            shutdown(*sock, SHUT_RDWR);
            close(*sock);
        } catch (...) {
            OH_LOG_ERROR(LOG_APP, "关闭socket时出现异常");
        }
        *sock = LIBSSH2_INVALID_SOCKET;
    }

    // 等待线程池完成清理 - 注意：确保线程池在 keepAliveThread join 之后清理
     OH_LOG_INFO(LOG_APP, "Resetting threadPool in destructor.");
    threadPool.reset(); // 确保这个在 join 之后

    OH_LOG_INFO(LOG_APP, "SshSession destructor finished.");
}

int SshSession::waitSocket() {
    struct timeval timeout;
    int rc;
    fd_set fd;
    fd_set *writefd = NULL;
    fd_set *readfd = NULL;
    int dir;
    libssh2_socket_t current_sock = LIBSSH2_INVALID_SOCKET; // 本地变量存储socket

    timeout.tv_sec = 0;
    timeout.tv_usec = 50000; // 保持50ms超时

    FD_ZERO(&fd);

    // --- 在锁内获取必要的共享信息 ---
    {
        std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
        if (!sock || *sock == LIBSSH2_INVALID_SOCKET) {
            OH_LOG_ERROR(LOG_APP, "waitSocket: Invalid socket descriptor inside lock.");
            return -1; // Socket无效
        }
        current_sock = *sock; // 复制 socket descriptor 到本地变量

        if (!session) {
            OH_LOG_ERROR(LOG_APP, "waitSocket: Invalid session pointer inside lock.");
            return -1; // Session 无效
        }
        dir = libssh2_session_block_directions(session.get()); // 获取方向
    }
    // --- 锁已释放 ---

    // 检查 socket descriptor 是否有效（在锁外检查本地副本）
    if (current_sock == LIBSSH2_INVALID_SOCKET) {
        OH_LOG_ERROR(LOG_APP, "waitSocket: Socket descriptor became invalid after lock release.");
        return -1;
    }

    // --- 设置 fd_set (不需要锁) ---
    FD_SET(current_sock, &fd);

    if(dir & LIBSSH2_SESSION_BLOCK_INBOUND)
        readfd = &fd;

    if(dir & LIBSSH2_SESSION_BLOCK_OUTBOUND)
        writefd = &fd;
    // ---------------------------

    // --- 调用 select (不需要锁) ---
    // OH_LOG_DEBUG(LOG_APP, "waitSocket: Calling select (socket=%d, read=%d, write=%d)", current_sock, readfd != NULL, writefd != NULL); // Optional debug log
    rc = select((int)(current_sock + 1), readfd, writefd, NULL, &timeout);
    // OH_LOG_DEBUG(LOG_APP, "waitSocket: select returned %d", rc); // Optional debug log
    // ---------------------------

    // 检查 select 错误
    if (rc < 0) {
        int select_errno = errno;
        OH_LOG_ERROR(LOG_APP, "waitSocket: select error %{public}d (%{public}s)", select_errno, strerror(select_errno));
    }

    return rc;
}

bool SshSession::openConnect(const std::string& napiInput) {

    uint32_t hostaddr {};
    int ret = 0;
    string userAuthList {};

    SessionAnalyse* SessionAnalyseHandle = encapsulateSSHFromJson(napiInput);
    if (SessionAnalyseHandle == NULL) {
        OH_LOG_INFO(LOG_APP, "Failed to parse JSON input.");
        return false;
    }

    // 保存认证信息到成员变量，用于SFTP连接
    if (SessionAnalyseHandle->hostName) {
        hostname = SessionAnalyseHandle->hostName;
    } else {
        OH_LOG_ERROR(LOG_APP, "主机名为空");
        return false;
    }

    port = SessionAnalyseHandle->port;

    if (SessionAnalyseHandle->userName) {
        username = SessionAnalyseHandle->userName;
    } else {
        OH_LOG_ERROR(LOG_APP, "用户名为空");
        return false;
    }

    if (SessionAnalyseHandle->password) {
        password = SessionAnalyseHandle->password;
    }

    useKeyAuth = (SessionAnalyseHandle->authType == AUTH_PUBLICKEY);
    if (useKeyAuth) {
        privateKeyPath = ""; // 不再使用路径
        this->privateKeyData = ""; // 初始化
        if (SessionAnalyseHandle->password) {
            passphrase = SessionAnalyseHandle->password;
        }
    }

    // 获取保活参数
    keepAliveInterval = SessionAnalyseHandle->keepAlive;
    if (keepAliveInterval == 0) {
        keepAliveInterval = 60; // 默认值为60秒
        OH_LOG_INFO(LOG_APP, "保活间隔为0，使用默认值: %{public}d秒", keepAliveInterval);
    }

    OH_LOG_INFO(LOG_APP, "SSH连接配置: %{public}s@%{public}s:%{public}d, 保活间隔: %{public}d秒",
               username.c_str(), hostname.c_str(), port, keepAliveInterval);

    ret = libssh2_init(0);
    if (ret) {
        OH_LOG_INFO(LOG_APP, "libssh2 initialization failed (%{public}d)", ret);
        return false;
    }

    // --- Socket 创建移到这里之后 ---
    // sock = std::make_unique<libssh2_socket_t>(socket(AF_INET, SOCK_STREAM, 0));
    // if (*sock.get() == LIBSSH2_INVALID_SOCKET) {
    //    OH_LOG_INFO(LOG_APP, "failed to create socket.");
    //    return false;
    // }

    OH_LOG_INFO(LOG_APP, "准备解析的主机名/IP: '%{public}s'", SessionAnalyseHandle->hostName);

    struct sockaddr_storage addr;
    memset(&addr, 0, sizeof(addr));
    socklen_t addr_len = 0;
    int pton_ret = 0; // 用于存储 inet_pton 的返回值
    bool parsedAsIp = false;

    // 先尝试将输入作为 IPv4/IPv6 字面量解析
    pton_ret = inet_pton(AF_INET, SessionAnalyseHandle->hostName,
                         &(((struct sockaddr_in *)&addr)->sin_addr));
    if (pton_ret == 1) {
        OH_LOG_INFO(LOG_APP, "地址被识别为 IPv4");
        struct sockaddr_in *sin = (struct sockaddr_in *)&addr;
        sin->sin_family = AF_INET;
        sin->sin_port = htons(SessionAnalyseHandle->port);
        addr_len = sizeof(struct sockaddr_in);
        parsedAsIp = true;
    } else {
        if (pton_ret == -1) {
            OH_LOG_ERROR(LOG_APP, "inet_pton(AF_INET) 失败: errno=%{public}d (%{public}s)", errno, strerror(errno));
        }

        pton_ret = inet_pton(AF_INET6, SessionAnalyseHandle->hostName,
                             &(((struct sockaddr_in6 *)&addr)->sin6_addr));
        if (pton_ret == 1) {
            OH_LOG_INFO(LOG_APP, "地址被识别为 IPv6");
            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)&addr;
            sin6->sin6_family = AF_INET6;
            sin6->sin6_port = htons(SessionAnalyseHandle->port);
            addr_len = sizeof(struct sockaddr_in6);
            parsedAsIp = true;
        } else {
            if (pton_ret == -1) {
                OH_LOG_ERROR(LOG_APP, "inet_pton(AF_INET6) 失败: errno=%{public}d (%{public}s)", errno, strerror(errno));
            } else {
                OH_LOG_INFO(LOG_APP,
                            "inet_pton 未将 '%{public}s' 识别为 IPv4/IPv6 字面量，尝试作为域名解析",
                            SessionAnalyseHandle->hostName);
            }
        }
    }

    // 如果既不是合法 IPv4 也不是合法 IPv6，则按域名解析
    if (!parsedAsIp) {
        struct addrinfo hints;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC; // 允许 IPv4 或 IPv6
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_protocol = IPPROTO_TCP;

        struct addrinfo* result = nullptr;
        std::string portStr = std::to_string(SessionAnalyseHandle->port);

        int gaiRet = getaddrinfo(SessionAnalyseHandle->hostName, portStr.c_str(), &hints, &result);
        if (gaiRet != 0) {
            OH_LOG_ERROR(LOG_APP, "getaddrinfo 解析域名失败: %{public}s", gai_strerror(gaiRet));
            return false;
        }

        bool foundAddr = false;
        for (struct addrinfo* ptr = result; ptr != nullptr; ptr = ptr->ai_next) {
            if (ptr->ai_family == AF_INET || ptr->ai_family == AF_INET6) {
                if (ptr->ai_addrlen <= sizeof(addr)) {
                    memcpy(&addr, ptr->ai_addr, ptr->ai_addrlen);
                    addr_len = static_cast<socklen_t>(ptr->ai_addrlen);
                    OH_LOG_INFO(LOG_APP, "域名解析成功，使用地址族 %{public}d", ptr->ai_family);
                    foundAddr = true;
                    break;
                }
            }
        }

        freeaddrinfo(result);

        if (!foundAddr || addr_len == 0) {
            OH_LOG_ERROR(LOG_APP, "getaddrinfo 未返回可用的 IPv4/IPv6 地址");
            return false;
        }
    } else if (addr_len == 0) {
        // 理论上不会发生，但为了安全性保留检查
        OH_LOG_ERROR(LOG_APP, "内部错误：地址解析后 addr_len 仍为 0");
        return false;
    }

    // --- 在确定地址族后创建 Socket ---
    OH_LOG_INFO(LOG_APP, "使用地址族 %{public}d 创建套接字", addr.ss_family);
    sock = std::make_unique<libssh2_socket_t>(socket(addr.ss_family, SOCK_STREAM, 0));
    if (*sock.get() == LIBSSH2_INVALID_SOCKET) {
        OH_LOG_ERROR(LOG_APP, "创建套接字失败: errno=%{public}d (%{public}s)", errno, strerror(errno));
        libssh2_exit(); // 清理 libssh2
        return false;
    }
    OH_LOG_INFO(LOG_APP, "套接字创建成功 (fd=%{public}d)", *sock.get());

    int retryCount = 0;
    const int maxRetries = 3;
    const int connectTimeout = 1;

    int flags = fcntl(*sock.get(), F_GETFL, 0);

    fcntl(*sock.get(), F_SETFL, flags | O_NONBLOCK);

    bool connected = false;

    // --- 修改非阻塞连接逻辑 ---
    OH_LOG_INFO(LOG_APP, "发起非阻塞连接...");
    int connect_ret = connect(*sock.get(), (struct sockaddr *)&addr, addr_len);

    if (connect_ret == 0) {
        // 立即连接成功 (虽然对于非阻塞不常见)
        OH_LOG_INFO(LOG_APP, "连接立即成功");
        connected = true;
        fcntl(*sock.get(), F_SETFL, flags); // 恢复阻塞模式
    } else if (errno == EINPROGRESS) {
        OH_LOG_INFO(LOG_APP, "连接正在进行中 (EINPROGRESS)，进入 select 等待循环 (最多 %{public}d 次，每次 %{public}d 秒)", maxRetries, connectTimeout);
        while (retryCount < maxRetries) {
            retryCount++;
            fd_set writefds;
            FD_ZERO(&writefds);
            FD_SET(*sock.get(), &writefds);

            // readfds 和 exceptfds 设为 NULL，我们只关心写就绪（连接完成）
            fd_set readfds = writefds; // 也可以同时检查读和错误
            fd_set exceptfds = writefds;

            struct timeval timeout;
            timeout.tv_sec = connectTimeout;
            timeout.tv_usec = 0;

            OH_LOG_INFO(LOG_APP, "等待 select (第 %{public}d 次尝试)...", retryCount);
            int select_ret = select(*sock.get() + 1, &readfds, &writefds, &exceptfds, &timeout);

            if (select_ret > 0) {
                // select 返回 > 0 表示套接字状态改变
                int error = 0;
                socklen_t len = sizeof(error);
                // 检查套接字错误状态
                if (getsockopt(*sock.get(), SOL_SOCKET, SO_ERROR, &error, &len) == 0) {
                    if (error == 0) {
                        // 没有错误，连接成功
                        OH_LOG_INFO(LOG_APP, "select 报告连接成功 (SO_ERROR=0)");
                        connected = true;
                        fcntl(*sock.get(), F_SETFL, flags); // 恢复阻塞模式
                        break; // 成功，退出等待循环
                    } else {
                        // 连接过程中发生错误
                        OH_LOG_ERROR(LOG_APP, "select 报告连接失败 (SO_ERROR=%{public}d): %{public}s", error, strerror(error));
                        errno = error; // 设置 errno 以便外部检查
                        // 不再重试，直接跳出循环去处理失败
                        break;
                    }
                } else {
                     OH_LOG_ERROR(LOG_APP, "getsockopt(SO_ERROR) 失败: %{public}s", strerror(errno));
                     // 不再重试，直接跳出循环去处理失败
                     break;
                }
            } else if (select_ret == 0) {
                // select 超时
                OH_LOG_INFO(LOG_APP, "select 等待超时 (第 %{public}d 次尝试)", retryCount);
                // 继续循环，直到达到 maxRetries
            } else { // select_ret < 0
                // select 本身出错
                OH_LOG_ERROR(LOG_APP, "select 失败: %{public}s", strerror(errno));
                // 不再重试，直接跳出循环去处理失败
                break;
            }
        } // while (retryCount < maxRetries)
    } else {
        // 初始 connect 调用直接失败 (非 EINPROGRESS)
        OH_LOG_ERROR(LOG_APP, "初始 connect 调用失败: %{public}s", strerror(errno));
        // connected 保持 false
    }
    // --------------------------

    if (!connected) {
        OH_LOG_INFO(LOG_APP, "Failed to connect after %{public}d attempts", maxRetries);

        if (sock && *sock != LIBSSH2_INVALID_SOCKET) {
            close(*sock);
            *sock = LIBSSH2_INVALID_SOCKET;
        }

        libssh2_exit();

        return false;
    }

    session.reset(libssh2_session_init());
    if (!session) {
        OH_LOG_INFO(LOG_APP, "Could not initialize SSH session.");
        return false;
    }

    libssh2_trace(session.get(), 0);

    knownHosts.reset(libssh2_knownhost_init(session.get()));
    if (!knownHosts) {
        OH_LOG_INFO(LOG_APP, "Failed to initialize known hosts");
        return false;
    }

    const int handshakeTimeout = 5;
    auto handshakeStartTime = std::chrono::steady_clock::now();
    while ((ret = libssh2_session_handshake(session.get(), *sock)) == LIBSSH2_ERROR_EAGAIN) {
        auto elapsedTime = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - handshakeStartTime).count();
        if (elapsedTime > handshakeTimeout) {
            OH_LOG_INFO(LOG_APP, "Session handshake failed due to timeout");
            return false;
        }
        if (waitSocket() <= 0) {
            OH_LOG_INFO(LOG_APP, "Session handshake failed due to timeout");
            return false;
        }
    }

    if (ret != 0) {
        char* hsErr = nullptr;
        int hsErrLen = 0;
        libssh2_session_last_error(session.get(), &hsErr, &hsErrLen, 0);
        OH_LOG_ERROR(LOG_APP, "SSH 握手失败: code=%{public}d (%{public}s)", ret, hsErr ? hsErr : "N/A");
        return false;
    }

    // libssh2_userauth_list 在会话异常或服务器未返回认证方式时返回 NULL，
    // 直接赋值给 std::string 会触发 strlen(nullptr) 崩溃（ImmortalWrt/dropbear 上复现）
    const char* authMethods = libssh2_userauth_list(session.get(), SessionAnalyseHandle->userName,
                                                    (unsigned int)strlen(SessionAnalyseHandle->userName));
    if (authMethods == nullptr) {
        int authErr = libssh2_session_last_errno(session.get());
        OH_LOG_ERROR(LOG_APP, "获取认证方式失败: libssh2 errno=%{public}d", authErr);
        return false;
    }
    userAuthList = authMethods;
    if (!userAuthList.empty()) {
        // 根据前端配置的认证方式选择认证方法
        if (SessionAnalyseHandle->authType == AUTH_PASSWORD) {
            if (userAuthList.find("password") == std::string::npos) {
                OH_LOG_INFO(LOG_APP, "Password authentication not supported by server");
                return false;
            }

            if (strlen(SessionAnalyseHandle->password) != 0) {
                const int authTimeout = 5;
                auto authStartTime = std::chrono::steady_clock::now();
                while ((ret = libssh2_userauth_password(session.get(),
                    SessionAnalyseHandle->userName,
                    SessionAnalyseHandle->password)) == LIBSSH2_ERROR_EAGAIN) {
                    auto elapsedTime = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - authStartTime).count();
                    if (elapsedTime > authTimeout) {
                        OH_LOG_INFO(LOG_APP, "Authentication timeout");
                        return false;
                    }
                    if (waitSocket() <= 0) {
                        OH_LOG_INFO(LOG_APP, "Authentication timeout");
                        return false;
                    }
                }

                if (ret != 0) {
                    OH_LOG_INFO(LOG_APP, "Password authentication failed with error code: %{public}d", ret);
                    return false;
                }
            }
        }
        else if (SessionAnalyseHandle->authType == AUTH_PUBLICKEY) {
            if (userAuthList.find("publickey") == std::string::npos) {
                OH_LOG_INFO(LOG_APP, "Public key authentication not supported by server");
                return false;
            }

            // 使用前端提供的私钥文件描述符进行认证
            if (SessionAnalyseHandle->privateKeyFd < 0) {
                OH_LOG_INFO(LOG_APP, "Invalid private key file descriptor");
                return false;
            }

            // 从文件描述符读取私钥内容
            std::vector<char> keyDataVec;
            char buffer[READ_MAX_BUFF_SIZE];
            ssize_t bytesRead;
            while ((bytesRead = read(SessionAnalyseHandle->privateKeyFd, buffer, sizeof(buffer))) > 0) {
                keyDataVec.insert(keyDataVec.end(), buffer, buffer + bytesRead);
            }

            if (keyDataVec.empty()) {
                OH_LOG_INFO(LOG_APP, "Failed to read private key data");
                return false;
            }
            // 将读取到的密钥数据存储到成员变量中
            this->privateKeyData = std::string(keyDataVec.begin(), keyDataVec.end());

            // 使用内存中的私钥数据进行认证
            if (libssh2_userauth_publickey_frommemory(session.get(),
                SessionAnalyseHandle->userName,
                strlen(SessionAnalyseHandle->userName),
                nullptr, 0,  // 公钥数据可以为空，因为服务器会从私钥中提取
                this->privateKeyData.data(), // 使用成员变量
                this->privateKeyData.size(), // 使用成员变量
                SessionAnalyseHandle->password)) {  // 如果私钥有密码保护，使用提供的密码
                OH_LOG_INFO(LOG_APP, "Authentication by public key failed");
                // --- 添加详细错误日志 ---
                int last_errno = libssh2_session_last_errno(session.get());
                char *errmsg = nullptr;
                int errmsg_len = 0;
                libssh2_session_last_error(session.get(), &errmsg, &errmsg_len, 0);
                OH_LOG_ERROR(LOG_APP, "Public key auth failed with libssh2 error code: %{public}d, message: %{public}s", last_errno, errmsg ? errmsg : "N/A");
                // -----------------------
                return false;
            }
            OH_LOG_INFO(LOG_APP, "Authentication by public key succeeded");
        }
        else {
            OH_LOG_INFO(LOG_APP, "Unsupported authentication type");
            return false;
        }
    }
    else {
        OH_LOG_INFO(LOG_APP, "Failed to get authentication methods");
        return false;
    }

    // --- 改用 channel exec 模式（不创建交互 shell/pty）---
    // OpenWrt dropbear 对交互 shell+pty 兼容差：连接建立后 2~3 秒主动关闭（socket EOF）
    // channel exec 模式：每次命令独立 channel，dropbear 支持良好且有 EOF 立即返回
    // （channelShell 保持空，receiveData 线程会因无 channel 退出，但 exec 模式不依赖它）
    OH_LOG_INFO(LOG_APP, "openConnect: Using channel exec mode (no interactive shell).");
    channelShell.reset();

    string m_termType = "xterm-256color";

    // 终端尺寸常量
    const int TERM_WIDTH = 80;      // 终端宽度（字符数）
    const int TERM_HEIGHT = 24;     // 终端高度（行数）
    const int TERM_WIDTH_PX = 0;    // 终端像素宽度（0表示使用默认值）
    const int TERM_HEIGHT_PX = 0;   // 终端像素高度（0表示使用默认值）

    // 禁用终端回显，避免双重换行问题
    // 注意：SSH终端模式是按照POSIX规范定义的
    // ECHO (53) - 是否回显输入字符
    // ECHOCTL (90) - 是否回显控制字符
    // ECHONL (91) - 是否回显换行符
    typedef struct {
        char opcode;
        int value;
    } LIBSSH2_TERM_MODE;

    LIBSSH2_TERM_MODE modes[4] = {
        {53, 0},  // Disable ECHO
        {90, 0},  // Disable ECHOCTL
        {91, 0},  // Disable ECHONL
        {0, 0}    // Terminal
    };

    // 设置终端模式以禁用回显，确保在所有服务器环境下都能正确控制回显
    while((ret = libssh2_channel_request_pty_ex(channelShell.get(), m_termType.c_str(), m_termType.length(),
                                            (char*)modes, sizeof(modes), // 传递实际的终端模式设置
                                            TERM_WIDTH, TERM_HEIGHT, TERM_WIDTH_PX, TERM_HEIGHT_PX)) == LIBSSH2_ERROR_EAGAIN) {
        waitSocket();
    }

    // 初始化SSH接收数据线程
    stopThread.store(false);
    status = SessionStatus::CONNECTED;
    statusChange.store(true);

    // --- Xshell 极简模式：不启动读线程/keepalive 线程/同步 SFTP/端口转发 ---
    // 每次命令走 channel exec（独立 channel，EOF 立即返回），dropbear 兼容性好
    // SFTP 由文件管理按需 initSftp（独立连接）
    OH_LOG_INFO(LOG_APP, "[Session %{public}d] openConnect successful (exec mode).", sessionId);
    return true;
}


bool SshSession::disconnect() {
    OH_LOG_INFO(LOG_APP, "SshSession::disconnect called."); // 添加日志以便追踪

    { // 清理缓冲区
        std::lock_guard<std::mutex> lock(bufferMutex);
        initialBuffer.clear();
    }

    if(status != SessionStatus::CONNECTED) {
        OH_LOG_INFO(LOG_APP, "Attempting to disconnect, but session is not in CONNECTED state.");
        return false;
    }

    OH_LOG_INFO(LOG_APP, "Setting stopThread flag to true.");
    stopThread.store(true);
    callBackDataCV.notify_one(); // 唤醒 callBackSendData 线程

    // 标记状态为正在断开连接
    {
        std::lock_guard<std::mutex> lock(statusMutex);
        status = SessionStatus::DISCONNECTING;
    }

    bool success = true;

    // 使用锁保护资源访问
    {
        std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);

        // --- 新增：在断开 SSH 之前清理 SFTP 会话 ---
        OH_LOG_INFO(LOG_APP, "Disconnect: Resetting SFTP sessions.");
        if (interactiveSftpSession) {
            interactiveSftpSession.reset();
        }
        if (transferSftpSession) {
            transferSftpSession.reset();
        }

        // 关闭channelShell
        if(channelShell) {
            try {
                int attempts = 0;
                int result = LIBSSH2_ERROR_EAGAIN;
                while(attempts < 3 && result == LIBSSH2_ERROR_EAGAIN) {
                    result = libssh2_channel_close(channelShell.get());
                    if(result == LIBSSH2_ERROR_EAGAIN)
                        waitSocket();
                    attempts++;
                }

                if(result != 0 && result != LIBSSH2_ERROR_EAGAIN) {
                    OH_LOG_ERROR(LOG_APP, "关闭Shell通道失败: %{public}d", result);
                }
            } catch(...) {
                OH_LOG_ERROR(LOG_APP, "关闭Shell通道时发生异常");
            }
        }

        // 断开SSH会话
        if(session) {
            try {
                int attempts = 0;
                int result = LIBSSH2_ERROR_EAGAIN;
                while(attempts < 3 && result == LIBSSH2_ERROR_EAGAIN) {
                    result = libssh2_session_disconnect(session.get(), "Normal shutdown");
                    if(result == LIBSSH2_ERROR_EAGAIN)
                        waitSocket();
                    attempts++;
                }

                if(result != 0 && result != LIBSSH2_ERROR_EAGAIN) {
                    OH_LOG_ERROR(LOG_APP, "断开SSH会话失败: %{public}d", result);
                }
            } catch(...) {
                OH_LOG_ERROR(LOG_APP, "断开SSH会话时发生异常");
            }
        }
    }

    // 更新状态为已断开连接
    {
        std::lock_guard<std::mutex> lock(statusMutex);
        status = SessionStatus::DISCONNECTED;
    }

    // 禁用日志管理器并刷新尾行（如有）
    try {
        logManager.disable();
        logManagerInitialized.store(false);
    } catch (...) {
        OH_LOG_WARN(LOG_APP, "SshSession::disconnect: exception while disabling LogManager");
    }

    // 发送会话关闭通知
    pendingCallData("SSH连接已断开", true);

    OH_LOG_INFO(LOG_APP, "SshSession::disconnect returning: %{public}d", success); // 添加日志：记录最终返回值
    return success;
}

std::string SshSession::execCommand(const std::string& command, int timeoutMs) {
    // Xshell 同款：纯阻塞同步模式（session 默认阻塞，channel_open/exec/read 都阻塞等待结果）
    OH_LOG_INFO(LOG_APP, "execCommand: entering, cmd len=%zu", command.length());
    if (!session) {
        return "SESSION_INVALID";
    }

    LIBSSH2_CHANNEL* ch = libssh2_channel_open_session(session.get());
    if (!ch) {
        OH_LOG_ERROR(LOG_APP, "execCommand: channel open failed, errno=%d", libssh2_session_last_errno(session.get()));
        return "CHANNEL_OPEN_FAILED";
    }
    OH_LOG_INFO(LOG_APP, "execCommand: channel opened.");

    int rc = libssh2_channel_exec(ch, command.c_str());
    if (rc != 0) {
        OH_LOG_ERROR(LOG_APP, "execCommand: exec failed rc=%d", rc);
        libssh2_channel_free(ch);
        return "EXEC_FAILED";
    }
    OH_LOG_INFO(LOG_APP, "execCommand: exec sent, reading output...");

    std::string output;
    char buf[4096];
    int nbytes;
    // 阻塞读 stdout 直到 EOF（Xshell 同款）
    while ((nbytes = libssh2_channel_read(ch, buf, sizeof(buf))) > 0) {
        output.append(buf, nbytes);
    }
    // 阻塞读 stderr
    while ((nbytes = libssh2_channel_read_stderr(ch, buf, sizeof(buf))) > 0) {
        output.append(buf, nbytes);
    }
    int exitStatus = libssh2_channel_get_exit_status(ch);
    OH_LOG_INFO(LOG_APP, "execCommand: done, exit=%d output=%zu bytes", exitStatus, output.length());

    libssh2_channel_free(ch);
    return output;
}

bool SshSession::sendData(const std::string& command) {
    // 兼容旧接口：内部走 execCommand（输出经 pendingCallData 回传）
    std::string out = execCommand(command, 15000);
    if (!out.empty() && out != "SESSION_INVALID" && out != "CHANNEL_OPEN_FAILED" && out != "EXEC_FAILED") {
        pendingCallData(out, false);
        return true;
    }
    return !out.empty() && out != "SESSION_INVALID" && out != "CHANNEL_OPEN_FAILED" && out != "EXEC_FAILED";
}

void SshSession::receiveData() {
    const size_t threadId = std::hash<std::thread::id>{}(std::this_thread::get_id());
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData 开始执行 (v13 - 增加初始化日志)", threadId, sessionId); // 添加 sessionId
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Initial logManagerInitialized = %{public}d", threadId, sessionId, logManagerInitialized.load()); // 添加日志：记录初始 logManagerInitialized

    // --- Define the lines/strings to filter out ---
    // NOTE: Adjust these strings precisely based on what you see in YOUR terminal
    const std::vector<std::string> lines_to_filter = {
        "# Configuring terminal for directory tracking (ignore if echoed)", // The starting comment
        "stty -echo",                                                      // The stty command itself (might appear after prompt)
        "# Configuration complete",                                        // The ending comment
        "> > > > >"                                                        // Add the occasional extra prompt line
    };
    // ---------------------------------------------

    char buffer[READ_MAX_BUFF_SIZE];
    ssize_t n = 0;
    int read_errno = 0;
    int ws_rc = 0;
    bool should_exit = false;
    int readErrorCount = 0;

    // --- Initial non-blocking read (unchanged from previous version) ---
    bool initial_data_processed = false;
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Attempting initial non-blocking read...", threadId);
    {
        std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
        if (session && channelShell) {
            libssh2_channel_set_blocking(channelShell.get(), 0);
            n = libssh2_channel_read(channelShell.get(), buffer, sizeof(buffer) - 1);
            libssh2_channel_set_blocking(channelShell.get(), 1);

            // --- 添加详细的首次读取日志 ---
            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Initial read result n = %zd", threadId, sessionId, n);
            // -----------------------------

            if (n > 0) {
                buffer[n] = '\0';
                std::string initial_received_data(buffer, n);
                OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Initial data received (first 50 chars): %{public}.50s", threadId, sessionId, initial_received_data.c_str()); // 打印部分初始数据

                // --- 新增：检查是否在配置 Shell ---
                if (isConfiguringShell.load()) {
                    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Discarding initial data received during shell configuration (%zd bytes).", threadId, sessionId, n);
                    initial_data_processed = true; // 标记为已处理，避免后续逻辑误判
                    // 直接跳出 if (n > 0) 的处理，因为首次读取只执行一次
                } else {
                    // --- 原始逻辑（在 else 块中） ---
                    // --- Filtering Check for Initial Read ---
                    bool initial_should_filter = false;
                    // Simple check: does the received block contain any filter string?
                    for (const auto& filter_str : lines_to_filter) {
                        // Check if the data CONTAINS the filter string. Adjust if needed (e.g., check start/end)
                        if (initial_received_data.find(filter_str) != std::string::npos) {
                            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Initial read data contains filter string: '%s'. Filtering out.", threadId, sessionId, filter_str.c_str());
                            initial_should_filter = true;
                            break;
                        }
                    }
                    // --------------------------------------

                    if (!initial_should_filter) {
                        OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Initial read successful (%zd bytes). Buffering/Processing...", threadId, sessionId, n);
                        if (followTerminalDirectory) {
                            parseOSC7Sequence(initial_received_data); // Use the string version
                        }
                        if (!logManagerInitialized.load()) {
                            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: logManager not initialized, appending to initialBuffer.", threadId, sessionId); // 记录缓冲行为
                            std::lock_guard<std::mutex> bufferLock(bufferMutex);
                            if (initialBuffer.length() + n < MAX_INITIAL_BUFFER_SIZE) {
                                initialBuffer.append(buffer, n);
                                OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Appended initial data to buffer. Buffer size: %zu", threadId, sessionId, initialBuffer.length());
                            } else {
                                OH_LOG_WARN(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Initial buffer full, dropping initial data.", threadId, sessionId);
                            }
                        } else {
                            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: logManager initialized, writing to logManager.", threadId, sessionId); // 记录写日志行为
                            logManager.writeLog(buffer, n);
                        }
                        OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Calling pendingCallData for initial data.", threadId, sessionId); // 记录调用回调
                        pendingCallData(buffer, false); // Send to UI
                        {
                            std::lock_guard<std::mutex> status_lock(statusMutex);
                            statusChange = true;
                        }
                        initial_data_processed = true;
                    } else {
                         OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] receiveData: Initial read data was filtered out.", threadId, sessionId);
                         // Still mark as processed so we don't treat it as an error/EOF
                         initial_data_processed = true;
                    }
                    // --- 原始逻辑结束 ---
                } // --- 新增 else 块结束 ---

            } else if (n == 0) {
                 OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Initial read returned 0 (EOF).", threadId);
                 should_exit = true;
            } else {
                 read_errno = libssh2_session_last_errno(session.get());
                 // 初次读无数据/瞬时错误属正常（会话刚建立，可能无输出待读）
                 // 不标记退出——继续主循环，waitSocket 会等待真实数据
                 OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Initial read returned %{public}zd (errno=%{public}d), continuing to main loop.", threadId, n, read_errno);
            }
        } else {
            OH_LOG_WARN(LOG_APP, "[Thread %{public}zu] receiveData: Session/Channel invalid before initial read.", threadId);
            should_exit = true;
        }
    }
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Initial read attempt finished.", threadId);


    // --- 主接收循环 ---
    while(!stopThread.load() && !should_exit) {
        n = 0;
        ws_rc = 0;
        read_errno = 0;
        bool channel_valid = true;

        // 1. Check validity (unchanged)
        {
            std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
            if (!session || !channelShell) {
                OH_LOG_ERROR(LOG_APP, "[Thread %{public}zu] receiveData: 会话或通道已无效.", threadId);
                channel_valid = false;
                should_exit = true;
            }
        }
        if (!channel_valid) {
            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Channel invalid, breaking loop.", threadId);
            break;
        }

        // 2. Wait socket (unchanged)
        ws_rc = waitSocket();

        if (ws_rc < 0) {
            read_errno = errno;
            OH_LOG_ERROR(LOG_APP, "[Thread %{public}zu] receiveData: waitSocket error (%d: %s)，标记退出", threadId, read_errno, strerror(read_errno));
            should_exit = true;
        } else if (ws_rc > 0) {
            // 3. Attempt read (unchanged, includes try-catch)
            {
                std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
                try {
                    if (!channelShell) {
                         OH_LOG_WARN(LOG_APP, "[Thread %{public}zu] receiveData: channelShell became null before read attempt.", threadId);
                         n = -1; read_errno = -999;
                    } else {
                       // --- 设置为非阻塞读 ---
                       libssh2_channel_set_blocking(channelShell.get(), 0);
                       n = libssh2_channel_read(channelShell.get(), buffer, sizeof(buffer) - 1);
                       // --- 恢复阻塞模式 --- (即使出错也要恢复，或者后续逻辑依赖阻塞模式)
                       libssh2_channel_set_blocking(channelShell.get(), 1);

                       if (n < 0) {
                           read_errno = libssh2_session_last_errno(session.get());
                       }
                    }
                } catch (const std::exception& e) {
                    OH_LOG_ERROR(LOG_APP, "[Thread %{public}zu] receiveData: Exception during read: %{public}s", threadId, e.what());
                    n = -1; read_errno = -998;
                } catch (...) {
                    OH_LOG_ERROR(LOG_APP, "[Thread %{public}zu] receiveData: Unknown exception during read", threadId);
                    n = -1; read_errno = -997;
                }
            }

            // --- 4. Process read result (Filtering added here) ---
            if (n > 0) {
                // Successfully read data
                buffer[n] = '\0';
                std::string received_data(buffer, n); // Convert to string for filtering

                // --- 新增：检查是否在配置 Shell ---
                if (isConfiguringShell.load()) {
                    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Discarding data received during shell configuration (%zd bytes).", threadId, n);
                    continue; // 直接跳到下一次循环，丢弃此数据块
                }
                // -------------------------------

                // --- Filtering Check ---
                bool should_filter = false;
                 // Simple check: does the received block contain any filter string?
                 // More advanced: Check if the line *ends* with the filter string after removing prompt?
                for (const auto& filter_str : lines_to_filter) {
                    // Check if the data CONTAINS the filter string.
                    // You might need a more sophisticated check depending on your exact output.
                    // For example, checking if the line *ends* with `stty -echo` after stripping whitespace.
                    if (received_data.find(filter_str) != std::string::npos) {
                        OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Data contains filter string: '%s'. Filtering out.", threadId, filter_str.c_str());
                        should_filter = true;
                        break; // Found a match, no need to check others for this block
                    }
                }
                // ---------------------

                if (!should_filter) { // If data should NOT be filtered
                    // Original processing logic:
                    if (followTerminalDirectory) {
                        parseOSC7Sequence(received_data); // Use the string
                    }

                    if (!logManagerInitialized.load()) {
                        std::lock_guard<std::mutex> bufferLock(bufferMutex);
                         if (!logManagerInitialized.load()) {
                             if (initialBuffer.length() + n < MAX_INITIAL_BUFFER_SIZE) {
                                 initialBuffer.append(buffer, n);
                                 // OH_LOG_DEBUG(LOG_APP, "[Thread %{public}zu] receiveData: Appended data to buffer. Buffer size: %zu", threadId, initialBuffer.length());
                             } else {
                                  OH_LOG_WARN(LOG_APP, "[Thread %{public}zu] receiveData: Initial buffer full, dropping data.", threadId);
                             }
                         } else {
                            logManager.writeLog(buffer, n);
                         }
                    } else {
                        logManager.writeLog(buffer, n);
                    }

                    pendingCallData(buffer, false); // Send to UI

                    { // Update status (unchanged)
                        std::lock_guard<std::mutex> status_lock(statusMutex);
                        statusChange = true;
                    }
                } else {
                    // Data was filtered out, do nothing (or just log)
                    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Data filtered out.", threadId);
                }
                // -------------------------------------------------
                continue; // Continue loop immediately after processing/filtering
            } else if (n == 0) {
                // EOF (unchanged)
                OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Read 0 bytes -> Channel EOF detected，标记退出", threadId);
                should_exit = true;
            } else { // n < 0
                // Read error：瞬时错误不立即断开（dropbear 首包延迟常见），连续失败才退出
                if (read_errno != LIBSSH2_ERROR_EAGAIN) {
                    OH_LOG_ERROR(LOG_APP, "[Thread %{public}zu] receiveData: Non-EAGAIN read error (errno=%{public}d), retrying...", threadId, read_errno);
                    readErrorCount++;
                    if (readErrorCount > 20) {
                        should_exit = true;
                    }
                    std::this_thread::sleep_for(std::chrono::milliseconds(100));
                } else {
                    // EAGAIN (unchanged)
                    std::this_thread::sleep_for(std::chrono::milliseconds(20));
                }
            }
        } else { // ws_rc == 0
            // waitSocket timeout (unchanged)
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

    } // while loop end

    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData 循环最终结束 (should_exit=%d)", threadId, should_exit);

    // --- 5. Post-loop processing (unchanged) ---
    bool notify_needed = false;
    bool cleanup_needed = false; // <<< Add a flag to trigger cleanup
    {
        std::lock_guard<std::mutex> lock(statusMutex);
        if (status == SessionStatus::CONNECTED) {
            if (should_exit && !stopThread.load()) {
               status = SessionStatus::DISCONNECTED;
               notify_needed = true;
               cleanup_needed = true; // <<< Mark for cleanup
               OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData 设置状态为 DISCONNECTED，标记需要清理", threadId);
            } else if (stopThread.load()) {
               OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData 循环因外部停止而结束.", threadId);
               // External stop via disconnect() or destructor will handle cleanup
            }
        }
    }

    // --- Perform cleanup if marked ---
    if (cleanup_needed) {
        OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Triggering cleanup for SFTP and Port Forward due to unexpected disconnect...", threadId);
        // Use recursive mutex as these might call back into libssh2 functions
        std::lock_guard<std::recursive_mutex> sshLock(libssh2Mutex);
        try {
            // Reset SFTP sessions (calls their destructors)
            if (interactiveSftpSession) {
                OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Resetting interactive SFTP session.", threadId);
                interactiveSftpSession.reset();
            }
            if (transferSftpSession) {
                OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Resetting transfer SFTP session.", threadId);
                transferSftpSession.reset();
            }
            // Disconnect Port Forwarding session
            if (portForward) {
                 OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: Calling portForward->disconnectSession().", threadId);
                 portForward->disconnectSession(); // Call the explicit disconnect
                 // We don't reset portForward here, its destructor handles full cleanup later
            }
            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu] receiveData: SFTP and Port Forward cleanup calls completed.", threadId);
        } catch (const std::exception& e) {
             OH_LOG_ERROR(LOG_APP, "[Thread %{public}zu] receiveData: Exception during SFTP/PF cleanup: %{public}s", threadId, e.what());
        } catch (...) {
             OH_LOG_ERROR(LOG_APP, "[Thread %{public}zu] receiveData: Unknown exception during SFTP/PF cleanup", threadId);
        }
    }
    // --------------------------------

    if (notify_needed) {
        pendingCallData("Connection closed or error occurred in receive thread", true);
    }
}

void inline SshSession::pendingCallData(std::string data, bool status) {
    // --- 新增检查：如果正在配置Shell，则阻止回调 ---
    if (isConfiguringShell.load()) {
        OH_LOG_INFO(LOG_APP, "pendingCallData: Suppressing callback during shell configuration. Data length: %zu, Status: %d", data.length(), status);
        return; // 在配置期间阻止数据发送
    }
    // --------------------------------------------

    // 直接调用回调函数，避免使用队列缓冲，减少延迟
    if (dataCallback) {
        try {
            dataCallback(sessionId, data, status); // 添加sessionId参数
            return;
        } catch (const std::exception& e) {
            OH_LOG_ERROR(LOG_APP, "直接调用数据回调异常: %s", e.what());
            // 如果直接调用失败，退回到队列方式
        } catch (...) {
            OH_LOG_ERROR(LOG_APP, "直接调用数据回调未知异常");
            // 如果直接调用失败，退回到队列方式
        }
    }

    // 如果没有回调或回调失败，使用队列
    std::lock_guard<std::mutex> lock(callBackDataMutex);
    dataCallBackList.emplace_back(std::move(data), status);
    callBackDataCV.notify_one();
}


void SshSession::callBackSendData() {

    std::unique_lock<std::mutex> lock(callBackDataMutex);

    while (!stopThread.load()) {

        callBackDataCV.wait(lock, [this] {
            return !dataCallBackList.empty() || stopThread.load();
        });

        if (stopThread.load()) {
            break;
        }

        if (!dataCallBackList.empty() && dataCallback) {
            auto &front = dataCallBackList.front();
            std::string data = std::move(front.first);
            bool status = std::move(front.second);
            dataCallBackList.pop_front();
            lock.unlock();

            dataCallback(sessionId, data, status); // 添加sessionId参数

            lock.lock();
        }
    }
    OH_LOG_INFO(LOG_APP, "callBackSendData线程正常退出");
}

// --- 新增：keepAliveThread方法实现 ---
void SshSession::keepAliveThread() {
    const size_t threadId = std::hash<std::thread::id>{}(std::this_thread::get_id());
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] keepAliveThread 开始执行", threadId, sessionId);
    
    // 确保间隔大于0
    if (keepAliveInterval <= 0) {
        OH_LOG_ERROR(LOG_APP, "[Thread %{public}ld][Session %{public}d] keepAliveInterval 无效 (%d)，线程退出", 
                    threadId, sessionId, keepAliveInterval);
        return;
    }

    // 记录开始时间
    auto startTime = std::chrono::steady_clock::now();
    
    while (!stopThread.load()) {
        // 检查会话是否连接
        SessionStatus currentStatus;
        {
            std::lock_guard<std::mutex> lock(statusMutex);
            currentStatus = status;
        }
        
        if (currentStatus != SessionStatus::CONNECTED) {
            OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][Session %{public}d] 会话未连接，keepAliveThread 退出", 
                       threadId, sessionId);
            break;
        }
        
        // 定期发送 keepalive 消息
        int next_time = keepAliveInterval; // 默认值
        {
            std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
            if (session) {
                int rc = libssh2_keepalive_send(session.get(), &next_time);
                
                if (rc == 0) {
                    OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][Session %{public}d] Keepalive 消息已发送，下次发送时间: %{public}d秒后", 
                               threadId, sessionId, next_time);
                } else if (rc == LIBSSH2_ERROR_EAGAIN) {
                    // 发送缓冲区已满，这是正常的，稍后再试
                    OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][Session %{public}d] Keepalive 发送缓冲区已满 (EAGAIN)", 
                               threadId, sessionId);
                } else {
                    OH_LOG_ERROR(LOG_APP, "[Thread %{public}ld][Session %{public}d] Keepalive 发送失败，错误码: %{public}d", 
                                threadId, sessionId, rc);
                }
            } else {
                OH_LOG_ERROR(LOG_APP, "[Thread %{public}ld][Session %{public}d] 会话已失效，keepAliveThread 退出", 
                            threadId, sessionId);
                break;
            }
        }
        
        // 更新运行时间统计（可选）
        auto currentTime = std::chrono::steady_clock::now();
        auto elapsedSeconds = std::chrono::duration_cast<std::chrono::seconds>(
            currentTime - startTime).count();
        
        // 每5分钟记录一次日志（避免日志过多）
        if (elapsedSeconds % 300 == 0) {
            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] keepAliveThread 已运行 %{public}ld 秒", 
                       threadId, sessionId, (long)elapsedSeconds);
        }
        
        // 使用libssh2返回的next_time作为实际休眠时间
        int sleepTime = next_time;
        
        // 安全检查: 确保休眠时间合理
        if (sleepTime <= 0) {
            sleepTime = 1; // 至少休眠1秒
            OH_LOG_WARN(LOG_APP, "[Thread %{public}ld][Session %{public}d] 无效的next_time值(%{public}d)，使用最小值1秒", 
                       threadId, sessionId, next_time);
        } else if (sleepTime > keepAliveInterval) {
            sleepTime = keepAliveInterval; // 不超过配置的最大间隔
            OH_LOG_WARN(LOG_APP, "[Thread %{public}ld][Session %{public}d] next_time值(%{public}d)超过keepAliveInterval，使用%{public}d秒", 
                       threadId, sessionId, next_time, keepAliveInterval);
        }
        
        OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][Session %{public}d] keepAliveThread 将休眠 %{public}d 秒", 
                   threadId, sessionId, sleepTime);
        
        // 分段休眠，便于快速响应停止信号
        for (int i = 0; i < sleepTime && !stopThread.load(); i++) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }
    
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][Session %{public}d] keepAliveThread 正常退出", threadId, sessionId);
}
// --- 新增结束 ---

bool SshSession::initSftp() {
    std::lock_guard<std::recursive_mutex> lock(libssh2Mutex); // 确保在访问 session 时加锁
    if (!session) {
        OH_LOG_ERROR(LOG_APP, "SSH 会话未初始化，无法初始化 SFTP");
        return false;
    }

    OH_LOG_INFO(LOG_APP, "开始并行初始化 SFTP 会话...");

    // 销毁旧的SFTP会话（如果存在）
    if (interactiveSftpSession) {
        interactiveSftpSession.reset();
    }
    if (transferSftpSession) {
        transferSftpSession.reset();
    }

    SftpConfig config = getSftpConfig(); // 获取一次配置

    // 用于存储连接结果和临时会话对象
    std::unique_ptr<SftpSession> tempInteractiveSession = nullptr;
    std::unique_ptr<SftpSession> tempTransferSession = nullptr;
    std::atomic<bool> interactiveSuccess{false};
    std::atomic<bool> transferSuccess{false};
    std::string interactiveErrorMsg;
    std::string transferErrorMsg;
    std::mutex errorMutex; // 用于保护错误消息写入

    // --- 启动交互式 SFTP 会话连接线程 ---
    std::thread interactiveThread([&]() {
        OH_LOG_INFO(LOG_APP, "交互式 SFTP 连接线程启动");
        try {
            // Use a temporary unique_ptr within the thread
            auto sftpSession = std::make_unique<SftpSession>(config, true); // true表示非阻塞
            if (sftpSession->connect()) { // Check connection result
                // If connect succeeds, move ownership to the temporary variable captured by the outer scope
                tempInteractiveSession = std::move(sftpSession);
                interactiveSuccess.store(true);
                OH_LOG_INFO(LOG_APP, "交互式 SFTP 会话连接成功 (线程内)");
            } else {
                // Connection failed, log error but don't store the session
                std::lock_guard<std::mutex> lock(errorMutex);
                interactiveErrorMsg = "交互式 SFTP 会话连接失败 (connect 返回 false)";
                OH_LOG_ERROR(LOG_APP, "%s", interactiveErrorMsg.c_str());
                // interactiveSuccess remains false
            }
        } catch (const std::exception& e) {
            std::lock_guard<std::mutex> lock(errorMutex);
            interactiveErrorMsg = std::string("创建/连接交互式 SFTP 会话异常: ") + e.what(); // More specific message
            OH_LOG_ERROR(LOG_APP, "%s", interactiveErrorMsg.c_str());
            // interactiveSuccess remains false
        } catch (...) {
            std::lock_guard<std::mutex> lock(errorMutex);
            interactiveErrorMsg = "创建/连接交互式 SFTP 会话发生未知异常";
            OH_LOG_ERROR(LOG_APP, "%s", interactiveErrorMsg.c_str());
            // interactiveSuccess remains false
        }
         OH_LOG_INFO(LOG_APP, "交互式 SFTP 连接线程结束");
    });

    // --- 启动传输 SFTP 会话连接线程 ---
    std::thread transferThread([&]() {
         OH_LOG_INFO(LOG_APP, "传输 SFTP 连接线程启动");
        try {
            // Use a temporary unique_ptr within the thread
            auto sftpSession = std::make_unique<SftpSession>(config, true); // true表示非阻塞
            if (sftpSession->connect()) { // Check connection result
                // If connect succeeds, move ownership
                tempTransferSession = std::move(sftpSession);
                transferSuccess.store(true);
                OH_LOG_INFO(LOG_APP, "传输 SFTP 会话连接成功 (线程内)");
            } else {
                // Connection failed, log error
                std::lock_guard<std::mutex> lock(errorMutex);
                transferErrorMsg = "传输 SFTP 会话连接失败 (connect 返回 false)";
                 OH_LOG_ERROR(LOG_APP, "%s", transferErrorMsg.c_str());
                 // transferSuccess remains false
            }
        } catch (const std::exception& e) {
            std::lock_guard<std::mutex> lock(errorMutex);
            transferErrorMsg = std::string("创建/连接传输 SFTP 会话异常: ") + e.what(); // More specific message
            OH_LOG_ERROR(LOG_APP, "%s", transferErrorMsg.c_str());
             // transferSuccess remains false
        } catch (...) {
            std::lock_guard<std::mutex> lock(errorMutex);
            transferErrorMsg = "创建/连接传输 SFTP 会话发生未知异常";
            OH_LOG_ERROR(LOG_APP, "%s", transferErrorMsg.c_str());
             // transferSuccess remains false
        }
         OH_LOG_INFO(LOG_APP, "传输 SFTP 连接线程结束");
    });

    // --- 等待两个线程完成 ---
    OH_LOG_INFO(LOG_APP, "等待 SFTP 连接线程完成...");
    interactiveThread.join();
    transferThread.join();
    OH_LOG_INFO(LOG_APP, "SFTP 连接线程已全部完成");

    // --- 处理结果 --- (Modified logic)
    bool finalInteractiveSuccess = interactiveSuccess.load();
    bool finalTransferSuccess = transferSuccess.load();

    // Move successfully connected sessions to member variables
    if (finalInteractiveSuccess) {
        interactiveSftpSession = std::move(tempInteractiveSession);
        OH_LOG_INFO(LOG_APP, "交互式 SFTP 会话已成功设置.");
    } else {
        interactiveSftpSession.reset(); // Ensure it's null if failed
        std::lock_guard<std::mutex> lock(errorMutex); // Lock needed to read error message safely
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话初始化失败: %s", interactiveErrorMsg.empty() ? "未知错误" : interactiveErrorMsg.c_str());
    }

    if (finalTransferSuccess) {
        transferSftpSession = std::move(tempTransferSession);
        OH_LOG_INFO(LOG_APP, "传输 SFTP 会话已成功设置.");
    } else {
        transferSftpSession.reset(); // Ensure it's null if failed
        std::lock_guard<std::mutex> lock(errorMutex); // Lock needed to read error message safely
        OH_LOG_ERROR(LOG_APP, "传输 SFTP 会话初始化失败: %s", transferErrorMsg.empty() ? "未知错误" : transferErrorMsg.c_str());
    }

    // Always return true to indicate the initialization *attempt* finished, even if partially failed.
    // The caller (openConnect) should check if the pointers are valid.
    OH_LOG_INFO(LOG_APP, "initSftp 尝试完成 (Interactive: %{public}d, Transfer: %{public}d). 将返回 true.", finalInteractiveSuccess, finalTransferSuccess);
    return true;
    // ---------------------

    // Original logic commented out:
    /*
    if (finalInteractiveSuccess && finalTransferSuccess) {
        // 两者都成功，将临时指针移动到成员变量
        OH_LOG_INFO(LOG_APP, "两个 SFTP 会话均已成功初始化");
        interactiveSftpSession = std::move(tempInteractiveSession);
        transferSftpSession = std::move(tempTransferSession);
        return true;
    } else {
        // ... (original error logging) ...
        return false; // 整体初始化失败
    }
    */
}

bool SshSession::listDirectory(const std::string& path, std::function<void(const FileInfo&)> callback) {
    OH_LOG_INFO(LOG_APP, "SshSession::listDirectory 开始执行，路径: %{public}s", path.c_str());
    // 会话未就绪时先尝试重建
    if (!interactiveSftpSession || !interactiveSftpSession->isValid()) {
        OH_LOG_WARN(LOG_APP, "交互式 SFTP 会话未就绪，尝试重新初始化");
        if (!initSftp() || !interactiveSftpSession || !interactiveSftpSession->isValid()) {
            OH_LOG_ERROR(LOG_APP, "重新初始化交互式 SFTP 会话失败");
            return false;
        }
    }

    // 首次调用，捕获异常消息（包含 SFTP Code）
    std::string firstError;
    try {
        bool ok = interactiveSftpSession->listDirectory(path, callback);
        if (ok) return true;
    } catch (const std::exception& e) {
        firstError = e.what();
        OH_LOG_WARN(LOG_APP, "listDirectory 首次异常: %s，尝试重建并重试", firstError.c_str());
    } catch (...) {
        firstError = "Unknown error";
        OH_LOG_WARN(LOG_APP, "listDirectory 首次异常(未知)，尝试重建并重试");
    }

    // 重建并重试一次
    if (!initSftp() || !interactiveSftpSession || !interactiveSftpSession->isValid()) {
        OH_LOG_ERROR(LOG_APP, "listDirectory 重建 SFTP 失败");
        if (!firstError.empty()) throw std::runtime_error(firstError);
        return false;
    }
    try {
        bool ok2 = interactiveSftpSession->listDirectory(path, callback);
        if (!ok2 && !firstError.empty()) throw std::runtime_error(firstError);
        return ok2;
    } catch (...) {
        // 透传异常，便于 N-API 提取 SFTP Code（如权限不足=3）
        throw;
    }
}

bool SshSession::uploadFile(int localFd, const std::string& remotePath, std::function<void(int)> progressCallback) {
    if (!transferSftpSession) {
        OH_LOG_ERROR(LOG_APP, "传输 SFTP 会话未初始化 (Transfer SFTP session not initialized)");
        return false;
    }

    bool result = transferSftpSession->uploadFile(localFd, remotePath, progressCallback);

    return result;
}

bool SshSession::downloadFile(const std::string& remotePath, int localFd, std::function<void(off_t)> progressCallback) {
    OH_LOG_INFO(LOG_APP, "SshSession::downloadFile called for %s to fd %d", remotePath.c_str(), localFd);
    if (!transferSftpSession) {
        OH_LOG_ERROR(LOG_APP, "传输 SFTP 会话未初始化 (Transfer SFTP session not initialized)");
        return false;
    }

    // 直接将字节回调传递给 SftpSession
    bool result = transferSftpSession->downloadFile(remotePath, localFd, progressCallback);
    OH_LOG_INFO(LOG_APP, "SshSession::downloadFile forwarding result: %d", result);

    return result;
}

bool SshSession::deleteFile(const std::string& path) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return false;
    }

    bool result = interactiveSftpSession->deleteFile(path);

    return result;
}

bool SshSession::createDirectory(const std::string& path) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return false;
    }

    bool result = interactiveSftpSession->createDirectory(path);

    return result;
}

bool SshSession::deleteDirectory(const std::string& path) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return false;
    }

    bool result = interactiveSftpSession->deleteDirectory(path);

    return result;
}

bool SshSession::rename(const std::string& oldPath, const std::string& newPath) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return false;
    }

    bool result = interactiveSftpSession->rename(oldPath, newPath);

    return result;
}

// 设置文件时间
bool SshSession::setFileTime(const std::string& path, uint64_t mtime, uint64_t atime) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return false;
    }
    return interactiveSftpSession->setFileTime(path, mtime, atime);
}

// 获取文件信息
bool SshSession::getFileInfo(const std::string& path, FileInfo& info) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return false;
    }
    return interactiveSftpSession->getFileInfo(path, info);
}

// 设置文件权限
bool SshSession::setPermissions(const std::string& path, uint32_t permissions) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return false;
    }
    return interactiveSftpSession->setPermissions(path, permissions);
}

// 获取权限字符串
std::string SshSession::getPermissionString(uint32_t permissions) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return "";
    }
    return interactiveSftpSession->getPermissionString(permissions);
}

// 获取时间字符串
std::string SshSession::getTimeString(uint64_t timestamp) {
    if (!interactiveSftpSession) {
        OH_LOG_ERROR(LOG_APP, "交互式 SFTP 会话未初始化 (Interactive SFTP session not initialized)");
        return "";
    }
    return interactiveSftpSession->getTimeString(timestamp);
}

// 端口转发相关方法实现 - 转发给portForward对象
bool SshSession::startLocalPortForwarding(int localPort, const std::string& targetHost, int targetPort, bool anyInterface) {
    // --- Lazy Initialization Check ---
    if (!portForward) {
        OH_LOG_ERROR(LOG_APP, "Cannot start local forward: Port Forwarding Manager not initialized.");
        return false;
    }
    if (!portForward->isPfConnected()) {
        OH_LOG_INFO(LOG_APP, "startLocalPortForwarding: PF session not connected, attempting to connect...");
        if (!portForward->connectSession()) {
            OH_LOG_ERROR(LOG_APP, "Cannot start local forward: Failed to establish dedicated PF session.");
            return false;
        }
        OH_LOG_INFO(LOG_APP, "startLocalPortForwarding: Dedicated PF session established.");
    }
    // --- End Lazy Check ---

    // Original logic:
    // if (!portForward) {
    //     OH_LOG_ERROR(LOG_APP, "端口转发未初始化");
    //     return false;
    // }
    return portForward->startLocalPortForwarding(localPort, targetHost, targetPort, anyInterface);
}

bool SshSession::startRemotePortForwarding(int remotePort, const std::string& targetHost, int targetPort) {
    // --- Lazy Initialization Check ---
    if (!portForward) {
        OH_LOG_ERROR(LOG_APP, "Cannot start remote forward: Port Forwarding Manager not initialized.");
        return false;
    }
    if (!portForward->isPfConnected()) {
        OH_LOG_INFO(LOG_APP, "startRemotePortForwarding: PF session not connected, attempting to connect...");
        if (!portForward->connectSession()) {
            OH_LOG_ERROR(LOG_APP, "Cannot start remote forward: Failed to establish dedicated PF session.");
            return false;
        }
        OH_LOG_INFO(LOG_APP, "startRemotePortForwarding: Dedicated PF session established.");
    }
    // --- End Lazy Check ---

    // Original logic:
    // if (!portForward) {
    //     OH_LOG_ERROR(LOG_APP, "端口转发未初始化");
    //     return false;
    // }
    return portForward->startRemotePortForwarding(remotePort, targetHost, targetPort);
}

bool SshSession::startDynamicPortForwarding(int localPort, bool anyInterface) {
    // --- Lazy Initialization Check ---
    if (!portForward) {
        OH_LOG_ERROR(LOG_APP, "Cannot start dynamic forward: Port Forwarding Manager not initialized.");
        return false;
    }
    if (!portForward->isPfConnected()) {
        OH_LOG_INFO(LOG_APP, "startDynamicPortForwarding: PF session not connected, attempting to connect...");
        if (!portForward->connectSession()) {
            OH_LOG_ERROR(LOG_APP, "Cannot start dynamic forward: Failed to establish dedicated PF session.");
            return false;
        }
        OH_LOG_INFO(LOG_APP, "startDynamicPortForwarding: Dedicated PF session established.");
    }
    // --- End Lazy Check ---

    // Original logic:
    // if (!portForward) {
    //     OH_LOG_ERROR(LOG_APP, "端口转发未初始化");
    //     return false;
    // }
    return portForward->startDynamicPortForwarding(localPort, anyInterface);
}

bool SshSession::stopPortForwarding(int port, bool isRemote) {
    if (!portForward) {
        OH_LOG_ERROR(LOG_APP, "端口转发未初始化");
        return false;
    }
    return portForward->stopPortForwarding(port, isRemote);
}

bool SshSession::isPortForwardingActive(int port, bool isRemote) {
    // --- Add check for session status --- 
    SessionStatus currentStatus;
    {
        std::lock_guard<std::mutex> lock(statusMutex);
        currentStatus = status;
    }
    if (currentStatus != SessionStatus::CONNECTED) {
        OH_LOG_WARN(LOG_APP, "isPortForwardingActive called on non-connected session (status=%{public}d). Returning false.", static_cast<int>(currentStatus));
        return false; // Return false if not connected
    }
    // ------------------------------------

    if (!portForward) {
        OH_LOG_ERROR(LOG_APP, "端口转发未初始化");
        return false;
    }
    return portForward->isPortForwardingActive(port, isRemote);
}

std::vector<std::tuple<int, std::string, int, bool, bool>> SshSession::listActivePortForwardings() {
    // --- Add check for session status --- 
    SessionStatus currentStatus;
    {
        std::lock_guard<std::mutex> lock(statusMutex);
        currentStatus = status;
    }
    if (currentStatus != SessionStatus::CONNECTED) {
        OH_LOG_WARN(LOG_APP, "listActivePortForwardings called on non-connected session (status=%{public}d). Returning empty list.", static_cast<int>(currentStatus));
        return {}; // Return empty vector if not connected
    }
    // ------------------------------------

    if (!portForward) {
        OH_LOG_ERROR(LOG_APP, "端口转发未初始化");
        return {};
    }
    return portForward->listActivePortForwardings();
}

// --- 恢复 setLogging 实现 ---
bool SshSession::setLogging(int fd, int logType, int existOperation, bool includeHeader, bool omitKnownPassword, bool omitSessionData) {
    OH_LOG_INFO(LOG_APP, "SshSession::setLogging called with fd=%{public}d, logType=%{public}d, existOperation=%{public}d, includeHeader=%{public}d, omitKnownPassword=%{public}d, omitSessionData=%{public}d", 
        fd, logType, existOperation, includeHeader, omitKnownPassword, omitSessionData);
    bool success = false;
    bool loggingEnabled = false;

    try {
        // 根据参数直接初始化或禁用 LogManager
        if (logType == 0 || fd < 0) {
            OH_LOG_INFO(LOG_APP, "setLogging: 参数指示禁用日志，调用 logManager.disable()");
            logManager.disable();
            loggingEnabled = false; // 标记日志为禁用
        } else {
            OH_LOG_INFO(LOG_APP, "setLogging: 参数指示启用日志，调用 logManager.init()");
            logManager.init(fd, logType, existOperation, includeHeader, omitKnownPassword, omitSessionData);
            loggingEnabled = true; // 标记日志为启用
        }
        OH_LOG_INFO(LOG_APP, "LogManager 配置完成 (通过 setLogging)。");
        success = true;

        // --- 处理初始缓冲区 ---
        std::string bufferedData;
        {
            std::lock_guard<std::mutex> bufferLock(bufferMutex);
            // 只有在日志实际启用时才写入缓冲区
            if (loggingEnabled && !initialBuffer.empty()) {
                OH_LOG_INFO(LOG_APP, "setLogging: LogManager 初始化完成，开始写入 %zu 字节的初始缓冲区数据...", initialBuffer.length());
                bufferedData = std::move(initialBuffer); // 移动数据以减少拷贝
                initialBuffer.clear(); // 确保清空
            } else if (!initialBuffer.empty()) {
                 OH_LOG_INFO(LOG_APP, "setLogging: LogManager 已禁用或缓冲区为空，丢弃初始缓冲区数据。");
                 initialBuffer.clear(); // 如果日志被禁用，也清空缓冲区
            }
            // --- 设置初始化标志 ---
            logManagerInitialized.store(true);
            OH_LOG_INFO(LOG_APP, "setLogging: logManagerInitialized 标志设置为 true.");
        } // 释放 bufferMutex

        // 在锁外部写入数据，避免长时间持有锁
        if (loggingEnabled && !bufferedData.empty()) {
            try {
                logManager.writeLog(bufferedData.c_str(), bufferedData.length());
                OH_LOG_INFO(LOG_APP, "setLogging: 初始缓冲区数据写入完成。");
            } catch(const std::exception& writeEx) {
                 OH_LOG_ERROR(LOG_APP, "setLogging: 写入初始缓冲区数据时发生异常: %{public}s", writeEx.what());
                 // success 已经为 true，这里只记录错误
            } catch(...) {
                 OH_LOG_ERROR(LOG_APP, "setLogging: 写入初始缓冲区数据时发生未知异常。");
            }
        }
        // --------------------

        return success; // 返回 setLogging 操作本身的成功状态

    } catch (const std::exception& e) {
        OH_LOG_ERROR(LOG_APP, "配置 LogManager 失败: %{public}s", e.what());
        // 尝试在错误时禁用
        try {
            logManager.disable();
        } catch(...) { /*忽略禁用时的错误*/ }
         // 即使配置失败，也要标记初始化完成（虽然是失败的初始化），避免 receiveData 永远缓冲
         logManagerInitialized.store(true);
         OH_LOG_WARN(LOG_APP, "setLogging: 因异常设置 logManagerInitialized 标志为 true，但日志可能未启用。");
        return false; // 返回 setLogging 失败
    }
}
// ----------------------------

bool SshSession::resizePty(int width, int height) {
    // 使用带标签的日志记录宽度和高度
    OH_LOG_INFO(LOG_APP, "尝试将 PTY 大小调整为 宽度=%{public}d, 高度=%{public}d", width, height);

    // 检查宽度和高度是否有效
    if (width <= 0 || height <= 0) {
        OH_LOG_ERROR(LOG_APP, "调整 PTY 大小失败：无效的尺寸（宽度=%{public}d, 高度=%{public}d）", width, height);
        return false;
    }

    // 使用递归互斥锁保护对 libssh2 资源的访问
    std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
    OH_LOG_INFO(LOG_APP, "调整 PTY 大小：已获取 libssh2Mutex");

    // 检查会话和 Shell 通道是否有效
    if (!session || !channelShell) {
        OH_LOG_ERROR(LOG_APP, "调整 PTY 大小失败：会话或 Shell 通道无效。");
        OH_LOG_INFO(LOG_APP, "调整 PTY 大小：释放 libssh2Mutex"); // 在返回前记录锁的释放
        return false;
    }
    OH_LOG_INFO(LOG_APP, "调整 PTY 大小：会话和 Shell 通道有效");

    int rc;
    int attempts = 0;
    const int maxAttempts = 5; // 限制重试次数，防止无限循环

    // 循环调用 libssh2_channel_request_pty_size，处理 EAGAIN 错误
    OH_LOG_INFO(LOG_APP, "调整 PTY 大小：进入 libssh2_channel_request_pty_size 循环");
    while (attempts < maxAttempts) {
        rc = libssh2_channel_request_pty_size(channelShell.get(), width, height);
        OH_LOG_INFO(LOG_APP, "调整 PTY 大小：libssh2_channel_request_pty_size 返回 %{public}d (尝试次数 %{public}d/%{public}d)", rc, attempts + 1, maxAttempts);

        if (rc == LIBSSH2_ERROR_EAGAIN) {
            OH_LOG_INFO(LOG_APP, "调整 PTY 大小：收到 EAGAIN，等待 Socket...");
            int ws_rc = waitSocket(); // 等待 Socket 状态变化
            OH_LOG_INFO(LOG_APP, "调整 PTY 大小：waitSocket 返回 %{public}d", ws_rc);
            if (ws_rc <= 0) {
                // 如果 waitSocket 超时或出错，增加尝试次数并短暂休眠
                attempts++;
                OH_LOG_ERROR(LOG_APP, "调整 PTY 大小失败：waitSocket 在 EAGAIN 期间超时或出错（尝试次数 %{public}d/%{public}d）。将休眠 50ms 后重试。", attempts, maxAttempts);
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                 // 可以考虑在这里直接返回 false，避免长时间阻塞
                 // return false;
            } else {
                 OH_LOG_INFO(LOG_APP, "调整 PTY 大小：waitSocket 就绪，立即重试请求");
                 // 不需要增加 attempts 或休眠，立即重试
            }
        } else {
            // 如果不是 EAGAIN，则跳出循环
            break;
        }
    } // while 循环结束

    OH_LOG_INFO(LOG_APP, "调整 PTY 大小：退出 libssh2_channel_request_pty_size 循环");

    // 检查最终结果
    if (rc != 0) {
        int last_errno = libssh2_session_last_errno(session.get());
        char *errmsg = nullptr;
        int errmsg_len = 0;
        libssh2_session_last_error(session.get(), &errmsg, &errmsg_len, 0);
        OH_LOG_ERROR(LOG_APP, "调整 PTY 大小最终失败，rc=%{public}d, libssh2_errno=%{public}d, 消息: %{public}s", rc, last_errno, errmsg ? errmsg : "N/A");
        OH_LOG_INFO(LOG_APP, "调整 PTY 大小：释放 libssh2Mutex"); // 在返回前记录锁的释放
        return false;
    }

    OH_LOG_INFO(LOG_APP, "PTY 大小调整成功。");
    OH_LOG_INFO(LOG_APP, "调整 PTY 大小：释放 libssh2Mutex"); // 在返回前记录锁的释放
    return true;
}

// --- 新增: 取消传输实现 ---
bool SshSession::cancelTransfer() {
    OH_LOG_INFO(LOG_APP, "SshSession::cancelTransfer called.");
    bool requestSent = false;

    // 主要取消传输会话上的操作
    // 使用锁确保线程安全地访问和操作 transferSftpSession
    std::lock_guard<std::recursive_mutex> lock(libssh2Mutex);
    if (transferSftpSession) {
        OH_LOG_INFO(LOG_APP, "Requesting cancel on transfer SFTP session.");
        transferSftpSession->requestCancel(); // 调用 SftpSession 的取消方法
        requestSent = true; // 标记请求已发送
    } else {
        OH_LOG_WARN(LOG_APP, "Cannot cancel transfer: transfer SFTP session is not initialized.");
    }

    // 可选：如果需要，也可以对 interactiveSftpSession 发送取消请求
    // if (interactiveSftpSession) {
    //     OH_LOG_INFO(LOG_APP, "Requesting cancel on interactive SFTP session.");
    //     interactiveSftpSession->requestCancel();
    //     requestSent = true; // 如果任一请求发送成功，则标记为 true
    // }

    return requestSent; // 返回是否至少向一个 SFTP 会话发送了取消请求
}
// -------------------------

// 实现parseOSC7Sequence方法 (手动解析版本)
void SshSession::parseOSC7Sequence(const std::string& data) {
    size_t startPos = 0;
    const std::string prefix = OSC7_PREFIX;
    const std::string suffix = OSC7_SUFFIX;
    while ((startPos = data.find(prefix, startPos)) != std::string::npos) {
        // 找到 OSC7 前缀
        startPos += prefix.length(); // 移动到前缀之后

        // 查找结束符 BEL ()
        size_t endPos = data.find(suffix, startPos);
        if (endPos == std::string::npos) {
            // 未找到结束符，可能序列不完整，停止解析
            OH_LOG_WARN(LOG_APP, "parseOSC7Sequence: 未找到结束符，序列可能不完整");
            break;
        }

        // 提取 file://hostname/path 部分
        std::string uri = data.substr(startPos, endPos - startPos);

        // 跳过 hostname，提取路径
        // 查找第一个 '/' 作为路径的开始
        size_t pathStartPos = uri.find('/');
        if (pathStartPos != std::string::npos) {
            std::string newPath = uri.substr(pathStartPos);

            // (可选) URL 解码 - 简单的 %XX 解码
            std::string decodedPath;
            decodedPath.reserve(newPath.length()); // 预分配空间
            for (size_t i = 0; i < newPath.length(); ++i) {
                if (newPath[i] == '%' && i + 2 < newPath.length()) {
                    try {
                        std::string hex = newPath.substr(i + 1, 2);
                        char decodedChar = static_cast<char>(std::stoi(hex, nullptr, 16));
                        decodedPath += decodedChar;
                        i += 2;
                    } catch (const std::invalid_argument& e) {
                        // 无效的 % 序列，按原样添加
                        decodedPath += newPath[i];
                        OH_LOG_WARN(LOG_APP, "parseOSC7Sequence: 无效的URL编码序列 %s", newPath.substr(i, 3).c_str());
                    } catch (const std::out_of_range& e) {
                         // 转换超出范围
                        decodedPath += newPath[i];
                        OH_LOG_WARN(LOG_APP, "parseOSC7Sequence: URL编码转换超出范围 %s", newPath.substr(i, 3).c_str());
                    }
                } else {
                    decodedPath += newPath[i];
                }
            }


            // 如果目录有变化，更新当前目录并通知回调
            if (currentDirectory != decodedPath) {
                OH_LOG_INFO(LOG_APP, "检测到目录变更: %s", decodedPath.c_str());
                currentDirectory = decodedPath;

                // 如果设置了回调，通知目录变更
                if (directoryChangeCallback) {
                    try {
                       directoryChangeCallback(currentDirectory);
                    } catch (const std::exception& e) {
                       OH_LOG_ERROR(LOG_APP, "执行目录变更回调时发生异常: %s", e.what());
                    } catch (...) {
                       OH_LOG_ERROR(LOG_APP, "执行目录变更回调时发生未知异常");
                    }
                }
            }
        } else {
             OH_LOG_WARN(LOG_APP, "parseOSC7Sequence: 在URI中未找到路径分隔符 '/' (%s)", uri.c_str());
        }

        // 从结束符之后继续搜索
        startPos = endPos + suffix.length();
    }
}

// 实现enableDirectoryTracking方法
bool SshSession::enableDirectoryTracking(bool enable) {
    OH_LOG_INFO(LOG_APP, "enableDirectoryTracking: %d", enable);
    
    // 如果之前没有启用但现在要启用，发送配置命令
    if (!followTerminalDirectory && enable) {
        bool result = configureRemoteShell();
        if (!result) {
            OH_LOG_ERROR(LOG_APP, "Failed to configure remote shell for directory tracking");
            return false;
        }
    }
    
    followTerminalDirectory = enable;
    return true;
}

// 实现setDirectoryChangeCallback方法
void SshSession::setDirectoryChangeCallback(std::function<void(const std::string&)> callback) {
    directoryChangeCallback = std::move(callback);
}

// 实现configureRemoteShell方法
bool SshSession::configureRemoteShell() {
    // --- 使用 RAII 控制配置标志 ---
    ShellConfigGuard configGuard(isConfiguringShell);
    // ---------------------------
    OH_LOG_INFO(LOG_APP, "configureRemoteShell: Configuring remote shell for OSC7 directory tracking");

    if (!channelShell || status != SessionStatus::CONNECTED) {
        OH_LOG_ERROR(LOG_APP, "configureRemoteShell: Not connected or no shell channel");
        return false;
    }

    // 更加简洁的方法：使用bash -c执行未记录命令
    const char* bash_command = 
        "{\n"
        "HISTFILE_TMP=$HISTFILE; HISTSIZE_TMP=$HISTSIZE; HISTCONTROL_TMP=$HISTCONTROL;\n"
        "unset HISTFILE; HISTSIZE=0; HISTCONTROL=ignoreboth; stty -echo 2>/dev/null;\n"
        "cat > /tmp/osc7_config.$$ << 'EOFMARKER'\n"
        "#!/bin/bash\n"
        "# 配置OSC7目录跟踪\n"
        "if [ -n \"$BASH_VERSION\" ]; then\n"
        "  # Bash配置\n"
        "  PROMPT_COMMAND=\"${PROMPT_COMMAND:+$PROMPT_COMMAND; }printf '\\033]7;file://%s%s\\007' \\\"\\${HOSTNAME:-$(hostname)}\\\" \\\"\\${PWD/#$HOME/~}\\\"\"\n"
        "elif [ -n \"$ZSH_VERSION\" ]; then\n"
        "  # Zsh配置\n"
        "  precmd() { printf '\\033]7;file://%s%s\\007' \\\"\\${HOST}\\\" \\\"\\${PWD}\\\" ; }\n"
        "fi\n"
        "# 发送初始目录\n"
        "printf '\\033]7;file://%s%s\\007' \"${HOSTNAME:-$(hostname)}\" \"${PWD}\"\n"
        "EOFMARKER\n"
        "chmod +x /tmp/osc7_config.$$;\n"
        "source /tmp/osc7_config.$$ >/dev/null 2>&1;\n"
        "rm -f /tmp/osc7_config.$$;\n"
        "stty echo 2>/dev/null;\n"
        "export HISTFILE=$HISTFILE_TMP; export HISTSIZE=$HISTSIZE_TMP; export HISTCONTROL=$HISTCONTROL_TMP;\n"
        "unset HISTFILE_TMP HISTSIZE_TMP HISTCONTROL_TMP;\n"
        "} 2>/dev/null\n";

    // 使用一行命令发送所有内容
    OH_LOG_INFO(LOG_APP, "configureRemoteShell: Sending one-line configuration script...");
    if (!sendData(bash_command)) {
        OH_LOG_ERROR(LOG_APP, "configureRemoteShell: Failed to send configuration");
        return false;
    }

    // 等待脚本执行完成
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    OH_LOG_INFO(LOG_APP, "configureRemoteShell: Configuration completed via special script.");
    
    return true;
}

// --- 新增：实现 resizeTerminal override ---
bool SshSession::resizeTerminal(int width, int height) {
    // 直接调用内部的 pty 调整方法
    return this->resizePty(width, height);
}
