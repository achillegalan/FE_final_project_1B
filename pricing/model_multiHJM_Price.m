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
    fixedDelta = yearfrac(fixedAccrualStartDates, fixedPaymentDates, 2);

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

    %% Bracket su griglia per x*
    grid = linspace(-40, 40, 1601);
    vals = arrayfun(f, grid);
    k = find(vals(1:end-1) .* vals(2:end) <= 0, 1, 'first');
    xStar = fzero(f, [grid(k), grid(k+1)]);

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
end
