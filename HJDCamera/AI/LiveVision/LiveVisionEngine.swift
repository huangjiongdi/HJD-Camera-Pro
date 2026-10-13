//
//  LiveVisionEngine.swift
//  HJD Camera Pro
//
//  HJD Live Vision AI —— 实时取景框识别引擎。
//
//  在低分辨率预览帧上做低延迟、可降级的本地识别（全部离线，不联网）：
//    · 人脸 / 人体（VNDetectFaceRectangles / VNDetectHumanRectangles）
//    · 猫、狗等动物（VNRecognizeAnimals）
//    · 文字（VNRecognizeText）
//    · 场景分类（系统内置 VNClassifyImageRequest，零额外模型）
//    · 通用物体（内嵌 YOLOv3FP16，VNCoreML 包装，COCO 80 类）
//
//  高耗时请求（YOLO / 文字 / 分类）按帧轮询，不每帧全跑；人脸/人体/动物
//  这类轻量请求每帧都跑。随温度/帧率由 LiveQualityController 进一步降级。
//  结果发布到 AppState，由 LiveVisionHUD 叠加到取景框。
//

import Vision
import CoreML
import CoreImage
import UIKit

// MARK: - 识别结果类型

enum LiveSubjectKind: String {
    case face, person, animal, text, vehicle, plant, object
}

struct LiveSubject: Identifiable {
    let id = UUID()
    let kind: LiveSubjectKind
    let label: String
    let confidence: Float
    /// 归一化边界框，Vision 坐标系（原点左下）。
    let boundingBox: CGRect
}

struct LiveVisionResult {
    var subjects: [LiveSubject]
    var sceneLabel: String
    var latency: TimeInterval
}

// MARK: - 引擎

final class LiveVisionEngine {
    static let shared = LiveVisionEngine()

    /// 仅在视频数据回调队列上访问，避免加锁开销。
    private var frameCount: Int = 0
    private var lastSceneLabel: String = ""
    private var yoloModel: VNCoreMLModel?
    private var yoloTried = false

    private init() {}

    // MARK: - 公开入口

    /// 分析一帧。orientation 决定 Vision 坐标方向（通常 .right，iPhone 竖屏）。
    func analyze(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation,
                 level: LivePreviewLevel) -> LiveVisionResult {
        let start = CFAbsoluteTimeGetCurrent()
        frameCount &+= 1
        let n = frameCount

        // 高耗时请求的轮询间隔，随档位变化。
        let yoloEvery   = level == .highDetail ? 3 : (level == .balanced ? 5 : 8)
        let textEvery   = level == .highDetail ? 6 : 10
        let classEvery  = level == .highDetail ? 8 : 12

        var subjects: [LiveSubject] = []

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                           orientation: orientation,
                                           options: [:])

        // 1) 每帧必跑：人脸 / 人体 / 动物（轻量）
        subjects.append(contentsOf: runHumanAndAnimal(handler))

        // 2) 轮询：文字
        if n % textEvery == 0 {
            if let texts = runText(handler), !texts.isEmpty {
                subjects.append(contentsOf: texts)
            }
        }

        // 3) 轮询：YOLO 通用物体（车辆/植物/食物等）
        if n % yoloEvery == 0, let model = loadYOLO() {
            subjects.append(contentsOf: runYOLO(handler, model: model))
        }

        // 4) 轮询：系统场景分类（最稳定，作为场景标签）
        if n % classEvery == 0 {
            if let label = runClassification(handler) {
                lastSceneLabel = label
            }
        }

        // 去重：同一类主体最多保留置信度最高的若干个，避免 HUD 刷屏。
        let merged = cap(subjects, perKind: 6)

