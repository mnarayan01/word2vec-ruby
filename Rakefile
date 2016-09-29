#!/usr/bin/env rake
#
# frozen_string_literal: true

require "bundler/setup"

# Gem packaging/install/deploy tasks.
Bundler::GemHelper.install_tasks

# Set the default task.
task default: :build

# Support development by adding `compile` tasks to build the DLL locally. Note that this is _not_ required for the
# gem to install itself properly.
require "rake/extensiontask"
Rake::ExtensionTask.new do |ext|
  ext.name = "native_model"
  ext.gem_spec = Gem::Specification.load("word2vec-ruby.gemspec")
  ext.ext_dir = "ext/word2vec"
  ext.lib_dir = "lib/word2vec"
end
