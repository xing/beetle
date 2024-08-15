#!/usr/bin/env ruby
# encoding: utf-8

# rabbitmq-codegen is Python 3 compatible and so is
# the code in this repo but Mako still fails with 3.6 as of May 2017 :( MK.
python = ENV.fetch("PYTHON", "python2")

def sh(*args)
  system(*args)
end

extensions = []

spec = "codegen/rabbitmq-codegen/amqp-rabbitmq-0.9.1.json"
unless File.exist?(spec)
  sh "git submodule update --init"
end

path = "lib/amq/protocol/client.rb"
puts "Running '#{python} ./codegen/codegen.py client #{spec} #{extensions.join(' ')} #{path}'"
sh "#{python} ./codegen/codegen.py client #{spec} #{extensions.join(' ')} #{path}"
if File.file?(path)
  sh "ruby -c #{path}"
end
