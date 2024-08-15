# -*- encoding: utf-8 -*-
# stub: bunny 0.7.13 ruby lib

Gem::Specification.new do |s|
  s.name = "bunny".freeze
  s.version = "0.7.13"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Chris Duncan".freeze, "Eric Lindvall".freeze, "Jakub Stastny aka botanicus".freeze, "Michael S. Klishin".freeze, "Stefan Kaes".freeze]
  s.date = "2023-03-26"
  s.description = "A synchronous Ruby AMQP client that enables interaction with AMQP-compliant brokers.".freeze
  s.email = ["celldee@gmail.com".freeze, "eric@5stops.com".freeze, "stastny@101ideas.cz".freeze, "michael@novemberain.com".freeze, "skaes@railsexpress.de".freeze]
  s.extra_rdoc_files = ["README.textile".freeze]
  s.files = ["README.textile".freeze]
  s.homepage = "http://github.com/ruby-amqp/bunny".freeze
  s.licenses = ["MIT".freeze]
  s.post_install_message = "[\e[32mVersion 0.7.11\e[0m] support boolean values in message headers\n".freeze
  s.rdoc_options = ["--main".freeze, "README.rdoc".freeze]
  s.rubygems_version = "3.3.7".freeze
  s.summary = "Synchronous Ruby AMQP 0.9.1 client".freeze

  s.installed_by_version = "3.3.7" if s.respond_to? :installed_by_version
end
