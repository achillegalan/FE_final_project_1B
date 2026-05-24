function value = swapObjectiveCrab(PN, settlementDate, maturityDate, swapRate, ...
                                   knownDates, knownDisc, oisCurve)
% SWAPOBJECTIVECRAB Objective for swap bootstrap.
% INPUTS:
%   PN             - Candidate pseudo-discount factor at the swap maturity.
%   settlementDate - Datetime object representing the curve settlement date.
%   maturityDate   - Datetime object representing the swap maturity date.
%   swapRate       - Quoted fixed swap rate as a decimal.
%   knownDates     - Vector of datetime objects for known pseudo-curve nodes.
%   knownDisc      - Vector of known pseudo-discount factors.
%   oisCurve       - Structure containing OIS discount curve data, with fields:
%                    dates, discounts, settlementDate.
%
% OUTPUTS:
%   value - Difference between floating leg and fixed leg.
%           The bootstrap solves value = 0 for PN.

    % Add to the known curve the possible discount factor
    tmpDates = [knownDates; maturityDate];
    tmpDisc  = [knownDisc; PN];

    %% Floating leg
    floatingLeg = 0;
    floatDates = makeSchedule(settlementDate, maturityDate, 3, 'modifiedfollow');
    floatStart = floatDates(1:end-1);
    floatEnd = floatDates(2:end);
    floatDelta = yearfrac(floatStart, floatEnd, 2);

    for j = 1:numel(floatEnd)
        Tstart = floatStart(j);
        Tend   = floatEnd(j);
        delta = floatDelta(j);
        Pstart = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tstart, tmpDates, tmpDisc);
        Pend   = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tend, tmpDates, tmpDisc);
        forward3M = (Pstart / Pend - 1) / delta;

        oisDiscEnd = get_discount_factor_by_zero_rates_linear_interp( ...
            oisCurve.settlementDate, Tend, oisCurve.dates, oisCurve.discounts);
        floatingLeg = floatingLeg + delta * forward3M * oisDiscEnd;
    end

    %% Fixed leg
    fixedLeg = 0;
    fixedDates = makeSchedule(settlementDate, maturityDate, 12, 'modifiedfollow');
    fixedPrev = fixedDates(1:end-1);
    fixedEnd = fixedDates(2:end);
    fixedDelta = yearfrac(fixedPrev, fixedEnd, 6);

    for i = 1:numel(fixedEnd)
        delta = fixedDelta(i);
        Tend  = fixedEnd(i);
        oisDiscEnd = get_discount_factor_by_zero_rates_linear_interp( ...
            oisCurve.settlementDate, Tend, oisCurve.dates, oisCurve.discounts);
        fixedLeg = fixedLeg + swapRate * delta * oisDiscEnd;
    end

    value = floatingLeg - fixedLeg;
end
