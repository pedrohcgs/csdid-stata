/* Optional multiplier engine; estimator and inference logic remain in Mata. */
#include "stplugin.h"

#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CSDID_MT_N 624
#define CSDID_MT_M 397
#define CSDID_MT_MATRIX_A UINT32_C(0x9908b0df)
#define CSDID_MT_UPPER_MASK UINT32_C(0x80000000)
#define CSDID_MT_LOWER_MASK UINT32_C(0x7fffffff)

typedef struct {
    uint32_t state[CSDID_MT_N];
    int index;
} csdid_mt_state;

/* R's sqrt(.Machine$double.eps) * 10, which is `sqrt(epsilon(1)) * 10' in
   Mata. This threshold MUST track src/mata/csdid.mata's zero_tol: the two
   screens decide the same thing about the same columns. */
#define CSDID_ZERO_TOL 1.4901161193847656e-7

/* Kahan-Babuska-Neumaier compensated summation.

   The degeneracy screen used to accumulate in `long double', which is not one
   type across the release targets: arm64 Darwin makes it a 53-bit double,
   x86_64 and mingw give the x87 64-bit type, aarch64 Linux gives IEEE
   binary128. The universal macOS bundle is built -arch arm64 -arch x86_64, so
   the SAME shipped file evaluated this one threshold at two different
   precisions in its two slices, and none of the four matched the Mata twin,
   which computes the same quantity with quadcross(). Whether a borderline
   influence-function column counted as degenerate could therefore depend on
   which slice the user's machine loaded.

   Compensated summation in plain `double' is identical on every target and is
   far closer to quadcross() than any of those widths. Do not "simplify" this
   back to a wider accumulator: width is the defect, not the cure. */
static void csdid_kbn_add(double *sum, double *comp, double term)
{
    double t = *sum + term;

    if (fabs(*sum) >= fabs(term)) {
        *comp += (*sum - t) + term;
    }
    else {
        *comp += (term - t) + *sum;
    }
    *sum = t;
}

static int csdid_parse_positive_int(const char *text, const char *label, int *out)
{
    char *end = NULL;
    long value;

    errno = 0;
    value = strtol(text, &end, 10);
    if (errno || end == text || *end != '\0' || value < 1 || value > 2147483647L) {
        char message[160];
        snprintf(message, sizeof(message),
                 "csdid bootstrap plugin: %s must be a positive integer\n", label);
        SF_error(message);
        return 198;
    }
    *out = (int)value;
    return 0;
}

static int csdid_parse_binary(const char *text, const char *label, int *out)
{
    if (strcmp(text, "0") == 0) {
        *out = 0;
        return 0;
    }
    if (strcmp(text, "1") == 0) {
        *out = 1;
        return 0;
    }
    {
        char message[160];
        snprintf(message, sizeof(message),
                 "csdid bootstrap plugin: %s must be zero or one\n", label);
        SF_error(message);
    }
    return 198;
}

static void csdid_mt_init(csdid_mt_state *rng, uint32_t seed)
{
    int j;

    for (j = 0; j < 50; ++j) {
        seed = UINT32_C(69069) * seed + UINT32_C(1);
    }
    for (j = 0; j < CSDID_MT_N + 1; ++j) {
        seed = UINT32_C(69069) * seed + UINT32_C(1);
        if (j > 0) {
            rng->state[j - 1] = seed;
        }
    }
    rng->index = CSDID_MT_N;
}

