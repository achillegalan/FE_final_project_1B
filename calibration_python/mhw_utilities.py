from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
from scipy.optimize import root_scalar


@dataclass
class Curve:
    """
    Container for a zero-rate curve.
    Attributes:     settlementDate:Valuation/settlement date of the curve.
                    dates: Curve pillar dates.
                    zeroRates: Continuously compounded zero rates associated with the pillar dates.
                    discounts: Optional discount factors, if already available in the source data.
    """

    settlementDate: pd.Timestamp
    dates: np.ndarray
    zeroRates: np.ndarray
    discounts: np.ndarray | None = None


def load_curve_from_csv(path: str | Path, settlement_date: str) -> Curve:
    """
    Load a curve from a CSV file.
    The CSV file must contain at least the columns: Date & ZeroRate

    If a Discount column exists, it is loaded as optional additional data.

    Parameters:         path: Path to the CSV file.
                        settlement_date: Settlement date to attach to the curve.

    Returns:            Curve object containing dates, zero rates, and optional discounts.
    """
    df = pd.read_csv(path)

    return Curve(
        settlementDate=pd.Timestamp(settlement_date).normalize(),
        dates=pd.to_datetime(df["Date"]).to_numpy(),
        zeroRates=df["ZeroRate"].to_numpy(dtype=float),
        discounts=df["Discount"].to_numpy(dtype=float) if "Discount" in df.columns else None,
    )


def easter_sunday(year: int) -> date:
    """
    Compute Easter Sunday for a given year using the Gregorian calendar.

    Parameters:         year: Calendar year.

    Returns:            Easter Sunday date.
    """
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e0 = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e0 + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451

    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1

    return date(year, month, day)


def target_holidays(start_date: pd.Timestamp, end_date: pd.Timestamp) -> set[date]:
    """
    Return TARGET market holidays between two dates.
    The implemented TARGET holidays are:
    - New Year's Day
    - Good Friday
    - Easter Monday
    - Labour Day
    - Christmas Day
    - Boxing Day

    Parameters:         start_date: Start of the date interval.
                        end_date: End of the date interval.

    Returns:            Set of TARGET holiday dates within the interval.
    """
    start_year = pd.Timestamp(start_date).year
    end_year = pd.Timestamp(end_date).year
    holidays: set[date] = set()

    for year in range(start_year, end_year + 1):
        easter = easter_sunday(year)

        holidays.update(
            {
                date(year, 1, 1),
                easter - timedelta(days=2),
                easter + timedelta(days=1),
                date(year, 5, 1),
                date(year, 12, 25),
                date(year, 12, 26),
            }
        )

    start_d = pd.Timestamp(start_date).date()
    end_d = pd.Timestamp(end_date).date()

    return {holiday for holiday in holidays if start_d <= holiday <= end_d}


def is_target_business_day(d: pd.Timestamp) -> bool:
    """
    Check whether a date is a TARGET business day.

    Parameters:         d: Date to check.

    Returns:            True if the date is a weekday and not a TARGET holiday.
    """
    d = pd.Timestamp(d).normalize()

    if d.weekday() >= 5:
        return False

    # A narrow holiday window is enough because only the year-specific holidays
    # around the input date are needed for this check.
    holidays = target_holidays(d - pd.Timedelta(days=10), d + pd.Timedelta(days=10))

    return d.date() not in holidays


def modified_following(dt: pd.Timestamp) -> pd.Timestamp:
    """
    Apply the Modified Following business-day convention.
    If the adjusted date moves into the next month, the date is moved backward
    to the previous TARGET business day instead.

    Parameters:         dt: Date to adjust.

    Returns:            Adjusted TARGET business date.
    """
    dt = pd.Timestamp(dt).normalize()
    d = dt

    while not is_target_business_day(d):
        d += pd.Timedelta(days=1)

    if d.month != dt.month:
        d = dt
        while not is_target_business_day(d):
            d -= pd.Timedelta(days=1)

    return d


def add_target_months(
    input_date: pd.Timestamp,
    n_months: int,
    convention: str = "modifiedfollow",
) -> pd.Timestamp:
    """
    Add calendar months to a date and apply a TARGET business-day convention.

    Parameters:         input_date: Initial date.
                        n_months: Number of months to add.
                        convention: Business-day convention.

    Returns:            Adjusted date.
    """
    if convention.lower() != "modifiedfollow":
        raise ValueError("Only 'modifiedfollow' convention is supported.")

    raw_date = pd.Timestamp(input_date).normalize() + pd.DateOffset(months=int(n_months))

    return modified_following(raw_date)


