from __future__ import annotations

import numpy as np
import pandas as pd
from scipy.special import erfc

from mhw_utilities import (
    Curve,
    add_target_months,
    get_target_df,
    make_schedule,
    solve_root_robust,
    yearfrac,
)


def _prepare_diagonal_case_data(
    ois_curve: Curve,
    diag_summary_df: pd.DataFrame,
) -> dict:
    """
    Prepare the market inputs used by diagonal swaption calibration.

    Extracts expiries, tenors, ATM strikes and market prices from the input
    dataframe, then builds the quarterly floating and annual fixed payment
    schedules starting from the OIS settlement date.

    Inputs:
        ois_curve: OIS curve containing the settlement date.
        diag_summary_df: diagonal swaption market dataframe.

    Outputs:
        dict with market arrays and cached payment schedules.
    """
    mkt = diag_summary_df.copy()
    expiry_years = mkt["ExpiryYears"].to_numpy(dtype=float)
    tenor_years = mkt["TenorYears"].to_numpy(dtype=float)

    # Total maturity of each swaption is expiry plus underlying swap tenor.
    maturity_years = expiry_years + tenor_years

    strike_atm = mkt["StrikeATM"].to_numpy(dtype=float)
    market_prices = mkt["MarketPrice"].to_numpy(dtype=float)
    settle_date = pd.Timestamp(ois_curve.settlementDate).normalize()

    float_pay_cache: list[np.ndarray] = []
    fixed_pay_cache: list[np.ndarray] = []

    for expiry, tenor in zip(expiry_years, tenor_years, strict=True):
        # Swaption expiry date, adjusted according to the TARGET calendar.
        ex_date = add_target_months(
            settle_date,
            int(round(12 * expiry)),
            "modifiedfollow",
        )
        # Final maturity date of the underlying swap.
        mat_date = add_target_months(
            ex_date,
            int(round(12 * tenor)),
            "modifiedfollow",
        )
        # Floating leg schedule: quarterly payments.
        float_sched = make_schedule(ex_date, mat_date, 3, "modifiedfollow")
        # Fixed leg schedule: annual payments.
        fixed_sched = make_schedule(ex_date, mat_date, 12, "modifiedfollow")

        # Exclude the first date because it is the swap start date, not a payment date.
        float_pay_cache.append(float_sched[1:])
        fixed_pay_cache.append(fixed_sched[1:])

    return {
        "expiry_years": expiry_years,
        "tenor_years": tenor_years,
        "maturity_years": maturity_years,
        "strike_atm": strike_atm,
        "market_prices": market_prices,
        "float_pay_cache": float_pay_cache,
        "fixed_pay_cache": fixed_pay_cache,
    }


