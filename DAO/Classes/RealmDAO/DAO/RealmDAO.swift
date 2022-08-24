//
//  RealmDAO.swift
//  DAO
//
//  Created by Igor Bulyga on 04.02.16.
//  Copyright © 2016 RedMadRobot LLC. All rights reserved.
//


import Foundation
import Realm
import RealmSwift

/// `DAO` pattern implementation for `Realm`.
open class RealmDAO<Model: Entity, RealmModel: RLMEntry>: DAO<Model> {
    
    // MARK: - Private
    
    /// Translator for current `RLMEntry` and `RealmModel` types.
    private let translator: RealmTranslator<Model, RealmModel>
    private let configuration: Realm.Configuration
    /// In-memory Realm instance.
    private var inMemoryRealm: Realm?
    
    // MARK: - Public
    
    /// Creates an instance with specified `translator` and `configuration`.
    ///
    /// - Parameters:
    ///   - translator: translator for current `Model` and `RealmModel` types.
    ///   - configuration: configuration. See also `Realm.Configuration`.
    public init(
        _ translator: RealmTranslator<Model, RealmModel>,
        configuration: Realm.Configuration) {
        
        self.translator = translator
        self.configuration = configuration
        super.init()
    }
    
    /// Creates an instance with specified `translator` and `configuration`.
    ///
    /// - Parameters:
    ///   - translator: translator for current `Model` and `RealmModel` types.
    ///   - configuration: configuration. See also `RealmConfiguration`.
    public init(
        _ translator: RealmTranslator<Model, RealmModel>,
        configuration: RealmConfiguration) {
        
        self.translator = translator
        self.configuration = RealmDAO.makeRealmConfiguration(configuration)
        super.init()
    }
    
    
    /// Creates an instance with specified `translator` and default configuration.
    ///
    /// - Parameters:
    ///   - translator: translator for current `Model` and `RealmModel` types.
    public convenience init(
        _ translator: RealmTranslator<Model, RealmModel>) {
        
        self.init(translator, configuration: RealmConfiguration())
    }
    
    
    static func makeRealmConfiguration(_ configuration: RealmConfiguration) -> Realm.Configuration {
        
        var config = Realm.Configuration.defaultConfiguration
        
        guard let path = configuration.databaseURL ?? self.pathForFileName(configuration.databaseFileName) else {
            fatalError("Cant find path for DB with filename: \(configuration.databaseFileName)"
                + " v.\(configuration.databaseVersion)")
        }
        config.fileURL = path
        config.schemaVersion = configuration.databaseVersion
        config.migrationBlock = configuration.migrationBlock
        config.encryptionKey = configuration.encryptionKey
        config.shouldCompactOnLaunch = configuration.shouldCompactOnLaunch
        
        return config
    }
    
    public static func pathForFileName(_ fileName: String) -> URL? {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true).first as NSString?
        