def make_schedule(
    start_date: pd.Timestamp,
    end_date: pd.Timestamp,
    step_months: int,
    convention: str = "modifiedfollow",
) -> np.ndarray:
    """
    Build a regular payment schedule between two dates.
    The schedule includes the start date and the end date. Intermediate dates
    are generated with a fixed monthly step and adjusted using Modified Following.

    Parameters:         start_date: Schedule start date.
                        end_date: Schedule end date.
                        step_months: Frequency step in months.
                        convention: Business-day convention.

    Returns:            Array of schedule dates with dtype datetime64[ns].
    """
    if convention.lower() != "modifiedfollow":
        raise ValueError("Only 'modifiedfollow' convention is supported.")

    start_date = pd.Timestamp(start_date).normalize()
    end_date = pd.Timestamp(end_date).normalize()

    dates: list[pd.Timestamp] = [start_date]
    k = 1

    while True:
        raw_date = start_date + pd.DateOffset(months=int(k * step_months))

        if raw_date >= end_date:
            break

        dates.append(modified_following(raw_date))
        k += 1

    if dates[-1] != end_date:
        dates.append(end_date)

    # Remove duplicates while preserving the original schedule order.
    seen: set[pd.Timestamp] = set()
    out: list[pd.Timestamp] = []

    for d in dates:
        if d not in seen:
            seen.add(d)
            out.append(d)

    return np.array(out, dtype="datetime64[ns]")


def yearfrac(start_dates, end_dates, basis: int) -> np.ndarray:
    """
    Compute year fractions between start and end dates.
    Supported day-count bases:
    - 1: 30/360 US approximation
    - 2: ACT/360
    - 3: ACT/365
    - 6: 30E/360

    Parameters:         start_dates: Start date or array-like of start dates.
                        end_dates: End date or array-like of end dates.
                        basis: Day-count basis identifier.

    Returns:            Year fractions.
    """
    s = pd.to_datetime(np.atleast_1d(start_dates)).normalize()
    e = pd.to_datetime(np.atleast_1d(end_dates)).normalize()

    if s.size == 1 and e.size > 1:
        s = np.repeat(s, e.size)
    elif e.size == 1 and s.size > 1:
        e = np.repeat(e, s.size)
    elif s.size != e.size:
        raise ValueError("start_dates and end_dates must have compatible sizes.")

    out = np.empty(s.size, dtype=float)

    for i, (sd, ed) in enumerate(zip(s, e, strict=True)):
        sd_ts = pd.Timestamp(sd)
        ed_ts = pd.Timestamp(ed)

        if basis == 2:
            out[i] = (ed_ts - sd_ts).days / 360.0
        elif basis == 3:
            out[i] = (ed_ts - sd_ts).days / 365.0
        elif basis == 1:
            out[i] = daycount_30_360_us(sd_ts, ed_ts) / 360.0
        elif basis == 6:
            out[i] = daycount_30e_360(sd_ts, ed_ts) / 360.0
        else:
            raise ValueError(f"Unsupported basis: {basis}")

    return out


def daycount_30_360_us(start_date: pd.Timestamp, end_date: pd.Timestamp) -> int:
    """
    Compute the 30/360 US day-count distance between two dates.

    Parameters:         start_date: Start date.
                        end_date: End date.

    Returns:            Number of synthetic 30/360 days.
    """
    y1, m1, d1 = start_date.year, start_date.month, start_date.day
    y2, m2, d2 = end_date.year, end_date.month, end_date.day

    if d1 == 31:
        d1 = 30

    if d2 == 31 and d1 >= 30:
        d2 = 30

    return 360 * (y2 - y1) + 30 * (m2 - m1) + (d2 - d1)


def daycount_30e_360(start_date: pd.Timestamp, end_date: pd.Timestamp) -> int:
    """
    Compute the 30E/360 day-count distance between two dates.

    Parameters:         start_date: Start date.
                        end_date: End date.

    Returns:            Number of synthetic 30E/360 days.
    """
    y1, m1, d1 = start_date.year, start_date.month, min(start_date.day, 30)
    y2, m2, d2 = end_date.year, end_date.month, min(end_date.day, 30)

    return 360 * (y2 - y1) + 30 * (m2 - m1) + (d2 - d1)


