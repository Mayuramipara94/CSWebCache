//
//  URLCache.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.
//

import Foundation

/**
 Key used for a boolean property set on NSURLRequests by a
 WebViewCacher to indicate they should be stored in the cache.
 */
public let CSWebCacheRequestPropertyKey = "CSCacheRequest"
/// Used to avoid hitting the cache when online
public let CSWebAvoidCacheRetreiveOnlineRequestPropertyKey = "CSAvoidCacheRetreiveOnlineRequestPropertyKey"

private let kB = 1024
private let MB = kB * 1024
private let ArbitrarilyLargeSize = MB * 100

/**
 URLCache is an NSURLCache with an additional diskCache used
 only for storing requests that should be available without
 hitting the network.
 */
open class URLCache: Foundation.URLCache {
    // Handler used to determine if we're offline
    var isOfflineHandler: (() -> Bool)?
    
    // Associated disk cache
    var diskCache: DiskCache
    
    // Array of WebViewCacher objects used to cache pages
    var cachers: [WebViewCacher] = []
    
    /*
     We need to override this because the connection
     might decide not to cache something if it decides
     the cache is too small wrt the size of the request
     to be cached.
     */
    override open var diskCapacity: Int {
        get {
            return ArbitrarilyLargeSize
        }
        set (value) {}
    }
    
    // MARK: - Class Methods
    /**
     Determines whether a request should be cached in CSWebCache for later use.
     :param: request The request
     :returns: A boolean of whether the request should be cached.
     */
    class func requestShouldBeStoredInCS(_ request: URLRequest) -> Bool {
        if let value = Foundation.URLProtocol.property(forKey: CSWebCacheRequestPropertyKey, in: request) as? Bool {
            return value
        }
        return false
    }
    
    // MARK: - Instance Methods
    /**
     Initializes a URLCache.
     :param: memoryCapacity The memory capacity of the cache in bytes
     :param: diskCapacity The disk capacity of the cache in bytes
     :param: diskPath The location in the application's default cache
     directory at which to store the on-disk cache
     :param: CSWebCacheDiskCapacity The disk capacity of the cache dedicated
     to requests that should be available via CSWebCache
     :param: CSWebCacheDiskPath The location at which to store the CSWebCache
     disk cache, relative to the specified CSWebCacheSearchPathDirectory
     :param: CSWebCacheSearchPathDirectory The searchPathDirectory to use as
     the location for the CSWebCache disk cache
     :param: isOfflineHandler A handler that will be called as needed to
     determine if the CSWebCache cache should be used
     */
    public init(memoryCapacity: Int, diskCapacity: Int, diskPath path: String?, CSDiskCapacity: Int, CSDiskPath: String?,
                CSSearchPathDirectory searchPathDirectory: FileManager.SearchPathDirectory, isOfflineHandler: (() -> Bool)?)
    {
        diskCache = DiskCache(path: CSDiskPath, searchPathDirectory: searchPathDirectory, maxCacheSize: CSDiskCapacity)
        self.isOfflineHandler = isOfflineHandler
        super.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: path)
        addToProtocol(true)
    }
    
    deinit {
        addToProtocol(false)
    }
    
    /**
     Adds or removes the URLCache to/from the URLProtocol caches.
     
     :param: shouldAdd If true, adds the cache. Otherwise, removes.
     */
    func addToProtocol(_ shouldAdd: Bool) {
        if shouldAdd {
            URLProtocol.addCache(self)
        } else {
            URLProtocol.removeCache(self)
        }
    }
    
    /**
     Attempts to find a WebViewCacher responsible
     for a given request.
     
     :param: request The request
     
     :returns: The WebViewCacher responsible for the request if found,
     otherwise nil.
     */
    func webViewCacherOriginatingRequest(_ request: URLRequest) -> WebViewCacher? {
        for cacher in cachers {
            if cacher.didOriginateRequest(request) {
                return cacher
            }
        }
        return nil
    }
    
    /**
     Stores the cached response into the diskCache only if the response
     is valid (statusCode < 400).
     
     :param: cachedResponse The NSCachedURLResponse to store in diskCache.
     :param: request The NSURLRequest this response is associated with.
     */
    func storeCachedResponseInDiskCache(_ cachedResponse: CachedURLResponse, forRequest request: URLRequest) {
        // We should never store failure responses
        if let httpResponse = cachedResponse.response as? HTTPURLResponse {
            if httpResponse.statusCode < 400 {
                _ = diskCache.store(cachedResponse: cachedResponse, for: request)
            }
        }
    }
    
    // MARK: Public
    open func clearDiskCache() {
        diskCache.clearCache()
    }
    
    override open func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {
        if URLCache.requestShouldBeStoredInCS(request) {
            storeCachedResponseInDiskCache(cachedResponse, forRequest: request)
        } else {
            super.storeCachedResponse(cachedResponse, for: request)
            // If we've already stored this in the CSWebCache cache, update it
            if diskCache.hasCache(for: request) {
                storeCachedResponseInDiskCache(cachedResponse, forRequest: request)
            }
        }
    }
    
    override open func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        let cachedResponse = diskCache.cachedResponse(for: request)
        if cachedResponse != nil {
            return cachedResponse
        }
        return super.cachedResponse(for: request)
    }
    
    internal func hasCSCachedResponse(for request: URLRequest) -> Bool{
        return diskCache.hasCachedResponse(for: request)
    }
    
    /**
     Downloads and stores an entire page in the diskCache. Any urls
     cached in this way will be available when the device is offline.
     :param: url The url of a webpage to download
     :param: loadedHandler A handler that will be called every time the
     UIWebView used to load the request calls its delegate's
     webViewDidFinishLoad method. This handler will receive the webView
     and should return true if we are done loading the page, or false
     if we should continue loading.
     :param: completeHandler A handler called once the process has been
     completed.
     :param: failureHandler A handler with a single error parameter called
     in case of failure.
     */
    open func diskCacheURL(_ url: URL,
                           loadedHandler: @escaping WebViewLoadedHandler,
                           completeHandler: (() -> Void)? = nil,
                           failureHandler: ((Error) -> Void)? = nil) {
        let webViewCacher = WebViewCacher()
        
        synchronized(self) {
            self.cachers.append(webViewCacher)
        }
        
        var failureHandler = failureHandler
        var completeHandler = completeHandler
        
        webViewCacher.CSCacheURL(url, loadedHandler: loadedHandler, completionHandler: { (webViewCacher) -> () in
            synchronized(self) {
                if let index = self.cachers.index(of: webViewCacher) {
                    self.cachers.remove(at: index)
                }
                
                completeHandler?()
                completeHandler = nil
            }
        }, failureHandler: { (error) -> () in
            failureHandler?(error)
            failureHandler = nil
        })
    }
}
