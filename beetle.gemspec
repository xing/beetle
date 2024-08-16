# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "beetle/version"

Gem::Specification.new do |s|
  s.name    = "beetle"
  s.version = Beetle::VERSION
  s.required_rubygems_version = ">= 1.3.7"
  s.authors            = ["Stefan Kaes", "Pascal Friederich", "Ali Jelveh", "Sebastian Roebke", "Larry Baltz"]
  s.date               = Time.now.strftime('%Y-%m-%d')
  s.description        = "A highly available, reliable messaging infrastructure"
  s.summary            = "High Availability AMQP Messaging with Redundant Queues"
  s.email              = "opensource@xing.com"
  s.executables        = []
  s.extra_rdoc_files   = Dir['**/*.rdoc'] + %w(MIT-LICENSE)
  s.files              = Dir['{examples,lib}/**/*.rb'] + Dir['{features,script}/**/*'] + %w(beetle.gemspec Rakefile)
  s.homepage           = "https://xing.github.com/beetle/"
  s.rdoc_options       = ["--charset=UTF-8"]
  s.require_paths      = ["lib"]
  s.test_files         = Dir['test/**/*.rb']
  s.metadata = {
    'allowed_push_host' => "https://gems.xing.com",
    "changelog_uri"    => "https://github.com/xing/beetle/blob/master/RELEASE_NOTES.rdoc"
  }

  s.specification_version = 3
  s.add_runtime_dependency "bunny",                   "~> 0.7.13"
  s.add_runtime_dependency "redis",                   ">= 4.2.1"
  s.add_runtime_dependency "hiredis",                 ">= 0.4.5"
  s.add_runtime_dependency "amq-protocol",            "= 2.3.2"
  s.add_runtime_dependency "amqp",                    "= 1.8.0"
  s.add_runtime_dependency "activesupport",           ">= 2.3.4"

  s.add_development_dependency "activerecord",        "~> 5.0"
  s.add_development_dependency "cucumber",            "~> 8.0.0"
  s.add_development_dependency "daemon_controller",   "~> 1.2.0"
  s.add_development_dependency "daemons",             ">= 1.2.0"
  s.add_development_dependency "i18n"
  s.add_development_dependency "minitest",            "~> 5.1"
  s.add_development_dependency "minitest-reporters"
  s.add_development_dependency "mocha",               "~> 1.14"
  s.add_development_dependency "mysql2",              "~> 0.5"
  s.add_development_dependency "rake",                "~> 13.0"
  s.add_development_dependency "simplecov",           "~> 0.15"
  s.add_development_dependency "webmock",             "~> 3.0"
  s.add_development_dependency "websocket-eventmachine-client"
  s.add_development_dependency "em-http-server"
  s.add_development_dependency "yard"
  s.add_development_dependency "redcarpet"
  s.add_development_dependency "github-markup"
  s.add_development_dependency "byebug"
  s.add_development_dependency "appraisal"
end
