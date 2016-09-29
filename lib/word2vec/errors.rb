# frozen_string_literal: true

module Word2Vec
  class Error < StandardError ; end

  class ParseError < Error ; end

  class QueryError < Error ; end
end
