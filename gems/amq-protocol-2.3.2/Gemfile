# encoding: utf-8

source "https://rubygems.org"

group :development do
  # excludes Windows, Rubinius and JRuby
  gem "ruby-prof", :platforms => [:mri_19, :mri_20, :mri_21]

  gem "rake"
end

group :test do
  gem "rspec", ">= 3.8.0"
  gem "rspec-its"
  gem "simplecov"
end

group :development, :test do
  gem "byebug"
end
