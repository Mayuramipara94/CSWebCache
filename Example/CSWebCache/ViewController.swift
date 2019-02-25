//
//  ViewController.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.
//

import UIKit
import CSWebCache


class ViewController: UIViewController {
    
    @IBOutlet weak var webview: UIWebView!
    

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        let kB = 1024
        let MB = 1024 * kB
        let GB = 1024 * MB
        let isOfflineHandler: (() -> Bool) = {
            /*
             We are returning true here for demo purposes only.
             You should use Reachability or another method for determining whether the user is
             offline and return the appropriate value
             */
            return true
        }
        
        let urlCache = CSWebCache.URLCache(memoryCapacity: 20 * MB, diskCapacity: 20 * MB, diskPath: nil,
                                           CSDiskCapacity: 1 * GB, CSDiskPath: nil, CSSearchPathDirectory: .documentDirectory,
                                isOfflineHandler: isOfflineHandler)
        
        CSWebCache.URLCache.shared = urlCache
        
        if let urlToCache = URL(string: "https://appchance.com/blog/how-to-create-your-own-pod") {
            
            if let cache = URLCache.shared as? CSWebCache.URLCache {
                
                cache.diskCacheURL(urlToCache, loadedHandler: { (webView) -> (Bool) in
                    let state = webView.stringByEvaluatingJavaScript(from: "document.readyState")
                    if state == "complete" {
                        // Loading is done once we've returned true
                        return true
                    }
                    return false
                }, completeHandler: { () -> Void in
                    print("Finished caching")
                }, failureHandler: { (error) -> Void in
                    print("Error caching: \(error)")
                })
            }
            
            webview.loadRequest(URLRequest(url: urlToCache))
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

