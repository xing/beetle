# -*- encoding: utf-8 -*-
Gem::Specification.new do |gem|
  gem.authors       = ["alor"]
  gem.email         = ["alberto.ornaghi@gmail.com"]
  gem.description   = %q{Simple http server for eventmachine}
  gem.summary       = %q{Simple http server for eventmachine with the same interface as evma_httpserver}
  gem.homepage      = "https://github.com/alor/em-http-server"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "em-http-server"
  gem.require_paths = ["lib"]
  gem.version       = "0.1.8"

  gem.add_runtime_dependency "eventmachine"
end
