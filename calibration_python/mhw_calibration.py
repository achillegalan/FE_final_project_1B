from __future__ import annotations

from typing import Iterable

import numpy as np
import pandas as pd
from scipy.optimize import differential_evolution, minimize

from mhw_utilities import Curve
from mhw_pricing import (
    _model_prices_from_case_data,
    _prepare_diagonal_case_data,
)


def calibrate_mhw_ab_diagonal(
    ois_curve: Curve,
    eur3m_curve: Curve,
    diag_summary_df: pd.DataFrame,
    gamma: float,
    is_payer: bool = True,
    is_cs: bool = True,
    x0: Iterable[float] | None = None,
    local_method: str = "L-BFGS-B",
    bounds_ab: Iterable[tuple[float, float]] = ((0.0, 0.40), (0.0, 0.40)),
    local_maxiter: int = 700,
    local_ftol: float = 1e-8,
):
    """
    Locally calibrate MHW parameters a and b for one gamma.

    The objective is the SSE between model and market prices of diagonal
    swaptions. The optimizer starts from x0, respects bounds_ab and returns
    the calibrated parameters plus a compact diagnostics dictionary with SSE,
    RMSE, instrument-level errors and the scipy optimizer result.

    Inputs:
        ois_curve: OIS discount curve.
        eur3m_curve: Euribor 3M pseudo-discount curve.
        diag_summary_df: diagonal swaption market dataframe.
        gamma: fixed multi-curve deformation parameter.
        is_payer, is_cs: swaption type flags.
        x0: initial guess [a0, b0].
        local_method, bounds_ab, local_maxiter, local_ftol: optimizer settings.

    Outputs:
        a_cal, b_cal, calib diagnostics dictionary.
    """
    if x0 is None:
        x0_arr = np.array([0.1, 0.1], dtype=float)
    else:
        x0_arr = np.asarray(list(x0), dtype=float).reshape(-1)
        if x0_arr.size != 2:
            raise ValueError("x0 must contain exactly two values: [a0, b0].")

    bounds_list = [(float(lo), float(hi)) for lo, hi in bounds_ab]

    if len(bounds_list) != 2:
        raise ValueError("bounds_ab must contain exactly two bounds: [(a_min,a_max), (b_min,b_max)].")

    if any(not np.isfinite(x) for bnd in bounds_list for x in bnd):
        raise ValueError("All bounds in bounds_ab must be finite.")

    if any(hi <= lo for lo, hi in bounds_list):
        raise ValueError("Each bound must satisfy upper > lower.")

    # Prepare market inputs and payment schedules only once before optimization.
    case_data = _prepare_diagonal_case_data(ois_curve, diag_summary_df)
    market_prices = case_data["market_prices"]

    def model_prices_from_params(a_try: float, b_try: float) -> np.ndarray:
        return _model_prices_from_case_data(
            ois_curve,
            eur3m_curve,
            case_data,
            float(a_try),
            float(b_try),
            float(gamma),
            is_payer=is_payer,
            is_cs=is_cs,
        )

    def objective_ab(theta) -> float:
        a_try = float(theta[0])
        b_try = float(theta[1])

        # Penalize parameter values outside the admissible region.
        if a_try < 0.0 or b_try < 0.0:
            return 1e30

        try:
            model_try = model_prices_from_params(a_try, b_try)
        except Exception:
            return 1e30

        if not np.all(np.isfinite(model_try)):
            return 1e30

        residuals_try = model_try - market_prices
        sse_val = float(np.dot(residuals_try, residuals_try))

        if not np.isfinite(sse_val):
            return 1e30

        return sse_val

    # Local least-squares minimization of the pricing error.
    res = minimize(
        objective_ab,
        x0=x0_arr,
        method=local_method,
        bounds=bounds_list,
        options={
            "maxiter": int(local_maxiter),
            "ftol": float(local_ftol),
            "disp": False,
        },
    )

    a_cal = float(res.x[0])
    b_cal = float(res.x[1])

    # Recompute prices at the calibrated parameters to build diagnostics.
    model_prices = model_prices_from_params(a_cal, b_cal)
    residuals = model_prices - market_prices
    abs_errors = np.abs(residuals)
    rmse = float(np.sqrt(np.mean(residuals * residuals)))

    results_table = pd.DataFrame(
        {
            "ExpiryYears": case_data["expiry_years"],
            "TenorYears": case_data["tenor_years"],
            "StrikeATM": case_data["strike_atm"],
            "MarketPrice": market_prices,
            "ModelPrice": model_prices,
            "Residual": residuals,
            "AbsError": abs_errors,
        }
    )

    calib = {
        "a": a_cal,
        "b": b_cal,
        "gamma": float(gamma),
        "sse": float(res.fun),
        "rmse": rmse,
        "x0": x0_arr.copy(),
        "resultsTable": results_table,
        "optimizerResult": res,
    }

    return a_cal, b_cal, calib


