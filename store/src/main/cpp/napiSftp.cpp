#include "napiSftp.h"
#include "napiWrapper.hpp"
#include "command.h"
#include "napi/native_api.h"
#include "protocol/ssh/SshSession.h" // 需要 SshSession 头文件
#include "key_manager.h" // 为了 KeyOperationResult, 也许可以移走?
#include <hilog/log.h>
#include <string>
#include <uv.h>
#include <thread>
#include <memory>
#include <atomic>
#include <chrono>
#include <vector>
#include <tuple>
#include <system_error> // For std::error_code
#include <fcntl.h> // For open, O_RDWR etc.
#include <unistd.h> // For close, lseek etc.
#include <sys/stat.h> // For file size in upload
#include <regex> // 用于解析错误码
#include "protocol/SessionManager/SessionManager.h"
#include <libssh2_sftp.h>
#include <functional>
#include <map>  // 添加map头文件
#include <cassert>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200 // 全局domain宏，标识业务领域
#define LOG_TAG "SFTP_NAPI_TAG"  // 新的 Log Tag

// extern std::shared_ptr<Session> SessionHandle; // 移除全局会话句柄

// --- SFTP 相关数据结构 ---

// SFTP文件信息结构
struct SftpFileInfo {
    std::string name;
    bool isDirectory;
    uint64_t size;
    std::string permissions;
    std::string mtime;
    std::string atime;
    std::string owner;
    std::string group;
    // 添加 sessionId 字段，以便在 Execute lambda 中使用
    int sessionId;
};

// 下载文件数据结构
struct DownloadWorkData {
    int sessionId; // <-- Add sessionId
    std::string remotePath;
    int fd;
    bool success;
    std::string errorMsg;
    napi_ref progressCallbackRef;   // 进度回调引用
    napi_ref completionCallbackRef; // 完成回调引用
    napi_async_work work;
    napi_threadsafe_function progressTsfn; // 线程安全函数用于进度回调
    std::atomic<bool> tsfnActive{true};    // 控制 TSFN 是否仍在使用
    // 进度相关字段
    off_t fileSize;                 // 文件总大小
    off_t downloadedBytes;          // 已下载字节数
    std::chrono::steady_clock::time_point startTime; // 开始时间
};

// 进度更新数据结构 (上传下载通用)
struct ProgressUpdateData {
    bool isCompletionUpdate; // 标记是进度更新还是最终完成更新
    bool overallSuccess;     // 仅在 isCompletionUpdate 为 true 时有意义
    int totalProgress;       // 总体进度 (0-100)
    double speed;            // 当前或平均速度 (MB/s) <-- 注意单位
    int totalFiles;          // 总文件数 (下载时为1)
    int completedFiles;      // 已完成文件数 (下载时为 0 或 1)
    std::string currentFile; // 当前正在处理的文件路径
    off_t currentFileSize;   // 当前文件的大小
    std::string errorMsg;    // 错误信息 (如果 overallSuccess 为 false)
    off_t downloadedBytes; // 明确的已下载字节数 (下载专用)
    // off_t uploadedBytes; // 明确的已上传字节数 (上传专用, 在MultiUploadItem中)
};

// 多文件上传状态结构体
struct MultiUploadItem {
    int fd;                  // 文件描述符
    std::string remotePath;  // 远程路径
    int progress;           // 上传进度 (0-100)
    bool completed;         // 是否完成
    bool success;           // 是否成功
    std::string errorMsg;    // 错误信息
    off_t fileSize;         // 文件总大小
    off_t uploadedBytes;    // 已上传字节数
};

// 多文件上传工作数据
struct MultiUploadWorkData {
    int sessionId; // <-- Add sessionId
    std::vector<MultiUploadItem> items;
    int completedCount;         // 已完成的文件数量
    bool allCompleted;          // 是否全部完成 (后台任务标记)
    off_t totalSize;            // 所有文件的总大小
    off_t totalUploadedBytes;   // 所有文件已上传的总字节数
    std::chrono::steady_clock::time_point totalStartTime; // 总开始时间
    std::chrono::steady_clock::time_point lastReportTime; // <<<--- 添加：上次报告时间
    napi_ref progressCallbackRef; // 进度回调引用
    napi_ref completionCallbackRef; // 完成回调引用
    napi_async_work work;
    napi_threadsafe_function progressTsfn; // 线程安全函数用于进度回调
    std::atomic<bool> tsfnActive{true};    // 控制 TSFN 是否仍在使用
    std::atomic<bool> cancelRequested{false}; // 记录是否已请求取消整个上传任务
};

// --- 全局当前任务控制 ---
static struct {
    // 改为使用map存储不同会话的传输任务
    std::map<int, MultiUploadWorkData*> activeUploadTasks;
    std::map<int, DownloadWorkData*> activeDownloadTasks;
    std::mutex mutex;
} gCurrentTransfers;

// 目录列表数据结构
struct SimpleListDirWorkData {
    int sessionId; // <-- Add sessionId
    std::string remotePath;
    std::vector<SftpFileInfo> fileList;
    bool success;
    std::string errorMsg;
    // --- BEGIN MODIFICATION ---
    int sftpErrorCode = -1; // 新增 SFTP 错误码，默认为 -1 (未知)
    // --- END MODIFICATION ---
    napi_ref callback;
    napi_async_work work;
};

// 简单异步工作数据结构 (用于删除、创建、重命名)
struct SimpleWorkData {
    int sessionId; // <-- Add sessionId
    std::string path;
    std::string oldPath;
    std::string newPath;
    bool success;
    std::string errorMsg;
    // --- BEGIN MODIFICATION: Add SFTP error code field ---
    int sftpErrorCode = -1;
    // --- END MODIFICATION ---
    napi_ref callback;
    napi_async_work work;
    std::function<bool(SshSession*, SimpleWorkData*)> executeFunc; // <-- 添加 std::function 成员
};

// --- 辅助函数 ---

// 获取 Session
static SshSession* GetSshSessionById(int sessionId) {
    auto& sessionManager = SessionManager::getInstance();
    auto session = sessionManager.getSession(sessionId);
    if (!session) {
        OH_LOG_WARN(LOG_APP, "GetSshSessionById: 无法找到 sessionId = %{public}d 的会话", sessionId);
        return nullptr;
    }
    return dynamic_cast<SshSession*>(session.get());
}

// 创建NAPI错误辅助函数
static napi_value CreateNapiError(napi_env env, const char* message) {
    napi_value error_msg;
    napi_value error;
    napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &error_msg);
    napi_create_error(env, nullptr, error_msg, &error);
    return error;
}

// 安全获取 NAPI 字符串
static std::string SafeGetStringFromNapi(napi_env env, napi_value value) {
    napi_valuetype valuetype;
    napi_status status = napi_typeof(env, value, &valuetype);
    if (status != napi_ok || valuetype != napi_string) {
        OH_LOG_WARN(LOG_APP, "SafeGetStringFromNapi: Expected string, got type %d", valuetype);
        return "";
    }
    size_t len = 0;
    status = napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    if (status != napi_ok || len == 0) {
        if (status != napi_ok) {
             OH_LOG_WARN(LOG_APP, "SafeGetStringFromNapi: Failed to get string length (status %d)", status);
        }
        return "";
    }
    std::string str(len, '\0');
    status = napi_get_value_string_utf8(env, value, &str[0], len + 1, &len);
     if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SafeGetStringFromNapi: Failed to get string value (status %d)", status);
        return "";
    }
    return str;
}

// 安全获取 NAPI int32
static int SafeGetInt32FromNapi(napi_env env, napi_value value, int default_val = -1) {
    napi_valuetype valuetype;
    napi_status status = napi_typeof(env, value, &valuetype);
    if (status != napi_ok || valuetype != napi_number) {
         OH_LOG_WARN(LOG_APP, "SafeGetInt32FromNapi: Expected number, got type %d", valuetype);
        return default_val;
    }
    int32_t int_val;
    status = napi_get_value_int32(env, value, &int_val);
     if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SafeGetInt32FromNapi: Failed to get int32 value (status %d)", status);
        return default_val;
    }
    return static_cast<int>(int_val);
}

// 将 FileInfo 转换为 SftpFileInfo
static SftpFileInfo convertToSftpFileInfo(const FileInfo& info, SshSession* sshSession) {
    SftpFileInfo sftpInfo;
    sftpInfo.name = info.name;
    sftpInfo.isDirectory = info.isDirectory;
    sftpInfo.size = info.size;

    if (sshSession) {
        sftpInfo.permissions = sshSession->getPermissionString(info.permissions);
        sftpInfo.mtime = sshSession->getTimeString(info.mtime);
        sftpInfo.atime = sshSession->getTimeString(info.atime);
    } else {
        sftpInfo.permissions = "";
        sftpInfo.mtime = "";
        sftpInfo.atime = "";
    }

    sftpInfo.owner = info.owner;
    sftpInfo.group = info.group;
    return sftpInfo;
}

// 将 SftpFileInfo 转换为 napi_value
static napi_value convertToNapiValue(napi_env env, const SftpFileInfo& info) {
    napi_value result;
    napi_create_object(env, &result);

    napi_value name;
    napi_create_string_utf8(env, info.name.c_str(), NAPI_AUTO_LENGTH, &name);
    napi_set_named_property(env, result, "name", name);

    napi_value isDirectory;
    napi_get_boolean(env, info.isDirectory, &isDirectory);
    napi_set_named_property(env, result, "isDirectory", isDirectory);

    napi_value size;
    napi_create_int64(env, (int64_t)info.size, &size);
    napi_set_named_property(env, result, "size", size);

    napi_value permissions;
    napi_create_string_utf8(env, info.permissions.c_str(), NAPI_AUTO_LENGTH, &permissions);
    napi_set_named_property(env, result, "permissions", permissions);

    napi_value mtime;
    napi_create_string_utf8(env, info.mtime.c_str(), NAPI_AUTO_LENGTH, &mtime);
    napi_set_named_property(env, result, "mtime", mtime);

    napi_value atime;
    napi_create_string_utf8(env, info.atime.c_str(), NAPI_AUTO_LENGTH, &atime);
    napi_set_named_property(env, result, "atime", atime);

    napi_value owner;
    napi_create_string_utf8(env, info.owner.c_str(), NAPI_AUTO_LENGTH, &owner);
    napi_set_named_property(env, result, "owner", owner);

    napi_value group;
    napi_create_string_utf8(env, info.group.c_str(), NAPI_AUTO_LENGTH, &group);
    napi_set_named_property(env, result, "group", group);

    return result;
}

// --- BEGIN HELPER FUNCTION ---
// 从错误消息中提取 SFTP Code 的辅助函数
static int ExtractSftpCode(const std::string& errorMessage) {
    // 尝试匹配 "[SFTP Code: <数字>]"
    std::regex codeRegex("\\[SFTP Code: (\\d+)\\]");
    std::smatch match;
    if (std::regex_search(errorMessage, match, codeRegex) && match.size() > 1) {
        try {
            return std::stoi(match[1].str());
        } catch (const std::invalid_argument& ia) {
            OH_LOG_WARN(LOG_APP, "ExtractSftpCode: Invalid argument during stoi for '%s'", match[1].str().c_str());
        } catch (const std::out_of_range& oor) {
            OH_LOG_WARN(LOG_APP, "ExtractSftpCode: Out of range during stoi for '%s'", match[1].str().c_str());
        }
    }
    // 如果没有找到或解析失败，返回默认值
    return -1; 
}
// --- END HELPER FUNCTION ---


// --- SFTP N-API 函数实现 ---

// 初始化SFTP会话 (同步)
static napi_value InitSftp(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "需要 1 个参数: sessionId");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        OH_LOG_ERROR(LOG_APP, "SFTP 初始化失败: 会话不是 SSH 会话类型");
        napi_throw_error(env, nullptr, "Session is not an SSH session");
        return nullptr;
    }

    // 获取并打印认证信息，用于调试
    SftpConfig config = sshSession->getSftpConfig();
    OH_LOG_INFO(LOG_APP, "SFTP 认证信息: 主机=%s, 端口=%d, 用户=%s, 认证方式=%s",
                config.host.c_str(), config.port, config.username.c_str(),
                config.useKeyAuth ? "密钥" : "密码");

    if (config.host.empty()) {
        OH_LOG_ERROR(LOG_APP, "SFTP 初始化失败: 主机名为空");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }

    bool success = sshSession->initSftp();

    if (success) {
        OH_LOG_INFO(LOG_APP, "SFTP 初始化成功");
    } else {
        OH_LOG_ERROR(LOG_APP, "SFTP 初始化失败，请检查网络连接和认证信息");
    }

    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 列出目录内容 (异步)
