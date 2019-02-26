# CSWebCache

[![Version](https://img.shields.io/cocoapods/v/CSWebCache.svg?style=flat)](https://cocoapods.org/pods/CSWebCache)
[![License](https://img.shields.io/cocoapods/l/CSWebCache.svg?style=flat)](https://cocoapods.org/pods/CSWebCache)
[![Platform](https://img.shields.io/cocoapods/p/CSWebCache.svg?style=flat)](https://cocoapods.org/pods/CSWebCache)


## Requirements

iOS 10.0+ | Xcode 10.0+ | Swift 4.0+

## Installation

CSWebCache is available through [CocoaPods](https://cocoapods.org/pods/CSWebCache). To install
it, simply add the following line to your Podfile:

```ruby
use_frameworks!
pod 'CSWebCache'
```

## Usage
You should create an instance of URLCache and set it as the shared cache for your app in your application:didFinishLaunching: method.

```swift

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
``` 
To cache a webPage in the CSWebCache disk cache, simply call URLCache's diskCacheURL:loadedHandler: method.

```swift

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
``` 

## Author

Mayur Amipara

## License

CSWebCache is available under the MIT license. See the LICENSE file for more info.
