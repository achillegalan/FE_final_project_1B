function [CVA, survProbs, CVA_det, CVA_stoch] = computeCVA_mix( ...
     swapData, OIS_curve, EUR3M_curve, settlementDate, strike, normalVol, ...
     isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing, Mode)
% COMPUTECVA_MIX Computes the CVA of an amortizing interest rate swap.
%
% This version maintains the function signature and structure but applies 
% the mathematically rigorous "fixing bleed" adjustment. It calculates an 
% adjusted forward swap rate and scales the Bachelier normal volatility 
% based on the ratio of stochastic BPV to total BPV, avoiding the invalid 
% max(V_det) + E[max(V_stoch)] split.
%
% INPUT
%   swapData          Table/struct containing the amortizing swap schedule.
%   OIS_curve         Struct containing the OIS discount curve.
%   EUR3M_curve       Struct containing the Euribor 3M pseudo-discount curve.
%   settlementDate    Valuation date.
%   strike            Fixed rate of the swap.
%   normalVol         Normal Bachelier volatility used for swaption pricing.
%   isPayer           true for payer exposure, false for receiver exposure.
%   fixingFrequency   Floating reset frequency: "quarterly" or "semiannual".
%   cdsSpreads        CDS spreads used to derive survival probabilities.
%   LGD               Loss Given Default.
%   knownFixing       Optional struct with already observed fixings.
%   Mode              Survival-probability method: "bootstrap" or "constant_lambda".
%
% OUTPUT
%   CVA               Total CVA value.
%   survProbs         Survival probabilities at future payment dates.
%   CVA_det           Set to 0 (Split methodology is mathematically invalid).
%   CVA_stoch         Set to total CVA.

if nargin < 11
    knownFixing = [];
end
if nargin < 12 || isempty(Mode)
    Mode = "bootstrap";
end
Mode = lower(string(strtrim(Mode)));

% Extract full schedules FIRST to avoid index offsets in semiannual mapping
fullNumPeriods = length(swapData.PayDate);
fullPayDates   = swapData.PayDate(:);
fullAccStart   = swapData.AccrualStart(:);
fullAccEnd     = swapData.AccrualEnd(:);
fullNotional   = swapData.Notional(:);

%% 0) Build reset periods correctly on the FULL schedule
fullCalcStart = fullAccStart;
fullCalcEnd   = fullAccEnd;
fixingFrequency = lower(string(strtrim(fixingFrequency)));

switch fixingFrequency
    case "quarterly"
        % Already mapped 1:1
    case "semiannual"
        % Semiannual reset: coupons (1,2), (3,4), ... share same 3M fixing
        pairStartIdx = 2 * ceil((1:fullNumPeriods)' / 2) - 1;
        fullCalcStart = fullAccStart(pairStartIdx);
        fullCalcEnd   = fullAccEnd(pairStartIdx);
    otherwise
        error('Unsupported fixingFrequency "%s". Use "quarterly" or "semiannual".', fixingFrequency);
end

fullFixingDates = add_target_business_days(fullCalcStart, -2);

% Keep only future payment flows
check = fullPayDates > settlementDate;
futurePayDates = fullPayDates(check);
futureAccStart = fullAccStart(check);
futureAccEnd   = fullAccEnd(check);
futureNotional = fullNotional(check);

calcStart   = fullCalcStart(check);
calcEnd     = fullCalcEnd(check);
fixingDates = fullFixingDates(check);
isFixedAtValuation = fixingDates <= settlementDate;

numPeriods = numel(futurePayDates);

% No future flows -> zero CVA
if numPeriods == 0
    survProbs = zeros(0,1);
    CVA = 0; CVA_det = 0; CVA_stoch = 0;
    return;
end

%% 1) Survival probabilities
switch Mode
    case "bootstrap"
        survProbs = bootstrapSurvivalProbabilities(OIS_curve, futurePayDates, cdsSpreads, LGD);
    case {"constant_lambda"}
        if LGD <= 0
            error('LGD must be > 0 for constant lambda mode.');
        end
        if isempty(cdsSpreads) || ~isfinite(cdsSpreads(1))
            error('cdsSpreads(1) must be finite for constant lambda mode.');
        end
        constant_lambda = cdsSpreads(1) / LGD;
        yearsFromSettle = yearfrac(settlementDate, futurePayDates, 2); % ACT/360
        survProbs = exp(-constant_lambda * yearsFromSettle);
    otherwise
        error('Unknown hazardMode "%s". Use "bootstrap" or "constant_lambda".', Mode);
end

survProbs = survProbs(:);
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);

%% 2) Pre-calculate the effective index rate (L) for every future period
L_effective = zeros(numPeriods, 1);
knownDates = NaT(0,1);
knownRates = [];

if isstruct(knownFixing) && isfield(knownFixing, 'fixingDate') && isfield(knownFixing, 'resetRate')
    knownDates = knownFixing.fixingDate(:);
    knownRates = knownFixing.resetRate(:);
end

