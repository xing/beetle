# -*- encoding: utf-8 -*-
# stub: em-http-server 0.1.8 ruby lib

Gem::Specification.new do |s|
  s.name = "em-http-server".freeze
  s.version = "0.1.8"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["alor".freeze]
  s.date = "2014-01-27"
  s.description = "Simple http server for eventmachine".freeze
  s.email = ["alberto.ornaghi@gmail.com".freeze]
  s.homepage = "https://github.com/alor/em-http-server".freeze
  s.rubygems_version = "3.3.7".freeze
  s.summary = "Simple http server for eventmachine with the same interface as evma_httpserver".freeze

  s.installed_by_version = "3.3.7" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<eventmachine>.freeze, [">= 0"])
  else
    s.add_dependency(%q<eventmachine>.freeze, [">= 0"])
  end
end