static void csdid_mt_twist(csdid_mt_state *rng)
{
    int k;
    uint32_t y;

    for (k = 0; k < CSDID_MT_N - CSDID_MT_M; ++k) {
        y = (rng->state[k] & CSDID_MT_UPPER_MASK) |
            (rng->state[k + 1] & CSDID_MT_LOWER_MASK);
        rng->state[k] = rng->state[k + CSDID_MT_M] ^ (y >> 1) ^
            ((y & UINT32_C(1)) ? CSDID_MT_MATRIX_A : UINT32_C(0));
    }
    for (; k < CSDID_MT_N - 1; ++k) {
        y = (rng->state[k] & CSDID_MT_UPPER_MASK) |
            (rng->state[k + 1] & CSDID_MT_LOWER_MASK);
        rng->state[k] = rng->state[k + (CSDID_MT_M - CSDID_MT_N)] ^ (y >> 1) ^
            ((y & UINT32_C(1)) ? CSDID_MT_MATRIX_A : UINT32_C(0));
    }
    y = (rng->state[CSDID_MT_N - 1] & CSDID_MT_UPPER_MASK) |
        (rng->state[0] & CSDID_MT_LOWER_MASK);
    rng->state[CSDID_MT_N - 1] = rng->state[CSDID_MT_M - 1] ^ (y >> 1) ^
        ((y & UINT32_C(1)) ? CSDID_MT_MATRIX_A : UINT32_C(0));
    rng->index = 0;
}

static uint32_t csdid_mt_next(csdid_mt_state *rng)
{
    uint32_t y;

    if (rng->index >= CSDID_MT_N) {
        csdid_mt_twist(rng);
    }
    y = rng->state[rng->index++];
    y ^= y >> 11;
    y ^= (y << 7) & UINT32_C(0x9d2c5680);
    y ^= (y << 15) & UINT32_C(0xefc60000);
    y ^= y >> 18;
    return y;
}

static uint32_t csdid_bmisc_integer(csdid_mt_state *rng)
{
    /* The two clamps below transcribe R's fixup() in RNG.c, which guards
       unif_rand() against returning exactly 0 or exactly 1. With this
       generator neither branch can change the returned integer -- the
       multiplier is 2^-32 applied to a 32-bit word, so `uniform' lies in
       [0, 1) and the second branch is unreachable, while the first can only
       replace 0 by a value that still floors to 0. They are kept so the
       correspondence with R is visible and verifiable, not because they are
       live. Do not delete them as dead code, and do not reason about the rest
       of the function as if they could fire. */
    const double scale = 2.3283064365386963e-10;
    double uniform = (double)csdid_mt_next(rng) * scale;

    if (uniform <= 0.0) {
        uniform = 0.5 * 2.328306437080797e-10;
    }
    else if ((1.0 - uniform) <= 0.0) {
        uniform = 1.0 - 0.5 * 2.328306437080797e-10;
    }
    return (uint32_t)floor(uniform * 2147483647.0) + UINT32_C(1);
}

static int csdid_store_state(const char *state_matrix, const csdid_mt_state *rng)
{
    int j, rc;

    if (SF_row((char *)state_matrix) != 1 || SF_col((char *)state_matrix) != 625) {
        SF_error("csdid bootstrap plugin: state matrix must be 1 x 625\n");
        return 503;
    }
    rc = SF_mat_store((char *)state_matrix, 1, 1, (double)rng->index);
    if (rc) return rc;
    for (j = 0; j < CSDID_MT_N; ++j) {
        rc = SF_mat_store((char *)state_matrix, 1, j + 2, (double)rng->state[j]);
        if (rc) return rc;
    }
    return 0;
}

static int csdid_load_state(const char *state_matrix, csdid_mt_state *rng)
{
    double value;
    int j, rc, nonzero;

    if (SF_row((char *)state_matrix) != 1 || SF_col((char *)state_matrix) != 625) {
        SF_error("csdid bootstrap plugin: state matrix must be 1 x 625\n");
        return 503;
    }
    rc = SF_mat_el((char *)state_matrix, 1, 1, &value);
    if (rc) return rc;
    if (SF_is_missing(value) || value < 0.0 || value > 624.0 || value != floor(value)) {
        SF_error("csdid bootstrap plugin: RNG state index is invalid\n");
        return 498;
    }
    rng->index = (int)value;
    nonzero = 0;
    for (j = 0; j < CSDID_MT_N; ++j) {
        rc = SF_mat_el((char *)state_matrix, 1, j + 2, &value);
        if (rc) return rc;
        if (SF_is_missing(value) || value < 0.0 || value > 4294967295.0 ||
            value != floor(value)) {
            SF_error("csdid bootstrap plugin: RNG state payload is invalid\n");
            return 498;
        }
        rng->state[j] = (uint32_t)value;
        if (rng->state[j] != UINT32_C(0)) nonzero = 1;
    }
    /* All zeros is the one ABSORBING state of MT19937: the twist maps it to
       itself, every draw is 0, and csdid_bmisc_integer then returns 1
       forever -- so every replication is identical and the reported standard
       errors come back missing, with nothing raised. R guards this in
       FixupSeeds. Note the caller captures this rc and falls through to the
       Mata bootstrap, which carries the same guard for the same reason. */
    if (!nonzero) {
        SF_error("csdid bootstrap plugin: RNG state payload is all zeros, which is an absorbing state\n");
        return 498;
    }
    return 0;
}

