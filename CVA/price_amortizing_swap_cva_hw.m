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
    % 3. TREE GEOMETRY (con limiti per a=0)
    % ---------------------------------------------------------------------
    a = hw.a;
    tol = 1e-6;
    if abs(a) < tol
        a = 0;
    end
    sigma = hw.sigma;
    dx = sigma * sqrt(3 * dt);
    
    % Cap j_max to prevent 'Inf' when a=0 (Ho-Lee limit)
    if a == 0
        j_max = N + 1; % Lasciamo espandere l'albero liberamente senza troncare
    else
        j_max = min(N + 1, ceil(0.184 / (a * dt))); 
    end
    
    num_nodes = 2 * j_max + 1;
    j_vec = (j_max:-1:-j_max)';
    x_space = j_vec * dx;
    
    pu = zeros(num_nodes, 1); pm = zeros(num_nodes, 1); pd = zeros(num_nodes, 1);
    idx_u = zeros(num_nodes, 1); idx_m = zeros(num_nodes, 1); idx_d = zeros(num_nodes, 1);
    
    for k = 1:num_nodes
        j = j_vec(k);
        
        % Boundaries safely handled for a=0 limit
        if j == j_max
            if a == 0
                pu(k) = 0; pm(k) = 1; pd(k) = 0; 
                idx_u(k) = k; idx_m(k) = k; idx_d(k) = k;
            else
                pu(k) = 7/6 + 0.5 * (a^2 * j^2 * dt^2 - 3 * a * j * dt);
                pm(k) = -1/3 - a^2 * j^2 * dt^2 + 2 * a * j * dt;
                pd(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 - a * j * dt);
                idx_u(k) = k; idx_m(k) = k+1; idx_d(k) = k+2;
            end
        elseif j == -j_max
            if a == 0
                pu(k) = 0; pm(k) = 1; pd(k) = 0; 
                idx_u(k) = k; idx_m(k) = k; idx_d(k) = k;
            else
                pu(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 + a * j * dt);
                pm(k) = -1/3 - a^2 * j^2 * dt^2 - 2 * a * j * dt;
                pd(k) = 7/6 + 0.5 * (a^2 * j^2 * dt^2 + 3 * a * j * dt);
                idx_u(k) = k-2; idx_m(k) = k-1; idx_d(k) = k;
            end
        else
            pu(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 + a * j * dt);
            pm(k) = 2/3 - a^2 * j^2 * dt^2;
            pd(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 - a * j * dt);
            idx_u(k) = k-1; idx_m(k) = k; idx_d(k) = k+1;
        end
    end
    
    % ---------------------------------------------------------------------
    % 4. FORWARD INDUCTION (STATE PROBABILITIES)
    % ---------------------------------------------------------------------
    Q = zeros(num_nodes, N+1);
    mid_idx = j_max + 1;
    Q(mid_idx, 1) = 1.0;
    
    % Precompute Market Discounts for the Grid Dates
    dates_grid = settlementDate + days(round(time_grid * 365));
    P_OIS_grid = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, dates_grid);
    
    for n = 1:N
        for k = 1:num_nodes
            if Q(k, n) > 0
                val = Q(k, n); % pure transition probabilities (no discounting)
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
                     'underlying_end_frac', {}, 'exact_date_reset', {}, ...
                     'exact_date_end', {}, 'exact_date_pay', {});
                     
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
        
        % Calcolo esatto della Fixing Date (2 bd prima dello start)
        fixingDate = add_target_business_days(t_reset, -2);
        
        % Valutazione sulla fixingDate: è un tasso storicamente fissato?
        is_det = false;
        det_rate = 0;
        
        if fixingDate <= settlementDate
            is_det = true;
            if nargin >= 11 && ~isempty(knownFixing) && ~isnan(knownFixing.resetRate)
                det_rate = knownFixing.resetRate;
            else
                % Implied forward rate fallback se il fixing reale non è fornito
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
        
        % Calcolo della yearfrac reale per il pricing analitico B(t,T)
        new_cf.underlying_end_frac = yearfrac(settlementDate, t_accEnd, 3);
        
        % Salvataggio date esatte per estrazione precisa dei market discount factors
        new_cf.exact_date_reset = t_reset;
        new_cf.exact_date_end   = t_accEnd;
        new_cf.exact_date_pay   = t_pay;
        
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
    
    % L'Hôpital's continuous limits for a=0
    if a == 0
        B_hw = @(t, T) (T - t);
        phi_hw = @(t) sigma^2 * t;
    else
        B_hw = @(t, T) (1 - exp(-a * (T - t))) / a;
        phi_hw = @(t) (sigma^2 / (2*a)) * (1 - exp(-2*a*t));
    end

    for n = (N+1):-1:1
                
        % Discount the Continuation Value (except at the exact end)
        if n <= N
            discount = P_OIS_grid(n+1) / P_OIS_grid(n); % Deterministic OIS
            EV = pu .* V(idx_u) + pm .* V(idx_m) + pd .* V(idx_d);
            V = discount .* EV;
        end
        
        % CORRECTION 1: Inject Stochastic Cash Flows BEFORE measuring EPE
        % This ensures the value of the locked-in floating cash flow is recorded 
        % in the EPE on the exact reset_step so we can carry it forward later.
        for c = 1:length(CF_list)
            if ~CF_list(c).is_det && CF_list(c).reset_step == n
                t1 = CF_list(c).reset_time_frac;
                t2 = CF_list(c).underlying_end_frac;
                
                % Analytical Bond pricing components
                B_term2 = B_hw(t1, t2);
                phi_t1 = phi_hw(t1);
                
                % Date REALI dal termsheet per calcolare i market DF corretti
                date1 = CF_list(c).exact_date_reset;
                date2 = CF_list(c).exact_date_end;
                date_pay = CF_list(c).exact_date_pay;
                
                P_OIS_0_t1  = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, date1);
                P_OIS_0_pay = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, date_pay);
                
                P_EUR_0_t1  = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, date1);
                P_EUR_0_t2  = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, date2);
                
                % OIS is purely deterministic (Gamma = 0)
                P_OIS_node_pay = (P_OIS_0_pay / P_OIS_0_t1); 
                
                % Euribor holds the full HW volatility
                P_EUR_node_t2 = (P_EUR_0_t2 / P_EUR_0_t1) * exp(-B_term2 * x_space - 0.5 * B_term2^2 * phi_t1);
                
                % Dynamic year fraction basata su ACT/360 esatta precalcolata
                delta_basis = CF_list(c).delta; 
                L_node = (1/delta_basis) * (1 ./ P_EUR_node_t2 - 1);
                
                if isPayer
                    CF_amt = CF_list(c).N * delta_basis * (L_node - strike);
                else
                    CF_amt = CF_list(c).N * delta_basis * (strike - L_node);
                end
                
                V = V + CF_amt .* P_OIS_node_pay;
            end
        end
        
        % CORRECTION 2: Measure EPE BEFORE deterministic cash flows are injected
        % (Right-Limit: evaluate exposure immediately *after* today's payment is made)
        % V holds future cash flows, but NOT the deterministic CF paid today.
        Exposure = max(V, 0);
        EPE(n) = P_OIS_grid(n) * sum(Q(:, n) .* Exposure);
        
        % CORRECTION 3: Inject fully deterministic cash flows AFTER EPE is measured
        % Now V includes today's payment, so as the tree steps back to yesterday,
        % the exposure will accurately reflect that the money is owed again.
        for c = 1:length(CF_list)
            if CF_list(c).is_det && CF_list(c).pay_step == n
                V = V + CF_list(c).amount;
            end
        end
    end
    
    NPV_riskfree = V(mid_idx);
    
    % =========================================================================
    % 6.5 POST-PROCESSING: THE EXPOSURE INTERPOLATION HEURISTIC
    % =========================================================================
    % The raw EPE array drops to 0 between reset_step and pay_step for floating
    % cash flows. We manually "carry forward" the valid EPE calculated at the reset_step.
    
    EPE_patched = EPE; 
    
    for c = 1:length(CF_list)
        if ~CF_list(c).is_det
            r_step = CF_list(c).reset_step;
            p_step = CF_list(c).pay_step;
            
            % Ensure indices are within bounds
            if r_step >= 1 && r_step <= length(EPE)
                % The valid exposure is exactly at the reset step
                valid_EPE = EPE(r_step);
                
                % Fill the "blind spot" from just after the reset up to the payment
                for n_idx = (r_step + 1) : min(p_step, length(EPE))
                    % Only overwrite if the patched value is higher 
                    % (prevents accidentally overwriting overlapping cash flows)
                    EPE_patched(n_idx) = max(EPE_patched(n_idx), valid_EPE);
                end
            end
        end
    end
    
    EPE = EPE_patched;

    % ---------------------------------------------------------------------
    % 7. CVA INTEGRATION
    % ---------------------------------------------------------------------
    futurePayDates = allPayDates(idx_future);
    
    survProbs = bootstrapSurvivalProbabilities(OIS_curve, futurePayDates, cdsSpreads, LGD);
    
    survProbsFull = [1; survProbs];
    CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end); % Q(t_{i-1}) - Q(t_i)
    
    % Interpolate the generic EPE grid precisely to the exact CDS periods
    cds_times = yearfrac(settlementDate, futurePayDates, 3);
    EPE_at_cds = interp1(time_grid, EPE, cds_times, 'linear');
    
    CVA = LGD * sum(CVAsurvProbs .* EPE_at_cds);
    
    final_price = NPV_riskfree - CVA;
end