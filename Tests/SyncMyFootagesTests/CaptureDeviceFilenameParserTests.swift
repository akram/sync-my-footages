import Foundation
import Testing
@testable import SyncMyFootages

@Suite("DJI Filename Parser")
struct CaptureDeviceFilenameParserTests {
    @Test("Parses standard DJI MP4 filename")
    func parseStandardMP4() {
        let result = CaptureDeviceFilenameParser.parse("DJI_20251222073342_0001_D.MP4")
        #expect(result != nil)
        #expect(result?.sequenceNumber == 1)
        #expect(result?.colorProfile == "D")
        #expect(result?.fileExtension == "MP4")
        #expect(result?.clipID == "20251222073342_0001_D")

        let cal = Calendar(identifier: .gregorian)
        let date = result!.captureDate
        #expect(cal.component(.year, from: date) == 2025)
        #expect(cal.component(.month, from: date) == 12)
        #expect(cal.component(.day, from: date) == 22)
        #expect(cal.component(.hour, from: date) == 7)
        #expect(cal.component(.minute, from: date) == 33)
        #expect(cal.component(.second, from: date) == 42)
    }

    @Test("Parses LRF filename")
    func parseLRF() {
        let result = CaptureDeviceFilenameParser.parse("DJI_20251222073342_0001_D.LRF")
        #expect(result != nil)
        #expect(result?.fileExtension == "LRF")
        #expect(result?.clipID == "20251222073342_0001_D")
    }

    @Test("Parses WAV filename")
    func parseWAV() {
        let result = CaptureDeviceFilenameParser.parse("DJI_20251222073342_0001_D.WAV")
        #expect(result != nil)
        #expect(result?.fileExtension == "WAV")
    }

    @Test("Parses Normal color profile with N suffix")
    func parseNormalProfile() {
        let result = CaptureDeviceFilenameParser.parse("DJI_20260101120000_0042_N.MP4")
        #expect(result != nil)
        #expect(result?.colorProfile == "N")
        #expect(result?.sequenceNumber == 42)
    }

    @Test("Related files share same clipID")
    func clipGrouping() {
        let mp4 = CaptureDeviceFilenameParser.parse("DJI_20251222073342_0001_D.MP4")
        let lrf = CaptureDeviceFilenameParser.parse("DJI_20251222073342_0001_D.LRF")
        let wav = CaptureDeviceFilenameParser.parse("DJI_20251222073342_0001_D.WAV")
        #expect(mp4?.clipID == lrf?.clipID)
        #expect(mp4?.clipID == wav?.clipID)
    }

    @Test("Rejects non-DJI filenames")
    func rejectNonDJI() {
        #expect(CaptureDeviceFilenameParser.parse("IMG_1234.JPG") == nil)
        #expect(CaptureDeviceFilenameParser.parse("video.mp4") == nil)
        #expect(CaptureDeviceFilenameParser.parse("") == nil)
        #expect(CaptureDeviceFilenameParser.parse("DJI_short.MP4") == nil)
    }

    @Test("isDJIFile convenience")
    func isDJIFile() {
        #expect(CaptureDeviceFilenameParser.isDJIFile("DJI_20251222073342_0001_D.MP4") == true)
        #expect(CaptureDeviceFilenameParser.isDJIFile("IMG_1234.JPG") == false)
    }
}
