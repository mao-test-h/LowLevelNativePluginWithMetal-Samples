import Foundation

/// Unity側から GL.IssuePluginEvent を呼ぶとレンダリングスレッドから呼び出されるメソッド
///
/// NOTE:
/// - P/Invokeで呼び出される関数自体はマクロ周りの都合から`UnityPluginRegister.m`で宣言されている
/// - ここではObjC側で宣言されている外部宣言関数を実装しているだけ
@_cdecl("onRenderEvent")
public func onRenderEvent(eventId: Int32) {
    MetalPlugin.onRenderEvent(eventId: eventId)

    guard let metal = UnityGraphicsBridge.getUnityGraphicsMetalV1() else {
        return
    }

    let metalv1 : IUnityGraphicsMetalV1 = metal.pointee
    print(metalv1.MetalDevice())
    print(metalv1.MetalBundle())

}

// P/Invoke

@_cdecl("setRTCopyTargets")
public func setRTCopyTargets(_ src: UnsafeRawPointer?, _ dst: UnsafeRawPointer?) {
    MetalPlugin.setRTCopyTargets(src, dst)
}
