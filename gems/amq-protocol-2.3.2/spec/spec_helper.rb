# encoding: binary

require 'bundler/setup'
Bundler.require(:test)

begin
  require 'simplecov'

  SimpleCov.start do
    add_filter '/spec/'
  end
rescue LoadError
end

$: << File.expand_path('../../lib', __FILE__)

require "amq/protocol"

puts "Running on #{RUBY_VERSION}"

RSpec.configure do |config|
  config.include AMQ::Protocol

  config.filter_run_when_matching :focus

  config.disable_monkey_patching!

  config.warnings = true
end
