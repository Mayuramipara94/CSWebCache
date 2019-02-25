//
//  DiskCache.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.
//

import Foundation
import UIKit

/**
 DiskCache is a NSURLCache replacement that will store
 and retrieve NSCachedURLResponses to disk.
 */
class DiskCache {
    
    /**
     Keys used to store properties in the plist.
     */
    struct DictionaryKeys {
        static let maxCacheSize = "maxCacheSize"
        static let requestsFilenameArray = "requestsFilenameArray"
    }
    
    // MARK: - Properties
    
    var isAtLeastiOS8: Bool {
        struct Static {
            static var onceToken : Int = 0
            static var value: Bool = false
        }
        Static.value = Double(UIDevice.current.systemVersion) ?? 0.0 >= 8.0
        return Static.value
    }
    
    /// Filesystem path where the cache is stored
    fileprivate let path: String
    /// Search path for the disk cache location
    fileprivate let searchPathDirectory: FileManager.SearchPathDirectory
    /// Size limit for the disk cache
    fileprivate let maxCacheSize: Int
    
    /// Provides locking for multi-threading sensitive operations
    fileprivate let lockObject = NSObject()
    
    /// Current disk cache size
    var currentSize = 0
    /// File paths for requests cached on disk
    var requestCaches: [String] = []
    
    // Mark: - Instance methods
    /**
     Initializes a new DiskCache
     
     :param: path The path of the location on disk that should be used
     to store requests. This MUST be unique for each DiskCache instance.
     Otherwise, you will have a hard time debugging crashes.
     :param: searchPathDirectory The NSSearchPathDirectory that will be
     used to find the location at which to store requests.
     :param: maxCacheSize The size limit of this diskCache. When the size
     of the requests exceeds this amount, older requests will be removed.
     No requests that are larger than this size will even attempt to be
     stored.
     */
    init(path: String?, searchPathDirectory: FileManager.SearchPathDirectory, maxCacheSize: Int) {
        self.path = path ?? "cswebcache/"
        self.searchPathDirectory = searchPathDirectory
        self.maxCacheSize = maxCacheSize
        loadPropertiesFromDisk()
    }
    
    /**
     Loads appropriate properties from the plist to restore
     this cache from disk.
     */
    fileprivate func loadPropertiesFromDisk() {
        synchronized(lockObject) { () -> Void in
            if let plistPath = self.diskPathForPropertyList()?.path {
                if !FileManager.default.fileExists(atPath: plistPath) {
                    self.persistPropertiesToDisk()
                } else {
                    if let dict = NSDictionary(contentsOfFile: plistPath) {
                        if let currentSize = dict.value(forKey: DictionaryKeys.maxCacheSize) as? Int {
                            self.currentSize = currentSize
                        }
                        if let requestCaches = dict.value(forKey: DictionaryKeys.requestsFilenameArray) as? [String] {
                            self.requestCaches = requestCaches
                        }
                    }
                }
            }
        }
    }
    
    /**
     Saves appropriate properties to a plist to save
     this cache to disk.
     */
    fileprivate func persistPropertiesToDisk() {
        synchronized(lockObject) { () -> Void in
            if let plistPath = self.diskPathForPropertyList()?.path {
                let dict = self.propertiesDictionary()
                (dict as NSDictionary).write(toFile: plistPath, atomically: true)
            }
            return
        }
    }
    
    func clearCache() {
        if let path = diskPath()?.path {
            do {
                try FileManager.default.removeItem(atPath: path)
                requestCaches = []
                currentSize = 0
            } catch {
                NSLog("Error clearing cache")
            }
        } else {
            NSLog("Error clearing cache")
        }
    }
    
    /**
     Keeps removing the oldest request until our
     currentSize is not greater than the maxCacheSize.
     Clears the cache on any failures.
     */
    fileprivate func trimCacheIfNeeded() {
        while currentSize > maxCacheSize && !requestCaches.isEmpty {
            let lastCurrentSize = currentSize
            let fileName = requestCaches.first
            if let
                fileName = fileName,
                let path = diskPathForRequestCache(named: fileName)?.path
            {
                var attributes: [FileAttributeKey : Any]?
                do {
                    try attributes = FileManager.default.attributesOfItem(atPath: path)
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    NSLog("Error getting attributes of or deleting item at path \(path)")
                    attributes = nil
                    clearCache()
                    return
                }
                
                if let
                    attributes = attributes,
                    let fileSize = attributes[FileAttributeKey.size] as? NSNumber
                {
                    let size = fileSize.intValue
                    currentSize -= size
                }
                if let index = requestCaches.index(of: fileName) {
                    requestCaches.remove(at: index)
                }
            } else {
                NSLog("Error getting filename or path")
                clearCache()
                return
            }
            if currentSize == lastCurrentSize {
                NSLog("Error: current cache size did not decrement")
                clearCache()
                return
            }
        }
    }
    