static napi_value ListDirectory(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "开始执行 ListDirectory 函数");

    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        napi_throw_type_error(env, nullptr, "需要 3 个参数: sessionId, 路径和回调函数");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    // --- BEGIN Log sessionId ---
    OH_LOG_INFO(LOG_APP, "ListDirectory: Received sessionId = %{public}d", sessionId);
    // --- END Log sessionId ---
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        OH_LOG_ERROR(LOG_APP, "ListDirectory: No active session for sessionId = %{public}d", sessionId);
        napi_throw_error(env, nullptr, "No active session");
        return nullptr;
    }

    // 检查参数类型
    napi_valuetype pathType, callbackType;
    napi_typeof(env, args[1], &pathType);
    napi_typeof(env, args[2], &callbackType);

    if (pathType != napi_string || callbackType != napi_function) {
        napi_throw_type_error(env, nullptr, "参数类型错误: 需要 (string, function)");
        return nullptr;
    }

    // 获取路径参数
    std::string pathStr = SafeGetStringFromNapi(env, args[1]);

    // 创建工作数据
    SimpleListDirWorkData* workData = new SimpleListDirWorkData();
    workData->sessionId = sessionId; // Assign sessionId to workData
    workData->remotePath = pathStr;
    workData->success = false;
    workData->sftpErrorCode = -1; // 初始化

    // 保存回调函数引用
    napi_create_reference(env, args[2], 1, &workData->callback);

    // 创建异步工作
    napi_value resourceName;
    napi_create_string_utf8(env, "SftpListDirectory", NAPI_AUTO_LENGTH, &resourceName);

    napi_create_async_work(
        env,
        nullptr,
        resourceName,
        // Execute lambda (后台线程)
        [](napi_env env, void* data) {
            SimpleListDirWorkData* wd = static_cast<SimpleListDirWorkData*>(data);
            wd->sftpErrorCode = -1; // 重置错误码
            wd->success = false;    // 初始假设失败

            // Get session using sessionId from work data
            SshSession* sshSession = GetSshSessionById(wd->sessionId);
            if (!sshSession) {
                wd->errorMsg = "Session is not an SSH session or is invalid";
                return;
            }

            try {
                wd->fileList.clear(); // Ensure list is empty

                // 调用 C++ 函数。它会在 opendir 失败时抛出异常。
                bool listSuccess = sshSession->listDirectory(wd->remotePath,
                    [wd, sshSession](const FileInfo& info) { // Capture sshSession
                        // Pass sshSession to the helper
                        wd->fileList.push_back(convertToSftpFileInfo(info, sshSession));
                    });

                // 只有在 listDirectory 返回 true 时才标记为成功
                if (listSuccess) {
                    wd->success = true;
                } else {
                    if (wd->errorMsg.empty()) wd->errorMsg = "Failed during directory reading";
                }

            } catch (const std::exception& e) {
                wd->success = false; // 确保 success 为 false
                wd->errorMsg = e.what(); // 直接使用异常消息
                wd->sftpErrorCode = ExtractSftpCode(wd->errorMsg); // 从此消息中提取代码
            } catch (...) {
                wd->success = false; // 确保 success 为 false
                wd->errorMsg = "Unknown error occurred during listDirectory";
                wd->sftpErrorCode = -1; // 未知异常，代码为 -1
            }
        },
        // Complete lambda (JS 主线程)
        [](napi_env env, napi_status status, void* data) {
             SimpleListDirWorkData* wd = static_cast<SimpleListDirWorkData*>(data);
            napi_value callback, global;
            napi_get_reference_value(env, wd->callback, &callback);
            napi_get_global(env, &global);

            napi_value args[2]; // [error, result_array]

            if (status != napi_ok) {
                 wd->success = false; // 如果异步任务本身失败，覆盖内部状态
                 wd->errorMsg = "Async list directory task failed or cancelled (status: " + std::to_string(status) + ")";
                 wd->sftpErrorCode = -1; // 重置 sftp code
            }

            if (wd->success) {
                napi_get_null(env, &args[0]); // error = null
                napi_create_array_with_length(env, wd->fileList.size(), &args[1]); // result = array
                for (size_t i = 0; i < wd->fileList.size(); i++) {
                    napi_value fileInfo = convertToNapiValue(env, wd->fileList[i]);
                    napi_set_element(env, args[1], i, fileInfo);
                }
            } else {
                napi_value errorMsgStr;
                napi_create_string_utf8(env, wd->errorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsgStr);
                napi_create_error(env, nullptr, errorMsgStr, &args[0]); // error = Error object
                napi_get_null(env, &args[1]); // result = null

                if (wd->sftpErrorCode != -1) {
                    napi_value errorCodeValue;
                    napi_create_int32(env, wd->sftpErrorCode, &errorCodeValue);
                    napi_set_named_property(env, args[0], "code", errorCodeValue);
                } else {
                    OH_LOG_ERROR(LOG_APP, "SFTP ListDirectory Complete: Failed for sessionId = %{public}d (Msg: %{public}s), calling JS callback.", wd->sessionId, wd->errorMsg.c_str());
                }
            }

            // Call JS callback
            napi_value result;
            napi_call_function(env, global, callback, 2, args, &result); // Ignore result

            // Clean up
            napi_delete_reference(env, wd->callback);
            napi_delete_async_work(env, wd->work);
            delete wd;
        },
        workData,
        &workData->work
    );

    // Queue async work
    napi_queue_async_work(env, workData->work);

    // Return undefined (callback handles result)
    napi_value undefined_result;
    napi_get_undefined(env, &undefined_result);
    return undefined_result;
}

