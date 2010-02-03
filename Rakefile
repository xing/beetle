require 'rake'
require 'rake/testtask'
require 'lib/bandersnatch'
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
    t.rcov_opts << "--exclude '.*' --include-file 'lib/bandersnatch/'"
  end
  task :coverage do
    system 'open test/coverage/index.html'
  end if RUBY_PLATFORM =~ /darwin/
end


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
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name    = 'bandersnatch'
    gemspec.version = '0.0.2'
    gemspec.summary = "Messages :P"
    gemspec.description = "A high available/reliabile messaging infrastructure"
    gemspec.email = "developers@xing.com"
    gemspec.authors = ["Stefan Kaes", "Pascal Friederich"]
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