    /**
     Creates a dictionary that will be used to store
     this diskCache's properties to disk.
     
     :returns: A dictionary of the cache's properties
     */
    fileprivate func propertiesDictionary() -> [String: Any] {
        var dict = [String: Any]()
        dict[DictionaryKeys.maxCacheSize] = currentSize
        dict[DictionaryKeys.requestsFilenameArray] = requestCaches
        return dict
    }
    
    /**
     Functions much like NSURLCache's similarly named method, storing a
     response and request to disk only.
     
     :param: cachedResponse an NSCachedURLResponse to persist to disk.
     :param: forRequest an NSURLRequest to associate the cachedResponse with.
     
     :returns: A Bool representing whether or not we successfully
     stored the response to disk.
     */
    func store(cachedResponse: CachedURLResponse, for request: URLRequest) -> Bool {
        var success = false
        
        synchronized(lockObject) { () -> Void in
            if let hash = self.hash(for: request) {
                if self.isAtLeastiOS8 {
                    success = self.save(object: cachedResponse, withHash: hash)
                } else {
                    success = self.storePieces(cachedResponse: cachedResponse, withHash: hash)
                }
            }
        }
        
        return success
    }
    
    /**
     Stores components of the NSCachedURLResponse to disk individually to
     work around iOS 7 not properly storing the response to disk with its
     data and userInfo.
     
     NOTE: Storage policy is not stored because it is irrelevant to CSWebCache
     cached responses.
     :param: cachedResponse an NSCachedURLResponse to persist to disk.
     :param: hash The hash associated with the NSCachedURLResponse.
     :returns: A Bool representing whether or not we successfully
     stored the response to disk.
     */
    fileprivate func storePieces(cachedResponse: CachedURLResponse, withHash hash: String) -> Bool {
        var success = true
        synchronized(lockObject) { () -> Void in
            let responseHash = self.hashForResponse(from: hash)
            success = success && self.save(object: cachedResponse.response, withHash: responseHash)
            let dataHash = self.hashForData(from: hash)
            success = success && self.save(object: cachedResponse.data as NSCoding, withHash: dataHash)
            if let userInfo = cachedResponse.userInfo {
                if !userInfo.isEmpty {
                    let userInfoHash = self.hashForUserInfo(from: hash)
                    success = success && self.save(object: userInfo as NSCoding, withHash: userInfoHash)
                }
            }
        }
        return success
    }
    
    /**
     Saves an archived object's data to disk with the hash it should be
     associated with. This will only store the request if it can fit in
     our max cache size, and will empty out older cached items if it
     needs to to make room.
     
     :param: object The NSCoding compliant object to save.
     :param: hash The hash associated with that object.
     
     :returns: A Bool indicating that the saves were successful.
     */
    fileprivate func save(object: NSCoding, withHash hash: String) -> Bool {
        var success = false
        synchronized(lockObject) { () -> Void in
            if let path = self.diskPathForRequestCache(named: hash)?.path {
                let data = NSKeyedArchiver.archivedData(withRootObject: object)
                if data.count < self.maxCacheSize {
                    self.currentSize += data.count
                    var index = -1
                    for i in 0..<self.requestCaches.count {
                        if self.requestCaches[i] == hash {
                            index = i
                            break
                        }
                    }
                    if index != -1 {
                        self.requestCaches.remove(at: index)
                    }
                    self.requestCaches.append(hash)
                    self.trimCacheIfNeeded()
                    self.persistPropertiesToDisk()
                    success = true
                    do {
                        try data.write(to: URL(fileURLWithPath: path), options: [])
                    } catch {
                        success = false
                        NSLog("Error writing request to disk: \(error)")
                    }
                }
            }
        }
        
        return success
    }
    
    /**
     Functions much like NSURLCache's method of the same signature.
     An NSCachedURLResponse associated with the specified NSURLRequest
     will be returned.
     
     :param: request The request.
     :returns: The cached response.
     */
    func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        var response: CachedURLResponse?
        
        synchronized(lockObject) { () -> Void in
            
            if let path = self.diskPath(for: request)?.path {
                if self.isAtLeastiOS8 {
                    response = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? CachedURLResponse
                } else {
                    response = self.cachedResponseFromPieces(for: request)
                }
            }
        }
        