// 上传文件 (异步, 多文件, 带进度)
static napi_value UploadFile(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "SFTP UploadFile: Entry");
    size_t argc = 5;  // sessionId, files (array), targetDir (string), progressCallback (function), completionCallback (function)
    napi_value args[5];
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (status != napi_ok || argc < 5) {
        OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 需要 5 个参数, 收到 %zu", argc);
        napi_throw_type_error(env, nullptr, "需要 5 个参数: sessionId, files (array), targetDir (string), progressCallback (function), completionCallback (function)");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: No active session");
        napi_throw_error(env, nullptr, "No active session");
        return nullptr;
    }

    // 检查参数类型
    napi_valuetype filesType, targetDirType, progressCbType, completionCbType;
    napi_typeof(env, args[1], &filesType);
    napi_typeof(env, args[2], &targetDirType);
    napi_typeof(env, args[3], &progressCbType);
    napi_typeof(env, args[4], &completionCbType);

    bool isArray;
    napi_is_array(env, args[1], &isArray);

    if (!isArray || targetDirType != napi_string || progressCbType != napi_function || completionCbType != napi_function) {
        OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 参数类型错误");
        napi_throw_type_error(env, nullptr, "参数类型错误: 需要 (array, string, function, function)");
        return nullptr;
    }

    // 获取目标目录
    std::string targetDirStr = SafeGetStringFromNapi(env, args[2]);

    // 获取数组长度
    uint32_t arrayLength;
    napi_get_array_length(env, args[1], &arrayLength);
    if (arrayLength == 0) {
        OH_LOG_WARN(LOG_APP, "SFTP UploadFile: 文件数组为空");
        // Call completion callback immediately with success? Or throw error?
        // Let's call completion callback successfully.
        napi_value completionCallback = args[4];
        napi_value global, nullVal, emptyDetails, cbArgs[2];
        napi_get_global(env, &global);
        napi_get_null(env, &nullVal);
        napi_create_object(env, &emptyDetails); // Empty details object
        cbArgs[0] = nullVal; // error = null
        cbArgs[1] = emptyDetails; // result = {}
        napi_call_function(env, global, completionCallback, 2, cbArgs, nullptr);
        napi_value undefined_result;
        napi_get_undefined(env, &undefined_result);
        return undefined_result; // Return undefined as async work not needed
    }

    // --- 创建工作数据 ---
    auto workData = new MultiUploadWorkData();
    workData->sessionId = sessionId; // <-- Add missing sessionId assignment
    workData->completedCount = 0;
    workData->allCompleted = false;
    workData->items.reserve(arrayLength);
    workData->totalSize = 0;
    workData->totalUploadedBytes = 0;
    workData->progressCallbackRef = nullptr;
    workData->completionCallbackRef = nullptr;
    workData->progressTsfn = nullptr;
    workData->tsfnActive = true;

    // 解析文件数组并计算总大小
    bool parseError = false;
    for (uint32_t i = 0; i < arrayLength; i++) {
        napi_value item;
        napi_get_element(env, args[1], i, &item);

        napi_value fdValue;
        napi_get_named_property(env, item, "fd", &fdValue);
        int fd = SafeGetInt32FromNapi(env, fdValue);

        std::string remotePath = targetDirStr;
        if (!remotePath.empty() && remotePath.back() != '/') {
            remotePath += '/';
        }

        std::string fileName = "unknown_file_" + std::to_string(i + 1);
        napi_value fileNameValue;
        napi_valuetype fileNameType;
        if (napi_get_named_property(env, item, "name", &fileNameValue) == napi_ok && napi_typeof(env, fileNameValue, &fileNameType) == napi_ok && fileNameType == napi_string) {
             fileName = SafeGetStringFromNapi(env, fileNameValue);
        }
        if (fileName.empty()) {
             OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 第 %u 个文件缺少有效的文件名", i);
             parseError = true;
             break; // Stop parsing on error
        }
        remotePath += fileName;

        off_t fileSize = 0;
        if (fd >= 0) {
            // 使用 fstat 获取文件大小更可靠
             struct stat st;
             if (fstat(fd, &st) == 0) {
                 fileSize = st.st_size;
                 // Reset fd position just in case (though SshSession should handle it)
                 lseek(fd, 0, SEEK_SET);
             } else {
                 OH_LOG_WARN(LOG_APP, "SFTP UploadFile: 无法使用 fstat 获取 fd %d 的文件大小: %s", fd, strerror(errno));
                 // Fallback to lseek maybe? Or just set to 0/error out? Let's set to 0 for now.
                 fileSize = 0;
             }

            // off_t currentPos = lseek(fd, 0, SEEK_CUR);
            // if (currentPos != -1) {
            //     fileSize = lseek(fd, 0, SEEK_END);
            //     if (fileSize == -1) fileSize = 0; // Handle error
            //     lseek(fd, currentPos, SEEK_SET); // Restore position
            // } else {
            //      OH_LOG_WARN(LOG_APP, "无法获取文件描述符 %d 的当前位置", fd);
            // }
        } else {
             OH_LOG_WARN(LOG_APP, "SFTP UploadFile: 无效的文件描述符 (%d) 在文件 %s", fd, fileName.c_str());
             // Treat as error? Or just skip? Let's skip this file by not adding it.
             // But need to adjust arrayLength later or handle it in loop.
             // For now, let's treat invalid fd as a parse error.
             parseError = true;
             break;
        }

        workData->totalSize += fileSize;

        MultiUploadItem uploadItem;
        uploadItem.fd = fd;
        uploadItem.remotePath = remotePath;
        uploadItem.progress = 0;
        uploadItem.completed = false;
        uploadItem.success = false;
        uploadItem.errorMsg = "";
        uploadItem.fileSize = fileSize;
        uploadItem.uploadedBytes = 0;
        workData->items.push_back(uploadItem);
    }

     if (parseError) {
         OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 解析文件列表时出错");
         delete workData; // Clean up allocated data
         napi_throw_error(env, nullptr, "解析文件列表时出错 (例如无效文件名或文件描述符)");
         return nullptr;
     }

    OH_LOG_INFO(LOG_APP, "SFTP UploadFile: 解析了 %{public}zu 个文件, 总大小: %{public}lu 字节", workData->items.size(), workData->totalSize);

    // --- 保存回调函数引用 ---
    status = napi_create_reference(env, args[3], 1, &workData->progressCallbackRef);
    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 创建进度回调引用失败");
        delete workData;
        napi_throw_error(env, nullptr, "创建进度回调引用失败");
        return nullptr;
    }
    status = napi_create_reference(env, args[4], 1, &workData->completionCallbackRef);
     if (status != napi_ok) {
         OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 创建完成回调引用失败");
         napi_delete_reference(env, workData->progressCallbackRef); // Clean up created ref
         delete workData;
         napi_throw_error(env, nullptr, "创建完成回调引用失败");
         return nullptr;
     }

    // --- 创建线程安全函数 (TSFN) ---
    napi_value tsfnResourceName;
    napi_create_string_utf8(env, "SftpUploadProgressCallback", NAPI_AUTO_LENGTH, &tsfnResourceName);

    status = napi_create_threadsafe_function(
        env,
        args[3], // JS 进度回调函数
        nullptr,
        tsfnResourceName,
        0, // max_queue_size (0 = 无限制)
        1, // initial_thread_count
        workData, // thread_finalize_data (传递 workData 以便在 TSFN 销毁时访问)
        // TSFN finalize callback
        [](napi_env env, void* finalize_data, void* context) {
            MultiUploadWorkData* wd = static_cast<MultiUploadWorkData*>(finalize_data);
            OH_LOG_INFO(LOG_APP, "SFTP Upload TSFN finalize callback. Setting tsfnActive=false.");
             if (wd) {
                 wd->tsfnActive = false;
             }
        },
        nullptr, // context
        // CallJs lambda (在主 JS 线程中执行)
        [](napi_env env, napi_value js_callback, void* context, void* data) {
            if (env == nullptr || js_callback == nullptr || data == nullptr) {
                 OH_LOG_ERROR(LOG_APP, "SFTP Upload TSFN CallJs: Invalid arguments.");
                 if (data) delete static_cast<ProgressUpdateData*>(data);
                 return;
             }

            ProgressUpdateData* progressData = static_cast<ProgressUpdateData*>(data);
            // OH_LOG_DEBUG(LOG_APP, "SFTP Upload TSFN CallJs: Received progress update (Total: %d%%).", progressData->totalProgress);

            napi_value global, progressInfo, result;
            napi_get_global(env, &global);
            napi_create_object(env, &progressInfo);

            // 构建传递给 JS 回调的参数
            napi_value jsArgs[2]; // [error, progressDetails]

            // 创建 progressDetails 对象 (符合 UploadProgressItem 接口)
            napi_value val;
            napi_get_boolean(env, progressData->isCompletionUpdate, &val); // completed
            napi_set_named_property(env, progressInfo, "completed", val);
            napi_create_int32(env, progressData->totalProgress, &val);    // progress
            napi_set_named_property(env, progressInfo, "progress", val);
            napi_create_double(env, progressData->speed, &val);           // speed (MB/s)
            napi_set_named_property(env, progressInfo, "speed", val);
            napi_create_int32(env, progressData->totalFiles, &val);       // totalFiles
            napi_set_named_property(env, progressInfo, "totalFiles", val);
            napi_create_int32(env, progressData->completedFiles, &val);   // completedFiles
            napi_set_named_property(env, progressInfo, "completedFiles", val);
            if (!progressData->currentFile.empty()) {                    // remotePath
                napi_create_string_utf8(env, progressData->currentFile.c_str(), NAPI_AUTO_LENGTH, &val);
                napi_set_named_property(env, progressInfo, "remotePath", val);
            }
            napi_create_int64(env, (int64_t)progressData->currentFileSize, &val); // currentFileSize
            napi_set_named_property(env, progressInfo, "currentFileSize", val);
             // Add uploadedBytes if needed (for upload specific progress item?)
             // napi_create_int64(env, (int64_t)progressData->uploadedBytes, &val);
             // napi_set_named_property(env, progressInfo, "uploadedBytes", val);

            // 设置回调参数
            if (progressData->isCompletionUpdate && !progressData->overallSuccess) {
                // Final update with error
                napi_value errorMsgStr;
                napi_create_string_utf8(env, progressData->errorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsgStr);
                napi_create_error(env, nullptr, errorMsgStr, &jsArgs[0]); // error = Error object
            } else {
                // Progress update or final success update
                napi_get_null(env, &jsArgs[0]); // error = null
            }
            jsArgs[1] = progressInfo; // progressDetails

            // 调用 JS 进度回调函数
            napi_status call_status = napi_call_function(env, global, js_callback, 2, jsArgs, &result);
            if (call_status != napi_ok) {
                OH_LOG_ERROR(LOG_APP, "SFTP Upload TSFN CallJs: Failed to call JS progress callback (status: %d).", call_status);
                 bool is_exception_pending = false;
                 napi_is_exception_pending(env, &is_exception_pending);
                 if (is_exception_pending) {
                     napi_value exception;
                     napi_get_and_clear_last_exception(env, &exception);
                     OH_LOG_ERROR(LOG_APP, "SFTP Upload TSFN CallJs: An exception occurred in the JS callback.");
                 }
            }
            // 清理后台线程 new 出来的 progressData
            delete progressData;
        },
        &workData->progressTsfn); // 输出 TSFN 句柄

    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 创建线程安全函数失败: %d", status);
        napi_delete_reference(env, workData->progressCallbackRef);
        napi_delete_reference(env, workData->completionCallbackRef);
        delete workData;
        napi_throw_error(env, nullptr, "创建上传线程安全函数失败");
        return nullptr;
    }
    OH_LOG_INFO(LOG_APP, "SFTP UploadFile: 线程安全函数已创建");

    // --- 创建资源名称 ---
    napi_value resourceName;
    napi_create_string_utf8(env, "SftpMultiUploadFileAsync", NAPI_AUTO_LENGTH, &resourceName);

    status = napi_create_async_work(
        env,
        nullptr,
        resourceName,
        // Execute lambda (后台线程)
        [](napi_env env, void* data) {
            MultiUploadWorkData* wd = static_cast<MultiUploadWorkData*>(data);
            OH_LOG_INFO(LOG_APP, "SftpMultiUpload Execute: Starting upload for %{public}zu files.", wd->items.size());

            // 注册当前上传任务
            {
                std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
                gCurrentTransfers.activeUploadTasks[wd->sessionId] = wd;
            }

            // Get session using sessionId
            SshSession* sshSession = GetSshSessionById(wd->sessionId);
            if (!sshSession) {
                 OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: Invalid SSH session.");
                 for (auto& item : wd->items) {
                    item.completed = true;
                    item.success = false;
                    item.errorMsg = "会话无效或非 SSH 会话";
                 }
                 wd->allCompleted = true;
                 
                 // 清除当前上传任务
                 {
                     std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
                     if (gCurrentTransfers.activeUploadTasks[wd->sessionId] == wd) {
                         gCurrentTransfers.activeUploadTasks.erase(wd->sessionId);
                     }
                 }
                 return;
            }

            wd->totalStartTime = std::chrono::steady_clock::now();
            wd->totalUploadedBytes = 0; // Reset counter
            // --- BEGIN MODIFICATION: Add state for progress callback frequency ---
            off_t lastReportedTotalUploadedBytes = 0;
            wd->lastReportTime = wd->totalStartTime; // <<<--- 初始化上次报告时间
            // --- END MODIFICATION ---

            // --- 添加会话状态检查 ---
            bool isConnected = false;
            try {
                isConnected = sshSession->isConnected();
            } catch (const std::exception& e) {
                 OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: 检查会话连接状态时发生异常: %{public}s", e.what());
                 isConnected = false; // 假定连接断开
            }
            if (!isConnected) {
                OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: SSH 会话已断开，中止上传任务");
                for (auto& item : wd->items) {
                    if (!item.completed) {
                        item.completed = true;
                        item.success = false;
                        item.errorMsg = "SSH 会话已断开";
                    }
                }
                wd->allCompleted = true;
                // 清除当前上传任务
                {
                    std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
                    if (gCurrentTransfers.activeUploadTasks[wd->sessionId] == wd) {
                        gCurrentTransfers.activeUploadTasks.erase(wd->sessionId);
                    }
                }
                return; // 提前退出 Execute lambda
            }
            // --- 会话状态检查结束 ---

            // 新增：在开始上传前立即发送初始进度通知
            if (wd->progressTsfn && wd->tsfnActive) {
                ProgressUpdateData* initialProgressData = new ProgressUpdateData();
                initialProgressData->isCompletionUpdate = false;
                initialProgressData->totalProgress = 0;
                initialProgressData->speed = 0.0;
                initialProgressData->totalFiles = wd->items.size();
                initialProgressData->completedFiles = 0;
                if (!wd->items.empty()) {
                    initialProgressData->currentFile = wd->items[0].remotePath;
                    initialProgressData->currentFileSize = wd->items[0].fileSize;
                } else {
                    initialProgressData->currentFile = "";
                    initialProgressData->currentFileSize = 0;
                }
                
                napi_status status = napi_call_threadsafe_function(
                    wd->progressTsfn, initialProgressData, napi_tsfn_blocking);
                if (status != napi_ok) {
                    OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: 发送初始进度通知失败 (status: %d).", status);
                    delete initialProgressData;
                } else {
                    OH_LOG_INFO(LOG_APP, "SftpMultiUpload Execute: 成功发送初始进度通知 (0%%).");
                }
            }
            
            // 开始上传文件
            for (size_t i = 0; i < wd->items.size(); i++) {
                 // 检查全局取消标志
                 if (wd->cancelRequested.load()) {
                     OH_LOG_WARN(LOG_APP, "SftpMultiUpload Execute: 检测到取消请求，停止后续文件上传");
                     // 将所有未完成的文件标记为已取消
                     for (size_t j = i; j < wd->items.size(); ++j) {
                         auto& item = wd->items[j];
                         if (!item.completed) {
                             item.completed = true;
                             item.success = false;
                             item.errorMsg = "传输被用户取消";
                         }
                     }
                     break; // 退出循环
                 }

                 // --- 添加关键错误检查点 ---
                 bool criticalErrorOccurred = false;
                 std::string firstCriticalErrorMsg = "";
                 // 检查上一个文件是否发生了严重错误 (如果不是第一个文件)
                 if (i > 0 && !wd->items[i-1].success) {
                    // 这里可以根据 wd->items[i-1].errorMsg 判断错误是否严重
                    // 例如，检查是否包含 "断开", "超时", "认证", "EAGAIN", "SFTP Code: 1" (EOF), "SFTP Code: 4" (Failure) 等关键字
                    // 为了简单起见，可以先假设任何失败都是关键错误，强制中止
                    // if (wd->items[i-1].errorMsg.find("...") != std::string::npos) { // 更精细的判断
                    OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: 检测到上一个文件 '%s' 上传失败 (%s)，中止后续上传。",
                                 wd->items[i-1].remotePath.c_str(), wd->items[i-1].errorMsg.c_str());
                    criticalErrorOccurred = true;
                    firstCriticalErrorMsg = "因先前文件上传失败而中止: " + wd->items[i-1].errorMsg;
                    // }
                 }
                 // 也可以在这里主动检查会话状态
                 SshSession* currentSession = GetSshSessionById(wd->sessionId);
                 if (!criticalErrorOccurred && (!currentSession || !currentSession->isConnected())) {
                     OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: 检测到会话断开或无效，中止后续上传。");
                     criticalErrorOccurred = true;
                     firstCriticalErrorMsg = "会话在中途断开或无效";
                 }

                 if (criticalErrorOccurred) {
                     // 将所有剩余未完成的文件标记为失败/中止
                     for (size_t j = i; j < wd->items.size(); ++j) {
                         auto& item = wd->items[j];
                         if (!item.completed) {
                             item.completed = true;
                             item.success = false;
                             item.errorMsg = firstCriticalErrorMsg; // 使用第一个关键错误信息
                         }
                     }
                     break; // *** 退出主上传循环 ***
                 }
                 // --- 连接检查结束 ---

                  if (!wd->tsfnActive) {
                     OH_LOG_WARN(LOG_APP, "SftpMultiUpload Execute: TSFN no longer active, stopping upload.");
                     for (size_t j = i; j < wd->items.size(); ++j) {
                         if (!wd->items[j].completed) { // Only mark incomplete ones as failed
                            wd->items[j].completed = true;
                            wd->items[j].success = false;
                            wd->items[j].errorMsg = "操作被中断或回调失效";
                         }
                     }
                     break; // Exit loop
                 }

                auto& uploadItem = wd->items[i];
                // Skip invalid fd (already checked during parsing, but double check)
                 if (uploadItem.fd < 0) {
                     OH_LOG_WARN(LOG_APP, "SftpMultiUpload Execute: Skipping file %{public}s due to invalid fd (%{public}d).",
                                uploadItem.remotePath.c_str(), uploadItem.fd);
                     uploadItem.completed = true;
                     uploadItem.success = false;
                     uploadItem.errorMsg = "本地文件描述符无效";
                     wd->completedCount++;
                     continue;
                 }

                OH_LOG_INFO(LOG_APP, "SftpMultiUpload Execute: Uploading file %{public}zu/%{public}zu: '%{public}s' (Size: %{public}lu bytes)",
                           i + 1, wd->items.size(), uploadItem.remotePath.c_str(), uploadItem.fileSize);

                auto fileStartTime = std::chrono::steady_clock::now();
                off_t fileStartTotalUploadedBytes = wd->totalUploadedBytes;

                try {
                    bool fileSuccess = sshSession->uploadFile(uploadItem.fd, uploadItem.remotePath,
                        // SFTP 进度回调 - Capture the state variable
                        [&](int progress) { // progress is 0-100 for the current file
                            // 检查是否请求取消
                            if (wd->cancelRequested.load()) {
                                // 取消时发送终止信号
                                return;
                            }
                            
                            if (!wd->tsfnActive) return;

                            off_t currentFileUploaded = (static_cast<off_t>(progress) * uploadItem.fileSize) / 100;
                            off_t diff = currentFileUploaded - uploadItem.uploadedBytes;
                            if (diff < 0) diff = 0;

                            wd->totalUploadedBytes += diff;
                            if (wd->totalUploadedBytes > wd->totalSize) {
                                wd->totalUploadedBytes = wd->totalSize;
                            }

                            uploadItem.progress = progress;
                            uploadItem.uploadedBytes = currentFileUploaded;

                            // --- BEGIN MODIFICATION: N-API Callback Frequency Optimization ---
                            static const off_t upload_progress_report_threshold_bytes = 262144; // 256KB
                            static const long long progress_report_interval_ms = 300; // 强制更新间隔 (毫秒)

                             // Check if enough TOTAL bytes have been uploaded since last report OR if current file is done
                            auto now = std::chrono::steady_clock::now();
                            auto elapsedSinceLastReportMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - wd->lastReportTime).count();

                            bool byteThresholdMet = (wd->totalUploadedBytes - lastReportedTotalUploadedBytes >= upload_progress_report_threshold_bytes);
                            bool timeThresholdMet = (elapsedSinceLastReportMs >= progress_report_interval_ms);
                            bool progressHappened = (wd->totalUploadedBytes > lastReportedTotalUploadedBytes); // 检查是否有实际进度
                            bool fileCompleted = (progress == 100); // 当前文件完成也强制更新

                            // 条件：字节阈值达到 或 (时间阈值达到且确有进度) 或 文件完成
                            if (byteThresholdMet || (timeThresholdMet && progressHappened) || fileCompleted)
                            {
                                // 更新标记
                                lastReportedTotalUploadedBytes = wd->totalUploadedBytes;
                                wd->lastReportTime = now; // <<<--- 更新上次报告时间

                                int totalProgress = 0;
                                if (wd->totalSize > 0) {
                                    totalProgress = (wd->totalUploadedBytes * 100) / wd->totalSize;
                                }
                                totalProgress = std::max(0, std::min(100, totalProgress));

                                double currentSpeed = 0.0; // MB/s
                                auto now = std::chrono::steady_clock::now();
                                auto totalElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - wd->totalStartTime).count();
                                if (totalElapsedMs > 50) {
                                    double speed_bps = (static_cast<double>(wd->totalUploadedBytes) * 1000.0) / totalElapsedMs;
                                    currentSpeed = speed_bps / (1024.0 * 1024.0);
                                }

                                // Create and send progress data
                                ProgressUpdateData* progressData = new ProgressUpdateData();
                                progressData->isCompletionUpdate = false;
                                progressData->totalProgress = totalProgress;
                                progressData->speed = currentSpeed;
                                progressData->totalFiles = wd->items.size();
                                progressData->completedFiles = wd->completedCount;
                                progressData->currentFile = uploadItem.remotePath;
                                progressData->currentFileSize = uploadItem.fileSize;
                                // progressData->uploadedBytes = currentFileUploaded; // If needed

                                // OH_LOG_DEBUG(LOG_APP, "SftpMultiUpload Progress: File '%s' %d%%, Total %d%%, Speed %.2f MB/s",
                                //             uploadItem.remotePath.c_str(), progress, totalProgress, currentSpeed);

                                napi_status tsfn_status = napi_call_threadsafe_function(wd->progressTsfn, progressData, napi_tsfn_nonblocking);
                                if (tsfn_status != napi_ok && tsfn_status != napi_closing) {
                                    OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: napi_call_threadsafe_function failed (%d)", tsfn_status);
                                    delete progressData; // Clean up if call fails
                                    if (tsfn_status == napi_invalid_arg || tsfn_status == napi_generic_failure) {
                                         OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: TSFN invalid, disabling calls.");
                                         wd->tsfnActive = false;
                                    }
                                }
                            }
                            // --- END MODIFICATION: N-API Callback Frequency Optimization ---
                        }); // End of uploadFile progress lambda

                    uploadItem.completed = true;

                    // 检查是否是因为取消而导致的文件上传不完整
                    if (wd->cancelRequested.load() && uploadItem.progress > 0 && uploadItem.progress < 100) {
                         // 如果是取消导致的不完整上传，标记为失败，临时文件由 SftpSession::uploadFile 处理
                         OH_LOG_INFO(LOG_APP, "SftpMultiUpload Execute: 检测到取消请求，将标记 \'%s\' 为失败。临时文件清理由底层处理。",
                                     uploadItem.remotePath.c_str());
                         // <<<--- 确认移除这里的删除逻辑 --->
                         uploadItem.success = false;
                         uploadItem.errorMsg = "传输被用户取消";
                     } else {
                         // 正常完成或其他失败
                         uploadItem.success = fileSuccess;
                     }

                     wd->completedCount++;

                     if (!fileSuccess) {
                         // uploadItem.errorMsg = sshSession->getLastSftpError();
                         if (uploadItem.errorMsg.empty()) uploadItem.errorMsg = "SFTP 上传操作失败";
                         OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: Failed to upload '%s': %s", uploadItem.remotePath.c_str(), uploadItem.errorMsg.c_str());
                         // Correct total bytes if upload failed partially
                          off_t uploadedDiff = uploadItem.uploadedBytes; // Bytes potentially added for this file
                          wd->totalUploadedBytes -= uploadedDiff; // Remove bytes counted for this failed file
                          // Ensure it doesn't go below the starting point for this file
                          if (wd->totalUploadedBytes < fileStartTotalUploadedBytes) {
                              wd->totalUploadedBytes = fileStartTotalUploadedBytes;
                          }
                          uploadItem.uploadedBytes = 0; // Reset failed file's uploaded bytes

                     } else {
                          OH_LOG_INFO(LOG_APP, "SftpMultiUpload Execute: Successfully uploaded '%s'.", uploadItem.remotePath.c_str());
                          // Ensure total bytes reflect full file size for success
                          off_t alreadyUploaded = uploadItem.uploadedBytes;
                          off_t remaining = uploadItem.fileSize - alreadyUploaded;
                          if (remaining > 0) {
                               wd->totalUploadedBytes += remaining;
                          } else if (remaining < 0) { // Overcounted?
                               wd->totalUploadedBytes += remaining; // Add negative remaining
                          }
                          uploadItem.uploadedBytes = uploadItem.fileSize;
                          uploadItem.progress = 100;
                     }

                 } catch (const std::exception& e) {
                     OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: Exception for '%s': %s", uploadItem.remotePath.c_str(), e.what());
                     uploadItem.completed = true;
                     uploadItem.success = false;
                     uploadItem.errorMsg = std::string("上传异常: ") + e.what();

                     // <<<--- 确认移除这里的删除逻辑 --->
                     OH_LOG_WARN(LOG_APP, "SftpMultiUpload Execute: 上传 \'%s\' 时捕获异常，将标记为失败。临时文件清理由底层处理。", uploadItem.remotePath.c_str());

                     wd->completedCount++;
                      // Correct total bytes
                      wd->totalUploadedBytes -= uploadItem.uploadedBytes;
                      if (wd->totalUploadedBytes < fileStartTotalUploadedBytes) {
                          wd->totalUploadedBytes = fileStartTotalUploadedBytes;
                      }
                      uploadItem.uploadedBytes = 0;

                 } catch (...) {
                     OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Execute: Unknown exception for '%s'.", uploadItem.remotePath.c_str());
                     uploadItem.completed = true;
                     uploadItem.success = false;
                     uploadItem.errorMsg = "上传时发生未知异常";

                     // <<<--- 确认移除这里的删除逻辑 --->
                     OH_LOG_WARN(LOG_APP, "SftpMultiUpload Execute: 上传 \'%s\' 时捕获未知异常，将标记为失败。临时文件清理由底层处理。", uploadItem.remotePath.c_str());

                     wd->completedCount++;
                     // Correct total bytes
                     wd->totalUploadedBytes -= uploadItem.uploadedBytes;
                     if (wd->totalUploadedBytes < fileStartTotalUploadedBytes) {
                          wd->totalUploadedBytes = fileStartTotalUploadedBytes;
                      }
                     uploadItem.uploadedBytes = 0;
                 }
             } // End of for loop

            wd->allCompleted = true;
            OH_LOG_INFO(LOG_APP, "SftpMultiUpload Execute: Finished processing all %{public}zu files. Completed count: %{public}d",
                        wd->items.size(), wd->completedCount);

            // 清除当前上传任务
            {
                std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
                if (gCurrentTransfers.activeUploadTasks[wd->sessionId] == wd) {
                    gCurrentTransfers.activeUploadTasks.erase(wd->sessionId);
                }
            }
        },
        // Complete lambda (JS 主线程)
        [](napi_env env, napi_status async_status, void* data) {
            MultiUploadWorkData* wd = static_cast<MultiUploadWorkData*>(data);
            OH_LOG_INFO(LOG_APP, "SftpMultiUpload Complete: Running in JS thread. Async status: %d", async_status);
            
            // 确保当前上传任务已清除
            {
                std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
                if (gCurrentTransfers.activeUploadTasks[wd->sessionId] == wd) {
                    gCurrentTransfers.activeUploadTasks.erase(wd->sessionId);
                }
            }

            // 1. Get completion callback
            napi_value completionCallback = nullptr, global = nullptr;
            bool completionCbOk = false;
            if (wd->completionCallbackRef != nullptr) {
                if (napi_get_reference_value(env, wd->completionCallbackRef, &completionCallback) == napi_ok) {
                    napi_get_global(env, &global);
                    completionCbOk = (completionCallback != nullptr && global != nullptr);
                 }
            }
             if (!completionCbOk) {
                 OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Complete: Failed to get completion callback function.");
             }

            // 2. Prepare final result
            napi_value finalArgs[2]; // [error, resultDetails]
            napi_value resultDetails;
            napi_create_object(env, &resultDetails); // Always create details object

            bool overallSuccess = true;
            std::string finalErrorMsg = "";
            int successfulUploads = 0;

            if (async_status != napi_ok) {
                OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Complete: Async work itself failed (%d).", async_status);
                overallSuccess = false;
                finalErrorMsg = "异步上传任务失败或被取消";
            } else {
                 OH_LOG_INFO(LOG_APP, "SftpMultiUpload Complete: Checking individual file results.");
                 for (const auto& item : wd->items) {
                     if (!item.success) {
                         overallSuccess = false;
                         if (finalErrorMsg.empty()) {
                             finalErrorMsg = "文件 '" + item.remotePath + "' 上传失败: " + item.errorMsg;
                         }
                         OH_LOG_WARN(LOG_APP, "SftpMultiUpload Complete: File '%s' failed: %s", item.remotePath.c_str(), item.errorMsg.c_str());
                     } else {
                         successfulUploads++;
                     }
                 }
                 if (overallSuccess) {
                      OH_LOG_INFO(LOG_APP, "SftpMultiUpload Complete: All %d files uploaded successfully.", successfulUploads);
                 } else {
                     if (finalErrorMsg.empty()) finalErrorMsg = "部分文件上传失败"; // Generic fallback
                      OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Complete: Finished with errors. Successful: %d/%zu. First error: %s",
                                   successfulUploads, wd->items.size(), finalErrorMsg.c_str());
                 }
                  // Sanity check
                 if (wd->completedCount != wd->items.size()) {
                      OH_LOG_WARN(LOG_APP, "SftpMultiUpload Complete: Mismatch! completedCount (%d) != totalFiles (%zu)",
                                   wd->completedCount, wd->items.size());
                     // This might indicate an interruption or logic error
                     overallSuccess = false; // Consider it a failure
                     if (finalErrorMsg.empty()) finalErrorMsg = "内部状态不一致或操作中断";
                 }
            }

            // 3. Build resultDetails object (matches UploadProgressItem)
            napi_value val_details;
            napi_get_boolean(env, true, &val_details); // completed = true
            int finalProgress = 0;
            if (overallSuccess) finalProgress = 100;
            else if (wd->totalSize > 0) finalProgress = (wd->totalUploadedBytes * 100) / wd->totalSize;
            finalProgress = std::max(0, std::min(100, finalProgress));
            napi_create_int32(env, finalProgress, &val_details); // progress
            napi_set_named_property(env, resultDetails, "progress", val_details);
            napi_create_double(env, 0.0, &val_details); // speed = 0.0
            napi_set_named_property(env, resultDetails, "speed", val_details);
            napi_create_int32(env, wd->items.size(), &val_details); // totalFiles
            napi_set_named_property(env, resultDetails, "totalFiles", val_details);
            napi_create_int32(env, successfulUploads, &val_details); // completedFiles
            napi_set_named_property(env, resultDetails, "completedFiles", val_details);
            // Optionally add remotePath (maybe the target dir?) or leave null
            // Optionally add currentFileSize (meaningless here) or leave null

            // 4. Set final callback args
            if (overallSuccess) {
                napi_get_null(env, &finalArgs[0]); // error = null
            } else {
                napi_value errorMsgStr;
                napi_create_string_utf8(env, finalErrorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsgStr);
                napi_create_error(env, nullptr, errorMsgStr, &finalArgs[0]); // error = Error object
            }
            finalArgs[1] = resultDetails; // result = details object

            // 5. Call completion callback
            if (completionCbOk) {
                 OH_LOG_INFO(LOG_APP, "SftpMultiUpload Complete: Invoking JS completion callback.");
                 napi_value completionCallResult;
                 napi_status completion_call_status = napi_call_function(env, global, completionCallback, 2, finalArgs, &completionCallResult);
                 if (completion_call_status != napi_ok) {
                     OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Complete: Failed to call JS completion callback (%d).", completion_call_status);
                      bool is_exception_pending = false;
                     napi_is_exception_pending(env, &is_exception_pending);
                     if (is_exception_pending) {
                         napi_value exception;
                         napi_get_and_clear_last_exception(env, &exception);
                         OH_LOG_ERROR(LOG_APP, "SftpMultiUpload Complete: Exception in JS completion callback.");
                     }
                 }
            }

            // 6. Clean up resources
            // 6a. Release TSFN
            if (wd->progressTsfn != nullptr && wd->tsfnActive) {
                 OH_LOG_INFO(LOG_APP, "SftpMultiUpload Complete: Releasing TSFN.");
                 wd->tsfnActive = false;
                 napi_status release_status = napi_release_threadsafe_function(wd->progressTsfn, napi_tsfn_release);
                 if (release_status != napi_ok) {
                      OH_LOG_WARN(LOG_APP, "SftpMultiUpload Complete: napi_release_threadsafe_function failed (%d).", release_status);
                 }
                 wd->progressTsfn = nullptr;
            }

            // 6b. Delete NAPI references
            if (wd->progressCallbackRef != nullptr) {
                 napi_delete_reference(env, wd->progressCallbackRef);
                 wd->progressCallbackRef = nullptr;
            }
            if (wd->completionCallbackRef != nullptr) {
                 napi_delete_reference(env, wd->completionCallbackRef);
                 wd->completionCallbackRef = nullptr;
            }

            // 6c. Delete async work handle
            napi_delete_async_work(env, wd->work);

            // 6d. Delete work data
            delete wd;

            OH_LOG_INFO(LOG_APP, "SftpMultiUpload Complete: Finished.");
        },
        workData, // data
        &workData->work
    );

    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 创建异步工作失败: %d", status);
        // Cleanup if async work creation failed
        if (workData->progressTsfn != nullptr) {
            napi_release_threadsafe_function(workData->progressTsfn, napi_tsfn_abort);
        }
        if (workData->progressCallbackRef != nullptr) napi_delete_reference(env, workData->progressCallbackRef);
        if (workData->completionCallbackRef != nullptr) napi_delete_reference(env, workData->completionCallbackRef);
        delete workData;
        napi_throw_error(env, nullptr, "创建异步上传任务失败");
        return nullptr;
    }

    // --- Queue async work ---
    status = napi_queue_async_work(env, workData->work);
    if (status != napi_ok) {
         OH_LOG_ERROR(LOG_APP, "SFTP UploadFile: 无法将异步工作加入队列: %d", status);
         // Complete callback will still be called with error status and handle cleanup
         napi_throw_error(env, nullptr, "无法调度异步上传任务");
         // Don't delete workData here
         return nullptr; // Indicate failure to queue
    }
    OH_LOG_INFO(LOG_APP, "SFTP UploadFile: Async work queued successfully.");

    // Return undefined
    napi_value undefined_result;
    napi_get_undefined(env, &undefined_result);
    return undefined_result;
}

