# frozen_string_literal: true

# rubocop:disable Lint/UnusedMethodArgument
# rubocop:disable Style/SignalException

#
module Word2Vec
  #
  # The base class of e.g. {NativeModel} and {RubyModel}. Generally only {NativeModel} should be used, though
  #   {RubyModel} (and to a lesser extent {ReferenceModel}) have addition documentation/discussion.
  #
  # @abstract
  #
  class Model
    DEFAULT_NEIGHBORS_COUNT = 40

    # @abstract
    #
    # @param [IO] io
    # @param [Hash] options
    #
    # @return [Model]
    def self.parse(io, options = {})
      fail NotImplementedError
    end

    # Convenience function which calls {Model.parse} on the provided file path.
    #
    # @param [String] filename
    # @param [Hash] options
    #
    # @return [Model]
    def self.parse_file(filename, options = {})
      File.open(filename, File::Constants::BINARY | File::Constants::RDONLY, encoding: Encoding::BINARY) do |io|
        parse(io, options)
      end
    end

    # @note _Purely_ for introspective purposes as it (may) return a _copy_ of the values used in {#nearest_neighbors}.
    #
    # @abstract
    #
    # @return [Array<Array<Float>>]
    #
    # @!attribute [r] vectors
    def vectors
      fail NotImplementedError
    end

    # @abstract
    #
    # @return [Integer]
    #
    # @!attribute [r] vector_dimensionality
    def vector_dimensionality
      fail NotImplementedError
    end

    # @note _Purely_ for introspective purposes as it (may) return a _copy_ of the values used in {#nearest_neighbors}.
    #
    # @abstract
    #
    # @return [Array<String>]
    #
    # @!attribute [r] vocabulary
    def vocabulary
      fail NotImplementedError
    end

    # @abstract
    #
    # @return [Integer]
    #
    # @!attribute [r] vocabulary_length
    def vocabulary_length
      fail NotImplementedError
    end

    # Returns the position of the provided `word` in {#vocabulary}. Since `word2vec` sorts by occurrence count, this
    # will be how popular the `word` is. Further, as {#vocabulary} and {#vectors} are synced, this will also be the
    # index of the word in {#vectors}.
    #
    # Uses either {#index_direct} or {#index_mapped} based on the value of the `:direct` option. The semantics of the
    # function should remain the same either way, but the efficiency may differ based upon the implementing class. See
    # said methods for additional information.
    #
    # @param [String] word
    #
    # @option options [Boolean] :direct (false)
    #
    # @return [Integer, nil]
    def index(word, direct: false)
      if direct
        index_direct(word)
      else
        index_mapped(word)
      end
    end

    # One implementation of {#index}. Initially this simply calls {#index_mapped}, but inheriting classes my override
    # the method to be implemented differently (e.g. {NativeModel#index_direct}).
    #
    # @note If overriden, the _semantics_ should remain unchanged; the overriding method should merely be more efficient
    #   (in at least some circumstances).
    #
    # @param [String] word
    #
    # @return [Integer, nil]
    def index_direct(word)
      index_mapped(word)
    end

    # One implementation of {#index}. Uses {#word_to_index_map}; see said method for additional information.
    #
    # @param [String] word
    #
    # @return [Integer, nil]
    def index_mapped(word)
      word_to_index_map[word]
    end

    # @abstract
    #
    # @param [Array<String>] search_terms
    #
    # @param [Hash] options Additional implementation dependent options.
    # @option options [Integer] :neighbors_count (DEFAULT_NEIGHBORS_COUNT)
    #
    # @return [Hash<String, Float>]
    def nearest_neighbors(search_terms, neighbors_count: DEFAULT_NEIGHBORS_COUNT, **options)
      # OPTIMIZE: Supporting passing the indicies of the `search_terms` in directly would provide some performance
      #   increase in certain situations.
      fail NotImplementedError
    end

    protected

    # @note This constructs a (memoized) `Hash`; in certain situations (e.g. when only looking up a small number of
    #   words using a {NativeModel}), it may be more efficient to use {#index_direct}.
    #
    # @note This value is lazily-evaluated and memoized.
    #
    # @return [Hash<String, Integer>]
    #
    # @!attribute [r] word_to_index_map
    def word_to_index_map
      @word_to_index_map ||= vocabulary.each_with_index.to_h.freeze
    end
  end
end
