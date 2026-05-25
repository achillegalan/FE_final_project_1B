function discounts = getTargetDF(evalDate, curveDates, zeroRates, targetDates)
% ZeroRatesToDiscounts - Linearly interpolates zero rates at targetDates
%                        and returns the corresponding discount factors.
%
% INPUTS:
%   evalDate   : settlement/evaluation date (scalar)
%   curveDates : curve pillar dates (Nx1)
%   zeroRates  : continuously-compounded zero rates at pillar dates (Nx1),
%                expressed on ACT/365 tenors from evalDate
%   targetDates: dates where we want discount factors (Mx1)
%
% OUTPUT:
%   discounts  : discount factors at targetDates (Mx1)

curveDates = curveDates(:);
zeroRates = zeroRates(:);
targetDates = targetDates(:);

% Year fractions from evalDate to curve pillars and target dates (ACT/365)
pillarTenors = yearfrac(evalDate, curveDates, 3);
targetTenors = yearfrac(evalDate, targetDates, 3);

% Drop invalid pillar nodes (e.g., NaN zero-rate at settlement tenor = 0).
valid = isfinite(pillarTenors) & isfinite(zeroRates);
pillarTenors = pillarTenors(valid);
pillarRates = zeroRates(valid);

% Linear interpolation in-range + flat extrapolation out-of-range.
if numel(pillarTenors) == 1
    interpRates = repmat(pillarRates, size(targetTenors));
else
    interpRates = interp1(pillarTenors, pillarRates, targetTenors, 'linear', NaN);
    interpRates(targetTenors <= pillarTenors(1)) = pillarRates(1);   % flat short-end
    interpRates(targetTenors >= pillarTenors(end)) = pillarRates(end); % flat long-end
end

discounts = exp(-interpRates .* targetTenors);
discounts(targetTenors == 0) = 1.0;

end
