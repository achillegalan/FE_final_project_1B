function value = swapObjectiveCrab(PN, settlementDate, maturityDate, swapRate, ...
                                   knownDates, knownDisc, swapCache)
% SWAPOBJECTIVECRAB Objective for swap bootstrap.
% INPUTS:
%   PN             - Candidate pseudo-discount factor at the swap maturity.
%   settlementDate - Datetime object representing the curve settlement date.
%   maturityDate   - Datetime object representing the swap maturity date.
%   swapRate       - Quoted fixed swap rate as a decimal.
%   knownDates     - Vector of datetime objects for known pseudo-curve nodes.
%   knownDisc      - Vector of known pseudo-discount factors.
%   oisInput       - Either:
%                    (A) structure with OIS discount curve fields:
%                        dates, discounts, settlementDate; or
%                    (B) precomputed swap cache with fields:
%                        floatStart, floatEnd, floatDelta,
%                        oisDiscFloatEnd, fixedLegConst.
%
% OUTPUTS:
%   value - Difference between floating leg and fixed leg.
%           The bootstrap solves value = 0 for PN.

    floatStart = swapCache.floatStart;
    floatEnd = swapCache.floatEnd;
    floatDelta = swapCache.floatDelta;
    oisDiscFloatEnd = swapCache.oisDiscFloatEnd;
    fixedLeg = swapCache.fixedLegConst;

    % Add to the known curve the possible discount factor
    tmpDates = [knownDates; maturityDate];
    tmpDisc  = [knownDisc; PN];

    %% Floating leg
    floatingLeg = 0;

    for j = 1:numel(floatEnd)
        Tstart = floatStart(j);
        Tend   = floatEnd(j);
        delta = floatDelta(j);
        Pstart = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tstart, tmpDates, tmpDisc);
        Pend   = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, Tend, tmpDates, tmpDisc);
        
        forward3M = (Pstart / Pend - 1) / delta;
        oisDiscEnd = oisDiscFloatEnd(j);

        floatingLeg = floatingLeg + delta * forward3M * oisDiscEnd;
    end

    %% total
    value = floatingLeg - fixedLeg;
end
