//
// **N.B.**: This is not the greatest set of C-bindings ever created, further complicated by the fact that `word2vec`'s
//   [`distance`](https://github.com/makeshifthoop/word2vec/blob/0733bf26/src/distance.c) which they are translated from
//   is not flawless.
//

#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include <ruby.h>
#include <ruby/io.h>

static inline bool normalize_vector(float *vector, size_t length) {
  float sum = 0.0;
  float magnitude;

  for (size_t i = 0; i < length; i++) {
    sum += vector[i] * vector[i];
  }

  if (sum <= 0.0) {
    return false;
  }

  magnitude = sqrt(sum);

  for (size_t i = 0; i < length; i++) {
    vector[i] /= magnitude;
  }

  return true;
}

//
// Once one of these structures is successfully created (currently only by `native_model_parse`), then it should be
// assumed that all the members are "valid", i.e., other than in `native_model_deallocate` and the afore mentioned
// `native_model_parse`, any instances should meet (at least) the following conditions:
//
// 1.  `size_t` fields should be non-zero.
// 2.  Array fields should by non-NULL and point to memory allocations of the appropriate size.
// 3.  C-strings (e.g. `vocabulary` entries) should be properly allocated and NULL-terminated (possibly "prematurely" in
//     the case of malformed input, but we just treat them as standard C-strings).
//
typedef struct word2vec_model_s {
  size_t vocabulary_length;
  char **vocabulary;  // char *[vocabulary_length]
  size_t vector_dimensionality;
  float *vectors;  // float[vocabulary_length][vector_dimensionality]
} word2vec_model;

static ssize_t word2vec_model_index(const word2vec_model *model, const char *word) {
  for (size_t i = 0; i < model->vocabulary_length; i++) {
    if (strcmp(word, model->vocabulary[i]) == 0) {
      return i;
    }
  }

  return -1;
}

typedef struct word2vec_model_nearest_neighbor_result_s {
  ssize_t word_index;
  float score;
} word2vec_model_nearest_neighbor_result;

static bool word2vec_model_nearest_neighbors(
  const word2vec_model *model,
  size_t search_terms_count,
  size_t search_terms_indicies[],
  size_t neighbors_count,
  word2vec_model_nearest_neighbor_result top_n_neighbors[]
) {
  if (search_terms_count <= 0 || neighbors_count <= 0) {
    return false;
  }

  for (size_t i = 0; i < neighbors_count; i++) {
    top_n_neighbors[i].word_index = -1;
    top_n_neighbors[i].score = 0.0;
  }

  float search_vector[model->vector_dimensionality];
  for (size_t i = 0; i < model->vector_dimensionality; i++) {
    search_vector[i] = 0.0;
  }
  for (size_t i = 0; i < search_terms_count; i++) {
    const float *vector = model->vectors + search_terms_indicies[i] * model->vector_dimensionality;

    for (size_t j = 0; j < model->vector_dimensionality; j++) {
      search_vector[j] += vector[j];
    }
  }
  if (!normalize_vector(search_vector, model->vector_dimensionality)) {
    return false;
  }

  for (size_t i = 0; i < model->vocabulary_length; i++) {
    for (size_t j = 0; j < search_terms_count; j++) {
      if (search_terms_indicies[j] == i) {
        goto continue_outer;
      }
    }

    float score = 0.0;
    const float *vector = model->vectors + i * model->vector_dimensionality;

    for (size_t j = 0; j < model->vector_dimensionality; j++) {
      score += search_vector[j] * vector[j];
    }

    for (size_t j = 0; j < neighbors_count; j++) {
      if (score > top_n_neighbors[j].score) {
        for (size_t k = neighbors_count - 1; k > j; k--) {
          top_n_neighbors[k].score = top_n_neighbors[k - 1].score;
          top_n_neighbors[k].word_index = top_n_neighbors[k - 1].word_index;
        }

        top_n_neighbors[j].score = score;
        top_n_neighbors[j].word_index = i;

        break;
      }
    }

    continue_outer: ;
  }

  return true;
}

static VALUE rb_eWord2VecParseError;
static VALUE rb_eWord2VecQueryError;

static ID rb_idAtVectors;
static ID rb_idAtVocabulary;
static ID rb_idDefaultNeighborsCount;
static ID rb_idIndex;
static VALUE rb_symIndexDirect;
static VALUE rb_symNeighborsCount;