for k = 1:numPeriods
    % Forward rate via pseudo-discount curve
    Pstart = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, calcStart(k));
    Pend   = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, calcEnd(k));
    deltaReset = yearfrac(calcStart(k), calcEnd(k), 2); % ACT/360
    L_effective(k) = (Pstart / Pend - 1) / deltaReset;
    
    % Override with known fixing if already fixed
    if isFixedAtValuation(k)
        idxKnown = find(knownDates == fixingDates(k), 1);
        if ~isempty(idxKnown) && ~isnan(knownRates(idxKnown))
            L_effective(k) = knownRates(idxKnown);
        end
    end
end

%% 3) Unified Stochastic exposures via Swaptions (Volatility Scaling)
EPE_total = zeros(max(numPeriods - 1, 0), 1);
deltaFracs = yearfrac(futureAccStart, futureAccEnd, 2); % ACT/360

for i = 1:(numPeriods - 1)
    exerciseDate = futurePayDates(i);
    TTM = yearfrac(settlementDate, exerciseDate, 3); % ACT/365
    
    if TTM <= 0
        continue;
    end
    
    optionDiscount = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
    
    remIdx = (i+1):numPeriods;
    if isempty(remIdx)
        continue;
    end
    
    remPayDates = futurePayDates(remIdx);
    remNotional = futureNotional(remIdx);
    remDelta    = deltaFracs(remIdx);
    remL        = L_effective(remIdx);
    remFixed    = isFixedAtValuation(remIdx);
    
    payDiscounts = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, remPayDates);
    fwdDiscounts = payDiscounts ./ optionDiscount;
    ammNotional  = remNotional ./ remNotional(1);
    
    % Combine BOTH deterministic and stochastic flows for Forward Rate
    BPV_total = sum(remDelta .* ammNotional .* fwdDiscounts);
    FloatNPV  = sum(remDelta .* ammNotional .* fwdDiscounts .* remL);
    
    if BPV_total <= 1e-12
        continue;
    end
    
    S_total = FloatNPV / BPV_total;
    
    % Calculate BPV of ONLY the stochastic tail
    stochMask = ~remFixed;
    BPV_stoch = sum(remDelta(stochMask) .* ammNotional(stochMask) .* fwdDiscounts(stochMask));
    
    if BPV_stoch <= 1e-8
        if isPayer
            unitPrice = max(S_total - strike, 0);
        else
            unitPrice = max(strike - S_total, 0);
        end
        EPE_total(i) = optionDiscount * BPV_total * unitPrice * remNotional(1);
        continue;
    end
    
    % Interp1 Bug Fix: Match vanillaBPV length to Tenors list exactly
    volsAtExpiry = interp1(normalVol.expiriesNum, normalVol.matrixDecimal, TTM, 'linear');
    tenorsList = normalVol.tenorsNum(:);
    numTenors = length(tenorsList);
    maxTenor = max(tenorsList);
    
    vanillaPaymentDates = NaT(maxTenor, 1);
    for y = 1:maxTenor
        vanillaPaymentDates(y) = add_target_months(exerciseDate, 12 * y, 'modifiedfollow');
    end
    
    vanillaAccrualStarts = [exerciseDate; vanillaPaymentDates(1:end-1)];
    vanillaYearFracs = yearfrac(vanillaAccrualStarts, vanillaPaymentDates, 2);
    vanillaPaymentDFs = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, vanillaPaymentDates);
    vanillaFwdDiscounts = vanillaPaymentDFs ./ optionDiscount;
    
    vanillaBPVs = zeros(1, numTenors);
    for j = 1:numTenors
        idx_t = tenorsList(j);
        vanillaBPVs(j) = sum(vanillaYearFracs(1:idx_t) .* vanillaFwdDiscounts(1:idx_t));
    end
    
    bpvMin = min(vanillaBPVs);
    bpvMax = max(vanillaBPVs);
    bpvQuery = min(max(BPV_stoch, bpvMin), bpvMax);
    
    interpolated_sigma = interp1(vanillaBPVs, volsAtExpiry, bpvQuery, 'linear');
    
    % Scale Volatility based on Stochastic variance proportion
    sigma_adj = interpolated_sigma * (BPV_stoch / BPV_total);
    
    stdDev = sigma_adj * sqrt(TTM);
    d = (S_total - strike) / stdDev;
    phi = exp(-0.5 * d^2) / sqrt(2*pi);
    Phi = 0.5 * erfc(-d / sqrt(2));
    
    if isPayer
        unitPrice = (S_total - strike) * Phi + stdDev * phi;
    else
        unitPrice = (strike - S_total) * (1 - Phi) + stdDev * phi;
    end
    
    EPE_total(i) = optionDiscount * BPV_total * unitPrice * remNotional(1);
end

%% 4) Deterministic/Stochastic split
% Because EPE[max(V)] cannot be split linearly without artificially
% inflating the risk exposure, the entire calculation is handled together.
EPE_det   = zeros(max(numPeriods - 1, 0), 1);
EPE_stoch = EPE_total;

%% 5) Final CVA
probWeights = CVAsurvProbs(1:end-1);
CVA       = LGD * sum(probWeights .* EPE_total);
CVA_det   = 0;
CVA_stoch = CVA;

end