#include "SftpSession.h"
#include "SshSession.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <ctime>
#include <iomanip>
#include <sstream>
#include <hilog/log.h>
#include <mutex>
#include <thread>
#include <atomic>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <cmath> // Need for isnan, isinf

#undef LOG_DOMAIN 
#undef LOG_TAG 
#define LOG_DOMAIN 0x3200  // 全局domain宏，标识业务领域
#define LOG_TAG "MY_TAG"   // 全局tag宏，标识模块日志tag

// 新构造函数，使用配置结构体
SftpSession::SftpSession(const SftpConfig& config, bool nonBlocking)
    : config(config),
      session(nullptr, libssh2_session_free),
      sftp(nullptr),
      socket_fd(new libssh2_socket_t(-1)),
      currentPath("/"), // 初始化当前路径
      nonBlocking(nonBlocking)
{
    OH_LOG_INFO(LOG_APP, "创建新的独立SFTP会话: %{public}s:%{public}d, Keepalive: %{public}d",
               config.host.c_str(), config.port, config.keepAliveInterval);
}

SftpSession::~SftpSession() {
    OH_LOG_INFO(LOG_APP, "SftpSession 析构函数开始.");
    
    // Set flags to stop any ongoing operations and timers
    cancelRequested.store(true);
    stopThread.store(true); // 停止keepalive线程
    if (currentOperationActiveFlag) {
        currentOperationActiveFlag->store(false);
        OH_LOG_INFO(LOG_APP, "SftpSession 析构: Marked current operation inactive.");
    }
    OH_LOG_INFO(LOG_APP, "SftpSession 析构: 设置 cancelRequested 标志为 true.");
    
    try {
        std::lock_guard<std::mutex> lock(sessionMutex); // sessionMutex 保护 sftp 和 session
        OH_LOG_INFO(LOG_APP, "SftpSession 析构: 获取 sessionMutex.");
        if (sftp) {
            OH_LOG_INFO(LOG_APP, "SftpSession 析构: 关闭 SFTP.");
            try {
                // 使用非阻塞尝试关闭，避免卡死
                 int rc;
                 int attempts = 0;
                 do {
                     rc = libssh2_sftp_shutdown(sftp);
                     if (rc == LIBSSH2_ERROR_EAGAIN && nonBlocking && attempts < 5) {
                         waitSocket();
                         attempts++;
                     } else {
                         break;
                     }
                 } while(rc == LIBSSH2_ERROR_EAGAIN && nonBlocking && attempts < 5);

                 if(rc != 0 && rc != LIBSSH2_ERROR_EAGAIN) {
                     char* errmsg;
                     libssh2_session_last_error(session.get(), &errmsg, nullptr, 0);
                     OH_LOG_ERROR(LOG_APP, "关闭 SFTP 会话时出错 (%d): %s", rc, errmsg ? errmsg : "N/A");
                 } else if (rc == LIBSSH2_ERROR_EAGAIN) {
                      OH_LOG_WARN(LOG_APP, "关闭 SFTP 会话时仍然是 EAGAIN 状态.");
                 } else {
                      OH_LOG_INFO(LOG_APP, "SFTP 会话已关闭.");
                 }

            } catch (...) {
                OH_LOG_ERROR(LOG_APP, "关闭SFTP会话时出现异常");
            }
            sftp = nullptr;
        }

        if (session) {
             OH_LOG_INFO(LOG_APP, "SftpSession 析构: 断开 SSH 会话.");
             // 尝试断开底层 SSH 连接
             int rc;
             int attempts = 0;
             do {
                 rc = libssh2_session_disconnect(session.get(), "SFTP session closed");
                 if (rc == LIBSSH2_ERROR_EAGAIN && nonBlocking && attempts < 5) {
                     waitSocket();
                     attempts++;
                 } else {
                     break;
                 }
             } while(rc == LIBSSH2_ERROR_EAGAIN && nonBlocking && attempts < 5);
             // session 会通过 unique_ptr 的自定义删除器释放
             session.reset(); // 显式释放，确保发生在析构函数结束前
             OH_LOG_INFO(LOG_APP, "SSH 会话已重置.");
        }

        if (socket_fd && *socket_fd >= 0) {
             OH_LOG_INFO(LOG_APP, "SftpSession 析构: 关闭套接字.");
            close(*socket_fd);
            *socket_fd = -1;
        }
         OH_LOG_INFO(LOG_APP, "SftpSession 析构: 释放 sessionMutex.");
    } catch (const std::exception& e) {
         OH_LOG_ERROR(LOG_APP, "SftpSession析构过程中发生异常: %{public}s", e.what());
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "SftpSession析构过程中发生未处理异常");
    }
     OH_LOG_INFO(LOG_APP, "SftpSession 析构函数结束.");
}

