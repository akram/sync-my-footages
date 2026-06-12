import Foundation
import Testing
@testable import RsyncMyFootages

@Suite("File Organizer Pattern Expansion")
struct FileOrganizerTests {
    let date: Date = {
        var c = DateComponents()
        c.year = 2025; c.month = 12; c.day = 22
        c.hour = 12; c.minute = 0; c.second = 0
        c.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    @Test("Basic pattern with type")
    func basicPattern() {
        let result = FileOrganizer.expandPattern(
            "{device}/{year}{month}{day}/{type}",
            deviceType: .osmoPocket3, captureDate: date, fileExtension: "MP4"
        )
        #expect(result == "OsmoPocket3/20251222/videos")
    }

    @Test("Pattern with dashes in date")
    func dashDate() {
        let result = FileOrganizer.expandPattern(
            "{device}/{year}-{month}-{day}",
            deviceType: .osmoPocket3, captureDate: date, fileExtension: "MP4"
        )
        #expect(result == "OsmoPocket3/2025-12-22")
    }

    @Test("Type token resolves different extensions")
    func typeToken() {
        let mp4 = FileOrganizer.expandPattern("{type}", deviceType: .osmoPocket3, captureDate: date, fileExtension: "MP4")
        let wav = FileOrganizer.expandPattern("{type}", deviceType: .osmoPocket3, captureDate: date, fileExtension: "WAV")
        let lrf = FileOrganizer.expandPattern("{type}", deviceType: .osmoPocket3, captureDate: date, fileExtension: "LRF")
        #expect(mp4 == "videos")
        #expect(wav == "audios")
        #expect(lrf == "lowres")
    }

    @Test("Full pattern with type and date")
    func fullPattern() {
        let result = FileOrganizer.expandPattern(
            "{device}/{year}{month}{day}/{type}",
            deviceType: .action5Pro, captureDate: date, fileExtension: "WAV"
        )
        #expect(result == "Action5Pro/20251222/audios")
    }
}

@Suite("Project Manager")
struct ProjectManagerTests {
    @Test("Parse PROJECT.md with frontmatter")
    func parseProject() {
        let content = """
        ---
        title: RC Car Vlog
        client: Personal
        ---
        Some notes about the project
        """
        let project = ProjectFile.parse(content: content, directoryPath: "/test")
        #expect(project?.title == "RC Car Vlog")
        #expect(project?.fields["client"] == "Personal")
        #expect(project?.body == "Some notes about the project")
    }

    @Test("Sanitized title removes special chars")
    func sanitizedTitle() {
        let project = ProjectFile(directoryPath: "/test", fields: ["title": "My Trip / Holiday"], body: "")
        #expect(project.sanitizedTitle == "My Trip - Holiday")
    }
}
