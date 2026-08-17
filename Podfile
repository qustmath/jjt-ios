platform :ios, '17.0'
use_frameworks!

target 'JJT' do
  # SVGA 动效播放（会员头像框等），对齐安卓 com.opensource.svgaplayer
  pod 'SVGAPlayer', '~> 2.5'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      if target.name == 'SVGAPlayer'
        # 2.5.7 内置 protobuf 用了已从 iOS 17 SDK 移除的 OSAtomic*；
        # C89 模式 + 显式取消该警告的 error 晋升，老代码可继续编译
        config.build_settings['GCC_C_LANGUAGE_STANDARD'] = 'gnu89'
        config.build_settings['CLANG_WARN_IMPLICIT_FUNCTION_DECLARATION'] = 'NO'
        config.build_settings['OTHER_CFLAGS'] = '$(inherited) -Wno-error=implicit-function-declaration -Wno-implicit-function-declaration'
      end
    end
  end
end
