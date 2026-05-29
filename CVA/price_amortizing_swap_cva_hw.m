function [NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw,...
     swapData, OIS_curve, EUR3M_curve, settlementDate, strike,...\
     isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing)
% PRICE_AMORTIZING_SWAP_CVA_HW Prices an amortizing swap and its CVA using a 
% Hull-White Trinomial Tree under the Multi-Curve framework (gamma = 0).

    % ---------------------------------------------------------------------
    % 1. EXTRACT & FILTER SWAP DATA
    % ---------------------------------------------------------------------
    allPayDates = swapData.PayDate;
    allAccStarts = swapData.AccrualStart;
    allAccEnds = swapData.AccrualEnd;
    allNotionals = swapData.Notional;
    
    idx_future = find(allPayDates > settlementDate);
    if isempty(idx_future)
        NPV_riskfree = 0; CVA = 0; final_price = 0; 
        return;
    end
    
    % ---------------------------------------------------------------------
    % 2. TIME GRID SETUP
    % ---------------------------------------------------------------------
    dt = 1/24; 
    T_max = yearfrac(settlementDate, max(allPayDates(idx_future)), 3);
    N = ceil(T_max / dt);
    time_grid = (0:N)' * dt;
    
    % ---------------------------------------------------------------------
    % 3. TREE GEOMETRY
    % ---------------------------------------------------------------------
    a = hw.a;
    tol = 1e-6;
    if abs(a) < tol
        a = 0;
    end
    sigma = hw.sigma;
    dx = sigma * sqrt(3 * dt);
    
    if a == 0
        j_max = N + 1; 
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
            pu(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 - a * j * dt);
            pm(k) = 2/3 - a^2 * j^2 * dt^2;
            pd(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 + a * j * dt);
            idx_u(k) = k-1; idx_m(k) = k; idx_d(k) = k+1;
        end
    end
    
    % Added the zeta_hw convexity correction term
    if a == 0
        B_hw = @(t, T) (T - t);
        phi_hw = @(t) sigma^2 * t;
        zeta_hw = @(t) 0.5 * sigma^2 * t^2;
    else
        B_hw = @(t, T) (1 - exp(-a * (T - t))) / a;
        phi_hw = @(t) (sigma^2 / (2*a)) * (1 - exp(-2*a*t));
        zeta_hw = @(t) (sigma^2 / (2*a^2)) * (1 - exp(-a*t))^2;
    end

    % ---------------------------------------------------------------------
    % 4. FORWARD INDUCTION (ARROW-DEBREU STATE PRICES)
    % ---------------------------------------------------------------------
    AD = zeros(num_nodes, N+1);
    mid_idx = j_max + 1;
    AD(mid_idx, 1) = 1.0;
    
    dates_grid = settlementDate + days(round(time_grid * 365));
    P_OIS_grid = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, dates_grid);
    
    for n = 1:N
        t_curr = time_grid(n);
        t_next = time_grid(n+1);
        
        B_step = B_hw(t_curr, t_next);
        phi_curr = phi_hw(t_curr);
        zeta_curr = zeta_hw(t_curr); % Fetch Zeta
        
        discount_det = P_OIS_grid(n+1) / P_OIS_grid(n); 
        % Added - B_step * zeta_curr
        discount_stoch = exp(-B_step * x_space - 0.5 * B_step^2 * phi_curr - B_step * zeta_curr);
        discount_node_fwd = discount_det .* discount_stoch;

        for k = 1:num_nodes
            if AD(k, n) > 0
                val = AD(k, n) * discount_node_fwd(k);
                AD(idx_u(k), n+1) = AD(idx_u(k), n+1) + val * pu(k);
                AD(idx_m(k), n+1) = AD(idx_m(k), n+1) + val * pm(k);
                AD(idx_d(k), n+1) = AD(idx_d(k), n+1) + val * pd(k);
            end
        end
    end
    
    % ---------------------------------------------------------------------
    % 5. MAP CASH FLOWS TO TREE
    % ---------------------------------------------------------------------
    CF_list = struct('is_det', {}, 'amount', {}, 'pay_step', {}, 'reset_step', {}, ...
                     'N', {}, 'delta', {}, 'delta_fixing', {}, 'reset_time_frac', {}, ...
                     'pay_time_frac', {}, 'underlying_end_frac', {}, ...
                     'exact_date_reset', {}, 'exact_date_end', {}, 'exact_date_pay', {});
                     
    for c = 1:length(idx_future)
        idx = idx_future(c);
        
        t_pay = allPayDates(idx);
        t_accStart = allAccStarts(idx);
        t_accEnd = allAccEnds(idx);
        N_notional = allNotionals(idx);
        delta = yearfrac(t_accStart, t_accEnd, 2); 
        
        if strcmpi(fixingFrequency, 'semiannual')
            if mod(idx, 2) == 0 && idx > 1
                t_reset = allAccStarts(idx-1); 
                t_underlying_end = allAccEnds(idx-1); 
            else
                t_reset = t_accStart;
                t_underlying_end = t_accEnd;
            end
        else
            t_reset = t_accStart;
            t_underlying_end = t_accEnd;
        end
        
        fixingDate = add_target_business_days(t_reset, -2);
        is_det = false;
        det_rate = 0;
        
        if fixingDate <= settlementDate
            is_det = true;
            if nargin >= 11 && ~isempty(knownFixing) && ~isnan(knownFixing.resetRate)
                det_rate = knownFixing.resetRate;
            else
                P_E_start = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, t_reset);
                P_E_end = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, t_underlying_end);
                delta_fallback = yearfrac(t_reset, t_underlying_end, 2);
                det_rate = (P_E_start / P_E_end - 1) / delta_fallback;
            end
        end
        
        pay_time = max(0, yearfrac(settlementDate, t_pay, 3));
        reset_time = max(0, yearfrac(settlementDate, t_reset, 3));
        
        pay_step = round(pay_time / dt) + 1;
        reset_step = round(reset_time / dt) + 1;
        
        new_cf.is_det = is_det;
        new_cf.pay_step = pay_step;
        new_cf.reset_step = reset_step;
        new_cf.N = N_notional;
        new_cf.delta = delta;
        new_cf.delta_fixing = yearfrac(t_reset, t_underlying_end, 2); 
        new_cf.reset_time_frac = reset_time;
        new_cf.pay_time_frac = pay_time;
        
        new_cf.underlying_end_frac = max(0, yearfrac(settlementDate, t_underlying_end, 3));
        new_cf.exact_date_reset = t_reset;
        new_cf.exact_date_end   = t_underlying_end;
        new_cf.exact_date_pay   = t_pay;
        
        if is_det
            if isPayer
                new_cf.amount = N_notional * delta * (det_rate - strike);
            else
                new_cf.amount = N_notional * delta * (strike - det_rate);
            end
        else
            new_cf.amount = 0; 
        end
        
        CF_list(c) = new_cf;
    end
    
    % ---------------------------------------------------------------------
    % 6. BACKWARD INDUCTION (NPV & EPE)
    % ---------------------------------------------------------------------
    V = zeros(num_nodes, 1);
    EPE = zeros(N+1, 1);

    for n = (N+1):-1:1
                
        if n <= N
            t_curr = time_grid(n);
            t_next = time_grid(n+1);
            
            B_step = B_hw(t_curr, t_next);
            phi_curr = phi_hw(t_curr);
            zeta_curr = zeta_hw(t_curr); % Fetch Zeta
            
            discount_det = P_OIS_grid(n+1) / P_OIS_grid(n); 
            
            % Added - B_step * zeta_curr
            discount_stoch = exp(-B_step * x_space - 0.5 * B_step^2 * phi_curr - B_step * zeta_curr);
            discount_node = discount_det .* discount_stoch;
            
            EV = pu .* V(idx_u) + pm .* V(idx_m) + pd .* V(idx_d);
            V = discount_node .* EV;
        end
        
        for c = 1:length(CF_list)
            if ~CF_list(c).is_det && CF_list(c).reset_step == n
                t1 = CF_list(c).reset_time_frac;
                t2 = CF_list(c).underlying_end_frac;
                
                B_term2 = B_hw(t1, t2);
                B_term_pay = B_hw(t1, CF_list(c).pay_time_frac);
                phi_t1 = phi_hw(t1);
                zeta_t1 = zeta_hw(t1); % Fetch Zeta
                
                date1 = CF_list(c).exact_date_reset;
                date2 = CF_list(c).exact_date_end;
                date_pay = CF_list(c).exact_date_pay;
                
                P_OIS_0_t1  = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, date1);
                P_OIS_0_pay = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, date_pay);
                
                P_EUR_0_t1  = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, date1);
                P_EUR_0_t2  = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, date2);
                
                % CORRECTED: Added - B_term * zeta_t1 to analytical bond formulas
                P_OIS_node_pay = (P_OIS_0_pay / P_OIS_0_t1) .* exp(-B_term_pay * x_space - 0.5 * B_term_pay^2 * phi_t1 - B_term_pay * zeta_t1); 
                P_EUR_node_t2 = (P_EUR_0_t2 / P_EUR_0_t1) * exp(-B_term2 * x_space - 0.5 * B_term2^2 * phi_t1 - B_term2 * zeta_t1);
                
                delta_basis = CF_list(c).delta; 
                delta_fix = CF_list(c).delta_fixing; 
                L_node = (1/delta_fix) * (1 ./ P_EUR_node_t2 - 1);
                
                if isPayer
                    CF_amt = CF_list(c).N * delta_basis * (L_node - strike);
                else
                    CF_amt = CF_list(c).N * delta_basis * (strike - L_node);
                end
                
                V = V + CF_amt .* P_OIS_node_pay;
            end
        end
        
        Exposure = max(V, 0);
        EPE(n) = sum(AD(:, n) .* Exposure); 
        
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
    EPE_patched = EPE; 
    all_pay_steps = unique([CF_list.pay_step]);
    
    for c = 1:length(CF_list)
        if ~CF_list(c).is_det
            r_step = CF_list(c).reset_step;
            p_step = CF_list(c).pay_step;
            
            if r_step >= 1 && r_step <= length(EPE)
                valid_EPE = EPE(r_step);
                
                future_pay_steps = all_pay_steps(all_pay_steps > r_step);
                if ~isempty(future_pay_steps)
                    next_swap_pay_step = min(future_pay_steps);
                else
                    next_swap_pay_step = p_step;
                end
                
                patch_end = min(next_swap_pay_step, length(EPE));
                
                for n_idx = (r_step + 1) : patch_end
                    decay_factor = P_OIS_grid(n_idx) / P_OIS_grid(r_step);
                    decayed_EPE = valid_EPE * decay_factor;
                    EPE_patched(n_idx) = max(EPE_patched(n_idx), decayed_EPE);
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
    CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end); 
    
    cds_times = yearfrac(settlementDate, futurePayDates, 3);
    EPE_at_cds = interp1(time_grid, EPE, cds_times, 'linear');
    
    CVA = LGD * sum(CVAsurvProbs .* EPE_at_cds);
    final_price = NPV_riskfree - CVA;
end