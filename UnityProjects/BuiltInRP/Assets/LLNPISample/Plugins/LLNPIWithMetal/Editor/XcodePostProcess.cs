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

            AddMetalShader(xcodeprojPath, ref pbxProject);
            ReplaceNativeSources(xcodeprojPath);
            SetPublicHeader(ref pbxProject);

            File.WriteAllText(pbxProjectPath, pbxProject.WriteToString());
        }

        private static void AddMetalShader(string xcodeprojPath, ref PBXProject pbxProject)
        {
            // `.metal` はAssets以下にあっても自動でxcodeprojに追加されないっぽいので、手動でコピーしてプロジェクトに足してやる。
            const string shaderPath = "/LLNPISample/Plugins/LLNPIWithMetal/Native/Shader.metal";
            const string nativePath = "/Libraries" + shaderPath;

            // 1. 先ずはビルド結果にあるプラグインが配置される場所と同じところにコピー
            var srcPath = Application.dataPath + shaderPath;
            var dstPath = xcodeprojPath + nativePath;
            File.Copy(srcPath, dstPath, true);

            // 2. xcodeprojにファイルとして追加し、ターゲットに含めてやる
            var frameworkGuid = pbxProject.GetUnityFrameworkTargetGuid();
            var file = pbxProject.AddFile(dstPath, nativePath, PBXSourceTree.Source);
            pbxProject.AddFileToBuild(frameworkGuid, file);
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