        return response
    }
    
    /**
     This will simply check if a response exists in the cache for the
     specified request.
     */
    internal func hasCachedResponse(for request: URLRequest) -> Bool {
        
        if let path = self.diskPath(for: request)?.path {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }
    
    /**
     Will create the cachedResponse from its response, data and
     userInfo. This is only used to workaround the bug in iOS 7
     preventing us from just saving the cachedResponse itself.
     
     :param: request The request.
     
     :returns: The cached response.
     */
    fileprivate func cachedResponseFromPieces(for request: URLRequest) -> CachedURLResponse? {
        var cachedResponse: CachedURLResponse? = nil
        
        synchronized(lockObject) { () -> Void in
            
            var response: URLResponse? = nil
            var data: Data? = nil
            var userInfo: [AnyHashable: Any]? = nil
            
            if let basePath = self.diskPath(for: request)?.path {
                let responsePath = self.hashForResponse(from: basePath)
                response = NSKeyedUnarchiver.unarchiveObject(withFile: responsePath) as? URLResponse
                let dataPath = self.hashForData(from: basePath)
                data = NSKeyedUnarchiver.unarchiveObject(withFile: dataPath) as? Data
                let userInfoPath = self.hashForUserInfo(from: basePath)
                userInfo = NSKeyedUnarchiver.unarchiveObject(withFile: userInfoPath) as? [AnyHashable: Any]
            }
            
            if let
                response = response,
                let data = data
            {
                cachedResponse = CachedURLResponse(response: response, data: data, userInfo: userInfo, storagePolicy: .allowed)
            }
        }
        
        return cachedResponse
    }
    
    /**
     hasCacheForRequest: returns a Bool indicating whether
     this diskCache has a cachedResponse associated with the
     specified NSURLRequest.
     
     :param: The request.
     :returns: A boolean indicating whether the cache has a
     response cached for the given request.
     */
    func hasCache(for request: URLRequest) -> Bool {
        if let hash = hash(for: request) {
            for requestHash in requestCaches {
                if hash == requestHash {
                    return true
                }
            }
        }
        return false
    }
    
    /**
     Returns the path where we should store our plist.
     
     :returns: The file path URL.
     */
    func diskPathForPropertyList() -> URL? {
        var url: URL?
        let filename = "diskCacheInfo.plist"
        if let baseURL = diskPath() {
            url = URL(string: filename, relativeTo: baseURL)
        }
        return url
    }
    
    /**
     Returns the path where we should store a cache
     with the specified filename.
     
     :params: name The filename of the cached request.
     
     :returns: The file path URL.
     */
    fileprivate func diskPathForRequestCache(named name: String) -> URL? {
        var url: URL?
        if let baseURL = diskPath() {
            url = URL(string: name, relativeTo: baseURL)
        }
        return url
    }
    
    /**
     Returns the path where a response should be stored
     for a given NSURLRequest.
     
     :params: request The request.
     :returns: The file path URL.
     */
    func diskPath(for request: URLRequest) -> URL? {
        var url: URL?
        if let
            hash = hash(for: request),
            let baseURL = diskPath()
        {
            url = URL(string: hash, relativeTo: baseURL)
        }
        return url
    }
    
    /**
     Return the path that should be used as the baseURL for
     all paths associated with this diskCache.
     
     :returns: The file path URL.
     */
    fileprivate func diskPath() -> URL? {
        
        let baseURL: URL?
        do {
            baseURL = try FileManager.default.url(for: searchPathDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: false)
        } catch {
            baseURL = nil
        }
        
        var url: URL?
        if let
            baseURL = baseURL,
            let fileURL = URL(string: path, relativeTo: baseURL)
        {
            var isDir : ObjCBool = false
            if !FileManager.default.fileExists(atPath: fileURL.absoluteString, isDirectory: &isDir) {
                do {
                    try FileManager.default.createDirectory(at: fileURL,
                                                            withIntermediateDirectories: true, attributes: nil)
                } catch {
                    NSLog("Error creating directory at URL: \(fileURL)")
                }
            }
            url = fileURL
        }
        return url
    }
    
    /**
     Returns the hash/filename that should be used for
     a given NSURLRequest.
     
     :param: request The request.
     
     :returns: The hash.
     */
    func hash(for request: URLRequest) -> String? {
        if let urlString = request.url?.absoluteString {
            return hash(forURLString: urlString)
        }
        return nil
    }
    
    /**
     Returns the hash/filename for the response associated with
     the hash for a request. This is only used as an iOS 7
     workaround.
     
     :returns: The hash.
     */
    func hashForResponse(from hash: String) -> String {
        return "\(hash)_response"
    }
    
    /**
     Returns the hash/filename for the data associated with
     the hash for a request. This is only used as an iOS 7
     workaround.
     
     :param: hash The hash.
     :returns: The hash.
     */
    func hashForData(from hash: String) -> String {
        return "\(hash)_data"
    }
    
    /**
     Returns the hash/filename for the userInfo associated with
     the hash for a request. This is only used as an iOS 7
     workaround.
     
     :param: hash The hash.
     :returns: The hash.
     */
    func hashForUserInfo(from hash: String) -> String {
        return "\(hash)_userInfo"
    }
    
    /**
     Returns the hash/filename that should be used for
     a given the URL absoluteString of a request.
     
     :param: string The URL string.
     
     :returns: The hash.
     */
    func hash(forURLString string: String) -> String? {
        return string.cswebcache_MD5()
    }
}
