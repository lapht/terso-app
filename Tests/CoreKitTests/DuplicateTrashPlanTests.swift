// SPDX-License-Identifier: GPL-3.0-or-later
//
// Terso — The Auditable Mac Cleaner
// Copyright (C) 2026 Terso Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received first copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import CoreKit
import Foundation
import Testing

private final class PlanFixture {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-plan-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func copy(_ name: String, content: String = "same") throws -> DuplicateTrashCopy {
        let url = root.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return DuplicateTrashCopy(url: url, modificationDate: date)
    }

    func group(_ id: String, _ copies: DuplicateTrashCopy..., size: Int64 = 4) -> DuplicateTrashGroup {
        DuplicateTrashGroup(id: id, fileSizeBytes: size, copies: copies)
    }
}

private func paths(_ copies: DuplicateTrashCopy...) -> Set<String> {
    Set(copies.map { $0.url.standardizedFileURL.path })
}

struct DuplicateTrashPlanTests {
    @Test func nothingSelectedMeansAnEmptyPlan() throws {
        let fixture = try PlanFixture()
        let group = try fixture.group("g", fixture.copy("a"), fixture.copy("b"))

        let plan = try DuplicateTrashPlan.make(groups: [group], selectedPaths: [])

        #expect(plan.items.isEmpty && plan.skipped.isEmpty)
    }

    @Test func theItemsAreExactlyTheSelectedCopiesAndNothingElse() throws {
        let fixture = try PlanFixture()
        let (first, second, third) = try (fixture.copy("a"), fixture.copy("b"), fixture.copy("c"))
        let (other, another) = try (fixture.copy("x", content: "diff"), fixture.copy("y", content: "diff"))
        let groups = [fixture.group("one", first, second, third), fixture.group("two", other, another)]

        let plan = try DuplicateTrashPlan.make(groups: groups, selectedPaths: paths(second, third, another))

        #expect(Set(plan.items.map(\.url.lastPathComponent)) == ["b", "c", "y"])
        #expect(plan.items.allSatisfy {
            $0.moduleId == "files.duplicates" && $0.recommendedAction == .trash && $0.isDeletable
                && !$0.isPreselected && !$0.isProtected && $0.sizeBytes == 4
        })
        #expect(plan.skipped.isEmpty)
    }

    @Test func selectingEveryCopyOfAGroupIsRefused() throws {
        let fixture = try PlanFixture()
        let (first, second) = try (fixture.copy("a"), fixture.copy("b"))

        #expect(throws: DuplicateTrashPlanError.noCopyKept(groupID: "g")) {
            let group = fixture.group("g", first, second)
            try DuplicateTrashPlan.make(groups: [group], selectedPaths: paths(first, second))
        }
    }

    @Test func theCopyThatStaysMustStillExistUnchanged() throws {
        let fixture = try PlanFixture()
        let (first, second) = try (fixture.copy("a"), fixture.copy("b"))
        let group = fixture.group("g", first, second)
        try FileManager.default.removeItem(at: second.url)

        #expect(throws: DuplicateTrashPlanError.noCopyKept(groupID: "g")) {
            try DuplicateTrashPlan.make(groups: [group], selectedPaths: paths(first))
        }

        try "longer than before".write(to: second.url, atomically: true, encoding: .utf8)
        #expect(throws: DuplicateTrashPlanError.noCopyKept(groupID: "g")) {
            try DuplicateTrashPlan.make(groups: [group], selectedPaths: paths(first))
        }
    }

    @Test func aPathOutsideEveryGroupIsRefused() throws {
        let fixture = try PlanFixture()
        let (first, second, stranger) = try (fixture.copy("a"), fixture.copy("b"), fixture.copy("z"))

        #expect(throws: DuplicateTrashPlanError.unknownCopy(path: stranger.url.standardizedFileURL.path)) {
            try DuplicateTrashPlan.make(groups: [fixture.group("g", first, second)], selectedPaths: paths(stranger))
        }
    }

    @Test func changedVanishedAndReplacedCopiesAreSkippedWithAReason() throws {
        let fixture = try PlanFixture()
        let (keep, resized, gone, swapped, retimed) = try (
            fixture.copy("keep"), fixture.copy("resized"), fixture.copy("gone"),
            fixture.copy("swapped"), fixture.copy("retimed")
        )
        let group = fixture.group("g", keep, resized, gone, swapped, retimed)
        try "much longer".write(to: resized.url, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: gone.url)
        try FileManager.default.removeItem(at: swapped.url)
        try FileManager.default.createSymbolicLink(at: swapped.url, withDestinationURL: keep.url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: retimed.url.path
        )

        let selection = paths(resized, gone, swapped, retimed)
        let plan = try DuplicateTrashPlan.make(groups: [group], selectedPaths: selection)

        #expect(plan.items.isEmpty)
        #expect(Set(plan.skipped.map { URL(fileURLWithPath: $0.path).lastPathComponent })
            == ["resized", "gone", "swapped", "retimed"])
        #expect(plan.skipped.allSatisfy { !$0.reason.isEmpty })
    }

    @Test func aCopyWithoutAScanTimeDateIsNeverPlanned() throws {
        let fixture = try PlanFixture()
        let (first, second) = try (fixture.copy("a"), fixture.copy("b"))
        let undated = DuplicateTrashCopy(url: second.url, modificationDate: nil)

        let group = fixture.group("g", first, undated)
        let plan = try DuplicateTrashPlan.make(groups: [group], selectedPaths: paths(undated))

        #expect(plan.items.isEmpty && plan.skipped.count == 1)
    }
}
