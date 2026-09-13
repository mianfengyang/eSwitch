import Foundation

// MARK: - App Name Initial
extension String {
    /// 应用名首字母：取第一个 ASCII 字母（大写）；
    /// 跳过非字母字符（中文、emoji、符号等）；无任何字母时回退 "•"。
    var switcherInitial: String {
        for ch in self.trimmingCharacters(in: .whitespacesAndNewlines) {
            if ch.isASCII {
                if "a"..."z" ~= ch || "A"..."Z" ~= ch {
                    return ch.uppercased()
                }
            }
            // 非字母字符（中文/emoji/符号）跳过，继续找下一个字母
        }
        return "•"
    }
}
