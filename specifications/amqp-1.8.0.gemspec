# -*- encoding: utf-8 -*-
# stub: amqp 1.8.0 ruby lib

Gem::Specification.new do |s|
  s.name = "amqp".freeze
  s.version = "1.8.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Aman Gupta".freeze, "Jakub Stastny aka botanicus".freeze, "Michael S. Klishin".freeze]
  s.date = "2018-01-02"
  s.description = "Mature EventMachine-based RabbitMQ client.".freeze
  s.email = ["michael@novemberain.com".freeze, "stastny@101ideas.cz".freeze]
  s.extra_rdoc_files = ["README.md".freeze, "docs/Exchanges.textile".freeze, "docs/Clustering.textile".freeze, "docs/VendorSpecificExtensions.textile".freeze, "docs/PatternsAndUseCases.textile".freeze, "docs/Troubleshooting.textile".freeze, "docs/Bindings.textile".freeze, "docs/AMQP091ModelExplained.textile".freeze, "docs/Durability.textile".freeze, "docs/ConnectionEncryptionWithTLS.textile".freeze, "docs/TestingWithEventedSpec.textile".freeze, "docs/Queues.textile".freeze, "docs/DocumentationGuidesIndex.textile".freeze, "docs/GettingStarted.textile".freeze, "docs/08Migration.textile".freeze, "docs/ConnectingToTheBroker.textile".freeze, "docs/ErrorHandling.textile".freeze, "docs/RabbitMQVersions.textile".freeze, "docs/RunningTests.textile".freeze]
  s.files = ["README.md".freeze, "docs/08Migration.textile".freeze, "docs/AMQP091ModelExplained.textile".freeze, "docs/Bindings.textile".freeze, "docs/Clustering.textile".freeze, "docs/ConnectingToTheBroker.textile".freeze, "docs/ConnectionEncryptionWithTLS.textile".freeze, "docs/DocumentationGuidesIndex.textile".freeze, "docs/Durability.textile".freeze, "docs/ErrorHandling.textile".freeze, "docs/Exchanges.textile".freeze, "docs/GettingStarted.textile".freeze, "docs/PatternsAndUseCases.textile".freeze, "docs/Queues.textile".freeze, "docs/RabbitMQVersions.textile".freeze, "docs/RunningTests.textile".freeze, "docs/TestingWithEventedSpec.textile".freeze, "docs/Troubleshooting.textile".freeze, "docs/VendorSpecificExtensions.textile".freeze]
  s.homepage = "http://rubyamqp.info".freeze
  s.licenses = ["Ruby".freeze]
  s.rdoc_options = ["--include=examples --main README.md".freeze]
  s.rubygems_version = "3.3.7".freeze
  s.summary = "Mature EventMachine-based RabbitMQ client".freeze

  s.installed_by_version = "3.3.7" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<eventmachine>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<amq-protocol>.freeze, [">= 2.2.0"])
  else
    s.add_dependency(%q<eventmachine>.freeze, [">= 0"])
    s.add_dependency(%q<amq-protocol>.freeze, [">= 2.2.0"])
  end
end
