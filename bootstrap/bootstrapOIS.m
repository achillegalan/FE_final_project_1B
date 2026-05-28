function OIS_Boot = bootstrapOIS(settlementDate, OIS_input)
%BOOTSTRAPOIS Bootstrap OIS discount factors from market quotes.
%
% INPUTS:
%   settlementDate : Spot settlement date (datetime scalar).
%   OIS_input      : Struct/table with fields:
%                      - Term       (e.g. '6 MO', '10 YR')
%                      - MarketRate (decimal rates, not percentages)
%
% OUTPUT:
%   OIS_Boot struct with fields:
%     - settlementDate : curve reference date
%     - dates          : bootstrap node dates
%     - discounts      : discount factors at node dates
%     - zeroRates      : continuous zero rates (ACT/365)
%     - marketRates    : input rates sorted by maturity

OIS_rates = OIS_input.MarketRate(:);
OIS_rates_dates = convertTermToDays(OIS_input.Term, settlementDate);

% Sort maturities and keep rates aligned
[OIS_df_dates, sortIdx] = sort(OIS_rates_dates);
sortedRates = OIS_rates(sortIdx);

n_knots = numel(sortedRates);
OIS_df = zeros(n_knots, 1);

% Year fractions from settlement date on ACT/360 (used for <=1Y instruments)
yearfracs = yearfrac(settlementDate, OIS_df_dates, 2);

for i = 1:n_knots
    if yearfracs(i) <= 1.0
        OIS_df(i) = 1 / (1 + yearfracs(i) * sortedRates(i));
        continue
    end

    % Build annual fixed-leg schedule backward from swap maturity
    % (Modified Following adjustment at each yearly step).
    pay_dates = OIS_df_dates(i);
    probe_date = OIS_df_dates(i);

    while (probe_date - calyears(1)) > settlementDate
        probe_date = modifiedFollowing(probe_date - calyears(1));
        pay_dates = [probe_date; pay_dates]; 
    end

    pay_dates = [settlementDate; pay_dates];

    % Previous known node (last solved maturity before current one).
    prev_t = yearfrac(settlementDate, OIS_df_dates(i-1), 3); % ACT/365
    prev_df = OIS_df(i-1);
    prev_r = -log(prev_df) / prev_t;
    
    % Current maturity in ACT/365 years.
    curr_t = yearfrac(settlementDate, OIS_df_dates(i), 3);
    
    % Initial DF guess based on flat extrapolation from previous node.
    guess_df = prev_df * exp(-sortedRates(i) * (curr_t - prev_t));
    
    % Solve current DF so that swap residual = 0.
    objective = @(curr_df) swapResidualOIS(curr_df, curr_t, prev_t, prev_r, ...
        settlementDate, pay_dates, OIS_df_dates, OIS_df, sortedRates(i), i);
    
    OIS_df(i) = fzero(objective, guess_df);
end

% Continuous zero rates on ACT/365 for output/reporting.
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

%------------------------- Helper -----------------------------------------
function res = swapResidualOIS(curr_df, curr_t, prev_t, prev_r, settlementDate, ...
    pay_dates, OIS_df_dates, OIS_df, swapRate, i)
%SWAPRESIDUALOIS Residual of OIS par equation for one maturity.

% Convert the unknown discount factor at current maturity into a
% continuously-compounded zero rate (ACT/365 basis).
curr_r = -log(curr_df) / curr_t;

% BPV (annuity) of the fixed leg for this OIS maturity:
% sum_k delta_k * DF(payment_k).
BPV = 0;

for p = 2:numel(pay_dates)

    pay_date = pay_dates(p);
    target_t = yearfrac(settlementDate, pay_date, 3); % ACT/365

    if target_t <= prev_t
        % Payment date is at or before the last known curve node:
        % use interpolation from already-bootstrapped nodes only.

        known_t = yearfrac(settlementDate, OIS_df_dates(1:i-1), 3);
        known_r = -log(OIS_df(1:i-1)) ./ known_t;

        interp_r = interp1(known_t, known_r, target_t, 'linear', 'extrap');

    else
        % Payment date falls between previous and current maturity:
        % interpolate linearly between previous known zero rate and
        % current trial zero rate implied by curr_df.

        lambda = (target_t - prev_t) / (curr_t - prev_t);

        interp_r = (1 - lambda) * prev_r + lambda * curr_r;
    end

    % Convert interpolated zero rate back to discount factor at pay_date.
    df_pay = exp(-interp_r * target_t);

    delta_k = yearfrac(pay_dates(p-1), pay_dates(p), 2); % ACT/360

    % Accumulate fixed-leg annuity contribution.
    BPV = BPV + delta_k * df_pay;
end

% OIS par condition for root-finding:
% fixed leg PV - floating leg PV = 0.
PV_fixed = swapRate * BPV;
PV_float = 1 - curr_df;
res = PV_fixed - PV_float;

end
