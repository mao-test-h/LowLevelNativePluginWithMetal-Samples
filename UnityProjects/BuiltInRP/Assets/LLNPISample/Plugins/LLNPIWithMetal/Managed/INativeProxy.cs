using UnityEngine;

namespace LLNPISample.Plugins.LLNPIWithMetal.Managed
{
    public interface INativeProxy
    {
        void DoExtraDrawCall();
        void DoCopyRT(RenderTexture srcRT, RenderTexture dstRT);
    }
}