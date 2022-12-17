【Unity】iOS 向けの Low-level native plug-in interface を利用した Metal API へのアクセスについて調べてみた

この記事は [Unity Advent Calendar 2022](https://qiita.com/advent-calendar/2022/unity) の記事です。


Unityには古くから [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html) と言う機能が存在しており、こちらを利用することでUnityが内部的に持っている各プラットフォーム向けの GraphicsAPI にアクセスすることが出来るようになります。

https://docs.unity3d.com/Manual/NativePluginInterface.html

じゃあ具体的にこれで何が出来るのか？と言うと、例えば今回話すiOS向けの場合には「**Unityが持つ`MTLCommandEncoder`をフックして追加で描画命令を挟んだり、若しくはこちらを終了させて自身で追加の`MTLCommandEncoder`を追加する**」と言ったことが行えるようになります。


実装例としてはUnity公式のリポジトリにてサンプルプロジェクトが公開されてますが、今回はこちらを参考に同じ例を再実装する形で所々補足しつつ解説していければと思います。

https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin





# この記事で解説する内容について

この記事では先程挙げた[公式のサンプルプロジェクト](https://github.com/Unity-Technologies/iOSNativeCodeSamples/tree/2019-dev/Graphics/MetalNativeRenderingPlugin)をベースに以下のトピックについて順に解説していければと思います。

- **iOS向けの `Low-level native plug-in interface` の導入について**
- **公式サンプルをベースに実装内容の解説**
    - 後述しますが今回の実装では大凡の実装を Swift に移植し直した上で実装してます

あとは幾つかの用語についてはそのままだと長いので、移行以下の省略表記で解説していきます。

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
と書いたものの...自分も Metal に関してはまだ初学者なので、もし間違いや違和感のある記載など見かけたら、コメントや編集リクエストなどでご指摘いただけると幸いです。。
::: 





# iOS向けの `LLNPI` の導入について

先ずはiOS環境にて `LLNPI` をどうやって導入するのか？について解説します。

こちらのやり方の大凡は[公式ドキュメント](https://docs.unity3d.com/Manual/NativePluginInterface.html)の方にも書かれておりますが、**iOS向けで使う場合には幾つか別途対応する必要がある箇所もある**ので、そこらも補足しつつ解説していければと思います。


## インターフェースの実装と登録

`LLNPI` は「インターフェース」と名前が付いている通り、**Unityが事前に用意してくれている仕組みをネイティブプラグインとして実装する**ことで、その機能郡にアクセスする事ができるようになります。

もう少し具体的に言うと、**ネイティブプラグイン側で `UnityPluginLoad` と `UnityPluginUnload` と言う関数を実装することでUnityが自動でこちらの関数を呼び出し、更にここから今回の肝である Graphics API へアクセスするためのインターフェースを受け取る**ことができます。　

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
    // NOTE: kUnityGfxDeviceEventInitialize の後にプラグインのロードを受けるので、コールバックは手動で行う必要があるとのこと
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

あとは今回の例では実装してませんが、`g_Graphics->GetRenderer()` から「実行しているプラットフォームの GraphicsAPI の種類」を取得することが可能なので、もしマルチプラットフォームで利用可能なプラグインを実装する際にはこちらを見て処理を分岐させるなんてことも出来るかもしれません。
(今回だと iOS 元い Metal が前提なので `kUnityGfxRendererMetal` と一致するか `assert` を貼ってます)

ちなみにこれらの定義は `IUnityGraphics.h` と言うソースコードに定義されます。
(Unityが iOS ビルド時に出す xcodeproj の中にあります)


## ◇ iOSの場合には `UnityAppController` のサブクラスを定義し、`shouldAttachRenderDelegate` をオーバーライドして登録を行う

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

<details><summary>補足: IMPL_APP_CONTROLLER_SUBCLASS が何をやっているのか？について (クリックで展開)



</summary><div>

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










# 次回予告

- URPでの導入
- MetalFX

# 参考/関連リンク

- [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html)
