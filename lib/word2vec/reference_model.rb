# frozen_string_literal: true

require "scanf"

require "word2vec/errors"
require "word2vec/model"

module Word2Vec
  #
  # Port of `word2vec`'s [`distance`](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c)
  # functionality to `ruby`. This is intended to be completely identical with the original program (including any
  # possible bugs), though it will be "safe" (i.e. purely `ruby` so none of the many buffer overflows, etc).
  #
  # @note This is not automatically required; it is simply here to give a reference to the original translation from
  #   `word2vec`'s `distance` program. For the actual model used, see {NativeModel} (or {RubyModel}).
  #
  # ### N.B.
  #
  # Since this is written to be completely identical to the original program:
  #
  # *   Any potential bugs were left in.
  # *   Variable names were (generally) left unchanged.
  # *   (Almost) no refactoring was done.
  #
  # ###  Discussion
  #
  # #### Probably already exists
  #
  # Given that (after mucking through it all), this is a pretty straight-forward function which I'd describe as:
  #
  # > Finding the vectors from a set with the maximum cosine distance to a particular vector.
  #
  # I'd guess that this probably already exists. But I've written it, so...IDK...YOLO.
  #
  # #### L-value discussion/correspondence
  #
  # ##### Constants
  #
  # For the constants defined [here](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L33):
  #
  # ```c
  # // Irrelevant.
  # const long long max_size = 2000;         // max length of strings
  #
  # // Corresponds to the `:neighbors_count` option to {Word2Vec::ReferenceModel#nearest_neighbors}.
  # const long long N = 40;                  // number of closest words that will be shown
  #
  # // Irrelevant.
  # const long long max_w = 50;              // max length of vocabulary entries
  # ```
  #
  # ##### Variables
  #
  # For the constants defined [here](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L26-L34):
  #
  # ```c
  # // Short duration scratch variables. Sometimes used as named.
  # long long a, b, c, d;
  #
  # // Used as named. Read from the input file. The number of words in the input file.
  # long long words;
  #
  # // Used as named. Read from the input file. The number of values in each vector.
  # long long size;
  #
  # // Used as named. Read from the input file. A list of all the terms in the input file.
  # char *vocab;
  #
  # // Corresponds to {Word2Vec::ReferenceModel#vectors}. Read from the input file. A list of vectors, one for each term
  # // in `vocab`.
  # float *M;
  #
  # // Irrelevant. Simply ignored when reading from the input file.
  # char ch;
  #
  # // Corresponds to the `magnitude` local defined in {Word2Vec::ReferenceModel#normalize!}.
  # float len;
  #
  # // In the original, this is used to construct `st` [here](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L76-L91).
  # // we simply pass `st` directly to {Word2Vec::ReferenceModel#nearest_neighbors}, so it is not used.
  # char st1[max_size];
  #
  # // Passed as a parameter (as named) to {Word2Vec::ReferenceModel#nearest_neighbors}.
  # char st[100][max_size];
  #
  # // Not needed. The length of `st`.
  # long long cn;
  #
  # // Used as named. The index of each term from `st` in `vectors` (i.e. `M`).
  # long long bi[100];
  #
  # // Used as named. Represents the sum of all of the vectors corresponding to the input terms (`st`).
  # float vec[max_size];
  #
  # // Used as named. Sorted list containing the current best cosine-distances (corresponds to `bestw`).
  # float bestd[N];
  #
  # // Used as named. List containing the current best words (corresponds to `bestd`).
  # char bestw[N][max_size];
  #
  # // Used as named. Scratch variable holding the cosine-distance for a particular word to `vec`.
  # float dist;
  # ```
  #
  class ReferenceModel < Model
    # @private
    SIZE_OF_FLOAT = [1].pack("f").bytesize

    # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L39-L61.
    #
    # @param [String, IO] filename
    # @param [Encoding] encoding
    # @param [Boolean] normalize
    # @param [Boolean] validate_encoding
    #
    # @return [ReferenceModel]
    def self.parse(filename, encoding: Encoding::UTF_8, normalize: true, validate_encoding: false)
      words = size = vocab = vectors = nil

      # (Roughly) corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L33.
      File.open(filename, File::Constants::BINARY | File::Constants::RDONLY, encoding: Encoding::BINARY) do |f|
        words = f.scanf("%d").first or raise ParseError
        size = f.scanf("%d").first or raise ParseError

        vocab = []
        vectors = []

        buffer_size = size * SIZE_OF_FLOAT
        buffer = "\0" * buffer_size
        unpack_format = "f#{size}"

        words.times do
          vocab << f.scanf("%s").first&.force_encoding(encoding) or raise ParseError
          raise ParseError unless f.scanf("%c").first == " "

          f.read(buffer_size, buffer)
          raise ParseError unless buffer.bytesize == buffer_size
          vectors << buffer.unpack(unpack_format)
        end
      end

      # Sanity checks.
      raise ParseError unless vocab.length == words
      raise ParseError if validate_encoding && !vocab.all?(&:valid_encoding?)
      raise ParseError unless vectors.length == words
      raise ParseError unless vectors.all? { |vector| vector.length == size }

      # (Roughly) corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L56-L60, though
      # there it is not optional.
      vectors.each { |vector| normalize!(vector) } if normalize

      new(words, size, vocab, vectors)
    end

    # Should (generally) be constructed using {ReferenceModel.parse}.
    #
    # @param [Integer] words
    # @param [Integer] size
    # @param [Array<String>] vocab
    # @param [Array<Array<Float>>] vectors
    def initialize(words, size, vocab, vectors)
      @words = words
      @size = size
      @vocab = vocab.freeze.each(&:freeze)
      @vectors = vectors.freeze.each(&:freeze)
    end

    # @return [Integer]
    attr_reader :words

    # @return [Integer]
    attr_reader :size

    # @return [Array<String>]
    attr_reader :vocab

    # Corresponds to the [`M` variable](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L33).
    #
    # @return [Array<Array<Float>>]
    attr_reader :vectors

    # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L92-L132.
    #
    # @param [Array<String>] st The search terms. In the original, this is constructed from the
    #   [`st1` variable](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L27)
    #   [here](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L76-L91). In the original, the
    #   `cn` variable corresponds to the length of this array.
    # @param [Integer] neighbors_count Corresponds to the [`N` constant](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L22).
    #
    # @return [Hash<String, Float>]
    def nearest_neighbors(st, neighbors_count: DEFAULT_NEIGHBORS_COUNT)
      raise ArgumentError if st.empty?

      # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L92-L102.
      #
      # @type [Array<Integer>]
      bi = st.map do |term|
        vocab.index(term) or raise QueryError, "Out of dictionary word: #{term}"
      end

      # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L104-L112.
      #
      # @type [Array<Float>]
      vec = Array.new(size, 0.0).tap do |vec|
        # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L105-L108.
        bi.each do |b|
          # XXX: Currently will never happen, but we could change it so it does in the future and the original is
          #   written to [handle it](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L106).
          next if b.nil?

          size.times do |a|
            vec[a] += vectors[b][a]
          end
        end

        # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L109-L112.
        self.class.normalize!(vec)
      end

      #
      # The rest corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L113-L132.
      #

      # @type [Array<Float>]
      bestd = Array.new(neighbors_count, 0.0)
      # @type [Array<String>]
      bestw = Array.new(neighbors_count, nil)

      words.times do |c|
        # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L116-L118.
        next if bi.include?(c)

        # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L119-L120.
        dist = size.times.inject(0) do |memo, a|
          memo + vec[a] * vectors[c][a]
        end

        # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L121-L131.
        neighbors_count.times do |a|
          if dist > bestd[a]
            # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L123-L126.
            (neighbors_count - 1 - a).times do |d_prime|
              d = neighbors_count - 1 - d_prime

              bestd[d] = bestd[d - 1]
              bestw[d] = bestw[d - 1]
            end

            # Corresponds to https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c#L127-L129.
            bestd[a] = dist
            bestw[a] = vocab[c]
            break
          end
        end
      end

      bestw.zip(bestd).to_h
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
