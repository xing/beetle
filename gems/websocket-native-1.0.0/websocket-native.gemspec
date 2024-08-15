# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "websocket-native"
  s.version     = "1.0.0"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Bernard Potocki"]
  s.email       = ["bernard.potocki@imanel.org"]
  s.homepage    = "http://github.com/imanel/websocket-ruby-native"
  s.summary     = %q{Native Extension for WebSocket gem}
  s.description = %q{Native Extension for WebSocket gem}

  s.add_development_dependency 'rspec', '~> 2.11'
  s.add_development_dependency 'rake-compiler'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.extensions   << "ext/websocket_native_ext/extconf.rb"
  s.require_paths = ["lib"]
end
