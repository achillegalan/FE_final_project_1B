function [NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw,...
     swapData, OIS_curve, EUR3M_curve, settlementDate, strike,...
     isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing)
% PRICE_AMORTIZING_SWAP_CVA_HW Prices an amortizing swap and its CVA using a 
% Hull-White Trinomial Tree under the Multi-Curve framework (gamma = 0).
%
% INPUTS:
%   hw              - Struct with Hull-White parameters 'a' and 'sigma'.
%   swapData        - Table/struct with PayDate, AccrualStart, AccrualEnd, Notional.
%   OIS_curve       - Struct containing settlementDate, dates, zeroRates.
%   EUR3M_curve     - Struct containing dates, zeroRates for forecasting.
%   settlementDate  - Valuation datetime (e.g., June 2022 or Jan 2023).
%   strike          - Fixed swap rate K.
%   normalVol       - Swaption normal volatility cube data structure.
%   isPayer         - Logical flag: true for Payer, false for Receiver.
%   fixingFrequency - String flag: 'quarterly' or 'semiannual'.
%   cdsSpreads      - Given CDS spread in decimal form (e.g., 300 bps = 0.03).
%   LGD             - Loss Given Default parameter (e.g., 40% = 0.40).
%   knownFixing     - Optional struct with resetStartDate and resetRate.

    % ---------------------------------------------------------------------
    % 1. EXTRACT & FILTER SWAP DATA
    % ---------------------------------------------------------------------
    allPayDates = swapData.PayDate;
    allAccStarts = swapData.AccrualStart;
    allAccEnds = swapData.AccrualEnd;
    allNotionals = swapData.Notional;

    % Isolate strictly future cash flows
    idx_future = find(allPayDates > settlementDate);
    if isempty(idx_future)
        NPV_riskfree = 0; CVA = 0; final_price = 0; 
        return;
    end

    % ---------------------------------------------------------------------
    % 2. TIME GRID SETUP
    % ---------------------------------------------------------------------
    dt = 1/24; % 24 steps per year (half-month granularity for accuracy)
    T_max = yearfrac(settlementDate, max(allPayDates(idx_future)), 3);
    N = ceil(T_max / dt);
    time_grid = (0:N)' * dt;

    % ---------------------------------------------------------------------
    % 3. TREE GEOMETRY
    % ---------------------------------------------------------------------
    a = hw.a; 
    sigma = hw.sigma;
    dx = sigma * sqrt(3 * dt);
    j_max = ceil(0.184 / (a * dt));
    num_nodes = 2 * j_max + 1;
    j_vec = (j_max:-1:-j_max)';
    x_space = j_vec * dx;

    pu = zeros(num_nodes, 1); pm = zeros(num_nodes, 1); pd = zeros(num_nodes, 1);
    idx_u = zeros(num_nodes, 1); idx_m = zeros(num_nodes, 1); idx_d = zeros(num_nodes, 1);

    for k = 1:num_nodes
        j = j_vec(k);
        if j == j_max
            pu(k) = 7/6 + 0.5 * (a^2 * j^2 * dt^2 - 3 * a * j * dt);
            pm(k) = -1/3 - a^2 * j^2 * dt^2 + 2 * a * j * dt;
            pd(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 - a * j * dt);
            idx_u(k) = k; idx_m(k) = k+1; idx_d(k) = k+2;
        elseif j == -j_max
            pu(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 + a * j * dt);
            pm(k) = -1/3 - a^2 * j^2 * dt^2 - 2 * a * j * dt;
            pd(k) = 7/6 + 0.5 * (a^2 * j^2 * dt^2 + 3 * a * j * dt);
            idx_u(k) = k-2; idx_m(k) = k-1; idx_d(k) = k;
        else
            pu(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 + a * j * dt);
            pm(k) = 2/3 - a^2 * j^2 * dt^2;
            pd(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 - a * j * dt);
            idx_u(k) = k-1; idx_m(k) = k; idx_d(k) = k+1;
        end
    end

    % ---------------------------------------------------------------------
    % 4. FORWARD INDUCTION (ALPHA CALIBRATION)
    % ---------------------------------------------------------------------
    Q = zeros(num_nodes, N+1);
    alpha = zeros(N, 1);
    mid_idx = j_max + 1;
    Q(mid_idx, 1) = 1.0;

    % Precompute Market Discounts for the Grid Dates
    dates_grid = settlementDate + days(round(time_grid * 365));
    P_OIS_grid = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, dates_grid);

    for n = 1:N
        P_market = P_OIS_grid(n+1);
        sum_Q_exp_x = sum(Q(:, n) .* exp(-x_space * dt));
        alpha(n) = (1 / dt) * log(sum_Q_exp_x / P_market);
        
        r_t = x_space + alpha(n);
        
        for k = 1:num_nodes
            if Q(k, n) > 0
                val = Q(k, n) * exp(-r_t(k) * dt);
                Q(idx_u(k), n+1) = Q(idx_u(k), n+1) + val * pu(k);
                Q(idx_m(k), n+1) = Q(idx_m(k), n+1) + val * pm(k);
                Q(idx_d(k), n+1) = Q(idx_d(k), n+1) + val * pd(k);
            end
        end
    end

    % ---------------------------------------------------------------------
    % 5. MAP CASH FLOWS TO TREE
    % ---------------------------------------------------------------------
    CF_list = struct('is_det', {}, 'amount', {}, 'pay_step', {}, 'reset_step', {}, ...
                     'N', {}, 'delta', {}, 'reset_time_frac', {}, 'pay_time_frac', {}, ...
                     'underlying_end_frac', {});

    for c = 1:length(idx_future)
        idx = idx_future(c);
        
        t_pay = allPayDates(idx);
        t_accStart = allAccStarts(idx);
        t_accEnd = allAccEnds(idx);
        N_notional = allNotionals(idx);
        delta = yearfrac(t_accStart, t_accEnd, 2); % ACT/360
        
        % Check Fixing Frequency rule
        if strcmpi(fixingFrequency, 'semiannual')
            if mod(idx, 2) == 0 && idx > 1
                t_reset = allAccStarts(idx-1); % Locks using previous period's start
            else
                t_reset = t_accStart;
            end
        else
            t_reset = t_accStart;
        end
        
        % Assess Determinism
        is_det = false;
        det_rate = 0;
        
        if t_reset <= settlementDate
            is_det = true;
            if nargin >= 12 && ~isempty(knownFixing) && ~isnan(knownFixing.resetRate)
                det_rate = knownFixing.resetRate;
            else
                % Implied forward rate fallback
                P_E_start = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, t_reset);
                P_E_end = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, t_accEnd);
                det_rate = (P_E_start / P_E_end - 1) / delta;
            end
        end
        
        pay_time = yearfrac(settlementDate, t_pay, 3);
        reset_time = max(0, yearfrac(settlementDate, t_reset, 3));
        
        pay_step = round(pay_time / dt) + 1;
        reset_step = round(reset_time / dt) + 1;
        
        new_cf.is_det = is_det;
        new_cf.pay_step = pay_step;
        new_cf.reset_step = reset_step;
        new_cf.N = N_notional;
        new_cf.delta = delta;
        new_cf.reset_time_frac = reset_time;
        new_cf.pay_time_frac = pay_time;
        new_cf.underlying_end_frac = reset_time + 0.25; % Standard 3M tenor

        if is_det
            if isPayer
                new_cf.amount = N_notional * delta * (det_rate - strike);
            else
                new_cf.amount = N_notional * delta * (strike - det_rate);
            end
        else
            new_cf.amount = 0; % Computed stochastically during backward induction
        end
        
        CF_list(c) = new_cf;
    end

    % ---------------------------------------------------------------------
    % 6. BACKWARD INDUCTION (NPV & EPE)
    % ---------------------------------------------------------------------
    V = zeros(num_nodes, 1);
    EPE = zeros(N+1, 1);
    
    B_hw = @(t, T) (1 - exp(-a * (T - t))) / a;
    phi_hw = @(t) (sigma^2 / (2*a)) * (1 - exp(-2*a*t));

    for n = (N+1):-1:1
        t = (n-1) * dt;
        
        % Discount the Continuation Value (except at the exact end)
        if n <= N
            r_t = x_space + alpha(n);
            discount = exp(-r_t * dt);
            EV = pu .* V(idx_u) + pm .* V(idx_m) + pd .* V(idx_d);
            V = discount .* EV;
        end
        
        % 1. Inject fully deterministic cash flows hitting this exact payment date
        for c = 1:length(CF_list)
            if CF_list(c).is_det && CF_list(c).pay_step == n
                V = V + CF_list(c).amount;
            end
        end
        
        % 2. Evaluate and Inject Stochastic Cash Flows fixing at this exact date
        for c = 1:length(CF_list)
            if ~CF_list(c).is_det && CF_list(c).reset_step == n
                t1 = CF_list(c).reset_time_frac;
                t2 = CF_list(c).underlying_end_frac;
                t_pay = CF_list(c).pay_time_frac;
                
                % Analytical Bond pricing components
                B_term2 = B_hw(t1, t2);
                B_term_pay = B_hw(t1, t_pay);
                
                P_OIS_0_t1  = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, settlementDate + days(round(t1*365)));
                P_OIS_0_t2  = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, settlementDate + days(round(t2*365)));
                P_OIS_0_pay = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, settlementDate + days(round(t_pay*365)));
                
                P_EUR_0_t1  = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, settlementDate + days(round(t1*365)));
                P_EUR_0_t2  = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, settlementDate + days(round(t2*365)));
                
                % Deterministic Beta extraction (Gamma = 0)
                beta_1 = P_OIS_0_t1 / P_EUR_0_t1;
                beta_2 = P_OIS_0_t2 / P_EUR_0_t2;
                
                phi_t1 = phi_hw(t1);
                
                % Multi-Curve forward extraction via node values
                P_OIS_node_t2 = (P_OIS_0_t2 / P_OIS_0_t1) * exp(-B_term2 * x_space - 0.5 * B_term2^2 * phi_t1);
                P_OIS_node_pay = (P_OIS_0_pay / P_OIS_0_t1) * exp(-B_term_pay * x_space - 0.5 * B_term_pay^2 * phi_t1);
                
                P_EUR_node_t2 = P_OIS_node_t2 * (beta_1 / beta_2);
                
                delta_basis = 0.25; % 3M basis
                L_node = (1/delta_basis) * (1 ./ P_EUR_node_t2 - 1);
                
                if isPayer
                    CF_amt = CF_list(c).N * CF_list(c).delta * (L_node - strike);
                else
                    CF_amt = CF_list(c).N * CF_list(c).delta * (strike - L_node);
                end
                
                V = V + CF_amt .* P_OIS_node_pay;
            end
        end
        
        % 3. Measure EPE _after_ resetting CFs are injected
        % (matches the exact exposure of a swaption entered on this date)
        Exposure = max(V, 0);
        EPE(n) = sum(Q(:, n) .* Exposure);
    end
    
    NPV_riskfree = V(mid_idx);
    
    % ---------------------------------------------------------------------
    % 7. CVA INTEGRATION
    % ---------------------------------------------------------------------
    futurePayDates = allPayDates(idx_future);
    
    % Use existing logic to bootstrap Q(T)
    survProbs = bootstrapSurvivalProbabilities(OIS_curve, futurePayDates, cdsSpreads, LGD);
    
    survProbsFull = [1; survProbs];
    CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end); % Q(t_{i-1}) - Q(t_i)
    
    % Interpolate the generic EPE grid precisely to the exact CDS periods
    cds_times = yearfrac(settlementDate, futurePayDates, 3);
    EPE_at_cds = interp1(time_grid, EPE, cds_times, 'linear');
    
    CVA = LGD * sum(CVAsurvProbs .* EPE_at_cds);
    
    final_price = NPV_riskfree - CVA;

end