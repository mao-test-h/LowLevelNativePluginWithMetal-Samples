using UnityEngine;

namespace LLNPISample.Plugins.LLNPIWithMetal.Managed
{
    public sealed class NativeProxyForEditor : INativeProxy
    {
        void INativeProxy.DoExtraDrawCall()
        {
            // do nothing
        }

        void INativeProxy.DoCopyRT(RenderBuffer src, RenderBuffer dst)
        {
            // do nothing
        }
    }
}