        guard let realmPath = documentDirectory?.appendingPathComponent(fileName) else {
            return nil
        }
        return URL(string: realmPath)
    }
    
    
    //MARK: - DAO
    
    override open func persist(_ entity: Model) throws {
        if let entry = try readFromRealm(entity.entityId) {
            try autoreleasepool {
                try realm().beginWrite()
                translator.fill(entry, fromEntity: entity)
                try realm().commitWrite()
            }
        } else {
            let entry = RealmModel()
            translator.fill(entry, fromEntity: entity)
            try write(entry)
        }
    }
    
    
    open override func persist(_ entities: [Model]) throws {
        
        let entries = List<RealmModel>()
        for entity in entities {
            if let entry = try? readFromRealm(entity.entityId) {
                entries.append(entry)
            }
        }
        
        let realm = try self.realm()
        try autoreleasepool {
            realm.beginWrite()
            translator.fill(entries, fromEntities: entities)
            
            entries.forEach {
                realm.create(RealmModel.self, value: $0, update: .all)
            }
            
            try realm.commitWrite()
        }
    }
    
    
    override open func read(_ entityId: String) -> Model? {
        
        guard let entry = try? readFromRealm(entityId) else { return nil }
        
        let entity = Model()
        translator.fill(entity, fromEntry: entry)
        
        return entity
    }
    
    
    open override func read() -> [Model] {
        do {
            let results = try readFromRealm()
            return results.map {
                let entity = Model()
                self.translator.fill(entity, fromEntry: $0)
                return entity
            }
        } catch {
            return []
        }
    }
    
    
    open override func read(predicatedBy predicate: NSPredicate?) -> [Model] {
        return read(predicatedBy: predicate, orderedBy: nil)
    }
    
    
    open override func read(
        orderedBy field: String?,
        ascending: Bool) -> [Model] {
        
        return read(predicatedBy: nil, orderedBy: field, ascending: ascending)
    }
    
    
    open override func read(
        predicatedBy predicate: NSPredicate?,
        orderedBy field: String?,
        ascending: Bool = true) -> [Model] {
        
        var entries: Results<RealmModel>
        do {
            entries = try readFromRealm(predicate)
        } catch {
            return []
        }
        
        if let field = field {
            entries = entries.sorted(byKeyPath: field, ascending: ascending)
        }
        
        return entries.map {
            let entity = Model()
            self.translator.fill(entity, fromEntry: $0)
            return entity
        }
    }
    
    
    override open func erase() throws {
        let results = try readFromRealm()
        let entries: List<RealmModel> = List<RealmModel>()
        
        entries.append(objectsIn: results.map {
            $0 as RealmModel
        })
        
        try self.delete(entries)
    }
    
    
    override open func erase(_ entityId: String) throws {
        guard let entry = try readFromRealm(entityId) else {
            return
        }
        try delete(entry)
    }
    
    
    // MARK: - Private
    
    private func write(_ entry: RealmModel) throws {
        let realm = try self.realm()
        try realm.write {
            realm.create(RealmModel.self, value: entry, update: .all)
        }
    }
    
    
    private func write(_ entries: List<RealmModel>) throws {
        let realm = try self.realm()
        try realm.write {
            entries.forEach { (e: RealmModel) -> () in
                realm.create(RealmModel.self, value: e, update: .all)
            }
        }
    }
    
    
    private func readFromRealm(_ entryId: String) throws -> RealmModel? {
        let realm = try self.realm()
        return realm.object(ofType: RealmModel.self, forPrimaryKey: entryId)
    }
    
    
    private func readFromRealm(_ predicate: NSPredicate? = nil) throws -> Results<RealmModel> {
        let realm = try self.realm()
        let results: Results<RealmModel> = realm.objects(RealmModel.self)
        guard let predicate = predicate else {
            return results
        }
        return results.filter(predicate)
    }
    
    
    private func delete(_ entry: RealmModel) throws {
        try self.realm().write {
            cascadeDelete(entry)
        }
    }
    
    
    private func delete(_ entries: List<RealmModel>) throws {
        try self.realm().write {
            cascadeDelete(entries)
        }
    }
    
    
    private func cascadeDelete(_ object: AnyObject?) {
        guard let object = object as? Object else { return }

        object.objectSchema.properties.forEach {
            guard $0.type == .object else { return }

            if $0.isArray {
                for element in object.dynamicList($0.name) {
                    cascadeDelete(element)
                }
            } else if !object.isInvalidated, let deletable = object as? CascadeDeletionProtocol {
                deletable.objectsToDelete.forEach { child in
                    cascadeDelete(child)
                }

                try? self.realm().delete(object)
            }

        }
    }
    
    private func realm() throws -> Realm {
        let realm = try Realm(configuration: configuration)

        if configuration.inMemoryIdentifier != nil {
            inMemoryRealm = realm
        }
        
        return realm
    }
    
}
