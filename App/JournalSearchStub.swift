import SwiftUI

// B-33 Contract (wave card W-B33 "## Contract"): `RootTabView`'s search-role `Tab` references
// `JournalSearchView(scopes:query:)` by name. The real screen is owned by lane L6
// (`Packages/JIFeatures/Sources/JIFeatures/Journal/JournalSearchView.swift`); until it lands on
// this branch the app compiles against this one-line stub. Delete this file (and re-run
// `xcodegen generate`) the moment L6's file is on the branch.
public struct JournalSearchView: View {
    public init(scopes: [String], query: Binding<String>) { _query = query; self.scopes = scopes }
    private let scopes: [String]
    @Binding private var query: String
    public var body: some View { Text("search") }
}