def _build_case_pricing_cache(
    ois_curve: Curve,
    eur3m_curve: Curve,
    case_data: dict,
) -> dict:
    """
    Build deterministic pricing arrays for one calibration case.

    Discount factors, spreads, coupon coefficients, BPV weights and validity
    masks are stored in rectangular numpy arrays so that all diagonal swaptions
    can be priced together. The cache is saved inside case_data and reused on
    later calls.

    Inputs:
        ois_curve: OIS discount curve.
        eur3m_curve: Euribor 3M pseudo-discount curve.
        case_data: prepared market data and payment schedules.

    Outputs:
        dict with cached pricing matrices, masks and discount quantities.
    """
    # If the cache has already been built, reuse it to avoid repeated computations.
    cached = case_data.get("_pricing_cache")
    if isinstance(cached, dict):
        return cached

    expiry_years = np.asarray(case_data["expiry_years"], dtype=float)
    strike_atm = np.asarray(case_data["strike_atm"], dtype=float)
    float_pay_cache = case_data["float_pay_cache"]
    fixed_pay_cache = case_data["fixed_pay_cache"]

    n = int(expiry_years.size)
    if n <= 0:
        raise ValueError("Empty case_data: no instruments to price.")

    # Number of floating and fixed payment dates for each swaption.
    float_lens = np.asarray([len(x) for x in float_pay_cache], dtype=int)
    fixed_lens = np.asarray([len(x) for x in fixed_pay_cache], dtype=int)

    if np.any(float_lens <= 0) or np.any(fixed_lens <= 0):
        raise ValueError("Each instrument must have at least one floating and fixed payment date.")

    # Maximum dimensions are used to store all instruments in rectangular matrices.
    max_float = int(float_lens.max())
    max_fixed = int(fixed_lens.max())

    p0t_alpha = np.zeros(n, dtype=float)
    t_expiry = np.zeros(n, dtype=float)

    # Masks identify the valid entries in the padded matrices.
    float_mask = np.zeros((n, max_float), dtype=bool)
    fixed_mask = np.zeros((n, max_fixed), dtype=bool)

    # For each fixed payment date, store its corresponding position on the floating grid.
    fixed_idx_mat = np.zeros((n, max_fixed), dtype=int)

    tau_mat = np.zeros((n, max_float + 1), dtype=float)
    balpha_pay_mat = np.zeros((n, max_float), dtype=float)
    balpha_start_mat = np.zeros((n, max_float), dtype=float)
    beta_mat = np.zeros((n, max_float), dtype=float)
    c_mat = np.zeros((n, max_float), dtype=float)
    bpv_weight_mat = np.zeros((n, max_fixed), dtype=float)

    settle_date = pd.Timestamp(ois_curve.settlementDate).normalize()

    for i in range(n):
        # Swaption expiry date for the current instrument.
        ex_date = add_target_months(
            settle_date,
            int(round(12 * expiry_years[i])),
            "modifiedfollow",
        )

        # Convert payment dates to normalized numpy datetime arrays.
        float_dates = (
            pd.to_datetime(np.atleast_1d(float_pay_cache[i]))
            .normalize()
            .to_numpy(dtype="datetime64[ns]")
        )
        fixed_dates = (
            pd.to_datetime(np.atleast_1d(fixed_pay_cache[i]))
            .normalize()
            .to_numpy(dtype="datetime64[ns]")
        )

        n_float = int(float_dates.size)
        n_fixed = int(fixed_dates.size)

        float_mask[i, :n_float] = True
        fixed_mask[i, :n_fixed] = True

        # Map each floating payment date to its index.
        # This is needed because fixed dates must be aligned with the floating grid.
        float_date_to_idx = {pd.Timestamp(d): j for j, d in enumerate(float_dates)}
        fixed_idx = np.empty(n_fixed, dtype=int)

        for k, d in enumerate(fixed_dates):
            d_ts = pd.Timestamp(d)

            if d_ts not in float_date_to_idx:
                raise ValueError("Fixed payment dates must lie on floating grid.")

            fixed_idx[k] = int(float_date_to_idx[d_ts])

        fixed_idx_mat[i, :n_fixed] = fixed_idx

        # Fixed-leg accrual periods start from the expiry date and end at fixed payment dates.
        fixed_accrual_start = np.concatenate(([ex_date], fixed_dates[:-1]))
        fixed_delta = yearfrac(fixed_accrual_start, fixed_dates, 1)

        # OIS discount factors from settlement date to expiry and floating payment dates.
        p0t_alpha_i = float(
            get_target_df(
                settle_date,
                ois_curve.dates,
                ois_curve.zeroRates,
                ex_date,
            )[0]
        )
        p0t_float_i = get_target_df(
            settle_date,
            ois_curve.dates,
            ois_curve.zeroRates,
            float_dates,
        )
        p0t_full_i = np.concatenate(([p0t_alpha_i], p0t_float_i))

        # Euribor 3M pseudo-discount factors on the same dates.
        ptilde_alpha_i = float(
            get_target_df(
                settle_date,
                eur3m_curve.dates,
                eur3m_curve.zeroRates,
                ex_date,
            )[0]
        )
        ptilde_float_i = get_target_df(
            settle_date,
            eur3m_curve.dates,
            eur3m_curve.zeroRates,
            float_dates,
        )
        ptilde_full_i = np.concatenate(([ptilde_alpha_i], ptilde_float_i))

        # Forward OIS discounts from option expiry to each payment date.
        balpha_pay_i = p0t_float_i / p0t_alpha_i

        # Forward OIS discounts from option expiry to each floating-period start date.
        balpha_start_i = p0t_full_i[:-1] / p0t_alpha_i

        # Multiplicative spread between OIS forward discounts and Euribor pseudo-discounts.
        beta_i = (p0t_full_i[1:] / p0t_full_i[:-1]) / (
            ptilde_full_i[1:] / ptilde_full_i[:-1]
        )

        # Fixed-leg cash-flow coefficients placed on the floating grid.
        c_i = np.zeros(n_float, dtype=float)
        c_i[fixed_idx] = strike_atm[i] * fixed_delta

        # The last fixed cash flow also includes the unit notional redemption.
        c_i[fixed_idx[-1]] = 1.0 + strike_atm[i] * fixed_delta[-1]

        # Time distances from option expiry to floating dates.
        tau_i = yearfrac(ex_date, np.concatenate(([ex_date], float_dates)), 3)

        # Option expiry time measured from settlement date.
        t_expiry_i = float(yearfrac(settle_date, ex_date, 3)[0])

        p0t_alpha[i] = p0t_alpha_i
        t_expiry[i] = t_expiry_i

        tau_mat[i, : n_float + 1] = tau_i
        balpha_pay_mat[i, :n_float] = balpha_pay_i
        balpha_start_mat[i, :n_float] = balpha_start_i
        beta_mat[i, :n_float] = beta_i
        c_mat[i, :n_float] = c_i

        # BPV weights of the fixed leg, used later for forward swap-rate calculations.
        bpv_weight_mat[i, :n_fixed] = fixed_delta * balpha_pay_i[fixed_idx]

    cache = {
        "n": n,
        "float_lens": float_lens,
        "fixed_lens": fixed_lens,
        "float_mask": float_mask,
        "fixed_mask": fixed_mask,
        "fixed_idx_mat": fixed_idx_mat,
        "p0t_alpha": p0t_alpha,
        "t_expiry": t_expiry,
        "tau_mat": tau_mat,
        "balpha_pay_mat": balpha_pay_mat,
        "balpha_start_mat": balpha_start_mat,
        "beta_mat": beta_mat,
        "c_mat": c_mat,
        "bpv_weight_mat": bpv_weight_mat,
    }

    # Store the cache inside case_data so future calls can reuse it.
    case_data["_pricing_cache"] = cache

    return cache


