function [CVA, survProbs] = computeCVAConstantLambda( ...
     OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, Notional, ...
     isPayer, fixingFrequency, cdsSpreads, LGD)
% COMPUTECVACONSTANTLAMBDA Computes CVA assuming a strictly constant hazard rate.
%
% INPUTS:
%   OIS_curve       - Struct containing settlementDate, dates, zeroRates.
%   EUR3M_curve     - Struct containing dates, zeroRates for forecasting.
%   paymentDates    - Full vector of quarterly swap payment schedules.
%   strike          - Fixed swap rate K.
%   normalVol       - Swaption normal volatility cube data structure.
%   Notional        - Array containing the amortizing notionals for each period.
%   isPayer         - Logical flag: true for Payer, false for Receiver.
%   fixingFrequency - String flag: 'quarterly' or 'semiannual'.
%   cdsSpreads      - Given CDS spread in decimal form (e.g., 300 bps = 0.03).
%   LGD             - Loss Given Default parameter (e.g., 40% = 0.40).

settleDate = OIS_curve.settlementDate;
paymentDates = paymentDates(:);

% 1. Compute direct survival probabilities using a continuous constant lambda
%    (Assumes the first element of cdsSpreads represents the flat curve target)
constant_lambda = cdsSpreads(1) / LGD; 
yearsFromSettle = yearfrac(settleDate, paymentDates, 2); % ACT/360 convention

% Q(0, T_i) calculated directly via exponential decay
survProbs = exp(-constant_lambda * yearsFromSettle);

% 2. Establish the default probability chunks: Q(t_{i-1}) - Q(t_i)
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);

% 3. Portfolio Exposure Summation Engine
numPeriods = numel(paymentDates);
swaptionPrices = zeros(numPeriods - 1, 1);

for i = 1:(numPeriods - 1)
    exerciseDate = paymentDates(i);
    swaptionPrices(i) = bachelierPSSwaptionPricerCVA( ...
        OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, ...
        exerciseDate, Notional, isPayer, fixingFrequency);
end

% Compute the final expected valuation adjustment
CVA = LGD * sum(CVAsurvProbs(1:end-1) .* swaptionPrices);

end