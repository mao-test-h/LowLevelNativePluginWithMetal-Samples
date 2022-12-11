using UnityEngine;

namespace LLNPISample.Plugins.LLNPIWithMetal.Managed
{
    public interface INativeProxy
    {
        void DoExtraDrawCall();
        void DoCopyRT(RenderBuffer src, RenderBuffer dst);
    }
}