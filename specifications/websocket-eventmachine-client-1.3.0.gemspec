# -*- encoding: utf-8 -*-
# stub: websocket-eventmachine-client 1.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "websocket-eventmachine-client".freeze
  s.version = "1.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Bernard Potocki".freeze]
  s.date = "2019-09-19"
  s.description = "WebSocket client for Ruby".freeze
  s.email = ["bernard.potocki@imanel.org".freeze]
  s.homepage = "http://github.com/imanel/websocket-eventmachine-client".freeze
  s.rubygems_version = "3.3.7".freeze
  s.summary = "WebSocket client for Ruby".freeze

  s.installed_by_version = "3.3.7" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<websocket-eventmachine-base>.freeze, ["~> 1.0"])
  else
    s.add_dependency(%q<websocket-eventmachine-base>.freeze, ["~> 1.0"])
  end
end
