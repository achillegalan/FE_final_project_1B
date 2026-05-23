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

    tmpDates = [knownDates; maturityDate];
    tmpDisc  = [knownDisc; PN];

    [tmpDates, tmpDisc] = sortCurve(tmpDates, tmpDisc);

    floatDates = makeSchedule(settlementDate, maturityDate, 3, 'modifiedfollow');
    fixedDates = makeSchedule(settlementDate, maturityDate, 12, 'modifiedfollow');

    floatingLeg = 0;
    for j = 2:numel(floatDates)
        Tstart = floatDates(j-1);
        Tend   = floatDates(j);
        delta = yearfrac(Tstart, Tend, 2);
        Pstart = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tstart, tmpDates, tmpDisc);
        Pend   = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tend, tmpDates, tmpDisc);
        forward3M = (Pstart / Pend - 1) / delta;
        oisDiscEnd = get_discount_factor_by_zero_rates_linear_interp( ...
            oisCurve.settlementDate, Tend, oisCurve.dates, oisCurve.discounts);
        floatingLeg = floatingLeg + delta * forward3M * oisDiscEnd;
    end

    fixedLeg = 0;
    for i = 2:numel(fixedDates)
        Tprev = fixedDates(i-1);
        Tend  = fixedDates(i);
        delta = yearfrac(Tprev, Tend, 6);
        oisDiscEnd = get_discount_factor_by_zero_rates_linear_interp( ...
            oisCurve.settlementDate, Tend, oisCurve.dates, oisCurve.discounts);
        fixedLeg = fixedLeg + swapRate * delta * oisDiscEnd;
    end

    value = floatingLeg - fixedLeg;
end
