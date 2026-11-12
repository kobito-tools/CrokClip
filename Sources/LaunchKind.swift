import AppKit

/// 起動のしかた。手で開いたときは設定画面を出し、初めての人にも起動したことが分かるようにする。
/// ログイン時の自動起動と、URL（corkclip:// など）での起動では出さない。
enum LaunchKind {
    /// 起動の Apple Event（kAEOpenApplication）が、ログイン項目としての起動を示しているか。
    static func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// 起動を終えたときに設定画面を開くか。URL で起動されたときは、その操作を優先する。
    static func shouldOpenSettingsOnLaunch(launchedAsLoginItem: Bool, hasPendingURL: Bool) -> Bool {
        !launchedAsLoginItem && !hasPendingURL
    }
}