// 下载文件 (异步, 单文件, 带进度)
static napi_value DownloadFile(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "SFTP DownloadFile: Entry");
    size_t argc = 5;  // sessionId, remotePath, fd, progressCallback, completionCallback
    napi_value args[5];
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (status != napi_ok || argc < 5) {
        OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 需要 5 个参数, 收到 %zu", argc);
        napi_throw_type_error(env, nullptr, "需要 5 个参数: sessionId, remotePath(string), fd(number), progressCallback(function), completionCallback(function)");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: No active session");
        napi_throw_error(env, nullptr, "No active session");
        return nullptr;
    }

    // 检查参数类型
    napi_valuetype pathType, fdType, progressCbType, completionCbType;
    napi_typeof(env, args[1], &pathType);
    napi_typeof(env, args[2], &fdType);
    napi_typeof(env, args[3], &progressCbType);
    napi_typeof(env, args[4], &completionCbType);

    if (pathType != napi_string || fdType != napi_number || progressCbType != napi_function || completionCbType != napi_function) {
        OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 参数类型错误");
        napi_throw_type_error(env, nullptr, "参数类型错误: 需要(string, number, function, function)");
        return nullptr;
    }

    // --- 创建工作数据 ---
    auto workData = new DownloadWorkData();
    workData->sessionId = sessionId;
    workData->remotePath = SafeGetStringFromNapi(env, args[1]);
    workData->fd = SafeGetInt32FromNapi(env, args[2]);
    workData->success = false;
    workData->fileSize = -1; // Initialize to unknown
    workData->downloadedBytes = 0;
    workData->progressCallbackRef = nullptr;
    workData->completionCallbackRef = nullptr;
    workData->progressTsfn = nullptr;
    workData->tsfnActive = true;

    if (workData->fd < 0) {
        OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 无效的文件描述符 fd=%d", workData->fd);
        delete workData;
        napi_throw_error(env, nullptr, "无效的本地文件描述符");
        return nullptr;
    }
    if (workData->remotePath.empty()) {
         OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 远程路径不能为空");
         delete workData;
         napi_throw_error(env, nullptr, "远程路径不能为空");
         return nullptr;
    }
    OH_LOG_INFO(LOG_APP, "SFTP DownloadFile: 请求下载 '%s' 到 fd %d", workData->remotePath.c_str(), workData->fd);

    // --- 并发防御：同一会话仅允许一个活动下载任务 ---
    {
        std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
        auto it = gCurrentTransfers.activeDownloadTasks.find(workData->sessionId);
        if (it != gCurrentTransfers.activeDownloadTasks.end() && it->second != nullptr) {
            OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: Session %d already has an active download task. Rejecting new request.", workData->sessionId);
            delete workData;
            napi_throw_error(env, nullptr, "当前会话已有进行中的下载任务，请稍后再试");
            return nullptr;
        }
    }

    // --- 保存回调函数引用 ---
    status = napi_create_reference(env, args[3], 1, &workData->progressCallbackRef);
    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 创建进度回调引用失败");
        delete workData;
        napi_throw_error(env, nullptr, "创建进度回调引用失败");
        return nullptr;
    }
    status = napi_create_reference(env, args[4], 1, &workData->completionCallbackRef);
     if (status != napi_ok) {
         OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 创建完成回调引用失败");
         napi_delete_reference(env, workData->progressCallbackRef);
         delete workData;
         napi_throw_error(env, nullptr, "创建完成回调引用失败");
         return nullptr;
     }

    // --- 创建线程安全函数 (TSFN) for Progress ---
    napi_value tsfnResourceName;
    napi_create_string_utf8(env, "SftpDownloadProgressCallback", NAPI_AUTO_LENGTH, &tsfnResourceName);

    status = napi_create_threadsafe_function(
        env,
        args[3], // JS progress callback function
        nullptr,
        tsfnResourceName,
        0, // max_queue_size
        1, // initial_thread_count
        workData, // thread_finalize_data
        // TSFN finalize callback
        [](napi_env env, void* finalize_data, void* context) {
             auto* wd = static_cast<DownloadWorkData*>(finalize_data);
             OH_LOG_INFO(LOG_APP, "SFTP Download TSFN finalize callback. Setting tsfnActive=false.");
             if (wd) {
                 wd->tsfnActive.store(false);
             }
        },
        nullptr, // context
        // CallJs lambda (主 JS 线程)
         [](napi_env env, napi_value js_callback, void* context, void* data) {
            if (env == nullptr || js_callback == nullptr || data == nullptr) {
                 OH_LOG_ERROR(LOG_APP, "SFTP Download TSFN CallJs: Invalid arguments.");
                 if (data) delete static_cast<ProgressUpdateData*>(data);
                 return;
             }
            ProgressUpdateData* progressData = static_cast<ProgressUpdateData*>(data);
            // OH_LOG_DEBUG(LOG_APP, "SFTP Download TSFN CallJs: Progress Update (Total: %d%%).", progressData->totalProgress);

            napi_value global, progressInfo, result;
            napi_get_global(env, &global);
            napi_create_object(env, &progressInfo);
            napi_value jsArgs[2]; // [error, progressDetails]

            // Build progressDetails object (matches DownloadProgressItem)
            napi_value val;
            napi_get_boolean(env, progressData->isCompletionUpdate, &val); // completed
            napi_set_named_property(env, progressInfo, "completed", val);
            napi_create_int32(env, progressData->totalProgress, &val);       // progress
            napi_set_named_property(env, progressInfo, "progress", val);
            napi_create_double(env, progressData->speed, &val);              // speed (MB/s)
            napi_set_named_property(env, progressInfo, "speed", val);
            if (!progressData->currentFile.empty()) {                       // remotePath
                napi_create_string_utf8(env, progressData->currentFile.c_str(), NAPI_AUTO_LENGTH, &val);
                napi_set_named_property(env, progressInfo, "remotePath", val);
            }
            napi_create_int64(env, (int64_t)progressData->currentFileSize, &val); // fileSize
            napi_set_named_property(env, progressInfo, "fileSize", val);
            napi_create_int64(env, (int64_t)progressData->downloadedBytes, &val); // downloadedBytes
            napi_set_named_property(env, progressInfo, "downloadedBytes", val);

            // Set callback args
            if (progressData->isCompletionUpdate && !progressData->overallSuccess) {
                napi_value errorMsgStr;
                napi_create_string_utf8(env, progressData->errorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsgStr);
                napi_create_error(env, nullptr, errorMsgStr, &jsArgs[0]);
            } else {
                 napi_get_null(env, &jsArgs[0]);
            }
            jsArgs[1] = progressInfo;

            // Call JS progress callback
            napi_status call_status = napi_call_function(env, global, js_callback, 2, jsArgs, &result);
            if (call_status != napi_ok) {
                OH_LOG_ERROR(LOG_APP, "SFTP Download TSFN CallJs: Failed to call JS progress callback (%d).", call_status);
                bool is_exception_pending = false;
                 napi_is_exception_pending(env, &is_exception_pending);
                 if (is_exception_pending) {
                     napi_value exception;
                     napi_get_and_clear_last_exception(env, &exception);
                     OH_LOG_ERROR(LOG_APP, "SFTP Download TSFN CallJs: Exception in JS callback.");
                 }
            }
            delete progressData; // Clean up data passed from background thread
        },
        &workData->progressTsfn // Output TSFN handle
    );

    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 创建线程安全函数失败: %d", status);
        napi_delete_reference(env, workData->progressCallbackRef);
        napi_delete_reference(env, workData->completionCallbackRef);
        delete workData;
        napi_throw_error(env, nullptr, "创建下载进度线程安全函数失败");
        return nullptr;
    }
    OH_LOG_INFO(LOG_APP, "SFTP DownloadFile: 线程安全函数已创建");

    // --- 创建异步工作 ---
    napi_value resourceName;
    napi_create_string_utf8(env, "SftpDownloadFileAsync", NAPI_AUTO_LENGTH, &resourceName);

    status = napi_create_async_work(
        env,
        nullptr,
        resourceName,
        // Execute lambda (后台线程)
        [](napi_env env, void* data) {
            DownloadWorkData* wd = static_cast<DownloadWorkData*>(data);
            OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Starting download for '%{public}s'.", wd->remotePath.c_str());

            // Get session using sessionId
            SshSession* sshSession = GetSshSessionById(wd->sessionId);
            if (!sshSession) {
                wd->success = false;
                wd->errorMsg = "会话无效或非 SSH 会话";
                OH_LOG_ERROR(LOG_APP, "SftpDownload Execute: Invalid SSH session.");
                // *** 添加: 清除活跃任务引用 ***
                {
                    std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
                    if (gCurrentTransfers.activeDownloadTasks[wd->sessionId] == wd) {
                        OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Clearing active download task reference on session error for '%{public}s'.", wd->remotePath.c_str());
                        gCurrentTransfers.activeDownloadTasks.erase(wd->sessionId);
                    }
                }
                return;
            }

            // --- BEGIN: Throttling state variables ---
            off_t lastReportedBytes = 0;
            std::chrono::steady_clock::time_point lastReportTime = std::chrono::steady_clock::now(); // Initialize here for elapsed time calculation later
            const off_t download_progress_report_threshold_bytes = 262144; // 256KB threshold
            const long long progress_report_interval_ms = 300; // 300ms interval
            // --- END: Throttling state variables ---

            // *** 将 try 块移到这里 ***
            try {
                // Try to get file size
                FileInfo fileInfo;
                // --->>> 现在这个调用在 try 块内部 <<<---
                if (sshSession->getFileInfo(wd->remotePath, fileInfo)) {
                    wd->fileSize = fileInfo.size;
                    OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Remote file size for '%{public}s': %{public}lu bytes", wd->remotePath.c_str(), wd->fileSize);
                } else {
                    // 如果 getFileInfo 返回 false（理论上不应发生，因为现在它会抛出异常）
                    wd->fileSize = -1; // Indicate unknown size
                    OH_LOG_WARN(LOG_APP, "SftpDownload Execute: sshSession->getFileInfo returned false for '%{public}s'.", wd->remotePath.c_str());
                    // 我们仍然可以尝试下载，但没有文件大小信息
                }

                wd->startTime = std::chrono::steady_clock::now(); // Reset start time after potential getFileInfo delay
                lastReportTime = wd->startTime; // Initialize last report time with actual start time
                wd->downloadedBytes = 0; // Reset counter

                OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Calling sshSession->downloadFile...");
                wd->success = sshSession->downloadFile(wd->remotePath, wd->fd,
                    // SFTP 进度回调 (byte count) - 加入节流逻辑
                    // --- BEGIN: Modified Progress Lambda with Throttling ---
                    [&](off_t bytesDownloaded) {
                        if (!wd->tsfnActive.load()) return; // Use .load() for atomic read

                        wd->downloadedBytes = bytesDownloaded; // Update total downloaded bytes in workData immediately

                        auto now = std::chrono::steady_clock::now();
                        auto elapsedSinceLastReportMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastReportTime).count();
                        off_t bytesSinceLastReport = bytesDownloaded - lastReportedBytes;
                        bool isFinalUpdate = (wd->fileSize >= 0 && bytesDownloaded == wd->fileSize); // Check if this is the final update

                        bool byteThresholdMet = (bytesSinceLastReport >= download_progress_report_threshold_bytes);
                        bool timeThresholdMet = (elapsedSinceLastReportMs >= progress_report_interval_ms);
                        bool progressHappened = (bytesDownloaded > lastReportedBytes); // Ensure actual progress occurred

                        // Report progress if byte threshold met OR (time threshold met AND progress happened) OR it's the final update
                        if (byteThresholdMet || (timeThresholdMet && progressHappened) || isFinalUpdate) {
                            lastReportedBytes = bytesDownloaded;
                            lastReportTime = now;

                            // Calculate progress percentage
                            int progressPercent = -1; // Unknown progress if size is unknown
                            if (wd->fileSize >= 0) {
                                progressPercent = (wd->fileSize == 0) ? 100 : static_cast<int>((wd->downloadedBytes * 100) / wd->fileSize);
                                progressPercent = std::max(0, std::min(100, progressPercent));
                            }

                            // Calculate speed (consider using EMA or calculate based on interval if preferred)
                            double speed_mbps = 0.0;
                            auto totalElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - wd->startTime).count();
                            if (totalElapsedMs > 50) { // Avoid division by zero or tiny intervals
                                double speed_bps = (static_cast<double>(wd->downloadedBytes) * 1000.0) / totalElapsedMs;
                                speed_mbps = speed_bps / (1024.0 * 1024.0);
                            }

                            // Create and send progress data
                            ProgressUpdateData* progressData = new ProgressUpdateData();
                            progressData->isCompletionUpdate = false; // This is a progress update
                            progressData->totalProgress = progressPercent;
                            progressData->speed = speed_mbps;
                            progressData->totalFiles = 1; // Always 1 for single download
                            progressData->completedFiles = 0; // Not completed yet
                            progressData->currentFile = wd->remotePath;
                            progressData->currentFileSize = wd->fileSize;
                            progressData->downloadedBytes = wd->downloadedBytes; // Send current total

                            napi_status tsfn_status = napi_call_threadsafe_function(wd->progressTsfn, progressData, napi_tsfn_nonblocking);
                            if (tsfn_status != napi_ok && tsfn_status != napi_closing) {
                                OH_LOG_ERROR(LOG_APP, "SftpDownload Execute: napi_call_threadsafe_function failed (%{public}d)", tsfn_status);
                                delete progressData; // Clean up if call fails
                                if (tsfn_status == napi_invalid_arg || tsfn_status == napi_generic_failure) {
                                     OH_LOG_ERROR(LOG_APP, "SftpDownload Execute: TSFN invalid, disabling calls.");
                                     wd->tsfnActive.store(false); // Stop trying to call TSFN
                                }
                            }
                            // else: progressData is now owned by TSFN, will be deleted in CallJs lambda
                        }
                    }
                    // --- END: Modified Progress Lambda with Throttling ---
                    ); // End of downloadFile progress lambda call

                // After downloadFile completes (successfully or not)
                // Ensure a final progress update is sent if download was successful and throttling might have skipped the last one
                if (wd->success && wd->tsfnActive.load()) {
                     // Check if the very last state (potentially 100%) wasn't reported due to throttling
                     bool finalStateReported = (lastReportedBytes == wd->downloadedBytes);
                     if (!finalStateReported || (wd->fileSize >=0 && lastReportedBytes != wd->fileSize)) {
                          OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Sending final explicit progress update after loop.");
                          int finalProgressPercent = (wd->fileSize >= 0) ? 100 : -1; // Assume 100% if size known, else unknown
                          double final_avg_speed_mbps = 0.0;
                          auto final_now = std::chrono::steady_clock::now();
                          auto final_totalElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(final_now - wd->startTime).count();
                           if (final_totalElapsedMs > 0) {
                               double final_speed_bps = (static_cast<double>(wd->downloadedBytes) * 1000.0) / final_totalElapsedMs;
                               final_avg_speed_mbps = final_speed_bps / (1024.0 * 1024.0);
                           }

                          ProgressUpdateData* finalProgressData = new ProgressUpdateData();
                          finalProgressData->isCompletionUpdate = false; // Still a progress update conceptually before completion callback
                          finalProgressData->totalProgress = finalProgressPercent;
                          finalProgressData->speed = final_avg_speed_mbps; // Report average speed at end
                          finalProgressData->totalFiles = 1;
                          finalProgressData->completedFiles = 0; // Still 0 here, completion marks it 1
                          finalProgressData->currentFile = wd->remotePath;
                          finalProgressData->currentFileSize = wd->fileSize;
                          finalProgressData->downloadedBytes = wd->downloadedBytes;

                          napi_status tsfn_status = napi_call_threadsafe_function(wd->progressTsfn, finalProgressData, napi_tsfn_nonblocking);
                          if (tsfn_status != napi_ok && tsfn_status != napi_closing) {
                               OH_LOG_ERROR(LOG_APP, "SftpDownload Execute: Final napi_call_threadsafe_function failed (%{public}d)", tsfn_status);
                               delete finalProgressData;
                               if (tsfn_status == napi_invalid_arg || tsfn_status == napi_generic_failure) {
                                   wd->tsfnActive.store(false);
                               }
                          }
                     }
                }


                if (!wd->success) {
                    // wd->errorMsg = sshSession->getLastSftpError(); // SftpSession should throw now
                     if (wd->errorMsg.empty()) wd->errorMsg = "文件下载失败"; // Fallback message
                     OH_LOG_ERROR(LOG_APP, "SftpDownload Execute: Failed for '%{public}s'. Error: %{public}s", wd->remotePath.c_str(), wd->errorMsg.c_str());
                } else {
                    OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Successfully downloaded '%{public}s'.", wd->remotePath.c_str());
                     // Ensure final byte count matches file size if known
                     if (wd->fileSize >= 0 && wd->downloadedBytes != wd->fileSize) {
                          OH_LOG_WARN(LOG_APP, "SftpDownload Execute: Final byte count mismatch for '%{public}s'. Reported: %{public}lu, Expected: %{public}lu. Correcting.",
                                       wd->remotePath.c_str(), wd->downloadedBytes, wd->fileSize);
                          wd->downloadedBytes = wd->fileSize;
                     }
                }

            } catch (const std::exception& e) {
                wd->success = false;
                wd->errorMsg = std::string("下载异常: ") + e.what(); // Use exception message
                OH_LOG_ERROR(LOG_APP, "SftpDownload Execute: Exception caught for '%{public}s': %{public}s", wd->remotePath.c_str(), e.what());
                 // Check for specific errors like timeout from exception message if needed
                 if (std::string(e.what()).find("timeout") != std::string::npos) {
                     wd->errorMsg = "文件下载超时";
                 }
            } catch (...) {
                wd->success = false;
                wd->errorMsg = "下载时发生未知异常";
                OH_LOG_ERROR(LOG_APP, "SftpDownload Execute: Unknown exception caught for '%{public}s'.", wd->remotePath.c_str());
            }
            OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Background work finished for '%{public}s'. Success: %{public}d", wd->remotePath.c_str(), wd->success);

            // *** 添加: 无论成功与否，都清除活跃任务引用 ***
            {
                std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
                if (gCurrentTransfers.activeDownloadTasks[wd->sessionId] == wd) {
                    OH_LOG_INFO(LOG_APP, "SftpDownload Execute: Clearing active download task reference for '%{public}s'.", wd->remotePath.c_str());
                    gCurrentTransfers.activeDownloadTasks.erase(wd->sessionId);
                }
            }
            // *** 添加结束 ***
        },
        // Complete lambda (JS 主线程)
        [](napi_env env, napi_status async_status, void* data) {
            DownloadWorkData* wd = static_cast<DownloadWorkData*>(data);
            // *** 添加日志: 确认 wd 是否有效 ***
            if (!wd) {
                OH_LOG_ERROR(LOG_APP, "SftpDownload Complete: Critical error! workData (wd) is null!");
                // 尝试进行最小化清理
                 if (data) {
                    // *** 修正类型 ***
                    // napi_value work_handle_val = reinterpret_cast<DownloadWorkData*>(data)->work;
                    napi_async_work work_handle_val = reinterpret_cast<DownloadWorkData*>(data)->work;
                    if (work_handle_val) {
                         // *** 现在类型匹配了 ***
                        napi_delete_async_work(env, work_handle_val);
                    }
                 }
                return;
            }
            // *** 日志结束 ***

            OH_LOG_INFO(LOG_APP, "SftpDownload Complete: Running in JS thread for '%{public}s'. Async status: %{public}d, Success: %{public}d",
                        wd->remotePath.c_str(), async_status, wd->success);

            // 1. Get completion callback
            napi_value completionCallback = nullptr, global = nullptr;
            bool completionCbOk = false;
            if (wd->completionCallbackRef != nullptr) {
                if (napi_get_reference_value(env, wd->completionCallbackRef, &completionCallback) == napi_ok && completionCallback != nullptr) {
                    if (napi_get_global(env, &global) == napi_ok && global != nullptr) {
                       completionCbOk = true;
                    }
                }
            }
            if (!completionCbOk) {
                 OH_LOG_ERROR(LOG_APP, "SftpDownload Complete: Failed to get valid completion callback or global for '%{public}s'.", wd->remotePath.c_str());
                 // 不能调用回调，但仍需清理资源
            }

            // 2. Prepare final result
            napi_value finalArgs[2]; // [error, resultDetails]
            napi_value resultDetails = nullptr;
            napi_create_object(env, &resultDetails); // Always create

            // 3. Determine final success state and error message
            bool finalOverallSuccess = wd->success && (async_status == napi_ok);
            std::string finalErrorMsg = wd->errorMsg;
            if (!finalOverallSuccess && async_status != napi_ok) {
                 finalErrorMsg = "异步下载任务失败或被取消 (status: " + std::to_string(async_status) + ")";
            } else if (!finalOverallSuccess && finalErrorMsg.empty()){
                 finalErrorMsg = "下载操作失败 (未知原因)";
            }


            // 4. Build final resultDetails (matches DownloadProgressItem)
            napi_value val_details;
            napi_get_boolean(env, true, &val_details); // completed = true
            napi_set_named_property(env, resultDetails, "completed", val_details);
            int finalProgress = -1;
            if (finalOverallSuccess) finalProgress = 100;
            else if (wd->fileSize >= 0) finalProgress = (wd->fileSize == 0) ? 100 : static_cast<int>((wd->downloadedBytes * 100) / wd->fileSize);
            finalProgress = std::max(-1, std::min(100, finalProgress)); // Keep -1 if size unknown & failed
            napi_create_int32(env, finalProgress, &val_details);       // progress
            napi_set_named_property(env, resultDetails, "progress", val_details);
            napi_create_double(env, 0.0, &val_details);              // speed = 0.0
            napi_set_named_property(env, resultDetails, "speed", val_details);
             if (!wd->remotePath.empty()) {                         // remotePath
                 napi_create_string_utf8(env, wd->remotePath.c_str(), NAPI_AUTO_LENGTH, &val_details);
                 napi_set_named_property(env, resultDetails, "remotePath", val_details);
             }
            napi_create_int64(env, (int64_t)wd->fileSize, &val_details); // fileSize
            napi_set_named_property(env, resultDetails, "fileSize", val_details);
            napi_create_int64(env, (int64_t)wd->downloadedBytes, &val_details); // downloadedBytes
            napi_set_named_property(env, resultDetails, "downloadedBytes", val_details);


            // 5. Set final callback args
            if (finalOverallSuccess) {
                napi_get_null(env, &finalArgs[0]); // error = null
            } else {
                napi_value errorMsgStr;
                napi_create_string_utf8(env, finalErrorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsgStr);
                napi_create_error(env, nullptr, errorMsgStr, &finalArgs[0]); // error = Error object
            }
            finalArgs[1] = resultDetails; // result = details object

            // 6. Call completion callback if possible
            if (completionCbOk) {
                 OH_LOG_INFO(LOG_APP, "SftpDownload Complete: Invoking JS completion callback for '%{public}s'.", wd->remotePath.c_str());
                 napi_value completionCallResult;
                 napi_status completion_call_status = napi_call_function(env, global, completionCallback, 2, finalArgs, &completionCallResult);
                 if (completion_call_status != napi_ok) {
                     OH_LOG_ERROR(LOG_APP, "SftpDownload Complete: Failed to call JS completion callback (%{public}d).", completion_call_status);
                      bool is_exception_pending = false;
                     napi_is_exception_pending(env, &is_exception_pending);
                     if (is_exception_pending) {
                         napi_value exception;
                         napi_get_and_clear_last_exception(env, &exception);
                         OH_LOG_ERROR(LOG_APP, "SftpDownload Complete: Exception in JS completion callback.");
                     }
                 }
            }

            // 7. Clean up resources
            // 7a. Release TSFN
            if (wd->progressTsfn != nullptr) { // Use wd->progressTsfn directly
                 if (wd->tsfnActive.load()) { // Check atomic flag before releasing
                     OH_LOG_INFO(LOG_APP, "SftpDownload Complete: Releasing TSFN.");
                     wd->tsfnActive.store(false); // Mark as inactive
                     napi_status release_status = napi_release_threadsafe_function(wd->progressTsfn, napi_tsfn_release);
                     if (release_status != napi_ok) {
                          OH_LOG_WARN(LOG_APP, "SftpDownload Complete: napi_release_threadsafe_function failed (%{public}d).", release_status);
                     }
                 } else {
                     OH_LOG_INFO(LOG_APP, "SftpDownload Complete: TSFN already marked inactive or released.");
                 }
                 wd->progressTsfn = nullptr; // Set handle to null after release attempt
            }

            // 7b. Delete NAPI references
            if (wd->progressCallbackRef != nullptr) {
                 napi_delete_reference(env, wd->progressCallbackRef);
                 wd->progressCallbackRef = nullptr;
            }
            if (wd->completionCallbackRef != nullptr) {
                 napi_delete_reference(env, wd->completionCallbackRef);
                 wd->completionCallbackRef = nullptr;
            }

            // 7c. Delete async work handle
            napi_delete_async_work(env, wd->work);

            // 7d. Delete work data
             OH_LOG_INFO(LOG_APP, "SftpDownload Complete: Deleting workData for '%{public}s'.", wd->remotePath.c_str());
            delete wd;
            // wd = nullptr; // No need to set to null here, it's going out of scope

            OH_LOG_INFO(LOG_APP, "SftpDownload Complete: Finished.");
            // *** REMOVED DUPLICATE CLEANUP LOGIC FROM HERE ***
        },
        workData, // data
        &workData->work // work handle
    );

    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "SFTP DownloadFile: 创建异步工作失败: %d", status);
        // Cleanup if async work creation failed
        if (workData->progressTsfn != nullptr) {
            napi_release_threadsafe_function(workData->progressTsfn, napi_tsfn_abort);
        }
        if (workData->progressCallbackRef != nullptr) napi_delete_reference(env, workData->progressCallbackRef);
        if (workData->completionCallbackRef != nullptr) napi_delete_reference(env, workData->completionCallbackRef);
        delete workData;
        napi_throw_error(env, nullptr, "创建异步下载任务失败");
        return nullptr;
    }

    // --- 保存当前传输任务 ---
    {
        std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
        gCurrentTransfers.activeDownloadTasks[workData->sessionId] = workData;
        OH_LOG_INFO(LOG_APP, "SFTP DownloadFile: 设置当前活跃下载任务 (SessionId=%d, Path=%s)", 
                   workData->sessionId, workData->remotePath.c_str());
    }

    // --- 创建并排列异步工作 ---
    napi_queue_async_work(env, workData->work);
    OH_LOG_INFO(LOG_APP, "SFTP DownloadFile: 异步下载工作已排队");

    // 返回undefined
    napi_value undefined_result;
    napi_get_undefined(env, &undefined_result);
    return undefined_result;
}