def calibrate_mhw_ab_global_per_case_robust(
    market_by_year: dict[int, tuple[Curve, Curve, pd.DataFrame]],
    gammas: Iterable[float] = (0.0, 0.5, 1.0),
    bounds_ab: Iterable[tuple[float, float]] = ((0.0, 0.40), (0.0, 0.40)),
    de_restarts: int = 8,
    de_maxiter: int = 120,
    de_popsize: int = 25,
    de_polish: bool = False,
    de_strategy: str = "best1bin",
    de_tol: float = 1e-8,
    de_atol: float = 1e-10,
    de_mutation: tuple[float, float] = (0.5, 1.0),
    de_recombination: float = 0.7,
    de_init: str = "sobol",
    topk_local_starts: int = 6,
    local_method: str = "SLSQP",
    local_maxiter: int = 4000,
    local_ftol: float = 1e-14,
    include_corner_starts: bool = True,
    probe_grid_points: int = 0,
    seed: int | None = 1234,
    is_payer: bool = True,
    is_cs: bool = True,
    store_history: bool = False,
) -> dict:
    """
    Robust global calibration by market year and gamma.

    For each case, repeated Differential Evolution runs generate candidate
    points that are refined locally; the best SSE is retained. The returned
    dictionary contains instrument-level results, a compact summary table and
    aggregate metrics. Set store_history=True only when DE callback history is
    needed for diagnostics.

    Inputs:
        market_by_year: mapping year -> (OIS curve, Euribor curve, market data).
        gammas: gamma values to calibrate.
        bounds_ab: bounds for a and b.
        de_*: Differential Evolution settings.
        topk_local_starts, local_*: local refinement settings.
        include_corner_starts, probe_grid_points: extra candidate controls.
        seed, is_payer, is_cs, store_history: reproducibility and output flags.

    Outputs:
        dict with results_df, summary_df, metrics and optional iter_history.
    """
    gammas_vec = [float(g) for g in gammas]
    bounds_list = [(float(lo), float(hi)) for lo, hi in bounds_ab]

    result_blocks: list[pd.DataFrame] = []
    case_summaries: list[dict] = []
    iter_history: list[dict] = []

    for year, (ois_curve, eur3m_curve, diag_summary_df) in market_by_year.items():
        case_data = _prepare_diagonal_case_data(ois_curve, diag_summary_df)
        market_prices = case_data["market_prices"]

        for gamma in gammas_vec:
            case_tag = f"{int(year)} | gamma={gamma}"
            eval_cache: dict[tuple[float, float], float] = {}
            raw_eval_counter = {"count": 0}

            def objective(theta):
                a_try = float(theta[0])
                b_try = float(theta[1])
                key = (round(a_try, 12), round(b_try, 12))

                if key in eval_cache:
                    return eval_cache[key]

                raw_eval_counter["count"] += 1

                if a_try < 0.0 or b_try < 0.0:
                    sse_val = 1e30
                else:
                    try:
                        model_prices_try = _model_prices_from_case_data(
                            ois_curve,
                            eur3m_curve,
                            case_data,
                            a_try,
                            b_try,
                            gamma,
                            is_payer=is_payer,
                            is_cs=is_cs,
                        )
                    except Exception:
                        sse_val = 1e30
                    else:
                        if not np.all(np.isfinite(model_prices_try)):
                            sse_val = 1e30
                        else:
                            residuals_try = model_prices_try - market_prices
                            sse_tmp = float(np.dot(residuals_try, residuals_try))
                            sse_val = sse_tmp if np.isfinite(sse_tmp) else 1e30

                eval_cache[key] = sse_val
                return sse_val

            candidate_rows: list[dict] = []

            if probe_grid_points >= 2:
                a_probe = np.linspace(bounds_list[0][0], bounds_list[0][1], int(probe_grid_points))
                b_probe = np.linspace(bounds_list[1][0], bounds_list[1][1], int(probe_grid_points))

                for b_try in b_probe:
                    for a_try in a_probe:
                        candidate_rows.append(
                            {
                                "a": float(a_try),
                                "b": float(b_try),
                                "SSE": float(objective((a_try, b_try))),
                                "Source": "probe_grid",
                                "Meta": f"n={int(probe_grid_points)}",
                            }
                        )

            for r in range(int(de_restarts)):
                run_seed = None if seed is None else int(seed + 10007 * r + 101 * int(year) + int(round(1000.0 * gamma)))
                run_iter = {"k": 0}

                def de_callback(xk, convergence):
                    run_iter["k"] += 1

                    if store_history:
                        sse_cb = objective((float(xk[0]), float(xk[1])))
                        iter_history.append(
                            {
                                "Case": case_tag,
                                "RunType": "DE",
                                "RunId": r,
                                "IterInRun": run_iter["k"],
                                "a": float(xk[0]),
                                "b": float(xk[1]),
                                "SSE": float(sse_cb),
                                "ConvergenceMetric": float(convergence),
                            }
                        )

                    return False

                res_de = differential_evolution(
                    objective,
                    bounds=bounds_list,
                    maxiter=int(de_maxiter),
                    popsize=int(de_popsize),
                    polish=bool(de_polish),
                    strategy=de_strategy,
                    tol=float(de_tol),
                    atol=float(de_atol),
                    mutation=de_mutation,
                    recombination=float(de_recombination),
                    init=de_init,
                    rng=run_seed,
                    callback=de_callback,
                )

                a_de = float(res_de.x[0])
                b_de = float(res_de.x[1])
                sse_de = objective((a_de, b_de))

                candidate_rows.append(
                    {
                        "a": a_de,
                        "b": b_de,
                        "SSE": float(sse_de),
                        "Source": "DE",
                        "Meta": f"run={r}; success={bool(res_de.success)}; nit={int(getattr(res_de, 'nit', -1))}",
                    }
                )

            candidates_df = pd.DataFrame(candidate_rows)
            candidates_df = candidates_df[np.isfinite(candidates_df["SSE"])].copy()

            if candidates_df.empty:
                raise RuntimeError(f"All candidate SSE values are invalid for case {case_tag}.")

            candidates_df["a_key"] = candidates_df["a"].round(10)
            candidates_df["b_key"] = candidates_df["b"].round(10)
            candidates_df = (
                candidates_df.sort_values("SSE")
                .drop_duplicates(subset=["a_key", "b_key"], keep="first")
                .drop(columns=["a_key", "b_key"])
                .reset_index(drop=True)
            )

            local_starts = [
                np.array([float(row["a"]), float(row["b"])], dtype=float)
                for _, row in candidates_df.head(int(topk_local_starts)).iterrows()
            ]

            if include_corner_starts:
                a_lo, a_hi = bounds_list[0]
                b_lo, b_hi = bounds_list[1]

                local_starts.extend(
                    [
                        np.array([a_lo, b_lo], dtype=float),
                        np.array([a_lo, b_hi], dtype=float),
                        np.array([a_hi, b_lo], dtype=float),
                        np.array([a_hi, b_hi], dtype=float),
                        np.array([(a_lo + a_hi) / 2.0, (b_lo + b_hi) / 2.0], dtype=float),
                    ]
                )

            local_rows: list[dict] = []
            seen_starts: set[tuple[float, float]] = set()

            for i, x0 in enumerate(local_starts):
                key0 = (round(float(x0[0]), 10), round(float(x0[1]), 10))

                if key0 in seen_starts:
                    continue

                seen_starts.add(key0)

                res_local = minimize(
                    objective,
                    x0=x0,
                    method=local_method,
                    bounds=bounds_list,
                    options={
                        "maxiter": int(local_maxiter),
                        "ftol": float(local_ftol),
                        "disp": False,
                    },
                )

                a_loc = float(res_local.x[0])
                b_loc = float(res_local.x[1])
                sse_loc = objective((a_loc, b_loc))

                local_rows.append(
                    {
                        "a": a_loc,
                        "b": b_loc,
                        "SSE": float(sse_loc),
                        "Source": "local_refine",
                        "Meta": f"start={i}; success={bool(res_local.success)}; nit={int(getattr(res_local, 'nit', -1))}",
                    }
                )

            all_df = pd.DataFrame(candidate_rows + local_rows)
            all_df = all_df[np.isfinite(all_df["SSE"])].copy()

            if all_df.empty:
                raise RuntimeError(f"No valid SSE found after robust optimization for case {case_tag}.")

            best_row = all_df.sort_values("SSE").iloc[0]

            a_cal = float(best_row["a"])
            b_cal = float(best_row["b"])

            model_prices = _model_prices_from_case_data(
                ois_curve,
                eur3m_curve,
                case_data,
                a_cal,
                b_cal,
                gamma,
                is_payer=is_payer,
                is_cs=is_cs,
            )

            residuals = model_prices - market_prices
            sse_val = float(np.dot(residuals, residuals))
            abs_errors = np.abs(residuals)
            rmse = float(np.sqrt(np.mean(residuals * residuals)))
            mae = float(np.mean(abs_errors))

            case_df = pd.DataFrame(
                {
                    "Year": int(year),
                    "Gamma": gamma,
                    "ExpiryYears": case_data["expiry_years"],
                    "TenorYears": case_data["tenor_years"],
                    "MaturityYears": case_data["maturity_years"],
                    "StrikeATM": case_data["strike_atm"],
                    "MarketPrice": market_prices,
                    "ModelPrice": model_prices,
                    "Residual": residuals,
                    "AbsError": abs_errors,
                }
            )

            result_blocks.append(case_df)

            case_summaries.append(
                {
                    "Year": int(year),
                    "Gamma": gamma,
                    "a": a_cal,
                    "b": b_cal,
                    "SSE": sse_val,
                    "RMSE": rmse,
                    "MAE": mae,
                }
            )

    results_df = pd.concat(result_blocks, axis=0, ignore_index=True).sort_values(["Year", "Gamma", "ExpiryYears"])
    summary_df = pd.DataFrame(case_summaries).sort_values(["Year", "Gamma"])

    out = {
        "results_df": results_df,
        "summary_df": summary_df,
        "metrics": {
            "rmse_global": float(np.sqrt(np.mean(results_df["Residual"] ** 2))),
            "mae_global": float(results_df["AbsError"].mean()),
            "max_abs_err": float(results_df["AbsError"].max()),
            "sse_global": float(np.sum(results_df["Residual"] ** 2)),
        },
    }

    if store_history:
        out["iter_history"] = iter_history

    return out


