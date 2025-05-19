import SwiftUI

struct JSONSyntaxView: View {
    let jsonString: String

    var body: some View {
        ZStack {
            if let data = jsonString.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(
                   withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8)
            {
                ScrollView {
                    FormattedJSONText(jsonString: prettyString)
                        .padding(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(jsonString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(4)
            }
            VStack {
                HStack {
                    Spacer()
                    CopyButton(content: jsonString)
                        .padding([.top, .trailing], 5.0)
                }
                Spacer()
            }
        }
    }
}

struct FormattedJSONText: View {
    let jsonString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(jsonLines, id: \.self) { line in
                HStack(spacing: 0) {
                    ForEach(tokenizeJSONLine(line), id: \.id) { token in
                        Text(token.text)
                            .foregroundColor(colorForToken(token.type))
                    }
                    Spacer()
                }
            }
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(alignment: .leading)
    }

    private var jsonLines: [String] {
        jsonString.components(separatedBy: "\n")
    }

    private func colorForToken(_ type: JSONTokenType) -> Color {
        switch type {
        case .key:
            return .blue
        case .string:
            return .mint
        case .number:
            return .orange
        case .bool:
            return .purple
        case .null:
            return .red
        case .punctuation:
            return .gray
        case .other:
            return .primary
        }
    }

    private func tokenizeJSONLine(_ line: String) -> [JSONToken] {
        var tokens: [JSONToken] = []
        var currentIndex = 0

        // Simple regex patterns for JSON tokens
        let patterns: [(pattern: String, type: JSONTokenType)] = [
            ("\\s+", .other), // Whitespace
            ("\"[^\"]*\"\\s*:", .key), // Keys
            ("\"[^\"]*\"", .string), // String values
            ("\\b-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?\\b", .number), // Number values (including scientific notation)
            ("\\btrue\\b|\\bfalse\\b", .bool), // Boolean values
            ("\\bnull\\b", .null), // Null values
            ("[\\{\\}\\[\\],:]", .punctuation), // Punctuation
        ]

        while currentIndex < line.count {
            let substring = String(line[line.index(line.startIndex, offsetBy: currentIndex)...])
            var matched = false

            for (pattern, type) in patterns {
                if let range = substring.range(of: pattern, options: .regularExpression) {
                    if range.lowerBound == substring.startIndex {
                        let matchedText = String(substring[range])
                        tokens.append(JSONToken(id: UUID(), text: matchedText, type: type))
                        currentIndex += matchedText.count
                        matched = true
                        break
                    }
                }
            }

            if !matched {
                // If no pattern matches, add one character as "other"
                let index = line.index(line.startIndex, offsetBy: currentIndex)
                tokens.append(JSONToken(id: UUID(), text: String(line[index]), type: .other))
                currentIndex += 1
            }
        }

        return tokens
    }
}

enum JSONTokenType {
    case key, string, number, bool, null, punctuation, other
}

struct JSONToken {
    let id: UUID
    let text: String
    let type: JSONTokenType
}

#Preview {
    JSONSyntaxView(jsonString: "{\"key\": \"value\", \"number\": 123, \"bool\": true, \"null\": null}")
        .padding()
        .frame(width: 500)
}
