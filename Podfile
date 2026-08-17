platform :ios, '17.0'
use_frameworks!

target 'JJT' do
  # SVGA 动效播放（会员头像框等），对齐安卓 com.opensource.svgaplayer
  pod 'SVGAPlayer', '~> 2.5'
  # GLB 3D 礼物渲染（SceneKit 场景源；未发布 trunk，直接指 git）
  pod 'GLTFSceneKit', :git => 'https://github.com/magicien/GLTFSceneKit.git', :branch => 'master'
  # 腾讯 IM（密语），对齐安卓 com.tencent.imsdk:imsdk-plus
  pod 'TXIMSDK_Plus_iOS'
  # Bugly 崩溃上报（对齐安卓 crashreport）
  pod 'Bugly'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end

  # SVGAPlayer 2.5.7 的内置 protobuf 使用 OSAtomicCompareAndSwapPtrBarrier，
  # 该函数声明已从 iOS 17 SDK 移除（新 clang 与内建签名冲突直接报错）。
  # 安装期打补丁：全部调用替换为 C11 stdatomic 等价实现。
  pb = File.join(installer.sandbox.root, 'SVGAPlayer/Source/pbobjc/Svga.pbobjc.m')
  if File.exist?(pb)
    src = File.read(pb, encoding: 'UTF-8')
    unless src.include?('JJT_OSAtomicCompareAndSwapPtrBarrier')
      shim = <<~'OBJC'

        // --- jjt patch: OSAtomic* 已从 iOS 17 SDK 移除，C11 原子操作等价补齐 ---
        #import <stdatomic.h>
        static inline BOOL JJT_OSAtomicCompareAndSwapPtrBarrier(void* oldValue, void* newValue, void* volatile* theValue) {
            void* expected = oldValue;
            return atomic_compare_exchange_strong((volatile _Atomic(void*)*)theValue, &expected, newValue) ? YES : NO;
        }
        // --- jjt patch end ---
      OBJC
      src = src.sub(/#import "Svga\.pbobjc\.h"/) { |m| m + shim }
      src = src.gsub('OSAtomicCompareAndSwapPtrBarrier(', 'JJT_OSAtomicCompareAndSwapPtrBarrier(')
      # 替换时把 shim 自身的定义也误改了前缀，还原定义行
      src = src.sub('static inline BOOL JJT_JJT_OSAtomicCompareAndSwapPtrBarrier', 'static inline BOOL JJT_OSAtomicCompareAndSwapPtrBarrier')
      File.write(pb, src, encoding: 'UTF-8')
      Pod::UI.puts "jjt: patched Svga.pbobjc.m (OSAtomic -> C11 stdatomic)"
    end
  end
end