def compute_mhw_ab_objective_grid(
    ois_curve: Curve,
    eur3m_curve: Curve,
    diag_summary_df: pd.DataFrame,
    gamma: float,
    is_payer: bool = True,
    is_cs: bool = True,
    a_values: Iterable[float] | None = None,
    b_values: Iterable[float] | None = None,
) -> dict:
    """
    Evaluate the calibration objective on an (a, b) grid.

    Each grid point is priced with the same prepared market case and compared
    with market prices through SSE. Returns the two parameter grids, the SSE
    surface and the best finite grid point.

    Inputs:
        ois_curve: OIS discount curve.
        eur3m_curve: Euribor 3M pseudo-discount curve.
        diag_summary_df: diagonal swaption market dataframe.
        gamma: fixed MHW gamma.
        is_payer, is_cs: swaption type flags.
        a_values, b_values: parameter grid values.

    Outputs:
        dict with Agrid, Bgrid, SSEgrid and min_point.
    """
    if a_values is None:
        a_values = np.linspace(0.0, 0.40, 31)
    if b_values is None:
        b_values = np.linspace(0.0, 0.40, 31)

    a_vec = np.unique(np.append(np.asarray(list(a_values), dtype=float), 0.0))
    b_vec = np.unique(np.append(np.asarray(list(b_values), dtype=float), 0.0))

    case_data = _prepare_diagonal_case_data(ois_curve, diag_summary_df)
    market_prices = case_data["market_prices"]

    a_grid, b_grid = np.meshgrid(a_vec, b_vec)
    sse_grid = np.full_like(a_grid, np.nan, dtype=float)

    for ib, b_try in enumerate(b_vec):
        for ia, a_try in enumerate(a_vec):
            try:
                model_try = _model_prices_from_case_data(
                    ois_curve,
                    eur3m_curve,
                    case_data,
                    float(a_try),
                    float(b_try),
                    float(gamma),
                    is_payer=is_payer,
                    is_cs=is_cs,
                )
            except Exception:
                continue

            if not np.all(np.isfinite(model_try)):
                continue

            residuals = model_try - market_prices
            sse_val = float(np.sum(residuals * residuals))

            if np.isfinite(sse_val):
                sse_grid[ib, ia] = sse_val

    valid_mask = np.isfinite(sse_grid)

    if not np.any(valid_mask):
        raise RuntimeError("All grid evaluations failed. Try a narrower (a,b) range.")

    sse_for_min = sse_grid.copy()
    sse_for_min[~valid_mask] = np.inf

    idx_min = int(np.argmin(sse_for_min))
    irow, icol = np.unravel_index(idx_min, sse_for_min.shape)

    return {
        "Agrid": a_grid,
        "Bgrid": b_grid,
        "SSEgrid": sse_grid,
        "min_point": {
            "a": float(a_grid[irow, icol]),
            "b": float(b_grid[irow, icol]),
            "sse": float(sse_grid[irow, icol]),
        },
    }


