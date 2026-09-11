import Foundation

// MARK: - App Name Initial
extension String {
    /// 应用名首字母：英文取首个字母（大写）；中文取首字的拼音首字母；
    /// 跳过无法转换出字母的字符（emoji、符号等）；都找不到时回退首个字符。
    var switcherInitial: String {
        let s = trimmingCharacters(in: .whitespacesAndNewlines)
        for ch in s {
            if ch.isASCII {
                // ASCII 下：字母直接采用；空格跳过（取下一个词）；其它符号无法出字母，终止
                if "a"..."z" ~= ch || "A"..."Z" ~= ch {
                    return ch.uppercased()
                }
                if ch == " " { continue }
                break
            }
            let mut = NSMutableString(string: String(ch))
            CFStringTransform(mut, nil, kCFStringTransformMandarinLatin, false)
            CFStringTransform(mut, nil, kCFStringTransformStripDiacritics, false)
            if let letter = (mut as String).unicodeScalars.first,
               "a"..."z" ~= Character(letter) || "A"..."Z" ~= Character(letter) {
                return Character(letter).uppercased().description
            }
            // 该字符无法转换出字母（emoji 等），继续找下一个
        }
        guard let first = s.first else { return "?" }
        return first.uppercased().description
    }
}
