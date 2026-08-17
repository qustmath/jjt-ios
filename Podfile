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
    end
  end
end
