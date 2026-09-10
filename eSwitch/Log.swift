import Foundation

func log(_ msg: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(msg)\n"
    let path = "/tmp/eswitch_debug.log"
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