static int csdid_run_integers(int argc, char *argv[])
{
    csdid_mt_state rng;
    int seed, repetitions, integers_per_draw;
    int b, j, rc;
    const char *draw_matrix;
    const char *state_matrix;

    if (argc != 5) {
        SF_error("csdid bootstrap plugin: integers task expects seed, repetitions, integers-per-draw, draw matrix, and state matrix\n");
        return 198;
    }
    if ((rc = csdid_parse_positive_int(argv[0], "seed", &seed)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[1], "repetitions", &repetitions)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[2], "integers per draw", &integers_per_draw)) != 0) return rc;
    draw_matrix = argv[3];
    state_matrix = argv[4];

    if (SF_row((char *)draw_matrix) != repetitions ||
        SF_col((char *)draw_matrix) != integers_per_draw) {
        SF_error("csdid bootstrap plugin: draw matrix has unexpected dimensions\n");
        return 503;
    }
    csdid_mt_init(&rng, (uint32_t)seed);
    for (b = 0; b < repetitions; ++b) {
        if (SF_poll()) return 1;
        for (j = 0; j < integers_per_draw; ++j) {
            rc = SF_mat_store((char *)draw_matrix, b + 1, j + 1,
                              (double)csdid_bmisc_integer(&rng));
            if (rc) {
                SF_error("csdid bootstrap plugin: failed to store compressed draws\n");
                return rc;
            }
        }
    }
    return csdid_store_state(state_matrix, &rng);
}

/* #53. Both tasks read their influence functions and screen out the degenerate
   columns with the same code: the same two overflow guards, the same three
   allocations, the same row-major fill, the same missing-value test, and the
   same compensated sum of squares against the same threshold -- which appeared
   twice as a bare literal before it was named. It was written out twice. One
   copy now.

   `task' only prefixes the diagnostics, so the aggregate task still says which
   task failed. The buffers are handed back even on failure, because the caller
   frees them at its cleanup label and initialises them to NULL. */
static int csdid_read_and_screen(
    int observations,
    int effects,
    const char *input_matrix,
    int use_variables,
    ST_int first_obs,
    const char *task,
    double **influence_out,
    double **sums_out,
    unsigned char **active_out)
{
    double *influence;
    double *sums;
    unsigned char *active;
    double value, sumsq, sumsq_comp;
    size_t influence_count;
    int j, obs, rc;
    char msg[256];

    if ((size_t)effects > SIZE_MAX / (size_t)observations) {
        snprintf(msg, sizeof msg,
                 "csdid bootstrap plugin: %sinfluence-function dimensions overflow address space\n", task);
        SF_error(msg);
        return 909;
    }
    influence_count = (size_t)observations * (size_t)effects;
    if (influence_count > SIZE_MAX / sizeof(double)) {
        snprintf(msg, sizeof msg,
                 "csdid bootstrap plugin: %sinfluence-function allocation is too large\n", task);
        SF_error(msg);
        return 909;
    }

    influence = (double *)malloc(influence_count * sizeof(double));
    sums = (double *)malloc((size_t)effects * sizeof(double));
    active = (unsigned char *)malloc((size_t)effects);
    *influence_out = influence;
    *sums_out = sums;
    *active_out = active;
    if (!influence || !sums || !active) {
        snprintf(msg, sizeof msg,
                 "csdid bootstrap plugin: %smemory allocation failed\n", task);
        SF_error(msg);
        return 909;
    }

    for (j = 0; j < effects; ++j) {
        active[j] = 1;
        sumsq = 0.0;
        sumsq_comp = 0.0;
        for (obs = 0; obs < observations; ++obs) {
            if (use_variables) {
                rc = SF_vdata(j + 1, first_obs + obs, &value);
            }
            else {
                rc = SF_mat_el((char *)input_matrix, obs + 1, j + 1, &value);
            }
            if (rc) return rc;
            influence[(size_t)obs * (size_t)effects + (size_t)j] = value;
            if (SF_is_missing(value)) {
                active[j] = 0;
            }
            else {
                csdid_kbn_add(&sumsq, &sumsq_comp, value * value);
            }
        }
        if (!active[j] || (sumsq + sumsq_comp) <= CSDID_ZERO_TOL) {
            active[j] = 0;
        }
    }
    return 0;
}

