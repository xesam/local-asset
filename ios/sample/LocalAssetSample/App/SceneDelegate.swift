import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        // 不再套 UINavigationController：演示的首页与页间跳转都在 WebView 里（shared/demo/pages/），
        // 保留导航栏会让 iOS 顶部比另外两端多出一条，与"三端外观一致"的目标相悖。
        window?.rootViewController = DemoViewController()
        window?.makeKeyAndVisible()
    }
}
