function [CVA, survProbs] = computeCVAConstantLambda( ...
     swapData, OIS_curve, EUR3M_curve, settlementDate, strike, normalVol, ...
     isPayer, fixingFrequency, cdsSpreads, LGD)
% COMPUTECVACONSTANTLAMBDA Computes CVA assuming a strictly constant hazard rate.
% Supports both trade inception (2022) and contractual unwinding (2023).
%
% INPUTS:
%   swapData        - Table/struct with PayDate, Notional, etc.
%   OIS_curve       - Struct containing settlementDate, dates, zeroRates.
%   EUR3M_curve     - Struct containing dates, zeroRates for forecasting.
%   settlementDate  - Valuation date (e.g., June 2022 or Jan 2023).
%   strike          - Fixed swap rate K.
%   normalVol       - Swaption normal volatility cube data structure.
%   isPayer         - Logical flag: true for Payer, false for Receiver.
%   fixingFrequency - String flag: 'quarterly' or 'semiannual'.
%   cdsSpreads      - Given CDS spread in decimal form (e.g., 300 bps = 0.03).
%   LGD             - Loss Given Default parameter (e.g., 40% = 0.40).

% Extract full schedules from the swapData structural block
paymentDates = swapData.PayDate(:);
Notional     = swapData.Notional(:);

% Keep only future payment flows relative to current valuation snapshot
check = paymentDates > settlementDate;

% CRITICAL DIMENSION MATCHING: Force strict vertical column vector layout
futurePayDates = paymentDates(check);
futurePayDates = futurePayDates(:);

futureNotional = Notional(check);
futureNotional = futureNotional(:);

% 1. Compute direct survival probabilities using a continuous constant lambda
%    relative to the evaluation date (settlementDate).
constant_lambda = cdsSpreads(1) / LGD; 
yearsFromSettle = yearfrac(settlementDate, futurePayDates, 2); % ACT/360 convention

% Q(t, T_i) calculated directly via exponential decay mapping
survProbs = exp(-constant_lambda * yearsFromSettle);
survProbs = survProbs(:);

% 2. Establish the default probability chunks: Q(t_{i-1}) - Q(t_i)
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);

% 3. Portfolio Exposure Summation Engine
numPeriods = numel(futurePayDates);
swaptionPrices = zeros(numPeriods - 1, 1);

for i = 1:(numPeriods - 1)
    exerciseDate = futurePayDates(i);
    
    % Pass ONLY the future schedule arrays to the underlying pricer module
    swaptionPrices(i) = bachelierPSSwaptionPricerCVA( ...
        OIS_curve, EUR3M_curve, futurePayDates, strike, normalVol, ...
        exerciseDate, futureNotional, isPayer, fixingFrequency);
end

% Compute the final credit valuation adjustment matching exact summation limits
CVA = LGD * sum(CVAsurvProbs(1:end-1) .* swaptionPrices);

end