def plot_mhw_ab_objective_landscape(
    ois_curve: Curve,
    eur3m_curve: Curve,
    diag_summary_df: pd.DataFrame,
    gamma: float,
    is_payer: bool = True,
    is_cs: bool = True,
    a_values: Iterable[float] | None = None,
    b_values: Iterable[float] | None = None,
    use_log10: bool = False,
    interactive: bool = False,
):
    """
    Plot the MHW calibration objective surface.

    Computes SSE(a,b), optionally transforms it to log10 scale, and displays a
    Matplotlib or Plotly 3D surface. The returned object is the compact grid
    data from compute_mhw_ab_objective_grid.

    Inputs:
        ois_curve: OIS discount curve.
        eur3m_curve: Euribor 3M pseudo-discount curve.
        diag_summary_df: diagonal swaption market dataframe.
        gamma: fixed MHW gamma.
        is_payer, is_cs: swaption type flags.
        a_values, b_values: parameter grid values.
        use_log10: plot log10(SSE) if True.
        interactive: use Plotly if True.

    Outputs:
        dict with the computed objective grid and best grid point.
    """
    import matplotlib.pyplot as plt

    grid_data = compute_mhw_ab_objective_grid(
        ois_curve=ois_curve,
        eur3m_curve=eur3m_curve,
        diag_summary_df=diag_summary_df,
        gamma=gamma,
        is_payer=is_payer,
        is_cs=is_cs,
        a_values=a_values,
        b_values=b_values,
    )

    a_grid = grid_data["Agrid"]
    b_grid = grid_data["Bgrid"]
    sse_grid = grid_data["SSEgrid"]

    if use_log10:
        valid = np.isfinite(sse_grid) & (sse_grid > 0.0)
        z_plot = np.full_like(sse_grid, np.nan, dtype=float)
        z_plot[valid] = np.log10(sse_grid[valid])
        cbar_label = "log10(SSE)"
        title_suffix = "log10(SSE(a,b))"
    else:
        z_plot = sse_grid.copy()
        cbar_label = "SSE"
        title_suffix = "SSE(a,b)"

    if int(np.isfinite(z_plot).sum()) == 0:
        raise RuntimeError("No finite values available to plot. Try a narrower (a,b) range.")

    invalid_plot_mask = ~np.isfinite(z_plot)
    z_surface = z_plot.copy()

    if np.any(invalid_plot_mask):
        finite_vals = z_plot[np.isfinite(z_plot)]
        fill_value = float(np.nanpercentile(finite_vals, 99.0))

        if not np.isfinite(fill_value):
            fill_value = float(np.nanmax(finite_vals))

        z_surface[invalid_plot_mask] = fill_value

    if interactive:
        try:
            import plotly.graph_objects as go
        except Exception:
            interactive = False
        else:
            fig = go.Figure(
                data=[
                    go.Surface(
                        x=a_grid,
                        y=b_grid,
                        z=z_surface,
                        colorscale="Viridis",
                        connectgaps=True,
                        colorbar={"title": cbar_label, "len": 0.76, "thickness": 14},
                        showscale=True,
                    )
                ]
            )

            fig.update_layout(
                title=f"{title_suffix} - gamma={gamma}",
                width=760,
                height=520,
                margin={"l": 20, "r": 20, "t": 52, "b": 20},
                template="plotly_white",
                paper_bgcolor="#ffffff",
                scene={
                    "xaxis_title": "a",
                    "yaxis_title": "b",
                    "zaxis_title": cbar_label,
                    "bgcolor": "#ffffff",
                },
            )

            try:
                from IPython import get_ipython
                from IPython.display import display

                if get_ipython() is not None:
                    display(fig)
                else:
                    fig.show()
            except Exception:
                fig.show()

            return grid_data

    fig = plt.figure(figsize=(7.2, 5.0))
    ax = fig.add_subplot(111, projection="3d")

    finite_z = z_plot[np.isfinite(z_plot)]
    zmin = float(np.min(finite_z))
    zmax = float(np.max(finite_z))

    surf = ax.plot_surface(
        a_grid,
        b_grid,
        z_surface,
        cmap="viridis",
        vmin=zmin,
        vmax=zmax,
        edgecolor="none",
        antialiased=True,
    )

    ax.set_xlabel("a")
    ax.set_ylabel("b")
    ax.set_zlabel(cbar_label)
    ax.set_title(f"Objective Surface - gamma={gamma}")

    fig.colorbar(surf, ax=ax, shrink=0.72, pad=0.05, label=cbar_label)
    fig.tight_layout(pad=0.6)

    try:
        from IPython import get_ipython
        from IPython.display import display

        if get_ipython() is not None:
            display(fig)
        else:
            plt.show()
    except Exception:
        plt.show()

    plt.close(fig)

    return grid_data
