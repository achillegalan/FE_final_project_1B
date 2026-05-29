function [CVA, survProbs, CVA_det, CVA_stoch] = computeCVA_mix( ...
     swapData, OIS_curve, EUR3M_curve, settlementDate, strike, normalVol, ...
     isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing, Mode)
% COMPUTECVA Unified CVA engine:
% - Mode = "bootstrap"        -> bootstrap survival probabilities
% - Mode = "constant_lambda"  -> flat hazard rate lambda = cdsSpreads(1)/LGD
%
% Backward compatible:
% - If hazardMode is omitted, defaults to "bootstrap".

if nargin < 11
    knownFixing = [];
end
if nargin < 12 || isempty(Mode)
    Mode = "bootstrap";
end
Mode = lower(string(strtrim(Mode)));

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

numPeriods = numel(futurePayDates);

% No future flows -> zero CVA
if numPeriods == 0
    survProbs = zeros(0,1);
    CVA = 0;
    CVA_det = 0;
    CVA_stoch = 0;
    return;
end

%% 1) Survival probabilities
switch Mode
    case "bootstrap"
        survProbs = bootstrapSurvivalProbabilities(OIS_curve, futurePayDates, cdsSpreads, LGD);

    case {"constantlambda","constant_lambda","flatlambda","flat_lambda"}
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

% The CVA summation requires Q(t_{i-1}) - Q(t_i)
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);

%% 2) Build reset periods and deterministic coupons for already-fixed buckets
detCF_PV = zeros(numPeriods, 1);

idx = (1:numPeriods).';
fixingFrequency = lower(string(strtrim(fixingFrequency)));

switch fixingFrequency
    case "quarterly"
        calcStart = futureAccStart;
        calcEnd   = futureAccEnd;

    case "semiannual"
        % Semiannual reset: coupons (1,2), (3,4), ... share same 3M fixing
        pairStartIdx = 2 * ceil(idx / 2) - 1;   % 1,1,3,3,...
        calcStart = futureAccStart(pairStartIdx);
        calcEnd   = futureAccEnd(pairStartIdx);

    otherwise
        error('Unsupported fixingFrequency "%s". Use "quarterly" or "semiannual".', fixingFrequency);
end

% fixing date = reset start - 2 TARGET business days
fixingDates = add_target_business_days(calcStart, -2);
isFixedAtValuation = fixingDates <= settlementDate;

% Optional known-fixing map (fixingDate + resetRate)
knownDates = NaT(0,1);
knownRates = [];
if isstruct(knownFixing) && ...
        isfield(knownFixing, 'fixingDate') && isfield(knownFixing, 'resetRate')
    knownDates = knownFixing.fixingDate(:);
    knownRates = knownFixing.resetRate(:);
end

deltaFracs = yearfrac(futureAccStart, futureAccEnd, 2); % ACT/360
DFs = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, futurePayDates);

for k = 1:numPeriods
    if ~isFixedAtValuation(k)
        continue; % not fixed yet: remains stochastic
    end

    idxKnown = find(knownDates == fixingDates(k), 1);
    if ~isempty(idxKnown) && ~isnan(knownRates(idxKnown))
        Lk = knownRates(idxKnown);
    else
        Pstart = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, calcStart(k));
        Pend   = getTargetDF(settlementDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, calcEnd(k));
        deltaReset = yearfrac(calcStart(k), calcEnd(k), 2); % ACT/360
        Lk = (Pstart / Pend - 1) / deltaReset;
    end

    if isPayer
        cf = futureNotional(k) * deltaFracs(k) * (Lk - strike);
    else
        cf = futureNotional(k) * deltaFracs(k) * (strike - Lk);
    end
    detCF_PV(k) = cf * DFs(k);
end

%% 3) Stochastic exposures via swaptions
swaptionPrices = zeros(max(numPeriods - 1, 0), 1);
for i = 1:(numPeriods - 1)
    if isFixedAtValuation(i)
        continue;
    end

    exerciseDate = futurePayDates(i);
    swaptionPrices(i) = bachelierPSSwaptionPricerCVA( ...
        OIS_curve, EUR3M_curve, futurePayDates, strike, normalVol, ...
        exerciseDate, futureNotional, isPayer, fixingFrequency);
end

%% 4) Deterministic/Stochastic split
EPE_det   = zeros(max(numPeriods - 1, 0), 1);
EPE_stoch = zeros(max(numPeriods - 1, 0), 1);

if numPeriods >= 2
    bucketFixedMask = isFixedAtValuation(1:end-1);
    detBuckets = detCF_PV(1:end-1);

    EPE_det(bucketFixedMask) = max(0, detBuckets(bucketFixedMask));
    EPE_stoch(~bucketFixedMask) = swaptionPrices(~bucketFixedMask);
end

EPE_total = EPE_det + EPE_stoch;
probWeights = CVAsurvProbs(1:end-1);

%% 5) Final CVA
CVA       = LGD * sum(probWeights .* EPE_total);
CVA_det   = LGD * sum(probWeights .* EPE_det);
CVA_stoch = LGD * sum(probWeights .* EPE_stoch);

end