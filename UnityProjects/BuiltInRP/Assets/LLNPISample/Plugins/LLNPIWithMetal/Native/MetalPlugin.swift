import Foundation

enum EventId: Int32 {
    case extraDrawCall = 0
    case captureRT = 1
}

final class MetalPlugin {

    static var unityMetal: IUnityGraphicsMetalV1!

    static func onInitialize() {
        guard let metal = UnityGraphicsBridge.getUnityGraphicsMetalV1() else {
            preconditionFailure()
            return
        }

        unityMetal = metal.pointee

        print("-------------------")
        print(unityMetal.MetalDevice())
        print(unityMetal.MetalBundle())
        print(unityMetal.CurrentRenderPassDescriptor())
    }

    static func onRenderEvent(eventId: Int32) {
        switch EventId(rawValue: eventId)! {
        case .extraDrawCall:
            // TODO: DoExtraDrawCall();
            break
            // TODO: DoCaptureRT();
        case .captureRT:
            break
        }
    }

    // copy of render surface to a texture

    static func setRTCopyTargets(_ src: UnsafeRawPointer?, _ dst: UnsafeRawPointer?) {
        //g_CopySrcRB = src, g_CopyDstRB = dst;
    }
}

/*
 UNITY_DECLARE_INTERFACE(IUnityGraphicsMetalV1)
{
    NSBundle* (UNITY_INTERFACE_API * MetalBundle)();
    id<MTLDevice>(UNITY_INTERFACE_API * MetalDevice)();

    id<MTLCommandBuffer>(UNITY_INTERFACE_API * CurrentCommandBuffer)();

    // for custom rendering support there are two scenarios:
    // you want to use current in-flight MTLCommandEncoder (NB: it might be nil)
    // カスタムレンダリングをサポートするには、2つのシナリオがあります。
    // 現在の機内の MTLCommandEncoder を使用したい場合（注意：nil かもしれません）。
    id<MTLCommandEncoder>(UNITY_INTERFACE_API * CurrentCommandEncoder)();

    // or you might want to create your own encoder.
    // In that case you should end unity's encoder before creating your own and end yours before returning control to unity
    // あるいは、独自のエンコーダを作りたいかもしれません。
    // その場合、独自のエンコーダを作成する前に unity のエンコーダを終了し、制御を unity に戻す前に自分のエンコーダを終了する必要があります。
    void(UNITY_INTERFACE_API * EndCurrentCommandEncoder)();

    // returns MTLRenderPassDescriptor used to create current MTLCommandEncoder
    // 現在のMTLCommandEncoderを作成するために使用されたMTLRenderPassDescriptorを返す
    MTLRenderPassDescriptor* (UNITY_INTERFACE_API * CurrentRenderPassDescriptor)();

    // converting trampoline UnityRenderBufferHandle into native RenderBuffer
    // トランポリンUnityRenderBufferHandleをネイティブRenderBufferに変換する
    UnityRenderBuffer(UNITY_INTERFACE_API * RenderBufferFromHandle)(void* bufferHandle);

    // access to RenderBuffer's texure
    // NB: you pass here *native* RenderBuffer, acquired by calling (C#) RenderBuffer.GetNativeRenderBufferPtr
    // AAResolvedTextureFromRenderBuffer will return nil in case of non-AA RenderBuffer or if called for depth RenderBuffer
    // StencilTextureFromRenderBuffer will return nil in case of no-stencil RenderBuffer or if called for color RenderBuffer
    // RenderBufferのテクスチャにアクセスする。
    // RenderBuffer.GetNativeRenderBufferPtrを呼び出して取得したRenderBufferを渡します。
    // AAResolvedTextureFromRenderBufferは、非AAのRenderBufferの場合、または深さのRenderBufferに対して呼ばれた場合、nilを返します。
    // StencilTextureFromRenderBuffer はステンシルなしの RenderBuffer の場合、または color RenderBuffer に対してコールされた場合、nil を返します。
    id<MTLTexture>(UNITY_INTERFACE_API * TextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * AAResolvedTextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * StencilTextureFromRenderBuffer)(UnityRenderBuffer buffer);
};
UNITY_REGISTER_INTERFACE_GUID(0x29F8F3D03833465EULL, 0x92138551C15D823DULL, IUnityGraphicsMetalV1)
 */