bool SftpSession::connect() {
    std::lock_guard<std::mutex> lock(sessionMutex);
    OH_LOG_INFO(LOG_APP, "SFTP 开始连接过程...");

    // 检查配置有效性
    if (config.host.empty() || config.port <= 0 || config.port > 65535 || config.username.empty()) {
        OH_LOG_ERROR(LOG_APP, "SFTP 连接失败: 无效的连接参数 (Host: %{public}s, Port: %{public}d, User: %{public}s)",
                   config.host.c_str(), config.port, config.username.c_str());
        return false;
    }

    // --- 1. 地址解析 (同 SshSession) ---
    struct sockaddr_storage addr;
    memset(&addr, 0, sizeof(addr));
    socklen_t addr_len = 0;
    int pton_ret = 0;

    OH_LOG_INFO(LOG_APP, "SFTP 准备解析主机名/IP: '%{public}s'", config.host.c_str());

    // 尝试 IPv4
    pton_ret = inet_pton(AF_INET, config.host.c_str(), &(((struct sockaddr_in *)&addr)->sin_addr));
    if (pton_ret == 1) {
        OH_LOG_INFO(LOG_APP, "SFTP 地址被识别为 IPv4");
        struct sockaddr_in *sin = (struct sockaddr_in *)&addr;
        sin->sin_family = AF_INET;
        sin->sin_port = htons(config.port);
        addr_len = sizeof(struct sockaddr_in);
    } else {
        if (pton_ret == -1) {
            OH_LOG_ERROR(LOG_APP, "SFTP inet_pton(AF_INET) 失败 for '%{public}s': errno=%{public}d (%{public}s)", config.host.c_str(), errno, strerror(errno));
        }
        // 尝试 IPv6
        pton_ret = inet_pton(AF_INET6, config.host.c_str(), &(((struct sockaddr_in6 *)&addr)->sin6_addr));
        if (pton_ret == 1) {
            OH_LOG_INFO(LOG_APP, "SFTP 地址被识别为 IPv6");
            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)&addr;
            sin6->sin6_family = AF_INET6;
            sin6->sin6_port = htons(config.port);
            addr_len = sizeof(struct sockaddr_in6);
        } else {
            if (pton_ret == -1) {
                OH_LOG_ERROR(LOG_APP, "SFTP inet_pton(AF_INET6) 失败 for '%{public}s': errno=%{public}d (%{public}s)", config.host.c_str(), errno, strerror(errno));
            } else { // pton_ret == 0
                 OH_LOG_INFO(LOG_APP, "SFTP 输入 '%{public}s' 不是有效的 IPv6 地址格式，尝试 DNS 解析...", config.host.c_str());
                 // --- DNS 解析回退 ---
                 struct addrinfo hints, *res;
                 memset(&hints, 0, sizeof(hints));
                 hints.ai_family = AF_UNSPEC; // 允许 IPv4 或 IPv6
                 hints.ai_socktype = SOCK_STREAM;

                 int getaddrinfo_ret = getaddrinfo(config.host.c_str(), std::to_string(config.port).c_str(), &hints, &res);
                 if (getaddrinfo_ret == 0 && res != nullptr) {
                     OH_LOG_INFO(LOG_APP, "SFTP DNS 解析成功，使用第一个结果 (Family: %{public}d)", res->ai_family);
                     memcpy(&addr, res->ai_addr, res->ai_addrlen);
                     addr_len = res->ai_addrlen;
                     // 确保端口号正确设置 (getaddrinfo 应该已经设置了)
                     if (addr.ss_family == AF_INET) {
                         ((struct sockaddr_in *)&addr)->sin_port = htons(config.port);
                     } else if (addr.ss_family == AF_INET6) {
                         ((struct sockaddr_in6 *)&addr)->sin6_port = htons(config.port);
                     }
                     freeaddrinfo(res); // 释放 getaddrinfo 分配的内存
                 } else {
                    OH_LOG_ERROR(LOG_APP, "SFTP 无法将 '%{public}s' 解析为有效的 IPv4/IPv6 地址或通过 DNS 解析 (getaddrinfo error: %{public}s)", config.host.c_str(), gai_strerror(getaddrinfo_ret));
                    return false;
                 }
                 // --- DNS 解析结束 ---
            }
        }
    }

    if (addr_len == 0) {
         OH_LOG_ERROR(LOG_APP, "SFTP 内部错误：地址解析后 addr_len 仍为 0");
         return false;
    }

    // --- 2. 创建套接字 (在确定地址族后) ---
    if (*socket_fd >= 0) { // 如果之前有旧的socket，先关闭
        OH_LOG_INFO(LOG_APP, "SFTP 关闭旧的套接字 (fd=%{public}d)", *socket_fd);
        close(*socket_fd);
        *socket_fd = -1;
    }
    OH_LOG_INFO(LOG_APP, "SFTP 使用地址族 %{public}d 创建套接字", addr.ss_family);
    *socket_fd = socket(addr.ss_family, SOCK_STREAM, 0);
    if (*socket_fd < 0) {
        OH_LOG_ERROR(LOG_APP, "SFTP 创建套接字失败: errno=%{public}d (%{public}s)", errno, strerror(errno));
        return false;
    }
    OH_LOG_INFO(LOG_APP, "SFTP 套接字创建成功 (fd=%{public}d)", *socket_fd);


    // --- 3. 非阻塞连接 (同 SshSession) ---
    int retryCount = 0;
    const int maxRetries = 3;
    const int connectTimeout = 5; // 连接超时设为5秒
    bool connected = false;

    int flags = fcntl(*socket_fd, F_GETFL, 0);
    fcntl(*socket_fd, F_SETFL, flags | O_NONBLOCK);

    OH_LOG_INFO(LOG_APP, "SFTP 发起非阻塞连接到 %{public}s:%{public}d...", config.host.c_str(), config.port);
    int connect_ret = ::connect(*socket_fd, (struct sockaddr *)&addr, addr_len);

    if (connect_ret == 0) {
        OH_LOG_INFO(LOG_APP, "SFTP 连接立即成功");
        connected = true;
        fcntl(*socket_fd, F_SETFL, flags); // 恢复阻塞模式
    } else if (errno == EINPROGRESS) {
        OH_LOG_INFO(LOG_APP, "SFTP 连接正在进行中 (EINPROGRESS)，进入 select 等待循环 (最多 %{public}d 次，每次 %{public}d 秒)", maxRetries, connectTimeout);
        while (retryCount < maxRetries && !connected) {
            retryCount++;
            fd_set writefds;
            FD_ZERO(&writefds);
            FD_SET(*socket_fd, &writefds);
            fd_set exceptfds = writefds;

            struct timeval timeout;
            timeout.tv_sec = connectTimeout;
            timeout.tv_usec = 0;

            OH_LOG_INFO(LOG_APP, "SFTP 等待 select (第 %{public}d 次尝试)...", retryCount);
            int select_ret = select(*socket_fd + 1, nullptr, &writefds, &exceptfds, &timeout);

            if (select_ret > 0) {
                if (FD_ISSET(*socket_fd, &writefds) || FD_ISSET(*socket_fd, &exceptfds)) {
                    int error = 0;
                    socklen_t len = sizeof(error);
                    if (getsockopt(*socket_fd, SOL_SOCKET, SO_ERROR, &error, &len) == 0) {
                        if (error == 0) {
                            OH_LOG_INFO(LOG_APP, "SFTP select 报告连接成功 (SO_ERROR=0)");
                            connected = true;
                            fcntl(*socket_fd, F_SETFL, flags); // 恢复阻塞模式
                        } else {
                            OH_LOG_ERROR(LOG_APP, "SFTP select 报告连接失败 (SO_ERROR=%{public}d): %{public}s", error, strerror(error));
                            errno = error; // 设置 errno
                            break; // 失败，跳出重试
                        }
                    } else {
                        OH_LOG_ERROR(LOG_APP, "SFTP getsockopt(SO_ERROR) 失败: %{public}s", strerror(errno));
                        break; // 失败，跳出重试
                    }
                } else {
                    // select 返回 > 0 但我们的 fd 没有就绪？理论上不应该
                    OH_LOG_WARN(LOG_APP, "SFTP select 返回 %{public}d 但套接字未就绪?", select_ret);
                    std::this_thread::sleep_for(std::chrono::milliseconds(100)); // 短暂等待
                }
            } else if (select_ret == 0) {
                OH_LOG_INFO(LOG_APP, "SFTP select 等待超时 (第 %{public}d 次尝试)", retryCount);
                // 继续循环重试
            } else { // select_ret < 0
                OH_LOG_ERROR(LOG_APP, "SFTP select 失败: %{public}s", strerror(errno));
                break; // 失败，跳出重试
            }
        } // while retry loop
    } else {
        OH_LOG_ERROR(LOG_APP, "SFTP 初始 connect 调用失败: %{public}s", strerror(errno));
        // connected 保持 false
    }

    if (!connected) {
        OH_LOG_ERROR(LOG_APP, "SFTP 连接失败 (尝试 %{public}d 次后)", retryCount);
        if (*socket_fd >= 0) {
            close(*socket_fd);
            *socket_fd = -1;
        }
        return false;
    }
    OH_LOG_INFO(LOG_APP, "SFTP 套接字连接成功");

    // --- 4. 创建 SSH 会话 ---
    LIBSSH2_SESSION* new_session = libssh2_session_init();
    if (!new_session) {
        OH_LOG_ERROR(LOG_APP, "SFTP 创建 libssh2 会话失败");
        close(*socket_fd);
        *socket_fd = -1;
        return false;
    }
    session.reset(new_session);
    OH_LOG_INFO(LOG_APP, "SFTP libssh2 会话初始化成功");

    // --- 5. 设置会话阻塞模式 ---
    // 注意：这里我们遵循 SftpSession 的 nonBlocking 成员变量
    // 如果外部需要非阻塞，则设置为0；否则为1
    OH_LOG_INFO(LOG_APP, "SFTP 设置会话阻塞模式: %{public}s", nonBlocking ? "Non-blocking" : "Blocking");
    libssh2_session_set_blocking(session.get(), nonBlocking ? 0 : 1);

    // --- BEGIN MODIFICATION: Enable Compression ---
    OH_LOG_INFO(LOG_APP, "SFTP 尝试启用压缩...");
    if (libssh2_session_flag(session.get(), LIBSSH2_FLAG_COMPRESS, 1) == 0) {
        OH_LOG_INFO(LOG_APP, "SFTP 压缩已启用.");
    } else {
        OH_LOG_WARN(LOG_APP, "SFTP 无法启用压缩 (可能服务器不支持).");
    }
    // --- END MODIFICATION ---

    // --- 6. SSH 会话握手 ---
    int rc = 0;
    time_t startTime = time(nullptr);
    const int handshakeTimeout = 15; // 握手超时设为15秒
    OH_LOG_INFO(LOG_APP, "SFTP 开始 SSH 握手 (超时: %{public}d 秒)...", handshakeTimeout);

    do {
        rc = libssh2_session_handshake(session.get(), *socket_fd);
        if (rc == LIBSSH2_ERROR_EAGAIN) {
            if (!nonBlocking) { // 如果是阻塞模式收到 EAGAIN，说明有问题
                OH_LOG_ERROR(LOG_APP, "SFTP 阻塞模式下握手返回 EAGAIN");
                session.reset();
                close(*socket_fd);
                *socket_fd = -1;
                return false;
            }
            int ws_rc = waitSocket(); // 非阻塞模式下等待
            if (ws_rc < 0) {
                OH_LOG_ERROR(LOG_APP, "SFTP waitSocket 在握手期间失败");
                session.reset();
                close(*socket_fd);
                *socket_fd = -1;
                return false;
            }
            if (time(nullptr) - startTime > handshakeTimeout) {
                OH_LOG_ERROR(LOG_APP, "SFTP SSH 握手超时");
                session.reset();
                close(*socket_fd);
                *socket_fd = -1;
                return false;
            }
        } else if (rc != 0) {
            char* errmsg = nullptr;
            libssh2_session_last_error(session.get(), &errmsg, nullptr, 0);
            OH_LOG_ERROR(LOG_APP, "SFTP SSH 握手失败: rc=%{public}d, msg: %{public}s", rc, errmsg ? errmsg : "N/A");
            session.reset();
            close(*socket_fd);
            *socket_fd = -1;
            return false;
        }
    } while (rc == LIBSSH2_ERROR_EAGAIN); // 只有非阻塞模式下才会因为 EAGAIN 循环

    OH_LOG_INFO(LOG_APP, "SFTP SSH 握手成功");

    // --- 7. 用户认证 ---
    startTime = time(nullptr);
    const int authTimeout = 15; // 认证超时设为15秒
    OH_LOG_INFO(LOG_APP, "SFTP 开始用户认证 (超时: %{public}d 秒)...", authTimeout);

    if (config.useKeyAuth) {
        OH_LOG_INFO(LOG_APP, "SFTP 尝试使用内存中的密钥进行认证 (User: %{public}s)", config.username.c_str());
        if (config.privateKeyData.empty()) {
            OH_LOG_ERROR(LOG_APP, "SFTP 密钥认证失败：私钥数据为空");
            session.reset();
            close(*socket_fd);
            *socket_fd = -1;
            return false;
        }
        do {
            rc = libssh2_userauth_publickey_frommemory(
                session.get(),
                config.username.c_str(),
                config.username.length(), // 使用用户名长度
                nullptr, 0, // 公钥数据为空
                config.privateKeyData.data(),
                config.privateKeyData.size(),
                config.passphrase.empty() ? nullptr : config.passphrase.c_str() // 私钥密码，空则传nullptr
            );

            if (rc == LIBSSH2_ERROR_EAGAIN) {
                 if (!nonBlocking) {
                    OH_LOG_ERROR(LOG_APP, "SFTP 阻塞模式下密钥认证返回 EAGAIN");
                    session.reset(); close(*socket_fd); *socket_fd = -1; return false;
                 }
                int ws_rc = waitSocket();
                if (ws_rc < 0) {
                     OH_LOG_ERROR(LOG_APP, "SFTP waitSocket 在密钥认证期间失败");
                     session.reset(); close(*socket_fd); *socket_fd = -1; return false;
                }
                if (time(nullptr) - startTime > authTimeout) {
                    OH_LOG_ERROR(LOG_APP, "SFTP 密钥认证超时");
                    session.reset(); close(*socket_fd); *socket_fd = -1; return false;
                }
            } else if (rc != 0) {
                char* errmsg = nullptr;
                libssh2_session_last_error(session.get(), &errmsg, nullptr, 0);
                OH_LOG_ERROR(LOG_APP, "SFTP 密钥认证失败: rc=%{public}d, msg: %{public}s", rc, errmsg ? errmsg : "N/A");
                session.reset(); close(*socket_fd); *socket_fd = -1; return false;
            }
        } while (rc == LIBSSH2_ERROR_EAGAIN);
        OH_LOG_INFO(LOG_APP, "SFTP 密钥认证成功");
    } else {
        OH_LOG_INFO(LOG_APP, "SFTP 尝试使用密码进行认证 (User: %{public}s)", config.username.c_str());
        do {
            rc = libssh2_userauth_password(
                session.get(),
                config.username.c_str(),
                config.password.c_str()
            );

            if (rc == LIBSSH2_ERROR_EAGAIN) {
                if (!nonBlocking) {
                    OH_LOG_ERROR(LOG_APP, "SFTP 阻塞模式下密码认证返回 EAGAIN");
                    session.reset(); close(*socket_fd); *socket_fd = -1; return false;
                }
                int ws_rc = waitSocket();
                 if (ws_rc < 0) {
                     OH_LOG_ERROR(LOG_APP, "SFTP waitSocket 在密码认证期间失败");
                     session.reset(); close(*socket_fd); *socket_fd = -1; return false;
                 }
                if (time(nullptr) - startTime > authTimeout) {
                    OH_LOG_ERROR(LOG_APP, "SFTP 密码认证超时");
                    session.reset(); close(*socket_fd); *socket_fd = -1; return false;
                }
            } else if (rc != 0) {
                 char* errmsg = nullptr;
                 libssh2_session_last_error(session.get(), &errmsg, nullptr, 0);
                 OH_LOG_ERROR(LOG_APP, "SFTP 密码认证失败: rc=%{public}d, msg: %{public}s", rc, errmsg ? errmsg : "N/A");
                 session.reset(); close(*socket_fd); *socket_fd = -1; return false;
            }
        } while (rc == LIBSSH2_ERROR_EAGAIN);
         OH_LOG_INFO(LOG_APP, "SFTP 密码认证成功");
    }
    OH_LOG_INFO(LOG_APP, "SFTP 用户认证成功");

    // --- 8. 初始化 SFTP 子系统 ---
    startTime = time(nullptr);
    // 关键修复：阻塞模式下 libssh2_sftp_init 会无限阻塞（SFTP 子系统无响应时
    // 超时检查在 EAGAIN 分支永远到不了）→ 强制非阻塞 + 1.5 秒超时快速失败
    const int sftpInitTimeout = 2; // SFTP 初始化超时 2 秒（快速失败，避免 UI 卡顿）
    OH_LOG_INFO(LOG_APP, "SFTP 初始化 SFTP 子系统 (超时: %{public}d 秒)...", sftpInitTimeout);
    libssh2_session_set_blocking(session.get(), 0); // 强制非阻塞（让 libssh2_sftp_init 返回 EAGAIN 而非无限阻塞）

    // 先检查 sftp 是否已存在 (重连场景?)，如果存在先关闭旧的
    if (sftp) {
        OH_LOG_WARN(LOG_APP, "SFTP 检测到已存在的 SFTP 实例，将先关闭");
        libssh2_sftp_shutdown(sftp); // 尝试关闭，忽略错误
        sftp = nullptr;
    }

    do {
        sftp = libssh2_sftp_init(session.get());
        rc = sftp ? 0 : libssh2_session_last_errno(session.get()); // 获取错误码

        if (!sftp && rc == LIBSSH2_ERROR_EAGAIN) {
            int ws_rc = waitSocket();
            if (ws_rc < 0) {
                OH_LOG_ERROR(LOG_APP, "SFTP waitSocket 在 SFTP 初始化期间失败");
                session.reset(); close(*socket_fd); *socket_fd = -1; return false;
            }
            if (time(nullptr) - startTime > sftpInitTimeout) {
                OH_LOG_ERROR(LOG_APP, "SFTP 初始化超时 (%d 秒)", sftpInitTimeout);
                session.reset(); close(*socket_fd); *socket_fd = -1; return false;
            }
        } else if (!sftp) {
            char* errmsg = nullptr;
            libssh2_session_last_error(session.get(), &errmsg, nullptr, 0); // 获取更详细错误
            OH_LOG_ERROR(LOG_APP, "SFTP 初始化失败: rc=%{public}d, msg: %{public}s", rc, errmsg ? errmsg : "N/A");
            session.reset(); close(*socket_fd); *socket_fd = -1; return false;
        }
    } while (!sftp); // 循环直到 sftp 初始化成功
    libssh2_session_set_blocking(session.get(), 1); // 恢复阻塞模式（后续操作依赖）

    OH_LOG_INFO(LOG_APP, "SFTP 子系统初始化成功");


    // --- 9. 配置 Keepalive ---
    if (config.keepAliveInterval > 0 && session) {
        OH_LOG_INFO(LOG_APP, "为 SFTP 会话配置 libssh2 Keepalive (Interval: %{public}d)", config.keepAliveInterval);
        libssh2_keepalive_config(session.get(), 1, config.keepAliveInterval);
        
        // --- 新增：启动 Keepalive 线程 ---
        stopThread.store(false); // 确保线程不会立即退出
        std::thread([this]() {
            this->keepAliveThread();
        }).detach();
        OH_LOG_INFO(LOG_APP, "SFTP Keepalive线程已启动");
        // --- 新增完毕 ---
    } else {
         OH_LOG_INFO(LOG_APP, "SFTP Keepalive 已禁用 (Interval: %{public}d).", config.keepAliveInterval);
    }

    OH_LOG_INFO(LOG_APP, "SFTP 连接和初始化过程完成: %{public}s:%{public}d", config.host.c_str(), config.port);
    return true;
}

bool SftpSession::init() {
    // 为兼容性保留，现在只是简单地调用connect()
    return connect();
}

void SftpSession::setNonBlocking(bool nonBlock) {
    std::lock_guard<std::mutex> lock(sessionMutex);
    nonBlocking = nonBlock;
    if (session) {
        libssh2_session_set_blocking(session.get(), nonBlock ? 0 : 1);
    }
}