// --- Helper for Simple Async Operations (Delete, CreateDir, DeleteDir, Rename) ---
static napi_value SimpleSftpAsyncOperation(napi_env env, napi_callback_info info, const char* resourceNameStr,
                                           std::function<bool(SshSession*, SimpleWorkData*)> executeLogic)
{
    size_t argc = 0;
    napi_value* args = nullptr;
    bool isRename = (strcmp(resourceNameStr, "SftpRename") == 0);

    if (isRename) {
        argc = 4; // sessionId, oldPath, newPath, callback
        args = new napi_value[argc];
    } else {
        argc = 3; // sessionId, path, callback
        args = new napi_value[argc];
    }
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if ((isRename && argc < 4) || (!isRename && argc < 3)) {
        delete[] args;
        napi_throw_type_error(env, nullptr, "参数数量错误");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        delete[] args;
        napi_throw_error(env, nullptr, "No active session");
        return nullptr;
    }

    // Check types
    napi_valuetype pathType1, pathType2, callbackType;
    napi_typeof(env, args[1], &pathType1);
    if (isRename) napi_typeof(env, args[2], &pathType2);
    napi_typeof(env, args[isRename ? 3 : 2], &callbackType);

    if (pathType1 != napi_string || (isRename && pathType2 != napi_string) || callbackType != napi_function) {
        delete[] args;
        napi_throw_type_error(env, nullptr, "参数类型错误");
        return nullptr;
    }

    // Create work data
    SimpleWorkData* workData = new SimpleWorkData();
    workData->sessionId = sessionId;
    workData->path = SafeGetStringFromNapi(env, args[1]); // Also oldPath for rename
    if (isRename) {
        workData->oldPath = workData->path;
        workData->newPath = SafeGetStringFromNapi(env, args[2]);
    }
    workData->success = false;
    workData->executeFunc = executeLogic; // <-- 将 executeLogic 存入 workData

    // Save callback ref
    napi_create_reference(env, args[isRename ? 3 : 2], 1, &workData->callback);
    delete[] args; // Args values are copied or referenced, safe to delete array

    // Create async work
    napi_value resourceName;
    napi_create_string_utf8(env, resourceNameStr, NAPI_AUTO_LENGTH, &resourceName);

    napi_create_async_work(
        env, nullptr, resourceName,
        // Execute (Background) - 移除捕获列表
        [](napi_env env, void* data) {
            SimpleWorkData* wd = static_cast<SimpleWorkData*>(data);
            // --- BEGIN MODIFICATION: Add try-catch and error code extraction ---
            wd->sftpErrorCode = -1; // Reset code
            wd->success = false;    // Assume failure initially
            // --- END MODIFICATION ---

            // Get session using sessionId
            SshSession* sshSession = GetSshSessionById(wd->sessionId);
            if (!sshSession) {
                wd->success = false;
                wd->errorMsg = "Session is not an SSH session or is invalid";
                return;
            }
            if (!wd->executeFunc) { // 检查 function 是否有效
                wd->success = false;
                wd->errorMsg = "Internal error: executeFunc is null";
                return;
            }
            try {
                // 通过 workData 中的 executeFunc 调用具体逻辑
                // wd->success = wd->executeFunc(sshSession, wd);
                // if (!wd->success && wd->errorMsg.empty()) {
                //     // wd->errorMsg = sshSession->getLastSftpError();
                //     if (wd->errorMsg.empty()) wd->errorMsg = "SFTP 操作失败"; // Generic fallback
                // }

                // --- BEGIN MODIFICATION: Call executeFunc within try, set success only if no exception ---
                wd->executeFunc(sshSession, wd); // This might throw an exception now
                wd->success = true; // Set success to true ONLY if executeFunc completes without throwing
                // --- END MODIFICATION ---

            } catch (const std::exception& e) {
                // --- BEGIN MODIFICATION: Handle exception, extract error code ---
                wd->success = false;
                wd->errorMsg = e.what(); // Get message from exception
                wd->sftpErrorCode = ExtractSftpCode(wd->errorMsg); // Try to extract SFTP code
                OH_LOG_ERROR(LOG_APP, "SimpleSftpAsync Execute Exception: %{public}s, SFTP Code: %{public}d",
                             wd->errorMsg.c_str(), wd->sftpErrorCode);
                // --- END MODIFICATION ---
            } catch (...) {
                // --- BEGIN MODIFICATION: Handle unknown exception ---
                wd->success = false;
                wd->errorMsg = "执行 SFTP 操作时发生未知错误";
                wd->sftpErrorCode = -1; // No specific code for unknown errors
                OH_LOG_ERROR(LOG_APP, "SimpleSftpAsync Execute Unknown Exception");
                // --- END MODIFICATION ---
            }
        },
        // Complete (JS Thread) - 保持不变
        [](napi_env env, napi_status status, void* data) {
            SimpleWorkData* wd = static_cast<SimpleWorkData*>(data);

            napi_value callback, global;
            napi_get_reference_value(env, wd->callback, &callback);
            napi_get_global(env, &global);

            napi_value cbArgs[2]; // [error, result_boolean]

            if (status != napi_ok) {
                 wd->success = false;
                 wd->errorMsg = "Async SFTP task failed or cancelled (status: " + std::to_string(status) + ")";
            }

            if (wd->success) {
                napi_get_null(env, &cbArgs[0]); // error = null
                napi_get_boolean(env, true, &cbArgs[1]); // result = true
            } else {
                napi_value errorMsg;
                napi_create_string_utf8(env, wd->errorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsg);
                napi_create_error(env, nullptr, errorMsg, &cbArgs[0]); // error = Error object
                napi_get_boolean(env, false, &cbArgs[1]); // result = false

                // --- BEGIN MODIFICATION: Add error code to JS Error object ---
                if (wd->sftpErrorCode != -1) {
                    napi_value errorCodeValue;
                    napi_create_int32(env, wd->sftpErrorCode, &errorCodeValue);
                    napi_set_named_property(env, cbArgs[0], "code", errorCodeValue);
                    OH_LOG_ERROR(LOG_APP, "SimpleSftpAsync Complete Failed (SFTP Code: %{public}d, Msg: %{public}s)", wd->sftpErrorCode, wd->errorMsg.c_str());
                } else {
                    OH_LOG_ERROR(LOG_APP, "SimpleSftpAsync Complete Failed (Msg: %{public}s)", wd->errorMsg.c_str());
                }
                // --- END MODIFICATION ---
            }

            // Call JS callback
            napi_value result;
            napi_call_function(env, global, callback, 2, cbArgs, &result); // Ignore result

            // Clean up
            napi_delete_reference(env, wd->callback);
            napi_delete_async_work(env, wd->work);
            delete wd;
        },
        workData, &workData->work
    );

    // Queue async work
    napi_queue_async_work(env, workData->work);

    // Return undefined
    napi_value undefined_result;
    napi_get_undefined(env, &undefined_result);
    return undefined_result;
}

