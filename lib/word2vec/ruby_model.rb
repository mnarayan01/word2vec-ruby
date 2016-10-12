# frozen_string_literal: true

require "scanf"
require "set"

require "word2vec/errors"
require "word2vec/model"

module Word2Vec
  #
  # Port of `word2vec`'s [`distance`](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c)
  # functionality to `ruby`. While changes/improvements of the original program have been made, they have _not_ been
  # particularly through, so much of it (including any possible bugs), still shows through.
  #
  # @note This is not automatically required as generally the **much** more performant {NativeModel} should be used in
  #   its place.
  #
  # ### N.B.
  #
  # Since this has not been totally refactored from the original program, the following my come into play:
  #
  # *   Any potential bugs may still exist.
  # *   Variable names may have been left unchanged.
  #
  # ###  Discussion
  #
  # #### Reference model
  #
  # For a version of this which is a more faithful translation of `word2vec`'s `distance` program, see {ReferenceModel}.
  #
  # #### Probably already exists
  #
  # Given that (after mucking through it all), this is a pretty straight-forward function which I'd describe as:
  #
  # > Finding the vectors from a set with the maximum cosine distance to a particular vector.
  #
  # I'd guess that this probably already exists. But I've written it, so...IDK...YOLO.
  #
  class RubyModel < Model
    # @private
    SIZE_OF_FLOAT = [1].pack("f").bytesize

    # @param [IO] io
    # @param [Encoding] encoding
    # @param [Boolean] normalize
    # @param [Boolean] validate_encoding
    #
    # @return [RubyModel]
    def self.parse(io, encoding: Encoding::UTF_8, normalize: true, validate_encoding: false)
      vocabulary_count = io.scanf("%d").first or raise ParseError
      vector_dimensionality = io.scanf("%d").first or raise ParseError

      vocabulary = []
      vectors = []

      buffer_size = vector_dimensionality * SIZE_OF_FLOAT
      buffer = "\0" * buffer_size
      unpack_format = "f#{vector_dimensionality}"

      vocabulary_count.times do
        vocabulary << io.scanf("%s").first&.force_encoding(encoding) or raise ParseError
        raise ParseError unless io.scanf("%c").first == " "

        io.read(buffer_size, buffer)
        raise ParseError unless buffer.bytesize == buffer_size
        vectors << buffer.unpack(unpack_format)
      end

      # Sanity checks.
      raise ParseError unless vocabulary.length == vocabulary_count
      raise ParseError if validate_encoding && !vocabulary.all?(&:valid_encoding?)
      raise ParseError unless vectors.length == vocabulary_count
      raise ParseError unless vectors.all? { |vector| vector.length == vector_dimensionality }

      vectors.each { |vector| normalize!(vector) } if normalize

      new(vocabulary, vectors)
    end

    # Should (generally) be constructed using {RubyModel.parse}.
    #
    # @param [Array<String>] vocabulary Will be deep-frozen.
    # @param [Array<Array<Float>>] vectors Will be deep-frozen.
    def initialize(vocabulary, vectors)
      raise ArgumentError if vocabulary.empty?
      raise ArgumentError unless vocabulary.length == vectors.length

      @vocabulary = vocabulary.freeze.each(&:freeze)
      @vectors = vectors.freeze.each(&:freeze)

      @vector_dimensionality = vectors.first.length
      raise ArgumentError unless vectors.all? { |vector| vector.length == vector_dimensionality }
    end

    # @return [Array<Array<Float>>]
    #
    # @!attribute [r] vectors
    attr_reader :vectors

    # @return [Integer]
    #
    # @!attribute [r] vector_dimensionality
    attr_reader :vector_dimensionality

    # @return [Array<String>]
    #
    # @!attribute [r] vocabulary
    attr_reader :vocabulary

    # @return [Integer]
    #
    # @!attribute [r] vocabulary_length
    def vocabulary_length
      vocabulary.length
    end

    # @param [Array<String>] search_terms
    # @param [Integer] neighbors_count
    #
    # @return [Hash<String, Float>]
    def nearest_neighbors(search_terms, neighbors_count: DEFAULT_NEIGHBORS_COUNT)
      raise ArgumentError if search_terms.empty?

      # The index of each term from `search_terms` in `#vectors`.
      #
      # @type [Set<Integer>]
      search_terms_indicies = search_terms.map do |term|
        word_to_index_map.fetch(term) { raise QueryError, "Out of dictionary word: #{term}" }
      end.to_set

      # @type [Array<Float>]
      search_vector = Array.new(vector_dimensionality, 0.0).tap do |search_vector|
        search_terms_indicies.each do |b|
          # XXX: Currently will never happen, but we could change it so it does in the future and the original is
          #   written to [handle it](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L106).
          next if b.nil?

          vector_dimensionality.times do |a|
            search_vector[a] += vectors[b][a]
          end
        end

        self.class.normalize!(search_vector)
      end

      # @type [Array<Float>]
      top_n_scores = Array.new(neighbors_count, 0.0)

      # @type [Array<String>]
      top_n_words = Array.new(neighbors_count, nil)

      vocabulary.length.times do |c|
        next if search_terms_indicies.include?(c)

        score = vector_dimensionality.times.inject(0) do |memo, a|
          memo + search_vector[a] * vectors[c][a]
        end

        neighbors_count.times do |a|
          if score > top_n_scores[a]
            (neighbors_count - 1 - a).times do |d_prime|
              d = neighbors_count - 1 - d_prime

              top_n_scores[d] = top_n_scores[d - 1]
              top_n_words[d] = top_n_words[d - 1]
            end

            top_n_scores[a] = score
            top_n_words[a] = vocabulary[c]
            break
          end
        end
      end

      top_n_words.zip(top_n_scores).to_h
    end

    private

    # @param [Array<Float>] vector
    #
    # @return [Array<Float>]
    def self.normalize!(vector)
      magnitude = Math.sqrt(vector.inject(0) { |memo, v| memo + v**2 })

      raise Error unless magnitude.finite? && magnitude > 0

      vector.map! { |v| v / magnitude }
    end
  end
end
