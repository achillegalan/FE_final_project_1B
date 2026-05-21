function zero_rates = from_discount_factors_to_zero_rates(dates, discount_factors)
% The function has the goal to transform the discount factors in zero
% rates:

%% INPUTS:
% dates:            vector of dates in which we have already available the 
%                   dfs
% discount_factors: vector of the available dfs

%% OUTPUTS:
% zero_rates:   vector of the zero rates
    
ref_date = dates(1);
    
% We calculate the year fractions with the ACT/360 convention:
effDates = yearfrac(ref_date, dates, 2); 
    
% We exclude the initial date:
effDates = effDates(2:end);
effDf = discount_factors(2:end);
    
% We apply the formula for the zero rates: -ln(DF) / t
zero_rates = -log(effDf) ./ effDates;
    
% We make sure that the output is a column vector:
zero_rates = zero_rates(:);
end