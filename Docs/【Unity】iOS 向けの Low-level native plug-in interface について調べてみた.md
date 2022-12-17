【Unity】iOS 向けの Low-level native plug-in interface を利用した Metal API へのアクセスについて調べてみた

---

この記事は [Unity Advent Calendar 2022](https://qiita.com/advent-calendar/2022/unity) の記事です。


Unityには古くから [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html) と言う機能が存在しており、こちらを利用することでUnityが内部的に持っている各プラットフォーム向けの GraphicsAPI にアクセスすることが出来るようになります。

https://docs.unity3d.com/Manual/NativePluginInterface.html

じゃあ具体的にこれで何が出来るのか？と言うと、例えば今回話すiOS向けの場合には「**Unityが持つ`MTLCommandEncoder`をフックして追加で描画命令を挟んだり、若しくはこちらを終了させて自身で追加の`MTLCommandEncoder`を追加する。**」と言ったことが行えるようになります。


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
- `ObjectiveC` → `ObjC`

## 記事の目的

上記の内容を踏まえて `LLNPI` を把握し、応用したり深く調べていく際の足がかりとするところまでを目的としてます。

:::note info
ちなみに自身がこの記事を書くに至ったモチベーションとして、Unityに [MetalFX](https://developer.apple.com/documentation/metalfx) を組み込んでみたかったと言う経緯があります。

詳細については[次回予告](#次回予告)の章にて改めて解説します。　
::: 

## 前提となる予備知識

記事を読むにあたっては以下の予備知識を必要とします。

- Unity 及び iOS向けのネイティブプラグインの実装知識
- [Metal](https://developer.apple.com/jp/metal/)の基礎知識

この記事中では詳細までは解説しないので、別途資料を見てキャッチアップを済ませておくところまでを前提に書いていきます。

:::note warn
と書いたものの...自分も Metal に関しては入門したてなので、もし間違いや違和感のある記載など見かけたら、コメントや編集リクエストなどでご指摘いただけると幸いです。。
::: 





# iOS向けの `Low-level native plug-in interface` の導入について








# 次回予告


# 参考/関連リンク

- [Low-level native plug-in interface](https://docs.unity3d.com/Manual/NativePluginInterface.html)
