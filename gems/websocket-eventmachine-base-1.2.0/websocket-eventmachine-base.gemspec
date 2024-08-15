# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "websocket/eventmachine/base/version"

Gem::Specification.new do |s|
  s.name        = "websocket-eventmachine-base"
  s.version     = WebSocket::EventMachine::Base::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Bernard Potocki"]
  s.email       = ["bernard.potocki@imanel.org"]
  s.homepage    = "http://github.com/imanel/websocket-eventmachine-base"
  s.summary     = %q{WebSocket base for Ruby client and server}
  s.description = %q{WebSocket base for Ruby client and server}

  s.add_dependency 'websocket', '~> 1.0'
  s.add_dependency 'websocket-native', '~> 1.0'
  s.add_dependency 'eventmachine', '~> 1.0'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
