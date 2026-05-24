function interp_discount = get_discount_factor_by_zero_rates_linear_interp( ...
    reference_date, interp_date, dates, discount_factors)

%GET_DISCOUNT_FACTOR_BY_ZERO_RATES_LINEAR_INTERP Interpolates a discount factor using linear interpolation on zero rates.
%
% INPUTS:
%   reference_date      Curve reference date.
%   interp_date         Date at which the discount factor is required.
%   dates               Curve node dates.
%   discount_factors    Discount factors corresponding to dates.
%
% OUTPUT:
%   interp_discount     Discount factor at interp_date, obtained by converting
%                       discounts into continuous ACT/365 zero rates, linearly
%                       interpolating the zero rate, and converting it back into
%                       a discount factor.

    dates = dates(:);
    discount_factors = discount_factors(:);

    %% case 1: we already have the date discount
    exactIdx = find(dates == interp_date, 1);
    if ~isempty(exactIdx)
        interp_discount = discount_factors(exactIdx);
        return
    end

    %% case 2: use linear interpolation to get the zero rate, and then compute the discount factor
    target_tau = yearfrac(reference_date, interp_date, 3); % ACT/365

    % If we're exactly at reference date, DF = 1 by definition
    if target_tau == 0
        interp_discount = 1.0;
        return
    end

    tau = yearfrac(reference_date, dates, 3); % ACT/365
    pos = tau > 0;
    if ~any(pos)
        error('get_discount_factor_by_zero_rates_linear_interp:NoPositiveMaturity', ...
            'At least one curve node must have strictly positive year fraction.');
    end

    tau_pos = tau(pos);
    zr_pos = -log(discount_factors(pos)) ./ tau_pos;
    [tau_pos, uniqueIdx] = unique(tau_pos, 'stable');
    zr_pos = zr_pos(uniqueIdx);

    if numel(tau_pos) == 1
        % With one positive node, use a flat zero rate.
        interp_rate = zr_pos(1);
    elseif target_tau <= tau_pos(1)
        % Flat extrapolation on the short end.
        interp_rate = zr_pos(1);
    elseif target_tau >= tau_pos(end)
        % Flat extrapolation on the long end.
        interp_rate = zr_pos(end);
    else
        interp_rate = interp1(tau_pos, zr_pos, target_tau, 'linear');
    end
    interp_discount = exp(-interp_rate * target_tau);
end
