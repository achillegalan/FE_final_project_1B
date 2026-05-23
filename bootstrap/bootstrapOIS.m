function OIS_Boot = bootstrapOIS(settlementDate, OIS_input)
%DISCOUNTINGBOOTSTRAPOIS Bootstrap OIS curve and return a curve struct.
%
% Constructs a discount curve by iteratively solving OIS discount factors.
% Short-term nodes (<= 1Y) are treated as single cashflow instruments,
% longer maturities are solved from annual fixed-leg payments.
%
% INPUTS:
%   settlementDate - Spot settlement date (datetime)
%
%   Syntax:
%   bootstrapOIS(settlementDate, OIS_Curve)
%     OIS_Curve must contain:
%       - Term
%       - MarketRate
%
% OUTPUTS:   OIS_Boot struct with fields:
%     - settlementDate
%     - dates
%     - discounts
%     - zeroRates
%     - marketRates

OIS_rates = OIS_input.MarketRate(:);
OIS_rates_dates = convertTermToDays(OIS_input.Term, settlementDate);

% Sort maturities and keep rates aligned
[OIS_df_dates, sortIdx] = sort(OIS_rates_dates);
sortedRates = OIS_rates(sortIdx);

n_knots = numel(sortedRates);
OIS_df = zeros(n_knots, 1);

% Year fractions from settlement date (Act/360)
yearfracs = yearfrac(settlementDate, OIS_df_dates, 2);

for i = 1:n_knots
    if yearfracs(i) <= 1.0
        OIS_df(i) = 1 / (1 + yearfracs(i) * sortedRates(i));
        continue
    end

    if i == 1
        error('discountingBootstrapOIS:invalidFirstNode', ...
            'First maturity is beyond 1Y. Add short-end OIS instruments before swaps.');
    end

    % Build annual payment schedule backward from swap maturity
    pay_dates = OIS_df_dates(i);
    probe_date = OIS_df_dates(i);

    while (probe_date - calyears(1)) > settlementDate
        probe_date = modifiedFollowing(probe_date - calyears(1));
        pay_dates = [probe_date; pay_dates]; 
    end

    pay_dates = [settlementDate; pay_dates];

    BPV = 0;
    for p = 2:(numel(pay_dates)-1)
        pay_date = pay_dates(p);

        known_t = yearfracs(1:i-1);
        known_r = -log(OIS_df(1:i-1)) ./ known_t;
        target_t = yearfrac(settlementDate, pay_date, 2);
        interp_r = interp1(known_t, known_r, target_t, 'linear', 'extrap');
        df_pay = exp(-interp_r * target_t);

        delta_k = yearfrac(pay_dates(p-1), pay_date, 2);
        BPV = BPV + delta_k * df_pay;
    end

    delta_i = yearfrac(pay_dates(end-1), pay_dates(end), 2);
    OIS_df(i) = (1 - sortedRates(i) * BPV) / (1 + sortedRates(i) * delta_i);
end

assert(all(OIS_df > 0), 'FinEng:BootstrapError', ...
    'Negative discount factor calculated. Check input rates.');

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