def get_target_df(
    eval_date: pd.Timestamp,
    curve_dates: Iterable[pd.Timestamp],
    zero_rates: Iterable[float],
    target_dates,
) -> np.ndarray:
    """
    Interpolate zero rates and compute discount factors at target dates.
    Zero rates are linearly interpolated in ACT/365 time from the evaluation
    date. Discount factors are then computed as exp(-r * t).

    Parameters:         eval_date: Evaluation date.
                        curve_dates: Curve pillar dates.
                        zero_rates: Zero rates associated with the pillar dates.
                        target_dates: Target date or array-like of target dates.

    Returns:            Discount factors at the target dates.
    """
    curve_dates_arr = pd.to_datetime(np.array(list(curve_dates))).astype("datetime64[ns]")
    zero_rates_arr = np.asarray(list(zero_rates), dtype=float).reshape(-1)
    target_dates_arr = pd.to_datetime(np.atleast_1d(target_dates)).astype("datetime64[ns]")

    pillar_tenors = yearfrac(pd.Timestamp(eval_date), curve_dates_arr, 3)
    target_tenors = yearfrac(pd.Timestamp(eval_date), target_dates_arr, 3)

    valid = np.isfinite(pillar_tenors) & np.isfinite(zero_rates_arr)
    pillar_tenors = pillar_tenors[valid]
    pillar_rates = zero_rates_arr[valid]

    if pillar_tenors.size == 1:
        interp_rates = np.full_like(target_tenors, pillar_rates[0], dtype=float)
    else:
        order = np.argsort(pillar_tenors)
        tau = pillar_tenors[order]
        zr = pillar_rates[order]

        interp_rates = np.interp(
            target_tenors,
            tau,
            zr,
            left=zr[0],
            right=zr[-1],
        )

    discounts = np.exp(-interp_rates * target_tenors)
    discounts[np.isclose(target_tenors, 0.0)] = 1.0

    return discounts


def solve_root_robust(fun) -> float:
    """
    Solve a scalar root-finding problem using robust bracketing and fallback logic.
    The function first scans increasingly wide symmetric intervals. If a sign
    change is found, Brent's method is used. If no bracket is found, a secant
    fallback is attempted near the best residual point.

    Parameters:         fun: Scalar function for which a root is required.

    Returns:            Approximate root of fun(x) = 0.

    Raises:             RuntimeError: If no stable root can be found.
    """
    half_width = 40.0
    max_half_width = 640.0
    n_grid = 1601
    residual_tol = 1e-8
    root_tol = 1e-6

    best_x_global = np.nan
    best_abs_global = np.inf

    while half_width <= max_half_width:
        grid = np.linspace(-half_width, half_width, n_grid)
        vals = np.array([fun(x) for x in grid], dtype=float)
        finite_mask = np.isfinite(vals)

        if not np.any(finite_mask):
            half_width *= 2.0
            continue

        finite_vals = vals[finite_mask]
        finite_grid = grid[finite_mask]

        idx_best = int(np.argmin(np.abs(finite_vals)))
        best_abs = abs(finite_vals[idx_best])
        best_x = finite_grid[idx_best]

        if best_abs < best_abs_global:
            best_abs_global = best_abs
            best_x_global = best_x

        if best_abs <= residual_tol:
            return float(best_x)

        finite_idx = np.where(finite_mask)[0]
        bracket_found = False

        for k in range(finite_idx.size - 1):
            i0 = finite_idx[k]
            i1 = finite_idx[k + 1]

            v0 = vals[i0]
            v1 = vals[i1]

            # Use signbit instead of v0 * v1 to avoid overflow in sign checks.
            if v0 == 0.0 or v1 == 0.0 or np.signbit(v0) != np.signbit(v1):
                try:
                    sol = root_scalar(
                        fun,
                        bracket=[grid[i0], grid[i1]],
                        method="brentq",
                    )

                    if sol.converged and abs(fun(sol.root)) <= root_tol:
                        return float(sol.root)

                except Exception:
                    pass

                bracket_found = True
                break

        if not bracket_found:
            try:
                sol = root_scalar(
                    fun,
                    x0=best_x,
                    x1=best_x + 1e-4,
                    method="secant",
                )

                if sol.converged and np.isfinite(sol.root):
                    f_val = fun(sol.root)

                    if np.isfinite(f_val) and abs(f_val) <= root_tol:
                        return float(sol.root)

            except Exception:
                pass

        half_width *= 2.0

    if np.isfinite(best_x_global):
        return float(best_x_global)

    raise RuntimeError("Unable to find a stable root for f(x)=0.")