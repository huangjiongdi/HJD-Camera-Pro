//
//  GalleryMetadataStore.swift
//  HJD Camera Pro
//
//  Lightroom 式图库元数据：星级评分（0-5）、旗标（精选/拒绝/无），
//  以 PHAsset.localIdentifier 为键持久化在本机（不修改系统相册）。
//

import Foundation
import Combine

final class GalleryMetadataStore: ObservableObject {
    static let shared = GalleryMetadataStore()

    enum Flag: Int, Codable { case none = 0, picked = 1, rejected = 2 }

    @Published private(set) var ratings: [String: Int] = [:]
    @Published private(set) var flags: [String: Flag] = [:]

    private let defaults = UserDefaults.standard
    private let ratingsKey = "HJD.gallery.ratings.v1"
    private let flagsKey = "HJD.gallery.flags.v1"

    private init() {
        load()
    }

    // MARK: - Rating

    func rating(for id: String) -> Int { ratings[id] ?? 0 }

    /// 点当前星数则清零（LR 行为）。
    func toggleRating(_ value: Int, id: String) {
        if ratings[id] == value {
            ratings[id] = nil
        } else {
            ratings[id] = value
        }
        save()
    }

    // MARK: - Flag

    func flag(for id: String) -> Flag { flags[id] ?? .none }

    func toggleFlag(_ flag: Flag, id: String) {
        if flags[id] == flag {
            flags[id] = nil
        } else {
            flags[id] = flag
        }
        save()
    }

    func cycleFlag(id: String) {
        switch flag(for: id) {
        case .none: toggleFlag(.picked, id: id)
        case .picked: flags[id] = .rejected; save()
        case .rejected: flags[id] = nil; save()
        }
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: ratingsKey),
           let v = try? JSONDecoder().decode([String: Int].self, from: data) {
            ratings = v
        }
        if let data = defaults.data(forKey: flagsKey),
           let v = try? JSONDecoder().decode([String: Int].self, from: data) {
            flags = v.mapValues { Flag(rawValue: $0) ?? .none }
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(ratings) { defaults.set(d, forKey: ratingsKey) }
        let raw = flags.mapValues { $0.rawValue }
        if let d = try? JSONEncoder().encode(raw) { defaults.set(d, forKey: flagsKey) }
    }
}
