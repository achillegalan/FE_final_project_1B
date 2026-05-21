function zero_rates = from_discounts_to_zero_rates(dates, discounts)
%FROM_DISCOUNTS_TO_ZERO_RATES Convert discount factors into zero rates.
%
% Supported inputs for `dates`:
%   1) datetime vector of curve dates (first date is the reference date)
%   2) numeric vector of year fractions from the reference date
%
% Output:
%   zero_rates, continuously-compounded zero rates.

    dates = dates(:);
    discounts = discounts(:);

    if numel(dates) ~= numel(discounts)
        error('from_discounts_to_zero_rates:SizeMismatch', ...
            'dates and discounts must have the same length.');
    end

    if isempty(dates)
        error('from_discounts_to_zero_rates:EmptyInput', ...
            'dates and discounts cannot be empty.');
    end

    if isdatetime(dates)
        [dates, idx] = sort(dates);
        discounts = discounts(idx);
        reference_date = dates(1);
        year_fractions = yearfrac(reference_date, dates, 3); % ACT/365
    else
        [year_fractions, idx] = sort(dates);
        discounts = discounts(idx);
    end

    zero_rates = nan(size(discounts));
    positive_tau = year_fractions > 0;

    if ~any(positive_tau)
        error('from_discounts_to_zero_rates:NoPositiveMaturity', ...
            'At least one date must have strictly positive year fraction.');
    end

    zero_rates(positive_tau) = ...
        -log(discounts(positive_tau)) ./ year_fractions(positive_tau);

    % Fill reference-date nodes (tau = 0) with first available short-end zero.
    first_positive = find(positive_tau, 1, 'first');
    zero_rates(~positive_tau) = zero_rates(first_positive);
end