int SftpSession::waitSocket() {
    if (!session || *socket_fd < 0) return -1;
    
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 500000; // 从 50000 (50ms) 增加到 500000 (500ms)
    
    fd_set fd;
    fd_set* writefd = nullptr;
    fd_set* readfd = nullptr;
    
    FD_ZERO(&fd);
    FD_SET(*socket_fd, &fd);
    
    int dir = libssh2_session_block_directions(session.get());
    
    if (dir & LIBSSH2_SESSION_BLOCK_INBOUND) {
        readfd = &fd;
    }
    if (dir & LIBSSH2_SESSION_BLOCK_OUTBOUND) {
        writefd = &fd;
    }
    
    if (!readfd && !writefd) {
        return 0;
    }
    
    // --- Loop to handle EINTR --- 
    int rc = -1; // Initialize rc
    do {
        // Non-blocking mode check removed from here, handled by caller context
        rc = select(*socket_fd + 1, readfd, writefd, nullptr, &timeout);
    } while (rc < 0 && errno == EINTR);
    // --- End EINTR loop ---

    // Original non-blocking logic removed as EINTR handling is now primary
    // if (nonBlocking) { ... }

    // Original blocking select call (now replaced by loop)
    // return select(*socket_fd + 1, readfd, writefd, nullptr, &timeout);

    // Log error if select failed for reasons other than EINTR
    if (rc < 0) {
        int select_errno = errno;
        OH_LOG_ERROR(LOG_APP, "SftpSession::waitSocket: select failed with rc=%{public}d, errno=%{public}d (%{public}s). Socket=%{public}d",
                     rc, select_errno, strerror(select_errno), *socket_fd);
    }

    return rc;
}

bool SftpSession::checkError(const char* operation) {
    if (!session) return false;
    
    if (libssh2_session_last_errno(session.get()) != 0) {
        char* errmsg;
        // want_buf=0: 返回内部缓冲区，不应手动释放
        libssh2_session_last_error(session.get(), &errmsg, nullptr, 0);
        OH_LOG_ERROR(LOG_APP, "SFTP %s failed: %s", operation, errmsg);
        return false;
    }
    return true;
}

