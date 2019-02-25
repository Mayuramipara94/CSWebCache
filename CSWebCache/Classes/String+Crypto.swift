//
//  String+Crypto.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.
//

import Foundation

extension String {
    func cswebcache_MD5() -> String? {
        
        return self.data(using: String.Encoding.utf8)?.cswebcache_MD5().cswebcache_hexString()
    }
    
    func cswebcache_SHA1() -> String? {
        return self.data(using: String.Encoding.utf8)?.cswebcache_SHA1().cswebcache_hexString()
    }
}