// 删除文件 (异步)
static napi_value DeleteFile(napi_env env, napi_callback_info info) {
    return SimpleSftpAsyncOperation(env, info, "SftpDeleteFile",
        [](SshSession* sshSession, SimpleWorkData* wd) {
            OH_LOG_INFO(LOG_APP, "SftpDeleteFile Execute: Deleting '%s'", wd->path.c_str());
            return sshSession->deleteFile(wd->path);
        });
}

// 创建目录 (异步)
static napi_value CreateDirectory(napi_env env, napi_callback_info info) {
    return SimpleSftpAsyncOperation(env, info, "SftpCreateDirectory",
        [](SshSession* sshSession, SimpleWorkData* wd) {
             OH_LOG_INFO(LOG_APP, "SftpCreateDirectory Execute: Creating '%s'", wd->path.c_str());
            return sshSession->createDirectory(wd->path);
        });
}

// 删除目录 (异步)
static napi_value DeleteDirectory(napi_env env, napi_callback_info info) {
     return SimpleSftpAsyncOperation(env, info, "SftpDeleteDirectory",
        [](SshSession* sshSession, SimpleWorkData* wd) {
             OH_LOG_INFO(LOG_APP, "SftpDeleteDirectory Execute: Deleting '%s'", wd->path.c_str());
            return sshSession->deleteDirectory(wd->path);
        });
}