bool SftpSession::listDirectory(const std::string& path, std::function<void(const FileInfo&)> callback) {
    std::lock_guard<std::mutex> lock(sessionMutex);

    if (!sftp || !session) {
        OH_LOG_ERROR(LOG_APP, "SFTP会话未初始化或已失效");
        return false;
    }

    bool originalBlockingMode = nonBlocking;
    if (!nonBlocking) {
        // 临时切换到非阻塞模式进行操作可能更好，但这里我们暂时不修改这个逻辑
        // 如果外部需要阻塞，这里应该恢复，反之亦然
        // 考虑到 listDirectory 内部使用了 executeNonBlocking，这里强制设为非阻塞可能更一致
        libssh2_session_set_blocking(session.get(), 0); // 强制非阻塞
        // nonBlocking = true; // 状态也应更新，但这会影响外部调用者的预期，需谨慎
    }

    bool result = false; // 默认失败
    LIBSSH2_SFTP_HANDLE* handle = nullptr;
    // --- BEGIN MODIFICATION: 移除内部 try-catch，让异常传播 ---
    // try {
        char buffer[4096];
        LIBSSH2_SFTP_ATTRIBUTES attrs;

        handle = executeNonBlocking([&]() {
            if (!sftp) {
                 OH_LOG_ERROR(LOG_APP, "executeNonBlocking for opendir: SFTP is null");
                 return (LIBSSH2_SFTP_HANDLE*)nullptr; // 让 executeNonBlocking 处理后续错误
            }
            return libssh2_sftp_opendir(sftp, path.c_str());
        }, "opendir");

        // 如果 handle 为 null，说明 executeNonBlocking 内部 opendir 或 waitSocket 失败
        if (!handle) {
             unsigned long sftp_error_code = libssh2_sftp_last_error(sftp);
             int session_errno = libssh2_session_last_errno(session.get()); // <<< 获取 Session 错误码
             char* errmsg = nullptr;
             int errmsg_len = 0;
             libssh2_session_last_error(session.get(), &errmsg, &errmsg_len, 0);

             std::string error_message = "Failed to open directory '" + path + "'"; // 添加路径到消息
             if (errmsg && errmsg_len > 0) {
                error_message += ": ";
                error_message.append(errmsg, errmsg_len);
             } else if (session_errno != 0) { // <<< 使用 Session 错误码判断
                 error_message += " (Session error code: " + std::to_string(session_errno) + ")";
             } else {
                 error_message += " (Unknown error)";
             }
             // 将 SFTP 错误码添加到消息中
             error_message += " [SFTP Code: " + std::to_string(sftp_error_code) + "]";

             // <<< 更新日志，包含 Session Code >>>
             OH_LOG_ERROR(LOG_APP, "打开目录 '%{public}s' 失败. Session Error: %{public}d, SFTP Error: %{public}lu, msg: %{public}s",
                          path.c_str(), session_errno, sftp_error_code, error_message.c_str());

             // *** 关键：现在直接抛出异常，让调用者 (NAPI) 处理 ***
             throw std::runtime_error(error_message);
        }

        // opendir 成功，进入 readdir 循环
        while (true) {
            // *** 添加取消检查点 1 ***
            if (cancelRequested.load()) {
                OH_LOG_INFO(LOG_APP, "List directory cancelled before readdir.");
                 // 关闭句柄并抛出取消异常
                 if (handle) {
                     // 尝试非阻塞关闭，忽略错误
                     executeNonBlocking([&]() {
                         if (!handle) return 0;
                         int close_rc = libssh2_sftp_closedir(handle);
                         handle = nullptr;
                         return close_rc;
                     }, "closedir during cancel");
                 }
                throw std::runtime_error("List directory cancelled");
            }

            int rc = executeNonBlocking([&]() {
                 // 内部检查句柄是否仍然有效
                 if (!handle) return -1;
                return libssh2_sftp_readdir(handle, buffer, sizeof(buffer), &attrs);
            }, "readdir");

            if (rc > 0) {
                // 处理读取到的条目
                std::string name(buffer);
                if (name != "." && name != "..") {
                    FileInfo info;
                    info.name = name;
                    info.isDirectory = (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && 
                                      S_ISDIR(attrs.permissions);
                    info.size = (attrs.flags & LIBSSH2_SFTP_ATTR_SIZE) ? attrs.filesize : 0;
                    info.permissions = (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) ? attrs.permissions : 0;
                    info.mtime = (attrs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) ? attrs.mtime : 0;
                    info.atime = (attrs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) ? attrs.atime : 0;
                    info.owner = "";
                    info.group = "";
                    
                    callback(info);
                    // *** 添加取消检查点 2 (在回调后) ***
                    // 可以在这里再次检查 cancelRequested.load()
                }
            } else if (rc == 0) {
                // 读取完成 (EOF)
                result = true; // 标记成功
                break;
            } else { // rc < 0
                 // 读取失败
                 int session_errno = libssh2_session_last_errno(session.get()); // <<< 获取 Session 错误码
                 unsigned long sftp_errno = libssh2_sftp_last_error(sftp);      // <<< 获取 SFTP 错误码
                 
                 // <<< 更新日志，包含 Session 和 SFTP Code >>>
                 OH_LOG_ERROR(LOG_APP, "读取目录 '%{public}s' 时发生错误. Session Error: %{public}d, SFTP Error: %{public}lu", 
                              path.c_str(), session_errno, sftp_errno);

                 // 如果不是 EAGAIN，则认为是致命错误，中断循环
                 if (session_errno != LIBSSH2_ERROR_EAGAIN) { 
                     // 可以考虑在这里也抛出异常，而不是仅仅中断
                     // throw std::runtime_error("Failed during directory read (Session: " + std::to_string(session_errno) + ", SFTP: " + std::to_string(sftp_errno) + ")");
                     break; // 当前行为：中断循环，result 保持 false
                 } else {
                     // 如果是 EAGAIN，在非阻塞模式下理论上 executeNonBlocking 内部会处理
                     // 如果执行到这里，可能表示意外的 EAGAIN 或其他问题，也中断循环
                     OH_LOG_WARN(LOG_APP, "Unexpected EAGAIN during readdir loop for path '%{public}s'. Breaking loop.", path.c_str());
                     break; 
                 }
            }
        }

        // 关闭目录句柄（如果仍然打开）
        if (handle) {
            // 尝试非阻塞关闭
            executeNonBlocking([&]() {
                 if (!handle) return 0; // 如果已被取消逻辑关闭
                 int close_rc = libssh2_sftp_closedir(handle);
                 handle = nullptr; // 标记已关闭
                 return close_rc;
            }, "closedir");
             // 注意：这里忽略了 closedir 的错误，如果需要可以处理
        }

    // } catch (const std::exception& e) { // <-- 移除外部 catch
    //      // ... 不再在这里处理，让 NAPI 层处理 ...
    // }

    // --- END MODIFICATION ---

    // 恢复原始阻塞模式 (如果需要)
    if (!originalBlockingMode && session) {
        // 之前的逻辑是强制非阻塞，这里需要决定是否恢复
        // 如果最初是非阻塞，则无需操作
        // 如果最初是阻塞，这里应该恢复阻塞
        // 假设 SftpSession 实例的 nonBlocking 状态是权威的
        libssh2_session_set_blocking(session.get(), this->nonBlocking ? 0 : 1);
    }

    return result; // 返回操作是否成功（可能部分成功）
}

bool SftpSession::uploadFile(int localFd, const std::string& remotePath, std::function<void(int)> progressCallback) {
    std::lock_guard<std::mutex> lock(sessionMutex);
    if (!session) { // Check session first
        OH_LOG_ERROR(LOG_APP, "SFTP 上传失败: SSH 会话无效");
        return false;
    }

    // --- BEGIN Operation Control Flags ---
    currentOperationActiveFlag = std::make_shared<std::atomic<bool>>(true);
    cancelRequested.store(false);
    operationTimedOut.store(false); // Use the renamed flag
    OH_LOG_INFO(LOG_APP, "UploadFile: Reset cancelRequested and operationTimedOut flags.");
    // --- END Operation Control Flags ---

    // 新增：如果有进度回调，立即发送0%进度
    if (progressCallback) {
        progressCallback(0);
    }

    bool overallResult = false; // Initialize overall result to failure
    LIBSSH2_SFTP_HANDLE* handle = nullptr;
    std::string tempRemotePath = remotePath + ".tmp"; // <<<--- 使用临时文件路径
    bool uploadCompletedSuccessfully = false; // Flag to track if the upload part finished ok
    std::string errorMessage; // Store potential error message
    std::shared_ptr<std::atomic<bool>> activeFlagForCleanup = currentOperationActiveFlag; // Keep a copy for finally block

    // --- BEGIN: EMA Speed Calculation Variables ---
    double ema_speed_bps = 0.0; // Exponential Moving Average Speed in Bytes per second
    const double ema_alpha = 0.2; // Smoothing factor (adjust as needed)
    auto lastSpeedUpdateTime = std::chrono::steady_clock::now();
    ssize_t bytesSinceLastSpeedUpdate = 0;
    // --- END: EMA Speed Calculation Variables ---

    try {
        if (localFd < 0) {
            OH_LOG_ERROR(LOG_APP, "无效的文件描述符: %d", localFd);
            throw std::runtime_error("Invalid file descriptor");
        }

        // 获取文件大小
        off_t totalSize = lseek(localFd, 0, SEEK_END);
        if (totalSize < 0) {
            OH_LOG_ERROR(LOG_APP, "无法获取文件大小: %d", errno);
            throw std::runtime_error("Failed to get file size");
        }
        if (lseek(localFd, 0, SEEK_SET) < 0) {
            OH_LOG_ERROR(LOG_APP, "无法重置文件指针: %d", errno);
            throw std::runtime_error("Failed to reset file pointer");
        }

        // 新增：获取文件大小后再次发送0%进度
        if (progressCallback) {
            progressCallback(0);
        }

        // --- 修改: 日志信息使用临时路径 ---
        OH_LOG_INFO(LOG_APP, "开始上传文件到临时路径 %{public}s, 目标路径: %{public}s, 文件大小: %{public}.2f MB",
                   tempRemotePath.c_str(), remotePath.c_str(), totalSize / 1024.0 / 1024.0);

        // 修改：优化文件大小判断逻辑，增加HUGE_FILE处理
        bool isLargeFile = (totalSize > LARGE_FILE_THRESHOLD);
        bool isHugeFile = (totalSize > HUGE_FILE_THRESHOLD);
        int uploadTimeout = isLargeFile ? LARGE_FILE_OPERATION_TIMEOUT_S : globalOperationTimeout;
        // --- Pass the active flag to setOperationTimeout ---
        setOperationTimeout(operationTimedOut, currentOperationActiveFlag, uploadTimeout);

        // --- 修改: 打开临时文件进行写入 ---
        handle = executeNonBlocking([&]() {
            // Check flags inside lambda too
            if (!sftp || operationTimedOut.load() || cancelRequested.load()) return (LIBSSH2_SFTP_HANDLE*)nullptr;
            // 打开临时文件路径
            return libssh2_sftp_open(sftp, tempRemotePath.c_str(),
                LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC, // 对临时文件使用TRUNC
                LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR);
        }, "open temp file for write");

        if (!handle) {
            if (cancelRequested.load()) {
                throw std::runtime_error("Upload cancelled during temporary file open");
            }
            if (operationTimedOut.load()) {
                throw std::runtime_error("Upload timed out during temporary file open");
            }
            unsigned long sftp_error_code = libssh2_sftp_last_error(sftp);
            int session_error_code = libssh2_session_last_errno(session.get()); // <<< 获取 Session 错误码
            char* session_errmsg = nullptr;
            libssh2_session_last_error(session.get(), &session_errmsg, nullptr, 0);
            std::string error_details = session_errmsg ? std::string(session_errmsg) : "N/A";
            // <<< 更新抛出的异常信息 >>>
            std::string error_msg = "Failed to open temporary remote file '" + tempRemotePath + 
                                    "' for write (SFTP Code: " + std::to_string(sftp_error_code) + 
                                    ", Session Code: " + std::to_string(session_error_code) + 
                                    ", Msg: " + error_details + ")";
             OH_LOG_ERROR(LOG_APP, "UploadFile Error: %{public}s", error_msg.c_str()); // 记录详细错误
             throw std::runtime_error(error_msg);
        }

        // 修改：根据文件大小选择最佳缓冲区大小
        size_t bufferSize;
        if (isHugeFile) {
            bufferSize = HUGE_BUFFER_SIZE;
            OH_LOG_INFO(LOG_APP, "使用特大文件缓冲区大小: %{public}zu KB", bufferSize / 1024);
        } else if (isLargeFile) {
            bufferSize = LARGE_BUFFER_SIZE;
            OH_LOG_INFO(LOG_APP, "使用大文件缓冲区大小: %{public}zu KB", bufferSize / 1024);
        } else {
            bufferSize = DEFAULT_BUFFER_SIZE;
        }
        
        std::unique_ptr<char[]> buffer(new char[bufferSize]);
        ssize_t rc;
        ssize_t uploadedSize = 0;
        int lastProgress = 0;
        int currentProgress = 0;
        int consecutiveErrors = 0;
        const int maxConsecutiveErrors = 5;
        auto startTime = std::chrono::steady_clock::now();
        const size_t progressThreshold = 102400; // 100KB
        size_t bytesSinceLastProgressCall = 0;
        
        // 新增：进度报告时间控制
        auto lastProgressTime = std::chrono::steady_clock::now();
        const auto progressTimeThreshold = std::chrono::milliseconds(250);

        // Main loop checks cancel and timeout flags
        while (!operationTimedOut.load() && !cancelRequested.load() && (rc = read(localFd, buffer.get(), bufferSize)) > 0) {
            ssize_t total = 0;
            bytesSinceLastSpeedUpdate += rc;

            // 大文件日志 (保持不变)
            if (isLargeFile && uploadedSize > 0 && (uploadedSize % (20 * 1024 * 1024) == 0 || (uploadedSize + rc) / (20 * 1024 * 1024) != uploadedSize / (20 * 1024 * 1024)) ) {
                 OH_LOG_INFO(LOG_APP, "上传中 (临时路径 %{public}s): 已上传 %{public}.2f MB / %{public}.2f MB (%{public}.1f%%)",
                           tempRemotePath.c_str(),
                           uploadedSize / 1024.0 / 1024.0,
                           totalSize / 1024.0 / 1024.0,
                           (uploadedSize * 100.0) / totalSize);
            }
            // Inner loop also checks flags
            while (total < rc && !operationTimedOut.load() && !cancelRequested.load()) {
                size_t batchSize = static_cast<size_t>(rc - total);

                ssize_t written = executeNonBlocking([&]() {
                    // Check flags inside lambda
                    if (!sftp || !handle || operationTimedOut.load() || cancelRequested.load()) return (ssize_t)-1;
                    return libssh2_sftp_write(handle, buffer.get() + total, batchSize);
                }, "write to temp file");

                if (written < 0) {
                    // Check flags immediately after potential failure
                    if (cancelRequested.load()) {
                         throw std::runtime_error("Upload cancelled during write");
                    }
                    if (operationTimedOut.load()) {
                         throw std::runtime_error("Upload timed out during write");
                    }

                    // --- BEGIN MODIFICATION: Check for EAGAIN before retrying ---
                    int session_write_err = libssh2_session_last_errno(session.get());
                    unsigned long sftp_write_err_code = libssh2_sftp_last_error(sftp); // Get SFTP error too

                    if (session_write_err == LIBSSH2_ERROR_EAGAIN) {
                        // Only retry on EAGAIN
                        consecutiveErrors++;
                        // <<< 更新日志，包含 Session 和 SFTP Code >>>
                        OH_LOG_WARN(LOG_APP, "写入临时文件 '%{public}s' 返回 EAGAIN，将重试 (尝试次数: %{public}d/%{public}d, SFTP: %{public}lu, Session: %{public}d)",
                                    tempRemotePath.c_str(), consecutiveErrors, maxConsecutiveErrors, sftp_write_err_code, session_write_err);
                        if (consecutiveErrors >= maxConsecutiveErrors) {
                            // Throw error if EAGAIN persists too long
                            char* session_errmsg = nullptr;
                            libssh2_session_last_error(session.get(), &session_errmsg, nullptr, 0);
                            std::string error_details = session_errmsg ? std::string(session_errmsg) : "N/A";
                            // <<< 更新抛出的异常信息 >>>
                            std::string error_msg = "Write to temporary remote file '" + tempRemotePath + 
                                                    "' failed due to persistent EAGAIN (SFTP Code: " + std::to_string(sftp_write_err_code) + 
                                                    ", Session Code: " + std::to_string(session_write_err) + 
                                                    ", Msg: " + error_details + ")";
                            OH_LOG_ERROR(LOG_APP, "UploadFile Error: %{public}s", error_msg.c_str()); // 记录详细错误
                            throw std::runtime_error(error_msg);
                        }
                        // Short sleep might prevent busy-looping if EAGAIN happens extremely quickly.
                        std::this_thread::sleep_for(std::chrono::milliseconds(50)); // Shorter sleep for EAGAIN retry
                        continue; // Retry the write operation
                    } else {
                        // For any error other than EAGAIN, fail immediately
                        // <<< 更新日志，包含 Session 和 SFTP Code >>>
                        OH_LOG_ERROR(LOG_APP, "写入临时文件 '%{public}s' 发生不可恢复错误 (SFTP: %{public}lu, Session: %{public}d)",
                                    tempRemotePath.c_str(), sftp_write_err_code, session_write_err);
                        char* session_errmsg = nullptr;
                        libssh2_session_last_error(session.get(), &session_errmsg, nullptr, 0);
                        std::string error_details = session_errmsg ? std::string(session_errmsg) : "N/A";
                        // <<< 更新抛出的异常信息 >>>
                        std::string error_msg = "Write to temporary remote file '" + tempRemotePath + 
                                                "' failed (SFTP Code: " + std::to_string(sftp_write_err_code) + 
                                                ", Session Code: " + std::to_string(session_write_err) + 
                                                ", Msg: " + error_details + ")";
                        OH_LOG_ERROR(LOG_APP, "UploadFile Error: %{public}s", error_msg.c_str()); // 记录详细错误
                        throw std::runtime_error(error_msg);
                    }
                    // --- END MODIFICATION ---
                }
                consecutiveErrors = 0;
                total += written;
                uploadedSize += written;
            }

            // Check cancellation after inner loop
            if (cancelRequested.load()) {
                OH_LOG_INFO(LOG_APP, "Upload cancelled after write loop to temp file.");
                throw std::runtime_error("Upload cancelled");
            }
            // Check timeout after inner loop
             if (operationTimedOut.load()) {
                OH_LOG_INFO(LOG_APP, "Upload timed out after write loop to temp file.");
                throw std::runtime_error("Upload timed out");
            }

            bytesSinceLastProgressCall += rc;

            // --- EMA Speed Calculation --- (保持不变)
            auto currentTime = std::chrono::steady_clock::now();
            auto elapsedSinceLastSpeedUpdateMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                currentTime - lastSpeedUpdateTime).count();
            double currentSpeedMBps = 0.0;
            if (elapsedSinceLastSpeedUpdateMs >= 500) {
                if (elapsedSinceLastSpeedUpdateMs > 0) {
                    double instantaneous_speed_bps = (static_cast<double>(bytesSinceLastSpeedUpdate) * 1000.0) / elapsedSinceLastSpeedUpdateMs;
                    if (!std::isnan(instantaneous_speed_bps) && !std::isinf(instantaneous_speed_bps)) {
                        if (ema_speed_bps == 0.0) {
                            ema_speed_bps = instantaneous_speed_bps;
                        } else {
                            ema_speed_bps = (instantaneous_speed_bps * ema_alpha) + (ema_speed_bps * (1.0 - ema_alpha));
                        }
                    }
                }
                lastSpeedUpdateTime = currentTime;
                bytesSinceLastSpeedUpdate = 0;
            }
             if (ema_speed_bps > 0) {
                 currentSpeedMBps = ema_speed_bps / (1024.0 * 1024.0);
             }
            // --- END EMA Speed Calculation ---

            currentProgress = (totalSize > 0) ? static_cast<int>((uploadedSize * 100) / totalSize) : 0;
            currentProgress = std::max(0, std::min(100, currentProgress));

            // 修改：增加基于时间的进度报告逻辑
            bool shouldReportProgress = false;
            auto progressElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                currentTime - lastProgressTime).count();
            
            // 时间阈值检查：距离上次报告已超过时间阈值
            bool timeThresholdMet = (progressElapsedMs >= progressTimeThreshold.count());
            
            // 数据量阈值检查：已传输超过数据量阈值
            bool dataThresholdMet = (bytesSinceLastProgressCall >= progressThreshold);
            
            // 进度变化检查：进度百分比有变化
            bool progressChanged = (currentProgress != lastProgress);
            
            // 满足以下任一条件触发进度报告：
            // 1. 数据量达到阈值
            // 2. 时间达到阈值且进度有变化
            // 3. 大文件传输过程中的强制更新（超过1秒未更新）
            shouldReportProgress = dataThresholdMet || 
                                  (timeThresholdMet && progressChanged) || 
                                  (progressElapsedMs >= 1000); // 至少每秒更新一次

            if (progressCallback && shouldReportProgress) {
                OH_LOG_INFO(LOG_APP, "上传中 (临时路径 %{public}s): 已上传 %.2f MB / %.2f MB (%.1f%%)",
                           tempRemotePath.c_str(),
                           uploadedSize / 1024.0 / 1024.0,
                           totalSize / 1024.0 / 1024.0,
                           currentProgress * 1.0);
                
                // 调用进度回调
                progressCallback(currentProgress);
                
                // 更新状态
                lastProgress = currentProgress;
                bytesSinceLastProgressCall = 0;
                lastProgressTime = currentTime;
            }
        } // End of main upload loop (while read > 0)

        // --- 检查循环结束后的状态 --- 
        // Check cancel first, as timeout might also set cancel
        if (cancelRequested.load()) {
            errorMessage = operationTimedOut.load() ? "Upload timed out" : "Upload cancelled";
            OH_LOG_INFO(LOG_APP, "Upload loop terminated: %{public}s", errorMessage.c_str());
            // Throw exception to trigger cleanup logic
            throw std::runtime_error(errorMessage);
        }
        // Check for local read error
        if (rc < 0) { 
            OH_LOG_ERROR(LOG_APP, "读取本地文件失败: %{public}s", strerror(errno));
            throw std::runtime_error("Failed to read local file");
        }
        // If loop finished normally (rc == 0), mark as completed
        uploadCompletedSuccessfully = true; // <<<--- 标记上传本身成功

        // 确保发送最终进度 100%
        if (progressCallback && lastProgress < 100) {
            progressCallback(100);
        }

        auto endTime = std::chrono::steady_clock::now();
        auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
        double totalElapsedSeconds = durationMs / 1000.0;
        double avgSpeedBps = 0.0;
        if (durationMs > 50) { avgSpeedBps = (static_cast<double>(uploadedSize) * 1000.0) / durationMs; }

         std::string avgSpeedUnit;
         double avgDisplaySpeed;
         if (avgSpeedBps >= 1048576.0) { avgDisplaySpeed = avgSpeedBps / 1048576.0; avgSpeedUnit = "MB/s"; }
         else if (avgSpeedBps >= 1024.0) { avgDisplaySpeed = avgSpeedBps / 1024.0; avgSpeedUnit = "KB/s"; }
         else { avgDisplaySpeed = avgSpeedBps; avgSpeedUnit = "B/s"; }
         OH_LOG_INFO(LOG_APP, "文件上传到临时路径完成: %{public}s (%{public}.2f MB), 耗时: %.1f秒, 平均速度: %.2f %s",
                    tempRemotePath.c_str(), totalSize / 1024.0 / 1024.0,
                    totalElapsedSeconds, avgDisplaySpeed, avgSpeedUnit.c_str());

        // 注意：此时 handle 仍然打开

    } catch (const std::exception& e) {
        errorMessage = e.what();
        if (errorMessage.find("cancelled") != std::string::npos) {
            OH_LOG_INFO(LOG_APP, "文件上传到临时文件被取消: %{public}s", errorMessage.c_str());
        } else if (errorMessage.find("timeout") != std::string::npos || errorMessage.find(" timed out") != std::string::npos) {
             OH_LOG_ERROR(LOG_APP, "文件上传到临时文件超时: %{public}s", errorMessage.c_str());
        } else {
            OH_LOG_ERROR(LOG_APP, "文件上传到临时文件过程中发生异常: %{public}s", errorMessage.c_str());
        }
        uploadCompletedSuccessfully = false; // 标记上传失败
    } catch (...) {
        errorMessage = "文件上传到临时文件过程中发生未知异常";
        OH_LOG_ERROR(LOG_APP, "%s", errorMessage.c_str());
        uploadCompletedSuccessfully = false; // 标记上传失败
    }

    // --- 清理和重命名逻辑 --- 
    unsigned long sftp_error_code_cleanup = 0; // 统一存储清理阶段的错误码
    bool rename_succeeded = false; // 跟踪重命名是否成功

    // 1. 关闭 SFTP 句柄 (即使上传失败也要尝试关闭)
    if (handle) {
        OH_LOG_INFO(LOG_APP, "准备关闭临时文件 SFTP 句柄: %s", tempRemotePath.c_str());
        int close_rc = executeNonBlocking([&]() {
            if (!handle) return 0;
            int rc = libssh2_sftp_close(handle);
            handle = nullptr; // Mark as closed regardless of return code
            return rc;
        }, "close temp file handle");
        sftp_error_code_cleanup = libssh2_sftp_last_error(sftp); // 获取关闭操作的错误码
        if (close_rc != 0) {
            OH_LOG_ERROR(LOG_APP, "关闭临时文件 '%s' 的 SFTP 句柄时出错 (rc=%d, SFTP Code: %lu)",
                         tempRemotePath.c_str(), close_rc, sftp_error_code_cleanup);
            // 如果关闭句柄失败，通常后续操作也可能失败，但我们仍然尝试继续
            if (uploadCompletedSuccessfully) { // 如果上传本身是成功的，但关闭失败了
                 errorMessage = "Failed to close temporary file handle (SFTP Code: " + std::to_string(sftp_error_code_cleanup) + ")";
                 uploadCompletedSuccessfully = false; // 将整体标记为失败
            }
        } else {
            OH_LOG_INFO(LOG_APP, "成功关闭临时文件 SFTP 句柄: %s", tempRemotePath.c_str());
        }
        handle = nullptr; // 确保句柄设为 null
    } else {
        OH_LOG_WARN(LOG_APP, "UploadFile 清理阶段: 临时文件句柄已经为 null (可能在打开时就失败了).");
        // 如果句柄为 null，上传肯定不成功
        uploadCompletedSuccessfully = false;
        if (errorMessage.empty()) errorMessage = "Temporary file handle was null before cleanup.";
    }

    // 2. 只有在上传数据成功后才尝试重命名
    if (uploadCompletedSuccessfully) {
         OH_LOG_INFO(LOG_APP, "上传到临时文件成功，准备检查/删除目标文件并重命名。");
        // 2a. 检查目标文件是否存在
        LIBSSH2_SFTP_ATTRIBUTES attrs;
        OH_LOG_INFO(LOG_APP, "准备检查目标文件 '%s' 是否存在 (stat)", remotePath.c_str());
        int stat_rc = executeNonBlocking([&]() {
             if (!sftp) return -1;
             return libssh2_sftp_stat(sftp, remotePath.c_str(), &attrs);
        }, "stat target file");
        sftp_error_code_cleanup = libssh2_sftp_last_error(sftp); // 获取 stat 的错误码
        int session_stat_err = libssh2_session_last_errno(session.get()); // <<< 获取 Session 错误码

        bool delete_target_needed = false;
        if (stat_rc == 0) {
            OH_LOG_INFO(LOG_APP, "目标文件 '%s' 已存在，需要先删除。", remotePath.c_str());
            delete_target_needed = true;
        } else if (sftp_error_code_cleanup == LIBSSH2_FX_NO_SUCH_FILE) {
            OH_LOG_INFO(LOG_APP, "目标文件 '%s' 不存在，无需删除。", remotePath.c_str());
            delete_target_needed = false;
        } else {
             // <<< 更新日志和错误信息 >>>
            OH_LOG_ERROR(LOG_APP, "检查目标文件 '%s' 状态时出错 (stat_rc=%d, SFTP Code: %lu, Session Code: %d)",
                         remotePath.c_str(), stat_rc, sftp_error_code_cleanup, session_stat_err);
            errorMessage = "Error checking target file status (SFTP Code: " + std::to_string(sftp_error_code_cleanup) + 
                           ", Session Code: " + std::to_string(session_stat_err) + ")";
            uploadCompletedSuccessfully = false; // 标记失败
        }

        // 2b. 如果需要，删除目标文件
        if (uploadCompletedSuccessfully && delete_target_needed) {
             OH_LOG_INFO(LOG_APP, "准备删除已存在的目标文件: %s", remotePath.c_str());
             int unlink_rc = executeNonBlocking([&]() {
                  if (!sftp) return -1;
                 return libssh2_sftp_unlink(sftp, remotePath.c_str());
             }, "unlink target file");
             sftp_error_code_cleanup = libssh2_sftp_last_error(sftp);
             int session_unlink_err = libssh2_session_last_errno(session.get()); // <<< 获取 Session 错误码
             if (unlink_rc != 0) {
                 // <<< 更新日志和错误信息 >>>
                 OH_LOG_ERROR(LOG_APP, "删除已存在的目标文件 '%s' 时出错 (unlink_rc=%d, SFTP Code: %lu, Session Code: %d)",
                              remotePath.c_str(), unlink_rc, sftp_error_code_cleanup, session_unlink_err);
                 errorMessage = "Failed to delete existing target file (SFTP Code: " + std::to_string(sftp_error_code_cleanup) + 
                                ", Session Code: " + std::to_string(session_unlink_err) + ")";
                 uploadCompletedSuccessfully = false; // 标记失败
             } else {
                 OH_LOG_INFO(LOG_APP, "成功删除已存在的目标文件: %s", remotePath.c_str());
             }
        }

        // 2c. 重命名临时文件到目标文件
        if (uploadCompletedSuccessfully) {
             OH_LOG_INFO(LOG_APP, "准备将临时文件 '%s' 重命名为 '%s'", tempRemotePath.c_str(), remotePath.c_str());
             int rename_rc = executeNonBlocking([&]() {
                 if (!sftp) return -1;
                 return libssh2_sftp_rename(sftp, tempRemotePath.c_str(), remotePath.c_str());
             }, "rename temp to target");
             sftp_error_code_cleanup = libssh2_sftp_last_error(sftp); // 获取 rename 的错误码
             int session_rename_err = libssh2_session_last_errno(session.get()); // <<< 获取 Session 错误码
             if (rename_rc != 0) {
                 // <<< 更新日志和错误信息 >>>
                 OH_LOG_ERROR(LOG_APP, "将临时文件 '%s' 重命名为 '%s' 时出错 (rename_rc=%d, SFTP Code: %lu, Session Code: %d)",
                              tempRemotePath.c_str(), remotePath.c_str(), rename_rc, sftp_error_code_cleanup, session_rename_err);
                 errorMessage = "Failed to rename temporary file to target (SFTP Code: " + std::to_string(sftp_error_code_cleanup) + 
                                ", Session Code: " + std::to_string(session_rename_err) + ")";
                 uploadCompletedSuccessfully = false; // 标记失败，即使上传本身成功
                 rename_succeeded = false;
             } else {
                 OH_LOG_INFO(LOG_APP, "成功将临时文件重命名为: %s", remotePath.c_str());
                 rename_succeeded = true; // 标记重命名成功
             }
        }
    } // end if (uploadCompletedSuccessfully)

    // 最终决定 overallResult
    overallResult = uploadCompletedSuccessfully && rename_succeeded;

    // --- END Final Cleanup ---
    // Ensure the active flag is set to false when the function exits
    if (activeFlagForCleanup) {
        activeFlagForCleanup->store(false);
    }
    OH_LOG_DEBUG(LOG_APP, "UploadFile finished or exited, marking operation inactive.");

    if (!overallResult) {
        // 上传未成功（失败、取消、超时、删除目标失败或重命名失败），删除临时文件
        OH_LOG_WARN(LOG_APP, "上传操作未最终成功 (原因: %{public}s)，尝试删除临时文件: %{public}s",
                    errorMessage.empty() ? "Unknown error during upload or cleanup steps" : errorMessage.c_str(), tempRemotePath.c_str());

        // --- BEGIN MODIFICATION: Add more logging for final unlink ---
        OH_LOG_INFO(LOG_APP, "准备执行最终的 unlink 操作以删除临时文件: %{public}s", tempRemotePath.c_str());
        unsigned long sftp_error_code_final_unlink = 0; // Initialize
        int session_final_unlink_err = 0; // <<< 获取 Session 错误码
        int final_unlink_rc = executeNonBlocking([&]() {
             if (!sftp) return -1;
            // Reset last sftp error before calling unlink (optional, but good practice)
            // libssh2_sftp_last_error(sftp); // Seems libssh2 might reset this implicitly
            return libssh2_sftp_unlink(sftp, tempRemotePath.c_str());
        }, "unlink unsuccessful temp file");
        // Get the error code immediately after the operation attempt
        sftp_error_code_final_unlink = libssh2_sftp_last_error(sftp);
        session_final_unlink_err = libssh2_session_last_errno(session.get()); // <<< 获取 Session 错误码
        // <<< 更新日志 >>>
        OH_LOG_INFO(LOG_APP, "最终 unlink 操作完成，返回码: %{public}d, SFTP 错误码: %{public}lu, Session 错误码: %{public}d", 
                    final_unlink_rc, sftp_error_code_final_unlink, session_final_unlink_err);
        // --- END MODIFICATION ---

        if (final_unlink_rc != 0) {
             // If the error is "No such file", it might be because open failed, so ignore
             if (sftp_error_code_final_unlink != LIBSSH2_FX_NO_SUCH_FILE) {
                 // <<< 更新日志 >>>
                 OH_LOG_ERROR(LOG_APP, "删除最终失败操作的临时文件 '%{public}s' 时出错 (SFTP Code: %{public}lu, Session Code: %{public}d)",
                              tempRemotePath.c_str(), sftp_error_code_final_unlink, session_final_unlink_err);
             } else {
                 OH_LOG_INFO(LOG_APP, "删除临时文件 '%{public}s' 时未找到该文件 (可能从未创建或已被删除)，忽略", tempRemotePath.c_str());
             }
        } else {
            OH_LOG_INFO(LOG_APP, "成功删除最终失败操作的临时文件: %{public}s", tempRemotePath.c_str());
        }
    }

    return overallResult; 
}

