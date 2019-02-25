
Pod::Spec.new do |s|
  s.name             = 'CSWebCache'
  s.version          = '0.1.0'
  s.summary          = 'iOS Offline Caching for Webview Content'
  s.swift_version    = '4.0'
  s.platform         = :ios
  
  s.description      = <<-DESC
TODO: A Swift framework for storing entire web pages into a disk cache distinct from, but interoperable with, the standard URLCache layer. This is useful for both pre-caching web content for faster loading, as well as making web content available for offline browsing.
                       DESC

  s.homepage         = 'https://github.com/Mayuramipara94/CSWebCache'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Mayur Amipara' => 'mayur.amipara@coruscate.co.in' }
  s.source           = { :git => 'https://github.com/Mayuramipara94/CSWebCache.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.pod_target_xcconfig = { "SWIFT_VERSION" => "4.0" }
  s.requires_arc = true
  s.source_files = 'CSWebCache/Classes/**/*'
  
  #s.frameworks = 'CommonCrypto'
  #s.preserve_paths = 'CommonCrypto/*'
  #s.xcconfig = {
  #'SWIFT_INCLUDE_PATHS[sdk=iphoneos*]' => '$(SRCROOT)/CSWebCache/CommonCrypto/iphoneos',
  #'SWIFT_INCLUDE_PATHS[sdk=iphonesimulator*]' => '$(SRCROOT)/CSWebCache/CommonCrypto/iphonesimulator',
  #}
  
end
