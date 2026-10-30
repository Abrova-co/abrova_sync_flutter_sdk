Pod::Spec.new do |s|
  s.name             = 'abrova_sync'
  s.version          = '0.3.0'
  s.summary          = 'Flutter plugin for AbrovaSync realtime database SDK'
  s.description      = <<-DESC
Flutter plugin for AbrovaSync — realtime database SDK with offline-first sync.
                       DESC
  s.homepage         = 'https://abrova.ir/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Abrova' => 'founder@abrova.ir' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/AbrovaSyncPlugin.swift'

  s.dependency 'Flutter'
  s.dependency 'AbrovaSync', '~> 0.3.0'
  s.dependency 'PNProtocol', '~> 0.2'

  s.platform = :ios, '13.0'
  s.swift_version = '5.7'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
