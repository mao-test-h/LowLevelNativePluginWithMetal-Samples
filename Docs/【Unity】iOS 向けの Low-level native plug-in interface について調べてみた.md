【Unity】iOS 向けの Low-level native plug-in interface を利用した Metal API へのアクセスについて調べてみた

この記事は [Unity Advent Calendar 2022](https://qiita.com/advent-calendar/2022/unity) の記事です。


Unityには古くから [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html) と言う機能が存在しており、こちらを利用することでUnityが内部的に持っている各プラットフォーム向けの低レベルな GraphicsAPI にアクセスすることが出来るようになります。

https://docs.unity3d.com/Manual/NativePluginInterface.html

じゃあ具体的にこれで何が出来るのか？と言うと、例えば今回話す iOS 向けの場合には「**Unityが持つ`MTLCommandEncoder`をフックして追加で描画命令を挟んだり、若しくはこちらを終了させて自身で追加の`MTLCommandEncoder`を追加する**」と言ったことが行えるようになります。


実装例としてはUnity公式のリポジトリにてサンプルプロジェクトが公開されてますが、今回はこちらを参考に同じ例を再実装する形で所々補足しつつ解説していければと思います。

https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin





# この記事で解説する内容について

この記事では先程挙げた[公式のサンプルプロジェクト](https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin)をベースに以下のトピックについて順に解説していければと思います。

- **iOS向けの `Low-level native plug-in interface` の導入について**
    - レンダースレッドからの任意のメソッドを呼び出すには
- **公式サンプルをベースに実装内容の解説**

あとは幾つかの用語についてはそのままだと長いので、以降は以下の省略表記で解説していきます。

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
- [Metal](https://developer.apple.com/jp/metal/)の基礎知識

この記事中では詳細までは解説しないので、別途資料を見てキャッチアップを済ませておくところまでを前提に書いていきます。

:::note warn
と書いたものの...自分も Metal に関してはまだ初学者なので、もし間違いや違和感のある記載など見かけたら、コメントや編集リクエストなどでご指摘いただけると幸いです。。 :bow: 
::: 



# iOS向けの `LLNPI` の導入について

先ずはiOS環境にて `LLNPI` をどうやって導入するのか？について解説します。

こちらのやり方の大凡は[公式ドキュメント](https://docs.unity3d.com/Manual/NativePluginInterface.html)の方にも書かれておりますが、**iOS向けで使う場合には幾つか別途対応する必要がある箇所もある**ので、そこらも補足しつつ解説していければと思います。

導入まで済んだら **Unity が持つ低レベルな GraphicsAPI へアクセスするためのインターフェースが手に入っている**ので、次にこちらを用いるための「レンダースレッドから任意のメソッドを呼び出す方法」について解説します。

:::note note
今回のサンプルプロジェクトでは大凡のロジック周りはSwiftで実装してますが、これから解説する **`LLNPI` の初期化やイベントの登録周りについてはマクロ周りが絡む都合上、ObjC で実装してます。**

※ ObjC はなるべく最低限の範囲で済むように実装してますが、もし Swift だけで全て解決可能な手法があったら、コメントや編集コメントなどで教えていただけると幸いです... :bow: 
:::

## インターフェースの実装と登録

`LLNPI` は「インターフェース」と名前が付いている通り、**Unityが事前に用意してくれている仕組みをネイティブプラグインとして実装する**ことで、その機能郡にアクセスする事ができるようになります。

もう少し具体的に言うと、**ネイティブプラグイン側で `UnityPluginLoad` と `UnityPluginUnload` と言う関数を実装することでUnityが自動でこちらの関数を呼び出し、更にここから今回の肝である GraphicsAPI へアクセスするためのインターフェースを受け取る**ことができます。　

:::note warn
「Unityが自動でこちらの関数を呼び出してくれる」と書きましたが、**iOSの場合には少し語弊があり、正確に言うと更に追加の実装を行わなければ呼び出されません。**
記事中では便宜的に自動で呼び出される前提で書いてますが、こちらの詳細については追って解説していきます。
::: 


### ◇ `UnityPluginLoad` と `UnityPluginUnload` の実装

サンプルプロジェクトからコードを抜粋すると、`ObjC` 側で実装している以下の関数がUnityから自動で呼び出されるので、この関数を経由して以下のインターフェースを取得します。  
(コード全体は[こちら](https://github.com/mao-test-h/LowLevelNativePluginWithMetal-Samples/blob/main/UnityProjects/BuiltInRP/Assets/LLNPISample/Plugins/LLNPIWithMetal/Native/UnityPluginRegister.m))

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

例えば `kUnityGfxDeviceEventInitialize` のタイミングで各種初期化処理を呼び出すと行ったことが可能になります。

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

`IUnityGraphics.h` と言ったコードは Unity が iOS ビルド時に出力する `xcodeproj` の中に含まれており、今回関連する以下のコード含めて `(ビルドの出力先)/Classes/Unity` 以下に実態があります。
 
- `IUnityInterface.h`
- `IUnityGraphics.h`
- `IUnityGraphicsMetal.h`
:::

#### ◆ `IUnityGraphicsMetalV1` について

上述の手順で手に入る `IUnityGraphicsMetalV1` についても先に軽く触れておきます。

`IUnityGraphicsMetalV1` は `IUnityGraphicsMetal.h` にて宣言されており、一部機能を抜粋すると恐らくは `Metal` に触れたことがある方なら見たことがあるであろうAPIが提供されてます。


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

前述したとおり、**iOS 環境の場合には`UnityPluginLoad` と `UnityPluginUnload` は自動で呼び出されません。**

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

その上で定義したクラスは `IMPL_APP_CONTROLLER_SUBCLASS` と言うマクロを経由することで Unity に登録する必要があります。

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


## レンダースレッドからの任意のメソッドを呼び出すには

ここまで準備できたら `IUnityGraphicsMetalV1` を用いて Metal APIを叩くだけですが、これらの実装はレンダースレッドから呼び出す必要があるみたいです。

Unity iOS は初期設定だと `Multithread Rendering` が有効になっており、この場合にはレンダリング関連の処理が `MonoBehaviour` などが実行されるメインスレッドとは **別のスレッド(レンダースレッド)で実行されることになります。**

この状態でメインスレッドから描画関連のイベントを呼び出すのは都合が悪いので、今回のようにレンダースレッド上で任意のレンダリングメソッドを呼び出す際には `GL.IssuePlugimEvent` と言うAPIを経由して呼び出す必要があります。

https://docs.unity3d.com/ScriptReference/GL.IssuePluginEvent.html

これだけだと少し分かりづらいかもなので、実装例と併せて解説していきます。

### ◆ C# 側でレンダースレッドから呼び出したいメソッドをコール

先ずはC#のコードを載せます。

ここでは以下のタイミングで `GL.IssuePlugimEvent` を呼び出しており、タイミングに応じて引数に int型 の `eventType` を渡してます。(渡すのは int型 ではあるが、C#上では便宜的に enum型 として定義)

- **`RenderMethod1`**
    - `OnPostRender()` が呼び出されるタイミング
- **`RenderMethod2`**
    - `WaitForEndOfFrame` で待ってレンダリングが完了したタイミング

**この `eventType` はネイティブコード側で呼び出されたメソッドを判別する際に利用します。**

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


### ◆ ネイティブコード側の実装

C#側で `GL.IssuePluginEvent` を呼び出すと、第一引数に渡している `getRenderEventFunc` が P/Invoke 経由で呼び出され、**更にそこで返している関数ポインタの先である `OnRenderEvent(int eventID)` がレンダースレッドから呼び出されます。**

`OnRenderEvent` の引数には C# から渡した int型 の `eventType` が渡ってくるので、こちらを見る形でどのメソッドが呼ばれたかを分岐してます。

```objc
// C# 側にある `enum EventType` と同じ定義を用意
enum EventID {
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
            // C# から `CallRenderEventFunc(EventType.RenderMethod1)` が呼ばれたときに実行されるイベントを実装
            break;
        case RenderMethod2:
            // C# から `CallRenderEventFunc(EventType.RenderMethod2)` が呼ばれたときに実行されるイベントを実装
            break;
    }
}
```

`eventType` 自体は int型 ではあるものの、今回のように互いに enum型 で定義しておくと可読性的にも分かりやすくなるかもなのでオススメです。







# 次回予告

- URPでの導入
- MetalFX

# 参考/関連リンク

- [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html)