def _cash_annuity_vectorized(
    s_val: np.ndarray,
    n_tenor: np.ndarray,
) -> np.ndarray:
    """
    Compute the cash-settlement annuity for swap rates and tenors.

    Applies the standard annuity formula element-wise and uses the analytical
    near-zero rate limit to avoid numerical instability.

    Inputs:
        s_val: swap-rate array.
        n_tenor: tenor array in years.

    Outputs:
        array of cash annuity values.
    """
    s_val = np.asarray(s_val, dtype=float)
    n_tenor = np.asarray(n_tenor, dtype=float)

    out = np.full_like(s_val, np.nan, dtype=float)
    invalid = s_val <= -1.0

    # Near-zero rates require a special treatment to avoid division by zero.
    near_zero = np.abs(s_val) < 1e-10
    # Standard formula can be safely applied elsewhere.
    regular = ~(invalid | near_zero)
    # Limiting value of the annuity when the swap rate tends to zero.
    out[near_zero] = n_tenor[near_zero]

    with np.errstate(over="ignore", invalid="ignore", under="ignore", divide="ignore"):
        out[regular] = (
            1.0
            - np.power(1.0 + s_val[regular], -n_tenor[regular])
        ) / s_val[regular]

    return out


def _model_prices_from_case_data(
    ois_curve: Curve,
    eur3m_curve: Curve,
    case_data: dict,
    a: float,
    b: float,
    gamma: float,
    is_payer: bool,
    is_cs: bool,
) -> np.ndarray:
    """
    Price all swaptions contained in a prepared diagonal case.

    Uses the cached schedules and discount quantities to evaluate the MHW
    model for a given (a, b, gamma). Physical-delivery swaptions use the
    closed-form expression, while cash-settled swaptions are integrated over
    the Gaussian factor.

    Inputs:
        ois_curve: OIS discount curve.
        eur3m_curve: Euribor 3M pseudo-discount curve.
        case_data: prepared market data and cached schedules.
        a, b, gamma: MHW model parameters.
        is_payer: True for payer swaptions.
        is_cs: True for cash-settled swaptions.

    Outputs:
        numpy array with one model price per instrument.
    """
    cache = _build_case_pricing_cache(ois_curve, eur3m_curve, case_data)

    n = int(cache["n"])
    float_lens = cache["float_lens"]
    fixed_lens = cache["fixed_lens"]
    float_mask = cache["float_mask"]
    fixed_mask = cache["fixed_mask"]
    fixed_idx_mat = cache["fixed_idx_mat"]

    p0t_alpha = cache["p0t_alpha"]
    t_expiry = cache["t_expiry"]
    tau_mat = cache["tau_mat"]
    balpha_pay_mat = cache["balpha_pay_mat"]
    balpha_start_mat = cache["balpha_start_mat"]
    beta_mat = cache["beta_mat"]
    c_mat = cache["c_mat"]
    bpv_weight_mat = cache["bpv_weight_mat"]

    # Compute the Gaussian-factor volatility terms of the MHW model.
    with np.errstate(over="ignore", invalid="ignore", under="ignore", divide="ignore"):
        if abs(a) > 1e-14:
            zeta2 = b * b * (1.0 - np.exp(-2.0 * a * t_expiry)) / (2.0 * a)
            v_mat = np.sqrt(np.maximum(zeta2, 0.0))[:, None] * (1.0 - np.exp(-a * tau_mat)) / a
        else:
            zeta2 = b * b * t_expiry
            v_mat = np.sqrt(np.maximum(zeta2, 0.0))[:, None] * tau_mat

    varsigma_mat = (1.0 - gamma) * v_mat[:, 1:]
    nu_mat = v_mat[:, :-1] - gamma * v_mat[:, 1:]

    varsigma_mat = np.where(float_mask, varsigma_mat, 0.0)
    nu_mat = np.where(float_mask, nu_mat, 0.0)

    exp_clip = 700.0
    x_star = np.zeros(n, dtype=float)

    # Solve the exercise-boundary equation for each swaption.
    for i in range(n):
        n_float = int(float_lens[i])
        row_slice = slice(0, n_float)
        row_slice_m1 = slice(0, max(n_float - 1, 0))

        varsigma_i = varsigma_mat[i, row_slice]
        nu_i = nu_mat[i, row_slice]

        a1_i = c_mat[i, row_slice] * balpha_pay_mat[i, row_slice] * np.exp(-0.5 * varsigma_i * varsigma_i)
        a2_i = balpha_start_mat[i, 1:n_float] * np.exp(
            -0.5 * varsigma_i[row_slice_m1] * varsigma_i[row_slice_m1]
        )
        a3_i = beta_mat[i, row_slice] * balpha_start_mat[i, row_slice] * np.exp(-0.5 * nu_i * nu_i)

        def f_of_x(x):
            with np.errstate(over="ignore", invalid="ignore", under="ignore"):
                e1 = np.exp(np.clip(-varsigma_i * x, -exp_clip, exp_clip))
                e2 = np.exp(np.clip(-varsigma_i[row_slice_m1] * x, -exp_clip, exp_clip))
                e3 = np.exp(np.clip(-nu_i * x, -exp_clip, exp_clip))
                val = np.sum(a1_i * e1) + np.sum(a2_i * e2) - np.sum(a3_i * e3)

            if not np.isfinite(val):
                return np.nan

            return float(val)

        x_star[i] = solve_root_robust(f_of_x)

    x_col = x_star[:, None]
    n_cdf = lambda z: 0.5 * erfc(-z / np.sqrt(2.0))

    # Physical-delivery swaption pricing.
    if not is_cs:
        with np.errstate(over="ignore", invalid="ignore", under="ignore"):
            n1 = n_cdf(x_col + varsigma_mat)
            n2 = n_cdf(x_col + varsigma_mat[:, :-1])
            n3 = n_cdf(x_col + nu_mat)

            sum1 = np.sum(np.where(float_mask, c_mat * balpha_pay_mat * n1, 0.0), axis=1)
            sum2 = np.sum(np.where(float_mask[:, 1:], balpha_start_mat[:, 1:] * n2, 0.0), axis=1)
            sum3 = np.sum(np.where(float_mask, beta_mat * balpha_start_mat * n3, 0.0), axis=1)

            receiver_price = p0t_alpha * (sum1 + sum2 - sum3)

            bpv0 = np.sum(np.where(fixed_mask, bpv_weight_mat, 0.0), axis=1)
            last_float_idx = float_lens - 1
            balpha_last = balpha_pay_mat[np.arange(n), last_float_idx]

            num0 = 1.0 - balpha_last + np.sum(
                np.where(float_mask, balpha_start_mat * (beta_mat - 1.0), 0.0),
                axis=1,
            )

            if is_payer:
                return receiver_price + p0t_alpha * (num0 - case_data["strike_atm"] * bpv0)

            return receiver_price

    n_pts = 2000

    # Cash-settled swaptions are priced by numerical integration over the Gaussian factor.
    if is_payer:
        x_grid = x_col + np.linspace(0.0, 40.0, n_pts, dtype=float)[None, :]
    else:
        x_grid = x_col - 40.0 + np.linspace(0.0, 40.0, n_pts, dtype=float)[None, :]

    with np.errstate(over="ignore", invalid="ignore", under="ignore", divide="ignore"):
        phi = np.exp(-0.5 * x_grid * x_grid) / np.sqrt(2.0 * np.pi)

        arg_num_beta = np.clip(
            -nu_mat[:, :, None] * x_grid[:, None, :] - 0.5 * nu_mat[:, :, None] * nu_mat[:, :, None],
            -exp_clip,
            exp_clip,
        )
        arg_num_b = np.clip(
            -varsigma_mat[:, :, None] * x_grid[:, None, :]
            - 0.5 * varsigma_mat[:, :, None] * varsigma_mat[:, :, None],
            -exp_clip,
            exp_clip,
        )

        num_beta = np.sum(
            np.where(float_mask[:, :, None], (beta_mat * balpha_start_mat)[:, :, None] * np.exp(arg_num_beta), 0.0),
            axis=1,
        )
        num_b = np.sum(
            np.where(float_mask[:, :, None], balpha_pay_mat[:, :, None] * np.exp(arg_num_b), 0.0),
            axis=1,
        )

        fixed_idx_safe = fixed_idx_mat.copy()
        fixed_idx_safe[~fixed_mask] = 0
        varsigma_fixed = np.take_along_axis(varsigma_mat, fixed_idx_safe, axis=1)

        arg_den = np.clip(
            -varsigma_fixed[:, :, None] * x_grid[:, None, :]
            - 0.5 * varsigma_fixed[:, :, None] * varsigma_fixed[:, :, None],
            -exp_clip,
            exp_clip,
        )
        den = np.sum(
            np.where(fixed_mask[:, :, None], bpv_weight_mat[:, :, None] * np.exp(arg_den), 0.0),
            axis=1,
        )

        s_grid = (num_beta - num_b) / den
        s_grid[~np.isfinite(s_grid)] = np.nan

        n_tenor_mat = fixed_lens[:, None].astype(float)
        c_ann = _cash_annuity_vectorized(s_grid, np.broadcast_to(n_tenor_mat, s_grid.shape))

        if is_payer:
            payoff = np.maximum(s_grid - case_data["strike_atm"][:, None], 0.0)
        else:
            payoff = np.maximum(case_data["strike_atm"][:, None] - s_grid, 0.0)

        integrand = phi * c_ann * payoff
        integrand[~np.isfinite(integrand)] = 0.0

        return p0t_alpha * np.trapezoid(integrand, x_grid, axis=1)
