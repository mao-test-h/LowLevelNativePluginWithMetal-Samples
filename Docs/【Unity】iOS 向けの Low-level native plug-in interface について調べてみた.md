【Unity】iOS 向けの Low-level native plug-in interface を利用した Metal API へのアクセスについて調べてみた

この記事は [Unity Advent Calendar 2022](https://qiita.com/advent-calendar/2022/unity) の18日目の記事です。


Unityには [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html) と言う機能が存在しており、こちらを利用することでUnityが内部的に持っている各プラットフォーム向けの低レベルな GraphicsAPI にアクセスすることが出来るようになります。

https://docs.unity3d.com/Manual/NativePluginInterface.html

じゃあ具体的にこれで何が出来るのか？と言うと、例えば今回話す iOS 向けの場合には「**Unityが持つ`MTLCommandEncoder`をフックして追加で描画命令を挟んだり、若しくはこちらを終了させて自身で`MTLCommandEncoder`を追加する**」と言ったことが行えるようになります。


実装例としては Unity 公式のリポジトリにてサンプルプロジェクトが公開されてますが、今回はこちらを参考に同じ例を再実装する形で所々補足しつつ解説していければと思います。

https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin





# この記事で解説する内容について

この記事では先程挙げた[公式のサンプルプロジェクト](https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin)をベースに以下のトピックについて順に解説します。

- **iOS向けの `Low-level native plug-in interface` の導入について**
    - レンダースレッドからの任意のレンダリングメソッドを呼び出すには
    - Swift で実装していくにあたっての補足
- **公式サンプルをベースに実装内容の解説**

あとは幾つかの用語についてはそのままだと長いので、以降は以下の省略表記で記載していきます。

- `Low-level native plug-in interface` → `LLNPI`
    - ※頭文字を取って省略
- `Objective-C` → `ObjC`


## 環境とサンプルプロジェクト

- **環境**
    - Unity 2022.2.0f1
        - **Built-in RenderPipeline**
    - Xcode 14.1
- **プラットフォーム**
    - iOS/iPadOS 15.0 +

**サンプルプロジェクト**

https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples


:::note warn
記載の通り、このプロジェクトでは **Built-in RenaderPipleine**を前提に実装してます。  
(URPは調査中...)
::: 


## 記事の目的

上記の内容を踏まえて `LLNPI` を把握し、応用したり深く調べていく際の足がかりとするところまでを目的としてます。

:::note info
ちなみに自身がこの記事を書くに至ったモチベーションとして、Unityに [MetalFX](https://developer.apple.com/documentation/metalfx) を組み込んでみたかったと言う経緯があります。

詳細については[次回予告](#次回予告)の章にて改めて解説します。　
::: 

### ◇ 前提となる予備知識

記事を読むにあたっては以下の予備知識を必要とします。

- Unity 及び iOS向けのネイティブプラグインの実装知識
- [Metal](https://developer.apple.com/jp/metal/) の基礎知識

この記事中では詳細までは解説しないので、知らない方は別途入門者向けの資料などを見てキャッチアップを済ませてあるところまでを前提に書いていきます。

:::note warn
と書いたものの...自分も Metal に関してはまだ初学者なので、もし間違いや違和感のある記載など見かけたら、コメントや編集リクエストなどでご指摘いただけると幸いです。。 :bow: 
::: 





# iOS向けの `LLNPI` の導入について

先ずはiOS環境にて `LLNPI` をどうやって導入するのか？について解説します。

やり方の大凡は[公式ドキュメント](https://docs.unity3d.com/Manual/NativePluginInterface.html)の方にも書かれておりますが、**iOS向けで使う場合には幾つか追加で別途対応を行う箇所が存在する**ので、そこらも補足しつつ解説していければと思います。

導入まで済んだら **Unity が持つ低レベルな GraphicsAPI へアクセスするためのインターフェースが手に入る**ので、次にこちらを用いるための「レンダースレッドから任意のレンダリングメソッドを呼び出す方法」について解説していきます。

:::note note
今回のサンプルプロジェクトでは大凡のロジック周りはSwiftで実装してますが、これから解説する **`LLNPI` の初期化やイベントの登録周りについてはマクロ周りが絡む都合上、ObjC で実装してます。** [^1]

他にも **Swift で実装をしていくにあたっては幾つか追加で設定が必要となってくる**ので、こちらについては「[Swiftで実装していくにあたっての補足](#swiftで実装していくにあたっての補足)」の章にて解説します。
:::

[^1]: ObjC はなるべく最低限の範囲で済むように実装してますが、もし Swift だけで完結可能な手法があったら、コメントや編集リクエストなどで教えていただけると幸いです...

## インターフェースの登録

`LLNPI` は **Unity が事前に用意してくれている仕組みをネイティブプラグインとして実装する**ことで、低レベルな GraphicsAPI  にアクセスする事ができるようになります。

もう少し具体的に言うと、**iOSの場合にはネイティブプラグイン側で `UnityPluginLoad` と `UnityPluginUnload` と言う関数を実装し、後述する手順で登録することで Unity がこちらの関数を呼び出してくれるようになります。**

その上で**更にここから今回の肝である GraphicsAPI へアクセスするためのインターフェースを受け取ることが出来るので、** それを用いることで低レベルな GraphicsAPI にアクセスすることが可能です。

:::note note
`LLNPI` は iOS 以外のプラットフォームでも共通して使える機能であり、プラットフォームによっては後述する登録の手順を踏まずとも `UnityPluginLoad` と `UnityPluginUnload` を定義して公開するだけで自動で呼び出してくれる環境もあるみたいです。

これらの制約は iOS がプラットフォーム的にダイナミックライブラリを使えないので、ライブラリから名前指定で関数をロードすることができないと言ったところから来ているようです。
参考 : [README](https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin) 
::: 


### ◇ `UnityPluginLoad` と `UnityPluginUnload` の実装

サンプルプロジェクトからコードを抜粋すると、`ObjC` 側で実装している以下の関数が後述する登録手順を踏むことによって Unity から呼び出される様になるので、この関数を経由して以下のインターフェースを取得します。  

- `IUnityInterfaces`
    - こちらのインタフェース経由で次の物が取得可能
- `IUnityGraphics`
    - こちら経由でグラフィックドライバからの各種イベントを受けるためのコールバックを登録することが可能
- `IUnityGraphicsMetalV1`
    - **Unityが持つ MetalAPI へのアクセスするためのインターフェース**
        - ある意味この記事で解説する内容の要

```objc:UnityPluginRegister.m
#include "Unity/IUnityInterface.h"
#include "Unity/IUnityGraphics.h"
#include "Unity/IUnityGraphicsMetal.h"

static IUnityInterfaces* g_UnityInterfaces = 0;
static IUnityGraphics* g_Graphics = 0;

// NOTE: `IUnityGraphicsMetal` と `IUnityGraphicsMetalV1` の2つあるが、2017.4からは後者に切り替わっているとのこと
static IUnityGraphicsMetalV1* g_MetalGraphics = 0;


// プラグインのロードイベント
// NOTE: iOSの場合には一手間加えないと自動で呼び出されないので注意
void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* unityInterfaces) {
    g_UnityInterfaces = unityInterfaces;
    g_Graphics = UNITY_GET_INTERFACE(g_UnityInterfaces, IUnityGraphics);
    g_MetalGraphics = UNITY_GET_INTERFACE(g_UnityInterfaces, IUnityGraphicsMetalV1);

    // IUnityGraphics にイベントを登録
    // NOTE: kUnityGfxDeviceEventInitialize の後にプラグインのロードを受けるので、コールバックは手動で行う必要があるとのこと
    g_Graphics->RegisterDeviceEventCallback(OnGraphicsDeviceEvent);
    OnGraphicsDeviceEvent(kUnityGfxDeviceEventInitialize);
}

// プラグインのアンロードイベント
// NOTE: iOSの場合には一手間加えないと自動で呼び出されないので注意
void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload() {
    g_Graphics->UnregisterDeviceEventCallback(OnGraphicsDeviceEvent);
}

```

#### ◆ `RegisterDeviceEventCallback`に登録することでUnity側のグラフィックスに関するイベントを受け取れるようにする

イベント経由で受け取った `IUnityInterfaces` から `IUnityGraphics` を取得し、更にそこから`RegisterDeviceEventCallback`と言う関数を経由してコールバックを登録することで、**Unity 側のグラフィックスに関するイベントを受け取れるようになります。**

```objc:UnityPluginRegister.m
void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* unityInterfaces) {
    // 中略

    // IUnityGraphics にイベントを登録
    g_Graphics->RegisterDeviceEventCallback(OnGraphicsDeviceEvent);
    OnGraphicsDeviceEvent(kUnityGfxDeviceEventInitialize);
}
```

例えば 「`kUnityGfxDeviceEventInitialize` のタイミングで各種初期化処理を呼び出す」と言ったことが可能となり、サンプルプロジェクトではこのタイミングで `onUnityGfxDeviceEventInitialize` と言うプラグインの初期化関数を呼び出すようにしてます。

```objc:UnityPluginRegister.m
// `g_Graphics->RegisterDeviceEventCallback` で登録する関数
// NOTE: イベントの各定義は `IUnityGraphics.h` を参照
static void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType) {
    switch (eventType) {
        case kUnityGfxDeviceEventInitialize:
            // `g_Graphics->GetRenderer()` からは実行しているプラットフォームの GraphicsAPIを取得可能
            // 今回は Metal 限定なのでassertを貼ってその旨を明示的にしている
            assert(g_Graphics->GetRenderer() == kUnityGfxRendererMetal);

            // TODO: 各種初期化処理など

            // サンプルプロジェクトではここでプラグインの初期化関数を呼び出している
            onUnityGfxDeviceEventInitialize();
            break;
        case kUnityGfxDeviceEventShutdown:
            assert(g_Graphics->GetRenderer() == kUnityGfxRendererMetal);

            // TODO: 各種破棄時の処理などを実装

            break;
        default:
            // ignore others
            break;
    }
}
```


ちなみに `kUnityGfxDeviceEventInitialize` や `kUnityGfxRendererMetal` などの定義は `IUnityGraphics.h` と言うソースコードに定義されます。

::: note
**NOTE: `IUnityGraphics.h`とかはどこにあるのか？**

`IUnityGraphics.h` と言ったコードは Unity が iOS ビルド時に出力する `xcodeproj` の中に含まれており、今回関連する以下のソース含めて `(ビルドの出力先)/Classes/Unity` の下にファイルがあります。
 
- `IUnityInterface.h`
- `IUnityGraphics.h`
- `IUnityGraphicsMetal.h`
:::

#### ◆ `IUnityGraphicsMetalV1` について

上述の手順で手に入る `IUnityGraphicsMetalV1` についても先に軽く触れておきます。

`IUnityGraphicsMetalV1` は `IUnityGraphicsMetal.h` にて宣言されており、一部機能を抜粋すると恐らくは `Metal` に触れたことがある方なら目にしたことがあるであろうAPIが提供されてます。


```objc:IUnityGraphicsMetal.h
UNITY_DECLARE_INTERFACE(IUnityGraphicsMetalV1)
{
    // 中略

    NSBundle* (UNITY_INTERFACE_API * MetalBundle)();
    
    id<MTLDevice>(UNITY_INTERFACE_API * MetalDevice)();

    id<MTLCommandBuffer>(UNITY_INTERFACE_API * CurrentCommandBuffer)();

    // for custom rendering support there are two scenarios:
    // you want to use current in-flight MTLCommandEncoder (NB: it might be nil)
    id<MTLCommandEncoder>(UNITY_INTERFACE_API * CurrentCommandEncoder)();
    
    // or you might want to create your own encoder.
    // In that case you should end unity's encoder before creating your own and end yours before returning control to unity
    void(UNITY_INTERFACE_API * EndCurrentCommandEncoder)();

    // returns MTLRenderPassDescriptor used to create current MTLCommandEncoder
    MTLRenderPassDescriptor* (UNITY_INTERFACE_API * CurrentRenderPassDescriptor)();

    // 中略
};
UNITY_REGISTER_INTERFACE_GUID(0x29F8F3D03833465EULL, 0x92138551C15D823DULL, IUnityGraphicsMetalV1)
```

他にも iOS 限定にはなりますが、[RenderBuffer.GetNativeRenderBufferPtr](https://docs.unity3d.com/ScriptReference/RenderBuffer.GetNativeRenderBufferPtr.html) と言うAPIで得られるポインタを `MTLTexture` に変換して返す機能も備わってます。

```objc:IUnityGraphicsMetal.h
    // access to RenderBuffer's texure
    // NB: you pass here *native* RenderBuffer, acquired by calling (C#) RenderBuffer.GetNativeRenderBufferPtr
    // AAResolvedTextureFromRenderBuffer will return nil in case of non-AA RenderBuffer or if called for depth RenderBuffer
    // StencilTextureFromRenderBuffer will return nil in case of no-stencil RenderBuffer or if called for color RenderBuffer
    id<MTLTexture>(UNITY_INTERFACE_API * TextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * AAResolvedTextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * StencilTextureFromRenderBuffer)(UnityRenderBuffer buffer);
```

コード全体については以下を御覧ください。

<details><summary>コード全体はこちら (クリックで展開)</summary><div>

```objc:IUnityGraphicsMetal.h
// Unity Native Plugin API copyright © 2015 Unity Technologies ApS
//
// Licensed under the Unity Companion License for Unity - dependent projects--see[Unity Companion License](http://www.unity3d.com/legal/licenses/Unity_Companion_License).
//
// Unless expressly provided otherwise, the Software under this license is made available strictly on an “AS IS” BASIS WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.Please review the license for details on these and other terms and conditions.

#pragma once
#include "IUnityInterface.h"

#ifndef __OBJC__
    #error metal plugin is objc code.
#endif
#ifndef __clang__
    #error only clang compiler is supported.
#endif

@class NSBundle;
@protocol MTLDevice;
@protocol MTLCommandBuffer;
@protocol MTLCommandEncoder;
@protocol MTLTexture;
@class MTLRenderPassDescriptor;


UNITY_DECLARE_INTERFACE(IUnityGraphicsMetalV1)
{
    NSBundle* (UNITY_INTERFACE_API * MetalBundle)();
    id<MTLDevice>(UNITY_INTERFACE_API * MetalDevice)();

    id<MTLCommandBuffer>(UNITY_INTERFACE_API * CurrentCommandBuffer)();

    // for custom rendering support there are two scenarios:
    // you want to use current in-flight MTLCommandEncoder (NB: it might be nil)
    id<MTLCommandEncoder>(UNITY_INTERFACE_API * CurrentCommandEncoder)();
    // or you might want to create your own encoder.
    // In that case you should end unity's encoder before creating your own and end yours before returning control to unity
    void(UNITY_INTERFACE_API * EndCurrentCommandEncoder)();

    // returns MTLRenderPassDescriptor used to create current MTLCommandEncoder
    MTLRenderPassDescriptor* (UNITY_INTERFACE_API * CurrentRenderPassDescriptor)();

    // converting trampoline UnityRenderBufferHandle into native RenderBuffer
    UnityRenderBuffer(UNITY_INTERFACE_API * RenderBufferFromHandle)(void* bufferHandle);

    // access to RenderBuffer's texure
    // NB: you pass here *native* RenderBuffer, acquired by calling (C#) RenderBuffer.GetNativeRenderBufferPtr
    // AAResolvedTextureFromRenderBuffer will return nil in case of non-AA RenderBuffer or if called for depth RenderBuffer
    // StencilTextureFromRenderBuffer will return nil in case of no-stencil RenderBuffer or if called for color RenderBuffer
    id<MTLTexture>(UNITY_INTERFACE_API * TextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * AAResolvedTextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * StencilTextureFromRenderBuffer)(UnityRenderBuffer buffer);
};
UNITY_REGISTER_INTERFACE_GUID(0x29F8F3D03833465EULL, 0x92138551C15D823DULL, IUnityGraphicsMetalV1)


// deprecated: please use versioned interface above

UNITY_DECLARE_INTERFACE(IUnityGraphicsMetal)
{
    NSBundle* (UNITY_INTERFACE_API * MetalBundle)();
    id<MTLDevice>(UNITY_INTERFACE_API * MetalDevice)();

    id<MTLCommandBuffer>(UNITY_INTERFACE_API * CurrentCommandBuffer)();
    id<MTLCommandEncoder>(UNITY_INTERFACE_API * CurrentCommandEncoder)();
    void(UNITY_INTERFACE_API * EndCurrentCommandEncoder)();
    MTLRenderPassDescriptor* (UNITY_INTERFACE_API * CurrentRenderPassDescriptor)();

    UnityRenderBuffer(UNITY_INTERFACE_API * RenderBufferFromHandle)(void* bufferHandle);

    id<MTLTexture>(UNITY_INTERFACE_API * TextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * AAResolvedTextureFromRenderBuffer)(UnityRenderBuffer buffer);
    id<MTLTexture>(UNITY_INTERFACE_API * StencilTextureFromRenderBuffer)(UnityRenderBuffer buffer);
};
UNITY_REGISTER_INTERFACE_GUID(0x992C8EAEA95811E5ULL, 0x9A62C4B5B9876117ULL, IUnityGraphicsMetal)
```

</div></details>




### ◇ iOSの場合には `UnityAppController` のサブクラスを定義し、`shouldAttachRenderDelegate` をオーバーライドして登録を行う

前述したとおり、**iOS 環境の場合には特定の手順を踏まないと`UnityPluginLoad` と `UnityPluginUnload` が呼び出されません。**

こちらを呼び出すには、以下のように **`UnityAppController` のサブクラスを定義し、更に `shouldAttachRenderDelegate` をオーバーライドして手動で `UnityPluginLoad` と `UnityPluginUnload` を登録する必要があります。**

```objc:UnityPluginRegister.m
// MARK:- UnityPluginLoad と UnityPluginUnload の登録 (iOSのみ)

// Unityが UnityAppController と言う UIApplicationDelegate の実装クラスを持っているので、
// メンバ関数である shouldAttachRenderDelegate をオーバーライドすることで登録を行う必要がある。
@interface MyAppController : UnityAppController {
}
- (void)shouldAttachRenderDelegate;
@end

@implementation MyAppController

- (void)shouldAttachRenderDelegate {
    // NOTE: iOSはデスクトップとは違い、自動的にロードされて登録されないので手動で行う必要がある。
    UnityRegisterRenderingPluginV5(&UnityPluginLoad, &UnityPluginUnload);
}
@end
```

**その上で定義したクラスは `IMPL_APP_CONTROLLER_SUBCLASS` と言うマクロを経由することで Unity に登録する必要があります。**

```objc:UnityPluginRegister.m
// 定義したサブクラスはこちらのマクロを経由して登録する必要がある
IMPL_APP_CONTROLLER_SUBCLASS(MyAppController);
```

<details><summary>補足: IMPL_APP_CONTROLLER_SUBCLASS が何をやっているのか？について (クリックで展開)</summary><div>

こちらのマクロは何をやっているのかと言うと、実態はとしては `UnityAppController.h` にて定義されており、コードを読んだ感じだと `AppControllerClassName` に対して名前を書き換えることで `main.mm` でインスタンス化するクラス名を変えているようでした。

```objec:UnityAppController.h
// Put this into mm file with your subclass implementation
// pass subclass name to define

#define IMPL_APP_CONTROLLER_SUBCLASS(ClassName) \
@interface ClassName(OverrideAppDelegate)       \
{                                               \
}                                               \
+(void)load;                                    \
@end                                            \
@implementation ClassName(OverrideAppDelegate)  \
+(void)load                                     \
{                                               \
    extern const char* AppControllerClassName;  \
    AppControllerClassName = #ClassName;        \
}                                               \
@end                                            \
```

こちらの実装については `main.mm` の内容も合わせてみると分かりやすいかもしれません。

```objc:main.mm
// WARNING: this MUST be c decl (NSString ctor will be called after +load, so we cant really change its value)
const char* AppControllerClassName = "UnityAppController";

- (void)runUIApplicationMainWithArgc:(int)argc argv:(char*[])argv
{
    self->runCount += 1;
    [self frameworkWarmup: argc argv: argv];
    UIApplicationMain(argc, argv, nil, [NSString stringWithUTF8String: AppControllerClassName]);
}
```

</div></details>


## レンダースレッドからの任意のレンダリングメソッドを呼び出すには

ここまで準備できたら `IUnityGraphicsMetalV1` を用いて実際に Metal API を叩くレンダリングメソッドを実装するだけですが、これらの処理はレンダースレッドから呼び出す必要があります。

Unity iOS は初期設定だと `Multithread Rendering` が有効になっており、この場合にはレンダリング関連の処理が `MonoBehaviour` などが実行されるメインスレッドとは **別のスレッド(レンダースレッド)で実行されることになります。**

この状態でメインスレッドから描画関連の処理を呼び出すのは都合が悪いので、今回のようにレンダースレッド上で任意のレンダリングに関する処理を呼び出したい場合には `GL.IssuePlugimEvent` と言うAPIを経由して呼び出す必要があります。

https://docs.unity3d.com/ScriptReference/GL.IssuePluginEvent.html

これだけだと少し分かりづらいかもなので、実装例と併せて解説していきます。

### ◇ C# 側からレンダースレッドから呼び出したいメソッドをイベント経由でコール

先ずは C# のコードを載せます。

ここでは以下のタイミングで `GL.IssuePlugimEvent` を呼び出しており、タイミングに応じて引数に int型 の `eventType` を渡してます。(渡すのは int型 ではあるが、 C# 上では便宜的に enum型 として定義)

- **`RenderMethod1`**
    - `OnPostRender()` が呼び出されるタイミング
- **`RenderMethod2`**
    - `WaitForEndOfFrame` で待ってレンダリングが完了したタイミング

**引数として渡した `eventType` はネイティブコード側で呼び出されたイベントを判別する際に利用します。**

```csharp
sealed class Sample : MonoBehaviour
{
    private void OnPostRender()
    {
        CallRenderEventFunc(EventType.RenderMethod1);
        StartCoroutine(OnFrameEnd());
    }

    private IEnumerator OnFrameEnd()
    {
        yield return new WaitForEndOfFrame();
        CallRenderEventFunc(EventType.RenderMethod2);
        yield return null;
    }

    private enum EventType
    {
        // `OnPostRender()` が呼び出されるタイミング
        RenderMethod1 = 0,
        
        // `WaitForEndOfFrame` で待ってレンダリングが完了したタイミング
        RenderMethod2,
    }

    // 後述
    private static void CallRenderEventFunc(EventType eventType)
    {
        // ネイティブコードにある `getRenderEventFunc` と言う関数に対する P/Invoke
        // NOTE: 戻り値は呼び出すイベントの「関数ポインタ」
        [DllImport("__Internal", EntryPoint = "getRenderEventFunc")]
        static extern IntPtr GetRenderEventFunc();

        GL.IssuePluginEvent(GetRenderEventFunc(), (int)eventType);
    }
}
```

:::note info
ちなみに C# 8.0 からは**静的ローカル関数**が定義可能であり、更にC# 9.0からは**ローカル関数へ属性を適用**する事ができるようになりました。

今回は Unity 2022.2.0f1 を導入していることもあり、C# 9.0 が使えるので **P/Invoke のコードを上述のようにローカルメソッド内で完結させることが可能となります。**
:::


### ◇ ネイティブコード側の実装

C#側で `GL.IssuePluginEvent` を呼び出すと、第一引数に渡している `getRenderEventFunc` が P/Invoke 経由で呼び出され、**更にそこで返している関数ポインタの先である `OnRenderEvent(int eventID)` がレンダースレッドから呼び出されます。**

`OnRenderEvent` の引数には C# から渡した int型 の `eventType` が渡ってくるので、こちらを見る形でどのイベントが呼ばれたかを分岐してます。

**あとは渡ってきたイベントを元に任意のレンダリングメソッドを呼び出すことで実装していくことが可能です。**

```objc
// C# 側にある `enum EventType` と同じ定義を用意
enum EventType {
    RenderMethod1 = 0,
    RenderMethod2,
};

// GL.IssuePluginEvent に渡すコールバック関数のポインタを返す
// NOTE: `GL.IssuePluginEvent` の第一引数に渡されているのはこちら(の関数ポインタ)
UnityRenderingEvent UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API getRenderEventFunc() {
    return OnRenderEvent;
}

// Unity側で `GL.IssuePluginEvent` を呼ぶとレンダリングスレッドから呼ばれる
// NOTE: この関数はSwift側で持つことも可能だが、ここでは解説用にObjC側で持っている (詳しくは後述)
static void UNITY_INTERFACE_API OnRenderEvent(int eventID) {
    switch (eventID) {
        case RenderMethod1:

            // TODO: 
            // C# から `CallRenderEventFunc(EventType.RenderMethod1)` が呼ばれたときに実行されるレンダリングメソッドを呼び出す      

            break;
        case RenderMethod2:

            // TODO:
            // C# から `CallRenderEventFunc(EventType.RenderMethod2)` が呼ばれたときに実行されるレンダリングメソッドを呼び出す

            break;
    }
}
```

`eventType` 自体は int型 ではあるものの、今回のように互いに enum型 で定義しておくと可読性的にも分かりやすくなるかと思われるのでオススメです。



## Swiftで実装していくにあたっての補足

ここからは更に一部の処理を Swift の実装に移行し、**レンダリングに関する処理を Swift だけで実装できるように設定していく手順について解説していきます。**
(ObjC だけで実装/保守したい方は読み飛ばしても問題ありません)

### ◇ `OnRenderEvent` を Swiftに移行する

ObjC にある以下の `OnRenderEvent` は Swift に移行することが可能です。

```objc
// Unity側で `GL.IssuePluginEvent` を呼ぶとレンダリングスレッドから呼ばれる
static void UNITY_INTERFACE_API OnRenderEvent(int eventID) {
    switch (eventID) {
        case RenderMethod1:

            // TODO: 
            // C# から `CallRenderEventFunc(EventType.RenderMethod1)` が呼ばれたときに実行されるレンダリングメソッドを呼び出す      

            break;
        case RenderMethod2:

            // TODO:
            // C# から `CallRenderEventFunc(EventType.RenderMethod2)` が呼ばれたときに実行されるレンダリングメソッドを呼び出す

            break;
    }
}
```

具体的に言うと先ずは ObjC コードを以下のように変更します。

P/Invoke から呼び出される `getRenderEventFunc` はマクロの都合上、実装を ObjC 側で持つ必要はあります[^2]が、**そこで返す関数自体は外部宣言した関数を経由することで Swift 側に実装を持っていくことが可能です。**

[^2]: ひょっとしたらこちらも Swift 実装に持っていく手法が無きにしもあらずかもですが...マクロ周りの解決方法が分からなかったので断念... (分かる方が居たら教えて頂けると幸いです)

```objc
// ここでは外部宣言だけ (実装は Swift 側で行う)
extern void onRenderEvent();

// GL.IssuePluginEvent で登録するコールバック関数のポインタを返す
UnityRenderingEvent UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API getRenderEventFunc() {
    // Swift側で実装している`onRenderEvent`を返す
    return onRenderEvent;
}
```

Swift 側では「Cの関数」として定義するために `@_cdecl` を用いる必要があります。

```swift
enum EventType: Int32 {
    case renderMethod1 = 0
    case renderMethod2 = 1
}

// ObjC 側で外部宣言した関数は `@_cdecl` を用いて「Cの関数」として実装することで持っていくことが可能
@_cdecl("onRenderEvent")
func onRenderEvent(eventID: Int32) {
    switch EventType(rawValue: eventType)! {
    case .renderMethod1:
        break
    case .renderMethod2:
        break
    }
}
```


### ◇ Swift から `IUnityGraphicsMetalV1` にアクセスできるようにする

「これであとは Swift だけで実装できる！」と思いきや、 **現状のままだと Swift から `IUnityGraphicsMetalV1` にアクセスすることができません。**

肝心の GraphicsAPI にアクセスできないのでは意味がないので解決していきます。


#### ◆ `UnityFramework.h` を書き換えて `IUnityGraphicsMetalV1` を取得するためのクラスを追加する

先ずは Swift から `IUnityGraphicsMetalV1` を取得するためのクラスを用意していきます。

Swift から ObjC にアクセスするには `Umbrella header` [^3]に該当する `UnityFramework.h` に対して必要な機能を持たせる必要があるので、 **今回は以下のように`IUnityGraphicsMetalV1` を取得するためのクラスを追加します。**

[^3]: `Umbrella header` とは Xcode が Framework を作成した際に自動で生成してくれるファイルであり、Unityが出力する `xcodeproj` では `UnityFramework.h` が該当します。もう少し詳細について解説すると、こちらに Framework で使われる各種ヘッダーなどを含むことによって、実際に Framework を組み込む側が `Umbrella header` をインクルードするだけで `Framework` の全機能にアクセスできるようになると言う仕組みになります。(若干解説に自信ないので間違ってたら教えて下さい...)

```objc:UnityFramework.h
// こちらを追加
#import "IUnityGraphicsMetal.h"

(中略)

/// Swiftに `IUnityGraphicsMetalV1` を渡すためのブリッジ
///
/// NOTE:
/// Swiftからは「Low-level native plug-in interface」から受け取った
/// `IUnityGraphicsMetalV1`に対して直接アクセスする術が無いので、
/// こちらのクラスを介して構造体のポインタを渡す形を取っている。
///
/// そのため、前提としてUnityがiOSビルド時に出力するソースの中で、
/// 以下のヘッダーファイルについては Target Membership を事前に「public」に設定しておく必要がある。
/// - IUnityInterface.h
/// - IUnityGraphics.h
/// - IUnityGraphicsMetal.h
__attribute__ ((visibility("default")))
@interface UnityGraphicsBridge : NSObject {
}
+ (IUnityGraphicsMetalV1*)getUnityGraphicsMetalV1;
@end
```

ここではアクセス用のクラスとして、新規で `UnityGraphicsBridge` を宣言してます。

::: note
この対応内容は恐らくは `Unity as a Library (UaaL)` が公式サポートされ始めた Unity2019.3 前後で変わってくるかと思われます。

詳細について詳しく解説すると脱線するので割愛しますが、 `UnityFramework` への分割は UaaL が対応されてからの話なので、恐らくは `2019.3` より前のUnityは別の解決方法を取る必要があるかもです。
(未調査ですが、恐らくは `Bridging Header` で import を行う辺りの対応が必要だと予想)
:::

#### ◆ Swift に公開する必要があるヘッダーファイルを公開設定に変更

上記のコードのままだと `UnityFramework` から `IUnityGraphicsMetalV1` や、関連する定義が含まれているヘッダーファイルにアクセスできずにコンパイルエラーが発生します。

```objc:UnityFramework.h
// 設定を行わないと、ここでコンパイルエラーが発生
#import "IUnityGraphicsMetal.h"
```

これらを解決するには上に挙げた定義などが含まれている **以下のヘッダーファイルのアクセス権限を変更して `UnityFramework` からも見えるようにする必要があります。**

- `IUnityInterface.h`
- `IUnityGraphics.h`
- `IUnityGraphicsMetal.h`

Xcode 上からこの設定を行うには、該当するヘッダーファイルを選択し、以下画像の右の枠にある箇所 (`Target Membership`)の情報を `Public` に変更することで対応可能です。

![スクリーンショット 2022-12-18 8.53.48.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/80207/a33bb4d2-4359-19d1-bdf5-2f0c934dbdad.png)

ただ...ビルド時にいちいち手動で書き換えるのはスマートではないので、**最後に Editor 拡張で設定を自動化したコードを解説します。**


#### ◆ `UnityFramework.h` で宣言した `UnityGraphicsBridge` を実装する

`LLNPI` に関する処理を実装した `IUnityGraphicsMetalV1` のポインタを持つコード側で `UnityGraphicsBridge` を実装することで `IUnityGraphicsMetalV1` をそのまま返せるようにします。

サンプルコードでは `UnityPluginRegister.m` にて実装を行ってます。

```objc:UnityPluginRegister.m
// MARK:- UnityGraphicsBridgeの実装

// NOTE:
// - Swiftからアクセスしたいので、@interface の宣言は UmbrellaHeaderである `UnityFramework.h` にある

@implementation UnityGraphicsBridge {
}
+ (IUnityGraphicsMetalV1*)getUnityGraphicsMetalV1 {
    // LLNPI から得た `IUnityGraphicsMetalV1` のポインタをただ返すだけ
    return g_MetalGraphics;
}
@end
```

あとは Swift からは `UnityGraphicsBridge` から得られるポインタを経由することで、インスタンスにアクセスすることが出来るようになります。

```swift
@_cdecl("onRenderEvent")
func onRenderEvent(eventID: Int32) {

    // ポインタ経由でインスタンスを取得
    let unityMetal = UnityGraphicsBridge.getUnityGraphicsMetalV1().pointee
    
    // `MetalDevice()` からは `MTLDevice` を得られるので出力
    print(unityMetal.MetalDevice())

    switch EventType(rawValue: eventType)! {
    case .renderMethod1:
        break
    case .renderMethod2:
        break
    }
}
```

#### ◆ ここまでの手順を自動化する

`UnityFramework.h`を書き換えたり、一部のヘッダーファイルのアクセス権限を変更したりとしましたが、**最後にこれらの設定を全て Editor 拡張で自動化します。**
(やり方はいつもの？ `[PostProcessBuild]` を用いた `PBXProject` の書き換えです。[詳しくはこちら](https://qiita.com/mao_/items/c678f93ee04608492788))

コード全般は以下を御覧ください。

<details><summary>コード全体はこちら (クリックで展開)</summary><div>

```csharp:XcodePostProcess.cs
#if UNITY_IOS
using System.IO;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;
using UnityEngine;

namespace LLNPISample.Plugins.LLNPIWithMetal.Editor
{
    internal static class XcodePostProcess
    {
        [PostProcessBuild]
        private static void OnPostProcessBuild(BuildTarget target, string xcodeprojPath)
        {
            if (target != BuildTarget.iOS) return;

            var pbxProjectPath = PBXProject.GetPBXProjectPath(xcodeprojPath);
            var pbxProject = new PBXProject();
            pbxProject.ReadFromString(File.ReadAllText(pbxProjectPath));

            ReplaceNativeSources(xcodeprojPath);
            SetPublicHeader(ref pbxProject);

            File.WriteAllText(pbxProjectPath, pbxProject.WriteToString());
        }

        private static void ReplaceNativeSources(string xcodeprojPath)
        {
            // iOSビルド結果にある`UnityFramework.h`を改造済みのソースに差し替える
            const string headerFile = "UnityFramework.h";
            const string replaceHeaderPath = "/LLNPISample/Plugins/LLNPIWithMetal/Native/.ReplaceSources/" + headerFile;
            const string nativePath = "/UnityFramework/" + headerFile;

            var srcPath = Application.dataPath + replaceHeaderPath;
            var dstPath = xcodeprojPath + nativePath;
            File.Copy(srcPath, dstPath, true);
        }

        private static void SetPublicHeader(ref PBXProject pbxProject)
        {
            // iOSビルド結果にある以下のヘッダーはpublicとして設定し直す
            const string sourcesDirectory = "Classes/Unity/";
            var sources = new[]
            {
                "IUnityInterface.h",
                "IUnityGraphicsMetal.h",
                "IUnityGraphics.h",
            };

            var frameworkGuid = pbxProject.GetUnityFrameworkTargetGuid();
            foreach (var source in sources)
            {
                var sourceGuid = pbxProject.FindFileGuidByProjectPath(sourcesDirectory + source);
                pbxProject.AddPublicHeaderToBuild(frameworkGuid, sourceGuid);
            }
        }
    }
}

#endif
```

</div></details>

:::note alert
上記の例では `UnityFramework.h` を `[PostProcessBuild]` のタイミングで**事前に編集したソースコードと差し替える**と言う**ちょっとした黒魔術**を詠唱することでで問題を解決してますが、`UnityFramework.h` を含めた Unity が iOS ビルドで出力するコード全般は、 **Unity のバージョンアップによって内容が暗黙的に変わる可能性があるため、その点だけ念頭に置いておく必要があります。**
(例えば Unity のバージョンを上げた際に差し替え元のコードに変更が走っていると、差し替えた際にコードが古くてエラーが起こる可能性がある)
:::





# サンプルプロジェクトをベースに実装内容の解説

ここからは今回自分の方で再実装したプロジェクトをベースに解説していきます。

https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples

先ずは Unity(C#) 側で何をやっているのか？だけ先にサラッと解説し、次にネイティブ側の実装詳細について解説していきます。


## Unity 側の実装

Unity 側では以下のようなCube2つが回転するだけのシーンを用意し、こちらのレンダリングをネイティブで加工できるようにしていきます。

![20221218_190226.GIF](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/80207/3664ae1b-2493-0e6f-d1fd-4df75a3a5ad3.gif)

### ◇ `Camera` にアタッチされたスクリプトを起点に `OnPostRender()` からレンダースレッド上で実行されるメソッドを呼び出す

シーン上の `Camera` には以下の `Sample` をアタッチしており、**こちらから呼ばれる `OnPostRender()` を起点にレンダースレッド上で実行されるメソッドを呼び出していきます。**

ちなみにネイティブコードの呼び出しは[こちらに記載している作法](https://qiita.com/mao_/items/15d05d25a99ab290fa50)に倣って `interface` で実装を分けてますが、 Editor 実行時に入る `NativeProxyForEditor` は基本的にはエラー回避用のダミーだと思ってしまって問題ありません。

```csharp:Sample.cs
[RequireComponent(typeof(Camera))]
internal sealed class Sample : MonoBehaviour
{
    private Camera _targetCamera;
    private INativeProxy _nativeProxy;

    private void Awake()
    {
        TryGetComponent(out _targetCamera);
        Assert.IsTrue(_targetCamera != null);

#if UNITY_EDITOR
        _nativeProxy = new NativeProxyForEditor();
#elif UNITY_IOS
        _nativeProxy = new NativeProxyForIOS();
#endif
    }

    private void OnPostRender()
    {
        _nativeProxy.DoExtraDrawCall();
        StartCoroutine(OnFrameEnd());
    }

    private IEnumerator OnFrameEnd()
    {
        yield return new WaitForEndOfFrame();

        // Camera に targetTexture が存在するならそちらを使い、
        // そうじゃない場合には `Display.main.colorBuffer`を使う
        var srcRT = _targetCamera.targetTexture;
        var src = srcRT ? srcRT.colorBuffer : Display.main.colorBuffer;
        var dst = Display.main.colorBuffer;

        // こちらのイベントはUnityが実行する全てのレンダリングが完了した後に呼び出す必要がある。
        // (AAが関係している場合には特に重要であり、ネイティブ側でエンコーダーを終了することによってAAの解決が行われる)
        _nativeProxy.DoCopyRT(src, dst);
        yield return null;
    }
}
```

### ◇ ネイティブコードの呼び出し

まず前提として今回の実装で「レンダースレッド上から呼び出す想定のメソッド」の紹介からしていきます。

こちらは enum にて以下のように定義してます。

- `ExtraDrawCall`
    - 既存の描画をフックして描画を追加で差し込む例
    - `OnPostRender`のタイミングで呼び出す
    - 内容的には既存のレンダリングの上に赤い矩形を描画するだけ
- `CopyRTtoRT`
    - Unityのエンコーダーの終了を待った後に独自のエンコーダーを実行する例
    - `WaitForEndOfFrame` の後のタイミング(レンダリングが完了するタイミング)で呼び出す
    - 内容的には引数で渡した `src` を内部的なテクスチャ(バッファ)にコピーし、それを `dst` で渡されたバッファの上に描画する

実装内容はどれも[公式サンプル](https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin)と同じものですが、大凡の内容は把握できるかと思い、そのまま採用してます。

```csharp:NativeProxyForIOS.cs
/// <summary>
/// サンプルのレンダリングイベント
/// </summary>
private enum EventType
{
    /// <summary>
    /// Unityが持つレンダーターゲットに対して、追加で描画イベントの呼び出しを行う
    /// </summary>
    /// <remarks>Unityが実行する既存の描画をフックし、追加の描画を行うサンプル</remarks>
    ExtraDrawCall = 0,

    /// <summary>
    /// `src`を内部的なテクスチャにコピーし、それを`dst`上の矩形に対し描画する
    /// </summary>
    /// <remarks>独自のエンコーダーを実行する幾つかの例</remarks>
    CopyRTtoRT,
}
```

P/Invoke や [GL.IssuePluginEvent](https://docs.unity3d.com/ScriptReference/GL.IssuePluginEvent.html) 箇所は以下のようになってます。

今回は iOS オンリーの例と言うのもあり、ネイティブ側には前の章でも軽く話した [RenderBuffer.GetNativeRenderBufferPtr](https://docs.unity3d.com/ScriptReference/RenderBuffer.GetNativeRenderBufferPtr.html) で得られるポインタを渡すようにしてます。


```csharp:NativeProxyForIOS.cs
public sealed class NativeProxyForIOS : INativeProxy
{
    void INativeProxy.DoExtraDrawCall()
    {
        CallRenderEventFunc(EventType.ExtraDrawCall);
    }

    void INativeProxy.DoCopyRT(RenderBuffer src, RenderBuffer dst)
    {
        [DllImport("__Internal", EntryPoint = "setRTCopyTargets")]
        static extern void SetRTCopyTargets(IntPtr src, IntPtr dst);

        SetRTCopyTargets(src.GetNativeRenderBufferPtr(), dst.GetNativeRenderBufferPtr());
        CallRenderEventFunc(EventType.CopyRTtoRT);
    }

    private enum EventType { /* 中略 */ }

    private static void CallRenderEventFunc(EventType eventType)
    {
        [DllImport("__Internal", EntryPoint = "getRenderEventFunc")]
        static extern IntPtr GetRenderEventFunc();

        GL.IssuePluginEvent(GetRenderEventFunc(), (int)eventType);
    }
}
```

## ネイティブ側の実装

今回実装しているネイティブコードは以下のものがあります。

- [UnityPluginRegister.m](https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples/blob/main/UnityProjects/BuiltInRP/Assets/LLNPISample/Plugins/LLNPIWithMetal/Native/UnityPluginRegister.m)
    - 前の章で解説した `LLNPI` の周りの処理
- [NativeCallProxy.swift](https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples/blob/main/UnityProjects/BuiltInRP/Assets/LLNPISample/Plugins/LLNPIWithMetal/Native/NativeCallProxy.swift)
    - `LLNPI` 周りで呼び出される処理の一部や、 `LLNPI` に関わらない P/Invoke で呼び出される関数を定義
- [MetalPlugin.swift](https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples/blob/main/UnityProjects/BuiltInRP/Assets/LLNPISample/Plugins/LLNPIWithMetal/Native/MetalPlugin.swift)
    - 今回の実装のコアロジック
- [MetalShader.swift](https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples/blob/main/UnityProjects/BuiltInRP/Assets/LLNPISample/Plugins/LLNPIWithMetal/Native/MetalShader.swift)
    - シェーダーコード ( `Swift` のソースで持っている理由については後述)


前者2つについては前の章を読んでいれば大凡何をやっているのかは把握できる内容かと思います。
今回肝となるのはコアロジックを持つ `MetalPlugin.swift` の部分となるので、こちらを中心に解説していきます。

### ◇ プラグインの初期化

プラグインの初期化は `OnGraphicsDeviceEvent` から `kUnityGfxDeviceEventInitialize` を見る形で呼び出します。

```objc:UnityPluginRegister.m
// ここでは外部宣言だけ (実装は `NativeCallPloxy.swift` にある)
extern void onUnityGfxDeviceEventInitialize();

static void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType) {
    switch (eventType) {
        case kUnityGfxDeviceEventInitialize:
            assert(g_Graphics->GetRenderer() == kUnityGfxRendererMetal);
            
            // Swift 側で実装されている初期化処理を呼び出し
            onUnityGfxDeviceEventInitialize();
            break;
        case kUnityGfxDeviceEventShutdown:
            assert(g_Graphics->GetRenderer() == kUnityGfxRendererMetal);
            break;
        default:
            // ignore others
            break;
    }
}
```

この時点で `IUnityGraphicsMetalV1` は手に入っているので、こちらを取得して `MetalPlugin` のイニシャライザに渡して初期化を完了させます。

```swift:NativeCallPloxy.swift
/// NOTE: `OnGraphicsDeviceEvent -> kUnityGfxDeviceEventInitialize`のタイミングで呼び出される
@_cdecl("onUnityGfxDeviceEventInitialize")
func onUnityGfxDeviceEventInitialize() {
    let unityMetal = UnityGraphicsBridge.getUnityGraphicsMetalV1().pointee
    MetalPlugin.shared = MetalPlugin(with: unityMetal)
}
```

`MetalPlugin` のイニシャライザは長いので折りたたみますが、要約すると以下のことをやってます。

- `IUnityGraphicsMetalV1` から `MTLDevice`　を取得して保持
- シェーダーコードの読み込み
- レンダリングメソッドで描画する矩形オブジェクトの頂点情報の生成

<details><summary>イニシャライザのコード全体はこちら (クリックで展開)</summary><div>

```swift:MetalPlugin.swift
    init(with unityMetal: IUnityGraphicsMetalV1) {
        self.unityMetal = unityMetal

        guard let device: MTLDevice = unityMetal.MetalDevice() else {
            preconditionFailure("MTLDeviceが見つからない")
        }

        do {
            let library = try device.makeLibrary(source: Shader.shaderSrc, options: nil)
            guard let vertexShader = library.makeFunction(name: "vprog"),
                  let fragmentShaderColor = library.makeFunction(name: "fshader_color"),
                  let fragmentShaderTexture = library.makeFunction(name: "fshader_tex")
            else {
                preconditionFailure("シェーダーの読み込みで失敗")
            }

            self.vertexShader = vertexShader
            self.fragmentShaderColor = fragmentShaderColor
            self.fragmentShaderTexture = fragmentShaderTexture
        } catch let error {
            preconditionFailure(error.localizedDescription)
        }

        // pos.x pos.y uv.x uv.y
        let vertices: [Float] = [
            -1.0, 0.0, 0.0, 0.0,
            -1.0, -1.0, 0.0, 1.0,
            0.0, -1.0, 1.0, 1.0,
            0.0, 0.0, 1.0, 0.0,
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        let verticesLength = vertices.count * MemoryLayout<Float>.size
        let indicesLength = indices.count * MemoryLayout<UInt16>.size

        guard let verticesBuffer = device.makeBuffer(bytes: vertices, length: verticesLength, options: .cpuCacheModeWriteCombined),
              let indicesBuffer = device.makeBuffer(bytes: indices, length: indicesLength, options: .cpuCacheModeWriteCombined)
        else {
            preconditionFailure("バッファの生成に失敗")
        }

        self.verticesBuffer = verticesBuffer
        self.indicesBuffer = indicesBuffer

        let vertexAttributeDesc = MTLVertexAttributeDescriptor()
        vertexAttributeDesc.format = .float4

        let vertexBufferLayoutDesc = MTLVertexBufferLayoutDescriptor()
        vertexBufferLayoutDesc.stride = 4 * MemoryLayout<Float>.size
        vertexBufferLayoutDesc.stepFunction = .perVertex
        vertexBufferLayoutDesc.stepRate = 1

        vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0] = vertexAttributeDesc
        vertexDesc.layouts[0] = vertexBufferLayoutDesc
    }

```

</div></details>

:::note
**NOTE: シェーダーコードを文字列で持っている理由**

[MetalShader.swift](https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples/blob/main/UnityProjects/BuiltInRP/Assets/LLNPISample/Plugins/LLNPIWithMetal/Native/MetalShader.swift)を見たら分かる通り、今回のプロジェクトでは**シェーダーコードを文字列として持ってます。**

これだけ見ると普通に「 `.metal` で持って `makeDefaultLibrary()` で読み込めば良いのでは？」と思うかもしれませんが、今回は以下の理由から意図して `.metal` に持たずに文字列で持つようにしてます。

- `UniryFramework`を組み込む先を考えて `.metal` の配置を考える必要がある
    -  とは言え、普通に Unity が iOS ビルドで出力する `xcodeproj` でアプリをビルドするなら、 `.metal` を `Unity-iPhone` と言うターゲットに含めるようにすれば解決できる
    -  ただし UaaL とかを考え始めると面倒そう...
- そもそも Unity のプロジェクト上に `.metal` を配置しても自動で iOS ビルドに含めてくれない...
    - 自前で `.metal` をコピーして `xcodeproj` に含める拡張を実装する必要がある
- 実装しているシェーダーコードがシンプルだったのもあったので、費用対効果を考えると手間だった

**必ずしも文字列で持つのが正解では無いかと思われるので、プロジェクトの要件に応じて変えていくのが良いかと思います。**
(ちなみに[公式プロジェクト](https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin)の方も同じく文字列で持っている)
:::


### ◇ `ExtraDrawCall` の実装

> - `ExtraDrawCall`
>     - 既存の描画をフックして描画を追加で差し込む例
>     - `OnPostRender`のタイミングで呼び出す
>     - 内容的には既存のレンダリングの上に赤い矩形を描画するだけ

こちらの実装解説に入ります。
コード全体は以下を御覧ください。

<details><summary>コード全体 (クリックで展開)</summary><div>

```swift:MetalPlugin.swift
    // MARK:- ExtraDrawCall

    /// Unityが持つレンダーターゲットに対して、追加で描画イベントの呼び出しを行う
    ///
    /// NOTE:
    /// - ここでは現在のレンダリングをフックし、単色の矩形を追加描画する例
    private func extraDrawCall() {
        // 現在のレンダリング情報を取得
        guard let desc = unityMetal.CurrentRenderPassDescriptor(),
              let rt: MTLTexture = desc.colorAttachments[0].texture,
              let cmdEncoder: MTLCommandEncoder = unityMetal.CurrentCommandEncoder()
        else {
            preconditionFailure("レンダリング情報の取得に失敗")
        }

        // 現在のレンダーパスの設定を取得し、レンダーターゲットの形式に変更があったら PipelineState を再生成する
        if (rt.pixelFormat != extraDrawCallPixelFormat || rt.sampleCount != extraDrawCallSampleCount) {
            extraDrawCallPixelFormat = rt.pixelFormat
            extraDrawCallSampleCount = rt.sampleCount
            extraDrawCallPipelineState = createCommonRenderPipeline(
                label: "ExtraDrawCall",
                fragmentShader: fragmentShaderColor,
                format: extraDrawCallPixelFormat,
                sampleCount: extraDrawCallSampleCount)
        }

        guard let extraDrawCallPipelineState = extraDrawCallPipelineState,
              let renderCmdEncoder = cmdEncoder as? MTLRenderCommandEncoder
        else {
            preconditionFailure("PipelineState の取得に失敗、若しくはCommandEncoderの形式が不正")
        }

        renderCmdEncoder.setRenderPipelineState(extraDrawCallPipelineState)
        renderCmdEncoder.setCullMode(.none)
        renderCmdEncoder.setVertexBuffer(verticesBuffer, offset: 0, index: 0)
        renderCmdEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indicesBuffer,
            indexBufferOffset: 0)
    }
```

</div></details>

#### ◆ `IUnityGraphicsMetalV1` から現在のレンダリング情報を取得

こちらは `IUnityGraphicsMetalV1` から `CurrentRenderPassDescriptor()` と `CurrentCommandEncoder()` を呼び出すことで現在のレンダリング情報を取得してます。

```swift:MetalPlugin.swift
        // 現在のレンダリング情報を取得
        guard let desc = unityMetal.CurrentRenderPassDescriptor(),
              let rt: MTLTexture = desc.colorAttachments[0].texture,
              let cmdEncoder: MTLCommandEncoder = unityMetal.CurrentCommandEncoder()
        else {
            preconditionFailure("レンダリング情報の取得に失敗")
        }
```

参考程度に `IUnityGraphicsMetal.h` にある関数宣言の方も再度引用しておきます。

```objc:IUnityGraphicsMetal.h
    // you want to use current in-flight MTLCommandEncoder (NB: it might be nil)
    id<MTLCommandEncoder>(UNITY_INTERFACE_API * CurrentCommandEncoder)();

    // returns MTLRenderPassDescriptor used to create current MTLCommandEncoder
    MTLRenderPassDescriptor* (UNITY_INTERFACE_API * CurrentRenderPassDescriptor)();
```

#### ◆ `MTLRenderPipelineState` の生成

今回の例ではレンダーターゲットの変更に対応できるよう、都度変更を検知して生成するようにしてます。
とは言え、もしレンダーターゲットが固定であれば初期化時に生成して使い回すようにするのが正解かもしれません。

```swift:MetalPlugin.swift
        // 現在のレンダーパスの設定を取得し、レンダーターゲットの形式に変更があったら PipelineState を再生成する
        if (rt.pixelFormat != extraDrawCallPixelFormat || rt.sampleCount != extraDrawCallSampleCount) {
            extraDrawCallPixelFormat = rt.pixelFormat
            extraDrawCallSampleCount = rt.sampleCount
            extraDrawCallPipelineState = createCommonRenderPipeline(
                label: "ExtraDrawCall",
                fragmentShader: fragmentShaderColor,
                format: extraDrawCallPixelFormat,
                sampleCount: extraDrawCallSampleCount)
        }
```

#### ◆ `MTLRenderCommandEncoder` を取得して追加でプリミティブをレンダリング

`MTLRenderPipelineState` の生成まで完了したら、それを用いた描画処理を足していきます。

`IUnityGraphicsMetalV1` にある `CurrentCommandEncoder` から得られるエンコーダーを `MTLRenderCommandEncoder` にキャストし、**イニシャライザで事前に生成したシェーダーや頂点情報などを用いて矩形のプリミティブを描画します。**

```swift:MetalPlugin.swift
        guard let extraDrawCallPipelineState = extraDrawCallPipelineState,
              let renderCmdEncoder = cmdEncoder as? MTLRenderCommandEncoder
        else {
            preconditionFailure("PipelineState の取得に失敗、若しくはCommandEncoderの形式が不正")
        }

        renderCmdEncoder.setRenderPipelineState(extraDrawCallPipelineState)
        renderCmdEncoder.setCullMode(.none)
        renderCmdEncoder.setVertexBuffer(verticesBuffer, offset: 0, index: 0)
        renderCmdEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indicesBuffer,
            indexBufferOffset: 0)
```

正常に行けば恐らくは `Pipeline State` に `ExtraDrawCall` が追加され、以下のような表示になっているはずです。

![スクリーンショット 2022-12-18 21.13.41.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/80207/9fc4a73a-7f35-5f87-09c7-64849c99ec86.png)




### ◇ `CopyRTtoRT` の実装

> - `CopyRTtoRT`
>     - Unityのエンコーダーの終了を待った後に独自のエンコーダーを実行する例
>     - `WaitForEndOfFrame` の後のタイミング(レンダリングが完了するタイミング)で呼び出す
>     - 内容的には引数で渡した `src` を内部的なテクスチャ(バッファ)にコピーし、それを `dst` で渡されたバッファの上に描画する

最後にこちらの実装解説に入ります。
コード全体は以下を御覧ください。

<details><summary>コード全体 (クリックで展開)</summary><div>

```swift:MetalPlugin.swift
    // MARK:- CaptureRT

    /// `src`を内部的なテクスチャにコピーし、それを`dst`上の矩形に対し描画する
    ///
    /// NOTE:
    /// - Unityが実行するエンコーダーを完了させ、その後に独自のエンコーダーを実行する幾つかの例
    ///     - 1. `src` を `rtCopy` にコピー
    ///     - 2. `dst` 上に矩形を描画し、フラグメントシェーダーで `rtCopy` を描き込む
    private func captureRT() {
        if (copySrc == nil || copyDst == nil) {
            print("コピー対象のレンダーターゲットがまだ設定されていない");
            return
        }

        guard let device: MTLDevice = unityMetal.MetalDevice() else {
            preconditionFailure("MTLDeviceが見つからない")
        }

        // 独自のエンコーダーを作成する前に、Unityが持つエンコーダーを先に終了させる必要がある。
        // NOTE: ただし、これを行う場合にはUnityに制御を戻す前に自前で走らせたエンコーダーは終了させておく必要がある。
        unityMetal.EndCurrentCommandEncoder()

        // コピー対象のテクスチャを取得
        guard let copySrc = copySrc,
              let srcTexture: MTLTexture = getColorTexture(from: copySrc)
        else {
            preconditionFailure("コピー対象のテクスチャの取得に失敗")
        }

        // 必要に応じて `src` のコピー先を生成
        if rtCopy == nil ||
               rtCopy!.width != srcTexture.width ||
               rtCopy!.height != srcTexture.height ||
               rtCopy!.pixelFormat != srcTexture.pixelFormat {

            let texDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: srcTexture.pixelFormat,
                width: srcTexture.width,
                height: srcTexture.height,
                mipmapped: false)

            self.rtCopy = device.makeTexture(descriptor: texDesc)
        }

        guard let rtCopy = rtCopy else {
            preconditionFailure("コピー対象のテクスチャの生成に失敗している")
        }

        // BlitCommandEncoder を利用して `src` を `rtCopy` にコピーする
        if let cmdBuffer = unityMetal.CurrentCommandBuffer(),
           let blit = cmdBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: srcTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: srcTexture.width, height: srcTexture.height, depth: 1),
                to: rtCopy,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        } else {
            preconditionFailure("BlitCommandEncoder の実行に失敗")
        }

        // 書き込み先のテクスチャを取得
        guard let copyDst = copyDst,
              let dstTexture: MTLTexture = getColorTexture(from: copyDst)
        else {
            preconditionFailure("書き込み先のテクスチャの取得に失敗")
        }

        // NOTE: AAは既に解決済みであることを想定
        let colorAttachment = MTLRenderPassColorAttachmentDescriptor()
        colorAttachment.texture = dstTexture
        colorAttachment.loadAction = .load
        colorAttachment.storeAction = .store

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0] = colorAttachment

        // 書き込み先の設定を取得し、レンダーターゲットの形式に変更があったら PipelineState を再生成する
        if (dstTexture.pixelFormat != rtCopyPixelFormat || dstTexture.sampleCount != rtCopySampleCount) {
            rtCopyPixelFormat = dstTexture.pixelFormat
            rtCopySampleCount = dstTexture.sampleCount
            rtCopyPipelineState = createCommonRenderPipeline(
                label: "CaptureRT",
                fragmentShader: fragmentShaderTexture,
                format: rtCopyPixelFormat,
                sampleCount: rtCopySampleCount)
        }

        // RenderCommandEncoder を利用して `dst` 上に矩形を描画し、フラグメントシェーダーで`rtCopy`を描き込む
        if let cmdBuffer = unityMetal.CurrentCommandBuffer(),
           let cmd = cmdBuffer.makeRenderCommandEncoder(descriptor: desc),
           let rtCopyPipelineState = rtCopyPipelineState {
            cmd.setRenderPipelineState(rtCopyPipelineState)
            cmd.setCullMode(.none)
            cmd.setVertexBuffer(verticesBuffer, offset: 0, index: 0)
            cmd.setFragmentTexture(rtCopy, index: 0)
            cmd.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: indicesBuffer,
                indexBufferOffset: 0)
            cmd.endEncoding()
        } else {
            preconditionFailure("RenderCommandEncoder の実行に失敗")
        }
    }

    /// UnityRenderBuffer から MTLTexture を取得
    ///
    /// - Parameter renderBuffer: 対象の UnityRenderBuffer
    /// - Returns: 取得に成功した MTLTexture を返す (失敗時はnil)
    ///
    /// NOTE:
    /// - 渡すバッファの条件によって呼び出す関数が変わるので分岐を挟んでいる
    /// - 例えば前者の `AAResolvedTextureFromRenderBuffer` はAAが掛かっている必要がある
    ///     - 非AAのバッファやDepth形式のバッファを渡すとnilが返ってくるとのこと (詳しくは関数のコメント参照)
    private func getColorTexture(from renderBuffer: UnityRenderBuffer) -> MTLTexture? {
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
```

</div></details>

#### ◆ 先ずは Unity が持つエンコーダーを先に終了させる

コメントに書いてあるとおりですが、これから独自のエンコーダーを走らせていくので、その前に `EndCurrentCommandEncoder` を呼び出すことで Unity が持つエンコーダーを先に終了させておきます。

```swift:MetalPlugin.swift
        // 独自のエンコーダーを作成する前に、Unityが持つエンコーダーを先に終了させる必要がある。
        // NOTE: ただし、これを行う場合にはUnityに制御を戻す前に自前で走らせたエンコーダーは終了させておく必要がある。
        unityMetal.EndCurrentCommandEncoder()

```

こちらも参考程度に `IUnityGraphicsMetal.h` にある関数宣言の方も再度引用しておきます。

```objc:IUnityGraphicsMetal.h
    // or you might want to create your own encoder.
    // In that case you should end unity's encoder before creating your own and end yours before returning control to unity
    void(UNITY_INTERFACE_API * EndCurrentCommandEncoder)();
```

#### ◆ P/Invoke で `RenderBuffer` のポインタを Unity からネイティブに渡して保持

C# のコードに戻りますが、ここでは `DoCopyRT` を呼び出す際に `RenderBuffer` のポインタを P/Invoke でネイティブに渡してます。

```csharp:NativeProxyForIOS.cs
public sealed class NativeProxyForIOS : INativeProxy
{
    // (中略)

    void INativeProxy.DoCopyRT(RenderBuffer src, RenderBuffer dst)
    {
        [DllImport("__Internal", EntryPoint = "setRTCopyTargets")]
        static extern void SetRTCopyTargets(IntPtr src, IntPtr dst);

        SetRTCopyTargets(src.GetNativeRenderBufferPtr(), dst.GetNativeRenderBufferPtr());
        CallRenderEventFunc(EventType.CopyRTtoRT);
    }

    // (中略)
}
```

ここで渡されたポインタは Swift では以下のように受け取ることが出来るので、

```swift:NativeCallProxy.swift
// P/Invoke

@_cdecl("setRTCopyTargets")
func setRTCopyTargets(_ src: UnityRenderBuffer, _ dst: UnityRenderBuffer) {
    MetalPlugin.shared.setRTCopyTargets(src, dst)
}
```

それをフィールドに保持するようにします。

```swift:MetalPlugin.swift
    private var copySrc: UnityRenderBuffer? = nil
    private var copyDst: UnityRenderBuffer? = nil

    func setRTCopyTargets(_ src: UnityRenderBuffer, _ dst: UnityRenderBuffer) {
        copySrc = src
        copyDst = dst
    }
```

:::note
**NOTE: `UnityRenderBuffer` の型について**

`UnityRenderBuffer` の定義を見ると分かりますが、実態としてはただの**構造体のポインタ**でしか無いので、 P/Invoke の引数として普通に渡してネイティブ側で受け取ることが可能です。


```objc:IUnityInterface.h
struct RenderSurfaceBase;
typedef struct RenderSurfaceBase* UnityRenderBuffer;
typedef unsigned int UnityTextureID;
```

※ ちなみに「構造体のポインタ」である旨については [RenderBuffer.GetNativeRenderBufferPtr](https://docs.unity3d.com/ScriptReference/RenderBuffer.GetNativeRenderBufferPtr.html) のドキュメントの方にも記載されてます。
:::


#### ◆ `MTLBlitCommandEncoder` を利用して `src` をコピー

先ずは `copySrc` に保持している `RenderBuffer` を元に、 `getColorTexture` と言うメソッドから `MTLTexture` を取得します。

```swift:MetalPlugin.swift
    // コピー対象のテクスチャを取得
    guard let copySrc = self.copySrc,
          let srcTexture: MTLTexture = getColorTexture(from: copySrc)
    else {
        preconditionFailure("コピー対象のテクスチャの取得に失敗")
    }
```

以下の処理では取得した `srcTexture: MTLTexture` を元に `rtCopy` と言う `MTLTexture` を生成し、 **`BlitCommandEncoder` を走らせることで `srcTexture` の内容を `rtCopy` に書き込みます。**

```swift:MetalPlugin.swift
    // 必要に応じて `src` のコピー先を生成
    if self.rtCopy == nil ||
           self.rtCopy!.width != srcTexture.width ||
           self.rtCopy!.height != srcTexture.height ||
           self.rtCopy!.pixelFormat != srcTexture.pixelFormat {

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: srcTexture.pixelFormat,
            width: srcTexture.width,
            height: srcTexture.height,
            mipmapped: false)

        self.rtCopy = device.makeTexture(descriptor: texDesc)
    }

    guard let rtCopy = self.rtCopy else {
        preconditionFailure("コピー対象のテクスチャの生成に失敗している")
    }

    // BlitCommandEncoder を利用して `src` を `rtCopy` にコピーする
    if let cmdBuffer = unityMetal.CurrentCommandBuffer(),
       let blit = cmdBuffer.makeBlitCommandEncoder() {
        blit.copy(
            from: srcTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: srcTexture.width, height: srcTexture.height, depth: 1),
            to: rtCopy,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    } else {
        preconditionFailure("BlitCommandEncoder の実行に失敗")
    }
```

#### ◆ `RenderCommandEncoder` を利用して `dst` にコピーした内容を矩形として描き込む

こちらではコピー済みの `rtCopy` の内容を `RenderCommandEncoder` を用いて `dst` に書き込んでます。
詳細についてはコメントに記載しているのでこちらを御覧ください。

```swift:MetalPlugin.swift
    // 書き込み先のテクスチャを取得
    guard let copyDst = copyDst,
          let dstTexture: MTLTexture = getColorTexture(from: copyDst)
    else {
        preconditionFailure("書き込み先のテクスチャの取得に失敗")
    }

    // NOTE: AAは既に解決済みであることを想定
    let colorAttachment = MTLRenderPassColorAttachmentDescriptor()
    colorAttachment.texture = dstTexture
    colorAttachment.loadAction = .load
    colorAttachment.storeAction = .store

    let desc = MTLRenderPassDescriptor()
    desc.colorAttachments[0] = colorAttachment

    // 書き込み先の設定を取得し、レンダーターゲットの形式に変更があったら PipelineState を再生成する
    if (dstTexture.pixelFormat != rtCopyPixelFormat || dstTexture.sampleCount != rtCopySampleCount) {
        rtCopyPixelFormat = dstTexture.pixelFormat
        rtCopySampleCount = dstTexture.sampleCount
        rtCopyPipelineState = createCommonRenderPipeline(
            label: "CaptureRT",
            fragmentShader: fragmentShaderTexture,
            format: rtCopyPixelFormat,
            sampleCount: rtCopySampleCount)
    }

    // RenderCommandEncoder を利用して `dst` 上に矩形を描画し、フラグメントシェーダーで`rtCopy`を描き込む
    if let cmdBuffer = unityMetal.CurrentCommandBuffer(),
       let cmd = cmdBuffer.makeRenderCommandEncoder(descriptor: desc),
       let rtCopyPipelineState = rtCopyPipelineState {
        cmd.setRenderPipelineState(rtCopyPipelineState)
        cmd.setCullMode(.none)
        cmd.setVertexBuffer(verticesBuffer, offset: 0, index: 0)
        cmd.setFragmentTexture(rtCopy, index: 0)
        cmd.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indicesBuffer,
            indexBufferOffset: 0)
        cmd.endEncoding()
    } else {
        preconditionFailure("RenderCommandEncoder の実行に失敗")
    }
```

正常に行けば `Pipeline State` に `CaptureRT` が追加され、`ExtraDrawCall` と合わせて以下のような表示になっているはずです。

![スクリーンショット 2022-12-18 21.47.37.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/80207/74d28c9b-6bb7-493f-b9a4-f02d5dace35c.png)




# 次回予告

- URPでの導入
- MetalFX

# 参考/関連リンク

- [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html)

- [FrameworkでSwiftとObjective-C混ぜるのはやばい](https://qiita.com/fr0g_fr0g/items/82789af60b27ae19b263)