static void native_model_deallocate(word2vec_model *model) {
  if (model != NULL) {
    if (model->vocabulary != NULL) {
      for(size_t i = 0; i < model->vocabulary_length; i++) {
        if (model->vocabulary[i] != NULL) {
          xfree(model->vocabulary[i]);
        }
      }

      xfree(model->vocabulary);
    }

    if (model->vectors != NULL) {
      xfree(model->vectors);
    }

    xfree(model);
  }
}

#define native_model_parse_fail do {                                                                                   \
  native_model_deallocate(model);                                                                                      \
  rb_raise(rb_eWord2VecParseError, "Parse error.");                                                                    \
} while (0)

//
// N.B.: If the input is not UTF-8 (or is otherwise malformed), then the resulting `word` may contain `\0` characters.
//
// Alternatively could do e.g.:
//
//     // Excluding '\0' terminator.
//     #define MAX_STRING_LENGTH 254
//
//     #define _STR(x) #x
//     #define STR(x) _STR(x)
//
//     // ...
//
//     model->vocabulary[i] = ZALLOC_N(char, MAX_STRING_LENGTH + 1);
//     if (fscanf(f, "%" STR(MAX_STRING_LENGTH) "s%c", model->vocabulary[i], &sep) != 2 || sep != ' ') {
//
// but this seems cleaner.
//
static inline bool native_model_parse_read_vocabulary_word(FILE *f, char **word) {
  size_t dummy_sz = 0;
  ssize_t res;

  // Read the new vocab word.
  if ((res = getdelim(word, &dummy_sz, ' ', f)) < 2) {
    return false;
  }

  // REVIEW: Check for any `\0` characters? The tokenizer _should_ handle it, as (AFAIK) it can't appear in (printing)
  //   UTF-8 characters.

  // Get rid of the trailing space.
  if ((*word)[res - 1] != ' ') {
    return false;
  }
  (*word)[res - 1] = '\0';

  return true;
}

/*
 * @overload parse(io, options)
 *   @param [IO] io
 *   @param [Hash] options
 *
 * @return [Word2Vec::NativeModel]
 */
static VALUE native_model_parse(int argc, VALUE* argv, VALUE self) {
  word2vec_model *model;
  VALUE rb_io;
  VALUE rb_options;  // XXX: Currently not used.
  FILE *f;

  rb_scan_args(argc, argv, "1:", &rb_io, &rb_options);

  Check_Type(rb_io, T_FILE);
  f = rb_io_stdio_file(RFILE(rb_io)->fptr);

  model = ZALLOC(word2vec_model);

  if (fscanf(f, "%zu%zu", &model->vocabulary_length, &model->vector_dimensionality) != 2) {
    native_model_parse_fail;
  }

  if (fgetc(f) != '\n') {
    native_model_parse_fail;
  }

  // Probably not _necessary_, but since such a model would be totally pointless, remove any potential complications.
  if (model->vocabulary_length <= 0 || model->vector_dimensionality <= 0) {
    native_model_parse_fail;
  }

  model->vocabulary = ZALLOC_N(char *, model->vocabulary_length);
  model->vectors = ALLOC_N(float, model->vocabulary_length * model->vector_dimensionality);

  for (size_t i = 0; i < model->vocabulary_length; i++) {
    float *vector = model->vectors + i * model->vector_dimensionality;

    if (!native_model_parse_read_vocabulary_word(f, &model->vocabulary[i])) {
      native_model_parse_fail;
    }

    if (fread(vector, sizeof(float), model->vector_dimensionality, f) != model->vector_dimensionality) {
      native_model_parse_fail;
    }

    if (fgetc(f) != '\n') {
      native_model_parse_fail;
    }

    if (!normalize_vector(vector, model->vector_dimensionality)) {
      native_model_parse_fail;
    }
  }

  return Data_Wrap_Struct(self, NULL, native_model_deallocate, model);
}

/*
 * An implementation of {#index}.
 *
 * @note When a single instance will be used to look up more than a small number of words, it will generally be more
 *   efficient to use {#index_mapped}.
 *
 * @overload index_direct(word)
 *   @param [String] word
 *
 * @return [Integer, nil]
 */
static VALUE native_model_index_direct(VALUE self, VALUE rb_word)
{
  word2vec_model *model;
  ssize_t ret;
  char *word;

  Data_Get_Struct(self, word2vec_model, model);
  word = StringValueCStr(rb_word);

  ret = word2vec_model_index(model, word);

  if (ret < 0) {
    return Qnil;
  } else {
    return SSIZET2NUM(ret);
  }
}

