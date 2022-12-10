import Foundation
import Metal

final class MetalPlugin {

    private enum EventId: Int32 {
        case extraDrawCall = 0
        case captureRT = 1
    }

    static var shared: MetalPlugin! = nil

    private let unityMetal: IUnityGraphicsMetalV1
    private let vertexShader: MTLFunction
    private let fragmentShaderColor: MTLFunction
    private let fragmentShaderTexture: MTLFunction
    private let vertexBuffer: MTLBuffer
    private let indicesBuffer: MTLBuffer
    private let vertexDesc = MTLVertexDescriptor()

    // ExtraDrawCall
    private var extraDrawCallPixelFormat: MTLPixelFormat = .invalid
    private var extraDrawCallSampleCount: Int = 0
    private var extraDrawCallPipelineState: MTLRenderPipelineState? = nil

    // CaptureRT
    private var rtCopy: MTLTexture? = nil
    private var rtCopyPixelFormat: MTLPixelFormat = .invalid
    private var rtCopySampleCount: Int = 0
    private var rtCopyPipelineState: MTLRenderPipelineState? = nil
    private var copySrc: UnityRenderBuffer? = nil
    private var copyDst: UnityRenderBuffer? = nil

    init(with unityMetal: IUnityGraphicsMetalV1) {
        self.unityMetal = unityMetal

        guard let device: MTLDevice = unityMetal.MetalDevice(),
              let library = try? device.makeLibrary(source: Shader.shaderSrc, options: nil),
              let vertexShader = library.makeFunction(name: "vprog"),
              let fragmentShaderColor = library.makeFunction(name: "fshader_color"),
              let fragmentShaderTexture = library.makeFunction(name: "fshader_tex")
        else {
            preconditionFailure()
        }

        self.vertexShader = vertexShader
        self.fragmentShaderColor = fragmentShaderColor
        self.fragmentShaderTexture = fragmentShaderTexture

        // pos.x pos.y uv.x uv.y
        let vdata: [Float] = [
            -1.0, 0.0, 0.0, 0.0,
            -1.0, -1.0, 0.0, 1.0,
            0.0, -1.0, 1.0, 1.0,
            0.0, 0.0, 1.0, 0.0,
        ]
        let vdataLength = vdata.count * MemoryLayout<Float>.size

        let idata: [UInt16] = [0, 1, 2, 2, 3, 0]
        let idataLength = idata.count * MemoryLayout<UInt16>.size

        guard let vertexBuffer = device.makeBuffer(bytes: vdata, length: vdataLength, options: .cpuCacheModeWriteCombined),
              let indicesBuffer = device.makeBuffer(bytes: idata, length: idataLength, options: .cpuCacheModeWriteCombined)
        else {
            preconditionFailure()
        }

        self.vertexBuffer = vertexBuffer
        self.indicesBuffer = indicesBuffer

        let attrDesc = MTLVertexAttributeDescriptor()
        attrDesc.format = .float4

        let streamDesc = MTLVertexBufferLayoutDescriptor()
        streamDesc.stride = 4 * MemoryLayout<Float>.size
        streamDesc.stepFunction = .perVertex
        streamDesc.stepRate = 1

        vertexDesc.attributes[0] = attrDesc
        vertexDesc.layouts[0] = streamDesc
    }

    func onRenderEvent(eventId: Int32) {
        switch EventId(rawValue: eventId)! {
        case .extraDrawCall:
            ExtraDrawCall()
            break
        case .captureRT:
            CaptureRT()
            break
        }
    }

    /// copy of render surface to a texture
    func setRTCopyTargets(_ src: UnityRenderBuffer, _ dst: UnityRenderBuffer) {
        copySrc = src
        copyDst = dst
    }

    /// to simplify our lives: we will use similar setup for both "color rect" and "texture" draw calls
    /// the only reason we cannot pre-alloc them is that we want to handle changing RT transparently
    private func createCommonRenderPipeline(
        fragmentShader: MTLFunction,
        format: MTLPixelFormat,
        sampleCount: Int) -> MTLRenderPipelineState {

        guard let device: MTLDevice = unityMetal.MetalDevice() else {
            preconditionFailure()
        }

        let colorDesc = MTLRenderPipelineColorAttachmentDescriptor()
        colorDesc.pixelFormat = format

        let pipelineStateDesc = MTLRenderPipelineDescriptor()
        pipelineStateDesc.label = "Triangle Pipeline"
        pipelineStateDesc.vertexFunction = vertexShader
        pipelineStateDesc.vertexDescriptor = vertexDesc
        pipelineStateDesc.fragmentFunction = fragmentShader
        pipelineStateDesc.colorAttachments[0] = colorDesc
        pipelineStateDesc.rasterSampleCount = sampleCount

        return try! device.makeRenderPipelineState(descriptor: pipelineStateDesc)
    }

    /// we need to take special care about what "texture" do we use
    ///   as in case we are given AA-ed RT we need to use "resolved" texture
    private func getColorTexture(_ renderBuffer: UnityRenderBuffer) -> MTLTexture? {
        if let texture = unityMetal.AAResolvedTextureFromRenderBuffer(renderBuffer) {
            return texture
        } else {
            if let texture = unityMetal.TextureFromRenderBuffer(renderBuffer) {
                return texture
            } else {
                return nil
            }
        }
    }

