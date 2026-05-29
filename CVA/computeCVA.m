function [CVA, survProbs, CVA_det, CVA_stoch] = computeCVA( ...
     swapData, OIS_curve, EUR3M_curve, settlementDate, strike, normalVol, ...
     isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing)
% COMPUTECVA Computes CVA for both inception (2022) and unwinding (2023).
% Correctly divides deterministic and stochastic EXPOSURES to avoid fixing bleed.
%
% INPUTS:
%   swapData        - Table/struct with PayDate, AccrualStart, AccrualEnd, Notional.
%   OIS_curve       - Struct containing settlementDate, dates, zeroRates.
%   EUR3M_curve     - Struct containing dates, zeroRates for forecasting.
%   settlementDate  - Valuation date (e.g., June 2022 or Jan 2023).
%   strike          - Fixed swap rate K.
%   normalVol       - Swaption normal volatility cube data structure.
%   isPayer         - Logical flag: true for Payer, false for Receiver.
%   fixingFrequency - String flag: 'quarterly' or 'semiannual'.
%   cdsSpreads      - Given CDS spread in decimal form (e.g., 300 bps = 0.03).
%   LGD             - Loss Given Default parameter (e.g., 40% = 0.40).
%   knownFixing     - Struct with fixingRate and resetRate.

% Extract full schedules
paymentDates = swapData.PayDate(:);
accStart     = swapData.AccrualStart(:);
accEnd       = swapData.AccrualEnd(:);
Notional     = swapData.Notional(:);

% Keep only future payment flows
check = paymentDates > settlementDate;
futurePayDates = paymentDates(check);
futurePayDates = futurePayDates(:);
futureAccStart = accStart(check);
futureAccEnd   = accEnd(check);
futureNotional = Notional(check);
futureNotional = futureNotional(:);

%% Bootstrapping the survival probabilities from CDS market data
survProbs = bootstrapSurvivalProbabilities(OIS_curve, futurePayDates, cdsSpreads, LGD);

% The CVA summation requires Q(t_{i-1}) - Q(t_i)
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);
numPeriods = numel(futurePayDates);

%% 1) Build reset periods and fixing dates (2 TARGET business days before reset start)
detCF_PV = zeros(numPeriods, 1);

idx = (1:numPeriods).';
fixingFrequency = lower(string(strtrim(fixingFrequency)));

switch fixingFrequency
    case "quarterly"
        calcStart = futureAccStart;
        calcEnd   = futureAccEnd;
    case "semiannual"
        % Semiannual reset: coupons (1,2), (3,4), ... share the same 3M fixing
        pairStartIdx = 2 * ceil(idx / 2) - 1;   % 1,1,3,3,...
        calcStart = futureAccStart(pairStartIdx);
        calcEnd   = futureAccEnd(pairStartIdx);
end

fixingDates = add_target_business_days(calcStart, -2);
isFixedAtValuation = fixingDates <= settlementDate;

% Optional known-fixing map (strict format: fixingDate + resetRate)
knownDates = NaT(0,1);
knownRates = [];
if nargin >= 11 && ~isempty(knownFixing) ...
        && isfield(knownFixing, 'fixingDate') && isfield(knownFixing, 'resetRate')
    knownDates = knownFixing.fixingDate(:);
    knownRates = knownFixing.resetRate(:);
end

deltaFracs = yearfrac(futureAccStart, futureAccEnd, 2); % ACT/360 coupon accrual
DFs = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, futurePayDates);

for k = 1:numPeriods
    if ~isFixedAtValuation(k)
        continue; % Not fixed yet: this exposure remains stochastic
    end

    % Use known fixing if provided, otherwise fallback to pseudo-curve implied forward
    idxKnown = find(knownDates == fixingDates(k), 1);
    if ~isempty(idxKnown) && ~isnan(knownRates(idxKnown))
        Lk = knownRates(idxKnown);
    else
        Pstart = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, calcStart(k));
        Pend   = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, calcEnd(k));
        deltaReset = yearfrac(calcStart(k), calcEnd(k), 2); % ACT/360
        Lk = (Pstart / Pend - 1) / deltaReset;
    end

    % Deterministic coupon PV from bank perspective
    if isPayer
        cf = futureNotional(k) * deltaFracs(k) * (Lk - strike);
    else
        cf = futureNotional(k) * deltaFracs(k) * (strike - Lk);
    end
    detCF_PV(k) = cf * DFs(k);
end

% =========================================================================
% 2) Stochastic exposures via swaptions
% =========================================================================
swaptionPrices = zeros(numPeriods - 1, 1);
for i = 1:(numPeriods - 1)
    exerciseDate = futurePayDates(i);
    swaptionPrices(i) = bachelierPSSwaptionPricerCVA( ...
        OIS_curve, EUR3M_curve, futurePayDates, strike, normalVol, ...
        exerciseDate, futureNotional, isPayer, fixingFrequency);
end

% =========================================================================
% 3) Deterministic/Stochastic split driven by fixing state (no hardcoding)
% =========================================================================
EPE_det   = zeros(numPeriods - 1, 1);
EPE_stoch = zeros(numPeriods - 1, 1);

bucketFixedMask = isFixedAtValuation(1:end-1);
detBuckets = detCF_PV(1:end-1);

EPE_det(bucketFixedMask) = max(0, detBuckets(bucketFixedMask));
EPE_stoch(~bucketFixedMask) = swaptionPrices(~bucketFixedMask);

EPE_total = EPE_det + EPE_stoch;

% =========================================================================
% 4. Final CVA Calculation
% =========================================================================
probWeights = CVAsurvProbs(1:end-1);

CVA       = LGD * sum(probWeights .* EPE_total);

% Separated metrics for reporting
CVA_det   = LGD * sum(probWeights .* EPE_det);
CVA_stoch = LGD * sum(probWeights .* EPE_stoch);

end
