using System;
using System.Runtime.InteropServices;
using UnityEngine;

namespace LLNPISample.Plugins.LLNPIWithMetal.Managed
{
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

        private static void CallRenderEventFunc(EventType eventType)
        {
            [DllImport("__Internal", EntryPoint = "getRenderEventFunc")]
            static extern IntPtr GetRenderEventFunc();

            GL.IssuePluginEvent(GetRenderEventFunc(), (int)eventType);
        }
    }
}