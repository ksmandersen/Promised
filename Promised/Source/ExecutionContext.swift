//
//  ExecutionContext.swift
//  Promised
//
//  Created by Kristian Andersen on 23/08/2018.
//  Copyright © 2018 Kristian Andersen. All rights reserved.
//

import Foundation

public protocol ExecutionContext {
    func execute(_ work: @escaping () -> Void)
}

extension DispatchQueue: ExecutionContext {
    public func execute(_ work: @escaping () -> Void) {
        async(execute: work)
    }
}

public final class InvalidatableQueue: ExecutionContext {
    private var valid = true
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public func invalidate() {
        valid = false
    }

    public func execute(_ work: @escaping () -> Void) {
        guard valid else { return }
        queue.async(execute: work)
    }
}
