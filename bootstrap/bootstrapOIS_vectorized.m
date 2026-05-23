function OIS_Boot = bootstrapOIS_vectorized(settlementDate, OIS_input)

%BOOTSTRAPOIS_VECTORIZED Bootstraps the OIS discounting curve.
%
% INPUTS:
%   settlementDate   Curve settlement date.
%   OIS_input        Struct/table containing OIS market data, with fields:
%                    - Term: OIS maturities.
%                    - MarketRate: corresponding OIS market rates.
%
% OUTPUT:
%   OIS_Boot         Struct containing:
%                    - settlementDate: curve settlement date.
%                    - dates: OIS bootstrap node dates.
%                    - discounts: OIS discount factors on bootstrap nodes.
%                    - zeroRates: continuous ACT/365 zero rates computed from discounts.
%                    - marketRates: sorted OIS market rates used in the bootstrap.

% Sorting and Initialization
OIS_rates = OIS_input.MarketRate(:);
OIS_rates_dates = convertTermToDays(OIS_input.Term, settlementDate);

[OIS_df_dates, sortIdx] = sort(OIS_rates_dates);
sortedRates = OIS_rates(sortIdx);
n_knots = numel(sortedRates);
OIS_df = zeros(n_knots, 1);
yearfracs = yearfrac(settlementDate, OIS_df_dates, 2); % Act/360

% BOOTSTRAPPING (Sequential outer loop, Vectorized inner loops)
for i = 1:n_knots
    % Short-end nodes (<= 1Y)
    if yearfracs(i) <= 1.0
        OIS_df(i) = 1 / (1 + yearfracs(i) * sortedRates(i));
        continue
    end

    if i == 1
        error('discountingBootstrapOIS:invalidFirstNode', ...
            'First maturity is beyond 1Y. Add short-end OIS instruments before swaps.');
    end
    
    % --- VECTORIZED SCHEDULE GENERATION ---
    % Calculate full years between settlement and the swap maturity
    numYears = floor(yearfracs(i)); 
    
    % Generate the raw annual dates backward from maturity
    rawDates = OIS_df_dates(i) - calyears(1:numYears)';
    
    % Keep only dates strictly greater than the settlement date
    rawDates = rawDates(rawDates > settlementDate);
    
    % Apply business day convention to the whole array at once, then sort
    adjDates = sort(modifiedFollowing(rawDates));
    
    % Construct the final schedule [Settlement -> Intermediate -> Maturity]
    pay_dates = [settlementDate; adjDates; OIS_df_dates(i)];
    
    % --- VECTORIZED BPV CALCULATION ---
    target_dates = pay_dates(2:end-1);
    prev_dates   = pay_dates(1:end-2);
    
    if isempty(target_dates)
        BPV = 0;
    else
        % Hoist known curve history outside array operations
        known_t = yearfracs(1:i-1);
        known_r = -log(OIS_df(1:i-1)) ./ known_t;
        
        target_t = yearfrac(settlementDate, target_dates, 2);
        delta_k  = yearfrac(prev_dates, target_dates, 2);
        
        interp_r = interp1(known_t, known_r, target_t, 'linear', 'extrap');
        df_pay   = exp(-interp_r .* target_t);
        
        BPV = sum(delta_k .* df_pay);
    end
    
    % Solve for terminal discount factor
    delta_i = yearfrac(pay_dates(end-1), pay_dates(end), 2);
    OIS_df(i) = (1 - sortedRates(i) * BPV) / (1 + sortedRates(i) * delta_i);
end

assert(all(OIS_df > 0), 'FinEng:BootstrapError', ...
    'Negative discount factor calculated. Check input rates.');

% Outputs
% Continuous zero rates on Act/365
tau_ois = yearfrac(settlementDate, OIS_df_dates, 3);
zeroRates_ois = nan(size(OIS_df));
isAfterSettle = tau_ois > 0;
zeroRates_ois(isAfterSettle) = -log(OIS_df(isAfterSettle)) ./ tau_ois(isAfterSettle);

OIS_Boot = struct();
OIS_Boot.settlementDate = settlementDate;
OIS_Boot.dates = OIS_df_dates;
OIS_Boot.discounts = OIS_df;
OIS_Boot.zeroRates = zeroRates_ois;
OIS_Boot.marketRates = sortedRates;

end
