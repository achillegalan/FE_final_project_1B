function interp_discount = get_discount_factor_by_zero_rates_linear_interp( ...
    reference_date, interp_date, dates, discount_factors)
%GET_DISCOUNT_FACTOR_BY_ZERO_RATES_LINEAR_INTERP Interpolate discount by zero rates.
%
% The function:
%   1) computes continuous zero rates from discount factors
%   2) linearly interpolates zero rates in ACT/365 time
%   3) converts back to discount at interp_date

    dates = dates(:);
    discount_factors = discount_factors(:);

    if numel(dates) ~= numel(discount_factors)
        error('get_discount_factor_by_zero_rates_linear_interp:SizeMismatch', ...
            'dates and discount_factors must have the same length.');
    end

    if isempty(dates)
        error('get_discount_factor_by_zero_rates_linear_interp:EmptyCurve', ...
            'dates and discount_factors cannot be empty.');
    end

    [dates, discount_factors] = sortCurve(dates, discount_factors);

    % Ensure reference date exists and has discount = 1.
    refIdx = find(dates == reference_date, 1);
    if isempty(refIdx)
        dates = [reference_date; dates];
        discount_factors = [1.0; discount_factors];
    else
        discount_factors(refIdx) = 1.0;
    end
    [dates, discount_factors] = sortCurve(dates, discount_factors);

    exactIdx = find(dates == interp_date, 1);
    if ~isempty(exactIdx)
        interp_discount = discount_factors(exactIdx);
        return
    end

    year_fracs = yearfrac(reference_date, dates, 3); % ACT/365
    target_year_fraction = yearfrac(reference_date, interp_date, 3);

    if target_year_fraction < year_fracs(1) || target_year_fraction > year_fracs(end)
        error('get_discount_factor_by_zero_rates_linear_interp:OutOfRange', ...
            'Target date %s outside interpolation range.', string(interp_date));
    end

    % Inline conversion: discounts -> continuous zero rates (Act/365).
    zero_rates = nan(size(discount_factors));
    positive_tau = year_fracs > 0;
    if ~any(positive_tau)
        error('get_discount_factor_by_zero_rates_linear_interp:NoPositiveMaturity', ...
            'At least one curve node must have strictly positive year fraction.');
    end
    zero_rates(positive_tau) = ...
        -log(discount_factors(positive_tau)) ./ year_fracs(positive_tau);

    % For tau = 0 nodes, reuse the first available short-end zero rate.
    first_positive = find(positive_tau, 1, 'first');
    zero_rates(~positive_tau) = zero_rates(first_positive);

    interp_rate = interp1(year_fracs, zero_rates, target_year_fraction, 'linear');

    interp_discount = exp(-interp_rate * target_year_fraction);
end
