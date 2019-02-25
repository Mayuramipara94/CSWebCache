//
//  Synchronization.swift
//  CSWebCache
//
//  Created by Mayuramipara94 on 02/23/2019.
//  Copyright (c) 2019 Mayuramipara94. All rights reserved.
//

import Foundation

func synchronized<T>(_ lockObj: AnyObject!, closure: () -> T) -> T {
    objc_sync_enter(lockObj)
    let value: T = closure()
    objc_sync_exit(lockObj)
    return value
}
