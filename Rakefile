require 'rake'
require 'rake/testtask'
require 'lib/beetle'
require 'rcov/rcovtask'

namespace :test do
  namespace :coverage do
    desc "Delete aggregate coverage data."
    task(:clean) { rm_f "coverage.data" }
  end

  desc 'Aggregate code coverage'
  task :coverage => "test:coverage:clean"

  Rcov::RcovTask.new(:coverage) do |t|
    t.libs << "test"
    t.test_files = FileList["test/**/*_test.rb"]
    t.output_dir = "test/coverage"
    t.verbose = true
    t.rcov_opts << "--exclude '.*' --include-file 'lib/beetle/'"
  end
  task :coverage do
    system 'open test/coverage/index.html'
  end if RUBY_PLATFORM =~ /darwin/
end


namespace :beetle do
  Beetle.configuration do |config|
    config.config_file = File.dirname(__FILE__) + '/test/beetle.yml'
  end

  task :test do
    Beetle::Client.new.test
  end

  task :trace do
    trap('INT'){ EM.stop_event_loop }
    Beetle::Client.new.trace
  end
end

task :default do
  Rake::Task[:test].invoke
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name    = 'beetle'
    gemspec.version = '0.0.7'
    gemspec.summary = "Reliable Messaging with AMQP"
    gemspec.description = "A high available/reliabile messaging infrastructure"
    gemspec.email = "developers@xing.com"
    gemspec.authors = ["Stefan Kaes", "Pascal Friederich", "Ali Jelveh"]
    gemspec.add_dependency('uuid4r', '>=0.1.1')
    gemspec.add_dependency('bunny', '>=0.6.0')
    gemspec.add_dependency('redis', '>=0.1.2')
    gemspec.add_dependency('amqp', '>=0.6.6')
    gemspec.add_dependency('activesupport', '>=2.3.4')

    gemspec.add_development_dependency('mocha')
    gemspec.add_development_dependency('rcov')
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  # puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

