import Foundation

/// NOTE:
/// - 以下2つの関数はC側で定義されているマクロ周りの都合から`UnityPluginRegister.m`で宣言されている
///     - `onUnityGfxDeviceEventInitialize`
///     - `onRenderEvent`

/// プラグインの初期化
/// NOTE: `OnGraphicsDeviceEvent -> kUnityGfxDeviceEventInitialize`のタイミングで呼び出される
@_cdecl("onUnityGfxDeviceEventInitialize")
func onUnityGfxDeviceEventInitialize() {
    MetalPlugin.onInitialize()
}

/// Unity側から GL.IssuePluginEvent を呼ぶとレンダリングスレッドから呼び出されるメソッド
@_cdecl("onRenderEvent")
func onRenderEvent(eventId: Int32) {
    MetalPlugin.onRenderEvent(eventId: eventId)
}

// P/Invoke

@_cdecl("setRTCopyTargets")
func setRTCopyTargets(_ src: UnsafeRawPointer?, _ dst: UnsafeRawPointer?) {
    MetalPlugin.setRTCopyTargets(src, dst)
}
