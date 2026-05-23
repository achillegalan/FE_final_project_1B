function value = swapObjectiveCrab(PN, settlementDate, maturityDate, swapRate, ...
                                   knownDates, knownDisc, oisCurve, varargin)
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
%   precomputed    - Optional struct with precomputed schedules/deltas/OIS
%                    discounts to speed up repeated objective evaluations.
%
% OUTPUTS:
%   value - Difference between floating leg and fixed leg.
%           The bootstrap solves value = 0 for PN.

    if nargin >= 8 && ~isempty(varargin{1})
        pre = varargin{1};
    else
        pre = [];
    end

    tmpDates = [knownDates; maturityDate];
    tmpDisc  = [knownDisc; PN];

    if numel(tmpDates) > 1 && tmpDates(end) < tmpDates(end-1)
        [tmpDates, tmpDisc] = sortCurve(tmpDates, tmpDisc);
    end

    floatingLeg = 0;
    if isempty(pre)
        floatDates = makeSchedule(settlementDate, maturityDate, 3, 'modifiedfollow');
        floatStart = floatDates(1:end-1);
        floatEnd = floatDates(2:end);
        floatDelta = yearfrac(floatStart, floatEnd, 2);
    else
        floatStart = pre.floatStart;
        floatEnd = pre.floatEnd;
        floatDelta = pre.floatDelta;
    end

    for j = 1:numel(floatEnd)
        Tstart = floatStart(j);
        Tend   = floatEnd(j);
        delta = floatDelta(j);
        Pstart = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tstart, tmpDates, tmpDisc);
        Pend   = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tend, tmpDates, tmpDisc);
        forward3M = (Pstart / Pend - 1) / delta;

        if isempty(pre)
            oisDiscEnd = get_discount_factor_by_zero_rates_linear_interp( ...
                oisCurve.settlementDate, Tend, oisCurve.dates, oisCurve.discounts);
        else
            oisDiscEnd = pre.oisFloatDisc(j);
        end
        floatingLeg = floatingLeg + delta * forward3M * oisDiscEnd;
    end

    fixedLeg = 0;
    if isempty(pre)
        fixedDates = makeSchedule(settlementDate, maturityDate, 12, 'modifiedfollow');
        fixedPrev = fixedDates(1:end-1);
        fixedEnd = fixedDates(2:end);
        fixedDelta = yearfrac(fixedPrev, fixedEnd, 6);
    else
        fixedDelta = pre.fixedDelta;
        fixedEnd = pre.fixedEnd;
    end

    for i = 1:numel(fixedEnd)
        delta = fixedDelta(i);
        Tend  = fixedEnd(i);
        if isempty(pre)
            oisDiscEnd = get_discount_factor_by_zero_rates_linear_interp( ...
                oisCurve.settlementDate, Tend, oisCurve.dates, oisCurve.discounts);
        else
            oisDiscEnd = pre.oisFixedDisc(i);
        end
        fixedLeg = fixedLeg + swapRate * delta * oisDiscEnd;
    end

    value = floatingLeg - fixedLeg;
end
