//
//  PromiseState.swift
//  Promised
//
//  Created by Kristian Andersen on 23/08/2018.
//  Copyright © 2018 Kristian Andersen. All rights reserved.
//

import Foundation

internal enum PromiseState<T> {
    case pending
    case fulfilled(value: T)
    case rejected(error: Error)
}

extension PromiseState {
    var value: T? {
        guard case let .fulfilled(value) = self else {
            return nil
        }

        return value
    }

    var error: Error? {
        guard case let .rejected(error) = self else {
            return nil
        }

        return error
    }

    var isPending: Bool {
        guard case .pending = self else { return false }
        return true
    }

    var isFulfilled: Bool {
        guard case .fulfilled = self else { return false }
        return true
    }

    var isRejected: Bool {
        guard case .rejected = self else { return false }
        return true
    }
}
