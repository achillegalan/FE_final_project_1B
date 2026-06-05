function value = swapObjectiveCrab(PN, settlementDate, maturityDate, ...
                                   knownDates, knownDisc, swapCache)
%SWAPOBJECTIVECRAB Objective function for one pseudo-curve swap node.
%
% INPUTS:
%   PN             : Trial pseudo-discount factor at maturityDate.
%   settlementDate : Curve settlement date.
%   maturityDate   : Underlying swap maturity date (new node to solve).
%   knownDates     : Already-bootstrapped pseudo-curve node dates.
%   knownDisc      : Already-bootstrapped pseudo-curve discounts.
%   swapCache      : Precomputed constants for this swap, with fields:
%                      - floatStart       : floating period start dates
%                      - floatEnd         : floating period end dates
%                      - floatDelta       : ACT/360 accruals of floating leg
%                      - oisDiscFloatEnd  : OIS DFs at floating payment dates
%                      - fixedLegConst    : market fixed rate * fixed-leg annuity
%
% OUTPUT:
%   value          : Residual (floating PV - fixed PV). Root at zero.

    floatStart = swapCache.floatStart;
    floatEnd = swapCache.floatEnd;
    floatDelta = swapCache.floatDelta;
    oisDiscFloatEnd = swapCache.oisDiscFloatEnd;
    fixedLeg = swapCache.fixedLegConst;

    % Add to the known curve the possible discount factor
    tmpDates = [knownDates; maturityDate];
    tmpDisc  = [knownDisc; PN];

    %% Floating leg
    tau = yearfrac(settlementDate, tmpDates, 3);
    zeroRates = nan(size(tmpDisc));

    isAfterSettlement = tau > 0;
    zeroRates(isAfterSettlement) = ...
        -log(tmpDisc(isAfterSettlement)) ./ tau(isAfterSettlement);

    Pstart = getTargetDF(settlementDate, tmpDates, zeroRates, floatStart(:));
    Pend   = getTargetDF(settlementDate, tmpDates, zeroRates, floatEnd(:));

    forward3M = (Pstart ./ Pend - 1) ./ floatDelta(:);
    floatingLeg = sum(floatDelta(:) .* forward3M .* oisDiscFloatEnd(:));

    %% total
    value = floatingLeg - fixedLeg;
end
