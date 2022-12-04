#if UNITY_IOS
using System.IO;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;

namespace LLNPISample.Editor
{
    internal static class XcodePostProcess
    {
        [PostProcessBuild]
        private static void OnPostProcessBuild(BuildTarget target, string xcodeProjPath)
        {
            if (target != BuildTarget.iOS) return;

            var projectPath = PBXProject.GetPBXProjectPath(xcodeProjPath);
            var project = new PBXProject();
            project.ReadFromString(File.ReadAllText(projectPath));

            // 検証用に常に有効にしておく
            var schemePath = $"{xcodeProjPath}/Unity-iPhone.xcodeproj/xcshareddata/xcschemes/Unity-iPhone.xcscheme";
            var xcScheme = new XcScheme();
            xcScheme.ReadFromFile(schemePath);
            xcScheme.SetFrameCaptureModeOnRun(XcScheme.FrameCaptureMode.Metal);
            xcScheme.SetDebugExecutable(true);
            xcScheme.WriteToFile(schemePath);
        }
    }
}

#endif