static int csdid_run_bootstrap_core(
    int repetitions,
    int observations,
    const char *input_matrix,
    const char *output_matrix,
    const char *state_matrix,
    csdid_mt_state *rng,
    int use_variables)
{
    double *influence = NULL;
    double *sums = NULL;
    double *inf_a = NULL;
    double *sums_a = NULL;
    int *act_idx = NULL;
    unsigned char *active = NULL;
    int b, bit, j, a, obs, rc;
    int effects, integers_per_draw, n_active;
    size_t influence_count;
    uint32_t current;
    double value, sign, scale;
    double sumsq, sumsq_comp;
    /* SF_in1() is a function call and cannot change during the read; it was
       re-evaluated once per element. Only meaningful on the variables path. */
    ST_int first_obs = 0;

    if (use_variables) {
        effects = SF_nvars();
        first_obs = SF_in1();
        /* `!=', not `<'. The old test accepted any range at least
           `observations' wide and then read the first `observations' rows of
           it, so a call made without the `in' restriction silently
           bootstrapped a prefix of the data rather than the rows the
           influence functions describe. The caller always passes
           `in 1/<observations>'. */
        if (effects < 1 || first_obs < 1 || SF_in2() - first_obs + 1 != observations) {
            SF_error("csdid bootstrap plugin: influence-function variables have unexpected dimensions; the observation range must be exactly the number of rows declared\n");
            return 503;
        }
    }
    else {
        effects = SF_col((char *)input_matrix);
        if (SF_row((char *)input_matrix) != observations || effects < 1) {
            SF_error("csdid bootstrap plugin: influence-function matrix has unexpected dimensions\n");
            return 503;
        }
    }
    if (SF_row((char *)output_matrix) != repetitions ||
        SF_col((char *)output_matrix) != effects) {
        SF_error("csdid bootstrap plugin: bootstrap output matrix has unexpected dimensions\n");
        return 503;
    }

    rc = csdid_read_and_screen(observations, effects, input_matrix, use_variables,
                               first_obs, "", &influence, &sums, &active);
    if (rc) goto cleanup;

    /* Compact the SURVIVING columns into their own contiguous buffer.
       The accumulation below is the whole cost of the task -- repetitions x
       observations x effects fused multiply-adds -- and it used to carry an
       `if (active[j])' in the innermost statement. That branch is invariant
       across every draw and every observation, and it is enough to stop a
       compiler vectorizing an otherwise textbook unit-stride reduction.
       Compacting also makes the row segment for one observation contiguous in
       the active columns, so the inner loop walks memory in order instead of
       skipping over dead columns.
       Nothing about the arithmetic changes: the same terms are added in the
       same order, and the inactive columns are still written as exactly 0. */
    n_active = 0;
    for (j = 0; j < effects; ++j) {
        if (active[j]) ++n_active;
    }
    if (n_active > 0) {
        act_idx = (int *)malloc((size_t)n_active * sizeof(int));
        inf_a = (double *)malloc((size_t)observations * (size_t)n_active * sizeof(double));
        sums_a = (double *)malloc((size_t)n_active * sizeof(double));
        if (!act_idx || !inf_a || !sums_a) {
            SF_error("csdid bootstrap plugin: memory allocation failed\n");
            rc = 909;
            goto cleanup;
        }
        a = 0;
        for (j = 0; j < effects; ++j) {
            if (active[j]) act_idx[a++] = j;
        }
        for (obs = 0; obs < observations; ++obs) {
            for (a = 0; a < n_active; ++a) {
                inf_a[(size_t)obs * (size_t)n_active + (size_t)a] =
                    influence[(size_t)obs * (size_t)effects + (size_t)act_idx[a]];
            }
        }
    }

    integers_per_draw = (observations - 1) / 31 + 1;
    scale = 1.0 / sqrt((double)observations);
    for (b = 0; b < repetitions; ++b) {
        if (SF_poll()) {
            rc = 1;
            goto cleanup;
        }
        if (n_active > 0) memset(sums_a, 0, (size_t)n_active * sizeof(double));
        obs = 0;
        for (int integer_index = 0; integer_index < integers_per_draw; ++integer_index) {
            current = csdid_bmisc_integer(rng);
            for (bit = 30; bit >= 0 && obs < observations; --bit, ++obs) {
                const double *row = inf_a + (size_t)obs * (size_t)n_active;
                sign = ((current >> bit) & UINT32_C(1)) ? 1.0 : -1.0;
                for (a = 0; a < n_active; ++a) {
                    sums_a[a] += sign * row[a];
                }
            }
        }
        memset(sums, 0, (size_t)effects * sizeof(double));
        for (a = 0; a < n_active; ++a) {
            sums[act_idx[a]] = sums_a[a];
        }
        for (j = 0; j < effects; ++j) {
            value = active[j] ? sums[j] * scale : 0.0;
            rc = SF_mat_store((char *)output_matrix, b + 1, j + 1, value);
            if (rc) goto cleanup;
        }
    }

    rc = csdid_store_state(state_matrix, rng);

cleanup:
    free(act_idx);
    free(sums_a);
    free(inf_a);
    free(active);
    free(sums);
    free(influence);
    return rc;
}