        let latency = CFAbsoluteTimeGetCurrent() - start
        return LiveVisionResult(subjects: merged,
                                sceneLabel: lastSceneLabel,
                                latency: latency)
    }

    // MARK: - 人脸 / 人体 / 动物

    private func runHumanAndAnimal(_ handler: VNImageRequestHandler) -> [LiveSubject] {
        var out: [LiveSubject] = []

        let faceReq = VNDetectFaceRectanglesRequest()
        let humanReq = VNDetectHumanRectanglesRequest()
        humanReq.upperBodyOnly = false
        let animalReq = VNRecognizeAnimalsRequest()

        handler.performAll([faceReq, humanReq, animalReq])

        for case let obs as VNFaceObservation in faceReq.results ?? [] {
            out.append(LiveSubject(kind: .face, label: "人脸",
                                   confidence: Float(obs.confidence),
                                   boundingBox: obs.boundingBox))
        }
        for case let obs as VNHumanObservation in humanReq.results ?? [] {
            out.append(LiveSubject(kind: .person, label: "人物",
                                   confidence: Float(obs.confidence),
                                   boundingBox: obs.boundingBox))
        }
        // VNRecognizeAnimalsRequest 的结果是 VNRecognizedObjectObservation，
        // labels 为 "cat"/"dog"（不存在独立的 VNRecognizedAnimalObservation 类）。
        for case let obs as VNRecognizedObjectObservation in animalReq.results ?? [] {
            let cn = animalName(obs.labels.first?.identifier ?? "animal")
            out.append(LiveSubject(kind: .animal, label: cn,
                                   confidence: Float(obs.labels.first?.confidence ?? obs.confidence),
                                   boundingBox: obs.boundingBox))
        }
        return out
    }

    private func animalName(_ id: String) -> String {
        switch id.lowercased() {
        case "cat": return "猫"
        case "dog": return "狗"
        default: return "动物"
        }
    }

    // MARK: - 文字

    private func runText(_ handler: VNImageRequestHandler) -> [LiveSubject]? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = false
        guard handler.performAll([req]) else { return nil }
        let results = (req.results ?? []).prefix(3)
        return results.map {
            LiveSubject(kind: .text, label: "文字",
                        confidence: Float($0.confidence),
                        boundingBox: $0.boundingBox)
        }
    }

    // MARK: - 系统场景分类

    private func runClassification(_ handler: VNImageRequestHandler) -> String? {
        let req = VNClassifyImageRequest()
        guard handler.performAll([req]) else { return nil }
        let top = (req.results ?? [])
            .filter { $0.confidence > 0.25 }
            .prefix(2)
            .compactMap { sceneName($0.identifier) }
        guard !top.isEmpty else { return "" }
        return top.joined(separator: " · ")
    }

    // MARK: - YOLO 通用物体

    private func loadYOLO() -> VNCoreMLModel? {
        if yoloModel != nil { return yoloModel }
        guard !yoloTried else { return nil }
        yoloTried = true
        guard let url = Bundle.main.url(forResource: "YOLOv3FP16", withExtension: "mlmodelc") else {
            return nil
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let ml = try MLModel(contentsOf: url, configuration: config)
            yoloModel = try VNCoreMLModel(for: ml)
        } catch {
            yoloModel = nil
        }
        return yoloModel
    }

    private func runYOLO(_ handler: VNImageRequestHandler, model: VNCoreMLModel) -> [LiveSubject] {
        let req = VNCoreMLRequest(model: model)
        req.imageCropAndScaleOption = .scaleFill
        guard handler.performAll([req]) else { return [] }

        var out: [LiveSubject] = []
        for case let obs as VNRecognizedObjectObservation in req.results ?? [] {
            guard let label = obs.labels.max(by: { $0.confidence < $1.confidence }) else { continue }
            if label.confidence < 0.45 { continue }
            // 与人脸/人物/动物重复的类别交给专用请求，避免重复框。
            let id = label.identifier.lowercased()
            if id == "person" || id == "cat" || id == "dog" { continue }
            let (kind, cn) = yoloName(id)
            out.append(LiveSubject(kind: kind, label: cn,
                                   confidence: label.confidence,
                                   boundingBox: obs.boundingBox))
        }
        return out
    }

    /// COCO 类别 -> 中文 + 大类（仅列出常用项，其余归“物体”）。
    private func yoloName(_ id: String) -> (LiveSubjectKind, String) {
        let vehicles: Set<String> = ["car","motorbike","bus","truck","bicycle","train","boat","aeroplane"]
        let plants: Set<String> = ["potted plant","bird"]
        let table: [String: String] = [
            "car": "汽车", "motorbike": "摩托车", "bus": "公交车", "truck": "卡车",
            "bicycle": "自行车", "train": "火车", "boat": "船", "aeroplane": "飞机",
            "bird": "鸟", "horse": "马", "sheep": "羊", "cow": "牛", "elephant": "大象",
            "bear": "熊", "zebra": "斑马", "giraffe": "长颈鹿",
            "potted plant": "盆栽", "flower": "花", "tree": "树",
            "bottle": "瓶子", "cup": "杯子", "fork": "叉子", "knife": "刀",
            "spoon": "勺子", "bowl": "碗", "banana": "香蕉", "apple": "苹果",
            "sandwich": "三明治", "orange": "橙子", "broccoli": "西兰花", "carrot": "胡萝卜",
            "pizza": "披萨", "donut": "甜甜圈", "cake": "蛋糕",
            "chair": "椅子", "couch": "沙发", "bed": "床", "dining table": "餐桌",
            "toilet": "马桶", "tv": "电视", "laptop": "笔记本", "mouse": "鼠标",
            "remote": "遥控器", "keyboard": "键盘", "cell phone": "手机",
            "microwave": "微波炉", "oven": "烤箱", "toaster": "烤面包机",
            "sink": "水槽", "refrigerator": "冰箱", "book": "书", "clock": "时钟",
            "vase": "花瓶", "scissors": "剪刀", "teddy bear": "玩偶",
            "hair drier": "吹风机", "toothbrush": "牙刷",
            "backpack": "背包", "umbrella": "雨伞", "handbag": "手提包",
            "tie": "领带", "suitcase": "行李箱", "sports ball": "球",
            "skateboard": "滑板", "surfboard": "冲浪板", "tennis racket": "网球拍",
            "wine glass": "酒杯", "kite": "风筝", "baseball bat": "棒球棒",
            "skis": "滑雪板", "snowboard": "单板"
        ]
        if vehicles.contains(id) { return (.vehicle, table[id] ?? "车辆") }
        if plants.contains(id) { return (.plant, table[id] ?? "植物") }
        return (.object, table[id] ?? "物体")
    }

    // MARK: - 系统分类标签 -> 中文场景

    private func sceneName(_ raw: String) -> String? {
        let r = raw.lowercased()
        if r.contains("moon") { return "月亮" }
        if r.contains("sky") || r.contains("cloud") { return "天空" }
        if r.contains("sunset") || r.contains("sunrise") { return "日落" }
        if r.contains("building") || r.contains("skyscraper") || r.contains("tower") { return "建筑" }
        if r.contains("tree") || r.contains("forest") || r.contains("plant") || r.contains("grass") { return "植物" }
        if r.contains("flower") { return "花卉" }
        if r.contains("mountain") || r.contains("hill") { return "山景" }
        if r.contains("water") || r.contains("lake") || r.contains("ocean") || r.contains("sea") || r.contains("river") { return "水面" }
        if r.contains("snow") { return "雪景" }
        if r.contains("rain") { return "雨天" }
        if r.contains("fog") || r.contains("mist") { return "雾天" }
        if r.contains("person") || r.contains("people") { return "人物" }
        if r.contains("cat") { return "猫" }
        if r.contains("dog") { return "狗" }
        if r.contains("car") || r.contains("vehicle") || r.contains("road") || r.contains("street") { return "街道" }
        if r.contains("food") || r.contains("dining") || r.contains("restaurant") { return "美食" }
        if r.contains("stage") || r.contains("concert") { return "舞台" }
        if r.contains("firework") { return "烟花" }
        if r.contains("night") { return "夜景" }
        if r.contains("indoor") || r.contains("room") { return "室内" }
        if r.contains("document") || r.contains("text") || r.contains("book") { return "文档" }
        if r.contains("nature") || r.contains("landscape") || r.contains("outdoor") { return "风景" }
        return nil
    }

    // MARK: - 去重 / 限量

    private func cap(_ subjects: [LiveSubject], perKind: Int) -> [LiveSubject] {
        var counts: [LiveSubjectKind: Int] = [:]
        var result: [LiveSubject] = []
        // 置信度排序优先
        let sorted = subjects.sorted { $0.confidence > $1.confidence }
        for s in sorted {
            let c = counts[s.kind] ?? 0
            if c < perKind {
                result.append(s)
                counts[s.kind] = c + 1
            }
        }
        return result
    }
}

// MARK: - VNImageRequestHandler 便利封装（任一请求失败不影响其它）

private extension VNImageRequestHandler {
    @discardableResult
    func performAll(_ requests: [VNRequest]) -> Bool {
        do {
            try perform(requests)
            return true
        } catch {
            return false
        }
    }
}