    /// extra draw call: we will hook into current rendering and draw simple colored rect
    private func ExtraDrawCall() {
        guard let desc = unityMetal.CurrentRenderPassDescriptor(),
              // get current render pass setup
              let rt: MTLTexture = desc.colorAttachments[0].texture,
              // get current command encoder
              let cmd: MTLCommandEncoder = unityMetal.CurrentCommandEncoder()
        else {
            preconditionFailure()
        }

        if (rt.pixelFormat != extraDrawCallPixelFormat || rt.sampleCount != extraDrawCallSampleCount) {
            // RT format changed - recreate render pipeline
            extraDrawCallPixelFormat = rt.pixelFormat
            extraDrawCallSampleCount = rt.sampleCount
            extraDrawCallPipelineState = createCommonRenderPipeline(
                fragmentShader: fragmentShaderColor,
                format: extraDrawCallPixelFormat,
                sampleCount: extraDrawCallSampleCount)
        }

        guard let extraDrawCallPipelineState = extraDrawCallPipelineState,
              let cmd = cmd as? MTLRenderCommandEncoder
        else {
            preconditionFailure()
        }

        // update render setup and do extra draw call
        cmd.setRenderPipelineState(extraDrawCallPipelineState)
        cmd.setCullMode(.none)
        cmd.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        cmd.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indicesBuffer,
            indexBufferOffset: 0)
    }

    private func CaptureRT() {
        if (copySrc == nil || copyDst == nil) {
            print("RTs to copy are not set!\n");
            return
        }

        guard let device: MTLDevice = unityMetal.MetalDevice(),
              let cmdBuffer = unityMetal.CurrentCommandBuffer(),
              let copySrc = copySrc,
              let copyDst = copyDst
        else {
            preconditionFailure()
        }

        // get actual texture we want to copy
        guard let src: MTLTexture = getColorTexture(copySrc),
              // render to dst RT
              let dst: MTLTexture = getColorTexture(copyDst)
        else {
            return
        }

        // end current encoder
        unityMetal.EndCurrentCommandEncoder()

        // make sure we recreate texture itself if needed
        if rtCopy == nil ||
               rtCopy!.width != src.width ||
               rtCopy!.height != src.height ||
               rtCopy!.pixelFormat != src.pixelFormat {
            let texDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: src.pixelFormat,
                width: src.width,
                height: src.height,
                mipmapped: false)
            self.rtCopy = device.makeTexture(descriptor: texDesc)
        }

        guard let rtCopy = rtCopy else {
            preconditionFailure()
        }

        // do the copy to temp texture
        if let blit = cmdBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: src,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: src.width, height: src.height, depth: 1),
                to: rtCopy,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }

        // prepare render pass
        let att = MTLRenderPassColorAttachmentDescriptor()
        // NB we assume AA was already resolved, so we dont care
        att.texture = dst
        att.loadAction = .load
        att.storeAction = .store

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0] = att

        // prepare render pipeline
        if (dst.pixelFormat != rtCopyPixelFormat || dst.sampleCount != rtCopySampleCount) {
            rtCopyPixelFormat = dst.pixelFormat
            rtCopySampleCount = dst.sampleCount
            rtCopyPipelineState = createCommonRenderPipeline(
                fragmentShader: fragmentShaderTexture,
                format: rtCopyPixelFormat,
                sampleCount: rtCopySampleCount)
        }

        // render
        if let cmd = cmdBuffer.makeRenderCommandEncoder(descriptor: desc),
           let rtCopyPipelineState = rtCopyPipelineState {
            cmd.setRenderPipelineState(rtCopyPipelineState)
            cmd.setCullMode(.none)
            cmd.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            cmd.setFragmentTexture(rtCopy, index: 0)
            cmd.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: indicesBuffer,
                indexBufferOffset: 0)
            cmd.endEncoding()
        }
    }
}

final class Shader {
    static let shaderSrc: String =
        """
        #include <metal_stdlib>
        using namespace metal;

        struct AppData
        {
            float4 in_pos [[attribute(0)]];
        };

        struct VProgOutput
        {
            float4 out_pos [[position]];
            float2 texcoord;
        };

        struct FShaderOutput
        {
            half4 frag_data [[color(0)]];
        };

        vertex VProgOutput vprog(
            AppData input [[stage_in]]
        )
        {
            VProgOutput out = { float4(input.in_pos.xy, 0, 1), input.in_pos.zw };
            return out;
        }

        constexpr sampler blit_tex_sampler(address::clamp_to_edge, filter::linear);

        fragment FShaderOutput fshader_tex(
            VProgOutput input [[stage_in]],
            texture2d<half> tex [[texture(0)]]
        )
        {
            FShaderOutput out = { tex.sample(blit_tex_sampler, input.texcoord) };
            return out;
        }

        fragment FShaderOutput fshader_color(
            VProgOutput input [[stage_in]]
        )
        {
            FShaderOutput out = { half4(1,0,0,1) };
            return out;
        }
        """
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
