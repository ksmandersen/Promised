//
//  Promise.swift
//  Promised
//
//  Created by Kristian Andersen on 23/08/2018.
//  Copyright © 2018 Kristian Andersen. All rights reserved.
//

import Foundation

public class Promise<T> {
    private var lockQueue = DispatchQueue(label: "co.kristian.Promised.promise.lock", qos: .userInitiated)
    private var callbacks = [PromiseCallback<T>]()
    private var threadUnsafeState: PromiseState<T>

    public var isPending: Bool {
        return !isFulfilled && !isRejected
    }

    public var isFulfilled: Bool {
        return value != nil
    }

    public var isRejected: Bool {
        return error != nil
    }

    public var value: T? {
        return lockQueue.sync(execute: {
            self.threadUnsafeState.value
        })
    }

    public var error: Error? {
        return lockQueue.sync(execute: {
            self.threadUnsafeState.error
        })
    }

    public init() {
        threadUnsafeState = .pending
    }

    public init(value: T) {
        threadUnsafeState = .fulfilled(value: value)
    }

    public init(error: Error) {
        threadUnsafeState = .rejected(error: error)
    }

    public convenience init(queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated),
                            work: @escaping (_ fulfill: @escaping (T) -> Void,
                                             _ reject: @escaping (Error) -> Void) throws -> Void) {
        self.init()

        queue.async(execute: {
            do {
                try work(self.fulfill, self.reject)
            } catch let error {
                self.reject(error)
            }
        })
    }

    @discardableResult // flatMap
    public func then<U>(on queue: ExecutionContext = DispatchQueue.main,
                        _ onFulfilled: @escaping (T) throws -> Promise<U>) -> Promise<U> {
        return Promise<U>(work: { fulfill, reject in
            self.addCallbacks(
                on: queue,
                onFulfilled: { value in
                    do {
                        try onFulfilled(value).then(fulfill, reject)
                    } catch let error {
                        reject(error)
                    }
                },
                onRejected: reject
            )
        })
    }

    @discardableResult // map
    public func then<U>(on queue: ExecutionContext = DispatchQueue.main,
                        _ onFulfilled: @escaping (T) throws -> U) -> Promise<U> {
        return then(on: queue, { (value) -> Promise<U> in
            do {
                return Promise<U>(value: try onFulfilled(value))
            } catch let error {
                return Promise<U>(error: error)
            }
        })
    }

    @discardableResult
    public func then(on queue: ExecutionContext = DispatchQueue.main,
                     _ onFulfilled: @escaping (T) -> Void,
                     _ onRejected: @escaping (Error) -> Void = { _ in }) -> Promise<T> {
        _ = Promise<T>(work: { fulfill, reject in
            self.addCallbacks(
                on: queue,
                onFulfilled: { value in
                    fulfill(value)
                    onFulfilled(value)
                },
                onRejected: { error in
                    reject(error)
                    onRejected(error)
                }
            )
        })

        return self
    }

    @discardableResult
    public func `catch`(on queue: ExecutionContext = DispatchQueue.main,
                        _ onRejected: @escaping (Error) -> Void) -> Promise<T> {
        return then(on: queue, { _ in }, onRejected)
    }

    @discardableResult
    public func always(on queue: ExecutionContext = DispatchQueue.main,
                       _ onComplete: @escaping () -> Void) -> Promise<T> {
        return then(on: queue, { _ in onComplete() }, { _ in onComplete() })
    }

    public func fulfill(_ value: T) {
        updateState(.fulfilled(value: value))
    }

    public func reject(_ error: Error) {
        updateState(.rejected(error: error))
    }

    public func cancel() {
        reject(PromiseError.cancelled)
    }

    private func updateState(_ state: PromiseState<T>) {
        guard threadUnsafeState.isPending else { return }

        lockQueue.sync(execute: {
            self.threadUnsafeState = state
        })

        fireCallbacksIfNecessary()
    }

    private func addCallbacks(on queue: ExecutionContext = DispatchQueue.main,
                              onFulfilled: @escaping (T) -> Void,
                              onRejected: @escaping (Error) -> Void) {
        let callback = PromiseCallback(onFulfilled: onFulfilled, onRejected: onRejected, context: queue)
        lockQueue.sync {
            self.callbacks.append(callback)
        }

        fireCallbacksIfNecessary()
    }

    private func fireCallbacksIfNecessary() {
        lockQueue.async(execute: {
            guard !self.threadUnsafeState.isPending else { return }

            self.callbacks.forEach { callback in
                switch self.threadUnsafeState {
                case let .fulfilled(value):
                    callback.callFulfill(value)
                case let .rejected(error):
                    callback.callReject(error)
                default: break
                }
            }

            self.callbacks.removeAll()
        })
    }
}

extension Promise {
    public static func all<T>(_ promises: [Promise<T>]) -> Promise<[T]> {
        return Promise<[T]>(work: { fulfill, reject in
            guard !promises.isEmpty else {
                fulfill([])
                return
            }

            for promise in promises {
                promise.then({ _ in
                    if !promises.contains(where: { $0.isRejected || $0.isPending }) {
                        fulfill(promises.compactMap({ $0.value }))
                    }
                }).catch({ error in
                    reject(error)
                })
            }
        })
    }
}

extension Promise {
    public static func zip<T1, T2>(_ p1: Promise<T1>, _ p2: Promise<T2>) -> Promise<(T1, T2)> {
        return Promise<(T1, T2)>(work: { fulfill, reject in
            let resolver: (Any) -> Void = { _ in
                if let firstValue = p1.value, let secondValue = p2.value {
                    fulfill((firstValue, secondValue))
                }
            }

            p1.then(resolver, reject)
            p2.then(resolver, reject)
        })
    }

    // swiftlint:disable large_tuple
    // swiftlint:disable closure_parameter_position
    public static func zip<T1, T2, T3>(_ p1: Promise<T1>, _ p2: Promise<T2>,
                                       _ last: Promise<T3>) -> Promise<(T1, T2, T3)> {
        return Promise<(T1, T2, T3)>(work: {
            (fulfill: @escaping ((T1, T2, T3)) -> Void, reject: @escaping (Error) -> Void) in
            let zipped: Promise<(T1, T2)> = zip(p1, p2)

            func resolver() {
                if let zippedValue = zipped.value, let lastValue = last.value {
                    fulfill((zippedValue.0, zippedValue.1, lastValue))
                }
            }
            zipped.then({ _ in resolver() }, reject)
            last.then({ _ in resolver() }, reject)
        })
    }
}
