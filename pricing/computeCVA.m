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
%   knownFixing     - Optional struct with resetStartDate and resetRate.

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

% Bootstrapping the survival probabilities from CDS market data
survProbs = bootstrapSurvivalProbabilities(OIS_curve, futurePayDates, cdsSpreads, LGD);

% The CVA summation requires Q(t_{i-1}) - Q(t_i)
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);
numPeriods = numel(futurePayDates);

% =========================================================================
% 1. Evaluate Deterministic Cash Flows PV
% =========================================================================
detCF_PV = zeros(numPeriods, 1);
hasKnownFixing = (nargin >= 11 && ~isempty(knownFixing) && ~isnan(knownFixing.resetRate));

if hasKnownFixing
    deltaFracs = yearfrac(futureAccStart, futureAccEnd, 2); % ACT/360
    DFs = getTargetDF(settlementDate, OIS_curve.dates, OIS_curve.zeroRates, futurePayDates);
    
    rateDiff = knownFixing.resetRate - strike;
    if ~isPayer
        rateDiff = -rateDiff; % Receiver perspective
    end
    
    for k = 1:numPeriods
        % Raw Cash Flow PV (Can be negative)
        detCF_PV(k) = futureNotional(k) * deltaFracs(k) * rateDiff * DFs(k);
    end
end

% =========================================================================
% 2. Evaluate Stochastic Exposures (Standard Swaptions)
% =========================================================================
swaptionPrices = zeros(numPeriods - 1, 1);
for i = 1:(numPeriods - 1)
    exerciseDate = futurePayDates(i);
    swaptionPrices(i) = bachelierPSSwaptionPricerCVA( ...
        OIS_curve, EUR3M_curve, futurePayDates, strike, normalVol, ...
        exerciseDate, futureNotional, isPayer, fixingFrequency);
end

% =========================================================================
% 3. Merge EXPOSURES based on Reset Frequency
% =========================================================================
EPE_det   = zeros(numPeriods - 1, 1);
EPE_stoch = zeros(numPeriods - 1, 1);
EPE_total = zeros(numPeriods - 1, 1);

isSemiannual = strcmpi(strtrim(fixingFrequency), 'semiannual');

for i = 1:(numPeriods - 1)
    if hasKnownFixing
        if isSemiannual
            if i == 1
                % Bucket 1: Jan-Mar. Deterministic Exposure = max(CF1, 0)
                EPE_det(i)   = max(0, detCF_PV(1));
                EPE_stoch(i) = 0; % Swaption starting Jun
            elseif i == 2
                % Bucket 2: Mar-Jun. Deterministic Exposure = max(CF2, 0)
                EPE_det(i)   = max(0, detCF_PV(2));
                EPE_stoch(i) = 0;
            else
                % Bucket 3+: Fully stochastic
                EPE_det(i)   = 0;
                EPE_stoch(i) = swaptionPrices(i);
            end
        else
            % Quarterly case
            if i == 1
                % Bucket 1: Jan-Mar. Deterministic Exposure = max(CF1, 0)
                EPE_det(i)   = max(0, detCF_PV(1));
                EPE_stoch(i) = 0; % Swaption starting Mar
            else
                % Bucket 2+: Fully stochastic
                EPE_det(i)   = 0;
                EPE_stoch(i) = swaptionPrices(i);
            end
        end
    else
        % Standard Inception Case (No Known Fixing)
        EPE_det(i)   = 0;
        EPE_stoch(i) = swaptionPrices(i);
    end
    
    % Total Expected Positive Exposure is the sum of the divided exposures
    EPE_total(i) = EPE_det(i) + EPE_stoch(i);
end

% =========================================================================
% 4. Final CVA Calculation
% =========================================================================
probWeights = CVAsurvProbs(1:end-1);

CVA       = LGD * sum(probWeights .* EPE_total);

% Separated metrics for reporting
CVA_det   = LGD * sum(probWeights .* EPE_det);
CVA_stoch = LGD * sum(probWeights .* EPE_stoch);

end