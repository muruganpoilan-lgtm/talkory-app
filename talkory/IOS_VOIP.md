# iOS full-screen incoming-call ring (VoIP / PushKit)

The Dart and backend sides are done. iOS also needs a one-time native step that must be done in Xcode on a Mac, against a real iPhone.
Apple kills the app if a VoIP push does not immediately show a CallKit call, so test carefully. Follow the
`flutter_callkit_incoming` README for the version you install if anything below differs.

1. **Apple Developer account:** Keys > create an APNs key (`.p8`), note the **Key ID** and your **Team ID**. Save the file as `secrets/AuthKey.p8` on the server.
2. **.env:** `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` (your app's bundle id), `APNS_PRODUCTION=false` for debug builds from Xcode, `true` for TestFlight/App Store builds.
3. **Xcode (Runner target > Signing & Capabilities):** add *Push Notifications* and *Background Modes* with *Voice over IP*, *Audio* and *Remote notifications* ticked.
4. **ios/Runner/AppDelegate.swift:** import PushKit and flutter_callkit_incoming, register for VoIP pushes, and on every incoming VoIP push
   show the call straight away. The backend sends these keys: `id` (call id), `nameCaller`, `handle`, `isVideo`. Sketch:
```swift
import PushKit
import flutter_callkit_incoming

// in application(_:didFinishLaunchingWithOptions:)
let registry = PKPushRegistry(queue: .main)
registry.delegate = self
registry.desiredPushTypes = [.voIP]

extension AppDelegate: PKPushRegistryDelegate {
  func pushRegistry(_ r: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }
  func pushRegistry(_ r: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
    let p = payload.dictionaryPayload
    let data = flutter_callkit_incoming.Data(id: p["id"] as? String ?? "", nameCaller: p["nameCaller"] as? String ?? "", handle: p["handle"] as? String ?? "", type: 0)
    data.extra = ["callId": p["id"] as? String ?? ""]
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)
    completion()
  }
}
```
5. Test: partner logs in on the iPhone and goes online, then lock the phone and call from the user app. It should ring full-screen.
6. Cancel: if the caller hangs up first, a silent Firebase push ends the ring. iOS may delay silent pushes, so the ring can last a few extra seconds. This is an Apple limitation.
