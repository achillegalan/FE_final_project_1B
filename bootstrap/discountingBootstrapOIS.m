function [OIS_df, OIS_df_dates] = discountingBootstrapOIS(settlementdate, OIS_rates, OIS_rates_dates)
% DISCOUNTINGBOOTSTRAPOIS Bootstraps the OIS discounting curve from market rates.
%
%   Constructs a discount curve by iteratively solving for the discount factors 
%   of Overnight Indexed Swaps (e.g., €STR/EONIA). Handles short-term instruments 
%   (single payment at maturity) and long-term instruments (annual payments). 
%   Missing annual nodes are derived via linear interpolation on continuously 
%   compounded zero rates.
%
%   INPUTS:
%       settlementdate  - Datetime object representing the spot settlement (e.g., T+2).
%       OIS_rates       - Vector of quoted OIS fixed rates as decimals (e.g., 0.02 for 2%).
%       OIS_rates_dates - Vector of Datetime objects for the maturity of each node.
%
%   OUTPUTS:
%       OIS_df          - Vector of bootstrapped discount factors.
%       OIS_df_dates    - Vector of maturity dates corresponding to the discount factors.
%
%   NOTES:
%       - Strictly uses the Actual/360 day-count convention for year fractions.

%COMMENT: knots == nodes or whatever you like, but let's try to be
%consistent with papers terminology
n_knots = length(OIS_rates);
OIS_df = zeros(n_knots, 1);
OIS_df_dates = OIS_rates_dates;

%Build the yearfracs (from settlement date)
%COMMENT: Euro-denominated interbank rates => Act/360 (but double check)
yearfracs = yearfrac(settlementdate, OIS_rates_dates, 2);

%///BOOTSTRAP ALGO
k = 0;
for i = 1:n_knots
    
    if yearfracs(i) <= 1.0
        OIS_df(i) = 1 / (1 + yearfracs(i) * OIS_rates(i));
        k = k + 1;

    else
        % Find how many strictly annual payments have occurred
        num_annual_payments = floor(yearfracs(i));
        BPV = 0;
        prev_annual_date = settlementdate;
        
        for a = 1:num_annual_payments-1
                annual_date = settlementdate + calyears(a);
                
                %///lin_interp on zero rates ==> derive df
                known_t = yearfracs(1:i-1);
                known_r = -log(OIS_df(1:i-1)) ./ known_t;
                target_t = yearfrac(settlementdate, annual_date, 2);
                interp_r = interp1(known_t, known_r, target_t, 'linear', 'extrap');
                df_annual = exp(-interp_r * target_t);

                % year fraction for this specific annual period
                delta_k = yearfrac(prev_annual_date, annual_date, 2);
                BPV = BPV + (delta_k * df_annual);
                
                prev_annual_date = annual_date;
        end
            delta_i = yearfrac(prev_annual_date, OIS_rates_dates(i), 2);

        numerator = 1 - (OIS_rates(i) * BPV);
        denominator = 1 + (delta_i * OIS_rates(i));
        OIS_df(i) = numerator/denominator;
    end
end

%Sanity check: Ensure no discounts are negative or wildly above 1
assert(all(OIS_df > 0), 'FinEng:BootstrapError', 'Negative discount factor calculated. Check input rates.');
end
