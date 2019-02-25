//
//  Data+Crypto.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.
//


import Foundation
import CommonCrypto

extension Data {
    
    func cswebcache_hexString() -> String {
        return self.reduce("", { $0 + String(format: "%02x", $1) })
    }
    
    func cswebcache_MD5() -> Data {
        let resultPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(CC_MD5_DIGEST_LENGTH))
        
        let bytesPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        copyBytes(to: bytesPointer, count: count)
        
        CC_MD5(bytesPointer, CC_LONG(count), resultPointer)
        return Data(bytesNoCopy: resultPointer, count: Int(CC_MD5_DIGEST_LENGTH), deallocator: .free)
    }
    
    func cswebcache_SHA1() -> Data {
        let resultPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(CC_SHA1_DIGEST_LENGTH))
        let bytesPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        copyBytes(to: bytesPointer, count: count)
        
        CC_SHA1(bytesPointer, CC_LONG(count), resultPointer)
        return Data(bytesNoCopy: resultPointer, count: Int(CC_SHA1_DIGEST_LENGTH), deallocator: .free)
    }
}
