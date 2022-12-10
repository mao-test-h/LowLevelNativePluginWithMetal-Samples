using System.Collections;
using LLNPISample.Plugins.LLNPIWithMetal.Managed;
using UnityEngine;
using UnityEngine.Assertions;

namespace LLNPISample.Scripts
{
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

            // note that we do that AFTER all unity rendering is done.
            // it is especially important if AA is involved, as we will end encoder (resulting in AA resolve)
            _nativeProxy.DoCopyRT(_targetCamera.targetTexture, null);
            yield return null;
        }
    }
}