static int csdid_run_bootstrap_state(int argc, char *argv[])
{
    csdid_mt_state rng;
    int repetitions, observations, rc;

    if (argc != 5) {
        SF_error("csdid bootstrap plugin: bootstrap_state task expects repetitions, observations, input matrix, output matrix, and state matrix\n");
        return 198;
    }
    if ((rc = csdid_parse_positive_int(argv[0], "repetitions", &repetitions)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[1], "observations", &observations)) != 0) return rc;
    if ((rc = csdid_load_state(argv[4], &rng)) != 0) return rc;
    return csdid_run_bootstrap_core(
        repetitions, observations, argv[2], argv[3], argv[4], &rng, 0);
}

static int csdid_run_bootstrap_vars(int argc, char *argv[])
{
    csdid_mt_state rng;
    int repetitions, observations, rc;

    if (argc != 4) {
        SF_error("csdid bootstrap plugin: bootstrap_vars task expects repetitions, observations, output matrix, and state matrix\n");
        return 198;
    }
    if ((rc = csdid_parse_positive_int(argv[0], "repetitions", &repetitions)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[1], "observations", &observations)) != 0) return rc;
    if ((rc = csdid_load_state(argv[3], &rng)) != 0) return rc;
    return csdid_run_bootstrap_core(
        repetitions, observations, NULL, argv[2], argv[3], &rng, 1);
}

