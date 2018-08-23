//
//  PromiseCallback.swift
//  Promised
//
//  Created by Kristian Andersen on 23/08/2018.
//  Copyright © 2018 Kristian Andersen. All rights reserved.
//

import Foundation

internal struct PromiseCallback<T> {
    let onFulfilled: (T) -> Void
    let onRejected: (Error) -> Void
    let context: ExecutionContext

    func callFulfill(_ value: T) {
        context.execute {
            self.onFulfilled(value)
        }
    }

    func callReject(_ error: Error) {
        context.execute {
            self.onRejected(error)
        }
    }
}
