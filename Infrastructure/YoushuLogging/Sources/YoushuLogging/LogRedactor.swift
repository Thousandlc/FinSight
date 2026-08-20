import Foundation

/// 日志脱敏：禁止输出完整金额、身份信息、Token、API Key、图片内容。
public enum LogRedactor {
    public static func redact(_ message: String) -> String {
        var result = message
        result = replace(result, pattern: #"(?i)(api[_-]?key|token|bearer|authorization)\s*[:=]\s*\S+"#, with: "$1=[REDACTED]")
        result = replace(result, pattern: #"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#, with: "Bearer [REDACTED]")
        result = replace(result, pattern: #"¥\s*-?[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?"#, with: "¥[AMOUNT]")
        result = replace(result, pattern: #"(?i)(amount|balance|income|expense|debt)\s*[:=]\s*-?[0-9]+(?:\.[0-9]+)?"#, with: "$1=[AMOUNT]")
        result = replace(result, pattern: #"(?i)(phone|mobile|身份证|id[_-]?card)\s*[:=]\s*\S+"#, with: "$1=[PII]")
        result = replace(result, pattern: #"data:image/[a-zA-Z]+;base64,[A-Za-z0-9+/=]{32,}"#, with: "[IMAGE_REDACTED]")
        if result.count > 4000, looksLikeBinaryBlob(result) {
            return "[BINARY_REDACTED len=\(result.count)]"
        }
        return result
    }

    public static func containsSensitiveLeak(_ message: String) -> Bool {
        let patterns = [
            #"(?i)api[_-]?key\s*[:=]\s*(?!\[REDACTED\])\S+"#,
            #"Bearer\s+(?!\[REDACTED\])[A-Za-z0-9\-._~+/]+=*"#,
            #"¥\s*-?[0-9]+"#,
            #"data:image/"#,
        ]
        for pattern in patterns {
            if message.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static func replace(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }

    private static func looksLikeBinaryBlob(_ text: String) -> Bool {
        let sample = text.prefix(200)
        let allowed = CharacterSet.alphanumerics.union(.whitespacesAndNewlines).union(CharacterSet(charactersIn: "+/="))
        let weird = sample.unicodeScalars.filter { !allowed.contains($0) }.count
        return weird > 40
    }
}