// 重命名文件/目录 (异步)
static napi_value Rename(napi_env env, napi_callback_info info) {
    return SimpleSftpAsyncOperation(env, info, "SftpRename",
        [](SshSession* sshSession, SimpleWorkData* wd) {
             OH_LOG_INFO(LOG_APP, "SftpRename Execute: Renaming '%s' to '%s'", wd->oldPath.c_str(), wd->newPath.c_str());
            return sshSession->rename(wd->oldPath, wd->newPath);
        });
}

// 获取文件信息 (同步) - 注意: SFTP stat 操作通常很快，同步可能可以接受，但异步更好
static napi_value GetFileInfo(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "SFTP GetFileInfo: Entry (Sync)");
    size_t argc = 2; // sessionId, path
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_type_error(env, nullptr, "需要 2 个参数: sessionId, path");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        napi_throw_error(env, nullptr, "No active session");
        return nullptr;
    }

    napi_valuetype pathType;
    napi_typeof(env, args[1], &pathType);
    if (pathType != napi_string) {
        napi_throw_type_error(env, nullptr, "参数 path 必须是字符串");
        return nullptr;
    }

    std::string pathStr = SafeGetStringFromNapi(env, args[1]);

    FileInfo fileInfo;
    bool success = false;
    std::string errorMsg;
    try {
        OH_LOG_INFO(LOG_APP, "SFTP GetFileInfo: Calling sshSession->getFileInfo for '%s'", pathStr.c_str());
        success = sshSession->getFileInfo(pathStr, fileInfo);
        if (!success) {
            // errorMsg = sshSession->getLastSftpError();
             if (errorMsg.empty()) errorMsg = "无法获取文件信息";
        }
    } catch (const std::exception& e) {
        success = false;
        errorMsg = e.what();
    } catch (...) {
        success = false;
        errorMsg = "获取文件信息时发生未知错误";
    }

    if (!success) {
         OH_LOG_ERROR(LOG_APP, "SFTP GetFileInfo: Failed for '%s': %s", pathStr.c_str(), errorMsg.c_str());
        // Return null or throw error? Let's throw for consistency with initSftp.
         napi_throw_error(env, "SFTP_ERROR", errorMsg.c_str());
        return nullptr;
    }

    OH_LOG_INFO(LOG_APP, "SFTP GetFileInfo: Success for '%s'", pathStr.c_str());
    // Pass the obtained sshSession to the helper
    return convertToNapiValue(env, convertToSftpFileInfo(fileInfo, sshSession));
}

