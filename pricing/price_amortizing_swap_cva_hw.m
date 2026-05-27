function [NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw, swap, OIS_curve, EUR3M_curve, cds_data)
    % ---------------------------------------------------------------------
    % PARAMETERS & SETUP
    % ---------------------------------------------------------------------
    a = hw.a; 
    sigma = hw.sigma; 
    
    % Assuming swap.dt is the grid step (e.g., 1/12 for monthly, 0.25 for quarterly)
    dt = swap.dt; 
    N = round(swap.T_max / dt);
    
    % Swap Schedule setup (Mapping payment dates to tree indices)
    % swap.reset_indices contains the tree step index 'n' for each payment period
    reset_idx = swap.reset_indices; 
    num_periods = length(reset_idx);
    
    % Space Grid Setup (Using your exact logic)
    dx = sigma * sqrt(3 * dt);
    j_max = ceil(0.184 / (a * dt)); 
    num_nodes = 2 * j_max + 1;
    j_vec = (j_max:-1:-j_max)'; % Sorted descending (Up is top, Down is bottom)
    x_space = j_vec * dx;    
    
    % Transition Probabilities (Vectorized for the whole grid)
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
            pu(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 + a * j * dt); % Note: flipped sign logic for descending vector
            pm(k) = 2/3 - a^2 * j^2 * dt^2;
            pd(k) = 1/6 + 0.5 * (a^2 * j^2 * dt^2 - a * j * dt);
            idx_u(k) = k-1; idx_m(k) = k; idx_d(k) = k+1;
        end
    end
    
    % ---------------------------------------------------------------------
    % PHASE 1: PRE-CALCULATE DETERMINISTIC SPREAD (BETA)
    % ---------------------------------------------------------------------
    % Under gamma=0 (S0 hypothesis), spread volatility is 0, so beta is deterministic
    beta = zeros(num_periods, 1);
    for k = 1:num_periods
        t_start = swap.t_schedule(k);
        t_end = swap.t_schedule(k+1);
        
        % Extract discounts from initial curves
        P_OIS_start = OIS_curve.Discount(t_start);
        P_OIS_end   = OIS_curve.Discount(t_end);
        P_EUR_start = EUR3M_curve.Discount(t_start);
        P_EUR_end   = EUR3M_curve.Discount(t_end);
        
        % Calculate forward beta
        fwd_OIS = P_OIS_end / P_OIS_start;
        fwd_EUR = P_EUR_end / P_EUR_start;
        beta(k) = fwd_OIS / fwd_EUR;
    end

    % ---------------------------------------------------------------------
    % PHASE 2: FORWARD INDUCTION (ARROW-DEBREU & ALPHA CALIBRATION)
    % ---------------------------------------------------------------------
    Q = zeros(num_nodes, N+1);
    alpha = zeros(N, 1);
    
    % Initial state at t=0
    mid_idx = j_max + 1;
    Q(mid_idx, 1) = 1.0; 
    
    for n = 1:N
        t = (n-1)*dt;
        
        % Find alpha(n) to exactly match the OIS discount curve P(0, t+dt)
        P_market = OIS_curve.Discount(t + dt);
        sum_Q_exp_x = sum(Q(:, n) .* exp(-x_space * dt));
        alpha(n) = (1 / dt) * log(sum_Q_exp_x / P_market);
        
        % Short rate at this slice
        r_t = x_space + alpha(n);
        
        % Propagate Arrow-Debreu prices to the next time step
        % Q(i, n+1) is the sum of Q coming from up, mid, down nodes
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
    % PHASE 3: BACKWARD INDUCTION (NPV)
    % ---------------------------------------------------------------------
    V = zeros(num_nodes, 1); % Swap continuation value
    EPE = zeros(N+1, 1);     % Expected Positive Exposure for CVA
    
    % Hull-White analytical helpers for forward discounts
    B_hw = @(t, T) (1 - exp(-a * (T - t))) / a;
    phi = @(t) (sigma^2 / (2*a)) * (1 - exp(-2*a*t));
    
    current_period = num_periods;
    
    for n = N:-1:1
        t = (n-1) * dt;
        r_t = x_space + alpha(n);
        discount = exp(-r_t * dt);
        
        % 1. Discount future continuation value
        EV = pu .* V(idx_u) + pm .* V(idx_m) + pd .* V(idx_d);
        V = discount .* EV;
        
        % 2. Check if current step is a swap reset date
        if current_period > 0 && n == reset_idx(current_period)
            t_next = swap.t_schedule(current_period + 1);
            tau = t_next - t; % Year fraction (ACT/360)
            
            % Compute OIS Forward Discount analytically using x_space
            B_term = B_hw(t, t_next);
            P_OIS_0_t = OIS_curve.Discount(t);
            P_OIS_0_T = OIS_curve.Discount(t_next);
            
            % Forward OIS Discount at each node
            P_OIS_node = (P_OIS_0_T / P_OIS_0_t) .* exp(-B_term .* x_space - 0.5 * B_term^2 * phi(t));
            
            % Multi-Curve Magic: Pseudo-Discount using deterministic beta
            P_EUR_node = P_OIS_node / beta(current_period);
            
            % Extract Simulated Euribor 3M
            L_node = (1/tau) .* ((1 ./ P_EUR_node) - 1);
            
            % Calculate Cash Flow for this period (Bank receives Float, pays Fixed)
            N_amort = swap.Notional(current_period);
            CF = N_amort .* (L_node - swap.K) .* tau;
            
            % Add discounted cash flow to NPV (discounted back to reset date t)
            V = V + CF .* P_OIS_node;
            
            current_period = current_period - 1;
        end
        
        % 3. Calculate Exposure (Max of Swap Value and 0)
        Exposure = max(V, 0);
        
        % 4. Record Expected Positive Exposure (Weighted by Arrow-Debreu state prices)
        EPE(n) = sum(Q(:, n) .* Exposure);
    end
    
    NPV_riskfree = V(mid_idx); % The value at the root node
    
    % ---------------------------------------------------------------------
    % PHASE 4: CVA CALCULATION
    % ---------------------------------------------------------------------
    CVA = 0;
    LGD = cds_data.LGD;
    
    % Sum over all CDS buckets
    for i = 2:length(cds_data.t)
        % Map CDS time buckets to tree indices
        t_prev = cds_data.t(i-1);
        t_curr = cds_data.t(i);
        
        % Find closest EPE in the tree array (assuming tree matches dates)
        idx_prev = round(t_prev / dt) + 1;
        
        PD_marginal = cds_data.Surv(i-1) - cds_data.Surv(i);
        
        % CVA = LGD * EPE(t_prev) * Marginal Default Probability
        CVA = CVA + LGD * EPE(idx_prev) * PD_marginal;
    end
    
    final_price = NPV_riskfree - CVA;
end