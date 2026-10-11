//
//  AIProcessingQueue.swift
//  HJD Camera Pro
//
//  AI 任务队列：串行/并发调度、进度、取消、重试、温度与内存压力时自动降级。
//

import Foundation
import Combine

final class AIProcessingQueue: ObservableObject {

    static let shared = AIProcessingQueue()

    @Published private(set) var currentTask: AIProcessingTask?
    @Published private(set) var pendingTasks: [AIProcessingTask] = []
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var degradedMode: Bool = false

    private let queue = DispatchQueue(label: "com.hjd.camera.aiQueue", qos: .userInitiated)
    private var maxConcurrent: Int = 1
    private var activeCount: Int = 0
    private var thermalToken: NSObjectProtocol?

    private init() {
        // Block-based observer (this class is not an NSObject).
        thermalToken = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thermalStateChanged()
        }
    }

    // MARK: - Enqueue

    /// 入队一个 AI 任务。
    func enqueue(_ task: AIProcessingTask) {
        queue.async {
            self.pendingTasks.append(task)
            self.processNext()
        }
    }

    /// 取消指定任务（接受 UUID 字符串）。
    func cancel(taskID: String) {
        queue.async {
            self.pendingTasks.removeAll { $0.id.uuidString == taskID }
        }
    }

    /// 取消全部。
    func cancelAll() {
        queue.async {
            self.pendingTasks.removeAll()
        }
    }

    // MARK: - Scheduling

    private func processNext() {
        guard activeCount < maxConcurrent, let task = pendingTasks.first else {
            return
        }
        pendingTasks.removeFirst()
        activeCount += 1

        DispatchQueue.main.async {
            self.currentTask = task
            self.isProcessing = true
        }

        // 实际任务执行由各 Pipeline 提供的闭包完成；闭包无参数标签。
        DispatchQueue.global().async {
            task.executionBlock?(
                { progress in
                    DispatchQueue.main.async {
                        var updated = task
                        updated.progress = progress
                        updated.state = .processing(progress: progress)
                        self.currentTask = updated
                    }
                },
                { result in
                    self.queue.async {
                        self.activeCount -= 1
                        DispatchQueue.main.async {
                            var finished = task
                            finished.state = result
                                ? .completed
                                : .failed(error: "AI 处理失败")
                            finished.progress = result ? 1.0 : finished.progress
                            self.currentTask = nil
                            self.isProcessing = !self.pendingTasks.isEmpty
                        }
                        self.processNext()
                    }
                }
            )
        }
    }

    // MARK: - Thermal / Memory

    private func thermalStateChanged() {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal, .fair:
            degradedMode = false
            maxConcurrent = 1
        case .serious:
            degradedMode = true
            maxConcurrent = 1
        case .critical:
            degradedMode = true
            maxConcurrent = 0 // 暂停新任务
        @unknown default:
            break
        }
    }

    /// 预计剩余时间（秒）。
    func estimatedRemainingTime() -> TimeInterval {
        let avgTaskDuration: TimeInterval = 8.0
        return TimeInterval(pendingTasks.count) * avgTaskDuration
    }
}

// MARK: - AIProcessingTask 扩展（执行闭包）

extension AIProcessingTask {
    /// 任务执行闭包：传入进度回调与完成回调（无标签）。
    var executionBlock: ((@escaping (Double) -> Void, @escaping (Bool) -> Void) -> Void)? {
        get { objc_getAssociatedObject(self, &Keys.execBlock) as? ((@escaping (Double) -> Void, @escaping (Bool) -> Void) -> Void) }
        set { objc_setAssociatedObject(self, &Keys.execBlock, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

private struct Keys {
    static var execBlock: UInt8 = 0
}
