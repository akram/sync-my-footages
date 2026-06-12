import Foundation
import Testing
@testable import SyncMyFootages

@Suite("Rsync Progress Parser")
struct RsyncProgressParserTests {
    @Test("Parses file start line")
    func fileStart() {
        let result = RsyncProgressParser.parse(">f......... DJI_20251222073342_0001_D.MP4")
        guard case .fileStart(let name) = result else {
            Issue.record("Expected fileStart")
            return
        }
        #expect(name == "DJI_20251222073342_0001_D.MP4")
    }

    @Test("Parses file start with plus signs")
    func fileStartPlus() {
        let result = RsyncProgressParser.parse(">f+++++++++ DJI_20251222073342_0001_D.MP4")
        guard case .fileStart(let name) = result else {
            Issue.record("Expected fileStart")
            return
        }
        #expect(name == "DJI_20251222073342_0001_D.MP4")
    }

    @Test("Parses progress line with xfer and to-check")
    func progressLine() {
        let line = "    428123456  45%  120.50MB/s  0:01:23 (xfer#5, to-check=100/500)"
        let result = RsyncProgressParser.parse(line)
        guard case .progress(let bytes, let pct, let xfer, let remaining, let total) = result else {
            Issue.record("Expected progress")
            return
        }
        #expect(bytes == 428123456)
        #expect(pct == 45)
        #expect(xfer == 5)
        #expect(remaining == 100)
        #expect(total == 500)
    }

    @Test("Parses progress with comma-formatted bytes")
    func progressCommaBytes() {
        let line = "    1,234,567  99%  50.00MB/s  0:00:01 (xfer#10, to-check=0/100)"
        let result = RsyncProgressParser.parse(line)
        guard case .progress(let bytes, _, _, _, _) = result else {
            Issue.record("Expected progress")
            return
        }
        #expect(bytes == 1234567)
    }

    @Test("Parses dry-run file listing")
    func dryRunFile() {
        let result = RsyncProgressParser.parseDryRunLine("DJI_20251222073342_0001_D.MP4 428123456")
        guard case .dryRunFile(let name, let size) = result else {
            Issue.record("Expected dryRunFile")
            return
        }
        #expect(name == "DJI_20251222073342_0001_D.MP4")
        #expect(size == 428123456)
    }

    @Test("Returns nil for empty/irrelevant lines")
    func nilForIrrelevant() {
        #expect(RsyncProgressParser.parse("") == nil)
        #expect(RsyncProgressParser.parse("sending incremental file list") == nil)
        #expect(RsyncProgressParser.parse("total size is 12345  speedup is 1.00") == nil)
    }
}
