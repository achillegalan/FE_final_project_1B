function [CVA, survProbs] = computeCVA( ...
     OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, Notional, ...
     isPayer, fixingFrequency, cdsSpreads, LGD)

% Bootstrapping the survival probabilities from CDS market data
survProbs = bootstrapSurvivalProbabilities(OIS_curve, paymentDates, cdsSpreads, LGD);

% The CVA summation requires Q(t_{i-1}) - Q(t_i). We prepend Q(t_0) = 1.
survProbsFull = [1; survProbs];
CVAsurvProbs = survProbsFull(1:end-1) - survProbsFull(2:end);

numPeriods = numel(paymentDates);
% The formula specifies summation up to (b-1), meaning the last swaption expires at t_{b-1}
swaptionPrices = zeros(numPeriods - 1, 1);

for i = 1:(numPeriods - 1)
    exerciseDate = paymentDates(i);
    swaptionPrices(i) = bachelierPSSwaptionPricerCVA( ...
        OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, ...
        exerciseDate, Notional, isPayer, fixingFrequency);
end

% CVA calculation matching exactly the mathematical summation logic provided.
CVA = LGD * sum(CVAsurvProbs(1:end-1) .* swaptionPrices);

end