bool SftpSession::downloadFile(const std::string& remotePath, int localFd, std::function<void(off_t)> progressCallback) {
     std::lock_guard<std::mutex> lock(sessionMutex);
     if (!session) { // Check session first
        OH_LOG_ERROR(LOG_APP, "SFTP 下载失败: SSH 会话无效");
        return false;
    }

     // --- BEGIN Operation Control Flags ---
     currentOperationActiveFlag = std::make_shared<std::atomic<bool>>(true);
     cancelRequested.store(false);
     operationTimedOut.store(false);
     OH_LOG_INFO(LOG_APP, "DownloadFile: Reset cancelRequested and operationTimedOut flags.");
     // --- END Operation Control Flags ---

    bool result = false;
    LIBSSH2_SFTP_HANDLE* handle = nullptr;
    std::shared_ptr<std::atomic<bool>> activeFlagForCleanup = currentOperationActiveFlag; // Keep a copy
     // --- BEGIN: EMA Speed Calculation Variables ---
    double ema_speed_bps = 0.0; // Exponential Moving Average Speed in Bytes per second
    const double ema_alpha = 0.2; // Smoothing factor (adjust as needed)
    auto lastSpeedUpdateTime = std::chrono::steady_clock::now();
    ssize_t bytesDownloadedSinceLastSpeedUpdate = 0;
     // --- END: EMA Speed Calculation Variables ---

    try {
        if (localFd < 0) {
            OH_LOG_ERROR(LOG_APP, "无效的文件描述符: %{public}d", localFd);
            throw std::runtime_error("Invalid file descriptor");
        }

        OH_LOG_INFO(LOG_APP, "开始下载文件: %{public}s (文件描述符: %{public}d)", remotePath.c_str(), localFd);
        // --- Determine timeout duration --- 
        // We need the file size first to determine if it's a large file
        // Let's get file info *before* starting the timer
        LIBSSH2_SFTP_ATTRIBUTES attrs;
        // <<< 添加对 stat 错误的诊断 >>>
        int stat_rc = executeNonBlocking([&]() { // Get attributes first
            if (!sftp || cancelRequested.load()) return -1; // Check cancel early
            return libssh2_sftp_stat(sftp, remotePath.c_str(), &attrs); 
        }, "stat before download");
        if (stat_rc < 0) {
            if (cancelRequested.load()) throw std::runtime_error("Download cancelled during initial stat");
            unsigned long sftp_stat_err = libssh2_sftp_last_error(sftp);
            int session_stat_err = libssh2_session_last_errno(session.get());
            OH_LOG_ERROR(LOG_APP, "无法获取远程文件属性 '%{public}s' (SFTP Code: %{public}lu, Session Code: %{public}d)", 
                         remotePath.c_str(), sftp_stat_err, session_stat_err);
            throw std::runtime_error("Failed to get remote file attributes (SFTP: " + 
                                     std::to_string(sftp_stat_err) + ", Session: " + std::to_string(session_stat_err) + ")");
        }
        off_t totalSize = attrs.filesize;
        bool isLargeFile = (totalSize > LARGE_FILE_THRESHOLD);
        int downloadTimeout = isLargeFile ? LARGE_FILE_OPERATION_TIMEOUT_S : globalOperationTimeout;
        OH_LOG_INFO(LOG_APP, "文件大小: %{public}lld 字节. 超时设置为: %d 秒", (long long)totalSize, downloadTimeout);
        // --- Now start the timer --- 
        setOperationTimeout(operationTimedOut, currentOperationActiveFlag, downloadTimeout);

        // --- Open the file --- 
        handle = executeNonBlocking([&]() {
            // Check flags inside lambda
            if (!sftp || operationTimedOut.load() || cancelRequested.load()) return (LIBSSH2_SFTP_HANDLE*)nullptr;
            return libssh2_sftp_open(sftp, remotePath.c_str(),
                LIBSSH2_FXF_READ, 0);
        }, "open for read");
        
        if (!handle) {
            if (cancelRequested.load()) {
                 throw std::runtime_error("Download cancelled during file open");
            }
             if (operationTimedOut.load()) {
                 throw std::runtime_error("Download timed out during file open");
            }
            // <<< 添加对 open 错误的诊断 >>>
            unsigned long sftp_open_err = libssh2_sftp_last_error(sftp);
            int session_open_err = libssh2_session_last_errno(session.get());
            OH_LOG_ERROR(LOG_APP, "无法打开远程文件 '%{public}s' (SFTP Code: %{public}lu, Session Code: %{public}d)",
                         remotePath.c_str(), sftp_open_err, session_open_err);
            throw std::runtime_error("Failed to open remote file for read (SFTP: " + 
                                     std::to_string(sftp_open_err) + ", Session: " + std::to_string(session_open_err) + ")");
        }
        
        // --- BEGIN MODIFICATION: Use heap allocation for buffer ---
        std::unique_ptr<char[]> buffer_ptr(new char[LARGE_BUFFER_SIZE]);
        char* buffer = buffer_ptr.get(); // Get raw pointer for libssh2/write calls
        if (!buffer) {
            OH_LOG_ERROR(LOG_APP, "无法为下载缓冲区分配内存 (%{public}zu bytes)", (size_t)LARGE_BUFFER_SIZE);
            throw std::runtime_error("Failed to allocate download buffer");
        }
        // --- END MODIFICATION ---
        ssize_t rc;
        ssize_t downloadedSize = 0;
        int lastProgress = 0;
        int consecutiveEagain = 0;
        const int maxConsecutiveEagain = 100; // 允许的最大连续EAGAIN错误次数
        
        // 速度计算相关变量
        auto startTime = std::chrono::steady_clock::now();

        // Add cancellation check before the loop starts
        if (cancelRequested.load()) { // Check the atomic flag directly
            OH_LOG_WARN(LOG_APP, "downloadFile cancelled before loop start");
            throw std::runtime_error("Download cancelled"); // Throw exception for consistent cleanup
        }

        // Variables for progress report thresholding
        static const off_t progress_report_threshold = 262144; // Report approx every 256KB
        off_t last_reported_size = 0;

        // Main loop checks cancel and timeout
        while (!operationTimedOut.load() && !cancelRequested.load()) {
            rc = executeNonBlocking([&]() {
                 // 内部 lambda 也快速检查一下
                if (!sftp || !handle || operationTimedOut.load() || cancelRequested.load()) return (ssize_t)-1;
                // --- Use the raw pointer 'buffer' here --- 
                return libssh2_sftp_read(handle, buffer, LARGE_BUFFER_SIZE);
            }, "read");

            if (rc > 0) {
                consecutiveEagain = 0; // Reset counter

                ssize_t totalWrittenThisChunk = 0;
                // Inner loop also checks flags
                while (totalWrittenThisChunk < rc && !operationTimedOut.load() && !cancelRequested.load()) {
                    // --- Use the raw pointer 'buffer' here --- 
                    ssize_t written = write(localFd, buffer + totalWrittenThisChunk, rc - totalWrittenThisChunk);
                    if (written < 0) {
                        int write_errno = errno; // Save errno immediately
                        if (write_errno == EINTR) continue;
                        // Check flags before throwing error
                         if (cancelRequested.load()) {
                              throw std::runtime_error("Download cancelled during local write");
                         }
                         if (operationTimedOut.load()) {
                             throw std::runtime_error("Download timed out during local write");
                         }
                        // *** 添加更详细的日志 ***
                        OH_LOG_ERROR(LOG_APP, "写入本地文件失败: fd=%{public}d, rc=%{public}zd, total=%{public}zd, errno=%{public}d (%{public}s)",
                                     localFd, rc, totalWrittenThisChunk, write_errno, strerror(write_errno));
                        throw std::runtime_error("Write to local file failed");
                    }
                    totalWrittenThisChunk += written;
                    downloadedSize += written; // Update total downloaded size *after* potential yield
                    bytesDownloadedSinceLastSpeedUpdate += written; // Accumulate for speed calc
                }

                // Check flags after inner loop
                if (cancelRequested.load()) {
                    throw std::runtime_error("Download cancelled after writing chunk");
                }
                 if (operationTimedOut.load()) {
                    throw std::runtime_error("Download timed out after writing chunk");
                }

                // --- BEGIN MODIFICATION: Call the progress callback ---
                if (progressCallback) { 
                    progressCallback(downloadedSize);
                }
                // --- END MODIFICATION ---

                int progress = totalSize > 0 ? static_cast<int>((downloadedSize * 100) / totalSize) : 0;
                progress = std::max(0, std::min(100, progress)); // Clamp progress

                // --- BEGIN: EMA Speed Calculation --- 
                // (EMA logic remains the same)
                // ... [EMA calculation] ...

                 // ---- BEGIN MODIFICATION: Progress reporting ---- 
                 // (Progress reporting logic remains the same)
                 // ... [Progress callback logic] ...
                 // ---- END MODIFICATION ----
            } else if (rc == 0) {
                // File reading complete
                // ... [Completion log logic remains the same] ...
                break; // Exit the loop
            } else { // rc < 0
                // Check flags before handling error
                if (cancelRequested.load()) {
                    throw std::runtime_error("Download cancelled during remote read error/EAGAIN");
                }
                if (operationTimedOut.load()) {
                     throw std::runtime_error("Download timed out during remote read error/EAGAIN");
                }

                // 检查是否是EAGAIN错误
                int lastError = libssh2_session_last_errno(session.get());
                if (lastError == LIBSSH2_ERROR_EAGAIN) {
                    consecutiveEagain++;
                    if (consecutiveEagain > maxConsecutiveEagain) {
                        OH_LOG_ERROR(LOG_APP, "读取操作连续返回EAGAIN错误次数过多，可能陷入死循环");
                        throw std::runtime_error("Too many consecutive EAGAIN errors");
                    }
                    // 短暂等待后继续尝试
                    std::this_thread::sleep_for(std::chrono::milliseconds(50));
                    continue;
                } else {
                    char* errmsg;
                    libssh2_session_last_error(session.get(), &errmsg, nullptr, 0);
                    OH_LOG_ERROR(LOG_APP, "读取远程文件失败: %{public}s, 错误码: %{public}d", 
                               errmsg ? errmsg : "未知错误", lastError);
                    throw std::runtime_error("Read from remote file failed");
                }
            }
        } // End while loop

        // If loop finishes normally (rc == 0), mark success
        result = true;

    } catch (const std::exception& e) {
       // Log the exception
       OH_LOG_ERROR(LOG_APP, "下载过程中发生异常: %{public}s", e.what());
       // Ensure result is false
       result = false;
    }

    // --- Cleanup --- 
    // Always try to close the handle if it was opened
    if (handle) {
        OH_LOG_INFO(LOG_APP, "准备关闭下载 SFTP 句柄: %s", remotePath.c_str()); // Log before closing
        int session_close_err = 0; 
        unsigned long sftp_close_err = 0; 
        int close_rc = executeNonBlocking([&]() { // Use executeNonBlocking
            if (!handle) return 0;
            // Directly call libssh2_sftp_close within the lambda
            return libssh2_sftp_close(handle); 
        }, "close download handle");
        
        // Get errors *after* the call within executeNonBlocking finishes or fails
        sftp_close_err = libssh2_sftp_last_error(sftp); 
        session_close_err = libssh2_session_last_errno(session.get());

        if (close_rc != 0) {
            OH_LOG_ERROR(LOG_APP, "关闭下载句柄时出错 (rc=%{public}d, SFTP: %{public}lu, Session: %{public}d). 将标记下载结果为失败。",
                       close_rc, sftp_close_err, session_close_err);
            result = false; // *** Mark overall result as failed if handle close fails ***
            // If cancelled, attempt a robust shutdown of SFTP to avoid sticky bad state
            if (cancelRequested.load()) {
                OH_LOG_WARN(LOG_APP, "下载被取消且关闭句柄失败，尝试执行 sftp_shutdown (带 EAGAIN 重试)");
                int shutdown_rc = -1;
                if (sftp) {
                    // Retry shutdown on EAGAIN for a short period
                    int attempts = 0;
                    do {
                        shutdown_rc = libssh2_sftp_shutdown(sftp);
                        if (shutdown_rc == LIBSSH2_ERROR_EAGAIN) {
                            (void)waitSocket();
                        }
                        attempts++;
                    } while (shutdown_rc == LIBSSH2_ERROR_EAGAIN && attempts < 20);

                    if (shutdown_rc != 0 && shutdown_rc != LIBSSH2_ERROR_EAGAIN) {
                        unsigned long sftp_shutdown_err = libssh2_sftp_last_error(sftp);
                        int session_shutdown_err = libssh2_session_last_errno(session.get());
                        OH_LOG_ERROR(LOG_APP, "尝试 sftp_shutdown 时出错 (rc=%d, SFTP: %lu, Session: %d)",
                                     shutdown_rc, sftp_shutdown_err, session_shutdown_err);
                    } else {
                        OH_LOG_INFO(LOG_APP, "sftp_shutdown 调用完成 (rc=%d, attempts=%d)", shutdown_rc, attempts);
                    }

                    // 标记此 SFTP 会话已不可用，交由上层在下次调用时重新初始化
                    sftp = nullptr;
                } else {
                    OH_LOG_WARN(LOG_APP, "sftp_shutdown 跳过：sftp 句柄已为 null");
                }
            }
        } else {
             OH_LOG_INFO(LOG_APP, "成功关闭下载句柄: %s", remotePath.c_str());
        }
        handle = nullptr; // Mark handle as closed
    }
    
    // --- BEGIN Final Cleanup ---
     if (activeFlagForCleanup) {
         activeFlagForCleanup->store(false);
     }
     OH_LOG_DEBUG(LOG_APP, "DownloadFile finished or exited, marking operation inactive.");
     // --- END Final Cleanup ---

    return result;
}

