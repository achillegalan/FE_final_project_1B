function [price, details] = model_multiHJM_Price( ...
    OIS_curve, EUR3M_curve, paymentDates, strike, expiryYears, a, b, gamma, isPayer)
%MHWPDSWAPTIONPRICER
% Pricing di una swaption PD nel modello MHW di Baviera (2019), eq. (3.9)-(3.11).
% Nota: il parametro "b" qui corrisponde a "sigma" del paper.
% Assunzione: stessa schedule per gamba fissa e variabile (coerente con Task 5 diagonale).

    if nargin < 9 || isempty(isPayer)
        isPayer = true;
    end

    if gamma < 0 || gamma > 1
        error('mhwPDSwaptionPricer:GammaOutOfRange', 'gamma must be in [0,1].');
    end
    if a < 0 || b < 0
        error('mhwPDSwaptionPricer:InvalidParams', 'a and b must be non-negative.');
    end

    settleDate = OIS_curve.settlementDate;
    exerciseDate = add_target_months(settleDate, round(12 * expiryYears), 'modifiedfollow');

    paymentDates = paymentDates(:);
    paymentDates = paymentDates(paymentDates > exerciseDate);

    if isempty(paymentDates)
        price = 0;
        details = struct('exerciseDate', exerciseDate, 'xStar', NaN, 'receiverPrice', 0);
        return;
    end

    %% OIS CURVE
    % Year fractions (ACT/360) and forward discounts B_{alpha,j}(t0)
    accrualStartDates = [exerciseDate; paymentDates(1:end-1)];
    delta = yearfrac(accrualStartDates, paymentDates, 2);

    P0T_alpha = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
    P0T_pay = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, paymentDates);
    Balpha_pay = P0T_pay ./ P0T_alpha;

    %% MULTI-CURVE
    % beta_i(t0) = B(t0; t_i, t_{i+1}) / B_tilde(t0; t_i, t_{i+1})
    P0T_full = [P0T_alpha; P0T_pay];

    Ptilde_alpha = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, exerciseDate);
    Ptilde_pay = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, paymentDates);
    Ptilde_full = [Ptilde_alpha; Ptilde_pay];

    Bdisc_fwd = P0T_full(2:end) ./ P0T_full(1:end-1);
    Bpseudo_fwd = Ptilde_full(2:end) ./ Ptilde_full(1:end-1);
    beta = Bdisc_fwd ./ Bpseudo_fwd;

    % B_{alpha',i}(t0), i = alpha' ... omega'-1 (first term is 1)
    Balpha_start = P0T_full(1:end-1) ./ P0T_alpha;      %forward discount della floating leg

    %% MHW parameters (paper eq. 3.3, 3.5, 3.6)
    T = yearfrac(settleDate, exerciseDate, 3);  % ACT/365
    if abs(a) > 1e-14
        zeta2 = b^2 * (1 - exp(-2 * a * T)) / (2 * a);
    else
        zeta2 = b^2 * T;
    end
    zeta = sqrt(max(zeta2, 0));

    tau = yearfrac(exerciseDate, [exerciseDate; paymentDates], 3);
    if abs(a) > 1e-14
        v = zeta * (1 - exp(-a * tau)) / a;
    else
        v = zeta * tau;
    end

    varsigma = (1 - gamma) * v(2:end);            % ς_{alpha,j}
    nu = v(1:end-1) - gamma * v(2:end);           % ν_{alpha',i}

    %% f(x) in eq. (3.9)
    % --- oggetti base ---
    % Balpha_pay   : B_{alpha,j}(t0), j = alpha+1 ... omega              (n)
    % Balpha_start : B_{alpha',i}(t0), i = alpha' ... omega'-1           (n)
    % beta         : beta_i(t0),      i = alpha' ... omega'-1            (n)
    % varsigma     : (1-gamma)*v_j,   j = alpha+1 ... omega'             (n)
    % nu           : v_i-gamma*v_{i+1}, i = alpha' ... omega'-1          (n)
    
    % c_j: strike*delta tranne ultimo = 1 + strike*delta
    c = strike * delta;
    c(end) = 1 + strike * delta(end);

    A1 = c .* Balpha_pay .* exp(-0.5 * varsigma.^2);
    A2 =  Balpha_start(2:end) .* exp(-0.5 *  varsigma(1:end-1).^2);
    A3 = beta .* Balpha_start .* exp(-0.5 * nu.^2);   
    
    % f(x) = sum1 + sum2 - sum3
    f = @(x) sum(A1 .* exp(-varsigma * x)) + ...
             sum(A2 .* exp(- varsigma(1:end-1) * x)) - ...
             sum(A3 .* exp(-nu * x));

    %% Bracket robusto per x*
    L = -8; U = 8;
    fL = f(L); fU = f(U);
    it = 0;
    while ~(fL > 0 && fU < 0) && it < 40
        L = L - 4;
        U = U + 4;
        fL = f(L);
        fU = f(U);
        it = it + 1;
    end

    if ~(fL > 0 && fU < 0)
        grid = linspace(-40, 40, 1601);
        vals = arrayfun(f, grid);
        k = find(vals(1:end-1) .* vals(2:end) <= 0, 1, 'first');
        if isempty(k)
            error('mhwPDSwaptionPricer:RootNotBracketed', ...
                  'Unable to bracket x* for f(x)=0.');
        end
        xStar = fzero(f, [grid(k), grid(k+1)]);
    else
        xStar = fzero(f, [L, U]);
    end

    %% Closed-form PD receiver price (eq. 3.11)
    Ncdf = @(z) 0.5 * erfc(-z / sqrt(2));
    receiverPrice = P0T_alpha * ( ...
        sum(c .* Balpha_pay .* Ncdf(xStar + varsigma)) + ...
        sum(Balpha_start(2:end) .* Ncdf(xStar + varsigma(1:end-1))) - ...
        sum(beta .* Balpha_start .* Ncdf(xStar + nu)) );

    % Put-call parity in PD case
    BPV0 = sum(delta .* Balpha_pay);
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
    details.discountToExpiry = P0T_alpha;
    details.varsigma = varsigma;
    details.nu = nu;
    details.beta = beta;
    details.Balpha_pay = Balpha_pay;
end
