# -*- encoding: utf-8 -*-
# stub: websocket-native 1.0.0 ruby lib
# stub: ext/websocket_native_ext/extconf.rb

Gem::Specification.new do |s|
  s.name = "websocket-native".freeze
  s.version = "1.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Bernard Potocki".freeze]
  s.date = "2012-11-19"
  s.description = "Native Extension for WebSocket gem".freeze
  s.email = ["bernard.potocki@imanel.org".freeze]
  s.extensions = ["ext/websocket_native_ext/extconf.rb".freeze]
  s.files = ["ext/websocket_native_ext/extconf.rb".freeze]
  s.homepage = "http://github.com/imanel/websocket-ruby-native".freeze
  s.rubygems_version = "3.3.7".freeze
  s.summary = "Native Extension for WebSocket gem".freeze

  s.installed_by_version = "3.3.7" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 3
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<rspec>.freeze, ["~> 2.11"])
    s.add_development_dependency(%q<rake-compiler>.freeze, [">= 0"])
  else
    s.add_dependency(%q<rspec>.freeze, ["~> 2.11"])
    s.add_dependency(%q<rake-compiler>.freeze, [">= 0"])
  end
end
