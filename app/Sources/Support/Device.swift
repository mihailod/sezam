import UIKit

/// Which idiom the app is running on.
///
/// Almost every screen here is a `List` in a `NavigationStack` in a `TabView`,
/// and those three adapt to the iPad on their own -- the tab bar moves to the
/// top, sheets become form sheets, the index bar follows the wider trailing
/// edge. Nothing in this app needs to ask.
///
/// The exception is a screen laid out as one centred column rather than as a
/// list: on a 13-inch iPad a full-width column is 1,376 points of mostly
/// nothing. Size class cannot answer that, since "regular" covers everything
/// from a half-screen split to the full display, so the idiom is asked
/// directly. Every use is a maximum width, so an iPad in Slide Over -- as
/// narrow as a phone -- still lays out exactly like one.
enum Device {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The widest a single centred column of text and controls is allowed to
    /// get. Matched to the largest iPhone, so the column reads on an iPad
    /// exactly as the same screen reads on a phone.
    static let readableColumnWidth: CGFloat = 440
}
