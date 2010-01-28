require 'rake'
require 'rake/testtask'
require 'lib/bandersnatch'

namespace :bandersnatch do
  Bandersnatch.configuration do |config|
    config.config_file = File.dirname(__FILE__) + '/test/bandersnatch.yml'
  end

  task :test do
    Bandersnatch::Client.new.test
  end

  task :trace do
    trap('INT'){ EM.stop_event_loop }
    Bandersnatch::Client.new.trace
  end
end

task :default do
  Rake::Task[:test].invoke
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name    = 'banderstnatch'
    gemspec.version = '0.0.1'
    gemspec.summary = "Messages :P"
    gemspec.description = "A high available/reliabile messaging infrastructure"
    gemspec.email = "developers@xing.com"
    gemspec.authors = ["Stefan Kaes", "Pascal Friederich"]
    gemspec.add_dependency('uuid4r', '>=0.1.1')
    gemspec.add_dependency('bunny', '>=0.6.0')
    gemspec.add_dependency('redis', '>=1.2.1')
    gemspec.add_dependency('amqp', '>=0.6.6')
    gemspec.add_dependency('active_support', '2.3.5')

    gemspec.add_development_dependency('mocha')
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  # puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

