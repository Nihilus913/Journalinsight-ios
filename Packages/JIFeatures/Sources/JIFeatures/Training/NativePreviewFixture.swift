import Foundation
import JICore

/// B-33 §8.5 — the sweep's fixture loader for lane L5's screens.
///
/// Two constraints shape it. `ImageRenderer` never lays out a `ScrollView`'s off-screen content
/// (see `NativeGalleryView`), so a registry entry renders a screen's *composition* in a plain
/// stack rather than the screen's own scrolling root. And the hub DTOs' memberwise inits are
/// internal to `JICore`, so a fixture is decoded from the wire JSON — the same bytes the screen
/// would get from the hub — instead of hand-built.
///
/// `l5` in the name: three Phase-B lanes append to one module, and a lane-scoped helper cannot
/// collide with another lane's.
func l5Fixture<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
    try? JSON.decoder.decode(T.self, from: Data(json.utf8))
}
