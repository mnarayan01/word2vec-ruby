#!/usr/bin/env ruby
#
# frozen_string_literal: true

#
# Similar to `word2vec`'s [`distance`](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c) program,
# but using the `Word2Vec::NativeModel` `ruby` bindings.
#
# **N.B.**: This script is only intended for debugging/inspection and it is **not** distributed with the gem.
#
# ### Example usage
#
# Assuming that the `${REPO_ROOT}/data` directory contains the vector files (e.g. via symlinking):
#
#     NEIGHBORS_COUNT= bin/ruby-distance.rb data/vector.bin cat
#

require "bundler/setup"
require "word2vec"

################################################################################
# Configuration.

terms = ARGV.dup
filename = terms.shift
neighbors_count =
  if (raw_neighbors_count = ENV["NEIGHBORS_COUNT"]) && !raw_neighbors_count.empty?
    Integer(raw_neighbors_count)
  else
    10
  end

if filename.nil? || terms.empty?
  STDERR.puts "Usage: ruby-distance.rb <VECTOR_FILE> <TERM> [TERMS]"

  exit(1)
end

################################################################################
# Main logic.

model = Word2Vec::NativeModel.parse_file(filename)

if (sanitized_terms = terms.reject { |term| model.index(term).nil? }).empty?
  STDERR.puts "None of the provided terms existed in the model...aborting"

  exit(1)
else
  puts "### Terms in model"
  puts
  sanitized_terms.each do |term|
    puts "*   `#{term}`: `#{model.index(term)}`"
  end

  puts
  puts "### Neighbors"
  puts
  model.nearest_neighbors(sanitized_terms, neighbors_count: neighbors_count).each do |word, score|
    puts "*   `#{word}`: `#{score}`"
  end
end
