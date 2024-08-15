# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "websocket/eventmachine/client/version"

Gem::Specification.new do |s|
  s.name        = "websocket-eventmachine-client"
  s.version     = WebSocket::EventMachine::Client::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Bernard Potocki"]
  s.email       = ["bernard.potocki@imanel.org"]
  s.homepage    = "http://github.com/imanel/websocket-eventmachine-client"
  s.summary     = %q{WebSocket client for Ruby}
  s.description = %q{WebSocket client for Ruby}

  s.add_dependency 'websocket-eventmachine-base', '~> 1.0'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
