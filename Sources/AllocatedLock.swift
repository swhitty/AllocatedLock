//
//  AllocatedLock.swift
//  AllocatedLock
//
//  Created by Simon Whitty on 10/04/2023.
//  Copyright 2023 Simon Whitty
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/swhitty/AllocatedLock
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

// Backports the Swift interface around os_unfair_lock_t available in recent Darwin platforms
//
@available(iOS, deprecated: 16.0, message: "use OSAllocatedUnfairLock directly")
@available(tvOS, deprecated: 16.0, message: "use OSAllocatedUnfairLock directly")
@available(watchOS, deprecated: 9, message: "use OSAllocatedUnfairLock directly")
@available(macOS, deprecated: 13.0, message: "use OSAllocatedUnfairLock directly")
public struct AllocatedLock<State> {

    private let storage: Storage

    public init(initialState: State) {
        self.storage = Storage(initialState: initialState)
    }

    public func withLock<R>(_ body: @Sendable (inout State) throws -> R) rethrows -> R where R: Sendable {
        storage.lock()
        defer { storage.unlock() }
        return try body(&storage.state)
    }
}

public extension AllocatedLock where State == Void {

    init() {
        self.storage = Storage(initialState: ())
    }

    func lock() {
        storage.lock()
    }

    func unlock() {
        storage.unlock()
    }

    func withLock<R>(_ body: @Sendable () throws -> R) rethrows -> R where R: Sendable {
        storage.lock()
        defer { storage.unlock() }
        return try body()
    }
}

#if canImport(Darwin)
@_implementationOnly import os

private extension AllocatedLock {
    final class Storage {
        private let _lock: os_unfair_lock_t
        var state: State

        init(initialState: State) {
            self._lock = .allocate(capacity: 1)
            self._lock.initialize(to: os_unfair_lock())
            self.state = initialState
        }

        func lock() {
            os_unfair_lock_lock(_lock)
        }

        func unlock() {
            os_unfair_lock_unlock(_lock)
        }

        deinit {
            self._lock.deinitialize(count: 1)
            self._lock.deallocate()
        }
    }
}

#elseif canImport(Glibc)
@_implementationOnly import Glibc

private extension AllocatedLock {
    final class Storage {
        private let _lock: UnsafeMutablePointer<pthread_mutex_t>

        var state: State

        init(initialState: State) {
            var attr = pthread_mutexattr_t()
            pthread_mutexattr_init(&attr)
            self._lock = .allocate(capacity: 1)
            let err = pthread_mutex_init(self._lock, &attr)
            precondition(err == 0, "pthread_mutex_init error: \(err)")
            self.state = initialState
        }

        func lock() {
            let err = pthread_mutex_lock(_lock)
            precondition(err == 0, "pthread_mutex_lock error: \(err)")
        }

        func unlock() {
            let err = pthread_mutex_unlock(_lock)
            precondition(err == 0, "pthread_mutex_unlock error: \(err)")
        }

        deinit {
            let err = pthread_mutex_destroy(self._lock)
            precondition(err == 0, "pthread_mutex_destroy error: \(err)")
            self._lock.deallocate()
        }
    }
}
#endif