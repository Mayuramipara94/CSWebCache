//
//  WebViewCacher.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.


import UIKit

public typealias WebViewLoadedHandler = (_ webView: UIWebView) -> (Bool)
typealias WebViewCacherCompletionHandler = (_ webViewCacher: WebViewCacher) -> ()

/**
 WebViewCacher is in charge of loading all of the
 requests associated with a url and ensuring that
 all of that webpage's request have the property
 to signal that they should be stored in the CSWebCache
 disk cache.
 */
class WebViewCacher: NSObject, UIWebViewDelegate {
    
    // MARK: - Properties
    /// Handler called to determine if a webpage is considered loaded.
    var loadedHandler: WebViewLoadedHandler?
    /// Handler called once a webpage has finished loading.
    var completionHandler: WebViewCacherCompletionHandler?
    /// Handler called if a webpage fails to load.
    var failureHandler: ((Error) -> ())? = nil
    /// Main URL for the webpage request.
    fileprivate var mainDocumentURL: URL?
    /// Webview used to load the webpage.
    fileprivate var webView: UIWebView?
    
    // MARK: - Instance Methods
    /**
     Uses the associated mainDocumentURL to determine if it
     thinks it is responsible for a given NSURLRequest.
     
     This is necessary because the UIWebView can fire off requests
     without telling the webViewDelegate about them, so the
     URLProtocol will catch them for us, which should result in
     this method being called.
     
     :param: request The request in question.
     :returns: A Bool indicating whether this WebViewCacher is
     responsible for that NSURLRequest.
     */
    func didOriginateRequest(_ request: URLRequest) -> Bool {
        if let mainDocumentURL = mainDocumentURL {
            if request.mainDocumentURL == mainDocumentURL || request.url == mainDocumentURL {
                return true
            }
        }
        return false
    }
    
    /**
     Creates a mutable request for a given request that should
     be handled by the WebViewCacher.
     
     The property signaling that the request should be stored in
     the CSWebCache disk cache will be added.
     
     :param: request The request.
     
     :returns: A mutable request based on the requested passed in.
     */
    func mutableRequest(for request: URLRequest) -> URLRequest {
        let mutableRequest = request as! NSMutableURLRequest
        Foundation.URLProtocol.setProperty(true, forKey: CSWebCacheRequestPropertyKey, in: mutableRequest)
        return mutableRequest as URLRequest
    }
    
    /**
     CSWebCacheCacheURL:loadedHandler:completionHandler: is the main
     entry point for dealing with WebViewCacher. Calling this method
     will result in a new UIWebView being generated to cache all the
     requests associated with the given NSURL to the CSWebCache disk cache.
     
     :param: url The url to be cached.
     :param: loadedHandler The handler that will be called every time
     the webViewDelegate's webViewDidFinishLoading method is called.
     This should return a Bool indicating whether we should stop
     loading.
     :param: completionHandler Called once the loadedHandler has returned
     true and we are done caching the requests at the given url.
     :param: completionHandler Called if the webpage fails to load.
     */
    func CSCacheURL(_ url: URL,
                          loadedHandler: @escaping WebViewLoadedHandler,
                          completionHandler: @escaping WebViewCacherCompletionHandler,
                          failureHandler: @escaping (Error) -> ()) {
        self.loadedHandler = loadedHandler
        self.completionHandler = completionHandler
        self.failureHandler = failureHandler
        loadURLInWebView(url)
    }
    
    // MARK: WebView Loading
    /**
     Loads a URL in the webview associated with the WebViewCacher.
     
     :param: url URL of the webpage to be loaded.
     */
    fileprivate func loadURLInWebView(_ url: URL) {
        let webView = UIWebView(frame: CGRect.zero)
        let request = URLRequest(url: url)
        let mutableRequest = self.mutableRequest(for: request)
        self.webView = webView
        webView.delegate = self
        webView.loadRequest(mutableRequest)
    }
    
    // MARK: - UIWebViewDelegate
    func webViewDidFinishLoad(_ webView: UIWebView) {
        var isComplete = true
        synchronized(self) { () -> Void in
            if let loadedHandler = self.loadedHandler {
                isComplete = loadedHandler(webView)
            }
            if isComplete == true {
                webView.stopLoading()
                self.webView = nil
                
                if let completionHandler = self.completionHandler {
                    completionHandler(self)
                }
                self.completionHandler = nil
            }
        }
    }
    
    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        // We can ignore this error as it just means canceled.
        // http://stackoverflow.com/a/1053411/1084997
        if error._code == -999 {
            return
        }
        
        NSLog("WebViewLoadError \(error)")
        
        synchronized(self) { () -> Void in
            if let failureHandler = self.failureHandler {
                failureHandler(error)
            }
            self.failureHandler = nil
        }
    }
    
    func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        mainDocumentURL = request.mainDocumentURL
        if !URLCache.requestShouldBeStoredInCS(request) {
            let mutableRequest = self.mutableRequest(for: request)
            webView.loadRequest(mutableRequest)
            return false
        }
        return true
    }
}
