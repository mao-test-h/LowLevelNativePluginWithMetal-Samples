【Unity】iOS 向けの Low-level native plug-in interface を利用した Metal API へのアクセスについて調べてみた

この記事は [Unity Advent Calendar 2022](https://qiita.com/advent-calendar/2022/unity) の18日目の記事です。


Unityには [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html) と言う機能が存在しており、こちらを利用することでUnityが内部的に持っている各プラットフォーム向けの低レベルな GraphicsAPI にアクセスすることが出来るようになります。

https://docs.unity3d.com/Manual/NativePluginInterface.html

じゃあ具体的にこれで何が出来るのか？と言うと、例えば今回話す iOS 向けの場合には「**Unityが持つ`MTLCommandEncoder`をフックして追加で描画命令を挟んだり、若しくはこちらを終了させて自身で`MTLCommandEncoder`を追加する**」と言ったことが行えるようになります。


実装例としては Unity 公式のリポジトリにてサンプルプロジェクトが公開されてますが、今回はこちらを参考に同じ例を再実装する形で所々補足しつつ解説していければと思います。

https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin





# この記事で解説する内容について

この記事では先程挙げた[公式のサンプルプロジェクト](https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin)をベースに以下のトピックについて順に解説していければと思います。

- **iOS向けの `Low-level native plug-in interface` の導入について**
    - レンダースレッドからの任意のレンダリングメソッドを呼び出すには
    - Swift で実装していくにあたっての補足
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

`LLNPI` は **Unity が事前に用意してくれている仕組みをネイティブプラグインとして実装する**ことで、低レベルな GraphicsAPI と言った機能郡にアクセスする事ができるようになります。

もう少し具体的に言うと、**ネイティブプラグイン側で `UnityPluginLoad` と `UnityPluginUnload` と言う関数を実装することで Unity が自動でこちらの関数を呼び出し、更にここから今回の肝である GraphicsAPI へアクセスするためのインターフェースを受け取る**ことができます。　

:::note warn
「Unityが自動でこちらの関数を呼び出してくれる」と書きましたが、**iOSの場合には少し語弊があり、正確に言うと更に追加の実装を行わなければ呼び出されません。**
記事中では便宜的に自動で呼び出される前提で書いてますが、こちらの詳細については追って解説していきます。
::: 


### ◇ `UnityPluginLoad` と `UnityPluginUnload` の実装

サンプルプロジェクトからコードを抜粋すると、`ObjC` 側で実装している以下の関数がUnityから自動で呼び出されるので、この関数を経由して以下のインターフェースを取得します。  

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


## レンダースレッドからの任意のレンダリングメソッドを呼び出すには

ここまで準備できたら `IUnityGraphicsMetalV1` を用いて実際に Metal API を叩くレンダリングメソッドを実装するだけですが、これらの処理はレンダースレッドから呼び出す必要があります。

Unity iOS は初期設定だと `Multithread Rendering` が有効になっており、この場合にはレンダリング関連の処理が `MonoBehaviour` などが実行されるメインスレッドとは **別のスレッド(レンダースレッド)で実行されることになります。**

この状態でメインスレッドから描画関連の処理を呼び出すのは都合が悪いので、今回のようにレンダースレッド上で任意のレンダリングに関する処理を呼び出したい場合には `GL.IssuePlugimEvent` と言うAPIを経由して呼び出す必要があります。

https://docs.unity3d.com/ScriptReference/GL.IssuePluginEvent.html

これだけだと少し分かりづらいかもなので、実装例と併せて解説していきます。

### ◇ C# 側でレンダースレッドから呼び出したい関数をイベント経由でコール

先ずはC#のコードを載せます。

ここでは以下のタイミングで `GL.IssuePlugimEvent` を呼び出しており、タイミングに応じて引数に int型 の `eventType` を渡してます。(渡すのは int型 ではあるが、C#上では便宜的に enum型 として定義)

- **`RenderMethod1`**
    - `OnPostRender()` が呼び出されるタイミング
- **`RenderMethod2`**
    - `WaitForEndOfFrame` で待ってレンダリングが完了したタイミング

**この `eventType` はネイティブコード側で呼び出されたイベントを判別する際に利用します。**

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

```swift
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

最後に `LLNPI` に関する処理を実装した `IUnityGraphicsMetalV1` のポインタを持つコード側で `UnityGraphicsBridge` を実装することで `IUnityGraphicsMetalV1` をそのまま返せるようにします。

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


# 次回予告

- URPでの導入
- MetalFX

# 参考/関連リンク

- [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html)

- [FrameworkでSwiftとObjective-C混ぜるのはやばい](https://qiita.com/fr0g_fr0g/items/82789af60b27ae19b263)