bool SftpSession::deleteFile(const std::string& path) {
    std::lock_guard<std::mutex> lock(sessionMutex);
    int rc = executeNonBlocking([&]() {
        if (!sftp) return -1;
        if (path.empty()) return -2; // Custom error for empty path
        return libssh2_sftp_unlink(sftp, path.c_str());
    }, "unlink");

    if (rc == -2) {
        throw std::runtime_error("Failed to delete file: Path cannot be empty.");
    } else if (rc != 0) {
        unsigned long sftp_errno = libssh2_sftp_last_error(sftp);
        int session_errno = libssh2_session_last_errno(session.get()); // 获取 SSH Session 错误码
        // 目标已不存在：按幂等删除语义视为成功
        if (sftp_errno == LIBSSH2_FX_NO_SUCH_FILE) {
            OH_LOG_INFO(LOG_APP, "Delete file: '%s' already absent, treating as success.", path.c_str());
            return true;
        }
        std::string msg = "Failed to delete file '" + path + 
                          "' (SFTP Code: " + std::to_string(sftp_errno) + 
                          ", Session Code: " + std::to_string(session_errno) + ")"; // 添加 Session Code 到消息
        if (sftp_errno == LIBSSH2_FX_PERMISSION_DENIED) {
            msg += " - Permission denied";
        }
        // Add more specific error hints based on sftp_errno if needed
        throw std::runtime_error(msg);
    }
    return true;
}