// 修改文件权限 (同步)
static napi_value SetPermissions(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "SFTP SetPermissions: Entry (Sync)");
    size_t argc = 3; // sessionId, path, permissions (uint32)
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        napi_throw_type_error(env, nullptr, "需要 3 个参数: sessionId, path, permissions");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        napi_throw_error(env, nullptr, "No active session");
        return nullptr;
    }

    napi_valuetype pathType, permType;
    napi_typeof(env, args[1], &pathType);
    napi_typeof(env, args[2], &permType);
    if (pathType != napi_string || permType != napi_number) {
        napi_throw_type_error(env, nullptr, "参数类型错误: 需要 (string, number)");
        return nullptr;
    }

    std::string pathStr = SafeGetStringFromNapi(env, args[1]);
    uint32_t permissions;
    napi_get_value_uint32(env, args[2], &permissions);

    bool success = false;
    std::string errorMsg;
    try {
         OH_LOG_INFO(LOG_APP, "SFTP SetPermissions: Calling sshSession->setPermissions for '%s' to %o", pathStr.c_str(), permissions);
        success = sshSession->setPermissions(pathStr, permissions);
         if (!success) {
            // errorMsg = sshSession->getLastSftpError();
            if (errorMsg.empty()) errorMsg = "设置权限失败";
        }
    } catch (const std::exception& e) {
        success = false;
        errorMsg = e.what();
    } catch (...) {
        success = false;
        errorMsg = "设置权限时发生未知错误";
    }

     if (!success) {
         OH_LOG_ERROR(LOG_APP, "SFTP SetPermissions: Failed for '%s': %s", pathStr.c_str(), errorMsg.c_str());
         napi_throw_error(env, "SFTP_ERROR", errorMsg.c_str());
        return nullptr;
    }

    OH_LOG_INFO(LOG_APP, "SFTP SetPermissions: Success for '%s'", pathStr.c_str());
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// 修改文件时间戳 (同步)
static napi_value SetFileTime(napi_env env, napi_callback_info info) {
     OH_LOG_INFO(LOG_APP, "SFTP SetFileTime: Entry (Sync)");
    size_t argc = 4; // sessionId, path, mtime (int64), atime (int64)
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 4) {
        napi_throw_type_error(env, nullptr, "需要 4 个参数: sessionId, path, mtime, atime");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        napi_throw_error(env, nullptr, "No active session");
        return nullptr;
    }

    napi_valuetype pathType, mtimeType, atimeType;
    napi_typeof(env, args[1], &pathType);
    napi_typeof(env, args[2], &mtimeType);
    napi_typeof(env, args[3], &atimeType);
    if (pathType != napi_string || mtimeType != napi_number || atimeType != napi_number) {
        napi_throw_type_error(env, nullptr, "参数类型错误: 需要 (string, number, number)");
        return nullptr;
    }

    std::string pathStr = SafeGetStringFromNapi(env, args[1]);
    int64_t mtimeValue, atimeValue;
    napi_get_value_int64(env, args[2], &mtimeValue);
    napi_get_value_int64(env, args[3], &atimeValue);
    uint64_t mtime = (uint64_t)mtimeValue;
    uint64_t atime = (uint64_t)atimeValue;

    bool success = false;
    std::string errorMsg;
     try {
         OH_LOG_INFO(LOG_APP, "SFTP SetFileTime: Calling sshSession->setFileTime for '%s' (m:%{public}lu a:%{public}lu)", pathStr.c_str(), mtime, atime);
        success = sshSession->setFileTime(pathStr, mtime, atime);
         if (!success) {
            // errorMsg = sshSession->getLastSftpError();
            if (errorMsg.empty()) errorMsg = "设置文件时间失败";
        }
    } catch (const std::exception& e) {
        success = false;
        errorMsg = e.what();
    } catch (...) {
        success = false;
        errorMsg = "设置文件时间时发生未知错误";
    }

      if (!success) {
         OH_LOG_ERROR(LOG_APP, "SFTP SetFileTime: Failed for '%s': %s", pathStr.c_str(), errorMsg.c_str());
         napi_throw_error(env, "SFTP_ERROR", errorMsg.c_str());
        return nullptr;
    }

    OH_LOG_INFO(LOG_APP, "SFTP SetFileTime: Success for '%s'", pathStr.c_str());
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// 取消传输
static napi_value NAPI_CancelTransfer(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: Entry");

    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "需要 1 个参数: sessionId");
        return nullptr;
    }

    int sessionId = SafeGetInt32FromNapi(env, args[0]);
    SshSession* sshSession = GetSshSessionById(sessionId);
    if (!sshSession) {
        OH_LOG_ERROR(LOG_APP, "SFTP NAPI_CancelTransfer: No active session.");
        napi_throw_error(env, nullptr, "No active session to cancel transfer");
        return nullptr;
    }

    // 获取并标记当前的传输任务为已取消
    bool taskFound = false;
    {
        std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
        
        // 查找指定sessionId的上传任务
        auto uploadIt = gCurrentTransfers.activeUploadTasks.find(sessionId);
        if (uploadIt != gCurrentTransfers.activeUploadTasks.end() && uploadIt->second != nullptr) {
            OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: 标记sessionId=%d的上传任务为已取消", sessionId);
            uploadIt->second->cancelRequested = true;
            taskFound = true;
        }
        
        // 查找指定sessionId的下载任务
        auto downloadIt = gCurrentTransfers.activeDownloadTasks.find(sessionId);
        if (downloadIt != gCurrentTransfers.activeDownloadTasks.end() && downloadIt->second != nullptr) {
            OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: 标记sessionId=%d的下载任务为已取消", sessionId);
            downloadIt->second->tsfnActive = false;
            // 确保下载任务被标记为已取消
            OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: 确保下载所有相关取消标志被设置");
            taskFound = true;
        }
    }

    if (!taskFound) {
        OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: 没有找到sessionId=%d的活动传输任务", sessionId);
    }

    OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: Calling sshSession->cancelTransfer().");
    bool requestSent = sshSession->cancelTransfer();
    OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: Cancel request sent status: %d", requestSent);

    // 确保下载任务立即停止，直接在活跃下载任务中设置取消标志
    {
        std::lock_guard<std::mutex> lock(gCurrentTransfers.mutex);
        auto downloadIt = gCurrentTransfers.activeDownloadTasks.find(sessionId);
        if (downloadIt != gCurrentTransfers.activeDownloadTasks.end() && downloadIt->second != nullptr) {
            OH_LOG_INFO(LOG_APP, "SFTP NAPI_CancelTransfer: 强制停止sessionId=%d的下载任务", sessionId);
            // 使下载回调停止发送进度更新
            downloadIt->second->tsfnActive = false;
        }
    }

    // 返回 undefined 或 bool 表示请求是否已发送? 返回 undefined
    napi_value undefined_result;
    napi_get_undefined(env, &undefined_result);
    return undefined_result;
}


// --- 注册函数 ---

void RegisterSftpFunctions(napi_env env, napi_value exports) {
    OH_LOG_INFO(LOG_APP, "Registering SFTP N-API functions...");
    napi_property_descriptor sftpDesc[] = {
        { "initSftp", nullptr, InitSftp, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "listDirectory", nullptr, ListDirectory, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "uploadFile", nullptr, UploadFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "downloadFile", nullptr, DownloadFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "deleteFile", nullptr, DeleteFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createDirectory", nullptr, CreateDirectory, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "deleteDirectory", nullptr, DeleteDirectory, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "rename", nullptr, Rename, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getFileInfo", nullptr, GetFileInfo, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setPermissions", nullptr, SetPermissions, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setFileTime", nullptr, SetFileTime, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "cancelTransfer", nullptr, NAPI_CancelTransfer, nullptr, nullptr, nullptr, napi_default, nullptr },
    };

    napi_status status = napi_define_properties(env, exports, sizeof(sftpDesc) / sizeof(sftpDesc[0]), sftpDesc);
    if (status != napi_ok) {
        OH_LOG_FATAL(LOG_APP, "Failed to define SFTP N-API properties!");
        // Handle error, maybe throw exception?
    } else {
         OH_LOG_INFO(LOG_APP, "SFTP N-API functions registered successfully.");
    }
}
