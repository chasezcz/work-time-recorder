import Testing

/// 可复用的断言辅助。
enum TestHelper {
    /// 断言抛出的错误是指定枚举的具体 case。
    static func expectError<T: Error & Equatable>(
        _ expected: T,
        _ body: () throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try body()
            Issue.record("期望抛出错误 \(expected)，但没有抛出", sourceLocation: sourceLocation)
        } catch let error as T {
            if error != expected {
                Issue.record("抛出的错误为 \(error)，期望 \(expected)", sourceLocation: sourceLocation)
            }
        } catch {
            Issue.record("抛出了意外的错误类型：\(error)", sourceLocation: sourceLocation)
        }
    }
}