bool SftpSession::createDirectory(const std::string& path) {
    std::lock_guard<std::mutex> lock(sessionMutex);
    int rc = executeNonBlocking([&]() {
        if (!sftp) return -1; // Indicate error to executeNonBlocking
        // Ensure path is not empty
        if (path.empty()) return -2; // Custom error code for empty path
        return libssh2_sftp_mkdir(sftp, path.c_str(),
            LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR | LIBSSH2_SFTP_S_IXUSR);
    }, "mkdir");

    if (rc == -2) { // Handle custom empty path error
        throw std::runtime_error("Failed to create directory: Path cannot be empty.");
    } else if (rc != 0) {
        unsigned long sftp_errno = libssh2_sftp_last_error(sftp);
        int session_errno = libssh2_session_last_errno(session.get()); // 获取 SSH Session 错误码
        std::string msg = "Failed to create directory '" + path + 
                          "' (SFTP Code: " + std::to_string(sftp_errno) + 
                          ", Session Code: " + std::to_string(session_errno) + ")"; // 添加 Session Code 到消息
        // Map common SFTP error codes to user-friendly messages if possible
        switch(sftp_errno) {
            case LIBSSH2_FX_PERMISSION_DENIED:
                msg += " - Permission denied";
                break;
            case LIBSSH2_FX_FILE_ALREADY_EXISTS:
                 msg += " - File or directory already exists";
                 break;
            case LIBSSH2_FX_NO_SUCH_FILE: // May indicate parent dir doesn't exist
                 msg += " - No such file or directory (parent path may be invalid)";
                 break;
            // Add more cases as needed based on libssh2 sftp error codes (FX_...)
        }
        throw std::runtime_error(msg);
    }
    return true; // Indicate success if no exception was thrown
}

bool SftpSession::deleteDirectory(const std::string& path) {
    if (!sftp) {
        OH_LOG_ERROR(LOG_APP, "SFTP session not initialized");
        return false;
    }
    
    bool originalNonBlocking = nonBlocking;
    
    if (originalNonBlocking) {
        OH_LOG_INFO(LOG_APP, "临时切换到阻塞模式执行目录删除操作: %{public}s", path.c_str());
        setNonBlocking(false);
    }
    
    bool result = false;
    
    try {
        int rc = executeNonBlocking([&]() {
            return libssh2_sftp_rmdir(sftp, path.c_str());
        }, "rmdir");
        
        if (rc == 0) {
            result = true;
        } else {
            unsigned long sftp_error = libssh2_sftp_last_error(sftp);
            int session_error = libssh2_session_last_errno(session.get()); // 获取会话错误
            if (sftp_error == LIBSSH2_FX_DIR_NOT_EMPTY || sftp_error == LIBSSH2_FX_FAILURE) {
                OH_LOG_INFO(LOG_APP, "Directory may not be empty or generic failure (SFTP: %{public}lu, Session: %{public}d), attempting recursive delete: %{public}s", sftp_error, session_error, path.c_str());
                result = deleteDirectoryRecursive(path); // Recursive delete result determines final result
            } else {
                // 目录不存在：按幂等删除语义视为成功
                if (sftp_error == LIBSSH2_FX_NO_SUCH_FILE) {
                    OH_LOG_INFO(LOG_APP, "Delete directory: '%s' already absent, treating as success.", path.c_str());
                    result = true;
                } else {
                    std::string msg = "Failed to delete directory '" + path +
                                      "' (SFTP Code: " + std::to_string(sftp_error) +
                                      ", Session Code: " + std::to_string(session_error) + ")";
                    if (sftp_error == LIBSSH2_FX_PERMISSION_DENIED) {
                        msg += " - Permission denied";
                    }
                    // Add more specific error hints based on error code if needed
                    throw std::runtime_error(msg);
                }
            }
        }
    } catch (const std::exception& e) {
        // If deleteDirectoryRecursive throws, or other exceptions occur
        OH_LOG_ERROR(LOG_APP, "Delete directory operation exception: %{public}s", e.what());
        result = false;
        // Re-throw to let NAPI layer catch it and extract SFTP code if present
        throw;
    }
    
    if (originalNonBlocking) {
        OH_LOG_INFO(LOG_APP, "恢复非阻塞模式");
        setNonBlocking(true);
    }
    
    return result;
}

bool SftpSession::rename(const std::string& oldPath, const std::string& newPath) {
    std::lock_guard<std::mutex> lock(sessionMutex);
    int rc = executeNonBlocking([&]() {
        if (!sftp) return -1;
        if (oldPath.empty() || newPath.empty()) return -2; // Custom error for empty paths
        return libssh2_sftp_rename(sftp, oldPath.c_str(), newPath.c_str());
    }, "rename");

    if (rc == -2) {
        throw std::runtime_error("Failed to rename: Old or new path cannot be empty.");
    } else if (rc != 0) {
        unsigned long sftp_errno = libssh2_sftp_last_error(sftp);
        int session_errno = libssh2_session_last_errno(session.get()); // 获取 SSH Session 错误码
        std::string msg = "Failed to rename '" + oldPath + "' to '" + newPath + 
                          "' (SFTP Code: " + std::to_string(sftp_errno) + 
                          ", Session Code: " + std::to_string(session_errno) + ")"; // 添加 Session Code 到消息
        if (sftp_errno == LIBSSH2_FX_PERMISSION_DENIED) {
            msg += " - Permission denied";
        } else if (sftp_errno == LIBSSH2_FX_NO_SUCH_FILE) {
            msg += " - No such file or directory";
        } else if (sftp_errno == LIBSSH2_FX_FILE_ALREADY_EXISTS) {
            msg += " - Target file or directory already exists";
        }
        // Add more specific error hints based on sftp_errno if needed
        throw std::runtime_error(msg);
    }
    return true;
}

std::string SftpSession::getPermissionString(uint32_t permissions) {
    std::string result;
    result += (permissions & LIBSSH2_SFTP_S_IFDIR) ? "d" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IRUSR) ? "r" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IWUSR) ? "w" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IXUSR) ? "x" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IRGRP) ? "r" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IWGRP) ? "w" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IXGRP) ? "x" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IROTH) ? "r" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IWOTH) ? "w" : "-";
    result += (permissions & LIBSSH2_SFTP_S_IXOTH) ? "x" : "-";
    return result;
}

std::string SftpSession::getTimeString(uint64_t timestamp) {
    std::time_t time = static_cast<std::time_t>(timestamp);
    std::tm* tm = std::localtime(&time);
    std::stringstream ss;
    ss << std::put_time(tm, "%Y-%m-%d %H:%M:%S");
    return ss.str();
}

