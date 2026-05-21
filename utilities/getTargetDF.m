function discounts = getTargetDF(evalDate, curveDates, zeroRates, targetDates)
% ZeroRatesToDiscounts - Linearly interpolates zero rates at targetDates
%                        and returns the corresponding discount factors.
%
% INPUTS:
%   evalDate   : settlement/evaluation date (scalar)
%   curveDates : curve pillar dates (Nx1)
%   zeroRates  : zero rates at pillar dates (Nx1), Act/360 convention
%   targetDates: dates where we want discount factors (Mx1)
%
% OUTPUT:
%   discounts  : discount factors at targetDates (Mx1)

% Yearfracs from evalDate to curve pillars and target dates (Act/365) 
pillarTenors = yearfrac(evalDate, curveDates, 3);
targetTenors = yearfrac(evalDate, targetDates, 3);

% Linear interpolation of zero rates at target tenors
% interp1 with 'linear' and 'extrap' handles flat extrapolation implicitly
interpRates = interp1(pillarTenors, zeroRates, targetTenors, 'linear', 'extrap');

discounts = exp(-interpRates .* targetTenors);

end