/*
 * @overload nearest_neighbors(search_terms, index_direct: false, neighbors_count: DEFAULT_NEIGHBORS_COUNT)
 *   @param [Array<String>] search_terms
 *   @param [Boolean] :index_direct Will use {#index_direct} if set; {#index} otherwise.
 *   @param [Integer] :neighbors_count
 *
 * @return [Hash<String, Float>]
 */
static VALUE native_model_nearest_neighbors(int argc, VALUE* argv, VALUE self) {
  //////////////////////////////////////////////////////////////////////////////
  // Parse the arguments.
  word2vec_model *model;
  VALUE rb_search_terms;
  VALUE rb_options;
  VALUE rb_neighbors_count;
  ssize_t search_terms_count;
  bool index_direct_flag;
  ssize_t neighbors_count;

  Data_Get_Struct(self, word2vec_model, model);

  rb_scan_args(argc, argv, "1:", &rb_search_terms, &rb_options);

  Check_Type(rb_search_terms, T_ARRAY);
  search_terms_count = RARRAY_LEN(rb_search_terms);
  if (search_terms_count <= 0) {
    rb_raise(rb_eArgError, "search_terms may not be empty");
  }
  for (ssize_t i = 0; i < search_terms_count; i++) {
    Check_Type(rb_ary_entry(rb_search_terms, i), T_STRING);
  }

  if (NIL_P(rb_options)) {
    rb_options = rb_hash_new();
  }
  Check_Type(rb_options, T_HASH);

  index_direct_flag = RTEST(rb_hash_lookup(rb_options, rb_symIndexDirect));

  rb_neighbors_count = rb_hash_lookup(rb_options, rb_symNeighborsCount);
  if (NIL_P(rb_neighbors_count)) {
    rb_neighbors_count = rb_const_get_from(rb_obj_class(self), rb_idDefaultNeighborsCount);
  }
  Check_Type(rb_neighbors_count, T_FIXNUM);
  neighbors_count = NUM2SSIZET(rb_neighbors_count);
  if (neighbors_count <= 0) {
    rb_raise(rb_eArgError, ":neighbors_count must be greater than 0");
  }

  //////////////////////////////////////////////////////////////////////////////
  // Main logic.

  size_t search_terms_indicies[search_terms_count];
  word2vec_model_nearest_neighbor_result neighbors[neighbors_count];

  for (ssize_t i = 0; i < search_terms_count; i++) {
    VALUE rb_term = rb_ary_entry(rb_search_terms, i);
    VALUE rb_index;

    if (index_direct_flag) {
      rb_index = native_model_index_direct(self, rb_term);
    } else {
      rb_index = rb_funcall(self, rb_idIndex, 1, rb_term);
    }

    if (NIL_P(rb_index)) {
      rb_raise(rb_eWord2VecQueryError, "Query error.");
    }

    search_terms_indicies[i] = NUM2SIZET(rb_index);
  }

  // OPTIMIZE: If we want to make this multi-threaded, this call should be made via `rb_thread_call_without_gvl`, but
  //   for now leaving as is until it becomes a bottleneck.
  if (!word2vec_model_nearest_neighbors(model, search_terms_count, search_terms_indicies, neighbors_count, neighbors)) {
    rb_raise(rb_eWord2VecQueryError, "Query error.");
  }

  VALUE rb_ret = rb_hash_new();

  for (ssize_t i = 0; i < neighbors_count; i++) {
    ssize_t word_index = neighbors[i].word_index;

    if (word_index >= 0) {
      // OPTIMIZE: Potentially we could pull the string out of `native_model_vocabulary` and thus avoid an allocation.
      VALUE rb_word = rb_str_freeze(rb_utf8_str_new_cstr(model->vocabulary[word_index]));
      VALUE rb_score = DBL2NUM(neighbors[i].score);

      rb_hash_aset(rb_ret, rb_word, rb_score);
    }
  }

  return rb_ret;
}

/*
 * @note Purely for introspective purposes: Returns a _copy_ of the values used in {#nearest_neighbors}.
 *
 * @note This value is lazily-evaluated and memoized.
 *
 * @return [Array<Array<Float>>]
 */
