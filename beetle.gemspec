# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "beetle/version"

Gem::Specification.new do |s|
  s.name    = "beetle"
  s.version = Beetle::VERSION
  s.required_rubygems_version = ">= 1.3.7"
  s.authors            = ["Stefan Kaes", "Pascal Friederich", "Ali Jelveh", "Sebastian Roebke", "Larry Baltz"]
  s.date               = Time.now.strftime('%Y-%m-%d')
  s.default_executable = "beetle"
  s.description        = "A highly available, reliable messaging infrastructure"
  s.summary            = "High Availability AMQP Messaging with Redundant Queues"
  s.email              = "opensource@xing.com"
  s.executables        = ["beetle"]
  s.extra_rdoc_files   = Dir['**/*.rdoc'] + %w(MIT-LICENSE)
  s.files              = Dir['{examples,lib}/**/*.rb'] + Dir['{features,script}/**/*'] + %w(beetle.gemspec Rakefile)
  s.homepage           = "http://xing.github.com/beetle/"
  s.rdoc_options       = ["--charset=UTF-8"]
  s.require_paths      = ["lib"]
  s.rubygems_version   = "1.3.7"
  s.test_files         = Dir['test/**/*.rb']

  s.specification_version = 3
  s.add_runtime_dependency("uuid4r",                  [">= 0.1.2"])
  s.add_runtime_dependency("bunny",                   ["= 0.7.9"])
  s.add_runtime_dependency("redis",                   [">= 2.2.2", "< 3.1"])
  s.add_runtime_dependency("hiredis",                 ["= 0.4.5"])
  s.add_runtime_dependency("amq-client",              ["= 1.0.2"])
  s.add_runtime_dependency("amq-protocol",            ["= 1.6.0"])
  s.add_runtime_dependency("amqp",                    ["= 1.0.2"])
  s.add_runtime_dependency("activesupport",           [">= 2.3.4"])
  s.add_runtime_dependency("eventmachine_httpserver", [">= 0.2.1"])
  s.add_runtime_dependency("daemons",                 [">= 1.0.10"])
end
