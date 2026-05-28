function [price, details] = model_multiHJM_Price( ...
    OIS_curve, EUR3M_curve, floatingPaymentDates, fixedPaymentDates, ...
    strike, expiryYears, a, b, gamma, isPayer)
%MODEL_MULTIHJM_PRICE
% Pricing di una swaption PD nel modello MHW di Baviera (2019), eq. (3.9)-(3.11).
% Nota: il parametro "b" qui corrisponde a "sigma" del paper.

    settleDate = OIS_curve.settlementDate;
    exerciseDate = add_target_months(settleDate, round(12 * expiryYears), 'modifiedfollow');

    floatingPaymentDates = floatingPaymentDates(:);
    fixedPaymentDates = fixedPaymentDates(:);

    floatingPaymentDates = floatingPaymentDates(floatingPaymentDates > exerciseDate);
    fixedPaymentDates = fixedPaymentDates(fixedPaymentDates > exerciseDate);

   [~, fixedIdxOnFloat] = ismember(fixedPaymentDates, floatingPaymentDates);

    %% OIS CURVE

    fixedAccrualStartDates = [exerciseDate; fixedPaymentDates(1:end-1)];
    fixedDelta = yearfrac(fixedAccrualStartDates, fixedPaymentDates, 1); % Paper requires 30/360 for the fixed leg day-count.

    P0T_alpha = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
    P0T_floatPay = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, floatingPaymentDates);
    Balpha_pay = P0T_floatPay ./ P0T_alpha;

    %% MULTI-CURVE
    % beta_i(t0) = B(t0; t_i, t_{i+1}) / B_tilde(t0; t_i, t_{i+1})
    P0T_full = [P0T_alpha; P0T_floatPay];

    Ptilde_alpha = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, exerciseDate);
    Ptilde_floatPay = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, floatingPaymentDates);
    Ptilde_full = [Ptilde_alpha; Ptilde_floatPay];

    Bdisc_fwd = P0T_full(2:end) ./ P0T_full(1:end-1);
    Bpseudo_fwd = Ptilde_full(2:end) ./ Ptilde_full(1:end-1);
    beta = Bdisc_fwd ./ Bpseudo_fwd;

    % B_{alpha',i}(t0), i = alpha' ... omega'-1 (first term is 1)
    Balpha_start = P0T_full(1:end-1) ./ P0T_alpha;      % forward discount della floating leg

    %% MHW parameters (paper eq. 3.3, 3.5, 3.6)
    T = yearfrac(settleDate, exerciseDate, 3);  % ACT/365
    if abs(a) > 1e-14
        zeta2 = b^2 * (1 - exp(-2 * a * T)) / (2 * a);
    else
        zeta2 = b^2 * T;
    end
    zeta = sqrt(max(zeta2, 0));

    tau = yearfrac(exerciseDate, [exerciseDate; floatingPaymentDates], 3);
    if abs(a) > 1e-14
        v = zeta * (1 - exp(-a * tau)) / a;
    else
        v = zeta * tau;
    end

    varsigma = (1 - gamma) * v(2:end);            % varsigma_{alpha,j}
    nu = v(1:end-1) - gamma * v(2:end);           % nu_{alpha',i}

    %% f(x) in eq. (3.9)
    % c_j sulla griglia floating:
    % - c_j = K*delta_fissa quando j e' una fixed payment date
    % - c_j = 0 altrimenti
    % - all'ultima fixed payment date: c_j = 1 + K*delta_fissa (rimborso nozionale)
    c = zeros(size(floatingPaymentDates));
    c(fixedIdxOnFloat) = strike * fixedDelta;
    c(fixedIdxOnFloat(end)) = 1 + strike * fixedDelta(end);

    A1 = c .* Balpha_pay .* exp(-0.5 * varsigma.^2);
    A2 = Balpha_start(2:end) .* exp(-0.5 * varsigma(1:end-1).^2);
    A3 = beta .* Balpha_start .* exp(-0.5 * nu.^2);

    % f(x) = sum1 + sum2 - sum3
    f = @(x) sum(A1 .* exp(-varsigma * x)) + ...
             sum(A2 .* exp(-varsigma(1:end-1) * x)) - ...
             sum(A3 .* exp(-nu * x));

    %% Robust root finding for x*
    xStar = solveRootRobust(f);

    %% Closed-form PD receiver price (eq. 3.11)
    Ncdf = @(z) 0.5 * erfc(-z / sqrt(2));
    receiverPrice = P0T_alpha * ( ...
        sum(c .* Balpha_pay .* Ncdf(xStar + varsigma)) + ...
        sum(Balpha_start(2:end) .* Ncdf(xStar + varsigma(1:end-1))) - ...
        sum(beta .* Balpha_start .* Ncdf(xStar + nu)) );

    % Put-call parity in PD case
    BPV0 = sum(fixedDelta .* Balpha_pay(fixedIdxOnFloat));
    num0 = 1 - Balpha_pay(end) + sum(Balpha_start .* (beta - 1));

    if isPayer
        price = receiverPrice + P0T_alpha * (num0 - strike * BPV0);
    else
        price = receiverPrice;
    end

    details = struct();
    details.exerciseDate = exerciseDate;
    details.xStar = xStar;
    details.receiverPrice = receiverPrice;
    details.BPV0 = BPV0;
    details.num0 = num0;

function xRoot = solveRootRobust(fun)
    % Robust root search: start from a base interval and expand progressively.
    halfWidth = 40;
    maxHalfWidth = 640;
    nGrid = 1601;
    residualTol = 1e-8;
    rootTol = 1e-6;
    bestXGlobal = NaN;
    bestAbsGlobal = Inf;
    opts = optimset('Display', 'off');

    while halfWidth <= maxHalfWidth
        % Sample the function on a symmetric grid and ignore non-finite values.
        grid = linspace(-halfWidth, halfWidth, nGrid);
        vals = arrayfun(fun, grid);
        finiteMask = isfinite(vals);

        % If all evaluations failed, enlarge the search domain.
        if ~any(finiteMask)
            halfWidth = 2 * halfWidth;
            continue;
        end

        finiteVals = vals(finiteMask);
        finiteGrid = grid(finiteMask);
        [bestAbs, idxBest] = min(abs(finiteVals));
        bestX = finiteGrid(idxBest);
        if bestAbs < bestAbsGlobal
            bestAbsGlobal = bestAbs;
            bestXGlobal = bestX;
        end

        % Fast path: a near-zero value is already on the grid.
        if bestAbs <= residualTol
            xRoot = bestX;
            return;
        end

        % Preferred path: bracketed root (sign change) for stable fzero.
        k = find(finiteMask(1:end-1) & finiteMask(2:end) & (vals(1:end-1) .* vals(2:end) <= 0), 1, 'first');

        if ~isempty(k)
            [ok, xTry] = check_root([grid(k), grid(k+1)]);
            if ok
                xRoot = xTry;
                return;
            end
        end

        % Fallback: try from the best finite point even without bracketing.
        [ok, xTry] = check_root(bestX);
        if ok
            xRoot = xTry;
            return;
        end

        halfWidth = 2 * halfWidth;
    end

    % Last resort: return the best finite point found during exploration.
    if isfinite(bestXGlobal)
        xRoot = bestXGlobal;
        return;
    end

    error('model_multiHJM_Price:RootNotFound', ...
        'Unable to find a stable root for f(x)=0 up to |x| <= %.0f.', maxHalfWidth);

    function [tf, xCandidate] = check_root(seed)
        % Run fzero and accept the candidate only if residual/exit checks pass.
        tf = false;
        xCandidate = NaN;
        try
            [xTry, fTry, exitflag] = fzero(fun, seed, opts);
            tf = exitflag > 0 && isfinite(xTry) && isfinite(fTry) && abs(fTry) <= rootTol;
            if tf
                xCandidate = xTry;
            end
        catch
            % Keep tf=false and let outer logic try other seeds/ranges.
        end
    end
end
end
