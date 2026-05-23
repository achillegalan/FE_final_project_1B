function data = importExcellData(filename, sheetName, columns)
% IMPORTEXCELLDATA Generic importer for tabular Excel sheets.
%
% INPUTS:
%   filename       - Path to the .xlsx file.
%   sheetName      - Name of the sheet to read.
%   columns        - Cell array of column names to extract (must match headers).
%
% OUTPUT:
%   data - Scalar struct; each field is named after the cleaned column name
%          (spaces stripped, leading/trailing whitespace removed).
%
% EXAMPLES:
%   % Curve data (Market Rate is automatically converted from % to decimal)
%   curveData = importExcellData('curves.xlsx', 'EUR6M', ...
%       {'Term', 'Market Rate'});
%
%   % Swap amortizing plan (no scaling needed)
%   swapData = importExcellData('SwapAmortizingPlan_v1.xlsx', 'SwapPlan', ...
%       {'Pay Date', 'Accrual Start', 'Accrual End', 'Days', 'Notional'});

% --- Input validation ---
arguments
    filename  (1,:) char
    sheetName (1,:) char
    columns   (1,:) cell
end

% --- Read ---
dataTable = readtable(filename, ...
    'Sheet', sheetName, ...
    'VariableNamingRule', 'preserve');

% Validate requested columns exist
missing = setdiff(columns, dataTable.Properties.VariableNames);
if ~isempty(missing)
    error('importExcellData:missingColumns', ...
        'Column(s) not found in sheet "%s": %s', ...
        sheetName, strjoin(missing, ', '));
end

dataTable = dataTable(:, columns);

% --- Build output struct ---
data = struct();

for i = 1:numel(columns)
    col = columns{i};
    values = dataTable.(col);

    % Convert Market Rate from percentage points to decimals (e.g., 2.50 -> 0.025)
    normalizedCol = lower(regexprep(strtrim(col), '[\s_]+', ''));
    if isnumeric(values) && strcmp(normalizedCol, 'marketrate')
        values = values ./ 100;
    end

    % Warn on NaNs for numeric columns
    if isnumeric(values) && any(isnan(values))
        warning('importExcellData:NaNFound', ...
            'NaN values found in column "%s" of sheet "%s".', col, sheetName);
    end

    fieldName = matlab.lang.makeValidName(col);   % e.g. "Market Rate" -> "MarketRate"
    data.(fieldName) = values;
end

end
