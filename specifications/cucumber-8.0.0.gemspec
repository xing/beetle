# -*- encoding: utf-8 -*-
# stub: cucumber 8.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "cucumber".freeze
  s.version = "8.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.6.1".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/cucumber/cucumber-ruby/issues", "changelog_uri" => "https://github.com/cucumber/cucumber-ruby/blob/main/CHANGELOG.md", "documentation_uri" => "https://www.rubydoc.info/github/cucumber/cucumber-ruby/", "mailing_list_uri" => "https://groups.google.com/forum/#!forum/cukes", "source_code_uri" => "https://github.com/cucumber/cucumber-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Aslak Helles\u00F8y".freeze, "Matt Wynne".freeze, "Steve Tooke".freeze]
  s.date = "2022-05-19"
  s.description = "Behaviour Driven Development with elegance and joy".freeze
  s.email = "cukes@googlegroups.com".freeze
  s.executables = ["cucumber".freeze]
  s.files = ["bin/cucumber".freeze]
  s.homepage = "https://cucumber.io/".freeze
  s.licenses = ["MIT".freeze]
  s.rdoc_options = ["--charset=UTF-8".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6".freeze)
  s.rubygems_version = "3.3.7".freeze
  s.summary = "cucumber-8.0.0".freeze

  s.installed_by_version = "3.3.7" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<builder>.freeze, ["~> 3.2", ">= 3.2.4"])
    s.add_runtime_dependency(%q<cucumber-ci-environment>.freeze, ["~> 9.0", ">= 9.0.4"])
    s.add_runtime_dependency(%q<cucumber-core>.freeze, ["~> 11.0", ">= 11.0.0"])
    s.add_runtime_dependency(%q<cucumber-cucumber-expressions>.freeze, ["~> 15.1", ">= 15.1.1"])
    s.add_runtime_dependency(%q<cucumber-gherkin>.freeze, ["~> 23.0", ">= 23.0.1"])
    s.add_runtime_dependency(%q<cucumber-html-formatter>.freeze, ["~> 19.1", ">= 19.1.0"])
    s.add_runtime_dependency(%q<cucumber-messages>.freeze, ["~> 18.0", ">= 18.0.0"])
    s.add_runtime_dependency(%q<diff-lcs>.freeze, ["~> 1.5", ">= 1.5.0"])
    s.add_runtime_dependency(%q<mime-types>.freeze, ["~> 3.4", ">= 3.4.1"])
    s.add_runtime_dependency(%q<multi_test>.freeze, ["~> 1.1", ">= 1.1.0"])
    s.add_runtime_dependency(%q<sys-uname>.freeze, ["~> 1.2", ">= 1.2.2"])
    s.add_development_dependency(%q<cucumber-compatibility-kit>.freeze, ["~> 9.2", ">= 9.2.1"])
    s.add_development_dependency(%q<nokogiri>.freeze, ["~> 1.13", ">= 1.13.6"])
    s.add_development_dependency(%q<pry>.freeze, ["~> 0.14", ">= 0.14.1"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 13.0", ">= 13.0.6"])
    s.add_development_dependency(%q<rspec>.freeze, ["~> 3.11", ">= 3.11.0"])
    s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.21", ">= 0.21.2"])
    s.add_development_dependency(%q<syntax>.freeze, ["~> 1.2", ">= 1.2.2"])
    s.add_development_dependency(%q<test-unit>.freeze, ["~> 3.5", ">= 3.5.3"])
    s.add_development_dependency(%q<webrick>.freeze, ["~> 1.7", ">= 1.7.0"])
    s.add_development_dependency(%q<octokit>.freeze, ["~> 4.22", ">= 4.22.0"])
    s.add_development_dependency(%q<capybara>.freeze, ["~> 3.36", ">= 3.36.0", "< 3.37"])
    s.add_development_dependency(%q<rack-test>.freeze, ["~> 1.1", ">= 1.1.0"])
    s.add_development_dependency(%q<sinatra>.freeze, ["~> 2.2", ">= 2.2.0"])
  else
    s.add_dependency(%q<builder>.freeze, ["~> 3.2", ">= 3.2.4"])
    s.add_dependency(%q<cucumber-ci-environment>.freeze, ["~> 9.0", ">= 9.0.4"])
    s.add_dependency(%q<cucumber-core>.freeze, ["~> 11.0", ">= 11.0.0"])
    s.add_dependency(%q<cucumber-cucumber-expressions>.freeze, ["~> 15.1", ">= 15.1.1"])
    s.add_dependency(%q<cucumber-gherkin>.freeze, ["~> 23.0", ">= 23.0.1"])
    s.add_dependency(%q<cucumber-html-formatter>.freeze, ["~> 19.1", ">= 19.1.0"])
    s.add_dependency(%q<cucumber-messages>.freeze, ["~> 18.0", ">= 18.0.0"])
    s.add_dependency(%q<diff-lcs>.freeze, ["~> 1.5", ">= 1.5.0"])
    s.add_dependency(%q<mime-types>.freeze, ["~> 3.4", ">= 3.4.1"])
    s.add_dependency(%q<multi_test>.freeze, ["~> 1.1", ">= 1.1.0"])
    s.add_dependency(%q<sys-uname>.freeze, ["~> 1.2", ">= 1.2.2"])
    s.add_dependency(%q<cucumber-compatibility-kit>.freeze, ["~> 9.2", ">= 9.2.1"])
    s.add_dependency(%q<nokogiri>.freeze, ["~> 1.13", ">= 1.13.6"])
    s.add_dependency(%q<pry>.freeze, ["~> 0.14", ">= 0.14.1"])
    s.add_dependency(%q<rake>.freeze, ["~> 13.0", ">= 13.0.6"])
    s.add_dependency(%q<rspec>.freeze, ["~> 3.11", ">= 3.11.0"])
    s.add_dependency(%q<simplecov>.freeze, ["~> 0.21", ">= 0.21.2"])
    s.add_dependency(%q<syntax>.freeze, ["~> 1.2", ">= 1.2.2"])
    s.add_dependency(%q<test-unit>.freeze, ["~> 3.5", ">= 3.5.3"])
    s.add_dependency(%q<webrick>.freeze, ["~> 1.7", ">= 1.7.0"])
    s.add_dependency(%q<octokit>.freeze, ["~> 4.22", ">= 4.22.0"])
    s.add_dependency(%q<capybara>.freeze, ["~> 3.36", ">= 3.36.0", "< 3.37"])
    s.add_dependency(%q<rack-test>.freeze, ["~> 1.1", ">= 1.1.0"])
    s.add_dependency(%q<sinatra>.freeze, ["~> 2.2", ">= 2.2.0"])
  end
end
