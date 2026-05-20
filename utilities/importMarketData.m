function curveData = importMarketData(filename, sheetName)
% IMPORTCURVEDATA Imports specific interest rate curve data from a CSV file.
%
% INPUTS:
%   filename  - String or char array specifying the path to the CSV file.
%
% OUTPUTS:
%   curveData - A scalar structure containing the vectorized columns:
%               Term, MarketRate, ZeroRate, and Discount.

dataTable = readtable(filename, 'Sheet', sheetName, 'VariableNamingRule', 'preserve');

% Select only the columns of interest
dataTable = dataTable(:, {'Term', 'Market Rate', 'Zero Rate', 'Discount'});

curveData.Term       = dataTable.Term;
curveData.MarketRate = dataTable.("Market Rate")/100; % percentage => decimal
curveData.ZeroRate   = dataTable.("Zero Rate")/100; % percentage => decimal
curveData.Discount   = dataTable.Discount;

%///Warn if any NaNs were imported
if any(isnan(curveData.Discount))
    warning('importCurveData:NaNFound', 'Missing discount factors detected in %s.', filename);
end

end