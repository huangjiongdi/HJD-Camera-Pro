//
//  ShutterTrace.swift
//  HJD Camera Pro
//
//  快门拍照全链路埋点 + 崩溃捕获。
//
//  目的：真机上"一点快门就闪退"在云编译阶段无法复现。该模块把快门点击 →
//  会话/连接检查 → 闪光灯白名单 → 拍照参数 → AVCapturePhotoOutput.capturePhoto
//  → 各个 delegate 回调 → 原图/成片入库 的每一步都【同步落盘】到诊断日志，
//  并安装 NSException / signal 处理器，闪退前把崩溃原因与调用栈写进同一文件。
//
//  查看路径：App 内「设置 → 关于 → 诊断日志」，闪退重开后最后一条 `!!!` 开头
//  的记录就是崩溃原因，其上方 `[SHUTTER]` 记录是最后执行到的步骤。
//

import Foundation

final class ShutterTrace {
    static let shared = ShutterTrace()

    private static var installed = false
    private var tapCounter = 0
    /// 最近一次快门编号（delegate 回调中无法直接拿到 tap，用它关联）。
    static var lastTap = 0
    /// 本次启动时检测到的、上次运行遗留的崩溃记录（用于相机界面置顶提示）。
    static private(set) var lastCrashReport: String?
    private let lock = NSLock()
    /// 崩溃 signal 处理器用的日志文件路径（C 字符串，signal 上下文中安全访问）。
    private var crashPathC: [CChar] = []

    private init() {}

    // MARK: - 安装（App 启动时调用一次）

    static func install() {
        guard !installed else { return }
        installed = true
        // 先读取上一次运行遗留的崩溃记录（在追加本次启动日志之前）。
        readPreviousCrash()
        shared.prepareCrashPath()
        shared.installExceptionHandler()
        shared.installSignalHandlers()
        let device = DeviceCapabilityManager.shared.compatibilityReport()
        DiagnosticLogger.shared.trace(
            "=== ShutterTrace 已安装 | device=\(device["device"] ?? "?") iOS=\(device["iOS"] ?? "?") ==="
        )
    }

    /// 本次拍照成功后清除遗留崩溃提示。
    static func clearCrashReport() {
        lastCrashReport = nil
    }

    private static func readPreviousCrash() {
        let text = DiagnosticLogger.shared.currentLogContents()
        // 找最后一条崩溃记录（"!!!" 开头），取随后约 1500 字。
        if let range = text.range(of: "!!!", options: .backwards) {
            let snippet = text[range.lowerBound...]
            lastCrashReport = String(snippet.prefix(1500))
        }
    }

    // MARK: - 埋点

    /// 每次快门点击开始一个新编号。
    @discardableResult
    static func nextTap() -> Int {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        shared.tapCounter += 1
        lastTap = shared.tapCounter
        return shared.tapCounter
    }

    /// 记录一个拍照链路步骤。
    static func mark(_ tap: Int, _ step: String, extra: String = "") {
        let suffix = extra.isEmpty ? "" : " | \(extra)"
        DiagnosticLogger.shared.trace("tap#\(tap) \(step)\(suffix)")
    }

    // MARK: - 崩溃捕获

    private func prepareCrashPath() {
        crashPathC = Array(DiagnosticLogger.shared.fileURL.path.utf8CString)
    }

    /// NSException（如 AVFoundation 参数非法 NSInvalidArgumentException）。
    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { ex in
            let stack = ex.callStackSymbols.prefix(40).joined(separator: "\n")
            let body = """
            !!! NSException 崩溃: \(ex.name.rawValue)
            !!! 原因: \(ex.reason ?? "nil")
            !!! userInfo: \(ex.userInfo ?? [:])
            !!! 调用栈:
            \(stack)
            """
            DiagnosticLogger.shared.traceCrash(body)
        }
    }

    /// Swift fatalError / 越界 / 强制解包等走 SIGTRAP/SIGABRT。
    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        ShutterTrace.shared.writeSignalCrash(sig)
    }

    private func installSignalHandlers() {
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGTRAP, SIGFPE]
        for s in signals {
            Darwin.signal(s, Self.signalHandler)
        }
    }

    private func writeSignalCrash(_ sig: Int32) {
        let name = Self.signalName(sig)
        // 尽力补一份调用栈（非严格信号安全，best-effort）。
        let stack = Thread.callStackSymbols.prefix(40).joined(separator: "\n")
        // 信号上下文中只做最小化、确定性的底层 IO，不加锁、不碰 ObjC 文件句柄。
        let body = "!!! 致命信号 \(sig) (\(name))，调用栈:\n\(stack)\n"
        body.withCString { cstr in
            crashPathC.withUnsafeMutableBufferPointer { buf in
                guard let path = buf.baseAddress else { return }
                let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
                guard fd >= 0 else { return }
                write(fd, cstr, strlen(cstr))
                close(fd)
            }
        }
        Darwin.signal(sig, SIG_DFL)
        raise(sig)
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGILL:  return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS:  return "SIGBUS"
        case SIGTRAP: return "SIGTRAP"
        case SIGFPE:  return "SIGFPE"
        default:      return "UNKNOWN"
        }
    }
}