static VALUE native_model_vectors(VALUE self) {
  word2vec_model *model;
  VALUE rb_vectors;

  if (!NIL_P((rb_vectors = rb_ivar_get(self, rb_idAtVectors)))) {
    return rb_vectors;
  }

  Data_Get_Struct(self, word2vec_model, model);

  rb_vectors = rb_ary_new_capa(model->vocabulary_length);

  for (size_t i = 0; i < model->vocabulary_length; i++) {
    const float *vector = model->vectors + i * model->vector_dimensionality;
    VALUE rb_vector = rb_ary_new_capa(model->vector_dimensionality);

    for (size_t j = 0; j < model->vector_dimensionality; j++) {
      rb_ary_store(rb_vector, j, DBL2NUM(vector[j]));
    }

    rb_ary_store(rb_vectors, i, rb_ary_freeze(rb_vector));
  }

  return rb_ivar_set(self, rb_idAtVectors, rb_ary_freeze(rb_vectors));
}

/*
 * @return [Integer]
 */
static VALUE native_model_vector_dimensionality(VALUE self)
{
  word2vec_model *model;

  Data_Get_Struct(self, word2vec_model, model);

  return SIZET2NUM(model->vector_dimensionality);
}

/*
 * @note Purely for introspective purposes: Returns a _copy_ of the values used in {#nearest_neighbors}.
 *
 * @note This value is lazily-evaluated and memoized.
 *
 * @return [Array<String>]
 */
static VALUE native_model_vocabulary(VALUE self) {
  word2vec_model *model;
  VALUE rb_vocabulary;

  if (!NIL_P((rb_vocabulary = rb_ivar_get(self, rb_idAtVocabulary)))) {
    return rb_vocabulary;
  }

  Data_Get_Struct(self, word2vec_model, model);

  rb_vocabulary = rb_ary_new_capa(model->vocabulary_length);

  for (size_t i = 0; i < model->vocabulary_length; i++) {
    rb_ary_store(rb_vocabulary, i, rb_str_freeze(rb_utf8_str_new_cstr(model->vocabulary[i])));
  }

  return rb_ivar_set(self, rb_idAtVocabulary, rb_ary_freeze(rb_vocabulary));
}

/*
 * @return [Integer]
 */
static VALUE native_model_vocabulary_length(VALUE self)
{
  word2vec_model *model;

  Data_Get_Struct(self, word2vec_model, model);

  return SIZET2NUM(model->vocabulary_length);
}

/*
 * Document-class: Word2Vec::NativeModel
 *
 * Minor rewrite of, and `ruby` `C`-bindings for, the `distance` program from [`word2vec`](https://code.google.com/archive/p/word2vec/).
 * This could almost certainly be done with e.g. the [`rb-libsvm`](https://github.com/febeling/rb-libsvm) gem, but,
 * well, YOLO.
 */
void Init_native_model(void) {
  VALUE rb_mWord2Vec;
  VALUE rb_cWord2VecModel;
  VALUE rb_cWord2VecNativeModel;

  rb_idAtVectors = rb_intern("@vectors");
  rb_idAtVocabulary = rb_intern("@vocabulary");
  rb_idDefaultNeighborsCount = rb_intern("DEFAULT_NEIGHBORS_COUNT");
  rb_idIndex = rb_intern("index");
  rb_symIndexDirect = ID2SYM(rb_intern("index_direct"));
  rb_symNeighborsCount = ID2SYM(rb_intern("neighbors_count"));

  rb_require("word2vec/errors");
  rb_require("word2vec/model");
  rb_mWord2Vec = rb_define_module("Word2Vec");
  rb_eWord2VecParseError = rb_const_get(rb_mWord2Vec, rb_intern("ParseError"));
  rb_eWord2VecQueryError = rb_const_get(rb_mWord2Vec, rb_intern("QueryError"));
  rb_cWord2VecModel = rb_define_class_under(rb_mWord2Vec, "Model", rb_cObject);

  rb_cWord2VecNativeModel = rb_define_class_under(rb_mWord2Vec, "NativeModel", rb_cWord2VecModel);

  rb_undef_alloc_func(rb_cWord2VecNativeModel);

  rb_define_singleton_method(rb_cWord2VecNativeModel, "parse", native_model_parse, -1);

  rb_define_method(rb_cWord2VecNativeModel, "index_direct", native_model_index_direct, 1);
  rb_define_method(rb_cWord2VecNativeModel, "nearest_neighbors", native_model_nearest_neighbors, -1);
  rb_define_method(rb_cWord2VecNativeModel, "vectors", native_model_vectors, 0);
  rb_define_method(rb_cWord2VecNativeModel, "vector_dimensionality", native_model_vector_dimensionality, 0);
  rb_define_method(rb_cWord2VecNativeModel, "vocabulary", native_model_vocabulary, 0);
  rb_define_method(rb_cWord2VecNativeModel, "vocabulary_length", native_model_vocabulary_length, 0);
}
