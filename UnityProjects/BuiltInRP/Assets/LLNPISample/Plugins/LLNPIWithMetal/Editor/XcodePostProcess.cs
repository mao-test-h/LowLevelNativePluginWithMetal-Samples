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
        private static void OnPostProcessBuild(BuildTarget target, string xcodeProjPath)
        {
            if (target != BuildTarget.iOS) return;

            var projectPath = PBXProject.GetPBXProjectPath(xcodeProjPath);
            var project = new PBXProject();
            project.ReadFromString(File.ReadAllText(projectPath));

            AddMetalShader(xcodeProjPath, ref project);

            File.WriteAllText(projectPath, project.WriteToString());
        }

        private static void AddMetalShader(string xcodeProjPath, ref PBXProject project)
        {
            // `.metal` はAssets以下にあっても自動でxcodeprojに追加されないっぽいので、手動でコピーしてプロジェクトに足してやる。
            const string shaderPath = "/LLNPISample/Plugins/LLNPIWithMetal/Native/Shader.metal";
            const string nativePath = "/Libraries" + shaderPath;

            // 1. 先ずはビルド結果にあるプラグインが配置される場所と同じところにコピー
            var srcPath = Application.dataPath + shaderPath;
            var dstPath = xcodeProjPath + nativePath;
            File.Copy(srcPath, dstPath, true);

            // 2. xcodeprojにファイルとして追加し、ターゲットに含めてやる
            var frameworkGuid = project.GetUnityFrameworkTargetGuid();
            var file = project.AddFile(dstPath, nativePath, PBXSourceTree.Source);
            project.AddFileToBuild(frameworkGuid, file);
        }
    }
}

#endif