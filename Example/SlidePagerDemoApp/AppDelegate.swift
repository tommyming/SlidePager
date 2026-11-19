import UIKit

@main
final class AppDelegate: NSObject, UIApplicationDelegate {

    // Scene lifecycle. UIKit only calls this when Info.plist has UIApplicationSceneManifest.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
