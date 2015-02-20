source "https://rubygems.org"

gem 'git'
gem 'logger-colors'

group :development, :test do
  gem 'ci_reporter_test_unit'
  gem 'equivalent-xml'
  gem 'rake'
  gem 'simplecov'
  gem 'simplecov-rcov'
  gem 'test-unit'
  gem 'rubocop'
  gem 'rubocop-checkstyle_formatter'
end

group :s3 do
  gem 'aws-sdk-v1'
  gem 'nokogiri'
end

eval(IO.read(File.join(File.dirname(__FILE__),  'ci-tooling/Gemfile')), binding)
