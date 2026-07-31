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
    int j, rc;

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
    for (j = 0; j < CSDID_MT_N; ++j) {
        rc = SF_mat_el((char *)state_matrix, 1, j + 2, &value);
        if (rc) return rc;
        if (SF_is_missing(value) || value < 0.0 || value > 4294967295.0 ||
            value != floor(value)) {
            SF_error("csdid bootstrap plugin: RNG state payload is invalid\n");
            return 498;
        }
        rng->state[j] = (uint32_t)value;
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
    unsigned char *active = NULL;
    int b, bit, j, obs, rc;
    int effects, integers_per_draw;
    size_t influence_count;
    uint32_t current;
    double value, sign, scale;
    long double sumsq;

    if (use_variables) {
        effects = SF_nvars();
        if (effects < 1 || SF_in1() < 1 || SF_in2() - SF_in1() + 1 < observations) {
            SF_error("csdid bootstrap plugin: influence-function variables have unexpected dimensions\n");
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

    if ((size_t)effects > SIZE_MAX / (size_t)observations) {
        SF_error("csdid bootstrap plugin: influence-function dimensions overflow address space\n");
        return 909;
    }
    influence_count = (size_t)observations * (size_t)effects;
    if (influence_count > SIZE_MAX / sizeof(double)) {
        SF_error("csdid bootstrap plugin: influence-function allocation is too large\n");
        return 909;
    }

    influence = (double *)malloc(influence_count * sizeof(double));
    sums = (double *)malloc((size_t)effects * sizeof(double));
    active = (unsigned char *)malloc((size_t)effects);
    if (!influence || !sums || !active) {
        SF_error("csdid bootstrap plugin: memory allocation failed\n");
        rc = 909;
        goto cleanup;
    }

    for (j = 0; j < effects; ++j) {
        active[j] = 1;
        sumsq = 0.0L;
        for (obs = 0; obs < observations; ++obs) {
            if (use_variables) {
                rc = SF_vdata(j + 1, SF_in1() + obs, &value);
            }
            else {
                rc = SF_mat_el((char *)input_matrix, obs + 1, j + 1, &value);
            }
            if (rc) goto cleanup;
            influence[(size_t)obs * (size_t)effects + (size_t)j] = value;
            if (SF_is_missing(value)) {
                active[j] = 0;
            }
            else {
                sumsq += (long double)value * (long double)value;
            }
        }
        if (!active[j] || sumsq <= 1.4901161193847656e-7L) {
            active[j] = 0;
        }
    }

    integers_per_draw = (observations - 1) / 31 + 1;
    scale = 1.0 / sqrt((double)observations);
    for (b = 0; b < repetitions; ++b) {
        if (SF_poll()) {
            rc = 1;
            goto cleanup;
        }
        memset(sums, 0, (size_t)effects * sizeof(double));
        obs = 0;
        for (int integer_index = 0; integer_index < integers_per_draw; ++integer_index) {
            current = csdid_bmisc_integer(rng);
            for (bit = 30; bit >= 0 && obs < observations; --bit, ++obs) {
                sign = ((current >> bit) & UINT32_C(1)) ? 1.0 : -1.0;
                for (j = 0; j < effects; ++j) {
                    if (active[j]) {
                        sums[j] += sign * influence[(size_t)obs * (size_t)effects + (size_t)j];
                    }
                }
            }
        }
        for (j = 0; j < effects; ++j) {
            value = active[j] ? sums[j] * scale : 0.0;
            rc = SF_mat_store((char *)output_matrix, b + 1, j + 1, value);
            if (rc) goto cleanup;
        }
    }

    rc = csdid_store_state(state_matrix, rng);

cleanup:
    free(active);
    free(sums);
    free(influence);
    return rc;
}

static int csdid_run_bootstrap(int argc, char *argv[])
{
    csdid_mt_state rng;
    int seed, repetitions, observations, rc;

    if (argc != 6) {
        SF_error("csdid bootstrap plugin: bootstrap task expects seed, repetitions, observations, input matrix, output matrix, and state matrix\n");
        return 198;
    }
    if ((rc = csdid_parse_positive_int(argv[0], "seed", &seed)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[1], "repetitions", &repetitions)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[2], "observations", &observations)) != 0) return rc;
    csdid_mt_init(&rng, (uint32_t)seed);
    return csdid_run_bootstrap_core(
        repetitions, observations, argv[3], argv[4], argv[5], &rng, 0);
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
    unsigned char *active = NULL;
    const char *independent_matrix;
    const char *common_matrix;
    const char *state_matrix;
    const char *input_matrix = NULL;
    int repetitions, observations, cband, effects, effect_count;
    int use_variables;
    int b, bit, j, obs, integer_index, integers_per_draw, rc = 0;
    size_t influence_count;
    uint32_t current;
    double value, sign, scale;
    long double sumsq;

    if (argc != 6 && argc != 7) {
        SF_error("csdid bootstrap plugin: aggregate bootstrap expects repetitions, observations, cband, optional input matrix, independent matrix, common matrix, and state matrix\n");
        return 198;
    }
    use_variables = (argc == 6);
    if ((rc = csdid_parse_positive_int(argv[0], "repetitions", &repetitions)) != 0) return rc;
    if ((rc = csdid_parse_positive_int(argv[1], "observations", &observations)) != 0) return rc;
    if ((rc = csdid_parse_binary(argv[2], "cband", &cband)) != 0) return rc;
    if (use_variables) {
        independent_matrix = argv[3];
        common_matrix = argv[4];
        state_matrix = argv[5];
        effects = SF_nvars();
    }
    else {
        input_matrix = argv[3];
        independent_matrix = argv[4];
        common_matrix = argv[5];
        state_matrix = argv[6];
        effects = SF_col((char *)input_matrix);
    }
    effect_count = effects - 1;

    if (effects < 2 ||
        (use_variables &&
         (SF_in1() < 1 || SF_in2() - SF_in1() + 1 < observations)) ||
        (!use_variables && SF_row((char *)input_matrix) != observations)) {
        SF_error("csdid bootstrap plugin: aggregate influence-function variables have unexpected dimensions\n");
        return 503;
    }
    if (SF_row((char *)independent_matrix) != repetitions ||
        SF_col((char *)independent_matrix) != effects ||
        SF_row((char *)common_matrix) != repetitions ||
        SF_col((char *)common_matrix) != effect_count) {
        SF_error("csdid bootstrap plugin: aggregate bootstrap output matrices have unexpected dimensions\n");
        return 503;
    }
    if ((size_t)effects > SIZE_MAX / (size_t)observations) {
        SF_error("csdid bootstrap plugin: aggregate influence-function dimensions overflow address space\n");
        return 909;
    }
    influence_count = (size_t)observations * (size_t)effects;
    if (influence_count > SIZE_MAX / sizeof(double)) {
        SF_error("csdid bootstrap plugin: aggregate influence-function allocation is too large\n");
        return 909;
    }

    influence = (double *)malloc(influence_count * sizeof(double));
    sums = (double *)malloc((size_t)effects * sizeof(double));
    active = (unsigned char *)malloc((size_t)effects);
    if (!influence || !sums || !active) {
        SF_error("csdid bootstrap plugin: aggregate bootstrap memory allocation failed\n");
        rc = 909;
        goto cleanup;
    }

    for (j = 0; j < effects; ++j) {
        active[j] = 1;
        sumsq = 0.0L;
        for (obs = 0; obs < observations; ++obs) {
            if (use_variables) {
                rc = SF_vdata(j + 1, SF_in1() + obs, &value);
            }
            else {
                rc = SF_mat_el((char *)input_matrix, obs + 1, j + 1, &value);
            }
            if (rc) goto cleanup;
            influence[(size_t)obs * (size_t)effects + (size_t)j] = value;
            if (SF_is_missing(value)) {
                active[j] = 0;
            }
            else {
                sumsq += (long double)value * (long double)value;
            }
        }
        if (!active[j] || sumsq <= 1.4901161193847656e-7L) active[j] = 0;
    }

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

    /* Simultaneous bands use one common stream across event effects. */
    if (cband) {
        for (b = 0; b < repetitions; ++b) {
            if (SF_poll()) {
                rc = 1;
                goto cleanup;
            }
            memset(sums, 0, (size_t)effects * sizeof(double));
            obs = 0;
            for (integer_index = 0; integer_index < integers_per_draw; ++integer_index) {
                current = csdid_bmisc_integer(&rng);
                for (bit = 30; bit >= 0 && obs < observations; --bit, ++obs) {
                    sign = ((current >> bit) & UINT32_C(1)) ? 1.0 : -1.0;
                    for (j = 0; j < effect_count; ++j) {
                        if (active[j]) {
                            sums[j] += sign * influence[(size_t)obs * (size_t)effects + (size_t)j];
                        }
                    }
                }
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
    if (strcmp(argv[0], "bootstrap") == 0) {
        return csdid_run_bootstrap(argc - 1, argv + 1);
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
    if (strcmp(argv[0], "bootstrap_agg") == 0) {
        return csdid_run_bootstrap_agg_vars(argc - 1, argv + 1);
    }
    SF_error("csdid bootstrap plugin: unknown task\n");
    return 198;
}
