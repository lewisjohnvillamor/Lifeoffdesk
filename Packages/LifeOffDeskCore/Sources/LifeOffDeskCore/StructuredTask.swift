import Foundation

/// One model reply and what the validator thought of it.
public struct TaskAttempt: Hashable, Sendable, Codable {
    public var rawOutput: String
    public var seconds: Double
    public var errors: [String]
}

public enum TaskOutcome<Value: Sendable>: Sendable {
    case valid(Value)
    /// Two invalid replies: show retry/manual controls with the user's input intact.
    case invalid
    case engineError(String)
}

/// Shared runner for the small local-AI tasks (history search, recap narration): each task has
/// its own prompt, grammar and strict validator. At most one bounded repair attempt.
public enum StructuredTask {
    public static func run<Value: Sendable>(
        engine: any IntentEngine, maxTokens: Int, grammar: String?,
        prompt: (_ repairNote: String?) -> String,
        validate: (String) -> Result<Value, TaskValidationError>
    ) async -> (TaskOutcome<Value>, [TaskAttempt]) {
        var attempts: [TaskAttempt] = []
        var repair: String?
        for _ in 0..<2 {
            let start = Date()
            let output: String
            do {
                output = try await engine.complete(prompt: prompt(repair), grammar: grammar, maxTokens: maxTokens)
            } catch {
                return (.engineError("\(error)"), attempts)
            }
            switch validate(output) {
            case let .success(value):
                attempts.append(TaskAttempt(rawOutput: output, seconds: Date().timeIntervalSince(start), errors: []))
                return (.valid(value), attempts)
            case let .failure(error):
                attempts.append(TaskAttempt(rawOutput: output, seconds: Date().timeIntervalSince(start), errors: error.messages))
                repair = "Your previous reply was not valid (\(error.messages.joined(separator: ", "))). Reply with only the JSON object."
            }
        }
        return (.invalid, attempts)
    }

    /// ChatML with Qwen3 thinking disabled. User text is sanitized and quoted as data.
    public static func chatML(system: String, examples: [(user: String, assistant: String)], user: String) -> String {
        var turns = "<|im_start|>system\n\(system)<|im_end|>\n"
        for example in examples {
            turns += "<|im_start|>user\n\(example.user)<|im_end|>\n<|im_start|>assistant\n\(example.assistant)<|im_end|>\n"
        }
        turns += "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        return turns
    }

    /// Parses exactly one JSON object and rejects any key outside `allowed` or missing from it.
    static func object(_ text: String, keys allowed: [String]) -> Result<[String: JSONValue], TaskValidationError> {
        guard let json = PreferenceValidator.extractJSONObject(from: text), let data = json.data(using: .utf8),
              case let .object(object)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .failure(TaskValidationError(["not a JSON object"]))
        }
        var errors: [String] = []
        let extra = Set(object.keys).subtracting(allowed)
        let missing = Set(allowed).subtracting(object.keys)
        if !extra.isEmpty { errors.append("unexpected keys \(extra.sorted().joined(separator: ","))") }
        if !missing.isEmpty { errors.append("missing keys \(missing.sorted().joined(separator: ","))") }
        return errors.isEmpty ? .success(object) : .failure(TaskValidationError(errors))
    }
}

/// Field readers that record type errors instead of guessing.
struct FieldReader {
    let object: [String: JSONValue]
    var errors: [String] = []

    mutating func optionalInt(_ key: String, range: ClosedRange<Int>) -> Int? {
        switch object[key] {
        case nil, .null?: return nil
        case let .number(d)? where d.isFinite && d == d.rounded() && range.contains(Int(exactly: d) ?? Int.min):
            return Int(d)
        default: errors.append("\(key) must be null or an integer in \(range.lowerBound)...\(range.upperBound)"); return nil
        }
    }

    mutating func int(_ key: String, range: ClosedRange<Int>) -> Int {
        if case let .number(d)? = object[key], d == d.rounded(), let i = Int(exactly: d), range.contains(i) { return i }
        errors.append("\(key) must be an integer in \(range.lowerBound)...\(range.upperBound)"); return range.lowerBound
    }

    mutating func optionalBool(_ key: String) -> Bool? {
        switch object[key] {
        case nil, .null?: return nil
        case let .bool(b)?: return b
        default: errors.append("\(key) must be null or a boolean"); return nil
        }
    }

    mutating func bool(_ key: String) -> Bool {
        if case let .bool(b)? = object[key] { return b }
        errors.append("\(key) must be a boolean"); return false
    }

    mutating func optionalString(_ key: String) -> String? {
        switch object[key] {
        case nil, .null?: return nil
        case let .string(s)?: return s
        default: errors.append("\(key) must be null or a string"); return nil
        }
    }

    mutating func enumValue<E: RawRepresentable>(_ key: String) -> E? where E.RawValue == String {
        if case let .string(s)? = object[key], let value = E(rawValue: s) { return value }
        errors.append("\(key) has an unsupported value"); return nil
    }

    mutating func stringList(_ key: String, max: Int) -> [String] {
        guard case let .array(items)? = object[key] else { errors.append("\(key) must be an array"); return [] }
        if items.count > max { errors.append("\(key) allows at most \(max) items") }
        var result: [String] = []
        for item in items {
            guard case let .string(s) = item else { errors.append("\(key) items must be strings"); continue }
            if result.contains(s) { errors.append("\(key) repeats \(s)") } else { result.append(s) }
        }
        return result
    }

    mutating func enumList<E: RawRepresentable>(_ key: String, max: Int) -> [E] where E.RawValue == String {
        stringList(key, max: max).compactMap { raw in
            guard let value = E(rawValue: raw) else { errors.append("\(key) has unsupported \(raw)"); return nil }
            return value
        }
    }
}

public struct TaskValidationError: Error, Hashable, Sendable {
    public var messages: [String]
    public init(_ messages: [String]) { self.messages = messages }
}