bool SftpSession::getFileInfo(const std::string& path, FileInfo& info) {
    std::lock_guard<std::mutex> lock(sessionMutex);

    LIBSSH2_SFTP_ATTRIBUTES attrs;

    int rc = executeNonBlocking([&]() {
        if (!sftp) return -1;
        if (path.empty()) return -2; // Custom error for empty path
        // Using LIBSSH2_SFTP_LSTAT to follow symlinks might be useful, but stat is usually fine.
        return libssh2_sftp_stat(sftp, path.c_str(), &attrs);
    }, "stat");

    if (rc == -2) {
        throw std::runtime_error("Failed to get file info: Path cannot be empty.");
    } else if (rc < 0) { // stat returns 0 on success, < 0 on failure
        unsigned long sftp_errno = libssh2_sftp_last_error(sftp);
        int session_errno = libssh2_session_last_errno(session.get()); // 获取 SSH Session 错误码
        std::string msg = "Failed to get info for '" + path + 
                          "' (SFTP Code: " + std::to_string(sftp_errno) + 
                          ", Session Code: " + std::to_string(session_errno) + ")"; // 添加 Session Code 到消息
        if (sftp_errno == LIBSSH2_FX_PERMISSION_DENIED) {
            msg += " - Permission denied";
        } else if (sftp_errno == LIBSSH2_FX_NO_SUCH_FILE) {
            msg += " - No such file or directory";
        }
        // Add more specific error hints based on sftp_errno if needed
        throw std::runtime_error(msg);
    }

    // Fill FileInfo struct if stat was successful
    info.name = path.substr(path.find_last_of("/") + 1);
    // Check flags before accessing attributes
    info.isDirectory = (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && S_ISDIR(attrs.permissions);
    info.size = (attrs.flags & LIBSSH2_SFTP_ATTR_SIZE) ? attrs.filesize : 0;
    info.permissions = (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) ? attrs.permissions : 0;
    info.mtime = (attrs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) ? attrs.mtime : 0;
    info.atime = (attrs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) ? attrs.atime : 0;
    // Owner/Group IDs might be available in attrs.uid/gid if flags are set,
    // but converting them to names requires SSH exec or server-side lookup.
    info.owner = (attrs.flags & LIBSSH2_SFTP_ATTR_UIDGID) ? std::to_string(attrs.uid) : "?";
    info.group = (attrs.flags & LIBSSH2_SFTP_ATTR_UIDGID) ? std::to_string(attrs.gid) : "?";

    return true;
}

bool SftpSession::setPermissions(const std::string& path, uint32_t permissions) {
    OH_LOG_WARN(LOG_APP, "setPermissions using SFTP is not directly supported by libssh2, use SSH exec instead.");
    return true;
}

bool SftpSession::setFileTime(const std::string& path, uint64_t mtime, uint64_t atime) {
    std::lock_guard<std::mutex> lock(sessionMutex);
    LIBSSH2_SFTP_ATTRIBUTES attrs;
    attrs.flags = LIBSSH2_SFTP_ATTR_ACMODTIME;
    attrs.mtime = mtime;
    attrs.atime = atime;

    int rc = executeNonBlocking([&]() {
        if (!sftp) return -1;
        if (path.empty()) return -2; // Custom error for empty path
        return libssh2_sftp_setstat(sftp, path.c_str(), &attrs);
    }, "setstat");

    if (rc == -2) {
        throw std::runtime_error("Failed to set file time: Path cannot be empty.");
    } else if (rc != 0) {
        unsigned long sftp_errno = libssh2_sftp_last_error(sftp);
        std::string msg = "Failed to set time for '" + path + "' (SFTP Code: " + std::to_string(sftp_errno) + ")";
        if (sftp_errno == LIBSSH2_FX_PERMISSION_DENIED) {
            msg += " - Permission denied";
        } else if (sftp_errno == LIBSSH2_FX_NO_SUCH_FILE) {
            msg += " - No such file or directory";
        }
        // Add more specific error hints based on sftp_errno if needed
        throw std::runtime_error(msg);
    }
    return true;
}

bool SftpSession::changeFilePermissions(const std::string& path, int permissions) {
    std::stringstream ss;
    ss << std::oct << permissions;
    
    std::string command = "chmod " + ss.str() + " " + path;
    
    // 这里需要调用SSH执行命令的函数
    // ...
    
    return true;
}

bool SftpSession::deleteDirectoryRecursive(const std::string& path) {
    if (!sftp || !session) {
        OH_LOG_ERROR(LOG_APP, "deleteDirectoryRecursive: SFTP session not initialized for path '%s'", path.c_str());
        return false;
    }
    // Note: This function is expected to be called when the session is already in blocking mode
    // by the calling deleteDirectory function. We will use direct blocking calls here.

    LIBSSH2_SFTP_HANDLE* handle = nullptr;
    int rc;
    bool success = false; // Default to failure

    // 1. Open the directory directly (blocking)
    handle = libssh2_sftp_opendir(sftp, path.c_str());
    if (!handle) {
        unsigned long sftp_error = libssh2_sftp_last_error(sftp);
        int session_error = libssh2_session_last_errno(session.get());
        OH_LOG_ERROR(LOG_APP, "deleteDirectoryRecursive: Failed to open directory '%s' for listing (SFTP: %lu, Session: %d)",
                     path.c_str(), sftp_error, session_error);
        // If open fails (e.g., no such directory, permission denied), maybe it's already gone?
        // Let's consider this a non-fatal error for the *recursive* part,
        // but the final rmdir will likely fail if the reason wasn't "no such file".
        // However, to prevent leaving parent directories undeleted, we should return false here.
        return false;
    }
    OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Opened directory '%s' for listing.", path.c_str());

    // 2. Read directory entries and process them (blocking)
    char buffer[4096];
    LIBSSH2_SFTP_ATTRIBUTES attrs;
    while ((rc = libssh2_sftp_readdir(handle, buffer, sizeof(buffer), &attrs)) > 0) {
        std::string name(buffer);
        if (name == "." || name == "..") {
            continue;
        }

        std::string fullPath = path + "/" + name;
        OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Processing item '%s'", fullPath.c_str());

        // Check if it's a directory
        if ((attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && S_ISDIR(attrs.permissions)) {
            // Recursively delete subdirectory
            OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Recursing into directory '%s'", fullPath.c_str());
            if (!deleteDirectoryRecursive(fullPath)) {
                OH_LOG_ERROR(LOG_APP, "deleteDirectoryRecursive: Failed to delete subdirectory '%s'. Aborting deletion of '%s'.",
                             fullPath.c_str(), path.c_str());
                goto cleanup; // Go to cleanup (close handle) and return failure
            }
             OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Successfully deleted subdirectory '%s'", fullPath.c_str());
        } else {
            // Delete file directly (blocking)
             OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Deleting file '%s'", fullPath.c_str());
            int unlink_rc = libssh2_sftp_unlink(sftp, fullPath.c_str());
            if (unlink_rc != 0) {
                unsigned long sftp_error = libssh2_sftp_last_error(sftp);
                int session_error = libssh2_session_last_errno(session.get());
                OH_LOG_ERROR(LOG_APP, "deleteDirectoryRecursive: Failed to delete file '%s' (SFTP: %lu, Session: %d). Aborting deletion of '%s'.",
                             fullPath.c_str(), sftp_error, session_error, path.c_str());
                goto cleanup; // Go to cleanup and return failure
            }
             OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Successfully deleted file '%s'", fullPath.c_str());
        }
    }

    // Check why the loop ended
    if (rc < 0) {
        // An error occurred during readdir (other than EOF)
        unsigned long sftp_error = libssh2_sftp_last_error(sftp);
        int session_error = libssh2_session_last_errno(session.get());
         // LIBSSH2_ERROR_EAGAIN should NOT happen in blocking mode. Treat any error here as fatal.
        OH_LOG_ERROR(LOG_APP, "deleteDirectoryRecursive: Error reading directory '%s' (rc=%d, SFTP: %lu, Session: %d). Aborting deletion.",
                     path.c_str(), rc, sftp_error, session_error);
        goto cleanup; // Go to cleanup and return failure
    }
    // rc == 0 means end of directory listing, proceed to delete the now-empty directory

    // 3. Close the directory handle
    OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Finished listing directory '%s'. Closing handle.", path.c_str());
    rc = libssh2_sftp_closedir(handle);
    if (rc < 0) {
         // Log warning, but proceed to rmdir anyway
         unsigned long sftp_error = libssh2_sftp_last_error(sftp);
         int session_error = libssh2_session_last_errno(session.get());
         OH_LOG_WARN(LOG_APP, "deleteDirectoryRecursive: Failed to close directory handle for '%s' (rc=%d, SFTP: %lu, Session: %d). Proceeding with rmdir.",
                     path.c_str(), rc, sftp_error, session_error);
    }
    handle = nullptr; // Mark handle as closed

    // 4. Delete the now hopefully empty directory (blocking)
    OH_LOG_DEBUG(LOG_APP, "deleteDirectoryRecursive: Attempting to remove directory '%s' itself.", path.c_str());
    rc = libssh2_sftp_rmdir(sftp, path.c_str());
    if (rc == 0) {
        OH_LOG_INFO(LOG_APP, "deleteDirectoryRecursive: Successfully removed directory '%s'.", path.c_str());
        success = true;
    } else {
        unsigned long sftp_error = libssh2_sftp_last_error(sftp);
        int session_error = libssh2_session_last_errno(session.get());
        OH_LOG_ERROR(LOG_APP, "deleteDirectoryRecursive: Failed to remove directory '%s' itself (rc=%d, SFTP: %lu, Session: %d).",
                     path.c_str(), rc, sftp_error, session_error);
        success = false;
    }

    return success;

cleanup:
    // Cleanup section: Close the handle if it's still open
    if (handle) {
        int close_rc = libssh2_sftp_closedir(handle);
         if (close_rc < 0) {
            OH_LOG_WARN(LOG_APP, "deleteDirectoryRecursive (cleanup): Failed to close directory handle for '%s' (rc=%d).", path.c_str(), close_rc);
         }
        handle = nullptr;
    }
    return false; // Return failure as we came here via goto from an error path
}

void SftpSession::setOperationTimeout(std::atomic<bool>& timedOutFlag, std::shared_ptr<std::atomic<bool>> activeFlag, int seconds) {
    // Reset the timedOutFlag for this specific operation timeout instance
    timedOutFlag.store(false);

    // Capture necessary flags by value/shared_ptr for the thread
    auto capturedActiveFlag = activeFlag; // Copy shared_ptr

    std::thread timeoutThread([capturedActiveFlag, seconds, this]() { // Capture 'this'
        const int checkInterval = 100;
        const int maxChecks = (seconds > 0) ? (seconds * 1000 / checkInterval) : -1; // Handle seconds <= 0 as infinite
        int totalChecks = 0;

        // Loop while the operation is active, hasn't timed out yet, and timeout duration hasn't been reached
        // Access member operationTimedOut via 'this'
        while (capturedActiveFlag->load() && !this->operationTimedOut.load() && (maxChecks == -1 || totalChecks < maxChecks)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(checkInterval));
            totalChecks++;

            // Debug log
            if (maxChecks != -1 && totalChecks % 10 == 0) {
                 OH_LOG_DEBUG(LOG_APP, "操作超时检查: %{public}d/%{public}d 秒", totalChecks / 10, seconds);
            } else if (maxChecks == -1 && totalChecks % 600 == 0) { // Log every minute if infinite
                 OH_LOG_DEBUG(LOG_APP, "操作超时检查: 无限超时运行中 (%d分钟)", totalChecks / 600);
            }

            // Check active flag again after sleep
            if (!capturedActiveFlag->load()) {
                OH_LOG_DEBUG(LOG_APP, "操作超时检查: 操作已标记为非活动，超时线程退出.");
                return; // Exit if operation became inactive
            }
        }

        // Check why the loop exited
        // Access member operationTimedOut via 'this'
        if (capturedActiveFlag->load() && !this->operationTimedOut.load() && maxChecks != -1 && totalChecks >= maxChecks) {
            // Only trigger timeout if the operation is still marked active when the timer expires
            OH_LOG_ERROR(LOG_APP, "SFTP操作已超时(%{public}d秒)，强制终止", seconds);
            this->operationTimedOut.store(true); // Mark that timeout occurred
            this->cancelRequested.store(true);   // Request cancellation
        } else {
             OH_LOG_DEBUG(LOG_APP, "操作超时检查: 循环正常退出 (操作结束、已超时或无限等待)，超时线程结束.");
        }
    });

    timeoutThread.detach();
}

void SftpSession::setGlobalOperationTimeout(int seconds) {
    globalOperationTimeout = seconds;
}

// --- 新增: 取消请求方法的实现 ---
void SftpSession::requestCancel() {
    OH_LOG_INFO(LOG_APP, "SFTP Cancel request received.");
    cancelRequested.store(true);
    // Also mark the current operation as inactive so the timer thread stops
    if (currentOperationActiveFlag) {
        currentOperationActiveFlag->store(false);
        OH_LOG_DEBUG(LOG_APP, "requestCancel marked current operation inactive.");
    }
}
// --------------------------------

// --- 新增：keepAliveThread方法实现 ---
void SftpSession::keepAliveThread() {
    const size_t threadId = std::hash<std::thread::id>{}(std::this_thread::get_id());
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][SFTP Session %{public}d] keepAliveThread 开始执行", threadId, sessionId.load());
    
    // 确保间隔大于0
    if (config.keepAliveInterval <= 0) {
        OH_LOG_ERROR(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] keepAliveInterval 无效 (%d)，线程退出", 
                    threadId, sessionId.load(), config.keepAliveInterval);
        return;
    }

    // 记录开始时间
    auto startTime = std::chrono::steady_clock::now();
    
    while (!stopThread.load()) {
        // 检查会话是否有效
        bool sessionValid = false;
        {
            std::lock_guard<std::mutex> lock(sessionMutex);
            sessionValid = (session && sftp);
        }
        
        if (!sessionValid) {
            OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] 会话无效，keepAliveThread 退出", 
                       threadId, sessionId.load());
            break;
        }
        
        // 定期发送 keepalive 消息
        int next_time = config.keepAliveInterval; // 默认值
        {
            std::lock_guard<std::mutex> lock(sessionMutex);
            if (session) {
                int rc = libssh2_keepalive_send(session.get(), &next_time);
                
                if (rc == 0) {
                    OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] Keepalive 消息已发送，下次发送时间: %{public}d秒后", 
                               threadId, sessionId.load(), next_time);
                } else if (rc == LIBSSH2_ERROR_EAGAIN) {
                    // 发送缓冲区已满，这是正常的，稍后再试
                    OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] Keepalive 发送缓冲区已满 (EAGAIN)", 
                               threadId, sessionId.load());
                } else {
                    OH_LOG_ERROR(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] Keepalive 发送失败，错误码: %{public}d", 
                                threadId, sessionId.load(), rc);
                }
            } else {
                OH_LOG_ERROR(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] 会话已失效，keepAliveThread 退出", 
                            threadId, sessionId.load());
                break;
            }
        }
        
        // 更新运行时间统计（可选）
        auto currentTime = std::chrono::steady_clock::now();
        auto elapsedSeconds = std::chrono::duration_cast<std::chrono::seconds>(
            currentTime - startTime).count();
        
        // 每5分钟记录一次日志（避免日志过多）
        if (elapsedSeconds % 300 == 0) {
            OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][SFTP Session %{public}d] keepAliveThread 已运行 %{public}ld 秒", 
                       threadId, sessionId.load(), (long)elapsedSeconds);
        }
        
        // 使用libssh2返回的next_time作为实际休眠时间
        int sleepTime = next_time;
        
        // 安全检查: 确保休眠时间合理
        if (sleepTime <= 0) {
            sleepTime = 1; // 至少休眠1秒
            OH_LOG_WARN(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] 无效的next_time值(%{public}d)，使用最小值1秒", 
                       threadId, sessionId.load(), next_time);
        } else if (sleepTime > config.keepAliveInterval) {
            sleepTime = config.keepAliveInterval; // 不超过配置的最大间隔
            OH_LOG_WARN(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] next_time值(%{public}d)超过keepAliveInterval，使用%{public}d秒", 
                       threadId, sessionId.load(), next_time, config.keepAliveInterval);
        }
        
        OH_LOG_INFO(LOG_APP, "[Thread %{public}ld][SFTP Session %{public}d] keepAliveThread 将休眠 %{public}d 秒", 
                   threadId, sessionId.load(), sleepTime);
        
        // 分段休眠，便于快速响应停止信号
        for (int i = 0; i < sleepTime && !stopThread.load(); i++) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }
    
    OH_LOG_INFO(LOG_APP, "[Thread %{public}zu][SFTP Session %{public}d] keepAliveThread 正常退出", threadId, sessionId.load());
}
// --- 新增结束 ---