static int csdid_run_bootstrap_agg_vars(int argc, char *argv[])
{
    csdid_mt_state rng;
    double *influence = NULL;
    double *sums = NULL;
    double *inf_a = NULL;
    double *sums_a = NULL;
    int *act_idx = NULL;
    unsigned char *active = NULL;
    const char *independent_matrix;
    const char *common_matrix;
    const char *state_matrix;
    int repetitions, observations, cband, effects, effect_count;
    int b, bit, j, a, obs, integer_index, integers_per_draw, rc = 0;
    int n_active = 0;
    /* SF_in1() is a function call, and it was re-evaluated once per element
       of the read loop. It cannot change during the read. */
    ST_int first_obs;
    size_t influence_count;
    uint32_t current;
    double value, sign, scale;
    double sumsq, sumsq_comp;

    /* Arity is the ONLY thing that used to select between the variables path
       and the matrix path, and the dispatcher accepted two task names for
       this one function, so a caller could ask for one task and silently get
       the other's reading of its arguments. There is now one task name and
       one arity: the aggregate influence functions always arrive as
       variables. */
    if (argc != 6) {
        SF_error("csdid bootstrap plugin: bootstrap_agg_vars expects exactly six arguments -- repetitions, observations, cband, independent matrix, common matrix, and state matrix -- with the influence functions passed as variables\n");
        return 198;
    }
    if ((rc = csdid_parse_positive_int(argv[0], "repetitions", &repetitions)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[1], "observations", &observations)) != 0) return rc;
    if ((rc = csdid_parse_binary(argv[2], "cband", &cband)) != 0) return rc;
    independent_matrix = argv[3];
    common_matrix = argv[4];
    state_matrix = argv[5];
    effects = SF_nvars();
    effect_count = effects - 1;

    /* `!=', not `<'. The width test used to accept ANY observation range at
       least `observations' wide and then read the first `observations' rows
       of it, so a call made without an `in' restriction -- or with one the
       caller got wrong -- silently bootstrapped a prefix of the data instead
       of the rows the influence functions describe. The caller now always
       passes `in 1/<observations>', so anything else is a defect and is
       refused. */
    first_obs = SF_in1();
    if (effects < 2 ||
        first_obs < 1 ||
        SF_in2() - first_obs + 1 != observations) {
        SF_error("csdid bootstrap plugin: aggregate influence-function variables have unexpected dimensions; the observation range must be exactly the number of rows declared\n");
        return 503;
    }
    if (SF_row((char *)independent_matrix) != repetitions ||
        SF_col((char *)independent_matrix) != effects ||
        SF_row((char *)common_matrix) != repetitions ||
        SF_col((char *)common_matrix) != effect_count) {
        SF_error("csdid bootstrap plugin: aggregate bootstrap output matrices have unexpected dimensions\n");
        return 503;
    }
    rc = csdid_read_and_screen(observations, effects, NULL, 1,
                               first_obs, "aggregate ", &influence, &sums, &active);
    if (rc) goto cleanup;

    if ((rc = csdid_load_state(state_matrix, &rng)) != 0) goto cleanup;
    integers_per_draw = (observations - 1) / 31 + 1;
    scale = 1.0 / sqrt((double)observations);

    /* R aggregation uses an independent multiplier stream for each effect. */
    for (j = 0; j < effect_count; ++j) {
        for (b = 0; b < repetitions; ++b) {
            if (SF_poll()) {
                rc = 1;
                goto cleanup;
            }
            sums[j] = 0.0;
            obs = 0;
            for (integer_index = 0; integer_index < integers_per_draw; ++integer_index) {
                current = csdid_bmisc_integer(&rng);
                for (bit = 30; bit >= 0 && obs < observations; --bit, ++obs) {
                    if (!active[j]) continue;
                    sign = ((current >> bit) & UINT32_C(1)) ? 1.0 : -1.0;
                    sums[j] += sign * influence[(size_t)obs * (size_t)effects + (size_t)j];
                }
            }
            value = active[j] ? sums[j] * scale : 0.0;
            if ((rc = SF_mat_store((char *)independent_matrix, b + 1, j + 1, value)) != 0) {
                goto cleanup;
            }
        }
    }

    /* Simultaneous bands use one common stream across event effects.

       Same compaction as the estimation core, and for the same reason: this
       is the loop that dominates the task, and the `if (active[j])' in its
       innermost statement is invariant across every draw and every
       observation while being enough to stop the reduction vectorizing. The
       surviving columns of the EVENT block (the first effect_count of them)
       are gathered into a contiguous buffer once, so the inner loop is a
       unit-stride reduction over exactly the columns that contribute.
       Arithmetic is unchanged: same terms, same order, inactive columns still
       written as exactly 0. */
    if (cband) {
        n_active = 0;
        for (j = 0; j < effect_count; ++j) {
            if (active[j]) ++n_active;
        }
        if (n_active > 0) {
            act_idx = (int *)malloc((size_t)n_active * sizeof(int));
            inf_a = (double *)malloc((size_t)observations * (size_t)n_active * sizeof(double));
            sums_a = (double *)malloc((size_t)n_active * sizeof(double));
            if (!act_idx || !inf_a || !sums_a) {
                SF_error("csdid bootstrap plugin: aggregate bootstrap memory allocation failed\n");
                rc = 909;
                goto cleanup;
            }
            a = 0;
            for (j = 0; j < effect_count; ++j) {
                if (active[j]) act_idx[a++] = j;
            }
            for (obs = 0; obs < observations; ++obs) {
                for (a = 0; a < n_active; ++a) {
                    inf_a[(size_t)obs * (size_t)n_active + (size_t)a] =
                        influence[(size_t)obs * (size_t)effects + (size_t)act_idx[a]];
                }
            }
        }
        for (b = 0; b < repetitions; ++b) {
            if (SF_poll()) {
                rc = 1;
                goto cleanup;
            }
            if (n_active > 0) memset(sums_a, 0, (size_t)n_active * sizeof(double));
            obs = 0;
            for (integer_index = 0; integer_index < integers_per_draw; ++integer_index) {
                current = csdid_bmisc_integer(&rng);
                for (bit = 30; bit >= 0 && obs < observations; --bit, ++obs) {
                    const double *row = inf_a + (size_t)obs * (size_t)n_active;
                    sign = ((current >> bit) & UINT32_C(1)) ? 1.0 : -1.0;
                    for (a = 0; a < n_active; ++a) {
                        sums_a[a] += sign * row[a];
                    }
                }
            }
            memset(sums, 0, (size_t)effects * sizeof(double));
            for (a = 0; a < n_active; ++a) {
                sums[act_idx[a]] = sums_a[a];
            }
            for (j = 0; j < effect_count; ++j) {
                value = active[j] ? sums[j] * scale : 0.0;
                if ((rc = SF_mat_store((char *)common_matrix, b + 1, j + 1, value)) != 0) {
                    goto cleanup;
                }
            }
        }
    }

    /* The overall effect follows the common-band stream, matching R order. */
    j = effects - 1;
    for (b = 0; b < repetitions; ++b) {
        if (SF_poll()) {
            rc = 1;
            goto cleanup;
        }
        sums[j] = 0.0;
        obs = 0;
        for (integer_index = 0; integer_index < integers_per_draw; ++integer_index) {
            current = csdid_bmisc_integer(&rng);
            for (bit = 30; bit >= 0 && obs < observations; --bit, ++obs) {
                if (!active[j]) continue;
                sign = ((current >> bit) & UINT32_C(1)) ? 1.0 : -1.0;
                sums[j] += sign * influence[(size_t)obs * (size_t)effects + (size_t)j];
            }
        }
        value = active[j] ? sums[j] * scale : 0.0;
        if ((rc = SF_mat_store((char *)independent_matrix, b + 1, j + 1, value)) != 0) {
            goto cleanup;
        }
    }

    rc = csdid_store_state(state_matrix, &rng);

cleanup:
    free(act_idx);
    free(sums_a);
    free(inf_a);
    free(active);
    free(sums);
    free(influence);
    return rc;
}

STDLL stata_call(int argc, char *argv[])
{
    if (argc < 1) {
        SF_error("csdid bootstrap plugin: missing task\n");
        return 198;
    }
    if (strcmp(argv[0], "integers") == 0) {
        return csdid_run_integers(argc - 1, argv + 1);
    }
    if (strcmp(argv[0], "bootstrap_state") == 0) {
        return csdid_run_bootstrap_state(argc - 1, argv + 1);
    }
    if (strcmp(argv[0], "bootstrap_vars") == 0) {
        return csdid_run_bootstrap_vars(argc - 1, argv + 1);
    }
    if (strcmp(argv[0], "bootstrap_agg_vars") == 0) {
        return csdid_run_bootstrap_agg_vars(argc - 1, argv + 1);
    }
    SF_error("csdid bootstrap plugin: unknown task\n");
    return 198;
}
