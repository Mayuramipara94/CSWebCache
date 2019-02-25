//
//  URLProtocol.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.
//

import Foundation

/// Caches to be consulted
var caches: [URLCache] = []
/// Provides locking for multi-threading sensitive operations
let cacheLockObject = NSObject()

/// Used to indicate that a request has been handled by this URLProtocol
private let URLProtocolHandledRequestKey = "URLProtocolHandledRequestKey"
public var shouldRetrieveFromCSCacheByDefault = false

/**
 URLProtocol is an NSURLProtocol in charge of ensuring
 that any requests made as a result of a WebViewCacher
 are forwarded back to the WebViewCacher responsible.
 Additionally it ensures that when we are offline, we will
 use the CSWebCache diskCache if possible.
 */
class URLProtocol: Foundation.URLProtocol, URLSessionDataDelegate {
    
    /// Used to stop loading
    lazy var session: Foundation.URLSession = {
        let config = Foundation.URLSession.shared.configuration
        return Foundation.URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    var dataTask: URLSessionDataTask?
    
    static var shouldRetrieveFromCSCacheByDefault = false
    
    // MARK: - Class Methods
    override class func canInit(with request: URLRequest) -> Bool {
        if Foundation.URLProtocol.property(forKey: URLProtocolHandledRequestKey, in: request) != nil {
            return false
        }
        
        // In the case that we're trying to diskCache, we should always use this protocol
        if webViewCacherForRequest(request) != nil {
            return true
        }
        
        var isOffline = false
        if let cache = Foundation.URLCache.shared as? URLCache {
            if let handler = cache.isOfflineHandler {
                isOffline = handler()
            }
        }
        
        // Online requests get a chance to opt out of retreival from cache
        if !isOffline &&
            Foundation.URLProtocol.property(forKey: CSWebAvoidCacheRetreiveOnlineRequestPropertyKey,
                                            in: request) as? Bool == true
        {
            return false
        }
        
        // Online requests that didn't opt out will get included if turned on
        // and if there is something in the CSWebCache disk cache to get fetched.
        let scheme = request.url?.scheme
        if scheme == "http" || scheme == "https" {
            if shouldRetrieveFromCSCacheByDefault {
                if let cache = Foundation.URLCache.shared as? URLCache {
                    if cache.hasCSCachedResponse(for: request) {
                        return true
                    }
                }
            }
        }
        
        // Otherwise only use this protocol when offline
        return isOffline
    }
    
    /**
     Adds a URLCache that should be consulted
     when deciding which/if a WebViewCacher is
     responsible for a request.
     
     This method is responsible for having this
     protocol registered. It will only register
     itself when there is a URLCache that has been
     added.
     
     :param: cache The cache to be added.
     */
    class func addCache(_ cache: URLCache) {
        synchronized(cacheLockObject) { () -> Void in
            if caches.count == 0 {
                self.registerProtocol(true)
            }
            caches.append(cache)
        }
    }
    
    /**
     Removes a URLCache from the list of caches
     that should be used to find the WebViewCacher
     responsible for requests.
     
     If there are no more caches, this protocol will
     unregister itself.
     
     :param: cache The cache to be removed.
     */
    class func removeCache(_ cache: URLCache) {
        synchronized(cacheLockObject) { () -> Void in
            if let index = caches.index(of: cache) {
                caches.remove(at: index)
                if caches.count == 0 {
                    self.registerProtocol(false)
                }
            }
        }
    }
    
    /**
     Registers and unregisters this class for URL handling.
     
     :param: shouldRegister If true, registers this class
     for URL handling. If false, unregisters the class.
     */
    class func registerProtocol(_ shouldRegister: Bool) {
        if shouldRegister {
            self.registerClass(self)
        } else {
            self.unregisterClass(self)
        }
    }
    
    /**
     Finds the webViewCacher responsible for a request by
     asking each of its URLCaches in reverse order.
     
     :param: request The request.
     
     :returns: The WebViewCacher responsible for the request.
     */
    fileprivate class func webViewCacherForRequest(_ request: URLRequest) -> WebViewCacher? {
        var webViewCacherReturn: WebViewCacher? = nil
        
        synchronized(cacheLockObject) { () -> Void in
            for cache in caches.reversed() {
                if let webViewCacher = cache.webViewCacherOriginatingRequest(request) {
                    webViewCacherReturn = webViewCacher
                    break
                }
            }
        }
        
        return webViewCacherReturn
    }
    
    /**
     Helper method that returns and configures mutable copy
     of a request.
     
     :param: request The request.
     
     :returns: The mutable, configured copy of the request.
     */
    fileprivate class func mutableCanonicalRequest(for request: URLRequest) -> URLRequest {
        var mutableRequest = request
        mutableRequest.cachePolicy = .returnCacheDataElseLoad
        if let webViewCacher = webViewCacherForRequest(request) {
            mutableRequest = webViewCacher.mutableRequest(for: request)
        }
        
        Foundation.URLProtocol.setProperty(true, forKey: URLProtocolHandledRequestKey, in: mutableRequest as! NSMutableURLRequest)
        return mutableRequest
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return mutableCanonicalRequest(for: request)
    }
    
    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        return super.requestIsCacheEquivalent(a, to:b)
    }
    
    // MARK: - Instance Methods
    override func startLoading() {
        let mutableRequest = URLProtocol.mutableCanonicalRequest(for: request)
        if let
            cache = Foundation.URLCache.shared as? URLCache,
            let cachedResponse = cache.cachedResponse(for: mutableRequest),
            let response = cachedResponse.response as? HTTPURLResponse
            , response.statusCode < 400
        {
            client?.urlProtocol(self, cachedResponseIsValid: cachedResponse)
            return
        }
        self.dataTask = self.session.dataTask(with: request)
        self.dataTask?.resume()
    }
    
    override func stopLoading() {
        self.dataTask?.cancel()
        self.dataTask = nil
    }
    
    // Mark: - NSURLSessionDataDelegate Methods
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
    {
        completionHandler(.allow)
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
    }
    
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data)
    {
        self.client?.urlProtocol(self, didLoad: data)
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?)
    {
        if let error = error {
            self.client?.urlProtocol(self, didFailWithError: error)
        } else {
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
}
