function [CVA, survProbs] = computeCVA( ...
     swapData, OIS_curve, EUR3M_curve, settlementDate, strike, normalVol, ...
     isPayer, fixingFrequency, cdsSpreads, LGD)
% COMPUTECVA Computes CVA for both inception (2022) and unwinding (2023).
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

% Extract full schedules
paymentDates = swapData.PayDate(:);
Notional     = swapData.Notional(:);

% Keep only future payment flows (Crucial for the Unwinding case)
check = paymentDates > settlementDate;
futurePayDates = paymentDates(check);
futurePayDates = futurePayDates(:);
futureNotional = Notional(check);
futureNotional = futureNotional(:);

% Bootstrapping the survival probabilities from CDS market data
% (Only evaluates future survival nodes)
survProbs = bootstrapSurvivalProbabilities(OIS_curve, futurePayDates, cdsSpreads, LGD);

% The CVA summation requires Q(t_{i-1}) - Q(t_i). We prepend Q(t_0) = 1.
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);

numPeriods = numel(futurePayDates);

% The formula specifies summation up to (b-1)
swaptionPrices = zeros(numPeriods - 1, 1);

for i = 1:(numPeriods - 1)
    exerciseDate = futurePayDates(i);
    
    % Pass ONLY the future schedule to the swaption pricer
    swaptionPrices(i) = bachelierPSSwaptionPricerCVA( ...
        OIS_curve, EUR3M_curve, futurePayDates, strike, normalVol, ...
        exerciseDate, futureNotional, isPayer, fixingFrequency);
end

% CVA calculation matching exactly the mathematical summation logic provided.
CVA = LGD * sum(CVAsurvProbs(1:end-1) .* swaptionPrices);

end