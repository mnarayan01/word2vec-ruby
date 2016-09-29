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

    # @note _Purely_ for debugging purposes as it (may be) **extremely** inefficient.
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

    # @note _Purely_ for debugging purposes as it (may be) **extremely** inefficient.
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

    # Returns the position of the provided `word`, ranked by descending occurrence count in the training set.
    #
    # @abstract
    #
    # @param [String] word
    #
    # @return [Integer, nil]
    def index(word)
      fail NotImplementedError
    end

    # @abstract
    #
    # @param [Array<String>] search_terms
    #
    # @option options [Integer] :neighbors_count (DEFAULT_NEIGHBORS_COUNT)
    #
    # @return [Hash<String, Float>]
    def nearest_neighbors(search_terms, neighbors_count: DEFAULT_NEIGHBORS_COUNT)
      fail NotImplementedError
    end
  end
end
