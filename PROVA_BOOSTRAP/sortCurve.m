function [datesOut, discountsOut] = sortCurve(datesIn, discountsIn)

%SORTCURVE Sort curve and remove duplicate dates.
% INPUTS:
%   datesIn     - Vector of datetime objects representing curve dates.
%   discountsIn - Vector of discount factors corresponding to datesIn.
%
% OUTPUTS:
%   datesOut     - Sorted vector of unique datetime curve dates.
%   discountsOut - Discount factors corresponding to datesOut.
    
    [datesSorted, idx] = sort(datesIn(:));
    discSorted = discountsIn(idx);

    [datesOut, uniqueIdx] = unique(datesSorted, 'stable');
    discountsOut = discSorted(uniqueIdx);
end