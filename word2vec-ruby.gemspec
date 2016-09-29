# frozen_string_literal: true

# Maintain your gem's version:
require File.expand_path("../lib/word2vec/version", __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "word2vec-ruby"
  spec.version       = Word2Vec::VERSION
  spec.authors       = ["Michael Narayan"]
  spec.email         = ["michael@sensortower.com"]
  spec.homepage      = "https://github.com/mnarayan01/word2vec-ruby"
  spec.license       = "Apache-2.0"

  spec.summary       = "Ruby port of word2vec's distance program."

  spec.files         = Dir["LICENSE", "README.md", "ext/**/*.c", "lib/**/*.rb"]

  spec.extensions    = %w(ext/word2vec/extconf.rb)

  spec.required_ruby_version = ">= 2.3.0"
end
