import AppTrackingTransparency
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var didRequestTracking = false

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    guard !didRequestTracking else { return }
    didRequestTracking = true
    if #available(iOS 14.5, *) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        ATTrackingManager.requestTrackingAuthorization { _ in }
      }
    }
  }
}
