#!/usr/bin/env ruby
#
# frozen_string_literal: true

require "mkmf"

additional_prefixed_cflags = %w(-std=gnu99)
additional_suffixed_cflags = %w(-Wno-declaration-after-statement)
additional_prefixed_ldflags = %w()

#
# Add some additional development-oriented warning flags. Enable by compiling with:
#
#     rake compile -- --enable-development
#
# or, if using with the actual gem (for whatever reason):
#
#     gem install word2vec-ruby -- --enable-development
#
if enable_config("development")
  additional_prefixed_cflags = [*additional_prefixed_cflags, *%w(-Wall -Wextra -Werror)]
end

#
# Use `clang`'s [AddressSanitizer](http://clang.llvm.org/docs/AddressSanitizer.html). Enable by compiling with:
#
#     rake compile -- --enable-address-sanitizer
#
if enable_config("address-sanitizer")
  additional_prefixed_cflags = [*additional_prefixed_cflags, "-fsanitize=address"]
  additional_prefixed_ldflags = [*additional_prefixed_ldflags, "-fsanitize=address"]
end

unless (new_prefixed_cflags = additional_prefixed_cflags - $CFLAGS.split(/\s+/)).empty?
  $CFLAGS.prepend(new_prefixed_cflags.join(" ") << " ")
end

unless (new_suffixed_cflags = additional_suffixed_cflags - $CFLAGS.split(/\s+/)).empty?
  $CFLAGS << " " << new_suffixed_cflags.join(" ")
end

unless (new_prefixed_ldflags = additional_prefixed_ldflags - $LDFLAGS.split(/\s+/)).empty?
  $LDFLAGS.prepend(new_prefixed_ldflags.join(" ") << " ")
end

# Check for the C11 [`getdelim`](http://pubs.opengroup.org/onlinepubs/9699919799/functions/getdelim.html) function.
abort "missing getdelim()" unless have_func("getdelim")

create_makefile "word2vec/native_model"
